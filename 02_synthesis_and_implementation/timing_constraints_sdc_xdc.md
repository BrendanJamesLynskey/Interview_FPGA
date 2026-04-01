# Timing Constraints: SDC and XDC

Timing constraints are the specification you give the timing analysis engine describing how fast signals must travel and which paths are valid. Getting them right is one of the most consequential — and frequently botched — skills in FPGA design. An interview in this area tests whether you understand the semantics of each constraint, not just the syntax.

---

## Table of Contents

- [Fundamentals](#fundamentals)
- [Intermediate](#intermediate)
- [Advanced](#advanced)
- [Common Mistakes and Pitfalls](#common-mistakes-and-pitfalls)
- [Quick Reference](#quick-reference)

---

## Fundamentals

### SDC vs XDC

**Q: What is the difference between SDC and XDC? Are they interchangeable? What does Vivado accept?**

**A:**

**SDC (Synopsys Design Constraints)** is an industry-standard format originally developed by Synopsys. It is Tcl-based and defines timing constraints in terms of clocks, input/output delays, exceptions, and clock groups. SDC is accepted by virtually all EDA tools: Vivado, Quartus, PrimeTime, Design Compiler.

**XDC (Xilinx Design Constraints)** is Vivado's constraint format. XDC is a strict superset of SDC — it accepts all valid SDC commands and adds Xilinx-specific extensions:

- Physical constraints: `set_property LOC`, `set_property BEL`, `set_property PACKAGE_PIN`
- Vivado-specific timing attributes: `set_property CLOCK_DEDICATED_ROUTE`, `MARK_DEBUG`
- Pblock definitions: `create_pblock`, `add_cells_to_pblock`

**Key practical differences:**

| Aspect | SDC | XDC |
|---|---|---|
| Tool support | Universal | Vivado only |
| Physical constraints | No | Yes |
| Timing command syntax | Identical | Identical (superset) |
| Comment character | `#` | `#` |
| Execution model | Evaluated once at constraint load time | Same — Tcl-evaluated top to bottom |

**Vivado constraint evaluation order matters.** Within a single XDC file, commands execute sequentially. A `create_generated_clock` must appear after the `create_clock` it references. If you have multiple XDC files, the evaluation order is set in the Vivado project constraints order (Sources → Constraints).

A common mistake: treating XDC as a static file format rather than a Tcl script. You can use Tcl variables, loops, and procedures in XDC files, which is useful for parameterised constraint generation:

```tcl
# Valid Tcl constructs inside an XDC file
set CLK_PERIOD 4.0  ;# 250 MHz

create_clock -name sys_clk -period $CLK_PERIOD -waveform {0 [expr {$CLK_PERIOD / 2}]} \
    [get_ports clk_in]
```

---

### create_clock

**Q: Write the `create_clock` constraint for a 200 MHz differential input clock on ports `clk_p` and `clk_n`. Explain each parameter.**

**A:**

```tcl
# 200 MHz differential clock: period = 1/200MHz = 5.000 ns
# Waveform: rising edge at 0 ns, falling edge at 2.5 ns
create_clock -name clk200 \
             -period 5.000 \
             -waveform {0.000 2.500} \
             [get_ports clk_p]

# Note: for a differential pair, constrain only the positive leg (clk_p).
# The tool automatically applies the constraint to the negative leg (clk_n)
# through the IBUFDS primitive.
```

**Parameter explanation:**

- `-name clk200` — Assigns a logical name used in all subsequent constraint references. Without a name, the tool auto-generates one, but named clocks are essential for clear timing reports and constraint maintenance.

- `-period 5.000` — The clock period in nanoseconds. This is the fundamental value from which all setup and hold budgets are derived. For a 200 MHz clock: T = 1/f = 1/200e6 = 5 ns.

- `-waveform {0.000 2.500}` — Defines the rising and falling edges within one period. `{0.000 2.500}` means rising at 0 ns, falling at 2.5 ns (50% duty cycle). A 40/60 duty cycle clock would use `{0.000 2.000}` for a 5 ns period.

- `[get_ports clk_p]` — The source object. `get_ports` returns the top-level port of the design. For an internal clock (e.g., a clock generated inside a PLL output buffer), use `[get_pins mmcm_inst/CLKOUT0]`.

**What the constraint does NOT do:**
- It does not describe the clock routing (that is handled by the clock network primitives — BUFG, MMCM, PLL).
- It does not specify the clock source jitter (use `-add_attribute` or the tool's MMCM characterisation for accurate jitter).

---

### create_generated_clock

**Q: Your MMCM takes a 200 MHz input and produces a 500 MHz output on CLKOUT0. Write the generated clock constraint. What happens if you use `create_clock` on the MMCM output instead?**

**A:**

```tcl
# Primary clock on the MMCM input
create_clock -name clk200 -period 5.000 [get_ports clk_in_p]

# Generated clock on the MMCM output buffer output
# MMCM: 200 MHz input, 500 MHz output → divide_by 2, multiply_by 5
create_generated_clock -name clk500 \
                       -source [get_pins mmcm_inst/CLKIN1] \
                       -master_clock clk200 \
                       -multiply_by 5 \
                       -divide_by 2 \
                       [get_pins mmcm_inst/CLKOUT0]

# After the BUFG:
create_generated_clock -name clk500_buf \
                       -source [get_pins mmcm_inst/CLKOUT0] \
                       -divide_by 1 \
                       [get_pins clk500_bufg/O]
```

**Why use `create_generated_clock` rather than `create_clock`:**

`create_generated_clock` tells the timing engine that the generated clock is **phase-related to** its master clock. The tool then computes the actual phase relationship and uses it for hold analysis and CDC path checking between the two clock domains.

If you use `create_clock` on the MMCM output, the tool treats the 500 MHz clock as **independent** of the 200 MHz source. Two independent clocks are treated as asynchronous — the tool will neither perform setup/hold analysis between them nor warn about CDC paths that should be constrained. This silently suppresses valid timing checks.

**Practical verification:**

```tcl
# After applying constraints, verify the tool sees them correctly
report_clocks
# Expected output shows:
# clk200   period=5.000 waveform={0.000 2.500}
# clk500   period=2.000 waveform={0.000 1.000}  [generated from clk200]
```

---

### set_input_delay and set_output_delay

**Q: An external SRAM operates at 100 MHz. The SRAM data output is valid 6 ns after the rising clock edge, and the setup requirement of the FPGA input register is known from device data. The board has 2 ns of PCB trace delay. Write the `set_input_delay` constraint.**

**A:**

`set_input_delay` constrains the arrival time of a signal at an input port, relative to a clock edge at the port. It tells the timing engine: "The data at this port arrives X ns after the reference clock edge."

The formula for SDC input delay in a synchronous source-synchronous interface:

```
set_input_delay = T_co (source clock-to-output) + T_pcb (board delay)
                - T_setup_budget (kept by the tool)
```

For the SRAM scenario:
- Source clock period: 10 ns (100 MHz)
- T_co: 6 ns (data valid 6 ns after clock edge)
- T_pcb: 2 ns

```tcl
# Reference clock for this interface — can be the FPGA's input clock
# or a virtual clock representing the SRAM's clock
create_clock -name sram_clk -period 10.000 [get_ports sram_clk_in]

# Input delay: data arrives at the FPGA pin 6+2 = 8 ns after SRAM clock edge
set_input_delay -clock sram_clk \
                -max 8.0 \
                [get_ports {sram_data[*]}]

# For hold analysis: minimum data arrival time
# Minimum T_co might be 2 ns (from datasheet's minimum output delay)
set_input_delay -clock sram_clk \
                -min 4.0 \
                [get_ports {sram_data[*]}]
```

**`-max` vs `-min`:**
- `-max` is used for setup analysis: worst-case (latest) data arrival.
- `-min` is used for hold analysis: best-case (earliest) data arrival.

Omitting `-min` applies the same value to both, which is conservative for setup but may be overly pessimistic for hold.

**Virtual clock:** If the SRAM and FPGA are clocked from different sources (no shared clock pin at the FPGA), use a virtual clock:

```tcl
create_clock -name sram_vclk -period 10.000
# No [get_ports] argument → virtual clock (not connected to a physical pin)

set_input_delay -clock sram_vclk -max 8.0 [get_ports {sram_data[*]}]
```

---

## Intermediate

### set_false_path

**Q: What does `set_false_path` do? Give three scenarios where it is correctly applied, and one scenario where engineers incorrectly apply it when a better constraint exists.**

**A:**

`set_false_path` tells the timing engine to ignore setup and hold analysis on a specified path. The path still exists in the design; the tool simply does not check timing on it. No logic optimisation related to timing is performed on false paths.

**Correct uses:**

**1. Asynchronous CDC paths** — A signal crossing between unrelated clock domains has no timing relationship. The synchroniser is responsible for safety; STA cannot check metastability. The path from the source flip-flop (domain A) to the first synchroniser flip-flop (domain B) is a false path:

```tcl
set_false_path -from [get_clocks clkA] -to [get_clocks clkB]
# Note: this suppresses ALL paths from clkA to clkB including unintended ones.
# More precise:
set_false_path -from [get_cells {src_module/data_reg}] \
               -to   [get_cells {sync_module/sync_ff1_reg}]
```

**2. Reset tree paths** — An asynchronous reset is not a clocked signal. Its path from the reset input to flip-flop reset pins has no meaningful setup/hold relationship to the clock:

```tcl
set_false_path -from [get_ports sys_rst_n]
```

**3. Configuration/test-only paths** — Signals that change only during power-on configuration (e.g., DIP switch inputs sampled once at startup). They meet timing trivially and constraining them wastes tool effort:

```tcl
set_false_path -from [get_ports {dip_sw[*]}]
```

**Incorrect use — when `set_multicycle_path` is the right choice:**

If a signal crosses from a 200 MHz clock domain to a 100 MHz clock domain, the destination has 10 ns to sample data that was launched every 5 ns. Some engineers apply `set_false_path` to suppress the timing violation. This is wrong because:
- The path IS timed — there is a real setup requirement at the destination register
- `set_false_path` removes the check entirely, leaving the designer with no assurance the path meets timing
- The correct constraint is `set_multicycle_path -setup 2` to grant two cycles (allowing 10 ns instead of 5 ns)

```tcl
# WRONG:
set_false_path -from [get_clocks clk200] -to [get_clocks clk100]

# CORRECT:
set_multicycle_path -setup 2 -from [get_clocks clk200] -to [get_clocks clk100]
set_multicycle_path -hold  1 -from [get_clocks clk200] -to [get_clocks clk100]
```

---

### set_multicycle_path

**Q: Explain the relationship between `-setup` and `-hold` in `set_multicycle_path`. Why must you almost always specify both, and what is the correct hold value for a given setup multiplier?**

**A:**

`set_multicycle_path -setup N` relaxes the setup requirement by allowing the data N clock cycles to propagate from launch to capture. The default is 1 (data must arrive within 1 cycle). With N=2, the data has 2 cycles.

The formula for setup timing:

```
Data arrival ≤ (Capture edge - Setup slack)
Capture edge for setup N = Launch edge + N × T_clk
```

**The hold interaction:**

By default, when you set `set_multicycle_path -setup N`, the hold check reference clock edge does NOT automatically move. The hold check edge is by default at:

```
Hold capture edge = Setup capture edge - 1 cycle
                 = (Launch edge + N × T_clk) - T_clk
                 = Launch edge + (N-1) × T_clk
```

Without a corresponding `-hold` constraint, the hold check shifts by (N-1) cycles beyond the launch edge. For N=2, this means the hold check is at 1 cycle after launch, which is usually correct.

However, Vivado's default multicycle hold behaviour is: the hold check is defined relative to the setup edge. If setup uses N=2, the default hold edge is 1 cycle earlier than the setup capture edge — i.e., at 1 cycle after launch. For a same-frequency multicycle, this is appropriate.

**For a 2:1 clock frequency ratio (launching at 200 MHz, capturing at 100 MHz):**

```
Period of launch clock: 5 ns
Period of capture clock: 10 ns

Default setup check: data must arrive within 1 capture cycle = 10 ns
→ This is already satisfied because the data has 10 ns

But the hold check: hold is checked at the capture edge 1 cycle BEFORE the setup edge.
The capture edge before the target edge = the previous 100 MHz edge.

This is wrong — we want hold to be checked at the same edge as where the data is captured.
```

The correct constraint for a 200 MHz → 100 MHz path:

```tcl
# The data has 2 launch cycles (10 ns) to reach the capture register
set_multicycle_path -setup 2 \
                    -from [get_clocks clk200] \
                    -to   [get_clocks clk100]

# Hold: keep the hold check at the same edge as the launch edge (not 1 cycle before capture)
# -hold 1 means: move the hold check back 1 cycle from where setup placed it
set_multicycle_path -hold 1 \
                    -from [get_clocks clk200] \
                    -to   [get_clocks clk100]
```

**General rule:** For `-setup N`, specify `-hold N-1` for same-clock multicycle paths. For cross-clock-domain paths, the hold value depends on the phase relationship.

**Memory-aid:** "Hold chases setup." When you relax setup by N, hold defaults to chase it by N-1. The explicit `-hold` constraint overrides this default.

---

### Clock groups and asynchronous clocks

**Q: What is `set_clock_groups -asynchronous`? How does it differ from applying `set_false_path` between clocks, and when would you use each?**

**A:**

```tcl
# set_clock_groups: declare groups of clocks with no timing relationship between groups
set_clock_groups -asynchronous \
                 -group {clk_a clk_a_gen} \
                 -group {clk_b clk_b_gen} \
                 -group {clk_ref}
```

`set_clock_groups -asynchronous` declares that clocks in different groups are asynchronous — there is no defined phase relationship between them. The timing engine suppresses all setup and hold checks between any pair of clocks from different groups.

**Comparison with `set_false_path -from ... -to ...`:**

| Aspect | `set_clock_groups -asynchronous` | `set_false_path` |
|---|---|---|
| Direction | Bidirectional (A→B and B→A) | Directional unless `-through` is specified |
| Scope | All paths between the groups | Can be net-, cell-, or port-specific |
| Generated clocks | Must include generated clocks explicitly in the group | Must constrain generated clocks separately |
| Override precedence | Higher precedence than most other exceptions | Standard exception precedence |
| Hold check | Also suppressed | Also suppressed |

**When to use `set_clock_groups`:**
- For multiple completely independent clock domains in a design (e.g., PCIe reference clock vs Ethernet reference clock vs internal MMCM clock)
- When generated clocks from different PLLs should be treated as asynchronous even if they have the same frequency

**When to use `set_false_path` instead:**
- For a specific directional path (e.g., a one-time configuration register written from a slow domain, read in a fast domain — only the write-to-read direction matters)
- For non-clock-related false paths (async resets, test signals)

**Critical warning:** `set_clock_groups -asynchronous` suppresses ALL checks between those clock groups, including checks on paths that should be timed (e.g., if you accidentally declare two synchronous clocks as asynchronous). Always verify with `report_cdc` after applying clock groups:

```tcl
report_cdc -severity {Critical Warning}
```

---

### I/O timing: source-synchronous and system-synchronous

**Q: Your design has a DDR source-synchronous output interface. The downstream device requires data to be valid at least 1.5 ns before its clock edge (setup) and held 0.8 ns after (hold). PCB trace delay is 0.5 ns on data and 0.4 ns on clock. Write the output delay constraints.**

**A:**

For a source-synchronous output, the FPGA forwards its own clock along with the data. The external device samples data using the forwarded clock. The constraint is written from the perspective of the external device's setup and hold requirements, accounting for skew between data and clock at the board level.

```
Output delay max (setup constraint) = T_setup_external + T_clk_delay - T_data_delay
                                    = 1.5 + 0.4 - 0.5 = 1.4 ns

Output delay min (hold constraint)  = -T_hold_external - T_clk_delay + T_data_delay
                                    = -0.8 - 0.4 + 0.5 = -0.7 ns
```

```tcl
# Define the forwarded clock at the FPGA output pin
# The forwarded clock is a generated clock derived from the internal OSERDES clock
create_generated_clock -name fwd_clk \
                       -source [get_pins oserdes_clk_inst/CLKOUT] \
                       -divide_by 1 \
                       [get_ports data_clk_p]

# Setup constraint: data must be valid 1.4 ns before the forwarded clock edge arrives
set_output_delay -clock fwd_clk \
                 -max 1.4 \
                 [get_ports {data_out[*]}]

# Hold constraint: data must be held 0.7 ns before the forwarded clock edge
# (negative output delay means data can arrive that long before the clock)
set_output_delay -clock fwd_clk \
                 -min -0.7 \
                 [get_ports {data_out[*]}]
```

**DDR-specific consideration:** For DDR interfaces, data changes on both edges. You need to apply constraints for both clock edges using `-clock_fall`:

```tcl
# Rising-edge output (even bits)
set_output_delay -clock fwd_clk -max  1.4 [get_ports {data_out[*]}]
set_output_delay -clock fwd_clk -min -0.7 [get_ports {data_out[*]}]

# Falling-edge output (odd bits) — add to the rising-edge constraints
set_output_delay -clock fwd_clk -clock_fall -max  1.4 \
                 -add_delay [get_ports {data_out[*]}]
set_output_delay -clock fwd_clk -clock_fall -min -0.7 \
                 -add_delay [get_ports {data_out[*]}]
```

The `-add_delay` flag accumulates the constraint on top of the existing one, rather than replacing it.

---

## Advanced

### Constraint ordering and exception precedence

**Q: You have the following constraints in your XDC. Predict which constraint applies to the path from `reg_a` (clocked by clk_fast) to `reg_b` (clocked by clk_slow) and explain the precedence rules.**

```tcl
set_false_path -from [get_clocks clk_fast] -to [get_clocks clk_slow]
set_multicycle_path -setup 2 -from [get_cells reg_a] -to [get_cells reg_b]
set_clock_groups -asynchronous -group clk_fast -group clk_slow
```

**A:**

The Vivado exception precedence order (from highest to lowest):

1. **Most specific object match** wins. The specificity ranking is: cell > net > clock. A constraint that references a specific cell is more specific than one that references a clock.

2. **Among equal specificity**, the **last** constraint in file order wins.

For the three constraints shown:

- `set_false_path -from clk_fast -to clk_slow` — clock-level specificity
- `set_multicycle_path -setup 2 -from reg_a -to reg_b` — cell-level specificity (most specific)
- `set_clock_groups -asynchronous` — this is NOT a path exception; it is a clock relationship declaration and has separate, higher precedence

**Actual result:** `set_clock_groups -asynchronous` overrides both path exceptions for all paths between clk_fast and clk_slow. The multicycle path and false path constraints are ignored because the clock groups declaration suppresses all inter-group timing checks first.

**To achieve the multicycle path behaviour** while still declaring the clocks as asynchronous for other paths, you would need to:
1. Remove the `set_clock_groups` declaration for these specific clocks, OR
2. Use `set_false_path` only on the specific paths that are genuinely asynchronous and keep `set_multicycle_path` for the synchronous ones — but this requires the clocks to be in the same group (or no group declaration).

This is a nuanced area that frequently catches engineers off guard. The lesson: `set_clock_groups` is a very broad tool. Apply it only when all inter-group paths are genuinely asynchronous.

```tcl
# Verification: check what constraint is active on a specific path
report_exceptions -from [get_cells reg_a] -to [get_cells reg_b]
```

---

### Constraining a MMCM with spread-spectrum modulation

**Q: Your MMCM is configured with spread-spectrum clock modulation (SSEN=1, ±0.5% spread). How should the timing constraints account for this, and what effect does it have on the device's timing margins?**

**A:**

Spread-spectrum clocking (SSC) modulates the clock frequency slightly (typically ±0.5%) to spread electromagnetic emissions across a frequency range rather than concentrating them at one frequency. This reduces EMI at the cost of clock frequency uncertainty.

**Effect on timing:**

The modulated clock's period varies between:
```
T_min = T_nominal × (1 - spread_fraction) = T_nominal × 0.995
T_max = T_nominal × (1 + spread_fraction) = T_nominal × 1.005
```

For a 250 MHz clock (T = 4.000 ns) with ±0.5% spread:
- T_min = 3.980 ns (maximum frequency end)
- T_max = 4.020 ns (minimum frequency end)

The timing engine uses the worst-case period for setup analysis. The correct approach is to constrain to the **minimum period** (maximum frequency, worst-case setup):

```tcl
# Account for spread-spectrum: constrain at worst-case (highest frequency)
# T_min = 4.000 * (1 - 0.005) = 3.980 ns
create_clock -name clk_ssc -period 3.980 [get_ports clk_ssc_p]
```

**Device data sheet consideration:**

Xilinx characterises FPGA timing with a specific level of clock jitter assumption built into the timing model. For on-chip MMCM clocks, the jitter is modelled as part of the device characterisation. For external SSC clocks, the spread must be added as **input jitter** in the timing constraints:

```tcl
# Add input jitter to model SSC spread
set_input_jitter clk_ssc 0.100  ;# 100 ps RMS jitter from SSC modulation
```

**Practical warning:** Using SSC with high-speed interfaces (DDR4, PCIe, SERDES) is restricted. These interfaces have strict clock stability requirements. Always check the FPGA device data sheet and the IP core documentation before enabling SSC on a reference clock feeding high-speed transceivers.

---

### Constraint verification workflow

**Q: After writing all your timing constraints, describe the workflow you use to verify they are complete and correct before submitting to timing closure.**

**A:**

A systematic constraint verification workflow prevents the most common category of timing closure failure: incorrect or missing constraints.

**Step 1: Check that all clocks are defined**

```tcl
report_clocks
# Review: are all expected clocks present? Are generated clock frequencies correct?
# Missing clocks appear as "No clocks defined on ..." warnings in timing reports
```

**Step 2: Check for unconstrained I/O**

```tcl
report_timing -of_objects [get_ports *] -setup -hold
# Alternatively:
check_timing -verbose
# check_timing reports: unconstrained inputs, unconstrained outputs,
# missing input delay, missing output delay
```

**Step 3: Check for CDC paths**

```tcl
report_cdc -severity {Critical Warning Warning}
# Lists paths that cross clock domains without a synchroniser or false path exception
# Critical Warning = no synchroniser detected; Warning = potential issue
```

**Step 4: Verify exception coverage**

```tcl
# Check that false paths and multicycle paths apply to the intended paths
report_exceptions -ignored   ;# exceptions that are overridden by another constraint
report_exceptions -coverage  ;# how many paths each exception covers
```

**Step 5: Review the timing summary**

```tcl
report_timing_summary -delay_type min_max -report_unconstrained \
                      -check_timing_verbose -file timing_summary.rpt
```

The `-report_unconstrained` flag adds a section listing paths that have no timing constraint. A clean design should have zero unconstrained paths (or only intentionally unconstrained paths, e.g., test-only logic that is isolated with `set_false_path`).

**Step 6: Check the constraint file for common syntax errors**

```tcl
# In Vivado Tcl console, source the XDC file directly to catch errors
source constraints.xdc
```

Sourcing the XDC in the Tcl console reveals errors immediately (unresolved object names, wrong port names, incorrect clock names) without requiring a full implementation run.

---

## Common Mistakes and Pitfalls

1. **Forgetting `-min` on `set_input_delay` / `set_output_delay`.** Only specifying `-max` leaves hold analysis unconstrained or using the same value for both, which may be too pessimistic.

2. **Using `set_false_path` instead of `set_multicycle_path` for slow-changing signals.** If a signal is guaranteed to be stable when sampled — but the path still has a timing relationship — it should be a multicycle path, not a false path. False path removes the check entirely.

3. **Applying clock group constraints too broadly.** Declaring two clocks asynchronous when they are derived from the same source (e.g., two MMCM outputs at different frequencies) suppresses valid timing checks. Use `set_multicycle_path` for related but differently-divided clocks.

4. **Constraining the clock on the wrong object.** `create_clock` on an `IBUF` output rather than the corresponding `get_ports` results in a clock that is not visible to the `set_input_delay` constraints referencing that port.

5. **Not accounting for BUFG delay in generated clock constraints.** The BUFG adds ~600 ps of delay. This must be reflected in `create_generated_clock` chains that pass through BUFG primitives.

6. **Ordering errors in XDC files.** A `create_generated_clock` that references a master clock by name will fail if the master `create_clock` appears later in the file.

---

## Quick Reference

| Command | Purpose |
|---|---|
| `create_clock -period T [get_ports p]` | Define a primary clock at port p |
| `create_generated_clock -source S -multiply_by M -divide_by D [get_pins X]` | Define a derived clock |
| `set_input_delay -clock C -max/-min D [get_ports p]` | Constrain input arrival time |
| `set_output_delay -clock C -max/-min D [get_ports p]` | Constrain output required time |
| `set_false_path -from F -to T` | Exempt a path from timing analysis |
| `set_multicycle_path -setup N -from F -to T` | Allow N cycles for setup on a path |
| `set_multicycle_path -hold N-1 -from F -to T` | Companion hold relaxation |
| `set_clock_groups -asynchronous -group G1 -group G2` | Declare unrelated clock domains |
| `report_clocks` | List all defined clocks |
| `check_timing -verbose` | Report unconstrained ports and paths |
| `report_cdc` | Report clock domain crossing issues |
| `report_exceptions` | Show active timing exceptions |
| `report_timing_summary -report_unconstrained` | Full timing summary with unconstrained paths |
