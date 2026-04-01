# Problem 01: Timing Failure Debug

**Difficulty:** Intermediate to Advanced  
**Skills tested:** Timing report interpretation, root cause analysis, systematic debugging, tool familiarity  
**Typical interview context:** Given as a whiteboard/laptop exercise or verbal walkthrough at senior engineer level

---

## Scenario

You have just completed a full Vivado implementation run on a new design targeting a Xilinx Virtex UltraScale+ VU9P at 400 MHz. The design is a pipelined signal processing engine with the following structure:

```
input_capture (clk_400)
    └── fir_filter_bank (clk_400)
            └── magnitude_calc (clk_400)
                    └── output_formatter (clk_400)

axi_ctrl (clk_100, generated from MMCM)
    └── (writes configuration registers read by fir_filter_bank)
```

The MMCM takes a 200 MHz board clock and generates 400 MHz and 100 MHz outputs.

`report_timing_summary` produces:

```
Design Timing Summary
---------------------------------------------------------------------------
WNS(ns)  TNS(ns)   WHS(ns)   THS(ns)  WPWS(ns) TPWS(ns)
-------  -------   -------   -------  -------- --------
 -1.342  -87.420    0.065     0.000     0.312    0.000

All user specified timing constraints are met.
```

You also observe:

```
Timing constraints are met.
No timing constraints have negative slack.
```

Wait — those two statements contradict each other. The timing summary shows WNS = -1.342 ns, but the tool says constraints are met. You then run:

```tcl
report_timing -delay_type max -max_paths 1 -nworst 1 -path_type full_clock_expanded
```

The worst path output is:

```
Path Group:  CLK_400
Path Type:   Setup (Max at Slow Process Corner)

Slack:       -1.342ns

Source:      fir_filter_bank/coeff_mux/sel_reg[2]
             (rising edge-triggered cell FDRE clocked by clk_400)
Destination: fir_filter_bank/tap_delay/data_reg[47]
             (rising edge-triggered cell FDRE clocked by clk_400)

Requirement: 2.500ns  (clk_400 rise@2.500ns - clk_400 rise@0.000ns)

Data Path Delay:    3.718ns  (logic 1.891ns   routing 1.827ns)
Clock Path Skew:    0.124ns  (DCD - SCD + CPP)

Logic Levels:    9  (LUT3=1 LUT4=2 LUT5=1 LUT6=5)
```

---

## Part 1: The Contradiction — What Is Happening?

**Q: The timing summary shows WNS = -1.342 ns (a failing path) but the tool reports "All user specified timing constraints are met." How can both statements be true?**

**A:**

This is one of the most important subtleties in Vivado timing analysis and catches many engineers by surprise.

**The answer:** The failing path is in a clock domain that has **no user-defined timing constraint.** The path exists in `CLK_400` but `clk_400` was either:

1. **Not defined with `create_clock`** — The MMCM output is floating with no constraint.
2. **Defined as a generated clock without referencing its master** — The timing engine has no frequency context.
3. **Excluded from analysis by a broad `set_false_path` or `set_clock_groups` statement.**

When a clock has no constraint, Vivado performs timing analysis using a **default period assumption** (usually the tool's "assumed worst" or simply the minimum feasible period). The path still shows up in `report_timing` but is classified as **unconstrained** — which means no user-specified constraint is violated, even though the path has negative slack.

**How to confirm this:**

```tcl
# Check if clk_400 is defined
report_clocks
# Expected: clk_400 should appear. If it does not, it is missing.

# Check for unconstrained paths
check_timing -verbose
# Will report: "No clock is defined on net mmcm_inst/CLKOUT0"
# or similar warnings about missing clocks

# Check the failing path's clock definition
report_timing -delay_type max -max_paths 1 -path_type full_clock_expanded
# Look at the "Clock Path:" section. Does it show a real BUFG path
# from a defined create_clock source?
```

**Root cause in this scenario:**

The XDC file has:
```tcl
create_clock -name clk_in -period 5.000 [get_ports clk_in_200_p]
create_generated_clock -name clk_100 -source [get_pins mmcm_inst/CLKIN1] \
                       -divide_by 2 [get_pins mmcm_inst/CLKOUT1]
# clk_400 is MISSING — the 400 MHz output was added to the MMCM later
# but the XDC was not updated
```

The engineer added the 400 MHz MMCM output when adding `fir_filter_bank` to the design but forgot to add the corresponding `create_generated_clock` for `CLKOUT0`. Vivado inferred a default clock on that net, ran timing analysis, found violations, but because no user constraint exists, reported "user constraints are met."

**Fix:**

```tcl
# Add to XDC:
create_generated_clock -name clk_400 \
                       -source [get_pins mmcm_inst/CLKIN1] \
                       -multiply_by 2 \
                       [get_pins mmcm_inst/CLKOUT0]

# After the BUFG on the 400 MHz path:
create_generated_clock -name clk_400_buf \
                       -source [get_pins mmcm_inst/CLKOUT0] \
                       -divide_by 1 \
                       [get_pins bufg_400/O]
```

After re-implementing with the corrected constraint, the timing summary will correctly show the violations as real failures against the `clk_400` constraint.

---

## Part 2: Diagnosing the Failing Path

**Q: With the constraint now correctly applied, the same path still fails. Analyse the timing report excerpt above and determine the root cause. What is the minimum number of logic levels achievable for a typical FIR filter tap selection path, and what is the fix?**

**A:**

**Timing budget analysis:**

```
Clock period:          2.500 ns  (400 MHz)
Data path delay:       3.718 ns  (exceeds period by 1.218 ns before clock adjustments)
Clock skew:           +0.124 ns  (captures clock arrives 0.124 ns late → helps nothing here,
                                  it is positive skew from the source perspective, hurting setup)
                                  Wait — positive skew at capture means capture is later, which
                                  helps. Let's re-check: DCD - SCD + CPP. If skew = +0.124 ns,
                                  the requirement increases by 0.124 ns relative to ideal.
                                  Actually check:
                                  Slack = Req - DataPath = 2.500 - 3.718 + skew_adj...
                                  The negative slack of 1.342 accounts for all factors.

Slack:                -1.342 ns  (data arrives 1.342 ns too late)
Logic delay:           1.891 ns  (50.9% of path — significant)
Routing delay:         1.827 ns  (49.1% of path — also significant)
Logic levels:          9 LUTs
```

**The problem is logic depth: 9 LUT levels in a 2.5 ns period.**

At 400 MHz, the maximum allowable data path (accounting for FF clock-to-Q ~0.15 ns, FF setup ~0.10 ns, and clock skew) is approximately:

```
T_logic_max ≈ T_period - T_clk2q - T_setup - T_routing_budget
           ≈ 2.500 - 0.150 - 0.100 - 0.800  (estimating 0.8 ns routing for a clean path)
           ≈ 1.450 ns for logic
```

9 LUT levels at ~0.21 ns per LUT = ~1.89 ns of logic. This needs to be reduced to approximately 6 levels to meet timing.

**Interpretation of the path logic:**

`sel_reg[2]` is a 3-bit mux select register driving `data_reg[47]` through 9 levels. In a FIR filter:
- The coefficient mux selects one of N coefficients based on `sel`
- The selected coefficient is then applied to the tap data

A 9-level LUT path for a mux select suggests the MUX is implemented as a priority encoder tree, which is inefficient. A 4:1 MUX requires 2 LUT levels. An 8:1 MUX requires 3 LUT levels with LUT6s.

**Step-by-step fix:**

**Step 1: Understand the logic structure**

```tcl
# View the schematic of the critical path in Vivado
show_schematic [get_timing_paths -delay_type max -max_paths 1]
```

**Step 2: Pipeline the coefficient selection**

Add a register after the MUX select decoding, before the coefficient multiplication:

```verilog
// Before (single-cycle mux to data pipe — 9 levels)
module coeff_mux_bad #(parameter NTAPS = 64)(
    input  logic        clk,
    input  logic [5:0]  sel,
    input  logic [15:0] coeff [0:NTAPS-1],
    output logic [15:0] selected_coeff
);
    // 64:1 MUX in a single level → synthesises to 9 LUT levels
    always_ff @(posedge clk)
        selected_coeff <= coeff[sel];
endmodule

// After: register the select, then apply (adds 1 cycle latency)
module coeff_mux_good #(parameter NTAPS = 64)(
    input  logic        clk,
    input  logic [5:0]  sel,
    input  logic [15:0] coeff [0:NTAPS-1],
    output logic [15:0] selected_coeff
);
    // Stage 1: register the selection address
    logic [5:0] sel_d;
    always_ff @(posedge clk)
        sel_d <= sel;

    // Stage 2: apply registered select to coefficients
    // Synthesis sees a registered select → can use SRL or carry-chain
    always_ff @(posedge clk)
        selected_coeff <= coeff[sel_d];
endmodule
```

**Step 3: Consider BRAM inference for the coefficient table**

If NTAPS is large, the coefficient array should be stored in a BRAM, not in distributed LUT RAM. BRAM access is 1 clock cycle (with output register) and does not consume LUT logic:

```verilog
// Infer BRAM for coefficient storage
// The read path becomes: sel_reg → BRAM_ADDR → BRAM_DOUT (1 or 2 cycles)
// This eliminates the LUT-based MUX entirely
logic [15:0] coeff_bram [0:NTAPS-1];
initial $readmemh("coefficients.hex", coeff_bram);

always_ff @(posedge clk)
    selected_coeff <= coeff_bram[sel];  // synthesiser infers BRAM
```

**Step 4: Re-synthesise and re-implement**

```tcl
synth_design -top fir_filter_bank -directive PerformanceOptimized -retiming
impl_design
report_timing_summary
```

Expected result: the coefficient selection path now has 1–2 LUT levels (the BRAM output registers plus one small decode stage), comfortably meeting 2.5 ns.

---

## Part 3: The AXI CDC Path

**Q: `report_cdc` produces the following warning:**

```
Critical Warning [CDC-1]: No synchronizer found between source clock 'clk_100' and
destination clock 'clk_400' for path:
  Source:      axi_ctrl/config_regs/coeff_update_reg
  Destination: fir_filter_bank/coeff_array/wr_en_reg
```

**Explain what this means, why it is dangerous, and write the fix.**

**A:**

**What it means:**

A flip-flop in the `axi_ctrl` module (clocked by `clk_100`, 100 MHz) drives a flip-flop in `fir_filter_bank` (clocked by `clk_400`, 400 MHz) without any synchronisation. The `coeff_update` control signal changes at 100 MHz rates and is directly sampled by a 400 MHz flip-flop. The two clocks are asynchronous (even though one is a multiple of the other, unless they share a MMCM output with phase alignment — and even then, the relative phase is not guaranteed to be consistent over temperature and voltage).

**Why it is dangerous:**

When the source flip-flop (`coeff_update_reg`) transitions, the destination flip-flop (`wr_en_reg`) may capture the signal during its metastability window. The metastable output of `wr_en_reg` propagates through the FIR filter's coefficient write path, potentially:
- Corrupting the coefficient RAM contents
- Writing incorrect data at an incorrect address
- Causing intermittent failures that only appear in certain operating conditions

This will not show up in simulation (simulators assume discrete logic levels). It is a hardware-only bug.

**The fix — two-flop synchroniser plus handshake:**

For a single control bit (`coeff_update` as a write enable pulse), a two-flop synchroniser is appropriate:

```verilog
// In the destination clock domain (clk_400):
// Two-flop synchroniser for the write-enable signal from clk_100

module cdc_sync_single_bit (
    input  logic src_clk,    // source clock (not used in synchroniser, but good practice to declare)
    input  logic dst_clk,
    input  logic rst_n,
    input  logic src_data,
    output logic dst_data
);
    // DONT_TOUCH prevents synthesis/implementation from merging or replicating these FFs
    (* DONT_TOUCH = "TRUE" *) logic sync_ff1, sync_ff2;

    always_ff @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= src_data;
            sync_ff2 <= sync_ff1;
        end
    end

    assign dst_data = sync_ff2;
endmodule
```

However, a write enable is a multi-cycle operation — the write address and data must also cross the CDC boundary safely. A pulse from `clk_100` may be only 10 ns wide (1 cycle at 100 MHz), which is only 4 cycles at 400 MHz. A two-flop synchroniser on the enable alone is insufficient if the data bus also crosses the boundary.

**For multi-bit CDC (data + enable):**

```verilog
// Option A: Gray-coded counter or FIFO (for streaming data)
// Option B: Handshake protocol for configuration register updates

// 4-phase handshake (suitable for low-rate config updates):
// Source (clk_100): Assert req, wait for ack, deassert req, wait for ack low
// Destination (clk_400): Detect req rising edge, sample data, assert ack
module cdc_handshake_write #(parameter WIDTH = 16)(
    input  logic             src_clk,
    input  logic             dst_clk,
    input  logic             rst_n,
    // Source-side interface
    input  logic             src_valid,    // pulse: data is valid
    input  logic [WIDTH-1:0] src_data,
    output logic             src_ready,    // source may send next data
    // Destination-side interface
    output logic             dst_valid,    // data is valid in dst domain
    output logic [WIDTH-1:0] dst_data
);
    // ... (full implementation in the CDC design techniques module)
endmodule
```

**XDC fix — false path from src flip-flop to synchroniser input:**

```tcl
# The path from axi_ctrl/config_regs/coeff_update_reg to the synchroniser
# input is genuinely asynchronous — apply false path to suppress STA check
set_false_path -from [get_cells {axi_ctrl/config_regs/coeff_update_reg}] \
               -to   [get_cells {fir_filter_bank/cdc_sync/sync_ff1_reg}]
```

After adding the synchroniser and the false path constraint, re-run `report_cdc`. The Critical Warning should be resolved.

---

## Summary: The Debugging Workflow

The three issues in this scenario represent the three most common categories of timing failure debug in industry:

| Issue | Category | Root Cause | Fix |
|---|---|---|---|
| Constraint not applied | Missing constraint | `create_generated_clock` omitted | Add the missing constraint |
| Path too slow | Logic depth | 9-level MUX combinational path | Pipeline with BRAM inference |
| CDC without synchroniser | Clock domain crossing | Missing two-flop synchroniser | Add synchroniser + false path |

**Interview lesson:** When a timing report seems contradictory (failures but "constraints met"), always check for missing clock constraints with `report_clocks` and `check_timing -verbose`. This diagnostic instinct is a clear differentiator between engineers with real debugging experience and those without.
