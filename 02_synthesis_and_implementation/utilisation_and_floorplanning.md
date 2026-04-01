# Utilisation and Floorplanning

Floorplanning is the practice of guiding the placement tool by partitioning the design into physical regions. It is both an art and an engineering discipline: too rigid a floorplan constrains the tool unnecessarily; too loose a floorplan allows uncontrolled cross-region routing that defeats timing. This topic appears in senior-level interviews because it requires integrating knowledge of the device architecture, the design structure, and the tool flow.

---

## Table of Contents

- [Fundamentals](#fundamentals)
- [Intermediate](#intermediate)
- [Advanced](#advanced)
- [Common Mistakes and Pitfalls](#common-mistakes-and-pitfalls)
- [Quick Reference](#quick-reference)

---

## Fundamentals

### Utilisation targets

**Q: What is a safe LUT utilisation target for a design targeting 300 MHz on an UltraScale+ device? Why is 100% utilisation problematic even if all logic can technically fit?**

**A:**

A practical guideline for UltraScale+ targeting 300 MHz:
- **LUT utilisation: 70–80% maximum**
- **BRAM utilisation: 85% maximum**
- **DSP utilisation: 85% maximum**
- **Flip-flop utilisation: typically not the limiting resource** (there are 2× as many FFs as LUTs)

**Why high LUT utilisation is problematic:**

**1. Routing congestion.** Each LUT has inputs and outputs that must be routed. At high utilisation, the routing fabric is crowded. The router is forced to use longer, less direct paths, increasing routing delay and potentially making previously-passing paths fail.

**2. Reduced placer freedom.** The placement optimiser works by comparing the cost of placing a cell at different sites. At 95% utilisation, most sites are taken. The placer cannot find a low-cost location for cells that need to be close to each other, resulting in forced suboptimal placements.

**3. Incremental change impact.** If the design is at 98% utilisation and a feature adds 3% more logic, the design no longer fits. High utilisation leaves no margin for design changes, bug fixes, or late requirements.

**4. Tool runtime.** The router at high utilisation takes significantly longer to find valid routes and may iterate many more times, increasing compile time.

**5. Power consumption.** High utilisation concentrates switching activity in smaller areas, increasing local power density and temperature gradients.

**Practical calibration:**
- At 80% LUT utilisation, most designs of moderate complexity close timing without extraordinary effort.
- At 90%, timing closure becomes reliably challenging and requires floorplanning.
- Above 95%, the implementation will almost certainly require significant architectural changes or a larger device.

---

### Reading a utilisation report

**Q: Explain the key fields in a Vivado `report_utilization` output. What does it mean when Slice LUT utilisation is 65% but CLB utilisation is 88%?**

**A:**

A simplified `report_utilization` output looks like:

```
+----------------------------+--------+-------+------------+-----------+-------+
|          Site Type         |  Used  | Fixed | Prohibited | Available | Util% |
+----------------------------+--------+-------+------------+-----------+-------+
| CLB LUTs                   |  87432 |     0 |          0 |    134600 | 64.96 |
|   LUT as Logic             |  82100 |       |            |           | 61.00 |
|   LUT as Memory            |   5332 |       |            |           |  3.96 |
|     LUT as Distributed RAM |   4100 |       |            |           |       |
|     LUT as Shift Register  |   1232 |       |            |           |       |
| CLB Registers              |  96210 |     0 |          0 |    269200 | 35.74 |
| RAMB36/FIFO                |    312 |     0 |          0 |       600 | 52.00 |
| DSP48E2                    |    890 |     0 |          0 |      2520 | 35.32 |
| Slice                      |  23100 |       |            |     26920 | 85.80 |
+----------------------------+--------+-------+------------+-----------+-------+
```

**Key fields explained:**

- **CLB LUTs (64.96%)** — Percentage of total LUT sites used. This is the most commonly cited utilisation figure.
- **LUT as Logic vs LUT as Memory** — LUTs used as logic implement boolean functions. LUTs used as memory implement small SRAMs (distributed RAM) or shift registers (SRL16/SRL32). Distributed RAM is 3–4× less area-efficient than BRAM for large memories.
- **CLB Registers (35.74%)** — Percentage of available flip-flops used. If this is much lower than LUT %, the design is LUT-bound.
- **Slice (85.80%)** — A Slice is a sub-unit of a CLB (UltraScale: 1 CLB = 2 Slices; earlier families: 1 Slice = 2 LUTs + 2 FFs). Slice utilisation can be higher than LUT % when LUTs and FFs cannot be packed together efficiently.

**Why CLB utilisation (as Slice %) can be higher than LUT %:**

A CLB Slice is occupied if ANY of its resources is used. Even if a Slice uses 1 of its 8 LUTs but all 8 LUTs in the other Slice of the same CLB are used, both Slices are "occupied." This is called **packing inefficiency**.

Causes of poor packing:
- Mismatched control sets: two registers with different clock enables cannot share the same Slice
- LUT inputs with too many unique variables to share a LUT
- `DONT_TOUCH` attributes preventing LUT merging

A Slice utilisation of 88% with only 65% LUT utilisation means many Slices are partially occupied. The packer is effectively running out of compatible placement sites before it runs out of raw LUT count.

**Fix:** Reduce control set diversity. Group registers by clock enable domain. Use `opt_design -directive ExploreWithRemap` to improve packing.

---

### Introduction to Pblocks

**Q: What is a Pblock in Vivado? Write the Tcl commands to create a Pblock for a module named `dsp_engine` and constrain it to the upper-left quadrant of a VU9P.**

**A:**

A Pblock (placement block) is a rectangular region of the FPGA that you assign specific design modules to. The placement tool will only place the cells assigned to a Pblock within that Pblock's physical boundaries. This gives the designer explicit control over where modules land on the die.

**Use cases:**
- Keep communicating modules physically close to reduce routing delay
- Separate unrelated modules to reduce routing congestion
- Assign modules to specific SLRs in multi-die devices
- Create a stable physical boundary for incremental implementation

**Pblock creation for `dsp_engine`:**

```tcl
# Step 1: Create the Pblock and give it a name
create_pblock pblock_dsp_engine

# Step 2: Assign cells to the Pblock
# get_cells with -hierarchical finds cells at any depth in the hierarchy
add_cells_to_pblock [get_pblocks pblock_dsp_engine] \
    [get_cells -hierarchical -filter {NAME =~ dsp_engine/*}]

# Step 3: Define the physical area (for VU9P, coordinates depend on the device)
# The upper-left quadrant of SLR1 on a VU9P (approximate):
resize_pblock [get_pblocks pblock_dsp_engine] \
    -add {SLICE_X0Y120:SLICE_X59Y239 DSP48E2_X0Y48:DSP48E2_X7Y95 RAMB36_X0Y24:RAMB36_X3Y47}

# Step 4: Verify the Pblock contents and size
report_pblock_utilization -pblock pblock_dsp_engine
```

**Resource coordinate notation:**
- `SLICE_X0Y120:SLICE_X59Y239` — All CLB Slices in the rectangular region from column 0, row 120 to column 59, row 239
- `DSP48E2_X0Y48:DSP48E2_X7Y95` — DSP blocks in that region (DSP columns have fewer sites than LUT columns)
- `RAMB36_X0Y24:RAMB36_X3Y47` — BRAM sites in that region

**Important:** When defining a Pblock, explicitly include all resource types the module uses (LUTs, DSPs, BRAMs). A Pblock that specifies only SLICE coordinates but not DSP coordinates will cause DSP placement to be unconstrained — the DSPs will land outside the intended region.

---

## Intermediate

### Floorplanning strategies for a multi-module design

**Q: Your design has three independent processing pipelines (pipeline_a, pipeline_b, pipeline_c), a shared memory controller, and a top-level AXI interconnect. Describe your floorplanning strategy and the rationale for each decision.**

**A:**

**Principle: Minimise cross-boundary communication.**

The floorplan should mirror the connectivity graph of the design. Modules that communicate frequently should be adjacent. Modules that communicate rarely can be distant.

**Analysis of the design:**

```
AXI Interconnect
    ├── pipeline_a (independent)
    ├── pipeline_b (independent)
    ├── pipeline_c (independent)
    └── Memory Controller (shared)
                └── (all pipelines read/write)
```

**Floorplan strategy:**

**1. Memory controller: central placement**

The memory controller communicates with all three pipelines. Placing it centrally minimises the average routing distance to each pipeline:

```tcl
create_pblock pblock_mem_ctrl
add_cells_to_pblock [get_pblocks pblock_mem_ctrl] \
    [get_cells -hierarchical -filter {NAME =~ mem_ctrl/*}]
resize_pblock [get_pblocks pblock_mem_ctrl] \
    -add {SLICE_X40Y100:SLICE_X60Y150 RAMB36_X3Y25:RAMB36_X5Y37}
```

**2. AXI interconnect: adjacent to memory controller**

The interconnect routes all transactions and must reach every module. Place it near the memory controller to keep AXI bus routing compact:

```tcl
create_pblock pblock_axi
add_cells_to_pblock [get_pblocks pblock_axi] \
    [get_cells -hierarchical -filter {NAME =~ axi_interconnect/*}]
resize_pblock [get_pblocks pblock_axi] \
    -add {SLICE_X30Y100:SLICE_X40Y150}
```

**3. Pipelines: distributed evenly around the memory controller**

Each pipeline is independent of the others — no direct communication. Spread them out to avoid congestion and use the full device area:

```tcl
# Pipeline A: left of memory controller
create_pblock pblock_pipe_a
add_cells_to_pblock [get_pblocks pblock_pipe_a] \
    [get_cells -hierarchical -filter {NAME =~ pipeline_a/*}]
resize_pblock [get_pblocks pblock_pipe_a] \
    -add {SLICE_X0Y60:SLICE_X30Y180 DSP48E2_X0Y24:DSP48E2_X3Y71}

# Pipeline B: above memory controller
# Pipeline C: below memory controller
# (similar commands, different coordinate ranges)
```

**4. Leave interface registers unconstrained or at module boundaries**

Registers that cross between Pblocks should be placed by the tool near the boundary. Forcing them into either Pblock adds routing pressure.

**5. Verify the floorplan does not create bottlenecks**

```tcl
# Check that each Pblock has sufficient resources
report_pblock_utilization
# Target: < 75% LUT utilisation within each Pblock
```

---

### Partitioning strategies for SSI (multi-die) devices

**Q: You are floorplanning a design for a Virtex UltraScale+ VU9P (3 SLRs). The design has a PCIe subsystem, a signal processing core, and a DDR4 memory interface. Explain your SLR assignment rationale.**

**A:**

The VU9P has:
- SLR0 (bottom): contains the PCIe hard block (PCIE4C) and DDR4 XIPHY interfaces on the left side
- SLR1 (middle): general logic
- SLR2 (top): additional PCIE4C and some XIPHY interfaces

**Assignment rationale:**

**PCIe subsystem → SLR0**

The PCIe hard block is physically located in SLR0. There is no choice — the hard block cannot be moved. All logic associated with PCIe (DMA engine, AXI-to-PCIe bridge, TLP processing) should also go in SLR0 to avoid SLL crossings on the PCIe data path.

**DDR4 memory interface → SLR0 (same as the XIPHY)**

The DDR4 PHY (XIPHY) connects to specific I/O banks in SLR0 on the VU9P. The memory controller (MC) must be adjacent to the PHY. Place the MC and its associated logic in SLR0.

**Signal processing core → SLR1 and SLR2**

The processing core has no hard-block dependencies. Distribute it across SLR1 and SLR2 to use the full available fabric. If the core has a linear pipeline:
- Early pipeline stages → SLR1 (receives data from DDR4 in SLR0 via SLLs)
- Later pipeline stages → SLR2 (sends results back to PCIe in SLR0 via SLLs)

**Pipeline registers at SLR boundaries:**

Every signal crossing an SLR boundary must have a register on each side. The SLL delay (~0.8 ns) must be budgeted as part of the inter-SLR clock period:

```verilog
// SLR0 → SLR1 boundary: register in SLR0 before crossing
(* keep_hierarchy = "yes" *)
module slr_boundary_pipeline (
    input  logic        clk,
    input  logic [63:0] data_in,   // SLR0 source
    output logic [63:0] data_out   // SLR1 destination
);
    // This register must be placed in SLR0 (use a Pblock or LOC attribute)
    logic [63:0] crossing_reg;
    always_ff @(posedge clk)
        crossing_reg <= data_in;
    assign data_out = crossing_reg;
endmodule
```

```tcl
# Lock the crossing register to SLR0
set_property LOC SLICE_X59Y199 [get_cells {slr_boundary_pipeline/crossing_reg_reg[*]}]
```

**Monitor SLL utilisation:**

```tcl
report_design_analysis -ssio_crossings
```

Target: < 60% of available SLLs per boundary. Exceeding 80% causes routing congestion at the boundary.

---

### Resource partitioning for iterative development

**Q: Your team is developing a large FPGA design collaboratively. Four engineers are working on four different modules simultaneously. How do you use Pblocks and out-of-context synthesis to enable parallel development without blocking each other?**

**A:**

**Out-of-context (OOC) synthesis** allows each module to be synthesised independently:

```tcl
# Each engineer synthesises their module independently
# engineer_1 runs:
synth_design -mode out_of_context \
             -top module_a \
             -part xcvu9p-flga2577-2-e
write_checkpoint module_a_synth.dcp

# engineer_2 runs the same for module_b, etc.
```

OOC synthesis treats the module boundaries as black boxes (no I/O timing — those are added by the top level). Each module can be synthesised in parallel, and once complete, the checkpoints are checked into version control.

**Pblock-based top-level integration:**

The top-level integrator defines strict Pblocks for each module in advance. This "locks in" the physical partitioning so that when module implementations are updated, the rest of the design is unaffected:

```tcl
# Top-level integration script
foreach module {module_a module_b module_c module_d} {
    read_checkpoint ${module}_synth.dcp -cell [get_cells ${module}]
}

# Pre-defined Pblocks (established at project start, not changed per-iteration)
create_pblock pblock_module_a
resize_pblock [get_pblocks pblock_module_a] -add {SLICE_X0Y0:SLICE_X30Y120}
add_cells_to_pblock [get_pblocks pblock_module_a] [get_cells module_a]
# ... repeat for b, c, d

# Run implementation
opt_design
place_design
phys_opt_design
route_design
```

**Benefits:**
- Module A's timing closure does not affect module B's placement (Pblock isolation)
- Incremental implementation reuses unchanged modules' placement/routing
- Engineers can iterate their modules independently using `open_checkpoint; read_checkpoint -cell; opt_design; ...`

**Constraint for the Pblock interfaces:**

Use `set_bus_skew` or register interface signals to define timing between Pblocks. Interface registers placed at Pblock boundaries give the router a predictable landing point:

```tcl
# Interface registers at Pblock boundaries should have specific LOC constraints
# Place them at the edge of the Pblock closest to the other module
set_property LOC SLICE_X30Y60 [get_cells {module_a/output_pipeline_reg[*]}]
```

---

## Advanced

### Dynamic function exchange (partial reconfiguration) and floorplanning

**Q: You are designing an FPGA system that must reconfigure part of its logic at runtime using Xilinx Dynamic Function eXchange (DFX). What floorplanning requirements does DFX impose, and how do they differ from standard floorplanning?**

**A:**

Dynamic Function eXchange (formerly partial reconfiguration) allows a designated region of the FPGA to be reconfigured while the rest continues to operate. The physical region that can be reconfigured is called a **Reconfigurable Partition (RP)**.

**Floorplanning requirements for DFX:**

**1. Reconfigurable regions must be rectangular and resource-complete**

The RP must contain enough of every resource type the reconfigurable module needs. Additionally, DFX requires the partition to be aligned to **reconfiguration frames** — the minimum unit of configuration data. In UltraScale+, frames span the full height of a clock region (60 CLB rows).

```tcl
# RP Pblock must span full clock region height for DFX
create_pblock pblock_rp_0
resize_pblock [get_pblocks pblock_rp_0] \
    -add {SLICE_X10Y0:SLICE_X39Y59}   ;# full 60-row clock region height
set_property IS_RECONFIG_PARTITION true [get_pblocks pblock_rp_0]
```

**2. Interface registers at the RP boundary**

Every signal crossing between the static region and the RP must pass through an interface register. These are called **Partition Pins** in Vivado. They are placed at the boundary of the RP and remain stable during reconfiguration:

```tcl
# The tool inserts FDRE partition pins automatically when synthesising with DFX flow
# But you can guide their placement:
set_property HD.PARTPIN_LOCS SLICE_X10Y30 [get_nets {rp_module/data_in[0]}]
```

**3. No resource sharing between RP and static region**

CLBs, BRAMs, and DSPs at the boundary of an RP must be fully within the RP or fully outside it. The static region cannot use partial CLBs adjacent to the RP boundary.

**4. RP must be isolated during reconfiguration**

The fabric between the RP and static region must isolate the RP's outputs to a defined value (usually 0) during the reconfiguration process. Vivado handles this via the `HD.RECONFIGURABLE` property and isolation buffers.

**Difference from standard floorplanning:**

| Aspect | Standard Pblock | DFX Reconfigurable Partition |
|---|---|---|
| Boundary alignment | Any rectangle | Must align to clock region rows |
| Resource sharing at boundary | Allowed | Forbidden |
| Interface registers | Optional | Mandatory |
| Multiple configurations | One | Multiple reconfigurable modules (RMs) per RP |
| Bitstream | Full bitstream | Static bitstream + RM partial bitstreams |

**Interview depth question:** "What is a blanking bitstream?" — A blanking bitstream configures an RP with a safe default (all outputs driven to known values). It is used between loading two different RMs to prevent undefined behavior during the transition.

---

## Common Mistakes and Pitfalls

1. **Making Pblocks too small.** A Pblock at 95% internal utilisation has the same routing problems as a 95% utilised full device. Leave 20–25% resource headroom inside every Pblock.

2. **Not including all resource types in the Pblock definition.** Specifying only SLICE coordinates and omitting DSP48E2 or RAMB36 ranges causes those resources to be placed outside the Pblock even if they belong to the Pblocked module.

3. **Using LOC constraints prematurely.** LOC constraints lock specific cells to specific sites, preventing the placer from making any placement decisions for those cells. This should be reserved for primitives where physical location is architecturally required (e.g., MMCM, BUFG, IOB). Overusing LOC constraints severely restricts the placer.

4. **Floorplanning before synthesis is stable.** If the RTL is still changing significantly, the resource counts will change and invalidate the Pblock sizing. Establish Pblocks after the design is functionally complete and synthesises cleanly.

5. **Ignoring the Pblock report.** Always run `report_pblock_utilization` after adding cells to a Pblock. An over-filled Pblock shows high utilisation numbers before implementation starts.

6. **Creating Pblocks that cut high-fanout nets.** If a clock enable or data bus with fanout > 500 crosses a Pblock boundary, the routing tree becomes long and asymmetric. High-fanout nets should stay within a single region where possible, or be routed through BUFG/BUFGCE infrastructure.

---

## Quick Reference

| Command | Purpose |
|---|---|
| `create_pblock name` | Create a new Pblock |
| `add_cells_to_pblock [get_pblocks pb] [get_cells ...]` | Assign cells to a Pblock |
| `resize_pblock [get_pblocks pb] -add {SLICE_X0Y0:...}` | Define the physical area |
| `report_pblock_utilization` | Check resource usage within Pblocks |
| `report_utilization -hierarchical` | Per-module resource usage |
| `report_utilization -pblock [get_pblocks pb]` | Utilisation within a specific Pblock |
| `set_property IS_RECONFIG_PARTITION true [get_pblocks pb]` | Mark Pblock for DFX |
| `report_design_analysis -congestion` | Routing congestion heatmap |
| `report_design_analysis -ssio_crossings` | SLL usage on SSI devices |

| Utilisation guideline | Target |
|---|---|
| LUT utilisation (general) | < 80% |
| LUT utilisation (timing-critical, > 300 MHz) | < 70% |
| Slice utilisation (packing efficiency) | Should be within 5–10% of LUT% |
| BRAM/DSP utilisation | < 85% |
| LUT utilisation within a Pblock | < 75% |
| SLL utilisation per boundary (SSI devices) | < 60% |
