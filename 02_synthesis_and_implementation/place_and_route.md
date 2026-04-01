# Place and Route

Place and route (PAR) is the implementation phase that maps a synthesised netlist to physical silicon resources. A thorough understanding of PAR is critical for debugging timing closure failures and explaining implementation trade-offs in interviews. This topic tests whether a candidate understands the tool as a black box versus having genuine hands-on experience.

---

## Table of Contents

- [Fundamentals](#fundamentals)
- [Intermediate](#intermediate)
- [Advanced](#advanced)
- [Common Mistakes and Pitfalls](#common-mistakes-and-pitfalls)
- [Quick Reference](#quick-reference)

---

## Fundamentals

### The implementation flow

**Q: Describe the stages of FPGA implementation after synthesis. What does each stage do, and what is the output?**

**A:**

In Vivado, implementation (`impl_design`) comprises the following sequential steps:

**1. `opt_design` — Logic optimisation**

Performs gate-level optimisation on the synthesised netlist before placement. Key actions:
- Removes redundant logic (constants, unused cells)
- Rearranges LUT equations for better packability
- Optimises control sets (resets, clock enables) to reduce flip-flop packing fragmentation

Output: An optimised netlist, still unplaced.

**2. `place_design` — Placement**

Assigns each netlist cell (LUT, FF, DSP, BRAM, IOB) to a specific physical site on the device. The placer optimises for:
- Wire length (shorter wires → faster routing, lower power)
- Clock region boundaries (clocks cannot cross certain boundaries without buffering)
- Packing (LUTs and FFs sharing a CLB site reduce wire delays)

Output: A placed netlist where every cell has a `LOC` property.

**3. `phys_opt_design` — Physical optimisation (post-placement)**

Re-optimises the placed netlist with knowledge of physical coordinates. Actions:
- Critical path buffering and net splitting
- Logic replication to reduce fanout on long wires
- DSP and BRAM input register retiming with physical awareness

This step can be run multiple times. It is the most powerful timing closure step available without changing RTL.

Output: An improved placed netlist.

**4. `route_design` — Routing**

Assigns physical interconnect resources (routing tracks, switch boxes) to every net. The router operates in passes:
- Global routing: assigns approximate routing channels
- Detailed routing: assigns specific wires and switch settings

Output: A fully routed netlist where every net has an exact physical path.

**5. Timing sign-off (`report_timing_summary`)**

After routing, timing is now fully accurate (no wire-load models). The implementation passes only if all timing constraints are met (WNS ≥ 0, WHS ≥ 0, WPWS ≥ 0).

---

### Placement algorithms

**Q: What placement algorithm does a modern FPGA tool like Vivado use? Why does placement order matter, and what does the term "seed" mean in this context?**

**A:**

Modern FPGA placers use a combination of techniques:

**Analytical placement** — Treats placement as a continuous relaxation problem. Each cell is initially placed at its "ideal" location based on wire-length minimisation (a linear or quadratic objective). The placement is then legalised to snap cells to actual sites while preserving the approximate positions.

**Simulated annealing refinement** — After analytical placement, a perturbation-based search makes random moves (swapping, shifting cell clusters) and accepts or rejects moves based on a cost function (wire length + timing). The "temperature" parameter controls how often worse solutions are accepted — high temperature early (broad exploration), low temperature late (local optimisation).

**Timing-driven refinement** — The placer incorporates static timing analysis feedback. Cells on the critical path are placed with higher priority to minimise wire length on timing-critical nets.

**Seed:** The annealing and random perturbation steps use a pseudo-random number generator. The seed initialises this generator. Different seeds produce different placement results with similar average quality but occasionally one seed produces a significantly better result. This is the basis of the "try different seeds" strategy for difficult timing closure:

```tcl
# Vivado: try a different placement seed
place_design -directive Default
# or, to specify the seed via a property:
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExplorePostRoutePhysOpt [get_runs impl_1]
```

In Vivado, seed exploration is managed via implementation run strategies in the GUI, or by running multiple `impl_design` calls with different directive settings.

---

### Routing architecture

**Q: Explain the FPGA routing architecture. What are switch boxes, connection boxes, and routing tracks? Why does congestion occur, and what are its symptoms?**

**A:**

**Routing tracks** are horizontal and vertical wire segments embedded in the routing fabric. In Xilinx UltraScale+, tracks come in different lengths: single (1 CLB), double (2 CLB), quad (4 CLB), long (spanning a full column or row). Longer tracks reduce the number of hops for long-distance connections but are a shared, limited resource.

**Switch boxes (SB)** are programmable crossbar elements at the intersection of routing tracks. A switch box connects horizontal and vertical tracks. The set of connections available in a switch box is called the **switch box topology** (e.g., Wilton, Subset, Universal). Not every horizontal track connects to every vertical track — the limited connectivity is what makes routing a constrained problem.

**Connection boxes (CB)** connect routing tracks to the inputs and outputs of CLBs (LUT inputs, FF inputs, CLB outputs). Each CLB input is reachable from a limited set of nearby tracks.

**Congestion** occurs when the demand for routing resources in a region exceeds supply. Symptoms:
- `route_design` exits with unrouted nets
- Routing reports high "overflow" counts in congested tiles
- Timing gets worse than predicted by placement because the router is forced to use longer, indirect paths around congested areas
- `report_route_status` shows failed routes

```tcl
# Check routing status
report_route_status

# Examine congestion map
report_design_analysis -congestion -file congestion_report.txt
```

Congestion visualisation is available in Vivado's Device view (the gradient colour overlay showing routing utilisation per tile). A tile at 95%+ routing utilisation is effectively congested.

---

## Intermediate

### Congestion analysis and remediation

**Q: After place and route, `report_route_status` reports 147 unrouted nets. Walk through your diagnostic and remediation process.**

**A:**

**Step 1: Identify the congested region**

```tcl
# Generate the routing congestion report
report_design_analysis -congestion -file congestion.rpt

# In Vivado GUI: Window → Device → toggle Routing Congestion overlay
```

The report identifies hotspot tiles (typically expressed as a 1–8 congestion score, where 5+ is problematic).

**Step 2: Determine the cause**

Examine which logic is placed in the congested region:

```tcl
# Find cells in a problematic tile region
get_cells -filter {LOC =~ "SLICE_X50Y100:SLICE_X60Y110"}
```

Common root causes:

| Cause | Symptom | Remedy |
|---|---|---|
| Over-packed CLB region | High LUT/FF utilisation + high routing utilisation | Floorplan to spread logic; reduce overall utilisation |
| High-fanout net | One net uses many routing tracks | Replicate driver; use BUFG for clocks/control |
| Unsuitable placement directive | Placer clustered unrelated logic | Try `place_design -directive AltSpreadLogic_high` |
| Conflicting Pblock constraints | Logic forced into a too-small area | Relax or remove Pblock constraints |
| Wide buses through a narrow tile | Many parallel nets share the same crossing | Restructure logic or floorplan to avoid the crossing |

**Step 3: Apply targeted remediation**

```tcl
# Option A: Physical optimisation to reduce fanout in the congested area
phys_opt_design -directive AggressiveExplore

# Option B: Re-place with a congestion-aware directive
place_design -directive AltSpreadLogic_high
# or
place_design -directive SSI_SpreadSLLs  # for SSI devices (e.g., VU9P)

# Option C: Increase routing effort
route_design -directive AggressiveExplore

# Option D: If a specific Pblock is the cause, relax it
resize_pblock [get_pblocks my_pblock] -add {SLICE_X40Y90:SLICE_X70Y120}
```

**Step 4: Verify improvement**

Re-run `report_route_status` and `report_design_analysis -congestion`. Confirm WNS/WHS have not degraded.

**Candidate insight that impresses interviewers:** Mention that unrouted nets are a hard error (the bitstream cannot be generated), whereas timing violations are a soft warning (a bitstream can be produced but the device may malfunction at speed). Prioritise unrouted nets absolutely over timing violations.

---

### Placement directives comparison

**Q: Vivado offers multiple `place_design` directives: `Default`, `WLDrivenPlacement`, `ExtraNetDelay_high`, `AltSpreadLogic_high`, `SSI_SpreadSLLs`. When would you use each?**

**A:**

| Directive | Strategy | Use when |
|---|---|---|
| `Default` | Balanced wire length + timing | Normal designs; first attempt |
| `WLDrivenPlacement` | Minimise total wire length | Congestion is high; timing is secondary concern |
| `ExtraNetDelay_high` | Pessimistic wire delays during placement | Design is meeting timing at place but failing after route (placer underestimates routing delay) |
| `AltSpreadLogic_high` | Spreads logic across the device aggressively | Congestion in a localised region; overall utilisation is moderate |
| `SSI_SpreadSLLs` | Balances logic across SLR boundaries in SSI devices | Multi-die devices (VU9P, VU13P, Alveo U280) where SLL crossings are the timing bottleneck |
| `ExplorePostRoutePhysOpt` | Run aggressive post-route physical optimisation automatically | Near-timing-closure; WNS is -0.2 to -0.5 ns |

```tcl
# Example: applying ExtraNetDelay_high to improve post-route timing predictability
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
```

A common interview mistake is saying "I just try different directives until it works." A strong answer explains the reasoning: `ExtraNetDelay_high` is chosen specifically when there is a consistent gap between post-placement and post-route timing estimates, which indicates the placer is underestimating wire delays in that implementation run.

---

### Understanding packing and CLB utilisation

**Q: Your design reports 95% LUT utilisation but only 60% flip-flop utilisation. You are seeing routing congestion. Explain the relationship between LUT utilisation, FF utilisation, and routing congestion, and describe how to reduce congestion without reducing the logic.**

**A:**

Each CLB (configurable logic block) in UltraScale contains 8 LUTs and 16 flip-flops (2 FFs per LUT site). If a design uses many LUTs but few FFs, the FFs within each CLB are mostly empty. The CLB is "LUT-bound" — the packer cannot fit more LUTs in the CLB even though FF slots are available.

**Why this causes routing congestion:**
- At 95% LUT utilisation, nearly every CLB is being used. The placer has very little freedom to spread logic.
- The router must find paths through a nearly-full grid where most nearby CLB inputs are already occupied.
- Even though FF utilisation is low, the routing tracks between CLBs are still contested because the net endpoints (LUT inputs/outputs) are densely packed.

**Remediation strategies:**

1. **Reduce LUT utilisation.** The most effective approach is to use more BRAMs, DSPs, or SRLs (shift register LUTs) for logic that can be mapped there:

```verilog
// Replace a chain of FFs with an SRL16 (uses 1 LUT for up to 16-cycle delay)
(* srl_style = "srl" *) logic [15:0] delay_chain;
always_ff @(posedge clk)
    delay_chain <= {delay_chain[14:0], data_in};
assign data_delayed = delay_chain[15];
```

2. **Enable LUT-FF packing.** Ensure the tool packs FFs into the same CLB as the LUT driving them (the default behaviour). Avoid attributes that prevent packing:

```tcl
# Check if any cells have PACK_TYPES that prevent co-location
get_cells -filter {PACK_TYPES != ""}
```

3. **Restructure logic to use fewer LUT levels.** Deeply nested conditional logic creates wide fanin that maps to more LUT levels than a balanced tree. Restructure or let synthesis perform LUT re-mapping:

```tcl
# Re-run opt_design with aggressive LUT combining
opt_design -directive ExploreWithRemap
```

4. **Target a lower utilisation.** Best practice is to keep LUT utilisation below 80% to leave headroom for the router. A design at 95% LUTs will frequently encounter congestion and unpredictable timing.

---

## Advanced

### Multi-pass implementation

**Q: You are failing timing by WNS = -0.4 ns after a full implementation run. Describe a multi-pass strategy using Vivado that maximises your chance of timing closure without changing the RTL.**

**A:**

A multi-pass strategy runs multiple implementation attempts with different configurations and selects the best result.

**Pass structure:**

```tcl
# run_multipass.tcl — run from Vivado batch mode
set strategies {
    {place_Default_route_Default       Default            Default}
    {place_Extra_route_Aggressive      ExtraNetDelay_high AggressiveExplore}
    {place_AltSpread_route_Default     AltSpreadLogic_high Default}
    {place_Default_route_Explore       Default            Explore}
    {place_ExplorePost_route_Aggressive ExplorePostRoutePhysOpt AggressiveExplore}
}

set best_wns -9999
set best_dcp ""

foreach strat $strategies {
    lassign $strat name place_dir route_dir

    open_checkpoint synth_checkpoint.dcp
    opt_design
    place_design -directive $place_dir
    phys_opt_design -directive AggressiveExplore
    route_design   -directive $route_dir
    phys_opt_design -directive AggressiveExplore  ;# post-route physical opt

    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    puts "Strategy $name: WNS = $wns"

    if {$wns > $best_wns} {
        set best_wns $wns
        set best_dcp "${name}_routed.dcp"
        write_checkpoint -force $best_dcp
    }
    close_design
}

puts "Best WNS: $best_wns from $best_dcp"
open_checkpoint $best_dcp
```

**Additional techniques within a pass:**

- Run `phys_opt_design` twice (once post-placement, once post-routing) — the second run has more accurate timing data
- Use `-timing_summary` flag with `route_design` to see per-iteration improvement
- Enable `hold_fix` in `phys_opt_design` after setup is closed:

```tcl
phys_opt_design -directive AggressiveExplore
# Once setup is clean:
phys_opt_design -hold_fix -directive AggressiveExplore
```

**Interview answer structure:** Start with "I would first analyse the failing paths to understand whether the issue is a single long path or many scattered violations." This shows systematic thinking before immediately jumping to brute-force retries.

---

### SLR crossing (SSI devices)

**Q: You are implementing a design on a VU9P (3-die SSI device). Explain the SLR crossing problem and how you approach placement to manage it.**

**A:**

SSI (stacked silicon interconnect) devices consist of multiple FPGA dice (SLRs — super logic regions) connected through a silicon interposer. In the VU9P:
- SLR0 is the bottom die
- SLR1 is the middle die
- SLR2 is the top die

Signals crossing between SLRs must pass through dedicated **SLL (super long line) resources**. There are approximately 3,840 SLLs per SLR boundary in a VU9P. SLLs add approximately 0.5–1.0 ns of delay beyond the routing delay within a single SLR.

**Problems:**
- Excessive SLL crossings consume the limited SLL budget (few thousand per boundary)
- SLL delays open setup violations on paths that span boundaries
- Congestion at SLR boundaries causes the tool difficulty routing within-SLR signals around the crossing nets

**Management strategy:**

1. **Partition the design by SLR at the architectural level.** Group communicating logic into the same SLR. Use pipelining to cross SLR boundaries explicitly:

```verilog
// Register signals at every SLR boundary (pipeline the crossing)
// SLR0 logic → crossing register → SLR1 logic
always_ff @(posedge clk)
    slr_boundary_reg <= slr0_output;  // placed in SLR0
// slr1_input = slr_boundary_reg (consumed in SLR1)
```

2. **Use Pblocks to constrain SLR assignment:**

```tcl
# Create Pblocks for each SLR
create_pblock pblock_slr0
add_cells_to_pblock [get_pblocks pblock_slr0] [get_cells {slr0_module}]
resize_pblock [get_pblocks pblock_slr0] -add {SLR0}

create_pblock pblock_slr1
add_cells_to_pblock [get_pblocks pblock_slr1] [get_cells {slr1_module}]
resize_pblock [get_pblocks pblock_slr1] -add {SLR1}
```

3. **Monitor SLL utilisation:**

```tcl
report_design_analysis -ssio_crossings
```

4. **Use the `SSI_SpreadSLLs` placement directive** to have Vivado balance SLL use across boundaries automatically when manual partitioning is impractical.

**Interview depth question:** An interviewer may ask "What is the maximum safe throughput across an SLR boundary?" The answer is: up to ~3,840 single-ended signals per boundary, but in practice, plan for ~50–60% utilisation to leave headroom for routing. This means approximately 2,000 effective data bits per boundary per clock cycle.

---

### Critical region analysis and incremental implementation

**Q: You have a design that was timing-clean last week. A colleague made changes to module A, and now there are 23 new failing paths — all in module B, which was not touched. Explain what likely happened and how incremental implementation can help.**

**A:**

**Why module B can fail when module A changes:**

1. **Placement ripple effect.** Module A's changes altered its resource usage. The placer re-placed module A, and its new placement displaced some of module B's cells to less-optimal locations. Module B's paths are now longer even though its logic is unchanged.

2. **Shared routing resources.** Module A now uses different routing resources. Some of the tracks that module B relied on are now occupied by module A's new nets, forcing module B's router to take longer detours.

3. **Changed timing context.** If module A drives module B, and the output register of module A is now placed in a different clock region, module B's input timing has changed.

4. **Global signal changes.** If module A added a new clock enable or reset tree, the global signal routing has changed, affecting setup/hold times seen by module B's registers.

**Incremental implementation (Vivado 2019.1+):**

Incremental implementation preserves the placement and routing of unchanged cells from a reference checkpoint. Only cells that changed (module A) are re-placed and re-routed. Module B's placement and routing are locked:

```tcl
# Read the last known-good routed checkpoint
read_checkpoint -incremental last_good_routed.dcp

# Run implementation — changed cells are re-implemented, unchanged cells are locked
opt_design
place_design
phys_opt_design
route_design

# The tool reports which cells were re-placed vs preserved
report_incremental_reuse -file incremental_reuse.rpt
```

**Benefits:**
- Module B's paths are locked, eliminating placement ripple
- Implementation run time decreases (only module A is processed)
- Provides a controlled diff between runs

**Limitations:**
- If module A's new placement is incompatible with module B's locked placement (e.g., a shared CLB), the tool will unlock some of module B's cells and re-place them
- Incremental implementation cannot help if the root cause is that module A's changes truly require displacing module B

---

## Common Mistakes and Pitfalls

1. **Treating placement directives as random trial and error.** A strong engineer understands what each directive does mechanically and selects based on the observed failure mode. Blindly trying all directives wastes time.

2. **Running `phys_opt_design` only once.** Post-route physical optimisation has better timing data than post-placement. Always run `phys_opt_design` after `route_design`.

3. **Ignoring the congestion report until after routing failure.** Checking `report_design_analysis -congestion` after placement (before routing) identifies problems early when they are cheaper to fix.

4. **Forgetting that unrouted nets are a hard failure.** A design with unrouted nets cannot be programmed into the device regardless of timing. This takes precedence over all timing fixes.

5. **Over-constraining Pblocks.** A Pblock that is too small forces high utilisation within the constrained region, causing local congestion and routing failures. Leave at least 20% headroom inside any Pblock.

6. **Assuming the SLR boundary delay is zero.** When reading timing paths on SSI devices, SLL delay must be accounted for in the timing budget. A 500 MHz path has a 2 ns period; an SLL crossing consuming 1 ns leaves only 1 ns for all other delays.

---

## Quick Reference

| Command | Purpose |
|---|---|
| `opt_design` | Gate-level optimisation before placement |
| `place_design -directive X` | Placement with selected strategy |
| `phys_opt_design -directive X` | Physical optimisation (post-place or post-route) |
| `route_design -directive X` | Routing with selected strategy |
| `report_route_status` | Check for unrouted nets |
| `report_design_analysis -congestion` | Routing congestion hotspots |
| `report_utilization -hierarchical` | Resource usage per hierarchy level |
| `report_timing_summary` | WNS, TNS, WHS, WPWS after route |
| `write_checkpoint -force name.dcp` | Save implementation state for incremental reuse |
| `read_checkpoint -incremental ref.dcp` | Load reference checkpoint for incremental impl |
| `place_design -directive AltSpreadLogic_high` | Spread logic to reduce congestion |
| `place_design -directive ExtraNetDelay_high` | Pessimistic delays for better post-route predictability |
| `phys_opt_design -hold_fix` | Fix hold violations post-route |
