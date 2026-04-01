# Problem 01: FPGA Debug Scenario — Silent AXI4 Deadlock

## Problem Statement

You are a hardware engineer at a networking company. Your team has just completed bring-up of a
new FPGA-based packet processing board. The design comprises:

- A Zynq UltraScale+ MPSoC running Linux on the PS (ARM Cortex-A53).
- A PL design containing a custom AXI4-MM packet DMA engine connected to 4 GB of DDR4 via MIG.
- A 100G Ethernet MAC (CMAC) whose RX path writes received packets via the DMA engine to DDR4.
- The PS reads packet data from DDR4 via a 128-bit AXI4 interconnect.

**Observed symptom:**

The system appears to start correctly. DDR4 calibration passes. CMAC links train at 100G.
The PS boots Linux and the driver initialises the DMA engine via PCIe BAR register writes.
For the first 30–90 seconds, packet reception works correctly. Then traffic stops. No more
packet data appears in the kernel driver. The DMA engine's `rx_pkt_count` status register
(readable over PCIe) stops incrementing and stays frozen.

Rebooting the FPGA (reload bitstream) clears the issue temporarily — it always returns within
30–90 seconds of traffic.

**You have the following tools available:**

- Vivado Hardware Manager with ILA (already inserted on key AXI4 buses and the DMA state machine)
- VIO connected to DMA reset, enable, and status signals
- JTAG connected via Xilinx platform cable
- Oscilloscope
- Linux terminal on the PS (SSH access)

**Your task is to systematically diagnose the root cause. This problem has a realistic root
cause — work through each stage of reasoning.**

---

## Stage 1 — Characterise the Failure

**Before touching the ILA, what initial information would you gather?**

### Approach

**1. Reproduce reliably.**

The failure occurs in 30–90 seconds. Confirm this is deterministic by rebooting five times and
noting:
- Does it always fail? (Yes — rules out a flaky connection or one-off event.)
- Is the timing consistent or variable? (Variable 30–90s suggests a data-dependent or
  load-dependent trigger, not a simple timer or counter overflow at a fixed value.)

**2. Characterise the traffic dependency.**

Test with different packet rates:
- At 1% line rate: does failure occur? At what time?
- At 50% line rate: faster failure?
- At 100% line rate: fastest failure?

If failure time is inversely proportional to packet rate, a counter or FIFO fill condition is
the likely trigger. If failure time is consistent regardless of rate, a state machine bug or
timeout issue is more likely.

**3. Inspect the DMA status registers from the PS.**

```bash
# Read DMA status registers over PCIe via mmap
devmem 0xA0000000 32   # DMA control register
devmem 0xA0000004 32   # DMA status register
devmem 0xA0000008 32   # RX packet count
devmem 0xA000000C 32   # RX write pointer
devmem 0xA0000010 32   # RX read pointer (updated by PS driver)
```

**Key question:** when frozen, is the write pointer stuck at the same value? Is the read pointer
less than the write pointer (suggesting the PS is not consuming fast enough), or has it caught
up and passed the write pointer (suggesting an overrun)?

**4. Check for AXI4 error responses.**

If the AXI interconnect logged any SLVERR or DECERR responses, these would cause the DMA
engine to halt and flag an error. Check the DMA status register for an error flag bit.

---

## Stage 2 — Instrument with ILA

**The DMA engine has a state machine. An ILA is pre-inserted on the AXI4-MM write channel
(AW, W, B channels) and on the DMA state machine register. How do you configure the ILA
trigger to capture the failure moment?**

### ILA Configuration

**Probes available:**

```
probe0[1:0]   = dma_state       (DMA FSM: IDLE=0, FETCH=1, WRITE=2, WAIT_BRESP=3)
probe1[0]     = axi_awvalid
probe2[0]     = axi_awready
probe3[0]     = axi_wvalid
probe4[0]     = axi_wready
probe5[0]     = axi_wlast
probe6[1:0]   = axi_bresp       (OKAY=00, EXOKAY=01, SLVERR=10, DECERR=11)
probe7[0]     = axi_bvalid
probe8[0]     = axi_bready
probe9[7:0]   = axi_awlen       (burst length - 1)
probe10[31:0] = axi_awaddr[31:0]
probe11[0]    = rx_pkt_count_freeze  (synthetic: pkt_count unchanging for >10K cycles)
```

**Trigger strategy:**

The state machine freezing suggests the DMA is stuck in one state. Configure a state-based
trigger:

```
State 0: dma_state transitions to WAIT_BRESP (i.e., detect WAIT_BRESP asserted)
         → go to State 1
State 1: dma_state == WAIT_BRESP for 10,000 consecutive cycles
         → TRIGGER
```

This fires when the state machine is stuck waiting for a write response for more than 10,000
cycles (40 µs at 250 MHz), which is far longer than any valid AXI4 write latency.

**Capture position:** 90% post-trigger (trigger near the beginning of the window). We want to
capture what happens during and after the hang, not the lead-up.

**Leave ILA running in continuous mode.** The failure occurs 30–90 seconds in — the ILA will
re-arm automatically after each non-triggering capture and eventually catch the hang.

---

## Stage 3 — Analyse the Captured Waveform

**After 45 seconds of running, the ILA triggers. The captured waveform shows:**

```
Time    dma_state   awvalid  awready  wvalid  wready  wlast  bvalid  bready  bresp
T+0     WAIT_BRESP  0        0        0       0       0      0       1       00
T+1     WAIT_BRESP  0        0        0       0       0      0       1       00
T+2     WAIT_BRESP  0        0        0       0       0      0       1       00
...
T+9999  WAIT_BRESP  0        0        0       0       0      0       1       00
```

`bvalid` is 0 and `bready` is 1 throughout the capture. The DMA is correctly asserting
`bready` (it is ready to accept a write response), but the interconnect or DDR MIG is never
asserting `bvalid`.

**What does this tell you?**

### Analysis

The DMA engine completed a write burst (it finished the W-channel data, asserted `wlast`) and
entered `WAIT_BRESP` state. It is correctly asserting `bready` to accept the B-channel response.
However, the upstream AXI4 slave (the DDR4 MIG or a downstream interconnect) never asserts
`bvalid`. The write response is permanently withheld.

This is an **AXI4 B-channel stall** — the interconnect accepted the write data but will never
complete the handshake.

**Possible causes:**

1. The write data was accepted by an AXI4 interconnect buffer, but the interconnect forwarded
   it to a slave that returned an error response — and the error was lost or mishandled.

2. The interconnect has an outstanding transaction counter that overflowed. AXI4 interconnects
   limit the number of outstanding write transactions (defined by `AWID` depth). If the DMA
   issued more write transactions than the interconnect's write-response FIFO can hold, and
   the interconnect dropped a B-channel response, the DMA will wait forever.

3. The DDR MIG controller has an internal deadlock — it accepted the write command but its
   response path is stalled.

---

## Stage 4 — Narrow the Root Cause

**To distinguish between these causes, what do you check next?**

### Investigation

**Check 1 — AWID values and outstanding transaction count.**

Look at earlier captures (before the trigger fired). Count how many `AWVALID`/`AWREADY`
handshakes occurred without a corresponding `BVALID`/`BREADY` handshake in between.

If this count equals the interconnect's maximum outstanding write transaction depth (a design
parameter, typically 8 or 16 for AXI4 SmartConnect), then the DMA is exhausting the
outstanding transaction budget and the interconnect is not accepting new writes until it
issues all pending B-channel responses. But if it already dropped one B-channel response,
the count never decrements — deadlock.

**Check 2 — Look at the MIG status via ILA.**

A second ILA is pre-inserted on the MIG DDR4 UI port. Check:
- `app_rdy` — is the MIG accepting new commands?
- `app_wdf_rdy` — is the write data FIFO accepting data?
- `app_en` / `app_cmd` — is the DMA still issuing commands to the MIG?

If `app_rdy` is low and has been low for thousands of cycles, the MIG itself is stalled.

**Check 3 — Check XADC / System Monitor junction temperature.**

Intermittent stalls that occur after 30–90 seconds of operation sometimes have a thermal
cause. Read the junction temperature:

```bash
# On Zynq PS Linux:
cat /sys/class/hwmon/hwmon0/temp1_input
```

If junction temperature is climbing to the thermal throttle point, some IP cores enter a
protection mode. However, this would also cause other observable symptoms (reduced performance,
Linux warnings). This is a lower-probability cause given the clean waveform.

---

## Stage 5 — Root Cause Identification

**After checking the MIG status ILA, you find that `app_rdy` has been low for the entire
captured window. The MIG is not accepting new write commands. Why might the MIG's `app_rdy`
go low permanently?**

### Root Cause

The MIG `app_rdy` signal goes low when the MIG's internal command FIFO is full. The FIFO
fills when write commands are issued faster than the DDR4 SDRAM can complete them.

Normally this is temporary — the DRAM services the commands and the FIFO drains. But the FIFO
becomes permanently full when **there is a circular dependency**:

- The DMA's AXI4 port accepted write data but is waiting for B-channel responses before
  issuing more writes.
- The MIG command FIFO is full because it contains write commands whose data is in the write
  data FIFO, waiting to be committed to DRAM.
- The MIG's write data FIFO is full because the AXI4 interconnect has not dequeued the write
  data — it is waiting for the DMA to complete the burst with `wlast`.
- But the DMA already sent `wlast` — except the interconnect's internal buffer has wrapped
  around and the `wlast` marker was overwritten.

**The actual root cause: AXI4 write interleaving / ID mismatch bug.**

Review the DMA engine RTL. The DMA issues write transactions with incrementing `AWID` values
(0x0, 0x1, 0x2, ..., 0xF, then wraps to 0x0). The AXI4 interconnect must issue B-channel
responses in-order for the same `AWID`, but out-of-order responses for different `AWID` values
are permitted.

The bug: the DMA wraps `AWID` from 0xF back to 0x0 before all responses for `AWID=0x0` are
received. The interconnect sees a new `AWID=0x0` write while a previous `AWID=0x0` write is
still outstanding. This violates the AXI4 rule that **the same ID value must not be reused
until the previous transaction with that ID is complete**. Some interconnect implementations
handle this gracefully; others deadlock.

---

## Stage 6 — Fix and Verify

### Fix

**Option A — Increase `AWID` space (short-term fix):**

Change the DMA's `AWID` counter from 4 bits (16 IDs) to 8 bits (256 IDs). Given that the
maximum outstanding transactions in the system is 16 (determined by the MIG command FIFO
depth), 256 unique IDs guarantees no reuse before all responses are received.

**Option B — Limit outstanding transactions to unique ID count (correct fix):**

Add a tracking counter in the DMA that counts outstanding write transactions (increments on
`AWVALID`/`AWREADY`, decrements on `BVALID`/`BREADY`). Stall new `AWVALID` assertions when
the count reaches the number of available unique IDs minus one. This is an AXI4-compliant
throttle mechanism.

**Verification using ILA:**

After applying Option B:

1. Re-run the ILA with the same trigger configuration (wait for WAIT_BRESP for >10,000 cycles).
2. Run traffic for 10 minutes at 100% line rate.
3. Confirm the ILA never triggers.
4. Confirm `rx_pkt_count` increments continuously throughout the test.
5. Add a probe for the new outstanding-transaction counter; verify it never exceeds the safe
   limit and always decrements when B-channel responses arrive.

### Lessons

1. **AXI4 ID reuse is a subtle but dangerous bug.** It is not flagged by most simulation
   testbenches unless they use a protocol checker that explicitly validates the out-of-order
   ID rule.

2. **Intermittent deadlocks that clear on reset and worsen under load** almost always involve
   FIFO exhaustion or ID/transaction accounting bugs. Look for counters that increment and
   decrement, and ask whether decrement ever fails to fire.

3. **The ILA trigger duration condition is essential for finding hangs.** A level trigger on
   a stalled signal fires immediately on the first cycle it is asserted, giving you no context.
   A sequential trigger that waits for an abnormally long duration confirms the hang before
   capturing.

4. **Use VIO to inject controlled test cases.** After identifying the ID reuse condition,
   use a VIO to force the DMA to issue exactly 16 write transactions in burst before waiting
   for responses — this reliably reproduces the bug in seconds rather than waiting 30–90
   seconds for natural traffic to trigger it.
