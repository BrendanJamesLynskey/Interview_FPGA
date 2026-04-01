# Resource Sharing

## Overview

Resource sharing is the practice of time-multiplexing expensive hardware resources — such as
multipliers, adders, dividers, or memory ports — across multiple computations that do not need
to occur simultaneously. On FPGAs, where resources are finite and fixed, resource sharing is a
primary technique for reducing LUT, DSP, and BRAM utilisation at the cost of throughput.
Understanding the area-speed trade-off and when synthesis tools apply sharing automatically
(or fail to) is essential for FPGA design interviews.

---

## Fundamentals

### Q1. What is resource sharing, and what is the fundamental trade-off it introduces?

**Question:** Define resource sharing in the context of FPGA design. State the trade-off
between area and throughput, and explain when sharing is appropriate.

**Answer:**

**Definition:** Resource sharing assigns a single physical hardware resource (e.g., one
DSP48 multiplier) to serve multiple logical operations by time-multiplexing the inputs and
outputs using multiplexers.

```
Without sharing (three independent multipliers):
  result_a = a * coeff_a;     -> DSP48 #1
  result_b = b * coeff_b;     -> DSP48 #2
  result_c = c * coeff_c;     -> DSP48 #3
  All three compute every cycle. Area: 3 DSPs. Throughput: 3 results/cycle.

With sharing (one multiplier, time-multiplexed):
  Cycle 0: MUX selects a, coeff_a -> DSP -> result_a
  Cycle 1: MUX selects b, coeff_b -> DSP -> result_b
  Cycle 2: MUX selects c, coeff_c -> DSP -> result_c
  Area: 1 DSP + MUX logic. Throughput: 1 result per 3 cycles.
```

**The fundamental trade-off:**

| Parameter | Effect of sharing |
|---|---|
| Area | Reduces (fewer instances of expensive primitive) |
| Throughput | Reduces (N computations take N cycles) |
| Latency | May increase (must wait for allocated time slot) |
| Control complexity | Increases (MUX select, scheduling FSM) |
| Clock frequency | May decrease (MUX adds combinational delay before resource) |
| Power | Decreases (fewer primitives switching) |

**When resource sharing is appropriate:**

- The computation rate required is lower than the clock frequency (throughput slack exists).
- The shared resource is a high-cost primitive (DSP48, BRAM port, serdes lane).
- Area is the primary constraint (e.g., fitting design into a smaller FPGA device).
- Multiple computations are provably non-simultaneous (e.g., state-machine driven operations).

**When sharing is inappropriate:**

- Maximum throughput is required (one result per cycle).
- The design is already area-unconstrained.
- The MUX overhead is comparable to the resource being saved.

---

### Q2. How does Vivado synthesis decide to share operators automatically, and when does it fail to share?

**Question:** Describe the conditions under which Vivado's synthesiser shares arithmetic
operators without explicit direction. What coding styles prevent automatic sharing?

**Answer:**

Vivado synthesis applies resource sharing when:

1. **Multiple instances of the same operator type** exist in the same process block or module.
2. **The operators are mutually exclusive** (only one executes per clock cycle, e.g., in
   different branches of a case statement or if-else tree).
3. **The operands are the same width** (sharing requires identical resource type).
4. **No `use_dsp` or `keep` constraint** prevents sharing.

```systemverilog
// Case 1: Synthesis WILL share -- mutually exclusive in case statement
// Two multiplications, only one executes per cycle
always_comb begin
    unique case (sel)
        2'b00: result = a * b;    // multiplication 1
        2'b01: result = c * d;    // multiplication 2
        // Synthesis: ONE DSP48, with MUX on inputs
        default: result = '0;
    endcase
end

// Case 2: Synthesis will NOT share -- concurrent, both execute every cycle
logic [15:0] p1, p2;
assign p1 = a * b;    // always active -> needs DSP #1
assign p2 = c * d;    // always active -> needs DSP #2
// Cannot share: both must produce a result every cycle

// Case 3: Synthesis may FAIL to share -- in separate always blocks
// Some tools do not share across always block boundaries
always_comb begin
    if (mode == 2'b00)
        out1 = x * y;
end
always_comb begin
    if (mode == 2'b01)
        out2 = x * z;
end
// Synthesis tool sees two separate processes -- may not combine even though
// mode==00 and mode==01 are mutually exclusive
```

**Coding styles that prevent sharing:**

1. **Separate continuous assigns:** `assign p1 = a*b; assign p2 = c*d;` are always concurrent.
2. **Separate always blocks:** Tools rarely share across process boundaries.
3. **`USE_DSP = "YES"` attribute on both operators:** Forces each onto its own DSP.
4. **Different operand widths:** An 8-bit multiply and a 16-bit multiply use different DSP
   configurations and cannot share.
5. **Intermediate pipeline registers between operations:** Breaks the combinational sharing
   opportunity.

---

### Q3. What is operator sharing vs. memory port sharing? Give an example of each.

**Question:** Distinguish between arithmetic operator sharing and memory port sharing.
Provide a concrete RTL example for each.

**Answer:**

**Operator sharing** reuses a computation unit (adder, multiplier, comparator) for multiple
operations at different times.

```systemverilog
// Arithmetic operator sharing: one adder computes three different sums
// Based on a 3-cycle FSM, each sum is computed in a different cycle

module shared_adder #(parameter int W = 16) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [W-1:0] a, b, c, d, e, f,
    output logic [W-1:0] sum_ab, sum_cd, sum_ef,
    output logic         done
);
    typedef enum logic [1:0] { CALC_AB, CALC_CD, CALC_EF, IDLE } state_t;
    state_t state;

    logic [W-1:0] op_a, op_b;     // shared adder inputs
    logic [W-1:0] adder_result;   // shared adder output

    assign adder_result = op_a + op_b;  // ONE adder instance

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= CALC_AB;
            done   <= 1'b0;
            sum_ab <= '0;
            sum_cd <= '0;
            sum_ef <= '0;
        end else begin
            done <= 1'b0;
            unique case (state)
                CALC_AB: begin
                    op_a   <= a;
                    op_b   <= b;
                    sum_ab <= adder_result;  // capture previous cycle result
                    state  <= CALC_CD;
                end
                CALC_CD: begin
                    op_a   <= c;
                    op_b   <= d;
                    sum_cd <= adder_result;
                    state  <= CALC_EF;
                end
                CALC_EF: begin
                    op_a   <= e;
                    op_b   <= f;
                    sum_ef <= adder_result;
                    done   <= 1'b1;
                    state  <= CALC_AB;
                end
            endcase
        end
    end
endmodule
// Area: 1 adder + FSM + MUX. Throughput: 1 set of results every 3 cycles.
// Compared to 3 adders with 1 set per cycle.
```

**Memory port sharing** reuses read or write ports of a BRAM across multiple logical access
streams that cannot be active simultaneously.

```systemverilog
// Memory port sharing: one BRAM read port serves two lookup tables
// Both lookups happen in different clock phases (controlled by arbitration FSM)

module shared_bram_port #(
    parameter int ADDR_W = 10,
    parameter int DATA_W = 16
) (
    input  logic               clk,
    input  logic               rst_n,

    // Consumer A (read lookup table A)
    input  logic               req_a,
    input  logic [ADDR_W-1:0]  addr_a,
    output logic [DATA_W-1:0]  rdata_a,
    output logic               ack_a,

    // Consumer B (read lookup table B -- different address space, same BRAM)
    input  logic               req_b,
    input  logic [ADDR_W-1:0]  addr_b,
    output logic [DATA_W-1:0]  rdata_b,
    output logic               ack_b
);
    // Shared BRAM port
    logic [ADDR_W-1:0]  bram_addr;
    logic [DATA_W-1:0]  bram_dout;
    logic               bram_en;

    // Arbitration: simple round-robin, A has priority on contention
    logic  pending;
    logic  serving_a;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_a    <= 1'b0;
            ack_b    <= 1'b0;
            bram_en  <= 1'b0;
            pending  <= 1'b0;
            serving_a <= 1'b0;
        end else begin
            ack_a <= 1'b0;
            ack_b <= 1'b0;
            if (req_a) begin
                bram_addr  <= addr_a;
                bram_en    <= 1'b1;
                serving_a  <= 1'b1;
                pending    <= req_b;   // remember if B was also pending
            end else if (req_b) begin
                bram_addr  <= addr_b;
                bram_en    <= 1'b1;
                serving_a  <= 1'b0;
                pending    <= 1'b0;
            end else begin
                bram_en <= 1'b0;
            end
            // One cycle later: data is available
            if (bram_en) begin
                if (serving_a) ack_a <= 1'b1;
                else           ack_b <= 1'b1;
            end
        end
    end

    // Demultiplex BRAM output
    assign rdata_a = (serving_a) ? bram_dout : '0;
    assign rdata_b = (!serving_a) ? bram_dout : '0;

    // BRAM instantiation (inferred)
    (* RAM_STYLE = "BLOCK" *)
    logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    always_ff @(posedge clk) begin
        if (bram_en) bram_dout <= mem[bram_addr];
    end
endmodule
```

---

## Intermediate

### Q4. Walk through a worked example of replacing three parallel multipliers with one shared multiplier, comparing area and throughput.

**Question:** A signal processing block multiplies three independent inputs by fixed coefficients
every 8 clock cycles (triggered by a `calc_en` pulse). The target FPGA has a limited DSP count.
Show the transformation from parallel to shared implementation.

**Answer:**

**Original (parallel) implementation:**

```systemverilog
// Three independent multipliers, each consuming one DSP48
module parallel_mult (
    input  logic signed [15:0] x0, x1, x2,
    output logic signed [31:0] y0, y1, y2
);
    localparam signed [15:0] C0 = 16'h1234;
    localparam signed [15:0] C1 = 16'hABCD;
    localparam signed [15:0] C2 = 16'h5678;

    assign y0 = x0 * C0;   // DSP #1 -- always active
    assign y1 = x1 * C1;   // DSP #2 -- always active
    assign y2 = x2 * C2;   // DSP #3 -- always active
endmodule
// Resources: 3 DSP48, minimal LUT
// Throughput: 3 results per cycle
```

**Shared implementation (triggered every 8 cycles):**

```systemverilog
module shared_mult (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               calc_en,        // pulses every 8 cycles
    input  logic signed [15:0] x0, x1, x2,
    output logic signed [31:0] y0, y1, y2,
    output logic               result_valid    // pulses when y0/y1/y2 are ready
);
    localparam signed [15:0] C0 = 16'h1234;
    localparam signed [15:0] C1 = 16'hABCD;
    localparam signed [15:0] C2 = 16'h5678;

    typedef enum logic [2:0] { IDLE, MULT0, MULT1, MULT2, DONE } state_t;
    state_t state;

    // Shared multiplier inputs and output
    logic signed [15:0] mult_a;
    logic signed [15:0] mult_b;
    logic signed [31:0] mult_result;

    assign mult_result = mult_a * mult_b;  // ONE DSP48

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            result_valid <= 1'b0;
            y0 <= '0; y1 <= '0; y2 <= '0;
        end else begin
            result_valid <= 1'b0;
            unique case (state)
                IDLE: begin
                    if (calc_en) begin
                        mult_a <= x0;
                        mult_b <= C0;
                        state  <= MULT0;
                    end
                end
                MULT0: begin
                    y0     <= mult_result;   // latch result from previous cycle
                    mult_a <= x1;
                    mult_b <= C1;
                    state  <= MULT1;
                end
                MULT1: begin
                    y1     <= mult_result;
                    mult_a <= x2;
                    mult_b <= C2;
                    state  <= MULT2;
                end
                MULT2: begin
                    y2           <= mult_result;
                    result_valid <= 1'b1;
                    state        <= IDLE;
                end
            endcase
        end
    end
endmodule
```

**Comparison:**

| Metric | Parallel | Shared |
|---|---|---|
| DSP48 count | 3 | 1 |
| LUT count | ~0 | ~50 (FSM + MUX) |
| Throughput | 3 results / cycle | 3 results / 3 cycles |
| Latency from calc_en | 1 cycle | 3 cycles |
| Correct for 8-cycle interval? | Yes | Yes (3 cycles < 8) |
| Suitable if calc_en is every cycle? | Yes | No (would need 3 cycles) |

**The shared implementation is correct** because `calc_en` pulses every 8 cycles, leaving
5 idle cycles. The 3-cycle computation fits comfortably within the 8-cycle budget.

---

### Q5. How does operator sharing interact with pipelining, and how do you avoid unintentional sharing?

**Question:** Explain why pipelining can conflict with operator sharing. Give a concrete example
of how to prevent unintended sharing when the synthesiser is too aggressive.

**Answer:**

**The conflict:** Pipelining places a register between two operations, making them appear
sequential. If two pipelined computations use the same operator type and the synthesiser
detects they are in the same state, it may attempt to share — introducing a combinational MUX
that increases the path delay and defeats the purpose of the pipeline stage.

```systemverilog
// Intended: two independent pipelined multiplications for maximum throughput
always_ff @(posedge clk) begin
    p1 <= a * b;    // pipeline register -- intended as DSP #1
    p2 <= c * d;    // pipeline register -- intended as DSP #2
end
// Synthesiser sees: two concurrent multiplications in the same always_ff block
// If sharing is enabled, it may infer ONE multiplier with MUX -- WRONG for throughput
```

**Preventing unintended sharing:**

```verilog
// Method 1: USE_DSP attribute forces each assignment to its own DSP
(* USE_DSP = "YES" *) logic signed [31:0] p1;
(* USE_DSP = "YES" *) logic signed [31:0] p2;

always_ff @(posedge clk) begin
    p1 <= a * b;
    p2 <= c * d;
end

// Method 2: Separate the computations into separate module instances
// (sharing rarely crosses module boundaries)
mult_unit #(.W(16)) u_mult1 (.a(a), .b(b), .clk(clk), .p(p1));
mult_unit #(.W(16)) u_mult2 (.a(c), .b(d), .clk(clk), .p(p2));

// Method 3: Use resource_sharing synthesis directive (Vivado property)
// Set on individual cells or globally per module:
set_property resource_sharing off [get_cells u_my_pipeline/*]
```

**Detecting unintended sharing:**

```tcl
# After synthesis, check the DSP count
report_utilization -cells [get_cells -hier -filter {PRIMITIVE_TYPE =~ DSP*}]
# Expected: 2 DSPs. If only 1 is reported, sharing has occurred.

# Vivado synthesis log also reports:
# "INFO: [Synth 8-802] inferred ...multipliers" -- check this count
```

---

### Q6. Describe time-multiplexed memory architectures for FPGA resource reduction.

**Question:** A design requires 16 independent 256-entry lookup tables of 8-bit data.
Show how BRAM sharing can reduce the BRAM count from 16 to 1, and describe the timing impact.

**Answer:**

**Naive implementation:** 16 independent Block RAMs.

Each lookup table is 256 x 8 bits = 2 Kbits. A Xilinx UltraScale RAMB18 has 18 Kbits,
so each LUT uses 1/9 of a RAMB18. 16 LUTs = 16 RAMB18 instances, of which each uses
only 11% capacity.

**Shared implementation:** One RAMB18 with all 16 tables packed sequentially.

```
Memory map in shared BRAM:
  Addresses 0x000 - 0x0FF : Table 0 data (256 entries)
  Addresses 0x100 - 0x1FF : Table 1 data (256 entries)
  ...
  Addresses 0xF00 - 0xFFF : Table 15 data (256 entries)
  Total: 4096 entries x 8 bits = 32 Kbits -> one RAMB36 (or two RAMB18s)
```

```systemverilog
module shared_lut_bram #(
    parameter int NUM_TABLES  = 16,   // number of LUTs
    parameter int ENTRY_COUNT = 256,  // entries per table
    parameter int DATA_WIDTH  = 8
) (
    input  logic                            clk,
    input  logic [$clog2(NUM_TABLES)-1:0]  table_sel,
    input  logic [$clog2(ENTRY_COUNT)-1:0] addr,
    output logic [DATA_WIDTH-1:0]           data_out
);
    // BRAM address is: {table_sel, addr}
    localparam int BRAM_ADDR_W = $clog2(NUM_TABLES) + $clog2(ENTRY_COUNT);
    localparam int BRAM_DEPTH  = NUM_TABLES * ENTRY_COUNT;

    // Inferred BRAM
    (* RAM_STYLE = "BLOCK" *)
    logic [DATA_WIDTH-1:0] mem [0:BRAM_DEPTH-1];

    logic [BRAM_ADDR_W-1:0] full_addr;
    assign full_addr = {table_sel, addr};

    // BRAM read with output register (2 cycles latency)
    logic [DATA_WIDTH-1:0] bram_do;
    always_ff @(posedge clk) begin
        bram_do  <= mem[full_addr];  // cycle 1: BRAM read
        data_out <= bram_do;         // cycle 2: output register (DOA_REG)
    end

    // Initialise BRAM contents via $readmemh in simulation / .coe in Vivado IP
    initial $readmemh("lut_contents.hex", mem);
endmodule
```

**Timing impact:**

| Metric | 16 BRAMs | 1 BRAM (shared) |
|---|---|---|
| BRAM count | 16 RAMB18 | 1 RAMB36 |
| Read latency | 2 cycles (with output reg) | 2 cycles (identical) |
| Read throughput | 16 simultaneous reads/cycle | 1 read/cycle |
| If reads are serialised | 1 read/cycle each (waste) | 1 read/cycle (efficient) |
| Suitable when all 16 tables need concurrent access? | Yes | No |
| Suitable when only 1 table is accessed per cycle? | Yes (wasteful) | Yes (optimal) |

**For concurrent access:** If all 16 tables must be read in the same cycle, the shared BRAM
approach fails. In that case, the correct alternative is a wide BRAM (using the 16 data
as a 128-bit wide, 256-deep memory) read in one cycle, or distributed RAM for small tables.

---

## Advanced

### Q7. How does Vivado's `resource_sharing` synthesis option work, and how do you use it selectively?

**Question:** Describe the `resource_sharing` Vivado synthesis property, its scope, and
demonstrate selective application to control which operators are shared.

**Answer:**

Vivado's `resource_sharing` property controls whether the synthesiser attempts to share
operators (multipliers, comparators, etc.) across mutually exclusive branches.

**Scope of `resource_sharing`:**

The property can be applied at three levels:

```tcl
# 1. Global (all synthesis runs):
set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on [get_runs synth_1]

# 2. Per-module (in XDC or synthesis constraints):
set_property resource_sharing off [get_cells u_high_throughput_path/*]

# 3. Per-operator in RTL (synthesis attribute):
```

```verilog
// In RTL: prevent sharing on specific operators
// (operator must be the direct result of the always block assignment)

// Force two separate DSPs:
(* resource_sharing = "no" *)
logic [31:0] product_a;
(* resource_sharing = "no" *)
logic [31:0] product_b;

always_ff @(posedge clk) begin
    product_a <= x * coeff_a;
    product_b <= y * coeff_b;
end

// Allow sharing on these (Vivado default):
logic [31:0] result;
always_comb begin
    unique case (opcode)
        2'b00: result = a * b;
        2'b01: result = c * d;
    endcase
end
```

**Selective strategy for mixed designs:**

In a design with both high-throughput data paths and low-rate control computations:

```tcl
# Disable sharing on the datapath (performance-critical, pipelined):
set_property resource_sharing off [get_cells datapath_inst/*]

# Enable sharing on the control logic (compute-light, area-constrained):
set_property resource_sharing on [get_cells ctrl_inst/*]
```

**When Vivado's automatic sharing is insufficient:**

Automatic sharing is limited to operators within a single module. For sharing across module
boundaries or complex time-multiplexed schedules, explicit RTL sharing (FSM-based, as shown
in Q4) is required.

---

### Q8. Describe the area vs. speed design space for an FIR filter, showing how to move along the trade-off curve.

**Question:** An N-tap FIR filter needs to be implemented at four different throughput
requirements (full-rate, 1/2 rate, 1/4 rate, 1/8 rate). Describe the implementation
for each and the area-speed trade-off at each operating point.

**Answer:**

```
FIR filter: y[n] = sum(h[k] * x[n-k]) for k=0..N-1
N = 64 taps, 16-bit coefficients, 16-bit data
Target: UltraScale FPGA
```

**Point 1: Full-rate (one sample per clock cycle)**

Architecture: Fully parallel multiplier tree.
- 64 DSP48E2 multipliers (one per tap).
- Binary adder tree: 63 adders in 6 levels.
- Total: 64 DSPs + ~126 LUTs (adder tree).
- Fmax: ~500 MHz with full 3-stage DSP pipeline.
- Throughput: 1 sample/cycle.

**Point 2: Half-rate (one sample per 2 clock cycles)**

Architecture: Two-way time-multiplexed multiplier bank.
- 32 DSP48E2 multipliers, each computing 2 taps alternately.
- Requires 2-cycle accumulate mode or separate accumulate register.
- Total: 32 DSPs + ~50 LUTs (control + mux).
- Fmax: same 500 MHz (same paths, fewer instances).
- Throughput: 1 sample / 2 cycles.

**Point 3: Quarter-rate (one sample per 4 clock cycles)**

Architecture: Four-way time-multiplexed.
- 16 DSP48E2 multipliers, each computing 4 taps.
- Each multiplier runs 4 consecutive multiply-accumulate operations.
- Adder tree: parallel accumulation of 16 partial sums (4 levels).
- Total: 16 DSPs + ~30 LUTs.
- Throughput: 1 sample / 4 cycles.

**Point 4: Minimum area (one DSP48, sequential)**

Architecture: Single multiply-accumulate engine.
- 1 DSP48E2 multiplier with accumulate mode.
- Coefficient ROM: one BRAM (64 x 16-bit coefficients).
- Delay line: 64 x 16-bit shift register (8 SRL32s or 2 RAMB18s).
- Requires 64 clock cycles to compute one output sample.
- Total: 1 DSP + 1-2 BRAMs + ~20 LUTs (FSM).
- Throughput: 1 sample / 64 cycles (must have clock >> sample rate by 64x).

**Summary table:**

| Configuration | DSPs | BRAMs | LUTs | Throughput | Area |
|---|---|---|---|---|---|
| Full parallel | 64 | 0 | ~126 | 1/cycle | Largest |
| Half-rate | 32 | 0 | ~50 | 1/2 cycles | Medium |
| Quarter-rate | 16 | 0 | ~30 | 1/4 cycles | Medium-small |
| Single MAC | 1 | 1-2 | ~20 | 1/64 cycles | Smallest |

**Practical decision:** For a 10 MSPS audio filter at 100 MHz clock, the system has 10
clock cycles per sample. With 64 taps, only the single-MAC architecture requires more cycles
than available. The quarter-rate (4 cycles/sample) architecture with 16 DSPs fits easily and
leaves substantial clock budget for other logic.

---

## Quick-Reference Summary

```
Resource Sharing Decision Criteria:
───────────────────────────────────────────────────────────────────────────
Share when:
  - Throughput requirement < clock frequency / N (N operations can be serialised)
  - Saving high-cost resources (DSP, BRAM) is a priority
  - Operations are provably mutually exclusive (FSM states, case branches)
  - Area or power is the binding constraint

Do NOT share when:
  - Maximum throughput is required (one result per cycle)
  - Pipeline stages would be broken by MUX insertion
  - The MUX cost exceeds the resource saving
  - Operations are concurrent (always active)

Vivado controls:
  resource_sharing on/off per cell or globally
  USE_DSP = "YES" to force individual DSP allocation
  resource_sharing = "no" attribute in RTL to prevent sharing on a signal

Common pitfalls:
  - Pipelining defeats sharing (registering intermediate values breaks mutual exclusivity)
  - Cross-module sharing does not happen automatically
  - Memory port sharing requires explicit arbitration logic
───────────────────────────────────────────────────────────────────────────
```
