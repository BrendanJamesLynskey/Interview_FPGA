# Problem 03: Utilisation Optimisation

**Difficulty:** Intermediate to Advanced  
**Skills tested:** Resource usage analysis, RTL optimisation techniques, tool-driven optimisation, architectural alternatives  
**Typical interview context:** "This design uses too many resources. How do you reduce it?" — presented with a utilisation report or RTL snippet

---

## Scenario

You have completed synthesis on a real-time audio processing FPGA design. The target device is a Xilinx Artix-7 XC7A200T, which has 134,600 LUTs. The design must fit with at least 15% headroom for future features.

**Target:** ≤ 114,410 LUTs (85% of 134,600)

`report_utilization` after synthesis shows:

```
+----------------------------+--------+-------+------------+-----------+-------+
|          Site Type         |  Used  | Fixed | Prohibited | Available | Util% |
+----------------------------+--------+-------+------------+-----------+-------+
| Slice LUTs                 | 128,440|     0 |          0 |    134,600| 95.42 |
|   LUT as Logic             | 121,200|       |            |           | 90.04 |
|   LUT as Memory (LUTRAM)   |   7,240|       |            |           |  5.38 |
|     LUT as Distributed RAM |   6,800|       |            |           |       |
|     LUT as Shift Register  |     440|       |            |           |       |
| Slice Registers            |  62,300|     0 |          0 |    269,200| 23.14 |
| F7 Muxes                   |   4,200|       |            |           |  6.24 |
| F8 Muxes                   |   1,800|       |            |           |  5.35 |
| Block RAM Tile             |      42|     0 |          0 |        365| 11.51 |
|   RAMB36/FIFO              |      38|       |            |           |       |
|   RAMB18                   |       4|       |            |           |       |
| DSP48E1                    |     128|     0 |          0 |        740| 17.30 |
+----------------------------+--------+-------+------------+-----------+-------+
```

**Hierarchical breakdown (`report_utilization -hierarchical` excerpt):**

```
Module                    | LUTs  | % of total
--------------------------|-------|------------
top_level                 |  2,400|  1.87
audio_input_stage         |  8,200|  6.38
sample_rate_converter     | 31,600| 24.57  ← LARGEST
equaliser_bank            | 44,800| 34.83  ← LARGEST
reverb_engine             | 22,100| 17.19
output_mixer              |  6,400|  4.98
compressor_limiter        | 13,040| 10.14
```

You need to reduce total LUT usage from 128,440 to below 114,410 — a reduction of at least 14,030 LUTs (approximately 11% of total).

---

## Part 1: Initial Analysis

**Q: Before making any changes, what questions do you ask and what reports do you generate to understand the utilisation problem?**

**A:**

**Question 1: Is the LUTRAM usage legitimate?**

6,800 LUTs used as Distributed RAM is significant. Each LUT acting as a 64-deep × 1-bit RAM is wasteful if the same data could fit in a BRAM. Calculate the equivalent BRAM storage:

```
6,800 LUTRAM × 64 bits × 1 bit/LUT = 435,200 bits
BRAM36 capacity: 36 Kb = 36,864 bits
Equivalent BRAMs: 435,200 / 36,864 ≈ 11.8 RAMB36
```

The design is using ~12 equivalent BRAMs worth of data in distributed RAM. The device has 365 BRAMs, of which only 42 are used (11.5%). There is clearly headroom to migrate distributed RAM to BRAM.

**Question 2: Where exactly are the large modules spending their LUTs?**

```tcl
# Drill into the two largest modules
report_utilization -hierarchical -cells {equaliser_bank sample_rate_converter} \
                   -file detailed_util.rpt
```

This breaks down each module into sub-modules, identifying which sub-module is the hotspot.

**Question 3: Is the LUTRAM in the large modules?**

```tcl
# Report LUTRAM specifically
report_utilization -hierarchical -ram_type distributed -file lutram_report.rpt
```

**Question 4: Are the DSPs fully utilised?**

128/740 DSPs = 17.3%. There is substantial headroom to absorb arithmetic operations currently implemented in LUTs into DSP blocks.

```tcl
# Check if any multipliers are using LUTs instead of DSPs
report_design_analysis -logic_level_distribution
# Look for logic at levels 4-8+ — these may be LUT-based multipliers
```

**Question 5: What is the logic level distribution?**

```tcl
report_design_analysis -logic_level_distribution -file logic_dist.rpt
```

A distribution heavily weighted toward 6–10 logic levels suggests wide combinational cones that may be restructurable.

---

## Part 2: Distributed RAM to BRAM Migration

**Q: The `equaliser_bank` module contains 24 independent equaliser bands, each storing filter coefficients in a 128-entry × 16-bit distributed RAM. Show how to change the RTL to infer BRAM instead, and calculate the LUT savings.**

**A:**

**Current usage (distributed RAM):**
```
24 bands × 128 entries × 16 bits / (64 bits per LUTRAM) = 768 LUTs
```

Wait — let's be precise. Each 6-input LUT in Artix-7 can implement 64×1 distributed RAM. For a 128×16 array:
```
128 entries × 16 bits = 2,048 total bits
LUTs required: 2,048 / 64 = 32 LUTs per band
Total: 24 × 32 = 768 LUTs
```

But a 128×16 distributed RAM also needs address decode and output mux logic — estimate ≈40–50 LUTs per band, so 960–1,200 LUTs total for coefficient storage.

**BRAM equivalent:**
```
128 entries × 16 bits = 2 Kb per band → 1× RAMB18 per band
(RAMB18 = 18 Kb capacity; 2 Kb << 18 Kb → very wasteful per BRAM)

Alternative: pack multiple bands into one RAMB36 using wider addressing:
24 bands × 128 entries = 3,072 address space × 16 bits
RAMB36 can be 1K×36 or 2K×18.
A 2K×16 RAMB36 holds: 24 bands × 128 entries/band = 3,072 entries
→ 2× RAMB36 (with some unused space)
```

**Better architecture: combined coefficient storage**

Instead of 24 separate RAMs, use a single BRAM with a wider address that includes the band index:

```verilog
// Before: 24 separate distributed RAMs (24 × ~50 LUTs ≈ 1,200 LUTs)
module equaliser_band #(parameter BAND_ID = 0) (
    input  logic        clk,
    input  logic        we,
    input  logic [6:0]  addr,    // 128 entries
    input  logic [15:0] wdata,
    output logic [15:0] coeff
);
    logic [15:0] coeff_ram [0:127];   // distributed RAM: ~50 LUTs
    always_ff @(posedge clk) begin
        if (we) coeff_ram[addr] <= wdata;
        coeff <= coeff_ram[addr];
    end
endmodule

// After: single BRAM for all 24 bands (≈2 RAMB36, saves ~1,150 LUTs)
module equaliser_coeff_bram (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  band_id,  // 5 bits for 24 bands (0-23)
    input  logic [6:0]  addr,     // 7 bits for 128 entries per band
    input  logic [15:0] wdata,
    output logic [15:0] coeff_out [0:23]  // all 24 band outputs (one per cycle via port sharing)
);
    // 12-bit address: {band_id[4:0], addr[6:0]} = 2^12 = 4096 locations
    // Used: 24 × 128 = 3072. Fits in one RAMB36 (4K × 9 or 2K × 18 mode)

    logic [15:0] coeff_mem [0:4095];

    logic [11:0] rd_addr;
    assign rd_addr = {band_id, addr};

    always_ff @(posedge clk) begin
        if (we)
            coeff_mem[rd_addr] <= wdata;
        // Read (registered output → BRAM output register mode)
        foreach (coeff_out[i])
            coeff_out[i] <= coeff_mem[{5'(i), addr}];  // all bands read same addr
    end
    // Synthesis attribute to force BRAM inference
    (* ram_style = "block" *) logic [15:0] coeff_mem_bram [0:4095];
endmodule
```

**If each band needs independent simultaneous access**, use a true dual-port BRAM with time-multiplexed access or accept the latency of sequential reads.

**LUT savings estimate:** 1,200 LUTs saved on coefficient storage, plus the logic around the 24 separate mux/decode blocks. Total estimate: 1,500–2,000 LUTs.

---

## Part 3: DSP Underutilisation

**Q: The `sample_rate_converter` module (31,600 LUTs) is a polyphase FIR filter with 48 phases and 64 taps per phase. It currently uses 128 DSPs. Vivado reports that 3,840 LUTs in this module are implementing 32-bit × 32-bit multiplications. How do you force DSP inference and what is the expected savings?**

**A:**

**Current situation:**

3,840 LUTs implementing 32-bit multiplications. A 32×32 multiplier uses approximately 32 LUTs in a LUT-based implementation (rough estimate), so 3,840 LUTs represents approximately 120 multiplications implemented in LUTs.

**Why they are not using DSPs:**

Common causes:
1. The `use_dsp` attribute was explicitly set to `"no"` in RTL or XDC
2. The multiplier result feeds directly into logic that prevents DSP cascade inference
3. The tool ran out of DSP48E1 blocks — but we have 612 free (740 - 128), so this is not the cause
4. The operand widths exceed DSP input sizes (DSP48E1 has 30×18 inputs for signed multiplication)

**32-bit × 32-bit and DSP width limits:**

A DSP48E1 multiplier is 30-bit × 18-bit (signed). A 32×32 multiplication exceeds this in both operands. The tool may have fallen back to LUTs.

**Solution using DSP cascade:**

A 32×32 multiplication can be decomposed into four 17×17 sub-multiplications and accumulated:

```
A[31:0] × B[31:0] = (A_hi × B_hi << 34) + (A_hi × B_lo << 17) + (A_lo × B_hi << 17) + (A_lo × B_lo)
where A_hi = A[31:17], A_lo = A[16:0], similarly for B
```

Each sub-multiplication fits in one DSP48E1. The cascaded accumulation uses the DSP's P-cascade port. This requires 4 DSPs per 32×32 multiply but consumes zero LUTs:

```verilog
// 32x32 signed multiply using 4 DSP48E1 in cascade
// Instantiate using the DSP48E1 primitive directly for precise control
module mult32x32 (
    input  logic        clk,
    input  logic signed [31:0] a,
    input  logic signed [31:0] b,
    output logic signed [63:0] p   // 64-bit product
);
    // Split operands
    logic signed [16:0] a_lo, a_hi;
    logic signed [17:0] b_lo, b_hi;

    assign a_lo = {1'b0, a[16:0]};          // 17-bit unsigned lower half
    assign a_hi = a[31:17];                  // 15-bit signed upper half (sign-extended to 17)
    assign b_lo = {1'b0, b[16:0]};          // 17-bit unsigned lower half
    assign b_hi = b[31:17];                  // sign-extended to 18 bits

    // Sub-products (registered)
    logic signed [34:0] pp_ll, pp_lh, pp_hl, pp_hh;
    always_ff @(posedge clk) begin
        pp_ll <= a_lo * b_lo;
        pp_lh <= a_lo * $signed(b_hi);
        pp_hl <= $signed(a_hi) * b_lo;
        pp_hh <= $signed(a_hi) * $signed(b_hi);
    end

    // Accumulate
    always_ff @(posedge clk)
        p <= pp_hh << 34 | (pp_lh + pp_hl) << 17 | pp_ll;

    // Force DSP for each multiplication
    (* use_dsp = "yes" *) logic signed [34:0] _pp_ll_dsp;
    // (apply the attribute to each multiply expression)
endmodule
```

**Expected savings:**

```
120 LUT-based 32×32 multipliers removed: -3,840 LUTs
120 × 4 DSPs added: +480 DSP48E1

DSPs used after: 128 + 480 = 608 / 740 = 82.2% (within target)
LUT savings: 3,840 LUTs
```

**Warning:** This change adds latency (pipeline stages inside the multiplier). Verify the overall pipeline depth budget for the sample rate converter is still met. Add a `set_multicycle_path` if the output of `mult32x32` does not need to be used in the very next clock cycle.

---

## Part 4: equaliser_bank Structural Optimisation

**Q: The `equaliser_bank` module has 44,800 LUTs for 24 identical equaliser bands. Each band uses a biquad IIR filter with 5 fixed-point multiply-accumulate operations. The 24 bands process the same input sample in parallel. Propose a time-multiplexed architecture and estimate the LUT reduction.**

**A:**

**Current architecture:**

```
24 bands in parallel:
  Each band: 5 MACs × ~186 LUTs per MAC (16×16 fixed-point) = 930 LUTs
  Plus state registers and coefficient read: ~50 LUTs
  Total per band: ~980 LUTs × 24 = ~23,520 LUTs (rest is overhead/state)

Actual: 44,800 LUTs (includes coefficient decode, state machines, etc.)
```

**Time-multiplexed architecture:**

All 24 bands process the same sample rate (assume 48 kHz audio = 48,000 samples/sec). The FPGA runs at 100 MHz. The time budget for all 24 bands is:

```
FPGA cycles per audio sample = 100 MHz / 48 kHz = 2,083 cycles
Cycles available per band = 2,083 / 24 = 86 cycles per band
Cycles needed for a 5-tap biquad = ~10 cycles (5 MACs with pipeline)
```

86 cycles >> 10 cycles required — there is massive time-multiplexing headroom.

**New architecture: 1 shared MAC unit processes all 24 bands sequentially:**

```verilog
module equaliser_bank_timemux #(
    parameter N_BANDS  = 24,
    parameter N_STAGES = 5,    // biquad has 5 MUL operations
    parameter WIDTH    = 16,
    parameter FRAC     = 12
)(
    input  logic                      clk,
    input  logic                      rst,
    input  logic signed [WIDTH-1:0]   audio_in,
    output logic signed [WIDTH-1:0]   audio_out [0:N_BANDS-1],
    output logic                      valid
);
    // State machine: for each of N_BANDS, run N_STAGES MAC operations
    logic [$clog2(N_BANDS)-1:0]  band_idx;
    logic [$clog2(N_STAGES)-1:0] stage_idx;

    // Shared single MAC unit — infers ONE DSP48E1
    logic signed [WIDTH-1:0]   mac_a, mac_b;
    logic signed [2*WIDTH-1:0] mac_product;
    logic signed [2*WIDTH-1:0] mac_accum;

    (* use_dsp = "yes" *) always_ff @(posedge clk)
        mac_product <= mac_a * mac_b;

    // Coefficient BRAM: addressed by {band_idx, stage_idx}
    logic [WIDTH-1:0] coeff_bram [0:N_BANDS*N_STAGES-1];  // infer BRAM
    (* ram_style = "block" *) logic [WIDTH-1:0] coeff;
    always_ff @(posedge clk)
        coeff <= coeff_bram[{band_idx, stage_idx}];

    // State registers for each band (x1, x2, y1, y2 — 4 states × 24 bands)
    logic signed [WIDTH-1:0] state_x1 [0:N_BANDS-1];
    logic signed [WIDTH-1:0] state_x2 [0:N_BANDS-1];
    logic signed [WIDTH-1:0] state_y1 [0:N_BANDS-1];
    logic signed [WIDTH-1:0] state_y2 [0:N_BANDS-1];

    // Scheduler
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            band_idx  <= '0;
            stage_idx <= '0;
            valid     <= 1'b0;
        end else begin
            // Advance band and stage counters
            if (stage_idx == N_STAGES - 1) begin
                stage_idx <= '0;
                if (band_idx == N_BANDS - 1) begin
                    band_idx <= '0;
                    valid    <= 1'b1;  // all bands complete
                end else begin
                    band_idx <= band_idx + 1;
                    valid    <= 1'b0;
                end
            end else begin
                stage_idx <= stage_idx + 1;
                valid     <= 1'b0;
            end
        end
    end

    // MUX inputs to the shared MAC based on current stage
    always_comb begin
        case (stage_idx)
            3'd0: begin mac_a = audio_in;           mac_b = coeff; end  // b0*x
            3'd1: begin mac_a = state_x1[band_idx]; mac_b = coeff; end  // b1*x1
            3'd2: begin mac_a = state_x2[band_idx]; mac_b = coeff; end  // b2*x2
            3'd3: begin mac_a = state_y1[band_idx]; mac_b = coeff; end  // a1*y1
            3'd4: begin mac_a = state_y2[band_idx]; mac_b = coeff; end  // a2*y2
            default: begin mac_a = '0; mac_b = '0; end
        endcase
    end

    // Accumulate and write output
    always_ff @(posedge clk) begin
        if (stage_idx == 0)
            mac_accum <= mac_product;
        else
            mac_accum <= mac_accum + mac_product;

        if (stage_idx == N_STAGES - 1) begin
            audio_out[band_idx] <= mac_accum[WIDTH+FRAC-1:FRAC];  // truncate
            // Update state registers
            state_y2[band_idx] <= state_y1[band_idx];
            state_y1[band_idx] <= mac_accum[WIDTH+FRAC-1:FRAC];
            state_x2[band_idx] <= state_x1[band_idx];
            state_x1[band_idx] <= audio_in;
        end
    end
endmodule
```

**LUT savings analysis:**

```
Old architecture: 24 MAC units × ~186 LUTs = 4,464 LUTs (MAC logic alone)
New architecture: 1 MAC unit + state registers + scheduler
  - 1 shared MAC (DSP): ~0 LUTs (in DSP48E1)
  - State registers (24 × 4 × 16 bits): stored in BRAM or LUT flipflops
    As LUTRAM: (24 × 4 × 16) / 64 = 24 LUTs
  - Coefficient BRAM: 0 LUTs (in RAMB18)
  - Scheduler and MUX: ~200 LUTs
  Total new: ~224 LUTs

Savings: ~4,240 LUTs from MAC alone.
Full equaliser_bank overhead (state machines, output formatting, overflow protection):
  Estimate total new equaliser_bank: ~2,000–3,000 LUTs
  vs current: 44,800 LUTs
  Savings: ~42,000 LUTs
```

**Caveat:** The state registers (`state_x1`, `state_y1`, etc.) in an array of 24 × 4 registers are naturally inferred as a register file. If the tool maps them to LUT RAM rather than flip-flops, convert them to a BRAM:

```tcl
# Force register array to be implemented as flip-flops (for small arrays)
# or use ram_style = "distributed" / "block" for explicit control
set_property ram_style register [get_cells {equaliser_bank_timemux/state_x1_reg*}]
```

---

## Part 5: Synthesis Settings

**Q: After making the RTL changes above, which Vivado synthesis settings help squeeze out additional LUT reduction?**

**A:**

```tcl
# Full synthesis command with area-optimisation settings
synth_design -top top_level \
             -part xc7a200tffg1156-2 \
             -directive AreaOptimized_high \
             -fsm_extraction auto \
             -resource_sharing on \
             -keep_equivalent_registers \
             -no_lc
```

**Setting explanations:**

- `-directive AreaOptimized_high` — Aggressive logic sharing and constant propagation. May increase logic depth (hurts timing) but reduces LUT count.
- `-resource_sharing on` — Enables the tool to share arithmetic operators across time-multiplexed operations. Complements manual sharing.
- `-keep_equivalent_registers` — Prevents the tool from removing logically identical registers. Relevant only if duplicate registers were intentionally created for timing; disable if your intent is area reduction.
- `-no_lc` — Disables LUT combining within a LUTRAM structure. Can reduce LUTRAM utilisation but slightly increases pure LUT usage.

**Post-synthesis check:**

```tcl
report_utilization
report_design_analysis -logic_level_distribution -file logic_levels.rpt
```

Verify that:
1. LUT count has decreased
2. BRAM count has increased (confirming BRAM inference)
3. DSP count has increased (confirming DSP inference)
4. Logic level distribution has not dramatically worsened (check max levels per clock domain)

---

## Summary: Reduction Estimate

| Optimisation | LUT Reduction |
|---|---|
| Distributed RAM → BRAM (coefficient storage) | ~2,000 |
| LUT multipliers → DSP48E1 (32×32 MACs) | ~3,840 |
| Time-multiplexed equaliser_bank | ~42,000 |
| Synthesis directive (AreaOptimized_high) | ~2,000–3,000 |
| **Total estimated reduction** | **~50,000 LUTs** |

**Target:** 128,440 − 14,030 = 114,410 LUTs maximum  
**Projected result:** 128,440 − 50,000 ≈ 78,440 LUTs (**58% utilisation**)

This exceeds the target by a comfortable margin and provides headroom for future features.

**Interview insight:** The single largest gain (42,000 LUTs) came from a microarchitectural change — time-multiplexing — not from tweaking synthesis settings. This is the key lesson: when a design significantly exceeds resource targets, synthesis settings and attribute tuning are secondary. The primary lever is architectural restructuring. Interviewers at senior level expect candidates to reach for this lever first.
