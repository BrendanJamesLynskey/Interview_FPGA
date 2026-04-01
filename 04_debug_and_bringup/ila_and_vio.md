# ILA and VIO

## Overview

Vivado's Integrated Logic Analyser (ILA), Virtual Input/Output (VIO), and IBERT cores are the
primary on-chip debug mechanisms for Xilinx/AMD FPGAs. Unlike external logic analysers, these
cores are inserted into the synthesised netlist and communicate over the JTAG Debug Access Port,
allowing signal capture and stimulus injection without dedicated debug pins. Understanding how to
configure, insert, trigger, and interpret these cores is a core competency for any FPGA engineer
doing hardware bring-up or functional debug.

---

## Fundamentals

### Question 1

**What is an ILA core and how does it work at a high level? How does it differ from an external
logic analyser?**

**Answer:**

An ILA (Integrated Logic Analyser) is a debug IP core synthesised into the FPGA fabric alongside
the user design. It contains:

1. **Probe inputs** — nets tapped from the user design and fed into the ILA.
2. **Capture memory** — on-chip block RAM storing samples of those nets.
3. **Trigger engine** — configurable comparators that decide when to start or stop recording.
4. **JTAG interface** — communicates with Vivado Hardware Manager over the existing JTAG chain.

The core operates at the user design clock frequency. When a programmed trigger condition is met,
it records a window of samples (the capture depth) into BRAM and then halts, making the data
readable via JTAG.

| Property             | ILA (on-chip)                         | External Logic Analyser            |
|----------------------|---------------------------------------|------------------------------------|
| Signal access        | Internal nets, not just I/O pins      | Only signals routed to probe pads  |
| Bandwidth            | Captures at full design clock rate    | Limited by probe cable bandwidth   |
| Setup time           | Requires rebuild if probes change     | Clips connect without rebuild      |
| Depth                | Limited by BRAM budget (typ. 1k–64k) | External memory, often much deeper |
| Trigger flexibility  | Powerful multi-stage triggers         | Also powerful, depends on tool     |
| Cost                 | Uses FPGA fabric/BRAM resources       | Separate instrument cost           |

The key advantage of an ILA is visibility into internal nets that are not routed to device pins —
state machine registers, bus arbitration signals, and pipeline status bits are all observable.

---

### Question 2

**What is a VIO core and what distinguishes it from an ILA?**

**Answer:**

A VIO (Virtual Input/Output) core provides two capabilities:

- **Virtual outputs** (from Vivado to the FPGA): drive signals inside the design from the Vivado
  Hardware Manager dashboard. These are useful for injecting stimuli, overriding control signals,
  or toggling resets without physical switches.
- **Virtual inputs** (from the FPGA to Vivado): read back signal values in real time without
  triggering and buffering. These are shown as live probe values updated continuously.

The VIO samples its input probes synchronously but transfers values asynchronously over JTAG.
It therefore does not provide a time-correlated waveform the way an ILA does — it shows current
or recent values.

**Typical use cases for VIO:**

- Drive a one-shot reset pulse during bringup when no physical reset button is accessible.
- Override a chip-select or enable signal to isolate subsystems.
- Read back a status register value without writing dedicated debug logic.
- Combine with ILA: use a VIO output to arm a test sequence, then ILA captures the result.

---

### Question 3

**How do you insert an ILA into a Vivado design? Describe both the IP Catalog method and the
`mark_debug` attribute method.**

**Answer:**

**Method 1 — Instantiate from IP Catalog:**

Explicitly instantiate the `ila_0` (or similarly named) IP in the HDL. You specify the number of
probes and their widths at IP configuration time.

```vhdl
-- VHDL instantiation of a pre-generated ILA
component ila_0
    port (
        clk     : in std_logic;
        probe0  : in std_logic_vector(7 downto 0);
        probe1  : in std_logic_vector(0 downto 0);
        probe2  : in std_logic_vector(15 downto 0)
    );
end component;

u_ila : ila_0
    port map (
        clk    => sys_clk,
        probe0 => data_bus,
        probe1 => valid_flag,
        probe2 => address_bus
    );
```

This is the most explicit and portable method. The ILA IP is part of the synthesis netlist from
the start.

**Method 2 — `mark_debug` attribute (Tcl/XDC-driven insertion):**

Annotate signals in HDL or XDC with `MARK_DEBUG`, then run the "Set Up Debug" wizard in Vivado
or call `implement_debug_core` in Tcl. Vivado inserts the ILA automatically during implementation.

```vhdl
-- In VHDL source
attribute mark_debug : string;
attribute mark_debug of data_bus    : signal is "true";
attribute mark_debug of valid_flag  : signal is "true";
attribute mark_debug of address_bus : signal is "true";
```

```tcl
# Equivalent in XDC
set_property MARK_DEBUG true [get_nets data_bus[*]]
set_property MARK_DEBUG true [get_nets valid_flag]
```

After synthesis, Vivado groups all marked nets and presents the "Set Up Debug" wizard, which
assigns probes to ILA instances and sets capture depth.

**Trade-offs:**

| Aspect               | Instantiation             | mark_debug                        |
|----------------------|---------------------------|-----------------------------------|
| Control over probes  | Explicit, exact           | Wizard-managed                    |
| Rebuild required     | Yes, on every change      | Yes, but probe list editable post-synthesis |
| Script-friendly      | Yes                       | Yes (Tcl automation)              |
| Risk of optimisation | Explicit instances preserved | Synthesis may optimise away unmarked copies |

---

### Question 4

**What is capture depth and how does it affect BRAM consumption? How do you decide what depth
to use?**

**Answer:**

Capture depth is the number of samples stored per trigger event. Each sample contains one reading
of all probe inputs simultaneously. The BRAM consumption is:

```
BRAM bits required = capture_depth x total_probe_width
```

For a 36 Kb BRAM primitive (the standard Xilinx primitive), each holds 36,864 bits.

**Example:**

- Probe total width: 128 bits
- Capture depth: 1024 samples
- Total bits: 128 × 1024 = 131,072 bits → requires 4 × 36 Kb BRAMs

Vivado rounds up to the nearest BRAM boundary.

**Choosing capture depth:**

| Situation                                      | Recommended depth       |
|------------------------------------------------|-------------------------|
| Fast intermittent glitch, well-understood protocol | 256–1024          |
| Slow protocol, need to see many transactions   | 4096–16384              |
| Memory-mapped bus, capture a burst             | 2048–8192               |
| Multiple ILAs competing for BRAM               | Reduce each, prioritise |
| BRAM-constrained device                        | Use compression or reduce probe width |

**Key rule:** wider probes eat depth faster than you expect. Strip probes to the minimum
necessary widths. A 256-bit AXI bus at depth 2048 consumes 512 Kbits — roughly 15 BRAMs on a
smaller device.

---

## Intermediate

### Question 5

**Explain the ILA trigger modes: basic, advanced, and state. When would you use each?**

**Answer:**

**Basic trigger:**

A simple single-condition trigger. All enabled comparators are AND-ed or OR-ed. Available
comparators per probe include: `==`, `!=`, `>`, `<`, `>=`, `<=`, and don't-care (`X`).

Use for: catching a specific bus value, detecting an asserted signal, or triggering on a
particular state machine state code.

```
Trigger when: address_bus == 0x1000 AND write_enable == 1
```

**Advanced trigger:**

A user-defined boolean expression combining up to 16 probe comparators using arbitrary AND/OR/NOT
logic. The expression is written in the trigger condition editor.

Use for: complex multi-field conditions, e.g., "trigger when AXI response is SLVERR AND the
burst length is greater than 8 AND the transaction ID is 0x3."

**State-based (sequential) trigger:**

A finite state machine with up to 16 states, each having a condition and a transition to the next
state or a loop count. The ILA only fires when the full state sequence completes.

```
State 0: Wait for req_valid == 1 → go to State 1
State 1: Wait for ack == 0 for 3 consecutive cycles → TRIGGER
```

Use for: detecting protocol violations that require a sequence of events, such as a handshake
timeout, a missing acknowledgement after a request, or a specific pattern of accesses over time.

**Summary:**

| Trigger type  | Complexity | Use case                                       |
|---------------|------------|------------------------------------------------|
| Basic         | Low        | Single condition, fast setup                   |
| Advanced      | Medium     | Complex boolean condition, multiple fields     |
| State         | High       | Ordered sequences, timeouts, protocol checks   |

---

### Question 6

**What is the difference between trigger position settings (pre-trigger, post-trigger, centre)?
How does this affect what you see in the waveform?**

**Answer:**

The ILA BRAM is treated as a circular buffer that fills continuously. When the trigger fires,
the core decides where in the capture window the trigger event sits.

- **Full pre-trigger (trigger at sample 0):** the buffer captures entirely after the trigger.
  You see what happened immediately following the trigger event. Use this when you know what
  causes the problem and want to see the consequences.

- **Full post-trigger (trigger at last sample):** the buffer is already full when the trigger
  fires. You see what happened in the window leading up to the trigger. Use this when the trigger
  marks the end of an error — you want to see what preceded it.

- **Centre trigger:** the trigger event sits halfway through the captured window. You see equal
  amounts of pre- and post-trigger data. Good general-purpose choice when the context of an
  event matters in both directions.

**Practical example:**

You are debugging a CRC error on a packet. The CRC error flag appears at the end of the packet.
Set the trigger to the CRC error flag with a large pre-trigger window so you capture the entire
packet header and payload that led to the error.

---

### Question 7

**You have inserted an ILA but when you open Hardware Manager, the probe names show as `PROBE0`,
`PROBE1`, etc. instead of the signal names from your HDL. Why, and how do you fix it?**

**Answer:**

Probe names in the ILA are derived from a `.ltx` (Logic Analyser eXchange) file generated during
implementation. If the `.ltx` file is missing, stale, or not associated with the bitstream in
Hardware Manager, Vivado falls back to generic probe identifiers.

**Causes:**

1. The `.ltx` file was not generated (implementation not run, or ILA was inserted post-bitstream).
2. The correct `.ltx` file was not loaded — Hardware Manager auto-associates it only if it sits
   alongside the bitstream in the same directory with the matching name.
3. The design was modified and reimplemented but the old `.ltx` was kept.

**Fix:**

```tcl
# In Hardware Manager Tcl console, manually associate the LTX file
set_property PROBES.FILE {/path/to/design.ltx} [get_hw_devices xc7k325t_0]
refresh_hw_device [get_hw_devices xc7k325t_0]
```

Or via the GUI: in Hardware Manager, right-click the device → "Associate Probes File" → browse
to the correct `.ltx`.

**Prevention:** always use the "Program and Debug" flow from within the same Vivado project
session. When doing command-line flows, generate the `.ltx` explicitly:

```tcl
write_debug_probes -force ./output/design.ltx
```

---

### Question 8

**What is IBERT and when would you use it instead of an ILA?**

**Answer:**

IBERT (Integrated Bit Error Ratio Tester) is a Xilinx debug IP for characterising high-speed
serial transceivers (GTX, GTH, GTY, etc.). It generates PRBS patterns, loops them through the
transceiver, and measures the bit error rate.

**IBERT provides:**

- PRBS-7, PRBS-15, PRBS-23, PRBS-31 pattern generation and checking.
- Eye scan — a 2D scan of voltage/time margins, producing an eye diagram of the received serial
  data at a given equalisation setting.
- TX/RX pre-emphasis and equalisation control via the Vivado Hardware Manager link dashboard.
- BER measurement at programmable scan points.

**Use IBERT instead of (or alongside) ILA when:**

| Scenario                                            | Use IBERT |
|-----------------------------------------------------|-----------|
| Bringing up a PCIe, Ethernet, or custom SerDes link | Yes       |
| Measuring link margin before production release     | Yes       |
| Comparing two equalisation settings                 | Yes       |
| Debugging intermittent bit errors on a serial link  | Yes       |
| Debugging a logic protocol running over the link    | ILA after the PCS layer |

IBERT operates below the protocol level — it works at the physical coding sublayer. Once IBERT
confirms the physical link is clean, switch to an ILA on the deserialised data to debug protocol
behaviour.

---

### Question 9

**Describe the resource impact of adding multiple ILA and VIO cores. How do you manage the
debug overhead on a resource-constrained device?**

**Answer:**

Each debug core consumes:

| Core        | LUT cost (approx.)            | BRAM cost                             | Routing overhead |
|-------------|-------------------------------|---------------------------------------|-----------------|
| ILA (small) | 400–800 LUTs for control      | `depth × probe_width / 36Kb` BRAMs   | Moderate        |
| ILA (large) | 800–2000 LUTs                 | Scales linearly with depth × width    | Significant     |
| VIO         | 200–500 LUTs, minimal BRAM    | ~0–1 BRAM depending on width          | Low             |
| JTAG hub    | ~100 LUTs (shared by all cores) | 0                                   | Negligible      |

**Management strategies:**

1. **Reduce probe width:** only probe the bits you actually need. An 8-bit status field needs
   8 bits, not 32.

2. **Reduce capture depth:** use 256 or 512 samples for quick functional checks. Increase only
   when you need to capture a long sequence.

3. **Multiplex probes:** if the ILA has spare probe ports, pack multiple narrow signals into one
   wide probe and decode in Vivado post-capture (use "display name" with bit-slicing).

4. **Use a debug hub strategically:** all ILA/VIO cores share one JTAG hub. You pay the hub
   cost once regardless of how many cores are present.

5. **Stagger debug cores by revision:** in constrained designs, build multiple bitstreams each
   with ILAs focused on different subsystems, then test each subsystem in turn.

6. **Remove debug cores for production:** use a global `ifdef` or generics to exclude all debug
   instantiations. Alternatively, the `mark_debug` attribute can be stripped from the XDC before
   the final production build.

7. **Use chipscope-compatible synthesis attributes:** set `keep_hierarchy` on modules containing
   debug probes to prevent logic replication from creating multiple driven nets that confuse the
   ILA connections.

---

## Advanced

### Question 10

**You are debugging an intermittent AXI4 protocol violation that occurs roughly once per minute
in a complex SoC design running at 250 MHz. Describe how you would set up ILA triggers to
reliably capture this event.**

**Answer:**

An intermittent event at 250 MHz occurring once per minute means approximately 15 billion clock
cycles between events. A simple level trigger will miss it unless the ILA is armed exactly when
the event occurs. The solution is a state-based sequential trigger combined with careful probe
selection.

**Step 1 — Identify the violation signature.**

For an AXI4 protocol violation, common signatures include:
- `BVALID` asserted without a preceding `AWVALID`/`WVALID` handshake.
- `RDATA` valid (`RVALID`) arriving on the wrong transaction ID.
- A `WLAST` mismatch with the programmed burst length.
- `ARVALID` deasserted before `ARREADY` — illegal mid-handshake withdrawal.

Assume the target is a `WLAST` arriving at beat N when burst length indicates beat M.

**Step 2 — Define probes.**

```
probe0[7:0]   = AWLEN    (burst length from write address channel)
probe1[0]     = AWVALID
probe2[0]     = AWREADY
probe3[0]     = WVALID
probe4[0]     = WREADY
probe5[0]     = WLAST
probe6[2:0]   = beat_counter   (internal counter, register in design)
probe7[3:0]   = AWID
```

**Step 3 — Configure a state-based trigger.**

```
State 0: AWVALID == 1 AND AWREADY == 1  → latch AWLEN, go to State 1
State 1: WVALID == 1 AND WREADY == 1    → increment beat counter, stay in State 1
         WLAST == 1 AND beat_counter != AWLEN → TRIGGER
         WLAST == 1 AND beat_counter == AWLEN → go to State 0 (no error)
```

The trigger fires only when the WLAST appears at the wrong beat count. Because the state machine
resets on a clean transaction, it will not false-trigger on valid traffic.

**Step 4 — Set capture position.**

Use 75% post-trigger (trigger near the start of the capture window) to see the burst that caused
the violation plus the next few transactions, showing whether the interconnect recovers correctly.

**Step 5 — Use "run trigger for this ILA" mode.**

In Vivado Hardware Manager, set the ILA to "Re-arm after each trigger" (continuous run mode).
Each capture that does not show the violation automatically re-arms. Leave the capture running
unattended; Vivado saves the waveform each time the trigger fires.

**Step 6 — Corroborate with a VIO.**

Add a VIO output to inject a forced error (override `WLAST` one beat early) to verify the
trigger fires correctly before waiting for the real intermittent event.

---

### Question 11

**Explain how the ILA debug hub works. What happens when you have multiple ILA cores and one
VIO core in the same design?**

**Answer:**

The Debug Hub (also called the JTAG Hub or `dbg_hub`) is a Xilinx IP automatically inserted by
Vivado whenever one or more debug cores are present. It performs two functions:

1. **JTAG routing:** it sits on the device's dedicated BSCAN chain and exposes each connected
   debug core as a distinct virtual channel. The host (Vivado Hardware Manager) addresses each
   core independently over this shared JTAG connection.

2. **Clock and interface bridging:** each ILA/VIO is connected to the hub via a synchronisation
   interface. The hub handles the clock-domain crossing between the user-clock-domain ILA and
   the JTAG clock domain.

**Multi-core topology:**

```
                ┌───────────────────────────────────┐
JTAG TAP ───►  │           Debug Hub                │
                │  (auto-inserted by Vivado)         │
                │  ID=0: ILA_0 (AXI monitor, 250MHz) │
                │  ID=1: ILA_1 (DDR ctrl, 300MHz)    │
                │  ID=2: VIO_0 (control signals)     │
                └───────────────────────────────────┘
```

Each core gets a unique index. Vivado Hardware Manager discovers all cores by scanning the hub
and presents them as separate instruments.

**Important constraints:**

- Each ILA core must be connected to a **free-running clock**. If the ILA clock is gated off,
  the core becomes unresponsive and JTAG communication may time out.
- The Debug Hub itself uses the device's BSCAN2 primitive. You must not instantiate BSCAN2
  yourself if you have debug cores; doing so creates a conflict.
- All debug cores share the single JTAG bandwidth. Simultaneous high-rate JTAG transfers (e.g.,
  readback of a large ILA capture) can make VIO status updates appear sluggish.

**Practical implication:** if you observe that one ILA core freezes but others continue working,
the most likely cause is that the frozen ILA's clock has been gated, causing the hub's handshake
to that core to stall. Check clock enables and MMCM/PLL lock signals.

---

### Question 12

**What is the `KEEP` attribute and why is it important when probing signals inside a synthesised
design? What can go wrong without it?**

**Answer:**

The `KEEP` attribute prevents the synthesis and implementation tools from removing, merging, or
renaming a net during optimisation. When a net is marked `KEEP`, the tools guarantee a physical
net with that name survives to the implemented netlist and can be probed.

**Why it matters for debug:**

Synthesis can optimise a net away under several conditions:

1. **Constant propagation:** if synthesis determines that a signal is always '0' or '1', it
   removes the register and replaces downstream logic with a constant. An ILA probe on that net
   would then probe a constant value — or fail to connect at all.

2. **Logic duplication and fanout reduction:** a heavily-loaded net may be replicated into
   multiple copies with added suffixes (`net_rep0`, `net_rep1`). The original net name may no
   longer exist as a single net.

3. **Merging equivalent registers:** two registers with identical inputs may be merged into one.
   If you probed the eliminated register, the probe connects to nothing.

**How to apply:**

```vhdl
-- VHDL: keep attribute prevents removal
attribute keep : string;
attribute keep of status_reg : signal is "true";
```

```systemverilog
// SystemVerilog: keep attribute
(* keep = "true" *) logic [7:0] status_reg;
```

```tcl
# XDC / Tcl equivalent
set_property KEEP true [get_nets status_reg[*]]
```

**`KEEP` vs `MARK_DEBUG`:**

`MARK_DEBUG` implies `KEEP` — when you mark a signal for debug, Vivado automatically prevents
its removal. This is why using `MARK_DEBUG` is safer than separately managing `KEEP` for debug
purposes. If you instantiate an ILA manually and connect signals by name, you must apply `KEEP`
explicitly on those nets.

**Edge case:** `KEEP` prevents removal but does not prevent renaming during hierarchy flattening.
If a net is renamed after flattening, the ILA instantiation may fail to connect. Use
`KEEP_HIERARCHY` on the parent module to retain the hierarchy boundary if names are important.
