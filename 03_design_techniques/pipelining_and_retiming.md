# Pipelining and Retiming

## Overview

Pipelining is the primary technique for achieving high clock frequencies on FPGAs. By inserting
registers along a combinational path, the critical path length is reduced, enabling faster
clocking at the cost of added latency. Retiming is the complementary technique: moving existing
registers across combinational logic to balance stage delays, often performed automatically by
synthesis tools. Understanding both — and their interactions with FPGA architecture, timing
constraints, and DSP/BRAM primitives — is essential for FPGA interview performance.

---

## Fundamentals

### Q1. What is pipelining, and what is the fundamental trade-off it introduces?

**Question:** Define pipelining in RTL design. State the trade-off between latency and
throughput, and explain when pipelining is beneficial versus harmful.

**Answer:**

**Definition:** Pipelining divides a multi-cycle combinational computation into multiple stages
separated by registers. Each stage completes a portion of the computation in one clock cycle,
and multiple independent inputs progress through the stages simultaneously.

```
Without pipelining (single stage):
Input ─► [Combinational logic: A+B+C+D = 8 gate delays] ─► Output
  Max clock period: 8 gate delays (Fmax limited)
  Latency: 1 cycle
  Throughput: 1 result per cycle (when Fmax allows)

With 2-stage pipeline:
Input ─► [A+B: 4 delays] ─► REG ─► [+C+D: 4 delays] ─► Output
  Max clock period: 4 gate delays (Fmax doubles)
  Latency: 2 cycles
  Throughput: 1 result per cycle (throughput unchanged -- one result per cycle)
```

**The fundamental trade-off:**

| Parameter | Effect of adding pipeline stages |
|---|---|
| Latency | Increases (one cycle per added stage) |
| Throughput | Unchanged (1 result per clock, but clock runs faster) |
| Maximum Fmax | Increases (shorter critical path) |
| Area | Increases slightly (register cost) |
| Power | Increases (more switching activity) |
| Data dependency handling | May require stall or flush logic |

**When pipelining is beneficial:**
- The critical combinational path exceeds one clock period.
- High throughput is required and latency is acceptable.
- DSP-intensive pipelines (multiplier trees, filters) where latency is budgeted.
- The design produces and consumes data continuously (no bubble penalty).

**When pipelining is harmful:**
- Latency is the primary constraint (real-time control loops with tight feedback).
- The pipeline creates complex data hazards requiring stall/bypass logic.
- The computation is not on the critical path (adding registers wastes area).

---

### Q2. How does Vivado's synthesis retiming (`register_balancing`) work, and when should you enable it?

**Question:** Explain the `register_balancing` synthesis option. What transformations does it
perform, and what are its limitations?

**Answer:**

Retiming is the process of moving registers across combinational logic boundaries to balance
the delays in each pipeline stage. The goal is to reduce the longest stage delay while
preserving the pipeline's latency and functional correctness.

```
Before retiming (unbalanced):
Stage 1: [8 gate delays] ─► REG
Stage 2: [2 gate delays] ─► REG    <- critical path limited by stage 1
Stage 3: [3 gate delays] ─► REG

After retiming:
Stage 1: [4 gate delays] ─► REG    <- registers moved into stage 1/2 boundary
Stage 2: [5 gate delays] ─► REG
Stage 3: [4 gate delays] ─► REG    <- more balanced; higher Fmax
```

**In Vivado:** `register_balancing` is a synthesis property:

```tcl
# Enable register balancing globally (synthesis settings)
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Or in the XDC/synthesis settings file:
set_property register_balancing yes [get_cells -hier your_pipeline_module]
```

**What Vivado's retiming can do:**
- Move registers forward (into downstream logic) or backward (into upstream logic).
- Push registers through commutative operators (adders, multipliers).
- Replicate registers to avoid timing violations from high fanout.

**Limitations:**

1. **Cannot move registers across module boundaries by default.** If the combinational path
   spans multiple hierarchical levels, `KEEP_HIERARCHY` attributes prevent crossing.

2. **Cannot rebalance across BRAM or DSP primitive boundaries.** These primitives have fixed
   internal pipeline registers; retiming stops at their boundaries.

3. **Cannot move registers through asynchronous resets** that are not equivalent to the new
   register position's reset.

4. **Functional equivalence is not always maintained with complex logic.** Always verify with
   simulation after enabling retiming.

5. **Replication changes the netlist significantly**, which can affect debug (ILA probe
   connections) and ECO (Engineering Change Order) workflows.

**Best practice:** Enable retiming as a targeted directive on specific modules or paths rather
than globally, to maintain predictable synthesis results and debuggable netlists.

---

### Q3. What is the difference between a registered output and a registered input pipeline stage?

**Question:** Illustrate the difference between an "output-registered" and "input-registered"
pipeline topology. When does the distinction matter for FPGA timing?

**Answer:**

```systemverilog
// OUTPUT-REGISTERED: combinational logic first, register at output
// Common for: datapath elements where input data arrives combinationally
module output_registered #(parameter int W = 8) (
    input  logic         clk,
    input  logic [W-1:0] a, b,    // combinational inputs
    output logic [W-1:0] sum_q    // registered output
);
    always_ff @(posedge clk)
        sum_q <= a + b;   // adder result registered at output
endmodule
// Timing path: input port -> adder -> FF setup time
// Advantage: output is stable and registered; easy to use downstream

// INPUT-REGISTERED: register inputs first, combinational logic after
// Common for: signals arriving from high-fanout sources or external IOs
module input_registered #(parameter int W = 8) (
    input  logic         clk,
    input  logic [W-1:0] a, b,
    output logic [W-1:0] sum      // combinational output (NOT registered)
);
    logic [W-1:0] a_q, b_q;

    always_ff @(posedge clk) begin
        a_q <= a;    // register inputs
        b_q <= b;
    end
    assign sum = a_q + b_q;   // combinational adder from registered inputs
endmodule
// Timing path: FF clock-to-Q -> adder -> next FF setup time
// Advantage: input paths to the registers are simple; removes IO-to-FF path from critical path
```

**When the distinction matters for FPGA timing:**

1. **IO interface timing:** If `a` and `b` arrive from FPGA I/O pins, input registration
   captures them immediately at the IOB flip-flop (using `IOB` attribute in Vivado), which
   absorbs I/O delay into the register setup rather than the combinational path.

2. **DSP48 pipeline:** Xilinx DSP48E2 has optional input registers (A1, B1 registers) and
   output register (P register). Enabling these inside the DSP primitive is equivalent to
   input + output registration but uses zero fabric resources.

3. **Feedback loops:** In a design with combinational feedback, input-registered topology
   is safer because the register breaks the loop and makes the timing path well-defined.

---

## Intermediate

### Q4. How do you pipeline a multi-cycle multiplier tree for a 250 MHz FIR filter?

**Question:** A 64-tap FIR filter requires 64 multiplications and 63 additions. The target
is 250 MHz on a Xilinx UltraScale FPGA. Describe the pipeline architecture and how DSP48
primitives are used.

**Answer:**

**DSP48E2 pipeline architecture:**

Each DSP48E2 slice performs `P = A * B + C` or `P = P_prev + A * B` (cascade) in a fully
pipelined 3-stage configuration:

```
Stage 1: A and B register (pre-adder stage, input registration)
Stage 2: Multiply register (17x27 multiplier output)
Stage 3: Post-adder / Accumulate register (P register)
```

At 250 MHz on a UltraScale part, the full 3-stage pipeline of DSP48E2 is required (each
stage runs at 250 MHz without issue; the full pipeline latency is 3 cycles per DSP).

**64-tap FIR tree structure:**

```
Input stream: x[n]
Coefficients: h[0] .. h[63]

Level 1 (64 DSP48E2 multipliers, 3 pipeline stages each):
  p[k] = x[n-k] * h[k]     for k = 0..63

Level 2 (adder tree, 32 registered adders):
  s0[k] = p[2k] + p[2k+1]  for k = 0..31  (1 pipeline stage)

Level 3 (16 adders):
  s1[k] = s0[2k] + s0[2k+1] for k = 0..15 (1 pipeline stage)

Level 4: 8 adders, 1 stage
Level 5: 4 adders, 1 stage
Level 6: 2 adders, 1 stage
Level 7: 1 final adder, 1 stage

Total pipeline latency: 3 (DSP) + 6 (adder tree) = 9 cycles
Throughput: 1 output sample per clock cycle (fully pipelined)
```

**RTL approach using DSP cascade:**

For FIR filters specifically, DSP48E2 supports direct cascade (`PCOUT -> PCIN`) for the
accumulation tree. A 64-tap filter can be implemented as:
- 64 DSPs with `PCOUT` of each cascaded to `PCIN` of the next (symmetric filter).
- The final DSP accumulates all products.
- This cascade approach uses only the DSP's routing fabric, not general fabric routes.

```systemverilog
// Parameterised pipeline register insert (balances delay between DSP outputs)
// Each level of the adder tree gets a pipeline register
module adder_tree_stage #(parameter int W = 48, parameter int N = 32) (
    input  logic         clk,
    input  logic [W-1:0] in  [0:N-1],
    output logic [W-1:0] out [0:N/2-1]
);
    always_ff @(posedge clk)
        for (int i = 0; i < N/2; i++)
            out[i] <= in[2*i] + in[2*i+1];
endmodule
```

**Coefficient latency alignment:**

When using a pipelined multiplier, the input delay register `x[n-k]` must also be delayed
by 3 cycles (to match the multiplier pipeline) for each tap. This is implemented with a
shift register (SRL32 in UltraScale) per tap.

---

### Q5. What is "register balancing" vs "retiming" in Vivado, and how do they interact with `KEEP` and `DONT_TOUCH`?

**Question:** Explain the difference between register balancing and retiming as performed by
Vivado. Describe how `KEEP`, `KEEP_HIERARCHY`, and `DONT_TOUCH` attributes interact with these
optimisations.

**Answer:**

**Register balancing** (Vivado synthesis) moves registers across logic to equalise stage
delays. It is a synthesis-time transformation that operates on the RTL netlist before
place-and-route.

**Retiming** in the broader sense includes both synthesis-time register balancing and
implementation-time physical optimisation (`phys_opt_design`). The implementation-time
version (`-directive AggressiveExplore`) moves registers after placement to improve timing.

```tcl
# Synthesis retiming:
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Implementation physical optimisation (post-place retiming):
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore \
    [get_runs impl_1]
# AggressiveExplore enables: register retiming, hold-fix replication,
#                            path splitting, and DSP/BRAM pipeline insertion
```

**Interaction with constraints:**

| Attribute | Effect on retiming |
|---|---|
| `KEEP = "TRUE"` on net | Prevents the net from being removed; prevents register push-through |
| `KEEP_HIERARCHY = "TRUE"` on module | Prevents optimisation across module boundary |
| `DONT_TOUCH = "TRUE"` on cell | Prevents ANY modification to that cell (rename, move, replicate) |
| `REGISTER_BALANCING = "yes"` on module | Enables retiming within that specific module |

**Practical guidance:**

```verilog
// Use DONT_TOUCH on registers you need to probe with ILA
// (retiming could move or replicate these, breaking probe connections)
(* DONT_TOUCH = "TRUE" *)
logic [7:0] debug_probe_reg;

// Use KEEP_HIERARCHY on modules where functional equivalence
// must be maintained exactly (e.g., safety-critical blocks)
(* KEEP_HIERARCHY = "TRUE" *)
module safety_fsm (...);
```

**Common mistake:** Enabling aggressive retiming globally, then wondering why ILA probe
signals are in unexpected places. Always mark debug registers with `DONT_TOUCH` before
enabling retiming.

---

### Q6. How do you calculate the maximum achievable Fmax for a pipeline and the impact of adding stages?

**Question:** Given a combinational path of 12 ns and a FF clock-to-Q delay of 0.2 ns with
setup time of 0.1 ns, calculate the current Fmax. How many pipeline stages are needed to
achieve 500 MHz?

**Answer:**

**Setup timing equation:**

```
T_clock >= T_clk2q + T_comb + T_setup + T_skew

Where:
  T_clk2q = clock-to-Q propagation of launch FF    = 0.2 ns
  T_comb  = combinational path delay                = 12.0 ns
  T_setup = setup time of capture FF                = 0.1 ns
  T_skew  = clock skew (assume 0 for this example)  = 0.0 ns

T_clock >= 0.2 + 12.0 + 0.1 = 12.3 ns
Fmax = 1 / 12.3 ns ≈ 81.3 MHz
```

**Target: 500 MHz (T_clock = 2.0 ns)**

Available combinational budget per stage:
```
T_comb_max = T_clock - T_clk2q - T_setup
           = 2.0 - 0.2 - 0.1
           = 1.7 ns per stage
```

Number of stages needed (assuming equal division of 12 ns):
```
N = ceil(T_comb_total / T_comb_max)
  = ceil(12.0 / 1.7)
  = ceil(7.06)
  = 8 stages
```

**Pipeline latency impact:**

With 8 pipeline stages and 1 stage of output registration, the total latency is 8 clock
cycles at 500 MHz = 16 ns. Compare to the original 1 cycle at 81 MHz = 12.3 ns — latency
is slightly higher but throughput has increased 6x.

**Realistic FPGA considerations:**

The 12 ns combinational delay cannot usually be divided perfectly equally. In practice:
- Some stages (e.g., carry-chain arithmetic) cannot be split below a minimum granularity.
- DSP48 stages have fixed pipeline granularity (multiply = 1 cycle min).
- Vivado's retiming handles the fine-grained balancing after a coarse pipeline structure
  is set up in RTL.

---

## Advanced

### Q7. How does a stall-able pipeline work, and what are the key design patterns for implementing it?

**Question:** Describe the design of a stall-able (backpressure-capable) pipeline. Implement
a two-stage stall-able pipeline with valid/ready handshaking.

**Answer:**

A stall-able pipeline inserts register stages that can hold their value when downstream logic
asserts backpressure (not-ready). The key challenge is that when a stage stalls, all upstream
stages must also stall simultaneously.

**Valid/ready handshaking:**
- `valid`: asserted by a producer when the data on its output is valid.
- `ready`: asserted by a consumer when it can accept data this cycle.
- A transfer occurs when `valid && ready` on the clock edge.

```systemverilog
// Two-stage stall-able pipeline
// Stage 0 -> Stage 1 -> Stage 2 -> Output
// Each stage has its own valid register; ready propagates backward

module stall_pipeline #(parameter int DATA_W = 32) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Stage 0 input (from upstream)
    input  logic [DATA_W-1:0]     s0_data,
    input  logic                  s0_valid,
    output logic                  s0_ready,   // backpressure to upstream

    // Stage 2 output (to downstream)
    output logic [DATA_W-1:0]     s2_data,
    output logic                  s2_valid,
    input  logic                  s2_ready    // backpressure from downstream
);
    // Stage 1 registers
    logic [DATA_W-1:0] s1_data;
    logic              s1_valid;
    logic              s1_ready;

    // Stage 2 registers
    logic [DATA_W-1:0] s2_data_r;
    logic              s2_valid_r;

    // ------------------------------------------------------------------
    // Stage 0 -> Stage 1
    // Stage 1 accepts data when its register is empty or being consumed
    // ------------------------------------------------------------------
    assign s1_ready = !s1_valid || s2_ready;  // s1 can accept if empty or s2 consuming

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_data  <= '0;
        end else if (s1_ready) begin
            // s1 register can be updated
            s1_valid <= s0_valid;
            s1_data  <= s0_data;  // combinational transform can be inserted here
        end
        // else: s1 holds its value (stalled)
    end

    assign s0_ready = s1_ready;  // upstream ready tracks stage 1 ready

    // ------------------------------------------------------------------
    // Stage 1 -> Stage 2
    // ------------------------------------------------------------------
    assign s2_valid = s2_valid_r;
    assign s2_data  = s2_data_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid_r <= 1'b0;
            s2_data_r  <= '0;
        end else if (!s2_valid_r || s2_ready) begin
            // s2 accepts data when empty or being consumed
            s2_valid_r <= s1_valid;
            s2_data_r  <= s1_data;  // stage 1 transform result here
        end
    end

endmodule
```

**Key invariant:** A stage must never drop valid data. When `valid` is high but `ready`
is low, the register must hold its current value. This is enforced by the `if (!valid || ready)`
condition.

**Common mistake:** Using AXI-Stream convention but failing to hold data stable when
`valid` is high and `ready` is low. AXI4-Stream specification (A3.2.1) states: "Once
TVALID is asserted it must remain asserted until the handshake occurs."

---

### Q8. What is latency-insensitive design, and how does it relate to pipelining?

**Question:** Define latency-insensitive design. How does it differ from a stall-able pipeline,
and in what contexts is it used on FPGAs?

**Answer:**

**Latency-insensitive design (LID)** is a design methodology where each module is specified
with variable latency — the number of cycles from input to output can vary without changing
functional correctness. LID modules communicate via handshake channels and are correct for any
number of pipeline stages inserted in the communication channels.

**Key properties of LID:**
1. Any number of relay stations (pipeline stages) can be inserted between modules.
2. The overall system is correct regardless of the latency introduced.
3. Modules are "patient": they wait for valid data before producing output.

**Difference from stall-able pipeline:**
- A stall-able pipeline has a fixed number of stages with known latency bounds.
- LID allows stages to be added or removed without redesigning the protocol.
- LID is more flexible but requires more careful control logic (token flow, credit systems).

**FPGA context:** LID is primarily used in:

1. **High-Level Synthesis (HLS/Vitis HLS):** Vitis HLS generates LID-compatible AXI-Stream
   interfaces where pipeline depth varies with synthesis directives.

2. **Shell/kernel interfaces in Vitis acceleration platform:** The Vitis shell inserts variable
   numbers of pipeline stages in the AXI interconnect, and kernels must tolerate arbitrary
   latency on the `m_axi` interface.

3. **Network-on-Chip (NoC) designs:** Xilinx UltraScale+ includes a hard NoC; LID ensures
   the connected modules tolerate variable routing latency.

**Relationship to throughput vs. latency trade-off:**

LID explicitly accepts variable latency to achieve maximum throughput. The protocol ensures
that adding pipeline stages (to meet timing) never requires functional changes, only a change
in the number of cycles before the first output appears.

---

### Q9. How do you pipeline across DSP48E2 and BRAM boundaries in Vivado?

**Question:** Describe the specific techniques for integrating DSP48E2 pipeline stages and
BRAM output registers into a high-speed design pipeline, including the relevant Vivado
attributes and constraints.

**Answer:**

**DSP48E2 internal pipeline registers:**

The DSP48E2 has three configurable pipeline registers:
- `AREG`/`BREG`: Input A/B registers (0, 1, or 2 stages)
- `MREG`: Multiplier output register (0 or 1 stage)
- `PREG`: Post-adder / accumulate register (0 or 1 stage)

At 500 MHz+, all three must be enabled (latency = 3 cycles for multiply-accumulate).

```verilog
// Vivado infers DSP48E2 registers from RTL pipeline:
always_ff @(posedge clk) a_reg1 <= a;     // maps to AREG=1
always_ff @(posedge clk) a_reg2 <= a_reg1; // maps to AREG=2
always_ff @(posedge clk) prod   <= a_reg2 * b_reg; // maps to MREG=1
always_ff @(posedge clk) result <= prod + c;        // maps to PREG=1

// Attribute to prevent un-packing of DSP registers during retiming:
(* USE_DSP = "YES" *)
logic [47:0] dsp_result;
```

**Forcing DSP register inference:**

If Vivado does not infer the DSP internal registers (e.g., when intermediate signals are
used elsewhere and have fanout), force it explicitly:

```tcl
# In XDC, instruct the DSP to use all internal pipeline registers:
set_property DSP_MODE PIPE [get_cells -hier -filter {PRIMITIVE_TYPE =~ DSP*}]
```

**BRAM output register:**

Block RAM in UltraScale has a dedicated output register (`DOA_REG`/`DOB_REG`). Using it:
- Adds one cycle of read latency (2 cycles total: address register + output register).
- The output register is in the BRAM primitive, not fabric -- it runs at full BRAM timing
  without consuming a fabric FF.
- Critical for achieving >300 MHz read bandwidth.

```verilog
// RTL inference of BRAM output register:
// Two pipeline stages at the BRAM output infer DOA_REG automatically
always_ff @(posedge clk) begin
    addr_q <= addr;      // BRAM address register (internal)
end
// BRAM read data (1-cycle latency by default -- output registered = 2 cycles)
// Add the output register explicitly:
always_ff @(posedge clk) begin
    data_out_q <= bram_do;  // this should be absorbed into BRAM's DOA_REG
end
```

**Verifying DSP/BRAM pipeline absorption:**

```tcl
# After synthesis, check that pipeline registers are in primitives, not fabric:
report_utilization -cells [get_cells -hier -filter {PRIMITIVE_TYPE =~ DSP*}]
# Look for: AREG, BREG, MREG, PREG counts matching your pipeline design

# For BRAM:
report_utilization -cells [get_cells -hier -filter {PRIMITIVE_TYPE =~ RAMB*}]
# Look for: DOA_REG = 1 (output register enabled)
```

---

## Quick-Reference Summary

```
Pipelining rules for FPGA timing:
───────────────────────────────────────────────────────────────────────────
1. Insert pipeline registers to break any path with slack < 0.
2. Enable synthesis retiming (RETIMING=true) for automatic stage balancing.
3. Use phys_opt_design -directive AggressiveExplore for post-place retiming.
4. DSP48E2: use AREG=1/2, MREG=1, PREG=1 for maximum Fmax (3-cycle latency).
5. BRAM: enable output register (DOA_REG=1) for paths above 300 MHz (2-cycle latency).
6. Mark debug-probed registers with DONT_TOUCH before enabling retiming.
7. For stall-able pipelines: AXI-Stream valid/ready handshake -- never drop valid data.
8. Latency = total clock cycles through all pipeline stages.
9. Throughput = 1 result per clock cycle once pipeline is full (pipelined designs).
───────────────────────────────────────────────────────────────────────────

Fmax calculation:
  T_clock >= T_clk2q + T_comb + T_setup + T_skew
  Fmax = 1 / T_clock
  Stages needed = ceil(T_comb_original / (T_clock_target - T_clk2q - T_setup))
───────────────────────────────────────────────────────────────────────────
```
