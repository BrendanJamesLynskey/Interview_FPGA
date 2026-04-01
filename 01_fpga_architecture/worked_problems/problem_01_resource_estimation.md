# Problem 01: Resource Estimation

## Problem Statement

You are an FPGA architect preparing a feasibility study. A product manager has asked whether the following DSP subsystem can fit on a **Xilinx Kintex UltraScale KU040** device. The design requirements are:

**Design description:** A real-time digital up-converter (DUC) for a 4-channel software-defined radio transmitter.

**Per-channel requirements:**
- Polyphase FIR interpolation filter: 64 taps, 16-bit input, 18-bit coefficients, interpolation factor 8
- Complex multiplier for digital frequency shift: 24-bit I/Q × 18-bit coefficient
- CORDIC-based gain control: 16-bit I/Q, 10-stage pipeline
- Control and datapath logic: estimated 500 LUTs of overhead per channel

**System-wide requirements:**
- 4 independent channels
- 250 MHz processing clock
- AXI4-Lite register interface (shared): ~200 LUTs, ~150 FFs
- Clock generation: one MMCM for all clock outputs

**KU040 device resources:**
- LUT6: 242,400
- Flip-flops: 484,800
- BRAM 36Kb: 600
- DSP48E2: 1,920
- MMCM: 10 (across the device)

**Questions to answer:**

1. Estimate the DSP48E2 count required for the DUC.
2. Estimate the BRAM count for coefficient storage.
3. Estimate the LUT and FF count.
4. Determine whether the design fits on a KU040.
5. Identify the most likely bottleneck resource.

---

## Worked Solution

### Step 1 — DSP48E2 Estimation

**Polyphase FIR interpolation filter (per channel):**

A direct 64-tap FIR at 18-bit coefficients with 16-bit input would require 64 DSP48E2 primitives in the naive case (one multiplier per tap). However, a polyphase decomposition with interpolation factor 8 splits the 64-tap filter into 8 subfilters of 8 taps each. At any given input sample, only one subfilter is active (the polyphase phase selector). If the subfilters run sequentially (time-multiplexed on the 250 MHz clock), the number of physical multipliers equals the number of taps per subfilter.

Check: input sample rate 250 MHz / 8 = 31.25 MHz output from the previous stage. Each input sample produces 8 output samples. With 8 subfilters of 8 taps, time-multiplexing over 8 phases uses 8 physical multipliers.

**Symmetric coefficients:** A 64-tap linear-phase FIR has 32 unique tap values. With 8 taps per subfilter, symmetry gives 4 unique values per subfilter. The pre-adder in DSP48E2 halves the multiply count. Per subfilter: 4 DSPs.

**Total FIR DSPs per channel:** 4 DSP48E2 (exploiting symmetry + time-multiplexing).

**Complex frequency shift multiplier (per channel):**

Complex multiply $(I + jQ) \times (H_r + jH_i)$:
- Naive: 4 real multiplies
- Karatsuba: 3 real multiplies

Each 24×18-bit multiply fits in one DSP48E2.

**DSPs for complex multiplier per channel: 3 DSP48E2.**

**CORDIC gain control (per channel):**

A 10-stage CORDIC pipeline uses only additions and shifts — no multiplications. CORDIC is implemented entirely in LUT + carry chain logic, **not** in DSP48E2.

**DSPs for CORDIC: 0.**

**DSP48E2 summary:**

| Block | DSPs per channel | 4 channels |
|---|---|---|
| Polyphase FIR | 4 | 16 |
| Complex multiplier | 3 | 12 |
| CORDIC | 0 | 0 |
| Overhead/margin (10%) | ~1 | ~3 |
| **Total** | **~8** | **~31** |

**KU040 DSP limit: 1,920.** Estimated usage: **31 DSP48E2 (1.6%).**

DSP resources are not a constraint. The KU040 is massively over-specified for DSP alone.

---

### Step 2 — BRAM Estimation

**Coefficient storage — polyphase FIR:**

64 coefficients × 18 bits = 1,152 bits per channel.
For 4 channels with independent coefficients: 4 × 1,152 = 4,608 bits.

Minimum BRAM: a single 18Kb BRAM (16,384 bits) can hold all four channels' coefficients with 64-address × 72-bit width leaving only 4,608 / 16,384 = 28% utilisation. Use one 18Kb half-BRAM.

Alternatively, if coefficients are fixed at synthesis time, they fold into LUT INIT strings: **0 BRAMs** for fixed coefficients.

**Delay line for FIR (sample storage):**

Each polyphase channel needs a delay line of 63 previous samples (for 64-tap FIR), 16 bits wide.
63 × 16 = 1,008 bits per channel, 4 channels = 4,032 bits total.

At 16-bit width and 64-deep, a distributed RAM (RAM64M8 in SLICEM: 64 × 8-bit) uses 2 RAM64M8 primitives per channel per bit-group. More practically: each channel's delay line fits in 16 LUT cells configured as RAM64X1S (1 LUT per 64 × 1 bit = 1,008 bits / 64 = 16 LUTs per channel).

Total delay line: 4 × 16 = **64 SLICEM LUTs** (no BRAM needed).

**AXI4-Lite register file:**

A typical AXI4-Lite register file with 32 control registers (32-bit): 1,024 bits. Fits in distributed RAM (16 SLICEM LUTs) or one RAMB18. At this size, distributed RAM is appropriate.

**BRAM summary:**

| Use | BRAMs |
|---|---|
| Coefficient storage (programmable) | 1 (18Kb half) |
| Delay lines | 0 (use distributed RAM) |
| Register file | 0 (use distributed RAM) |
| **Total BRAMs** | **1** |

**KU040 BRAM limit: 600.** Estimated usage: **1 BRAM (<1%).**

BRAMs are not a constraint.

---

### Step 3 — LUT and FF Estimation

**Polyphase FIR (per channel) — LUT/FF for pipeline logic:**

The 4 DSP48E2s handle the multiplication. Supporting logic includes:
- Address counter for polyphase phase selection: 3-bit counter = ~6 LUTs, 3 FFs
- Coefficient address decoder: ~8 LUTs
- Input sample mux (8:1 for time-multiplexed subfilters): 8 × 16-bit = ~24 LUTs (F7/F8 muxes)
- Accumulator register between DSP cascade stages: handled inside DSP48E2 (PREG)
- Output scaling/rounding (18-bit output): ~12 LUTs

Per-channel FIR overhead: approximately **50 LUTs, 30 FFs.**

**CORDIC pipeline (per channel):**

A 10-stage CORDIC for 16-bit I/Q uses CORDIC rotation equations:

$$X_{i+1} = X_i - d_i \cdot 2^{-i} \cdot Y_i$$
$$Y_{i+1} = Y_i + d_i \cdot 2^{-i} \cdot X_i$$

Each stage involves two 16-bit additions/subtractions with a shift — implemented in carry chains. Each 16-bit adder uses one CARRY8 (one Slice column height of 2 Slices = 16 LUTs). Two adders per stage × 10 stages × 16-bit = approximately:

- Adder logic: 10 stages × 2 × 2 Slices × 8 LUTs = 320 LUTs (carry chain, CARRY8 occupies LUT cells)
- Stage registers: 10 stages × 2 × 16 bits = 320 FFs
- Direction decision logic: 10 × 8 LUTs = 80 LUTs

Per-channel CORDIC: approximately **400 LUTs, 320 FFs.**

**Complex frequency shifter (per channel):**

3 DSP48E2s perform the multiplies. Surrounding logic:
- Phase accumulator (NCO): 24-bit counter = ~30 LUTs, 24 FFs
- Output adder/subtractor for complex combine: ~30 LUTs, 40 FFs
- Saturation/clipping: ~16 LUTs

Per-channel frequency shifter overhead: approximately **76 LUTs, 64 FFs.**

**Control and datapath overhead (given): 500 LUTs per channel.**

**Per-channel total LUT/FF estimate:**

| Block | LUTs | FFs |
|---|---|---|
| Polyphase FIR support | 50 | 30 |
| CORDIC | 400 | 320 |
| Complex frequency shifter | 76 | 64 |
| Control/datapath overhead | 500 | 400 (estimated) |
| **Per channel total** | **~1,026** | **~814** |

**4-channel system + AXI:**

| Component | LUTs | FFs |
|---|---|---|
| 4 × DUC channel | 4,104 | 3,256 |
| AXI4-Lite interface | 200 | 150 |
| MMCM support logic | 20 | 16 |
| **Grand total** | **~4,324** | **~3,422** |

**KU040 LUT limit: 242,400. Estimated usage: 4,324 LUTs (1.8%).**

LUTs and FFs are trivially within budget.

---

### Step 4 — Feasibility Verdict

| Resource | KU040 Available | Estimated Usage | Utilisation |
|---|---|---|---|
| LUT6 | 242,400 | ~4,324 | **1.8%** |
| Flip-flops | 484,800 | ~3,422 | **0.7%** |
| BRAM 36Kb | 600 | ~1 | **<1%** |
| DSP48E2 | 1,920 | ~31 | **1.6%** |
| MMCM | 10 | 1 | **10%** |

**The design fits comfortably on a KU040.** In fact, the design uses less than 2% of any resource. The KU040 is massively over-specified for this workload.

**Recommendation:** Revisit the device selection. A smaller device in the UltraScale family (e.g., KU025 with 145,680 LUTs, 1,920 DSPs) or even a 7-series device (e.g., Kintex-7 XC7K70T) would accommodate this design at significantly lower cost.

---

### Step 5 — Most Likely Bottleneck and Timing Risk

At 1.8% LUT utilisation and 1.6% DSP utilisation, resource availability is not the constraint. The realistic bottleneck is **timing closure at 250 MHz** in two specific areas:

**1. CORDIC critical path:**

The 10-stage CORDIC runs at 250 MHz with carry-chain additions. Each CARRY8 stage adds ~0.5 ns. A 16-bit addition uses 2 CARRY8 stages = ~1 ns of carry chain + ~0.5 ns of routing = ~1.5 ns per stage. With proper pipeline registers at each CORDIC stage (as described), timing is achievable. Without registers between stages, 10 additions in series = 15 ns — completely unable to close.

**Action:** Verify the CORDIC implementation registers between every stage.

**2. FIR polyphase control timing:**

The 8:1 time-multiplexing requires the correct coefficient and sample to be selected within one clock cycle. At 250 MHz (4 ns cycle), the selection path (3-bit counter → address decode → coefficient RAM read → DSP input) must complete within the BRAM or distributed RAM read latency. With BRAM output register enabled (2-cycle latency), the coefficient address must be presented 2 cycles early. Verify the pipeline alignment.

**Interview takeaway:** Resource estimation is not just about counting primitives. The estimate is only useful if it flags whether timing closure is realistic at the target frequency for the chosen architecture.

---

### Common Interview Pitfalls

**Forgetting to apply polyphase decomposition:** A candidate who estimates 64 DSPs for the FIR (one per tap) without considering time-multiplexing or polyphase decomposition will significantly overestimate DSP usage. Always check whether time-multiplexing is applicable before counting resources.

**Ignoring CORDIC's LUT cost:** CORDIC is "free" in DSP terms but uses 300–500 LUTs per 16-bit 10-stage pipeline. This is still negligible on a KU040, but significant on a smaller device. Always account for it.

**Recommending the wrong device:** Giving a utilisation estimate without recommending a right-sized device is an incomplete answer. If the design uses 2% of a KU040, the engineer must at least flag that a cost re-evaluation is appropriate.
