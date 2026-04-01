# Timing Closure Strategies

Timing closure is the process of ensuring every path in a design meets its setup and hold requirements after place and route. It is one of the most practically demanding skills in FPGA engineering and accounts for a large fraction of interview depth-questions at experienced engineer level. Interviewers are looking for methodical, tool-aware thinking — not guesswork.

---

## Table of Contents

- [Fundamentals](#fundamentals)
- [Intermediate](#intermediate)
- [Advanced](#advanced)
- [Common Mistakes and Pitfalls](#common-mistakes-and-pitfalls)
- [Quick Reference](#quick-reference)

---

## Fundamentals

### WNS, TNS, WHS, WPWS

**Q: After implementation, `report_timing_summary` shows WNS = -0.45 ns, TNS = -12.3 ns, WHS = +0.08 ns, WPWS = +0.21 ns. Interpret each metric and explain what actions each value drives.**

**A:**

**WNS — Worst Negative Slack (setup)**

WNS is the slack of the most-failing setup timing path in the design. Slack is defined as:

```
Slack = Required arrival time - Actual arrival time
      = (Capture edge - T_setup) - (Launch edge + T_clk2q + T_logic + T_routing)
```

A WNS of -0.45 ns means the critical path arrives 0.45 ns too late at the destination register. The design will not function reliably at the target frequency.

**Action:** WNS drives the priority of timing closure work. Focus first on the single path contributing WNS — fix it, re-run, observe the new WNS. The critical path is always the first to fix.

**TNS — Total Negative Slack**

TNS is the sum of all negative setup slacks across all failing paths (typically one endpoint per path). TNS = -12.3 ns means there are many failing paths (not just the worst one).

**Action:** TNS indicates the scope of the timing closure problem. A design with WNS = -0.45 ns and TNS = -0.47 ns (two paths) has a focused problem. A design with WNS = -0.45 ns and TNS = -50 ns has widespread violations — probably a clocking, floorplanning, or systematic RTL issue, not a localised one.

**WHS — Worst Hold Slack**

WHS is the slack of the most-failing hold timing path. A positive WHS = +0.08 ns means all hold paths pass, with the tightest holding by only 80 ps. This is close enough to warrant attention.

```
Hold Slack = Actual arrival time - (Capture edge + T_hold)
```

Hold violations mean data changes before the capture flip-flop has reliably stored it. Unlike setup violations, hold violations cannot be fixed by slowing the clock. They are fixed by adding delay on the data path (buffer insertion or routing detour).

**Action:** WHS = +0.08 ns is technically passing, but 80 ps over PVT corners is marginal. Check whether this path was analysed at the correct operating corner (worst-case hold is typically at fast-process, low-voltage, high-temperature — opposite of worst-case setup).

**WPWS — Worst Pulse Width Slack**

WPWS is the minimum pulse width on any clock seen by a flip-flop's clock input. It must be positive for the flip-flop's minimum-width requirement to be met. WPWS = +0.21 ns indicates all clock pulse widths are sufficient.

**Summary for this report:**
- Setup: **failing** — WNS = -0.45 ns → requires attention
- Hold: **passing** (marginally) — WHS = +0.08 ns → monitor but not urgent
- Pulse width: **passing** — WPWS = +0.21 ns → no action

---

### Setup and hold slack interpretation

**Q: Draw the timing diagram for a setup timing check. Label T_clk2q, T_logic, T_routing, T_setup, the launch edge, and the capture edge. Write the slack equation.**

**A:**

```
Launch clock edge (at source FF clock pin):
     ___
    |   |
____|   |____
    ^
    Launch edge

Capture clock edge (at destination FF clock pin):
              ___
             |   |
_____________|   |____
             ^
             Capture edge (= Launch edge + T_period for same-clock path)

Data path timeline (from launch FF Q to destination FF D):

Launch edge
    |
    |-- T_clk2q (FF clock-to-output propagation) ---|
                                                    |
                                                    |-- T_logic (combinational delay) ---|
                                                                                         |
                                                                                         |-- T_routing (net delay) --> Data arrives at D

Required arrival time at D = Capture edge - T_setup(destination FF)
                           = Launch edge + T_period - T_setup

Slack = Required - Actual
      = (Launch edge + T_period - T_setup) - (Launch edge + T_clk2q + T_logic + T_routing)
      = T_period - T_setup - T_clk2q - T_logic - T_routing

For a positive slack (path passes):
T_period > T_setup + T_clk2q + T_logic + T_routing
```

**Also accounting for clock skew:**

In a real design, the launch and capture clocks arrive at different times due to clock network skew (T_skew):

```
Capture edge actual = Launch edge + T_period + T_skew

Slack = T_period + T_skew - T_setup - T_clk2q - T_logic - T_routing
```

Positive skew (capture clock arrives later than launch clock) helps setup slack. Negative skew hurts setup.

**Hold timing check (different equation, same clock):**

For hold, the check prevents the data launched by the CURRENT edge from overwriting data captured by the SAME edge:

```
Hold Slack = Actual arrival - (Capture edge + T_hold)
           = (Launch edge + T_clk2q + T_logic + T_routing) - (Launch edge + T_hold)
           = T_clk2q + T_logic + T_routing - T_hold - T_skew (skew hurts hold)
```

Hold violations increase when the data path is very fast (short logic + routing) and the clock has large positive skew.

---

### Critical path identification

**Q: You have 200 failing paths after implementation. Describe the first 10 minutes of your diagnostic process.**

**A:**

**Minute 1–2: Read the timing summary header**

```tcl
report_timing_summary -file timing_summary.rpt
```

Look at:
- WNS: How bad is the worst path?
- TNS: How many paths are failing?
- Which clock domains have failures?

If failures are concentrated in one clock domain, that is the starting point. If failures are spread across all domains, the problem is more likely a global issue (clocking, floorplanning, utilisation).

**Minute 3–5: Examine the worst path**

```tcl
report_timing -delay_type max -max_paths 1 -nworst 1 -path_type full_clock_expanded
```

Read the path report:
- Where does it start? (source cell, clock, pin)
- Where does it end? (destination cell)
- What is the breakdown? (how much is logic delay vs routing delay?)
- How many logic levels are in the path?

A path with 20+ logic levels is a deep combinational path — fix in RTL (pipeline).
A path with 2 logic levels but large routing delay is a placement problem — fix with floorplanning or directives.
A path spanning multiple clock regions is a global routing issue — may need a BUFG on a high-fanout signal in the path.

**Minute 5–8: Categorise the failures**

```tcl
# Report top 50 paths to get a representative sample
report_timing -delay_type max -max_paths 50 -nworst 1 -sort_by slack \
              -file top50_paths.rpt
```

Group the 50 paths by:
- Source module
- Destination module
- Number of logic levels
- Estimated fix type (pipeline stage, fanout reduction, floorplan)

If 40 of the 50 paths all share the same source module, that module is the bottleneck.

**Minute 8–10: Check for systematic root causes**

```tcl
# Check if high-fanout nets are involved
report_timing -delay_type max -max_paths 10 -path_type full \
    | grep -E "Source|Destination|Slack|Levels"
```

Look for:
- High-fanout nets appearing in multiple failing paths (replicate the driver)
- All paths ending in the same destination clock domain (check the clock constraint)
- All paths crossing an SLR boundary (need pipeline registers at the boundary)
- All paths starting from the same output (the source register is too far from destinations)

---

## Intermediate

### Closing setup violations

**Q: A path has a setup slack of -1.2 ns with 12 logic levels and a routing delay that accounts for 60% of the total path delay. What approaches are available, ranked by invasiveness, and which would you try first?**

**A:**

The path characteristics:
- 12 logic levels → moderate depth (not trivially reducible by adding one pipeline stage)
- 60% routing delay → placement is a significant contributor
- -1.2 ns → significant violation, not marginal

**Approaches ranked by invasiveness (least to most):**

**1. Physical optimisation (no design changes)**

```tcl
phys_opt_design -directive AggressiveExplore
```

`phys_opt_design` can rebalance logic, replicate drivers, and re-place cells on the critical path. For a routing-dominated path, it targets cell placement to shorten the nets. Effective for 0–0.5 ns recovery. With -1.2 ns to recover, this alone is likely insufficient.

**2. Different implementation directives**

```tcl
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore  ;# second post-route pass
```

`ExtraNetDelay_high` makes the placer assume pessimistic wire delays during placement, causing it to place cells more tightly. With 60% routing delay, this directive directly addresses the symptom.

**3. Floorplanning (Pblock)**

If the failing cells are spread across a large physical area, creating a Pblock forces them to be placed closer together:

```tcl
create_pblock pb_critical_path
add_cells_to_pblock [get_pblocks pb_critical_path] \
    [get_cells {source_module dest_module intermediate_cells}]
resize_pblock [get_pblocks pb_critical_path] \
    -add {SLICE_X20Y50:SLICE_X30Y70}
```

This requires knowing the physical location of the cells (visible in Vivado's Device view).

**4. RTL retiming (enable if not already on)**

```tcl
synth_design -retiming
```

Retiming can redistribute existing registers to balance the 12-level path. Effective only if there are registers before/after the combinational cloud that can be redistributed.

**5. RTL pipelining (moderate invasiveness)**

Add a pipeline register in the middle of the 12-level logic:

```verilog
// Before: 12 levels of combinational logic in one stage
always_ff @(posedge clk)
    result <= f12(f11(f10( ... f1(a, b) ... )));

// After: split into two 6-level stages
always_ff @(posedge clk)
    mid_result <= f6(f5(f4(f3(f2(f1(a, b))))));  // 6 levels
always_ff @(posedge clk)
    result     <= f12(f11(f10(f9(f8(f7(mid_result))))));  // 6 levels
```

This increases latency by one cycle but reduces the clock period requirement to approximately half the original critical path.

**6. Algorithmic restructuring (highest invasiveness)**

If the logic implements a priority encoder, adder tree, or comparator that inherently has depth, replace it with a faster structure (carry-lookahead adder, Wallace tree multiplier, binary-to-one-hot encoder).

**First action for this specific case:** Given the 60% routing contribution, start with `ExtraNetDelay_high` placement + aggressive post-route physical optimisation. If that recovers < 0.8 ns, add a Pblock around the critical cells. If still failing, add a pipeline stage.

---

### Hold closure after setup is met

**Q: After closing setup timing (WNS ≥ 0), you now have WHS = -0.15 ns. Setup closure took several implementation iterations. How do you close hold without re-opening setup violations?**

**A:**

Hold violations cannot be fixed by slowing the clock. They require the data path to be made slower (longer delay) so the data does not arrive at the destination register before the hold window expires.

**Key insight:** Hold is typically fixed by the tool automatically during routing (Vivado's router adds delay buffers on hold-critical paths). However, if the router did not fix all hold paths, `phys_opt_design -hold_fix` handles residual hold violations:

```tcl
# After route_design completes with setup passing:
phys_opt_design -hold_fix -directive AggressiveExplore
```

`phys_opt_design -hold_fix` inserts delay elements (IDELAY on I/O paths, or re-routing to longer paths) specifically for hold. It does not re-optimise setup paths unless they are the source of new hold failures.

**Risk of opening setup violations:**

Adding delay to a hold path increases the data arrival time, which helps hold but slightly increases the setup arrival time too. If the setup slack is thin (< 0.1 ns), hold fixes can convert setup pass to setup fail.

**Strategy to avoid this:**

1. Run hold fix after setup is comfortably closed (WNS > 0.2 ns provides a buffer).
2. Use `-min_paths` and `-max_paths` to limit hold-fix operations to the worst paths:

```tcl
# Fix only the 20 worst hold paths
phys_opt_design -hold_fix -max_paths 20
report_timing_summary  ;# verify setup is not degraded
```

3. If a hold-fix opens a setup violation, it often means the data path in question is simultaneously on the setup critical path. The solution is to relocate one of the registers physically — place the source and destination FF closer together to reduce both setup and hold variations.

4. For CDC-related hold violations (data crossing asynchronous clock domains), hold should not be checked — verify that the path has a `set_false_path` or `set_clock_groups -asynchronous` constraint.

---

### Reading a detailed timing report

**Q: Interpret the following timing report excerpt and identify the dominant source of delay. Propose specific fixes.**

```
Path Group:  CLK_200
Path Type:   Setup (Max at Slow Process Corner)
Slack:       -0.612ns

  Source:      alu_core/adder_inst/carry_reg[7]
               (rising edge-triggered cell FDRE clocked by CLK_200)
  Destination: output_buffer/result_reg[15]
               (rising edge-triggered cell FDRE clocked by CLK_200)

  Data Path Delay:    6.891ns  (logic 1.243ns   routing 5.648ns)
  Clock Path Skew:   -0.201ns

  Logic Levels:   4
  Data Path:
  -------------------------------------------------------------------
    FDRE (Prop_FDRE_C_Q)          0.141ns   carry_reg[7] -> carry_net[7]
    LUT6 (Prop_LUT6_I2_O)         0.352ns   carry_lut -> sum_partial[7]
    LUT4 (Prop_LUT4_I0_O)         0.314ns   sum_adj_lut -> adjusted[7]
    LUT6 (Prop_LUT6_I3_O)         0.436ns   final_lut -> result_net[15]
    FDRE (Setup_FDRE_C_D)         0.110ns   result_reg[15]
  Total Logic:                    1.243ns

  Routing:
    carry_net[7]  (fanout=1)      0.891ns
    sum_partial[7] (fanout=8)     1.732ns    ← HIGH
    adjusted[7]   (fanout=1)      0.412ns
    result_net[15] (fanout=1)     2.613ns    ← VERY HIGH
  Total Routing:                  5.648ns
```

**A:**

**Analysis:**

The total path delay is 6.891 ns on a 5.000 ns clock (200 MHz). The slack is -0.612 ns. Clock skew of -0.201 ns hurts setup (capture clock arrives late relative to launch clock).

**Logic delay (1.243 ns):** 4 LUT levels at an average of ~0.31 ns per LUT. This is normal for LUT6 paths. Not the problem.

**Routing delay (5.648 ns — 82% of total path delay):** This is the problem. Two nets dominate:

- `sum_partial[7]` has **fanout=8** and 1.732 ns routing delay. This net fans out to 8 sinks across (likely) different CLB regions.
- `result_net[15]` has **fanout=1** but **2.613 ns routing delay**. A single-fanout net with 2.6 ns routing delay means the source and destination are placed approximately 15–20 CLB tiles apart. This is a placement problem.

**Proposed fixes:**

**Fix 1: Address `result_net[15]` routing delay (highest impact)**

The source (`final_lut`) and destination (`result_reg[15]`) are far apart. Use Vivado's device view to confirm their physical locations. Create a Pblock containing both cells:

```tcl
# Find the cells driving and receiving result_net[15]
get_cells -of_objects [get_nets result_net[15]]
# Then constrain them to the same clock region
```

Alternatively, run `phys_opt_design -directive ExploreWithHoldFix` — the tool may relocate `result_reg[15]` closer to `final_lut` automatically.

**Fix 2: Reduce fanout on `sum_partial[7]`**

The net drives 8 sinks. Each additional hop to a distant sink adds routing delay. Replicate the driving LUT (`sum_adj_lut`) so each copy drives fewer sinks:

```tcl
# Force replication via attribute on the driving cell
set_property MAX_FANOUT 4 [get_cells {alu_core/adder_inst/sum_adj_lut}]
```

Or in RTL:
```verilog
(* keep = "true" *) logic sum_partial_copy1, sum_partial_copy2;
assign sum_partial_copy1 = sum_partial;  // drives sinks 1-4
assign sum_partial_copy2 = sum_partial;  // drives sinks 5-8
```

**Fix 3: Address clock skew (-0.201 ns)**

Negative clock skew hurts setup. Verify that both `carry_reg[7]` and `result_reg[15]` are on the same clock buffer path. If they are in different clock regions, consider relocating one of them.

**Expected recovery:** Fixing `result_net[15]` from 2.613 ns to ~0.4 ns (same region) recovers approximately 2.2 ns — more than sufficient to close the -0.612 ns violation.

---

## Advanced

### Systematic timing closure methodology

**Q: You are the lead engineer on a new design targeting 500 MHz on a UltraScale+ device. The first implementation run shows WNS = -3.2 ns with TNS = -890 ns across 340 failing paths. Describe your full methodology for achieving timing closure.**

**A:**

A -3.2 ns WNS is a severe violation requiring systematic analysis, not iterative tool retrying. The methodology proceeds from broadest to most specific:

**Phase 1: Establish the scope (day 1)**

```tcl
# Full timing analysis
report_timing_summary -file timing_summary_v1.rpt
report_design_analysis -logic_level_distribution -file logic_levels.rpt
report_design_analysis -congestion -file congestion.rpt
```

Categorise the 340 failing paths:
- Logic-dominated (> 8 levels): candidates for RTL pipelining
- Routing-dominated (logic < 30% of path delay): placement problem
- Clock-skew-dominated: MMCM/PLL configuration or clock routing issue
- Crossing SLR boundaries (if SSI device): missing pipeline registers at crossing

**Phase 2: Address RTL-level issues (days 1–3)**

For paths with > 8 logic levels at 500 MHz (2 ns period, max ~6 levels is realistic):
- Add pipeline registers to split deep combinational paths
- Enable retiming (`synth_design -retiming`) for automatic redistribution
- Review arithmetic paths: ensure adders and comparators are inferred with carry-chain primitives, not pure LUT logic

```tcl
# Re-run synthesis with retiming and performance directive
synth_design -top my_top -part xcvu9p-flga2577-2-e \
             -directive PerformanceOptimized \
             -retiming
```

**Phase 3: Address floorplanning (days 2–4)**

If the congestion report shows hotspots or if routing dominates the failures:
- Partition the design by function into SLR regions (for SSI devices)
- Create Pblocks for modules that show up repeatedly in failing paths
- Ensure no module's Pblock exceeds 75% resource utilisation

**Phase 4: Iterative implementation with targeted directives (days 3–5)**

Run a matrix of implementation strategies. For 500 MHz targets, emphasise timing-driven placement:

```tcl
# Strategy for placement-dominated violations
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
```

Compare WNS/TNS across strategies. Track improvement per iteration.

**Phase 5: Path-by-path closure for residual violations**

Once WNS is below -0.5 ns with < 20 failing paths, switch to path-by-path analysis:
- For each remaining failing path, read the full timing report
- Apply the minimum-invasive fix (Pblock, fanout reduction, pipeline stage)
- Re-run only implementation (not synthesis) after each RTL change

**Phase 6: Hold closure and sign-off**

```tcl
phys_opt_design -hold_fix -directive AggressiveExplore
report_timing_summary  ;# verify WNS ≥ 0, WHS ≥ 0, WPWS ≥ 0
```

Run at multiple corners: slow (worst setup) and fast (worst hold). Generate the final timing report for sign-off.

**Interview meta-answer:** The key differentiator in this answer is the structured approach. Candidates who say "I would try different directives" are treating timing closure as luck. Candidates who categorise violations by root cause, fix root causes systematically, and use tool-directed iteration intelligently demonstrate real engineering experience.

---

### Timing exceptions as a timing closure tool

**Q: A colleague suggests adding `set_false_path` to the 30 remaining failing paths to "fix" the timing violations. What is your response, and under what narrow circumstances would this approach be legitimate?**

**A:**

Using `set_false_path` to suppress timing violations is almost always wrong in production design. The colleague's suggestion should be pushed back on strongly.

**Why it is wrong:**

`set_false_path` does not fix timing. It tells the tool to stop checking the path. The physical delay on that path remains exactly what it was. At the target operating frequency:
- If the path has -0.3 ns slack, the flip-flop may or may not capture the correct data
- This becomes a frequency-dependent intermittent failure — the worst kind to debug in silicon

Additionally, suppressing checks removes the tool's ability to warn about that path in future runs. If a subsequent change makes the violation worse, no error will be reported.

**The narrow legitimate use cases:**

1. **The path is genuinely asynchronous.** A CDC path from domain A to domain B has no timing relationship to verify. Here, `set_false_path` is correct, and the synchroniser handles safety. Verify with `report_cdc`.

2. **The signal changes only during a non-functional phase.** A scan chain path, a JTAG path, or a hardware configuration input that changes only at power-on. The path timing is irrelevant during normal operation. Document this with a comment in the XDC.

3. **The path leads to a registered output that is not used in the critical operating mode.** For example, a debug register read-back path. Even here, consider whether the signal could unexpectedly affect operation.

**Correct response to the colleague:**

"We should not use `set_false_path` on paths that should be timed. I want to understand why these 30 paths are failing — are they deep combinational paths that need pipelining, or placement-driven? If any of them are genuinely asynchronous or test-only, we can apply false paths there with documentation. For the functional paths, we need to fix the root cause."

This response demonstrates both technical knowledge and engineering ethics around design quality.

---

## Common Mistakes and Pitfalls

1. **Confusing WNS with TNS.** WNS drives what to fix first (the worst path). TNS indicates scope. A design with WNS = -0.1 ns and TNS = -200 ns has hundreds of near-failing paths — fixing the worst path gains almost nothing.

2. **Running hold fix before setup is closed.** Hold fix inserts delay, which can push marginally-passing setup paths into failure. Always close setup first.

3. **Not specifying the corner.** Setup analysis uses the slow (SS, low voltage, high temperature) corner. Hold analysis uses the fast (FF, high voltage, low temperature) corner. Verify that `report_timing_summary` is being run at both corners.

4. **Interpreting routing delay as purely a tool problem.** Routing delay reflects physical distance between cells. Reducing it requires placing cells closer together (floorplanning), not just retrying the route.

5. **Chasing the critical path without checking TNS trends.** If fixing the critical path reveals many paths at -0.3 ns (previously masked by the -3.2 ns WNS), TNS has actually increased. Monitor TNS as a measure of overall convergence, not just WNS.

6. **Running phys_opt_design only once.** Post-placement physical optimisation uses estimated routing delays. Post-routing physical optimisation has exact delay information. Always run `phys_opt_design` again after `route_design`.

---

## Quick Reference

| Metric | Description | Positive = |
|---|---|---|
| WNS | Worst negative slack (setup) | All setup paths passing |
| TNS | Sum of all negative setup slacks | Zero when all paths pass |
| WHS | Worst hold slack | All hold paths passing |
| WPWS | Worst pulse width slack | All clock widths sufficient |

| Technique | When to use |
|---|---|
| `phys_opt_design -directive AggressiveExplore` | First tool response to any violation |
| `place_design -directive ExtraNetDelay_high` | Routing dominates path delay (> 60%) |
| `place_design -directive AltSpreadLogic_high` | Congestion is the root cause |
| Pblock around critical cells | Path delay dominated by long routing, cells far apart |
| RTL pipeline stage | Logic depth > 6 levels at 500 MHz, > 8 at 300 MHz |
| Fanout reduction / replication | Single net appears in many failing paths |
| `phys_opt_design -hold_fix` | Hold violations after setup is closed |
| `set_false_path` | ONLY for genuinely asynchronous or non-functional paths |
| `set_multicycle_path` | Paths that have N cycles to propagate by design |
