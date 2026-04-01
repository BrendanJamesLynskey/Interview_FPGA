# Problem 03: ILA Trigger Design for Protocol Violation Detection

## Problem Statement

You are debugging an intermittent failure in a custom AXI4-Stream (AXIS) based packet processing
pipeline running on a Kintex UltraScale+ FPGA at 300 MHz. The pipeline receives Ethernet frames
from a 100G MAC, processes them through a 4-stage custom parser, and forwards them to a DMA
engine that writes to DDR4.

**Observed symptom:**

Approximately once every 2–5 minutes of traffic, the DMA engine reports a "packet length
mismatch" error — the number of bytes written to DDR4 does not match the packet length
indicated by the first 16 bits of the frame (the length field in a proprietary header).

The pipeline is complex and simulation has not reproduced the bug. You need to use the on-chip
ILA to capture the exact transaction that causes the length mismatch.

**AXI4-Stream interface at the DMA input:**

```
tvalid  : 1 bit  — data valid
tready  : 1 bit  — downstream ready to accept
tdata   : 512 bits — packet data, 64 bytes per beat
tkeep   : 64 bits  — byte enables (which bytes in tdata are valid)
tlast   : 1 bit  — last beat of packet
tuser   : 16 bits — packet metadata, tuser[15:0] = declared_length (in bytes)
tid     : 8 bits  — stream ID (packet flow identifier)
```

**Protocol rules that must hold:**

1. Once `tvalid` is asserted for a beat, it must stay asserted until `tready` is also asserted
   (no `tvalid` withdrawal mid-transaction, known as the "sticky valid" rule).
2. `tlast` must be asserted exactly on the last beat of each packet.
3. The number of valid bytes in the final beat (indicated by the popcount of `tkeep` on the
   `tlast` beat) plus bytes in all previous beats must equal `tuser[15:0]`.
4. `tuser` must be stable from the first beat of the packet to `tlast`.

Your task is to design ILA trigger configurations to catch each of these four violation types.

---

## Background: ILA Resources Available

The design has one ILA core already inserted at the DMA input port with the following probes:

```
probe0[0]    = tvalid
probe1[0]    = tready
probe2[511:0]= tdata          (NOTE: this probe is wide — 512 bits)
probe3[63:0] = tkeep
probe4[0]    = tlast
probe5[15:0] = tuser          (declared_length field)
probe6[7:0]  = tid
probe7[15:0] = byte_count_reg (internal counter in parser: running byte count for current packet)
probe8[0]    = packet_active  (internal flag: set on first valid beat, cleared on tlast+tready)
```

ILA configuration:
- Capture depth: 4096 samples
- Clock: 300 MHz design clock (3.33 ns per sample)
- Trigger position: configurable (set per-violation as described below)

**Note on probe width and resources:** probe2 is 512 bits wide. This alone consumes
512 × 4096 / 36864 ≈ 56.9 → **57 BRAMs** just for the data probe. If BRAM is constrained,
reduce capture depth to 1024 (14 BRAMs for probe2) and increase it only when needed.

---

## Trigger Design 1 — Sticky Valid Violation

### The Rule

Once `tvalid` is asserted, it must remain asserted until `tready` is also asserted. Withdrawing
`tvalid` before `tready` is an AXI4-S protocol violation.

### Violation Signature

`tvalid` transitions from 1 to 0 while `tready` is 0. In other words: `tvalid` was high on
cycle N, then `tvalid` is low on cycle N+1, and `tready` was low on cycle N (so the handshake
did not complete).

### ILA Trigger Configuration

Use a **state-based (sequential) trigger** because the violation requires observing two
consecutive cycles.

```
State 0: CONDITION = (tvalid == 1) AND (tready == 0)
         → This cycle, the valid is asserted but the handshake has not completed.
         → Transition to State 1

State 1: CONDITION = (tvalid == 0)
         → On the very next (or any subsequent cycle before tready), tvalid dropped.
         → TRIGGER

Else (in State 1, tready == 1 before tvalid drops):
         → Handshake completed cleanly; return to State 0.
```

**Vivado Trigger Language Expression:**

```
State 0:
  Condition: (PROBE0 == 1'b1) AND (PROBE1 == 1'b0)   -- tvalid=1, tready=0
  Transition: → State 1

State 1:
  Condition: (PROBE0 == 1'b0)                          -- tvalid dropped
  Action: TRIGGER

  Else condition: (PROBE1 == 1'b1)                     -- tready went high (clean handshake)
  Action: → State 0
```

**Capture position:** 90% pre-trigger (trigger at sample ~3690 of 4096). Set post-trigger
to show what happens after the violation — does the pipeline stall, reset, or continue with
corrupted state?

**Expected false-trigger rate:** this trigger should be zero-rate on correct traffic. If it
fires frequently, the source is genuinely violating the protocol and the violation is the
root cause of the observed errors.

---

## Trigger Design 2 — Incorrect `tlast` Position

### The Rule

`tlast` must be asserted exactly on the last beat of each packet. Given that:
- Each beat carries up to 64 bytes (`tkeep` indicates which are valid).
- The declared length is `tuser[15:0]` bytes.

`tlast` should be asserted when `byte_count_reg + popcount(tkeep)` equals `tuser[15:0]`.

### Violation Signatures

Two variants:

**Type A — Early `tlast`:** `tlast` is asserted before the byte count reaches `tuser[15:0]`.

**Type B — Late `tlast`:** the byte count reaches or exceeds `tuser[15:0]` but `tlast` is not
asserted (pipeline sends extra beats into the next logical packet).

### Trigger for Type A (early `tlast`)

Condition: `tlast == 1` AND `tvalid == 1` AND `tready == 1` (completed handshake on tlast
beat) AND `byte_count_reg + popcount(tkeep) < tuser[15:0]`.

**Limitation:** the ILA comparator does not natively compute `popcount(tkeep)` or arithmetic
on probe values. To work around this, modify the design to add a pre-computed signal:

```vhdl
-- Pre-compute: expected_last flag — asserted when current beat will complete the packet
process(all)
    variable v_keep_count : unsigned(6 downto 0);
begin
    v_keep_count := (others => '0');
    for i in 0 to 63 loop
        if tkeep(i) = '1' then
            v_keep_count := v_keep_count + 1;
        end if;
    end loop;
    expected_last <= '1' when (byte_count_reg + v_keep_count = unsigned(tuser))
                          else '0';
end process;
```

Add `expected_last` as a probe (probe9). Now the trigger is:

```
Basic trigger:
  (PROBE4 == 1'b1) AND (PROBE0 == 1'b1) AND (PROBE1 == 1'b1)   -- tlast with handshake
  AND (PROBE9 == 1'b0)                                           -- but NOT expected last beat
```

**This is a single-condition basic trigger** — no state machine needed. The violation
is detectable in a single cycle.

**Capture position:** centre trigger (trigger at sample 2048). Show both what led to the
premature `tlast` and what the pipeline does immediately after.

### Trigger for Type B (missing `tlast` at expected end)

This is harder — the violation is the *absence* of `tlast` at the expected moment.

**State-based trigger:**

```
State 0: Wait for expected_last == 1 (i.e., this beat should be the last)
         AND tvalid == 1 AND tready == 1  (handshake completing)
         → Transition to State 1

State 1: Check on the same cycle whether tlast == 0
         Condition: (tlast == 0)
         Action: TRIGGER   -- expected last beat but tlast not asserted

         Else (tlast == 1): clean completion → return to State 0
```

**Note:** States 0 and 1 evaluate on the same cycle in the Vivado trigger state machine. This
is a "check at State 0 entry" pattern — the condition for State 1 is evaluated immediately
upon the State 0 condition being true.

---

## Trigger Design 3 — `tuser` Instability Mid-Packet

### The Rule

`tuser` (the declared length field) must be stable from the first beat of a packet through
`tlast`. A change in `tuser` mid-packet is a protocol violation.

### Violation Signature

Between the assertion of `packet_active` (first beat) and `tlast`, `tuser` changes value.

### Trigger Configuration

This requires a **sequential trigger that remembers the initial `tuser` value and compares
subsequent beats against it**.

The ILA's basic comparator can only compare probes against *constants* set at configuration
time — it cannot compare a probe against a previously-captured value of the same probe. This
is a fundamental ILA limitation.

**Workaround: add a stability-check register in the design.**

```vhdl
-- Register tuser on first beat; compare on subsequent beats
process(clk)
begin
    if rising_edge(clk) then
        if packet_active = '0' and tvalid = '1' and tready = '1' then
            -- First beat: capture tuser
            tuser_snapshot <= tuser;
            tuser_changed <= '0';
        elsif packet_active = '1' then
            if tuser /= tuser_snapshot then
                tuser_changed <= '1';  -- violation flag
            end if;
        else
            tuser_changed <= '0';
        end if;
    end if;
end process;
```

Add `tuser_changed` as probe10. Now use a simple basic trigger:

```
Basic trigger:
  (PROBE10 == 1'b1)   -- tuser changed mid-packet
```

**Capture position:** 80% pre-trigger. The tuser change happened *at* the trigger; you want
to see the several beats leading up to it (showing the stable value), then the change, and
a few beats after.

---

## Trigger Design 4 — Compound Violation Detection

### Scenario

You want to find the specific transaction that causes the DMA length mismatch error. The DMA
engine sets an internal flag `dma_length_error` when it detects a discrepancy between the
number of bytes written and `tuser`. This flag is added as probe11.

However, the DMA error flag is set cycles *after* the violating packet completes. You want to
capture the packet that caused the error, not just the error itself.

### Advanced State-Based Trigger

```
State 0: Normal — wait for a packet to start.
         Condition: (packet_active == 1) AND (tvalid == 1) AND (tready == 1)
         Action: → State 1

State 1: Packet in progress — continue accumulating data.
         Condition: (tlast == 1) AND (tvalid == 1) AND (tready == 1)
         Action: → State 2  (packet just ended)

         Else (packet still in progress):
         → Stay in State 1

State 2: Packet ended — wait up to N cycles for DMA error flag.
         Condition: (dma_length_error == 1)
         Action: TRIGGER

         Else (N cycles without error):
         → Return to State 0 (no error, this packet was clean)
```

**The key insight:** the TRIGGER fires when the DMA error occurs *after* a packet completes.
By setting the capture position to 85% pre-trigger (trigger at approximately sample 3480 of
4096), you capture most of the packet that just finished — even though the trigger fires some
cycles after the packet ended.

**Calculating the required N:**

The DMA engine takes approximately 50–200 cycles to report an error after the last byte is
written. Set State 2's loop count to 256 cycles. If no error occurs within 256 cycles of a
packet ending, reset to State 0.

**Capture depth consideration:**

At 300 MHz, 4096 samples = 13.65 µs. A 1500-byte frame at 64 bytes/beat = 24 beats = 24
cycles for data + overhead. A 9000-byte jumbo frame = 141 beats. The 4096-sample depth
comfortably captures a full jumbo frame plus surrounding traffic.

---

## Putting It All Together: Trigger Priority Strategy

When debugging which violation type is actually occurring, run the ILA with each trigger
separately:

```
Phase 1: Enable Trigger 1 (sticky valid). Run for 5 minutes.
         - If it fires: the upstream MAC or parser is violating tvalid rules.
           Separate issue from the length error.
         - If it does not fire: upstream tvalid discipline is correct. Proceed.

Phase 2: Enable Trigger 4 (compound DMA error capture). Run for 5 minutes.
         - This captures the actual violating packet.
         - Inspect the captured waveform: check tuser value vs actual byte count.

Phase 3: Based on the captured packet:
         - If tuser was correct but tlast came too early → use Trigger 2 Type A.
         - If tuser was correct but tlast came too late → use Trigger 2 Type B.
         - If tuser changed mid-packet → use Trigger 3.

Phase 4: Once the violation type is identified, use the corresponding specific trigger
         to gather multiple captures and confirm the pattern is consistent.
```

---

## Sample Waveform Interpretation

After running Trigger 4 and capturing a violation, the waveform might look like:

```
Cycle  tvalid  tready  tlast  tuser   byte_count_reg  tkeep (popcount)
  0      1       1       0    0x05DC    0x0000          64 (0x40)
  1      1       1       0    0x05DC    0x0040          64
  2      1       1       0    0x05DC    0x0080          64
...
 22      1       1       0    0x05DC    0x05C0          28  (0x1C)
 23      1       1       1    0x05DC    0x05DC          -- (tlast here)
 24      0       -       0    0x0000    0x0000          (packet_active clears)
```

In this example `tuser = 0x05DC = 1500`. At cycle 22, byte_count_reg = 0x05C0 = 1472.
`tkeep` popcount = 28. 1472 + 28 = 1500. `expected_last` should be 1, and `tlast` should
fire. Waveform confirms `tlast` fires at cycle 23 with correct count.

**A violation might look like:**

```
Cycle  tvalid  tready  tlast  tuser   byte_count_reg  tkeep (popcount)
...
 22      1       1       0    0x05DC    0x05C0          28    <- expected_last=1, tlast=0 (BUG)
 23      1       1       1    0x05DC    0x05FC          28    <- tlast one beat late: 28 extra bytes
```

This is a Type B violation — `tlast` is one beat late, adding 28 spurious bytes to the packet,
causing the DMA to write 1528 bytes instead of 1500. The DMA's length mismatch error fires
~100 cycles later when it computes the discrepancy.

**Root cause hypothesis from this waveform:** the `expected_last` computation in the parser
has an off-by-one error — it fires one beat after the byte count crosses the threshold rather
than on the beat where the count is reached. Fix: change the comparison from `>` to `>=`, or
review the byte counter increment/compare timing.

---

## Key ILA Trigger Design Principles Demonstrated

| Principle                          | Application in this problem                                      |
|------------------------------------|------------------------------------------------------------------|
| Add synthetic probes for complex conditions | `expected_last`, `tuser_changed`, `dma_length_error` make non-computable conditions triggerable |
| Match trigger type to violation structure | Single-cycle violations → basic; multi-cycle sequences → state-based |
| Set trigger position based on what you need to see | Violation at trigger: use pre-trigger; consequence after trigger: use post-trigger |
| Use compound triggers to link distant events | DMA error fires later than the violating packet — state machine bridges the gap |
| Verify trigger correctness with VIO injection | Before waiting for a real error, inject a forced violation via VIO to confirm the trigger fires |
