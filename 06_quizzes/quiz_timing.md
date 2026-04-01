# Quiz: FPGA Timing

## Instructions

15 multiple-choice questions covering timing constraints, setup and hold slack, timing closure
strategies, and SDC/XDC constraint syntax. Select the single best answer for each question.
Detailed explanations follow each answer in the Answer Key section.

Difficulty distribution: Q1–Q5 Fundamentals, Q6–Q10 Intermediate, Q11–Q15 Advanced.

---

## Questions

### Q1

In static timing analysis, what does "setup slack" represent?

A) The amount of time by which data arrives at a flip-flop input AFTER the clock edge.  
B) The margin between when data arrives at a flip-flop input and the latest it is permitted to arrive (the setup requirement deadline).  
C) The difference between the launch clock edge and the capture clock edge.  
D) The total propagation delay through all combinational logic in the path.  

---

### Q2

A design runs at 100 MHz. The clock period constraint is correctly written in XDC as:

A) `set_clock_period clk 10.0`  
B) `create_clock -period 10.0 [get_ports clk]`  
C) `create_clock -frequency 100 [get_ports clk]`  
D) `set_property PERIOD 10.0 [get_ports clk]`  

---

### Q3

What is the consequence of NOT constraining a clock input in your XDC file?

A) The tool assumes the worst-case clock period and applies maximum timing margins.  
B) The clock is treated as unconstrained — paths from that clock are not checked by the timing engine, hiding potential timing violations.  
C) The synthesis tool will fail with an error.  
D) The tool assumes a 1 GHz clock period, making all paths appear to pass timing trivially.  

---

### Q4

Which XDC command is used to tell the timing engine that two clocks are completely independent
and no timing paths between them need to be checked?

A) `set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]`  
B) `set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]`  
C) `set_multicycle_path -setup 2 -from [get_clocks clk_a] -to [get_clocks clk_b]`  
D) `set_disable_timing [get_cells *]`  

---

### Q5

A timing report shows a path with negative slack of -0.5 ns. What does this mean?

A) The path has 0.5 ns of margin and is passing timing.  
B) Data arrives 0.5 ns too late at the capturing flip-flop — the design will fail at this clock frequency.  
C) The path requires a 0.5 ns input delay constraint to be applied.  
D) The clock skew on this path is 0.5 ns, which is within acceptable limits.  

---

### Q6

A multicycle path constraint `set_multicycle_path -setup 2 -from [get_cells reg_a] -to [get_cells reg_b]`
is applied. What hold constraint must ALSO be applied to avoid a hold violation?

A) No additional constraint is needed — the hold check is automatically relaxed when setup multicycle is set to 2.  
B) `set_multicycle_path -hold 1 -from [get_cells reg_a] -to [get_cells reg_b]`  
C) `set_multicycle_path -hold 2 -from [get_cells reg_a] -to [get_cells reg_b]`  
D) `set_false_path -hold -from [get_cells reg_a] -to [get_cells reg_b]`  

---

### Q7

The timing report for a critical path shows the following components (all in ns):
- Logic delay: 4.2 ns  
- Net delay: 3.1 ns  
- Clock skew: 0.4 ns (launch clock arrives later than capture clock)  
- Setup time: 0.08 ns  
- Clock period: 8.0 ns  

What is the setup slack?

A) 0.22 ns  
B) 0.62 ns  
C) -0.22 ns  
D) 0.12 ns  

---

### Q8

A design has an input path from an external device with a known output delay of 3 ns after
the rising clock edge. The PCB trace delay is 0.5 ns. The FPGA internal clock-to-data skew
is negligible. The clock period is 10 ns. What is the correct `set_input_delay` command?

A) `set_input_delay -clock clk -max 3.5 [get_ports data_in]`  
B) `set_input_delay -clock clk -max 3.0 [get_ports data_in]`  
C) `set_input_delay -clock clk -max 6.5 [get_ports data_in]`  
D) `set_input_delay -clock clk -min 3.5 [get_ports data_in]`  

---

### Q9

Clock domain crossing paths should be covered by which constraint to prevent the timing
engine from trying to perform a physically meaningless timing check across asynchronous domains?

A) `set_multicycle_path -setup 2`  
B) `set_false_path` or `set_clock_groups -asynchronous`  
C) `set_max_delay -datapath_only`  
D) `set_input_delay -clock_fall`  

---

### Q10

A design fails timing with a path that has a large logic delay. The path passes through 7
levels of LUT logic. Which is the most effective first step toward timing closure for this path?

A) Increase the FPGA device to a larger part with more resources.  
B) Pipeline the path by inserting a register stage at the midpoint to split the 7 levels into two shorter paths.  
C) Apply `set_multicycle_path -setup 2` to give the path two clock cycles.  
D) Change the synthesis strategy from "default" to "PerformanceOptimized" and re-run synthesis without modifying the RTL.  

---

### Q11

A Vivado timing report shows a hold violation on a path between two flip-flops in the same
clock domain. The hold slack is -0.15 ns. Which of the following is the correct interpretation
and fix?

A) The data arrives too early relative to the clock edge. The tool typically fixes this automatically by adding delay buffers; if it does not, the designer should add a pipeline register.  
B) The data arrives too late relative to the clock edge. Pipelining the path will resolve the hold violation.  
C) Hold violations only occur in paths with CDC; this is a false positive and can be waived.  
D) The hold margin of -0.15 ns means the timing is passing — negative hold slack is acceptable.  

---

### Q12

Consider the following XDC constraint:

```tcl
set_max_delay -datapath_only 5.0 -from [get_cells sync_reg_stage1] -to [get_cells sync_reg_stage2]
```

When should `-datapath_only` be used on a `set_max_delay` constraint, and what does it change?

A) It should be used on all timing paths to improve runtime; it disables clock skew calculation for faster analysis.  
B) It should be used for CDC synchroniser paths where you want the tool to check only that the combinational delay does not exceed the specified value, ignoring clock skew and jitter pessimism that would be inappropriate for an asynchronous path.  
C) It instructs the tool to use datapath timing only when there is hold slack available to absorb, preventing unnecessary pipeline stages.  
D) It is equivalent to `set_false_path` — it removes the path from timing analysis entirely.  

---

### Q13

A design uses both a 100 MHz and a 125 MHz clock generated from the same MMCM. The GCD of
100 and 125 is 25 MHz, giving a common period of 40 ns. The tool's timing analysis shows a
setup requirement of 8 ns for paths crossing from 100 MHz to 125 MHz. You want to allow one
full 100 MHz cycle (10 ns) for the data to travel. What multicycle constraint is needed?

A) `set_multicycle_path -setup 2 -from [get_clocks clk_100] -to [get_clocks clk_125]`  
B) No constraint is needed — the tool automatically uses the 10 ns period for 100 MHz paths.  
C) `set_multicycle_path -setup 1 -from [get_clocks clk_100] -to [get_clocks clk_125]`  
D) `set_false_path -from [get_clocks clk_100] -to [get_clocks clk_125]`  

---

### Q14

A hierarchical design has a top-level module that instantiates a sub-module `core_u0`. A
path inside `core_u0` is failing timing. A colleague suggests applying
`set_false_path -through [get_cells core_u0/*]` to fix it. What is the problem with this approach?

A) There is no problem — applying `set_false_path` through a module is the recommended way to resolve paths that fail inside hierarchical blocks.  
B) `set_false_path -through` is an illegal XDC syntax and will cause an error.  
C) This constraint will suppress the timing check on the failing path but will also suppress checks on ALL other paths passing through that cell hierarchy, potentially hiding genuine timing violations throughout the sub-module.  
D) `set_false_path -through` only works on nets, not on cell hierarchies.  

---

### Q15

A design contains a Gray-code counter whose output crosses from a 200 MHz source domain to a
100 MHz capture domain through a 2FF synchroniser. The designer applies:

```tcl
set_max_delay -datapath_only 5.0 \
    -from [get_cells gray_counter_reg[*]] \
    -to   [get_cells sync_ff1_reg[*]]
```

The capture clock period is 10 ns. What is the significance of the 5.0 ns value, and is this
constraint complete?

A) 5.0 ns equals half the source clock period. The constraint is complete because it verifies the combinational path from the counter to the synchroniser input is short enough to be safely captured.  
B) 5.0 ns is the source clock period (200 MHz). The constraint correctly bounds the maximum combinational delay to the first synchroniser stage. However, the constraint is incomplete because a corresponding hold constraint (`set_false_path -hold` or a `set_clock_groups -asynchronous` to exclude hold checking on this path) should also be applied.  
C) 5.0 ns is the minimum hold time required by the synchroniser flip-flop. The constraint is checking hold, not setup.  
D) The constraint is incorrect — `set_max_delay -datapath_only` cannot be used on CDC paths and Vivado will issue a critical warning that must be resolved by using `set_false_path` instead.  

---

## Answer Key

### A1: B

Setup slack = (time available) − (time required). The time available is the clock period
(adjusted for skew). The time required is the data arrival time plus the flip-flop setup time.
Positive slack means the data arrives early enough with margin to spare. Negative slack means
the data arrives too late — the flip-flop may not reliably capture the correct value, leading
to potential metastability or incorrect data.

*Why A is wrong:* data arriving AFTER the clock edge (in a synchronous context) describes a
setup violation, which is negative slack — not positive.  
*Why C is wrong:* the difference between launch and capture clock edges is the clock period
(for single-cycle paths) or the allowed data window — not setup slack itself.  
*Why D is wrong:* total combinational propagation delay is a component used to CALCULATE slack,
not the definition of slack.

---

### A2: B

The correct Xilinx XDC / Synopsys SDC syntax for creating a clock constraint is:
`create_clock -period <period_ns> [get_ports <port_name>]`. The period is specified in
nanoseconds. A 100 MHz clock has a period of 1/100,000,000 = 10 ns.

*Why A is wrong:* `set_clock_period` is not a valid Tcl/XDC command.  
*Why C is wrong:* `create_clock` does not accept a `-frequency` argument — only `-period`.  
*Why D is wrong:* `set_property` is used for cell/net/port properties, not for timing
constraints. Vivado will not recognise this as a clock constraint.

---

### A3: B

The Vivado (and Quartus) timing engine only analyses paths between constrained endpoints. If a
clock is not constrained, all paths sourced from or captured by that clock are marked
"unconstrained" and are excluded from timing reports. This means a genuine 500 MHz critical path
could be present in the design and no warning would be issued. This is a dangerous situation
that has caused many tape-out failures. Always constrain every clock — including internally
generated clocks from MMCMs and divide-by-2 circuits.

*Why A is wrong:* the tool does not assume worst-case — it simply skips the check.  
*Why C is wrong:* synthesis tolerates unconstrained clocks (it may apply a default constraint
or no constraint, but it will not error out).  
*Why D is wrong:* the tool does not assume any implicit clock frequency for unconstrained paths.

---

### A4: A

`set_clock_groups -asynchronous` is the correct command to declare that two clocks have no
phase relationship and that ALL paths between them (in both directions) should be excluded
from timing analysis. This is more robust than `set_false_path` because it applies
bidirectionally and is semantically clearer about the intent.

*Why B is wrong:* `set_false_path -from clk_a -to clk_b` applies only in one direction
(clk_a → clk_b). Paths from clk_b to clk_a would still be checked. You would need two
`set_false_path` commands. More importantly, `set_clock_groups` is the idiomatic choice.  
*Why C is wrong:* `set_multicycle_path` relaxes timing by allowing more clock cycles — it does
not remove the check between asynchronous domains. This would be incorrect for truly
asynchronous clocks.  
*Why D is wrong:* `set_disable_timing` on all cells would remove all timing checks from the
entire design — far too broad and masks all violations.

---

### A5: B

Negative slack indicates a timing violation. Setup slack = required time − arrival time. If
slack = -0.5 ns, the data arrives 0.5 ns after the latest acceptable time. At the target clock
frequency, the capturing flip-flop cannot reliably sample the correct data value. If implemented
in hardware, the device may malfunction, produce metastable outputs, or fail intermittently
at speed.

*Why A is wrong:* positive slack represents margin; negative slack represents a violation.  
*Why C is wrong:* negative slack has nothing to do with input delay constraints — it is a
static timing analysis result.  
*Why D is wrong:* clock skew is one component factored into the timing calculation, but
negative slack is the overall verdict, not a description of skew alone.

---

### A6: B

When you set `set_multicycle_path -setup 2`, the setup check window moves forward by one cycle
(the capture edge is now checked 2 cycles after the launch edge). However, the DEFAULT hold
check assumes the data is captured one cycle after launch. With a setup multicycle of 2, the
hold check window must be adjusted so the tool does not require the data to still be valid
at the (now-irrelevant) single-cycle capture edge. The convention in Xilinx/SDC tools is:
`-hold N` where N = (setup_multicycle - 1) = 1. This moves the hold check back by one cycle
to align with the actual capture edge.

*Why A is wrong:* the hold check is NOT automatically relaxed when only `-setup` is specified.
Failing to add `-hold 1` results in a hold check that expects data to be stable until the
original (1-cycle) capture edge, which may trigger false hold violations.  
*Why C is wrong:* `-hold 2` would move the hold check back by 2 cycles — an overcorrection
that could allow real hold violations to be hidden.  
*Why D is wrong:* `set_false_path -hold` disables hold checking on the path entirely, which
is overly permissive and hides genuine hold violations that could cause functional failures.

---

### A7: A

Setup slack = Clock period − Data path delay − Setup time + Clock skew

Where clock skew = capture clock arrival − launch clock arrival. If the launch clock arrives
LATER than the capture clock, skew is negative (reduces available time).

Slack = 8.0 − (4.2 + 3.1) − 0.08 + (−0.4) = 8.0 − 7.3 − 0.08 − 0.4 = **0.22 ns**

The path meets timing with 0.22 ns of positive slack.

*Why B is wrong:* 0.62 ns ignores the setup time deduction.  
*Why C is wrong:* −0.22 ns would indicate a violation — this results from incorrectly adding the skew instead of subtracting it.  
*Why D is wrong:* 0.12 ns results from using the wrong sign convention for skew.

---

### A8: A

`set_input_delay -max` specifies the maximum time after the clock edge that the input data
can arrive at the FPGA pin. The external device's output delay is 3 ns, and the PCB trace
adds 0.5 ns, giving a maximum input delay of 3.5 ns. The `-max` value is used for setup
checking. A corresponding `-min` value (minimum delay) should also be applied for hold
checking, but the question asks for the setup-checking constraint.

*Why B is wrong:* 3.0 ns omits the PCB trace delay — the tool must account for the total
delay from clock edge to FPGA pin.  
*Why C is wrong:* 6.5 ns (10 − 3.5 = 6.5 would be the remaining window, not the input delay).
6.5 ns as an input delay constraint would be incorrect.  
*Why D is wrong:* `-min` alone without `-max` specifies only the hold check, not the setup
check. Both are required for a complete constraint; the question asks specifically about the
setup value.

---

### A9: B

`set_false_path` removes specific paths from timing analysis entirely. `set_clock_groups -asynchronous`
removes all paths between a pair of asynchronous clock groups. Both are appropriate for CDC
paths where the clocks have no defined phase relationship and the synchroniser itself (2FF, FIFO)
handles the metastability risk. Applying static timing analysis to these paths is meaningless —
the clocks may be at any phase offset, so any calculated slack value is irrelevant.

*Why A is wrong:* `set_multicycle_path -setup 2` relaxes timing but does not remove the check.
For truly asynchronous paths, there is no valid timing relationship to relax — the path should
not be checked at all.  
*Why C is wrong:* `set_max_delay -datapath_only` constrains the maximum combinational delay
and is sometimes used on CDC synchroniser inputs (to verify the data path is short), but it
is not the tool used to prevent meaningless cross-domain checks. It is an advanced technique,
not the general answer.  
*Why D is wrong:* `set_input_delay -clock_fall` is for off-chip interface constraints on
falling-edge-captured signals — it has no relevance to CDC paths.

---

### A10: B

Inserting a pipeline register at the midpoint of a long combinational path is the fundamental
and most effective timing closure technique. If a path has 7 LUT levels and is failing by
2 ns, splitting it into two paths of ~3 and ~4 LUT levels each reduces the critical path delay
to roughly half. This is almost always the right answer when logic delay dominates.

*Why A is wrong:* moving to a larger device provides more routing resources and potentially
better placement, but if the logic delay is the problem (7 LUT levels), a larger part will
not help because the logic structure is identical.  
*Why C is wrong:* `set_multicycle_path -setup 2` allows the path two clock cycles at the cost
of halving its throughput. This may be acceptable for non-critical datapaths but is a design
compromise, not a physical fix. It is not "the most effective first step."  
*Why D is wrong:* synthesis strategies can sometimes reshape logic (e.g., rebalancing LUT
trees), and this is worth trying. However, a 7-level logic path failing by a significant
margin typically requires RTL restructuring (pipelining), not just tool tuning.

---

### A11: A

A hold violation means data arrives TOO EARLY — it changes before the previous clock edge's
captured value has been safely stored (the hold window has not elapsed). In other words, data
transitions within the hold window of the previous capture event. Hold violations are
dangerous because they CANNOT be fixed by slowing the clock — they are timing-absolute.

The standard tool fix is to insert buffer delay (Vivado's router and implementation engine
does this automatically in most cases). If the tool cannot fix it automatically (rare, usually
indicates a floorplanning or placement problem), the designer must address the path placement.
Adding a pipeline register BETWEEN the two flip-flops is not the right fix for a hold
violation — the registers would need to move closer together or delay needs to be added on
the data path.

*Why B is wrong:* data arriving too LATE is a setup violation, not a hold violation.  
*Why C is wrong:* hold violations absolutely occur within the same clock domain — in fact,
intra-domain hold violations are common when fast paths exist between close-proximity flip-flops.  
*Why D is wrong:* negative hold slack is always a violation, never acceptable. It means the
design will malfunction.

---

### A12: B

`-datapath_only` instructs the timing engine to check only the combinational delay of the
data path (logic + routing), without adding clock uncertainty, clock skew, or jitter
pessimism to the calculation. This is appropriate for CDC synchroniser input paths where
you want to guarantee the combinational data delay from the sending domain is short enough
to settle before being sampled, but the clock relationship between domains is undefined so
skew/jitter calculations would be meaningless. Without `-datapath_only`, the tool would add
pessimistic clock uncertainty to a 5 ns constraint, potentially tightening it to 3–4 ns.

*Why A is wrong:* using `-datapath_only` on all paths is incorrect and dangerous — it removes
safety margins (jitter, uncertainty) that are physically real and must be accounted for on
synchronous paths.  
*Why C is wrong:* the constraint has no concept of "available hold slack" — it simply changes
how the timing check is computed.  
*Why D is wrong:* `set_max_delay -datapath_only` still performs a timing check (it checks
that the delay is less than the specified value). `set_false_path` removes the check entirely.
They are not equivalent.

---

### A13: A

When two clocks are generated from the same MMCM, the tool treats them as synchronous with
a known phase relationship. For a 100 MHz → 125 MHz crossing, the default setup check uses
the closest edge pair, which gives an effective check window shorter than one 100 MHz period
(8 ns in this case, as stated in the question). To tell the tool that data requires a full
10 ns (one 100 MHz cycle), you apply `set_multicycle_path -setup 2`, which moves the capture
edge forward, effectively giving the data path two "steps" in the common 40 ns period to
arrive — aligning the constraint with the actual one-cycle latency budget.

*Why B is wrong:* the tool does NOT automatically use the source clock period. It analyses
the shortest edge-to-edge relationship, which for these two frequencies is 8 ns, not 10 ns.  
*Why C is wrong:* `-setup 1` is the default — applying it explicitly does nothing.  
*Why D is wrong:* `set_false_path` would remove the timing check entirely. Since these clocks
ARE synchronous (same MMCM source), paths crossing between them must be checked. Using
`set_false_path` here would hide real timing violations.

---

### A14: C

`set_false_path -through [get_cells core_u0/*]` applies to every timing path that passes
through any cell in the `core_u0` hierarchy. This is an extremely broad constraint that
silences timing checks on all logic within the sub-module, not just the failing path. Any
genuine timing violation elsewhere in `core_u0` will be hidden, creating a design that may
fail in silicon. The correct approach is to identify the specific failing path using the
timing report and constrain only that path, or to restructure the RTL to fix the root cause.

*Why A is wrong:* this approach is explicitly discouraged in Vivado methodology checks — it
is a sign of poor constraint practice.  
*Why B is wrong:* `set_false_path -through` with a cell get is valid XDC syntax and will be
accepted by Vivado, making it a dangerous rather than syntactically incorrect approach.  
*Why D is wrong:* `set_false_path -through` can reference cells or nets — the `-through`
argument accepts both `get_cells` and `get_nets`.

---

### A15: B

The 5.0 ns value equals the source clock period (1/200 MHz = 5 ns). This constraint ensures
the combinational logic from the Gray counter register outputs to the first synchroniser
flip-flop has at most 5 ns of delay — guaranteeing the data has settled well before any
metastability window. The `- datapath_only` flag correctly removes clock skew pessimism for
this asynchronous crossing.

However, the constraint is incomplete. The `-datapath_only` flag handles the setup check,
but the hold check on this path (from the same or different CDC perspective) is not explicitly
constrained. Without a `set_false_path -hold` (or equivalent `set_clock_groups -asynchronous`)
on this path, the tool may still apply an inappropriate hold check using the asynchronous
clock relationship, which could generate false hold violations or — worse — fail to flag
genuine ones. A complete CDC constraint set requires both setup and hold considerations.

*Why A is wrong:* 5 ns is the source clock period (200 MHz), not half the period.  
*Why C is wrong:* `set_max_delay` performs a setup-type check (maximum delay), not a hold
check. The 5 ns is the maximum allowed propagation time, not a minimum hold requirement.  
*Why D is wrong:* `set_max_delay -datapath_only` is valid and widely used for CDC
synchroniser input constraints. Vivado accepts it and it is documented as a valid CDC
constraining technique in Xilinx UG903.
