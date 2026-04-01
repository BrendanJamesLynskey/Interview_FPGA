# Clock Domain Crossing (FPGA)

## Overview

Clock domain crossing (CDC) is one of the most frequently examined topics in FPGA design
interviews because metastability failures are silent, non-deterministic, and extremely difficult
to debug in hardware. Every data path that crosses a clock domain boundary requires a deliberate
synchronisation strategy. Getting it wrong produces designs that pass simulation and timing
analysis but fail intermittently in silicon.

This document covers the foundational theory, practical synchroniser circuits, FIFO-based CDC,
handshake protocols, and Xilinx-specific primitives from the XPM CDC library.

---

## Fundamentals

### Q1. What is metastability, and why does it occur at clock domain crossings?

**Question:** Explain what metastability is, the conditions under which it occurs, and why it
cannot be eliminated — only its probability reduced.

**Answer:**

A flip-flop is metastable when its input (D) changes within the setup or hold window around the
active clock edge. The FF cannot resolve to a valid logic level within the required propagation
time and enters a quasi-stable analogue state between 0 and 1. It will eventually resolve, but
the resolution time is unbounded — it follows an exponential probability distribution.

```
    Setup Window    Hold Window
         |               |
----+----+---[D change here = metastability risk]---+----
    |    |                                          |
 posedge clk                                     posedge clk
```

**Why it cannot be eliminated:** Metastability is a fundamental consequence of sampling
asynchronous signals with a synchronous clock. No matter how small the setup/hold window,
there is always a non-zero probability that the data transition falls inside it. The only
recourse is to:
1. Reduce the probability to an acceptable level (e.g., less than one failure per 10 years).
2. Ensure that if metastability does occur, it resolves before being sampled by downstream logic.

**Mean Time Between Failures (MTBF):**

```
MTBF = exp(t_resolve / tau) / (f_data * f_clk * C)
```

Where:
- `t_resolve` = time available for resolution (one clock period minus propagation delay)
- `tau` = FF technology time constant (smaller is better, ~30-50 ps for modern FPGAs)
- `f_data` = rate of data transitions at the crossing
- `f_clk` = destination clock frequency
- `C` = FF-specific constant

Adding synchronisation stages increases `t_resolve` exponentially, dramatically improving MTBF.

**Common mistake:** Believing that meeting timing constraints at the CDC point eliminates
metastability. It does not. Static timing analysis tools assume data launches synchronously
on a clock edge; they do not model asynchronous launches.

---

### Q2. What is a two-flip-flop synchroniser and when is it appropriate?

**Question:** Describe the 2FF synchroniser circuit. What does it protect against, and what
are its limitations? When is a 2FF synchroniser insufficient?

**Answer:**

The 2FF synchroniser is the fundamental building block for crossing a single-bit signal
between two clock domains:

```
  clk_src domain        |      clk_dst domain
                        |
  data_src ----+--------+---> [FF1] ---> [FF2] ---> data_sync
               |        |       ^           ^
               |        |       |           |
               |        |    clk_dst     clk_dst
```

```systemverilog
module sync_2ff #(
    parameter int SYNC_STAGES = 2       // 3 stages for very high frequencies
) (
    input  logic clk_dst,               // destination clock
    input  logic rst_n_dst,             // destination domain reset
    input  logic data_src,              // input from source domain (async)
    output logic data_sync              // synchronised output
);
    logic [SYNC_STAGES-1:0] sync_chain;

    // The two registers must be placed in adjacent FFs to minimise routing delay
    // between stages. Xilinx: use ASYNC_REG attribute to ensure this.
    (* ASYNC_REG = "TRUE" *) logic [SYNC_STAGES-1:0] sync_chain_attr;

    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst)
            sync_chain_attr <= '0;
        else
            sync_chain_attr <= {sync_chain_attr[SYNC_STAGES-2:0], data_src};
    end

    assign data_sync = sync_chain_attr[SYNC_STAGES-1];

endmodule
```

**What 2FF synchroniser protects against:**
- Metastability on the first FF (FF1). If FF1 goes metastable, it has one full clock period
  of `clk_dst` to resolve before FF2 samples it.
- For most designs, two stages achieve MTBF >> device lifetime.

**Limitations and when it is insufficient:**

| Situation | Why 2FF fails | Correct solution |
|---|---|---|
| Multi-bit data buses | Bits may sample from different source clock cycles | Gray code + 2FF, or async FIFO |
| Fast data that must not be missed | 2FF may miss short pulses | Pulse stretcher + 2FF, or handshake |
| Multiple related signals | Signals may sample inconsistently | Async FIFO or handshake protocol |
| Source faster than 2x destination | Pulses narrower than one destination period | Handshake or FIFO |

**Critical rule:** Never use a 2FF synchroniser directly on a multi-bit bus. Each bit passes
through its own FF1 at different metastability resolution times, so bits may appear to come
from different source clock cycles, producing a corrupted word.

---

### Q3. What does the Xilinx `ASYNC_REG` attribute do, and why is it mandatory on synchroniser FFs?

**Question:** Explain the purpose of the `ASYNC_REG` attribute and what happens if it is omitted
from synchroniser chains.

**Answer:**

`ASYNC_REG` is a Xilinx synthesis and implementation attribute that must be applied to every
flip-flop in a CDC synchroniser chain. It serves two purposes:

**1. Placement guidance:** Directs the placer to locate consecutive synchroniser FFs in the same
CLB slice (or adjacent slices). This minimises routing delay between FF1 and FF2, maximising
the time FF1 has to resolve before FF2 samples it. Without `ASYNC_REG`, the placer may
legally scatter synchroniser FFs across the device, creating long routing delays that eat into
the resolution window and degrade MTBF.

**2. Timing analysis exemption:** Marks the path into FF1 as a known CDC path that should not
be flagged as a timing violation. This prevents false critical warnings and allows the proper
`set_false_path` or `set_max_delay -datapath_only` constraints to suppress timing errors on the
asynchronous input path.

```verilog
// XDC constraint that works with ASYNC_REG:
// Suppress timing on the async input to the first synchroniser FF
// (ASYNC_REG tells Vivado which paths these are)
set_false_path -to [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]
```

**What happens without `ASYNC_REG`:**
- Placer may separate FF1 and FF2, adding routing delay between them.
- Vivado reports critical warnings about CDC paths without proper constraints.
- MTBF degrades silently — the design may work in benign conditions but fail under load.

**Three-stage synchronisers:** For clocks above ~500 MHz or across very long FPGA routing
distances, three stages are common. `ASYNC_REG` on all three stages is still required.

---

## Intermediate

### Q4. How do you safely cross a multi-bit data word between clock domains?

**Question:** A 32-bit configuration register is written in the CPU clock domain (100 MHz) and
read by signal processing logic in a 250 MHz clock domain. The register changes infrequently.
Describe three approaches and their trade-offs.

**Answer:**

**Approach 1: Gray code encoding (for counters/addresses only)**

Gray code is valid only when the multi-bit value changes by exactly one bit per cycle (a
counter). It cannot be used for arbitrary data.

```
1. Encode counter value as Gray code in source domain
2. Pass each Gray code bit through its own 2FF synchroniser
3. Decode Gray code back to binary in destination domain

Key property: even if bits sample from different source cycles, a Gray code
that "straddles" two consecutive values still decodes to one of the two valid values.
```

**Approach 2: Handshake protocol (for infrequent, multi-bit data)**

```
Source domain writes data, asserts req.
2FF synchronises req to destination.
Destination reads data (after req has been stable for 2 dst cycles).
Destination asserts ack.
2FF synchronises ack back to source.
Source de-asserts req only after seeing synchronised ack.
Minimum latency: ~4 cycles of slower clock.
```

This works correctly for the configuration register scenario because:
- The register changes infrequently (low overhead of handshake acceptable).
- Data is held stable throughout the handshake (sampled only after req is stable).

**Approach 3: Asynchronous FIFO (for streaming data)**

For continuous data flow, an asynchronous FIFO uses Gray-coded read/write pointers
synchronised across domains. This is the standard solution for high-throughput CDC.
See Q6 and Challenge 03 for full detail.

**For this specific scenario (infrequent configuration register):**

The handshake protocol is the correct choice. An async FIFO is over-engineered for
infrequent register updates. Gray code cannot be used because configuration data is arbitrary.

```
Trade-off summary:
┌──────────────────┬──────────────────┬──────────────────┬──────────────────┐
│ Method           │ Data types       │ Throughput       │ Latency          │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 2FF synchroniser │ Single-bit only  │ Up to f_dst/2    │ 2 dst cycles     │
│ Gray code        │ Counters only    │ Every src cycle  │ 2 dst cycles     │
│ Handshake        │ Any multi-bit    │ ~1/(4*T_slow)    │ 4+ slow cycles   │
│ Async FIFO       │ Any multi-bit    │ Near wire-rate   │ ~4 cycles each   │
└──────────────────┴──────────────────┴──────────────────┴──────────────────┘
```

---

### Q5. Explain the four-phase handshake protocol for CDC. Why is a two-phase variant sometimes preferred?

**Question:** Describe both the four-phase and two-phase handshake protocols. Implement the
four-phase protocol in synthesisable RTL.

**Answer:**

**Four-phase handshake (req/ack with return-to-zero):**

```
REQ (src) : _____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|____________|‾‾‾‾‾‾‾...
ACK (dst) : ____________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|______________...
Phases:         1     2        3       4     1   ...
  Phase 1: REQ asserted, data held stable
  Phase 2: Synchronised REQ seen by dst, ACK asserted, data latched
  Phase 3: Synchronised ACK seen by src, REQ de-asserted
  Phase 4: Synchronised REQ de-assertion seen by dst, ACK de-asserted
  Then repeat.
```

```systemverilog
// Sender side (source domain)
module cdc_handshake_sender #(parameter int DATA_WIDTH = 32) (
    input  logic                  clk_src,
    input  logic                  rst_n_src,
    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                  send,        // pulse: request to send
    output logic                  busy,         // high while handshake in progress
    output logic [DATA_WIDTH-1:0] data_out_reg, // captured data
    output logic                  req,           // to destination domain
    input  logic                  ack_sync       // ack synchronised into src domain
);
    typedef enum logic [1:0] { IDLE, REQ_HIGH, WAIT_ACK_LOW } state_t;
    state_t state;

    always_ff @(posedge clk_src or negedge rst_n_src) begin
        if (!rst_n_src) begin
            state        <= IDLE;
            req          <= 1'b0;
            data_out_reg <= '0;
            busy         <= 1'b0;
        end else begin
            unique case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (send) begin
                        data_out_reg <= data_in; // capture data
                        req          <= 1'b1;
                        busy         <= 1'b1;
                        state        <= REQ_HIGH;
                    end
                end
                REQ_HIGH: begin
                    if (ack_sync) begin          // ack received
                        req   <= 1'b0;           // phase 3: de-assert req
                        state <= WAIT_ACK_LOW;
                    end
                end
                WAIT_ACK_LOW: begin
                    if (!ack_sync) begin          // ack de-asserted (phase 4 complete)
                        state <= IDLE;
                        busy  <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
```

**Two-phase handshake (toggle-based):**

In the two-phase variant, the sender toggles REQ (rather than asserting/de-asserting it).
The receiver toggles ACK to acknowledge. This halves the handshake cycle count from four
synchroniser traversals to two. It is preferred when:
- Maximum throughput matters (e.g., crossing a low-speed control signal frequently).
- The protocol can tolerate more complex encoding logic.

**Disadvantage of two-phase:** More complex to decode correctly; the receiver must detect
any change in REQ (rising or falling edge), not just a high level.

---

### Q6. How does an asynchronous FIFO use Gray-coded pointers to cross clock domains safely?

**Question:** Explain why raw binary pointers cannot be used in an async FIFO and describe the
Gray-coded pointer approach. What constraint must be applied to the pointer synchronisation paths?

**Answer:**

An asynchronous FIFO has two independent clocks: a write clock (`clk_wr`) for the producer
and a read clock (`clk_rd`) for the consumer. Write and read pointers each need to be readable
in the opposite clock domain to compute full/empty flags.

**Why binary pointers fail:**

A binary pointer changes multiple bits simultaneously when it increments (e.g., 0111 -> 1000
changes all 4 bits). If each bit is synchronised independently, bits may capture values from
different write-clock cycles, producing a corrupted pointer value. A corrupted pointer leads
to incorrect full/empty flags, causing either data corruption (false not-full, data overwritten)
or data starvation (false not-empty, invalid data read).

**Gray-coded pointer solution:**

Gray code increments change exactly one bit per step. Therefore:
1. Each pointer bit can be synchronised independently through a 2FF chain.
2. Even if some bits capture the old value and some the new, the result is always one of two
   adjacent valid pointer values (the one before or the one after the increment).
3. Both adjacent values produce conservative full/empty flags (may indicate full/empty when
   there is still one slot or one word, but never indicates not-full when actually full).

```
Binary: 0110 -> 0111 -> 1000   (multiple bits change at 0111->1000)
Gray:   0101 -> 0100 -> 1100   (exactly one bit changes per step)
```

**Constraints on pointer synchronisation paths:**

The XDC constraint applied to Gray-coded pointer paths must ensure two things:
1. The path is treated as a CDC path (not a false path that ignores timing).
2. The data is stable for at least one destination-clock setup time before being sampled.

```tcl
# Constrain CDC path: allow up to one source clock period for data to launch
# (data is stable for one full source clock cycle -- the pointer does not change
#  every cycle in practice, but this worst-case constraint covers the case)
set_max_delay -datapath_only -from [get_cells -hier *wr_ptr_gray_reg*] \
              -to   [get_cells -hier *wr_ptr_gray_sync*] \
              [get_property PERIOD [get_clocks clk_wr]]
```

**`set_false_path` vs `set_max_delay -datapath_only`:**
- `set_false_path`: removes the path from timing analysis entirely. Acceptable if the 2FF
  synchroniser guarantees sufficient resolution time, but hides any accidental long paths.
- `set_max_delay -datapath_only`: keeps data path timing but ignores clock skew. Preferred
  because it catches routing problems while acknowledging the path is a CDC crossing.

---

### Q7. What are the Xilinx XPM CDC primitives, and when should you use them instead of custom RTL?

**Question:** Describe the XPM CDC family of macros. What are the key parameters of
`xpm_cdc_single` and `xpm_cdc_gray`? When is using XPM mandatory vs. optional?

**Answer:**

Xilinx Parameterised Macros (XPM) for CDC are Vivado-native modules that encapsulate correct
synchroniser circuits with built-in `ASYNC_REG` attributes, correct XDC constraints, and
CDC methodology reporting. They are the recommended approach for new designs.

**`xpm_cdc_single` -- single-bit synchroniser:**

```systemverilog
xpm_cdc_single #(
    .DEST_SYNC_FF   (2),     // number of synchroniser stages (2-10)
    .INIT_SYNC_FF   (0),     // initialise FFs to 0 during reset (0 or 1)
    .SIM_ASSERT_CHK (1),     // enable simulation checks for CDC violations
    .SRC_INPUT_REG  (0)      // register input in source domain (0 or 1)
) u_sync_single (
    .src_clk  (clk_src),     // source clock (only needed if SRC_INPUT_REG=1)
    .dest_clk (clk_dst),
    .src_in   (data_src),    // asynchronous input
    .dest_out (data_sync)    // synchronised output
);
```

**`xpm_cdc_gray` -- Gray-coded bus synchroniser:**

```systemverilog
xpm_cdc_gray #(
    .DEST_SYNC_FF   (2),     // synchroniser stages
    .INIT_SYNC_FF   (0),
    .SIM_ASSERT_CHK (1),
    .WIDTH          (8)      // bus width (Gray code)
) u_sync_gray (
    .src_clk   (clk_src),
    .dest_clk  (clk_dst),
    .src_in    (gray_data),  // already Gray-encoded in source domain
    .dest_out  (gray_sync)   // synchronised Gray code (decode in dst domain)
);
```

**Other XPM CDC primitives:**

| Primitive | Purpose |
|---|---|
| `xpm_cdc_single` | Single-bit level synchroniser |
| `xpm_cdc_pulse` | Converts short source pulse to a guaranteed-captured dst pulse |
| `xpm_cdc_handshake` | 4-phase handshake for multi-bit data, low bandwidth |
| `xpm_cdc_gray` | Gray-coded bus synchroniser (for counters/addresses) |
| `xpm_cdc_array_single` | Array of independent single-bit synchronisers |
| `xpm_cdc_async_rst` | Async reset synchroniser with synchronous de-assertion |

**When XPM is mandatory:**

Vivado's CDC methodology checks (`report_cdc`) are aware of XPM primitives and will correctly
characterise them as safe crossings. Custom RTL synchronisers that use `ASYNC_REG` are also
recognised, but XPM is required if:
- The project uses Vivado IP Integrator (Block Design) where XPM is the standard interface.
- The company's methodology requires `report_cdc` to show zero unclassified crossings.

**When custom RTL is acceptable:**

Custom RTL with `ASYNC_REG` attributes and correct XDC constraints is fully equivalent to
XPM and is appropriate for designs requiring tighter control over implementation or targeting
non-Xilinx devices.

---

## Advanced

### Q8. How do you handle a CDC reset signal that must be distributed to thousands of flip-flops?

**Question:** Describe the correct approach for synchronising an asynchronous reset across clock
domains in an FPGA, including the reset tree and Xilinx-specific considerations.

**Answer:**

The recommended pattern is asynchronous assertion, synchronous de-assertion (also called
"synchronised reset release" or "reset synchroniser"):

```
1. The raw reset (from board, button, or watchdog) asserts asynchronously -- immediately
   stopping the clock domain.
2. A reset synchroniser releases the reset synchronously -- ensuring all FFs in the domain
   come out of reset on the same clock edge, preventing any setup/hold violations on reset
   de-assertion.
```

```systemverilog
// Reset synchroniser: async assert, synchronous de-assert
// Place one of these per clock domain
module reset_sync (
    input  logic clk,
    input  logic async_rst_n,     // asynchronous reset input (active low)
    output logic sync_rst_n       // synchronised reset output for this domain
);
    // Two-stage synchroniser
    // ASYNC_REG ensures these FFs are placed adjacently
    (* ASYNC_REG = "TRUE" *) logic stage1, stage2;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            stage1 <= 1'b0;       // async assert: immediately clears both stages
            stage2 <= 1'b0;
        end else begin
            stage1 <= 1'b1;       // sync release: walk 1's through the chain
            stage2 <= stage1;
        end
    end

    assign sync_rst_n = stage2;
endmodule
```

**Xilinx-specific considerations:**

UltraScale and UltraScale+ FPGAs have a Global Set/Reset (GSR) network that initialises all
FFs to their `INIT` attribute value when the bitstream is loaded (and optionally after
configuration). For FPGA designs, the explicit reset synchroniser above handles the
runtime reset; GSR handles power-on initialisation.

**Reset tree distribution:**

In large designs, `sync_rst_n` must be buffered and distributed using the FPGA's clock
network resources. For a full-chip reset in a high-density device:

```tcl
# Use Vivado to set max fanout on reset registers, forcing replication
set_property MAX_FANOUT 100 [get_cells -hier -filter {NAME =~ *reset_sync*}]

# Or, use BUFG to drive reset on a clock network (use with caution --
# consumes a global buffer that could be used for clocks)
```

**Common mistake:** Failing to use `ASYNC_REG` on the reset synchroniser FFs. The placer may
separate them, and — critically — the CDC methodology checker will flag the reset path as
uncharacterised.

---

### Q9. A CDC path is flagged by `report_cdc` as "No synchronisation found." Walk through your debug methodology.

**Question:** Vivado's CDC report shows a critical warning: "No synchronisation found" on a
path between `clk_a` and `clk_b`. Describe your step-by-step debug process.

**Answer:**

**Step 1: Identify the path.**

```tcl
report_cdc -details -file cdc_report.txt
# Examine: source register, destination register, clock domains, path type
```

Check: Is this a genuine CDC path, or a false crossing introduced by synthesis (e.g., a
constant folded across a clock domain boundary)?

**Step 2: Determine the data type crossing.**

- Single bit? -> 2FF synchroniser or `xpm_cdc_single`.
- Single bit, short pulse? -> `xpm_cdc_pulse` or pulse stretcher + 2FF.
- Multi-bit counter/address? -> Gray code + 2FF or `xpm_cdc_gray`.
- Multi-bit arbitrary data, infrequent? -> Handshake or `xpm_cdc_handshake`.
- Multi-bit streaming data? -> Async FIFO.

**Step 3: Check whether a synchroniser exists but is not recognised.**

Custom synchronisers without `ASYNC_REG` are not recognised by `report_cdc`. Add the
attribute and re-run:

```verilog
(* ASYNC_REG = "TRUE" *) reg sync_ff1, sync_ff2;
```

**Step 4: Check for missing constraints.**

If the synchroniser exists and `ASYNC_REG` is set, the XDC may be missing:

```tcl
# Verify the false path or max_delay constraint exists
report_timing -from [get_clocks clk_a] -to [get_clocks clk_b]
```

**Step 5: Apply the correct constraint and re-run `report_cdc`.**

```tcl
# For a synchronised single-bit path:
set_false_path -from [get_clocks clk_a] \
               -to   [get_cells -hier -filter {ASYNC_REG == TRUE}]

# Or use set_max_delay for better visibility:
set_max_delay -datapath_only \
    -from [get_cells src_reg] \
    -to   [get_cells {sync_ff1}] \
    [get_property PERIOD [get_clocks clk_a]]
```

**Step 6: Validate with simulation.**

CDC analysis is static; it cannot verify that a handshake or Gray code is used correctly.
Write a targeted simulation with:
- Both clocks running at their design frequencies.
- Stimulus that exercises the crossing at maximum throughput.
- Assertions checking that Gray code values never change by more than one bit when sampled
  in the destination domain.

---

### Q10. What is the difference between `set_false_path` and `set_max_delay -datapath_only` for CDC paths? Which should you use and when?

**Question:** Explain the timing analysis behaviour of each constraint. When does using
`set_false_path` mask a real problem, and when is `set_max_delay -datapath_only` the safer choice?

**Answer:**

**`set_false_path`:**
- Completely removes the path from timing analysis.
- The path can be arbitrarily long with no violations reported.
- Appropriate when: the path has a deliberate synchroniser that guarantees correct operation
  regardless of path length (e.g., a 2FF synchroniser where the CDC path delay only affects
  MTBF, not correctness), or when the path is provably never used in the active state
  (a test-only path).

```tcl
# Typical use: remove all timing on paths into synchroniser FFs
set_false_path -to [get_cells -hier -filter {ASYNC_REG == TRUE}]
```

**`set_max_delay -datapath_only`:**
- Replaces the default timing constraint with a specified maximum delay, considering only
  the data path (ignores clock skew and uncertainty).
- Reports a violation if the data path exceeds the specified limit.
- Appropriate when: you want to ensure the combinational path from source FF to destination
  synchroniser FF is not excessively long (which would reduce the time available for
  metastability resolution), but you do not want to enforce a full setup/hold analysis.

```tcl
# Limit the CDC path to one source clock period
# This ensures the data arrives before the next source clock edge
set_max_delay -datapath_only \
    -from [get_cells src_ff_reg] \
    -to   [get_cells sync_ff1_reg] \
    5.0    ;# ns, one period of the source clock
```

**Why `set_max_delay -datapath_only` is generally safer:**

If a synthesis or place-and-route change inadvertently introduces a very long combinational
path before the synchroniser input (e.g., a complex MUX tree), `set_false_path` would never
catch it. The long path reduces the metastability resolution window and degrades MTBF.
`set_max_delay -datapath_only` will report a violation, flagging the problem.

**Rule of thumb:**
- Use `set_false_path` only when you truly do not care about path length (static signals,
  test-only paths, or reset trees that have dedicated FPGA routing).
- Use `set_max_delay -datapath_only` for all active CDC data paths to retain a sanity check
  on routing quality.

---

## Quick-Reference Summary

```
CDC Decision Tree:
───────────────────────────────────────────────────────────────────────────────
Single bit, level signal
    -> 2FF synchroniser (xpm_cdc_single)

Single bit, short pulse (may be missed)
    -> Pulse stretcher + 2FF, or xpm_cdc_pulse

Multi-bit, only changes by 1 bit per cycle (counter, address)
    -> Gray code encode -> 2FF per bit -> Gray decode (xpm_cdc_gray)

Multi-bit, arbitrary value, infrequent changes (config registers)
    -> 4-phase handshake (xpm_cdc_handshake)

Multi-bit, continuous streaming data
    -> Asynchronous FIFO with Gray-coded pointers

Reset signal
    -> Async assert, synchronous de-assert (xpm_cdc_async_rst)
───────────────────────────────────────────────────────────────────────────────

ASYNC_REG attribute: ALWAYS required on synchroniser FFs
XDC constraint:     set_max_delay -datapath_only preferred over set_false_path
report_cdc:         Must show zero "No synchronisation found" violations before tape-out
```
