# Vivado vs Quartus Prime: Tool Workflows and Ecosystems

Comparative interview preparation covering AMD/Xilinx Vivado and Intel Quartus Prime Pro/Standard
toolchains. Both tools follow the same high-level FPGA design flow (synthesis, place and route,
timing analysis, bitstream generation) but differ substantially in architecture, scripting interfaces,
GUI philosophy, and the constraints they impose on the engineer. Understanding these differences is
essential for roles that involve multi-vendor FPGA work or migration projects.

---

## Tier 1 — Fundamentals

### Core Concepts

**Vivado Design Suite** (AMD/Xilinx) replaced ISE in 2012. It is the mandatory tool for 7-series and
above devices. The suite covers synthesis (Vivado Synthesis or third-party Synplify), implementation
(place and route), timing analysis via the Timing Analysis engine (report_timing_summary), static
simulation setup, and bitstream generation. Vivado uses XDC (Xilinx Design Constraints) files, which
are a strict superset of SDC (Synopsys Design Constraints).

**Quartus Prime** (Intel) comes in three editions: Lite (free, limited devices), Standard, and Pro.
Quartus Prime Pro introduced a fundamentally redesigned compilation flow built around a new
"Hyperflex" architecture (Stratix 10, Agilex). The Pro edition changed place and route significantly:
routing is now pipelined and the concept of "hyper-registers" allows the tool to insert pipeline
registers on routing interconnect. Standard edition targets Arria 10 and below and retains the legacy
flow. Quartus uses SDC for timing constraints with Intel-specific extensions (e.g.,
`set_instance_assignment`).

**Design flow comparison (both tools):**

```
RTL (VHDL / SystemVerilog / Verilog)
         |
    Synthesis  <--- constraints file (XDC / SDC)
         |
   Netlist (post-synthesis)
         |
  Implementation / Compilation
    - Technology mapping
    - Place and Route
         |
   Timing Analysis (Static)
         |
   Bitstream / Programming File
         |
   Device Programming (JTAG / configuration)
```

**Key terminology mapping:**

| Concept              | Vivado Term               | Quartus Term                  |
|----------------------|---------------------------|-------------------------------|
| Synthesis tool       | Vivado Synthesis / Synplify | Quartus Synthesis / Synplify |
| P&R engine           | Implementation            | Fitter                        |
| Timing analysis      | Timing Analysis (report_timing_summary) | TimeQuest Timing Analyzer |
| Constraints file     | XDC                       | SDC (.sdc)                    |
| Logic cell           | LUT/CLB                   | ALM (Adaptive Logic Module)   |
| Debug insertion      | Debug Core insertion (ILA/VIO) | Signal Tap Logic Analyzer  |
| Configuration memory | bitstream (.bit / .bin)   | .sof / .pof                   |
| Partial reconfig     | Dynamic Function eXchange (DFX) | Partial Reconfiguration   |

---

### Fundamentals Interview Questions

**Q1. What are the mandatory steps in a Vivado implementation run, and what is produced at each step?**

Answer:

A Vivado implementation run consists of these ordered steps:

1. `opt_design` -- Logic optimisation on the synthesised netlist. Removes redundant logic, merges LUTs,
   propagates constants. Produces an optimised netlist still in memory.

2. `place_design` -- Assigns logical primitives to physical sites on the device. Produces a placed
   design. Vivado's placer uses a simulated-annealing-based algorithm with timing-driven refinement.

3. `phys_opt_design` (optional but strongly recommended) -- Post-placement physical optimisation.
   Performs path replication, hold buffer insertion, and retiming. Can be run multiple times.
   Particularly valuable for high-utilisation designs or those just failing timing.

4. `route_design` -- Routes all nets. Produces a fully routed design. Timing is evaluated in the
   context of actual routing delays.

5. `phys_opt_design` (post-route, optional) -- A second physical optimisation pass using accurate
   post-route delay information.

6. `write_bitstream` -- Generates the configuration bitstream (.bit file). The .bin file (for SPI
   flash) requires the `-bin_file` switch.

Common mistake: skipping `phys_opt_design` when timing is marginal. It often recovers 10--20% of
failing paths without any RTL change.

---

**Q2. What is the difference between Quartus Prime Standard and Quartus Prime Pro, and why does the distinction matter?**

Answer:

The editions target different device families and use fundamentally different compilation engines:

- **Standard edition**: Targets Arria 10, Cyclone V, MAX 10, and older families. Uses the
  "Classic" fitter. The place and route engine treats routing as passive interconnect. Standard
  edition supports Arria 10 but not Stratix 10 or Agilex.

- **Pro edition**: Mandatory for Stratix 10, Agilex 7/5, and Agilex M-Series. Uses the
  "Hyper-Aware" fitter designed for Hyperflex architecture. In Hyperflex devices, every routing
  segment has a register site (hyper-register), and the fitter can insert pipeline stages into the
  routing fabric itself. This means the fitter collaborates with RTL retiming in a way that has no
  equivalent in Standard or Vivado.

The distinction matters because:
- Constraints that work in Standard may not transfer directly to Pro.
- Pro introduces `set_max_skew` and new assignment syntax.
- The compilation flow in Pro is multi-pass by default (early place, route, retime).
- Scripted flows (Tcl) differ in available commands between editions.

---

**Q3. What is an XDC file and how does it differ from a plain SDC file?**

Answer:

SDC (Synopsys Design Constraints) is an industry-standard format for timing constraints, supported by
Synopsys PrimeTime and all major FPGA tools. It defines clocks, I/O timing requirements, false paths,
multicycle paths, and clock groups using Tcl commands.

An XDC file is an SDC file extended with Vivado-specific physical and non-timing constraints:

- `set_property PACKAGE_PIN` -- Pin location assignments.
- `set_property IOSTANDARD` -- I/O voltage standard (LVCMOS33, LVDS, etc.).
- `set_property BITSTREAM.*` -- Bitstream configuration options.
- `create_pblock` / `add_cells_to_pblock` -- Floorplanning regions.
- `set_property LOC` -- Direct site placement (lock a BRAM to a specific site).
- `set_property MARK_DEBUG` -- Flags nets for ILA insertion.

Because XDC is processed sequentially (unlike SDC, which is order-independent), the order of commands
matters in Vivado. A `set_property` placed before a net is created by synthesis will silently have no
effect.

Quartus uses plain SDC for timing, with physical constraints in `.qsf` (Quartus Settings File) using
`set_location_assignment` and `set_instance_assignment` Tcl commands.

---

**Q4. In Quartus, what is the TimeQuest Timing Analyzer and how does it relate to SDC?**

Answer:

TimeQuest is Intel's static timing analysis engine, integrated into Quartus. It performs STA after
the fitter completes and uses the SDC constraint file as its input. TimeQuest works in two passes:

1. **Setup analysis** -- Checks that data arrives at flip-flop inputs at least `t_su` before the
   capturing clock edge. Reports setup slack.
2. **Hold analysis** -- Checks that data is stable for at least `t_h` after the capturing clock edge.
   Reports hold slack.

TimeQuest reads the SDC file to understand which clocks exist, their frequencies, and relationships.
Without an SDC file (or with an incomplete one), TimeQuest makes pessimistic assumptions and many
paths appear unconstrained, which means they are not timed at all -- a dangerous situation for
production designs.

Key Quartus-specific SDC commands not found in standard SDC:
- `derive_pll_clocks` -- Automatically creates clock constraints for all PLL outputs.
- `derive_clock_uncertainty` -- Applies JTAG and PLL-specific jitter models.

The Vivado equivalent workflow: `report_timing_summary` uses the XDC constraints to perform STA.
Vivado's `create_generated_clock` is the manual equivalent of Quartus's `derive_pll_clocks`.

---

## Tier 2 — Intermediate

### Intermediate Concepts

**Vivado non-project mode vs project mode**: Vivado can be driven in "project mode" (GUI-centric,
stores a .xpr project file) or "non-project mode" (pure Tcl script, no persistent project state).
Production flows at large companies almost always use non-project mode for reproducibility and
integration with CI systems. In non-project mode you `read_vhdl`/`read_verilog`/`read_xdc`, then call
each step explicitly. In project mode, Vivado manages source files and run directories automatically.

**Quartus scripted flow**: Quartus uses a `.qpf` (project file) and `.qsf` (settings file). Scripted
flows use `quartus_map` (analysis and synthesis), `quartus_fit` (fitter), `quartus_sta`
(TimeQuest STA), `quartus_asm` (assembler, generates .sof/.pof), each as separate executables.
This is fundamentally different from Vivado, where the entire flow runs inside a single Tcl session.

**Synthesis engines**: Both tools offer first-party and third-party synthesis:
- Vivado: Vivado Synthesis (first-party) or Synplify Pro. Vivado Synthesis is tightly integrated and
  preferred for most designs. Synplify can yield better QoR for some datapath-heavy designs.
- Quartus: Quartus Synthesis (first-party) or Synplify. For Pro edition designs, Intel recommends
  Quartus Synthesis as Synplify does not understand hyper-register retiming opportunities.

---

### Intermediate Interview Questions

**Q5. Write a Vivado non-project mode Tcl script that synthesises and implements a design, then reports timing.**

Answer:

```tcl
# ---------------------------------------------------------------
# Vivado non-project mode implementation script
# Usage: vivado -mode batch -source build.tcl
# ---------------------------------------------------------------

# --- Read sources ---
read_vhdl -library work [glob ../src/*.vhd]
read_verilog                [glob ../src/*.v]
read_xdc                    ../constraints/top.xdc

# --- Synthesis ---
synth_design \
    -top        top_module   \
    -part       xczu9eg-ffvb1156-2-e \
    -flatten_hierarchy rebuilt

write_checkpoint -force ./checkpoints/post_synth.dcp

# --- Implementation ---
opt_design
place_design
phys_opt_design
route_design
phys_opt_design   ;# second pass with accurate routing delays

write_checkpoint -force ./checkpoints/post_route.dcp

# --- Timing reports ---
report_timing_summary \
    -max_paths  50 \
    -report_unconstrained \
    -file       ./reports/timing_summary.rpt

report_utilization \
    -file       ./reports/utilization.rpt

report_clock_interaction \
    -file       ./reports/clock_interaction.rpt

# --- Check for timing failures before writing bitstream ---
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if {$wns < 0} {
    puts "ERROR: Design has setup timing violations. WNS = $wns ns"
    exit 1
}

# --- Generate bitstream ---
write_bitstream -force ./output/top.bit
write_bitstream -force -bin_file ./output/top.bin

puts "Build complete. WNS = $wns ns"
```

Key points to explain in an interview:
- `-flatten_hierarchy rebuilt` keeps hierarchy visible in post-synthesis reports while still
  allowing cross-boundary optimisation.
- `write_checkpoint` saves the full design state; you can reload and re-run any stage from a DCP.
- Checking `$wns` before `write_bitstream` prevents generating a bitstream from a timing-failing
  design -- a real-world best practice.
- `report_clock_interaction` identifies potentially unsafe CDC paths that TimeQuest may not flag.

---

**Q6. In Quartus, how do you run a full compilation from the command line, and how does this compare to Vivado's approach?**

Answer:

Quartus separates compilation into discrete executables. A complete scripted flow:

```bash
#!/bin/bash
# Quartus command-line compilation flow
# Each executable is a separate process; all read/write the .qdb project database.

PROJECT="my_design"
REVISION="my_design"

# Step 1: Analysis and synthesis (equivalent to Vivado synth_design)
quartus_map  "$PROJECT" --rev="$REVISION" || exit 1

# Step 2: Partition merge (required for incremental flows, often skipped for simple builds)
# quartus_cdb  "$PROJECT" --rev="$REVISION" --merge || exit 1

# Step 3: Fitter (place and route, equivalent to Vivado place_design + route_design)
quartus_fit  "$PROJECT" --rev="$REVISION" || exit 1

# Step 4: Assembler (generates .sof / .pof programming files)
quartus_asm  "$PROJECT" --rev="$REVISION" || exit 1

# Step 5: Static Timing Analysis
quartus_sta  "$PROJECT" --rev="$REVISION" || exit 1

# Step 6: (Optional) EDA netlist writer for simulation or formal verification
# quartus_eda  "$PROJECT" --rev="$REVISION" || exit 1

echo "Compilation complete."
```

The `.qsf` file holds all assignments (pin locations, timing constraints file reference, device,
fitter seed, etc.) and is the Quartus equivalent of Vivado's XDC plus project settings.

**Comparison with Vivado:**

| Aspect               | Vivado                            | Quartus Pro                         |
|----------------------|-----------------------------------|-------------------------------------|
| Flow driver          | Single Tcl session                | Separate executables per stage      |
| State persistence    | DCP checkpoint files              | .qdb (Quartus Database) directory   |
| Incremental reuse    | `read_checkpoint` / `incremental_compile` | Rapid Recompile (block-level) |
| Parallel jobs        | `-jobs N` flag on place/route     | `--parallel` flag on fitter         |
| GUI vs script parity | High (same engine)                | High (same engine)                  |

---

**Q7. Explain Vivado's incremental implementation flow. When would you use it?**

Answer:

Vivado's incremental implementation reuses placement and routing from a previous run for logic that
has not changed, only re-implementing the modified portions. This dramatically reduces compile time
for late-stage ECOs (Engineering Change Orders) or when only a small portion of a large design
changes.

How it works:

```tcl
# Provide a "reference" checkpoint from a previous passing implementation
set_property incremental_checkpoint ./checkpoints/post_route_reference.dcp [current_run]

# Run implementation as normal -- Vivado will reuse unchanged placed/routed logic
launch_runs impl_1 -to_step write_bitstream
```

Vivado computes a "cell hash" for each hierarchical block. If a cell's hash matches the reference,
its placement and routing is copied directly. The tool then routes the delta (new/changed logic)
while preserving the existing placement. This is sometimes called "incremental compile" or
"ECO flow."

**When to use it:**
- Late RTL bug fixes where only one module changes.
- Adding or modifying ILA debug cores (the `MARK_DEBUG` flow).
- Iterating on top-level glue logic while a validated DSP core is frozen.
- CI flows where build time matters but full re-runs are occasionally needed to verify QoR.

**Risks:**
- If too much logic changes (>30% is a rough rule), incremental mode may produce worse QoR than a
  fresh run because the reference placement was optimised for different logic.
- The reference DCP must be from the same synthesis netlist (or a very close variant); mismatches
  cause Vivado to silently fall back to a full run.

Quartus equivalent: **Rapid Recompile** and **Design Partitions**. Quartus partitions can be frozen
(`set_instance_assignment -name PARTITION_COLOUR BLUE`) to prevent the fitter from touching them,
which is functionally similar but requires explicit partition setup in the QSF.

---

**Q8. What is Vivado's `report_cdc` and what does it catch that timing analysis does not?**

Answer:

`report_cdc` (Clock Domain Crossing report) performs structural analysis of the netlist to identify
signals that cross between asynchronous clock domains. Timing analysis (STA) deliberately ignores
inter-domain paths marked with `set_clock_groups -asynchronous` -- it must, because those paths have
no meaningful setup/hold relationship. This means STA cannot tell you whether the crossing is
properly synchronised; `report_cdc` fills that gap.

`report_cdc` identifies:

- **No synchroniser**: A signal crosses clock domains with no synchronisation primitive detected.
  Severity: Critical. This is a real metastability risk.
- **Incomplete synchroniser**: One flip-flop instead of two (or more) in the synchroniser chain.
- **Combo logic in synchroniser path**: Combinational logic between the source flip-flop and the
  synchroniser, which increases the probability of metastability settling into a wrong value.
- **Fanout from synchroniser output**: Multiple downstream registers, which can cause different
  parts of logic to see the synchronised value at different times.

```tcl
report_cdc -file ./reports/cdc.rpt -severity {Critical High}
```

Quartus equivalent: The **Metastability Analysis** in TimeQuest computes MTBF estimates for
synchroniser chains and identifies missing synchronisers. It is accessed via
`report_metastability` in the TimeQuest SDC console. Quartus also has `set_synchronizer_identification`
assignment to manually designate synchroniser flip-flops.

Key interview point: `report_cdc` uses pattern matching, not formal proof. It can miss CDC paths
that use unusual coding styles (e.g., MUX-based gray code encoders). Formal CDC tools (e.g.,
Mentor Questa CDC, Cadence JasperGold CDC) provide exhaustive structural analysis.

---

## Tier 3 — Advanced

### Advanced Concepts

**Vivado Synthesis attributes vs Quartus synthesis directives**: Both tools support vendor-specific
attributes embedded in RTL to guide synthesis. These attributes are not synthesised into logic; they
are read by the synthesis engine and influence optimisation decisions.

**Timing exception interaction**: Both tools support `set_false_path`, `set_multicycle_path`, and
`set_max_delay`. The subtle differences in how these interact with `set_clock_groups` and in the
priority ordering of exceptions cause real bugs in migrated designs.

**`set_max_delay -datapath_only`** (Vivado): Removes setup hold checking on a path and replaces it
with a maximum combinational delay constraint. Used for CDC paths where you want to bound
combinational delay but do not want standard synchronous STA. There is no direct Quartus equivalent;
in Quartus you use `set_max_delay` without the `-datapath_only` flag, but hold checking is not
suppressed.

---

### Advanced Interview Questions

**Q9. Compare how Vivado and Quartus handle timing exceptions priority. What can go wrong during a tool migration?**

Answer:

Both tools follow SDC priority rules, but the implementations diverge in edge cases.

**SDC exception priority (both tools, high to low):**
1. `set_false_path`
2. `set_multicycle_path`
3. `set_max_delay` / `set_min_delay`
4. Default clock-to-clock path analysis

**Vivado-specific behaviour:**
- `set_false_path -from [get_clocks clkA] -to [get_clocks clkB]` takes precedence over
  `set_multicycle_path` on the same path. This is correct per SDC, but many engineers forget it.
- `set_max_delay -datapath_only` in Vivado completely suppresses hold checking. This is used for
  asynchronous MUX-based CDC structures. If you migrate to Quartus and forget that Quartus does not
  support `-datapath_only`, the path gets standard hold checking and may fail with huge hold
  violations (since the intent was a CDC path with no hold relationship).
- `set_clock_groups -asynchronous` in Vivado exempts all paths between listed clock groups from
  both setup and hold checking. The equivalent in Quartus is `set_clock_groups -asynchronous` (same
  syntax) but Quartus prior to version 21.x had a known limitation where `set_clock_groups` did not
  properly suppress hold on some generated clock paths.

**Common migration pitfall -- multicycle path endpoints:**

In Vivado, `set_multicycle_path -setup 2 -from [get_cells src_reg]` automatically applies a
corresponding `set_multicycle_path -hold 1` to keep hold checking correct. If you do not explicitly
set the hold multicycle path in Quartus, the tool applies a 0-cycle hold check by default, which is
incorrect for a 2-cycle setup path and will cause spurious hold failures.

```tcl
# Vivado: setup multicycle -- hold is automatically adjusted
set_multicycle_path -setup 2 -from [get_cells {data_reg[*]}] -to [get_cells {output_reg[*]}]
# Vivado implicitly applies: set_multicycle_path -hold 1 ...

# Quartus: must be explicit
set_multicycle_path -setup 2 -from [get_registers {data_reg[*]}] -to [get_registers {output_reg[*]}]
set_multicycle_path -hold  1 -from [get_registers {data_reg[*]}] -to [get_registers {output_reg[*]}]
```

Note the difference in collection commands: Vivado uses `get_cells` for flip-flops in the netlist,
while Quartus TimeQuest uses `get_registers`.

---

**Q10. Explain Vivado's `phys_opt_design` transforms. Which are most impactful for high-speed designs?**

Answer:

`phys_opt_design` applies a set of netlist and placement transforms driven by estimated or actual
routing delays. The main transforms are:

**Critical path transforms (setup time recovery):**

- **Fanout optimisation (replication)**: Identifies high-fanout nets on critical paths and
  replicates the driving cell to reduce net load and routing distance. The replicated cell is
  placed near its local fanout cluster.
  
  ```tcl
  phys_opt_design -directive AggressiveFanoutOpt
  ```

- **DSP and BRAM register optimisation**: Moves registers into or out of DSP48/RAMB primitives
  to absorb pipeline stages. DSP48 has optional input registers (A, B, D registers) and the output
  register (P register). Moving a register into the DSP eliminates a separate slice FF and a routing
  hop.

- **Critical cell placement**: Re-places cells on the critical path to minimise routing detours.

**Hold time transforms:**

- **Hold fix (buffer insertion)**: Inserts LUT1 (buffer) cells on hold-critical paths to add
  deliberate delay. The tools prefer to insert these during `route_design` but `phys_opt_design`
  handles cases the router missed.

**Most impactful transforms for high-speed designs (>500 MHz UltraScale+):**

1. **Fanout replication** is usually the highest ROI action. A register driving 500 fanout will
   have long routing delays on the critical path; replication to groups of 50 can recover 0.5--1 ns.

2. **Post-route `phys_opt_design`** using actual routing delay (not estimated): run it after
   `route_design`. The first invocation (post-place) uses estimated delays which may not match
   reality for congested areas.

3. **Retiming across hierarchy**: `phys_opt_design -retime` moves registers backward or forward
   across combinational logic to balance pipeline stages. Requires that registers be at module
   boundaries.

```tcl
# Aggressive post-route physical optimisation recipe
phys_opt_design -directive AggressiveExplore
phys_opt_design -retime -directive AggressiveFanoutOpt
```

Quartus equivalent: Quartus Pro's fitter performs these operations automatically as part of its
Hyper-Aware compilation, including automatic register retiming. The engineer has less manual control
but the tool is more autonomous about inserting hyper-registers in routing.

---

**Q11. A design passes timing in Vivado on one fitter seed but fails on another. What are the underlying causes and what strategies address this?**

Answer:

This is a **seed sensitivity** problem and indicates the design is operating near the tool's
optimisation limit. The underlying causes are:

**Root causes:**

1. **Insufficient timing margin (WNS close to 0)**: If the design has < 100 ps of setup margin,
   small changes in placement due to different random seeds in the placer's simulated annealing
   algorithm result in pass/fail variance.

2. **Congestion**: High-utilisation regions force the router to use longer paths. Which cells end up
   in congested regions changes with seed; some placements route cleanly, others produce routing
   detours that cost hundreds of picoseconds.

3. **Critical path dependency on placement of nearby cells**: Vivado's timing-driven placer optimises
   the critical path, but the neighbourhood of that path influences routing resources available.
   Different seeds create different neighbourhood configurations.

**Strategies:**

1. **Add real timing margin**: The correct fix. Reduce the clock frequency in the constraint, add a
   pipeline stage on the failing path, or apply `set_multicycle_path` if the path genuinely does not
   need single-cycle latency.

2. **Run multiple seeds and select the best**: Automate seed sweeps with a Tcl loop:

   ```tcl
   # Seed sweep script -- run outside Vivado with xargs or LSF
   foreach seed {1 2 3 5 8 13 21 42 100 2024} {
       set_property STEPS.PLACE_DESIGN.ARGS.MORE_OPTIONS "-seed $seed" [get_runs impl_1]
       launch_runs impl_1 -to_step write_bitstream
       wait_on_run impl_1
       set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
       puts "Seed $seed: WNS = $wns"
   }
   ```

3. **Floorplanning**: Constrain the failing path's cells to a specific SLR (Super Logic Region) or
   pblock to eliminate cross-SLR routing variance.

4. **`phys_opt_design -directive AggressiveExplore`**: More optimisation effort can converge the
   design regardless of seed.

5. **Identify the root path**: If the same logical path fails across all seeds but with different
   slacks, the path itself is too long. Use `report_timing -from ... -to ...` to examine the
   path and address it in RTL or constraints.

In Quartus, the equivalent is varying the `--seed` argument to `quartus_fit`. The Pro edition's
Hyper-Aware flow is generally less seed-sensitive because hyper-register insertion can compensate
for routing variance, but seed sensitivity still occurs on routes near the device boundary or
in congested DSP columns.

---

**Q12. Compare Vivado's Debug Core insertion flow with Quartus Signal Tap. What are the tradeoffs of each approach?**

Answer:

Both flows insert a logic analyser core post-synthesis into the implemented netlist, which avoids
re-synthesising the design. This is critical because re-synthesis can change placement and timing.

**Vivado ILA insertion (netlist-based flow):**

```tcl
# Mark nets for debug in XDC (preferred: synthesise with marks, insert core post-synth)
set_property MARK_DEBUG true [get_nets {data_bus[*] valid_flag}]

# After synthesis, open the synthesised checkpoint and insert debug cores
open_checkpoint post_synth.dcp
implement_debug_core
write_checkpoint -force post_debug.dcp

# Alternatively, use the "Set Up Debug" wizard in the GUI
```

The ILA core is inserted as a standard IP core instance. The netlist then proceeds through
implementation normally. The ILA consumes BRAMs (for sample storage), LUTs (for trigger logic),
and a BSCAN primitive for JTAG access. After routing, the debug hub IP is automatically instantiated
to connect all ILA/VIO cores to the JTAG chain.

**Quartus Signal Tap (incremental insertion):**

Signal Tap uses a `.stp` file configured in the Signal Tap Logic Analyzer GUI. The flow compiles
the Signal Tap core into the design during the fitter stage using **incremental compilation**. The
key difference is that Signal Tap hooks into the design at the post-fit netlist level (not the
synthesised netlist), which means it uses Quartus's **ECO (Engineering Change Order)** capabilities.

**Tradeoff comparison:**

| Aspect                      | Vivado ILA                              | Quartus Signal Tap                    |
|-----------------------------|------------------------------------------|---------------------------------------|
| Insertion point             | Post-synthesis (before P&R)             | Post-fit (incremental ECO)            |
| Re-route required           | Yes (full route with ILA in netlist)    | Partial re-route (incremental)        |
| Timing impact               | Can affect design timing                | Minimal if incremental compile works  |
| BRAM consumption            | Explicit, user-configured depth/width   | Similar explicit configuration        |
| Trigger complexity          | Up to 4 trigger conditions, Boolean     | Up to 10 trigger conditions, Boolean  |
| Cross-trigger               | Yes (via trigger ports between ILAs)    | Yes (via Signal Tap trigger ports)    |
| JTAG access                 | Vivado Hardware Manager                  | Quartus Signal Tap GUI                |
| Script automation           | Full Tcl API (`write_debug_probes`)     | Partial (`.stp` file + quartus_cdb)   |

**When timing impact is a concern:** The Vivado flow can change routing for nearby nets because it
inserts probe connections. Using `KEEP_HIERARCHY` and `MARK_DEBUG` together with incremental
implementation mitigates this but does not eliminate it. Signal Tap's ECO approach is generally
less disruptive but requires the incremental partition flow to be set up correctly in advance.

---

## Quick Reference: Vivado vs Quartus Command Equivalents

```
SYNTHESIS
  Vivado:   synth_design -top <top> -part <part>
  Quartus:  quartus_map <project> --rev=<revision>

PLACE AND ROUTE
  Vivado:   place_design; route_design
  Quartus:  quartus_fit <project> --rev=<revision>

TIMING REPORT
  Vivado:   report_timing_summary -max_paths 50
  Quartus:  quartus_sta <project> --rev=<revision>  (then report_timing in TimeQuest)

BITSTREAM / PROGRAMMING FILE
  Vivado:   write_bitstream design.bit
  Quartus:  quartus_asm <project> --rev=<revision>  (produces .sof / .pof)

CDC REPORT
  Vivado:   report_cdc
  Quartus:  report_metastability  (in TimeQuest)

UTILISATION REPORT
  Vivado:   report_utilization
  Quartus:  (in Compilation Report -> Fitter -> Resource Section)

OPEN CHECKPOINT
  Vivado:   open_checkpoint design.dcp
  Quartus:  (open .qdb via GUI or quartus_cdb)

SEED CONTROL
  Vivado:   set_property STEPS.PLACE_DESIGN.ARGS.MORE_OPTIONS "-seed N" [get_runs impl_1]
  Quartus:  quartus_fit <project> --seed=N
```
