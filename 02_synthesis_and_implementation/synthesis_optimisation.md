# Synthesis Optimisation

Synthesis transforms RTL into a technology-mapped netlist. Understanding what the synthesiser does — and how to guide it — is essential for meeting timing, area, and power targets. This topic appears heavily in FPGA interviews because it sits at the intersection of RTL coding skill and tool knowledge.

---

## Table of Contents

- [Fundamentals](#fundamentals)
- [Intermediate](#intermediate)
- [Advanced](#advanced)
- [Common Mistakes and Pitfalls](#common-mistakes-and-pitfalls)
- [Quick Reference](#quick-reference)

---

## Fundamentals

### What is synthesis?

**Q: Describe the stages of synthesis from RTL to a placed-and-routed netlist. Where does synthesis end and implementation begin?**

**A:**

Synthesis is a multi-stage process performed by a tool such as Vivado Synthesis, Synplify Pro, or Quartus Analysis & Synthesis:

1. **Elaboration** — The RTL is parsed and expanded into a generic logic representation. Parameter values are resolved, generate blocks are unrolled, and the design hierarchy is established.

2. **Technology mapping** — Generic logic (AND/OR/MUX/FF) is mapped to the target device primitives: LUTs, flip-flops, carry chains, DSP blocks, and BRAMs. The mapper selects which primitives to use based on optimisation goals.

3. **Optimisation** — The mapper performs logic simplification, constant propagation, dead-code elimination, and resource sharing. The result is a pre-placed netlist in the device's native primitives.

Synthesis ends when a gate-level netlist is produced. **Implementation** then takes over: placement assigns each primitive to a physical site on the die; routing connects placed primitives through the programmable interconnect fabric. In Vivado, `synth_design` is synthesis and `impl_design` (comprising `opt_design`, `place_design`, `phys_opt_design`, `route_design`) is implementation.

The boundary matters because timing estimates after synthesis use wire-load models that are often inaccurate. Timing reported after route is authoritative.

---

### Inference vs instantiation

**Q: What is the difference between inferring a BRAM and instantiating one? When would you choose each approach, and what are the risks of inference?**

**A:**

**Inference** means writing RTL in a style that the synthesiser recognises as matching a primitive. For a BRAM, the classic inference pattern is a synchronous read with an `always_ff` block and a single read port:

```verilog
// Inferred single-port BRAM (Xilinx UltraScale style)
module simple_bram #(
    parameter DEPTH = 1024,
    parameter WIDTH = 32
)(
    input  logic                      clk,
    input  logic                      we,
    input  logic [$clog2(DEPTH)-1:0]  addr,
    input  logic [WIDTH-1:0]          din,
    output logic [WIDTH-1:0]          dout
);
    // Declare memory — synthesiser infers RAMB36 or RAMB18
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout <= mem[addr];   // read-first mode (synchronous read)
    end
endmodule
```

**Instantiation** means directly placing a technology primitive in RTL:

```verilog
// Direct RAMB36E2 instantiation (Xilinx UltraScale+)
RAMB36E2 #(
    .READ_WIDTH_A(36),
    .WRITE_WIDTH_A(36),
    .DOA_REG(1),           // output register enabled
    .INIT_FILE("NONE"),
    .RAM_MODE("TDP")       // true dual-port
) bram_inst (
    .CLKARDCLK(clk),
    .ENARDEN(1'b1),
    .ADDRA({addr, 5'b0}),
    .DINA(din),
    .DOADO(dout),
    .WEA(we),
    // ... remaining ports tied off
);
```

**Choosing between them:**

| Criterion | Inference | Instantiation |
|---|---|---|
| Portability | High — same RTL targets Xilinx and Intel | Low — primitive names differ per family |
| Control | Limited — tool decides mode and pipelining | Full — every parameter is explicit |
| Maintenance | Easier | Harder, must update on device migration |
| Use case | Standard memories, general logic | When exact primitive behaviour is required (e.g., ECC mode, specific init values, cascade) |

**Risks of inference:**

- The synthesiser may infer the wrong mode (read-first vs write-first vs no-change). Verify with `report_ram_utilization` (Vivado) or check the synthesis log.
- A mismatch between RTL intent and inferred behaviour can cause functional bugs that only appear in hardware.
- If the array is too small, the tool may map to distributed RAM (LUT-based) instead of BRAM, consuming unexpected LUT resources.
- Adding an asynchronous read path anywhere in the design forces distributed RAM for the entire array.

---

### Synthesis directives: keep and dont_touch

**Q: What is the difference between `(* keep = "true" *)` and `(* dont_touch = "true" *)` in Vivado? Give a scenario where each is necessary.**

**A:**

Both directives prevent the synthesiser from optimising away logic, but they differ in scope:

**`keep`** is a synthesis-only directive. It prevents a net or register from being absorbed during synthesis optimisation (e.g., prevents constant folding, merging, or removal of a register that drives only other logic the tool wants to optimise). The placement and routing engine can still optimise or replicate the logic after synthesis.

```verilog
// Prevent synthesis from merging this register into a downstream LUT
(* keep = "true" *) logic sync_ff1;
(* keep = "true" *) logic sync_ff2;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        sync_ff1 <= 1'b0;
        sync_ff2 <= 1'b0;
    end else begin
        sync_ff1 <= async_input;
        sync_ff2 <= sync_ff1;
    end
end
```

**`dont_touch`** is stronger and persists through both synthesis and implementation. The implementation engine cannot replicate, remap, or otherwise modify the annotated cell or net. Use it when you need to preserve a specific physical structure — for example, a CDC synchroniser chain where replication would break the MTBF guarantee, or a hand-placed carry chain.

```verilog
// CDC synchroniser — MUST NOT be replicated or reordered by the tool
(* DONT_TOUCH = "TRUE" *) FDRE sync_reg1 (
    .C(dest_clk), .D(src_data), .Q(sync_stage1),
    .CE(1'b1), .R(1'b0)
);
(* DONT_TOUCH = "TRUE" *) FDRE sync_reg2 (
    .C(dest_clk), .D(sync_stage1), .Q(sync_out),
    .CE(1'b1), .R(1'b0)
);
```

**Practical scenario for `keep`:** You have a registered intermediate signal that feeds a combinational loop. Synthesis wants to merge both registers into one LUT. `keep` on the intermediate register forces the register boundary to be preserved while still allowing downstream logic optimisation.

**Practical scenario for `dont_touch`:** A two-flop CDC synchroniser. If the implementation engine replicates the first flop to meet fanout requirements, two different copies of the synchroniser capture the asynchronous signal independently, doubling the metastability probability and breaking the chain's safety guarantee.

---

### Optimisation goals: area, speed, power

**Q: You need to meet a tight timing target and also minimise power. How do the area, speed, and power optimisation goals interact, and what trade-offs do you make?**

**A:**

The three goals are in tension:

| Goal | What the tool does | Effect on others |
|---|---|---|
| **Speed (timing)** | Duplicates logic to reduce fanout, uses faster carry-chain paths, adds pipeline registers, avoids resource sharing | Increases area; may increase dynamic power |
| **Area** | Shares resources across time-multiplexed operations, removes redundant logic, merges LUTs | Increases logic depth (hurts timing); may reduce power by reducing switching |
| **Power** | Gates clock enables, inserts pipeline stages to reduce toggle rate, uses lower-drive-strength buffers | Pipeline stages increase latency; lower drive reduces noise margin |

**Practical approach when timing is the primary constraint:**

1. First close timing using speed-oriented strategies (fanout control, retiming, physical optimisation).
2. Once timing is closed, apply power reduction passes: clock gating insertion, operand isolation on large arithmetic units, and reducing unnecessary toggling in idle paths.
3. Avoid using the "area" optimisation mode during the timing closure phase; resource sharing adds logic depth and frequently opens new timing paths.

In Vivado, synthesis strategies are selected via `synth_design -directive`:
- `Default` — balanced
- `AreaOptimized_high` — aggressive resource sharing
- `PerformanceOptimized` — speed-focused, may increase area

```tcl
# Vivado: run synthesis with performance focus
synth_design -top my_top -part xcvu9p-flga2577-2-e \
             -directive PerformanceOptimized \
             -fsm_extraction one_hot \
             -resource_sharing off
```

A common interview pitfall: candidates conflate synthesis power optimisation with physical implementation power optimisation. Most meaningful power reduction on FPGAs (clock gating, power domains) happens at the RTL level and through Vivado's `power_opt_design` step, not purely in synthesis.

---

## Intermediate

### max_fanout attribute

**Q: A net in your design has a fanout of 4000 and is causing significant hold violations during routing. You have tried `set_max_fanout` in your XDC but the violations remain. Explain what `set_max_fanout` does, why it might not have resolved the problem, and what else you can try.**

**A:**

`set_max_fanout` is a synthesis hint that tells the synthesiser to duplicate logic driving a high-fanout net so that each copy drives fewer loads. For example:

```tcl
# XDC / synthesis constraint: replicate logic if any net exceeds 50 loads
set_max_fanout 50 [get_nets {my_high_fanout_net}]
```

Or applied globally:

```tcl
set_max_fanout 20 [current_design]
```

**Why it may not resolve the problem:**

1. `set_max_fanout` is a synthesis constraint. If the problem is that the routed wire is physically long (causing both setup and hold problems in a post-route STA), synthesis-time duplication may not be sufficient — the duplicated drivers may still be placed far from their loads.

2. If the high-fanout net is a global signal (clock enable, reset, chip-select), the synthesiser may refuse to replicate it even with the attribute set, because it treats global signals specially.

3. Vivado's `phys_opt_design` with `-directive AggressiveExplore` can perform post-placement replication with physical awareness, which is more effective than synthesis-time replication.

4. If the net is a clock, `set_max_fanout` does not apply — clocks are managed through the clock network (BUFG/BUFR), not by logic replication.

**Additional strategies:**

```tcl
# In implementation: physical optimisation with fanout fix
phys_opt_design -directive AggressiveExplore

# Force register replication for a specific register
set_property MAX_FANOUT 32 [get_cells {my_module/my_register_reg}]

# In RTL: manual replication (most reliable for critical cases)
(* keep = "true" *) logic ctrl_copy1, ctrl_copy2;
assign ctrl_copy1 = original_ctrl;
assign ctrl_copy2 = original_ctrl;
// Use ctrl_copy1 for one half of the loads, ctrl_copy2 for the other
```

Hold violations from high fanout specifically suggest that some loads are reached much faster than others, because the routing tree is asymmetric. Reducing fanout shortens the longest wire in the tree, which typically reduces the hold problem.

---

### Retiming and register balancing

**Q: Explain retiming. Draw a before/after example of a pipeline that benefits from retiming. What are the RTL coding implications, and when should you NOT rely on retiming?**

**A:**

Retiming is the process of moving registers across combinational logic to balance the pipeline stages and reduce the critical path length. The synthesiser (or implementation engine) performs this automatically when enabled.

**Before retiming:**
```
Stage A (12 ns logic) -> FF -> Stage B (3 ns logic) -> FF -> output
Critical path: 12 ns → fmax = 83 MHz
```

**After retiming:**
```
Stage A (7.5 ns logic) -> FF -> (4.5 ns logic + Stage B 3 ns) -> FF -> output
Critical path: 7.5 ns → fmax = 133 MHz
```

The register is "moved" earlier into Stage A, splitting the 12 ns logic into two ~6-7 ns halves. The overall latency is the same (two register cycles), but the critical path is shorter.

**RTL and tool usage:**

In Vivado synthesis:
```tcl
# Enable retiming globally during synthesis
synth_design -retiming

# Or per-module via attribute
set_property RETIMING true [get_cells {my_pipeline_module}]
```

In RTL, the attribute can be applied directly:
```verilog
(* retiming_forward = 1 *) module my_pipeline (
    // Vivado retiming hint: push registers forward through logic
    ...
);
```

**When NOT to rely on retiming:**

1. **Functional side effects** — Retiming changes where in the pipeline a register sits. If a register has a meaningful functional role (e.g., it captures a cycle-accurate handshake signal, or its output feeds a `ready` signal), retiming may break the cycle-accurate behaviour even though the logic function is preserved.

2. **Reset domains** — Retiming across a reset boundary can place a register that must be in one reset domain into another. Always verify the reset structure after retiming.

3. **ILA probe points** — If an ILA is probing a signal at a specific pipeline stage, retiming may move the probed register, making the captured data correspond to a different cycle than intended.

4. **Cross-hierarchy retiming** — Retiming typically does not cross hierarchy boundaries. An RTL design with deep module hierarchy will not benefit as much as a flat design. Flatten the hierarchy with `set_property FLATTEN_HIERARCHY full [current_design]` to allow the tool more freedom.

5. **Latency-sensitive interfaces** — If the block has a fixed-latency contract with another block (e.g., a fixed read latency on a cache), retiming must not change the register depth on the critical path through that interface.

---

### FSM encoding

**Q: Vivado infers a large FSM in your design. You notice it is using binary encoding, but you suspect one-hot would be faster. Explain the trade-offs and how you control FSM encoding.**

**A:**

FSM encoding affects both the combinational logic generating next-state and the number of registers required:

| Encoding | State registers | Next-state logic | Best for |
|---|---|---|---|
| Binary | log2(N) | Complex, multi-level | Many states, area-constrained |
| One-hot | N | Simple, one LUT per state | Fewer states, timing-critical |
| Gray | log2(N) | Moderate | Noise-sensitive, asynchronous observation |

**One-hot advantage on FPGAs:** Each state has its own flip-flop. The next-state logic for each state reduces to a small OR of the predecessor states, often fitting in one LUT. Binary encoding requires a priority encoder that touches all state bits, creating longer combinational paths.

**When binary is better:** Above approximately 10-12 states, one-hot consumes more registers than the FPGA has available efficiently. Binary or Johnson encoding fits more states in fewer registers.

**Control in Vivado:**

```tcl
# Synthesis setting: force one-hot for all FSMs
synth_design -fsm_extraction one_hot

# Attribute in RTL (overrides global setting per module)
(* fsm_encoding = "one_hot" *) logic [7:0] state;

# Other valid values: "binary", "gray", "johnson", "sequential", "auto" (default)
```

```verilog
// Explicit one-hot state declaration — tool will respect the encoding
typedef enum logic [3:0] {
    IDLE  = 4'b0001,
    FETCH = 4'b0010,
    EXEC  = 4'b0100,
    WRITE = 4'b1000
} state_t;

(* fsm_encoding = "none" *) state_t state, next_state;
// "none" tells the tool not to re-encode — use the user-defined values
```

**Interview tip:** If you say "I always use one-hot", that is a red flag. Demonstrate knowledge of when each encoding is appropriate. A well-prepared candidate mentions the `auto` mode, where Vivado chooses based on the number of states, which is appropriate for most production designs.

---

### DSP and BRAM inference rules

**Q: You write a 32-bit multiplier in RTL. Under what conditions will Vivado infer a DSP block, and under what conditions will it use LUTs? How do you force DSP inference?**

**A:**

Vivado infers DSP48E2 (UltraScale+) for multiplication when:
- The operands are both multi-bit (typically >= 4 bits each)
- The result is used combinationally or in a registered fashion consistent with the DSP pipeline

The DSP block maps to the A*B path in the DSP48E2 pre-adder/multiplier/accumulator cascade.

**Conditions that prevent DSP inference:**

1. **Constant multiplication** — If one operand is a power of 2 (or close to one), the tool uses shifts and adds in LUTs, which may be more efficient.
2. **Very small operands** — A 4×4 multiplier may fit in a single LUT6, making DSP wasteful.
3. **Intermediate pipeline stages broken** — If the RTL inserts extra pipeline registers in a way the DSP cascade cannot match, the tool falls back to LUTs.
4. **Resource exhaustion** — If DSPs are already fully utilised, the tool falls back to LUTs.

**Forcing DSP inference in Vivado:**

```verilog
// Method 1: Use_dsp attribute on the module or register
(* use_dsp = "yes" *) module multiplier (
    input  logic signed [17:0] a,
    input  logic signed [17:0] b,
    output logic signed [35:0] product
);
    always_ff @(posedge clk)
        product <= a * b;
endmodule
```

```tcl
# Method 2: Synthesis directive
set_property USE_DSP yes [get_cells {my_mult_instance}]
```

**Verifying inference:**

After synthesis, check the utilisation:
```tcl
report_utilization -hierarchical
```
Or check the synthesis log for "DSP48E2" inferences. In Vivado's schematic view, DSP blocks appear as yellow rectangles. A partially-used DSP (only the multiplier, not the accumulator) may indicate a missed optimisation opportunity — restructuring the RTL to include `product <= product + a*b` allows the full multiply-accumulate (MACC) mode.

---

## Advanced

### Synthesis attributes interaction with timing

**Q: You have a module where `DONT_TOUCH` has been applied to preserve a specific logic structure for a previous timing closure. A new requirement means you must add another register stage to this path. Explain the hazards and how you safely modify this structure.**

**A:**

The hazard is that `DONT_TOUCH` is inherited by all cells and nets inside the annotated scope. Adding a register inside that scope may cause the tool to refuse any further optimisation on the surrounding logic, potentially opening new timing violations elsewhere.

**Step-by-step safe procedure:**

1. **Understand what `DONT_TOUCH` is protecting.** Is it a CDC synchroniser? A specific carry-chain? Check the original intent by looking at review notes or constraints comments.

2. **Scope the attribute precisely.** If `DONT_TOUCH` was applied to a module boundary, consider moving it to only the specific cells that require it:

```tcl
# Remove module-level DONT_TOUCH
set_property DONT_TOUCH false [get_cells {critical_module}]

# Re-apply only to the specific cells that need it
set_property DONT_TOUCH true [get_cells {critical_module/sync_ff1_reg}]
set_property DONT_TOUCH true [get_cells {critical_module/sync_ff2_reg}]
```

3. **Add the new register stage in RTL** in a separate always_ff block, outside the protected scope. Feed the protected output into the new register:

```verilog
// Protected CDC synchroniser (preserve as-is)
(* DONT_TOUCH = "TRUE" *) logic sync1, sync2;
always_ff @(posedge clk) sync1 <= async_in;
always_ff @(posedge clk) sync2 <= sync1;

// New pipeline stage OUTSIDE the protected scope
logic pipeline_stage;
always_ff @(posedge clk) pipeline_stage <= sync2;
```

4. **Re-run implementation and verify** that `report_timing_summary` shows no degradation on the protected path, and the new stage meets timing.

5. **Document the constraint change** with a comment in the XDC file explaining what each `DONT_TOUCH` is protecting and why.

---

### Resource sharing and time-multiplexing

**Q: Your design uses 12 identical 32×32-bit multipliers operating at different phases of a state machine. The device has only 8 DSP blocks available for your block. Describe a resource sharing strategy and the RTL changes required.**

**A:**

Resource sharing replaces N identical functional units with a smaller number of shared units, using a multiplexer to select inputs and a state machine (or counter) to schedule operations.

**Analysis:** 12 multipliers at 1 op/cycle → 12 DSPs. With 8 available, we need to time-multiplex. We can use 4 shared multipliers, each handling 3 of the 12 original multiply operations in 3 sequential cycles. This adds latency (3× throughput reduction) but reduces DSP usage.

```verilog
module shared_multiplier_bank #(
    parameter N_OPS   = 12,   // total multiply operations
    parameter N_UNITS = 4,    // physical DSP units
    parameter CYCLES  = 3     // cycles per output (N_OPS / N_UNITS)
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start,          // pulse to begin computation
    input  logic [31:0] a [0:N_OPS-1], // all 12 A operands
    input  logic [31:0] b [0:N_OPS-1], // all 12 B operands
    output logic [63:0] result [0:N_OPS-1],
    output logic        valid
);
    // Phase counter: 0, 1, 2 → selects which group of 4 ops to compute
    logic [1:0] phase;
    logic       running;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            phase   <= 2'd0;
            running <= 1'b0;
            valid   <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (start) begin
                running <= 1'b1;
                phase   <= 2'd0;
            end else if (running) begin
                phase <= phase + 1;
                if (phase == CYCLES - 1) begin
                    running <= 1'b0;
                    valid   <= 1'b1;
                end
            end
        end
    end

    // 4 shared DSP-inferred multipliers
    genvar u;
    generate
        for (u = 0; u < N_UNITS; u++) begin : gen_units
            logic [31:0] mux_a, mux_b;
            logic [63:0] product;

            // Select the appropriate operand pair based on phase
            // Unit u computes operation (phase * N_UNITS + u)
            always_comb begin
                logic [$clog2(N_OPS)-1:0] op_idx;
                op_idx = phase * N_UNITS + u;
                mux_a = (op_idx < N_OPS) ? a[op_idx] : '0;
                mux_b = (op_idx < N_OPS) ? b[op_idx] : '0;
            end

            // DSP-mapped multiply (registered output)
            (* use_dsp = "yes" *) always_ff @(posedge clk)
                product <= mux_a * mux_b;

            // Capture result into the correct output slot
            always_ff @(posedge clk) begin
                if (running)
                    result[phase * N_UNITS + u] <= product;
            end
        end
    endgenerate
endmodule
```

**Key considerations:**

- The MUX logic must be fast enough that it does not itself become the critical path.
- Input operands must be stable for the entire 3-cycle computation window (or captured into registers at `start`).
- The tool's automatic resource sharing (enabled by `set_property RESOURCE_SHARING on [current_design]`) can sometimes achieve this automatically, but for complex cases manual RTL control is more reliable.
- Report DSP utilisation after synthesis: `report_utilization` should show 4 DSP48E2 blocks, not 12.

---

### Synthesis flow optimisation for iteration time

**Q: Your design takes 40 minutes to synthesise. During development, timing closure iterations are slow. What strategies reduce synthesis iteration time without sacrificing result quality?**

**A:**

**1. Incremental synthesis (Vivado 2018.1+):**

```tcl
# On first run, save the incremental checkpoint
synth_design -incremental_mode default
write_checkpoint -force synth_checkpoint.dcp

# On subsequent runs, only re-synthesise changed modules
synth_design -incremental_mode default \
             -incremental_synthesis synth_checkpoint.dcp
```

Only modules whose RTL has changed are re-synthesised. Unchanged modules are read from the checkpoint. Speedup is proportional to the fraction of the design that changed.

**2. Out-of-context (OOC) synthesis for stable IP blocks:**

```tcl
# Synthesise a stable sub-block independently, once
synth_design -mode out_of_context -top my_stable_core \
             -part xcvu9p-flga2577-2-e
write_checkpoint my_stable_core_synth.dcp
```

The OOC block is treated as a black box by the top-level synthesis. It is only re-synthesised when its own RTL changes.

**3. Flatten hierarchy selectively:**

Fully flattening the hierarchy allows the best cross-boundary optimisation but takes longer. Keeping hierarchy (`-keep_hierarchy yes` on stable modules) speeds up synthesis and enables incremental flow.

**4. Run synthesis on a subset of the design during initial development:**

Use `set_property USED_IN_SYNTHESIS false [get_files ...]` to exclude unchanged IP from synthesis runs when you are iterating on a specific submodule.

**5. Parallelise synthesis jobs:**

If running from the command line, run multiple configuration sweeps in parallel on a server cluster, using Vivado's batch mode:

```bash
vivado -mode batch -source run_synth.tcl -tclargs directive1 &
vivado -mode batch -source run_synth.tcl -tclargs directive2 &
```

**Trade-off to acknowledge in an interview:** Incremental synthesis can sometimes produce a worse result than a clean run because the checkpoint may carry over sub-optimal logic structures. Always run a clean synthesis for the final tape-out build.

---

## Common Mistakes and Pitfalls

1. **Assuming synthesis timing estimates are accurate.** Synthesis uses wire-load models. Actual timing is only reliable after routing. Do not declare timing closure based on synthesis reports.

2. **Applying `DONT_TOUCH` too broadly.** Annotating an entire module prevents even basic optimisations (constant propagation, dead-code removal). Scope attributes to the smallest necessary set of cells.

3. **Forgetting that `set_max_fanout` is a hint, not a guarantee.** The tool can ignore it if the net is a special signal (reset, clock enable) or if the directive conflicts with other constraints.

4. **Inferring latches unintentionally.** In combinational `always` blocks, an incomplete case or missing `else` branch infers a latch. Latches have no setup/hold timing arc by default in most SDC flows, masking timing problems.

5. **Confusing synthesis resource sharing with manual sharing.** The tool's automatic resource sharing works within a single combinational expression. It cannot share logic across clock edges or between otherwise independent logic cones without RTL restructuring.

6. **Over-relying on retiming for performance.** Retiming moves registers; it cannot create new registers. If a path has no registers to redistribute, retiming has nothing to work with. Fundamental bottlenecks require RTL pipelining, not retiming.

---

## Quick Reference

| Attribute / Command | Scope | Effect |
|---|---|---|
| `(* keep = "true" *)` | Net / register | Prevents removal during synthesis |
| `(* DONT_TOUCH = "TRUE" *)` | Cell / net | Prevents modification in synthesis AND implementation |
| `(* use_dsp = "yes" *)` | Module / expression | Forces DSP primitive inference |
| `(* use_dsp = "no" *)` | Module / expression | Forces LUT implementation |
| `(* fsm_encoding = "one_hot" *)` | State register | Overrides FSM encoding selection |
| `set_max_fanout N [get_nets ...]` | XDC / Tcl | Hint to replicate high-fanout drivers |
| `synth_design -retiming` | Tcl | Enables cross-register retiming |
| `synth_design -directive PerformanceOptimized` | Tcl | Speed-focused synthesis strategy |
| `synth_design -directive AreaOptimized_high` | Tcl | Area-focused synthesis strategy |
| `report_utilization -hierarchical` | Tcl | Per-hierarchy resource usage |
| `report_timing_summary` | Tcl | Post-synthesis timing estimate |
