# DSP Slices

## Overview

DSP slices are hardened arithmetic macros embedded in the FPGA fabric. They perform the multiply-accumulate operations at the heart of signal processing, machine learning inference, and high-speed arithmetic — at far higher performance and lower power than equivalent LUT-based logic. In Xilinx UltraScale/UltraScale+ devices, the DSP primitive is the **DSP48E2**, a flexible 27×18 multiplier combined with a 48-bit post-adder and accumulator. Understanding its internal pipeline, cascade interfaces, and the patterns for which it is optimally suited is essential for both resource estimation and performance optimisation.

---

## Tier 1: Fundamentals

### Q1. What is the core function of a DSP48E2 slice? Describe its key input and output ports.

**Answer:**

The DSP48E2 is a 27×18-bit two's-complement multiplier with a pre-adder and a 48-bit post-add/accumulate stage, all within a single hardened macro. Its most common use is the multiply-accumulate operation:

$$P = A \times B + C \quad \text{or} \quad P = P + A \times B$$

**Key input ports:**

| Port | Width | Function |
|---|---|---|
| A | 30 bits | Multiplier input (upper) / pre-adder input / cascade input source |
| B | 18 bits | Multiplier input (lower) |
| C | 48 bits | Post-adder addend (third operand) |
| D | 27 bits | Pre-adder input (combined with A before multiply) |
| P (feedback) | 48 bits | Accumulator feedback — output of prior cycle fed back to post-adder |
| CARRYIN | 1 bit | Carry input to post-adder |
| ACIN/BCIN | 30/18 bits | Cascade inputs from adjacent DSP (no routing fabric) |
| PCIN | 48 bits | P cascade input from adjacent DSP |

**Key output ports:**

| Port | Width | Function |
|---|---|---|
| P | 48 bits | Post-adder/accumulator result |
| ACOUT/BCOUT | 30/18 bits | A/B cascade outputs to next DSP |
| PCOUT | 48 bits | P cascade output to next DSP |
| CARRYOUT | 4 bits | Carry out of each 12-bit section of the post-adder |
| OVERFLOW | 1 bit | Overflow detect for P accumulator |

**OPMODE and ALUMODE:** The DSP48E2 is controlled by a 9-bit `OPMODE` word and 4-bit `ALUMODE` word. These select which inputs feed each internal stage, enabling one primitive to implement dozens of different arithmetic functions. The tools set these automatically when the DSP is inferred from RTL; they are set manually when using the primitive directly.

---

### Q2. Draw and describe the internal pipeline stages of a DSP48E2. How many pipeline registers are available and where are they?

**Answer:**

The DSP48E2 has three optional pipeline register stages, arranged as follows:

```
                    A[29:0]     D[26:0]     B[17:0]
                       |           |           |
                    [AREG]      [DREG]      [BREG]    <-- Stage 1 registers
                       |           |           |
                       +--->[Pre-adder]        |
                       |    (A+D or A-D)       |
                       |           |           |
                    [A2REG]    [AD_REG]    [B2REG]    <-- Stage 2 registers
                       |           |           |
                       +-------->[Mult]<-------+
                                   |
                               [MREG]                 <-- Stage M register (between mult and post-add)
                                   |
               C[47:0]  P_feedback  CARRYIN
                  |          |        |
                  +----------+--------+
                             |
                        [Post-adder / ALU]
                           P = M + C
                             |
                          [PREG]                      <-- Stage P register (output)
                             |
                          P[47:0] out
```

**Pipeline stage summary:**

| Stage | Registers | Purpose |
|---|---|---|
| A input | AREG (0, 1, or 2) | Pipeline A input before multiply |
| B input | BREG (0, 1, or 2) | Pipeline B input before multiply |
| D input | DREG (0 or 1) | Pipeline D before pre-adder |
| A+D result | ADREG (0 or 1) | Pipeline pre-adder result |
| Multiplier | MREG (0 or 1) | Pipeline multiplier output |
| Post-adder | PREG (0 or 1) | Pipeline accumulator output |

**Maximum pipeline depth:** 4 registered stages (AREG=2, MREG=1, PREG=1) between input and P output.

**Why pipeline stages matter:**

Without any registers (MREG=0, PREG=0), the DSP48E2 is purely combinational. The propagation delay from A/B inputs to P output through the full multiplier and post-adder is approximately 3–4 ns, limiting clock rates to ~250 MHz.

With MREG=1 and PREG=1 enabled, the multiplier result is registered after the multiply stage and the post-adder is a separate pipeline stage. The critical path splits into:
- Stage 1: $T_{mult}$ ≈ 1.5–2.0 ns
- Stage 2: $T_{post-add}$ ≈ 0.5–1.0 ns

This allows clock rates of 500–700 MHz on high-speed UltraScale+ grade parts. Enabling MREG is the single most important DSP timing decision.

---

### Q3. What is the pre-adder in a DSP48E2 and what operation does it enable that would otherwise require an extra DSP or LUTs?

**Answer:**

The pre-adder is a dedicated 27-bit adder placed before the multiplier's A input. It computes either:

$$AD = D + A \quad \text{(pre-add mode)}$$
$$AD = D - A \quad \text{(pre-subtract mode)}$$

The result $AD$ feeds the multiplier's upper input instead of $A$ directly.

**Why the pre-adder is important — the symmetric FIR filter:**

A symmetric FIR filter with $N$ taps has the property:

$$h[k] = h[N-1-k]$$

This symmetry means that samples $x[n-k]$ and $x[n-(N-1-k)]$ are always multiplied by the same coefficient $h[k]$. Rather than using two multipliers:

$$h[k] \cdot x[n-k] + h[k] \cdot x[n-(N-1-k)] = h[k] \cdot (x[n-k] + x[n-(N-1-k)])$$

The pre-adder computes $x[n-k] + x[n-(N-1-k)]$ first, then a single multiply gives the combined result.

**Resource saving:**

For a 32-tap symmetric FIR:
- Without pre-adder: 32 DSP48E2 primitives (one per tap)
- With pre-adder: 16 DSP48E2 primitives (one per tap pair)

This is a 2× reduction in DSP usage with no loss of functionality and only a small increase in pre-adder delay (which fits within the A-input pipeline register budget).

**RTL inference:** Synthesis tools automatically detect symmetric FIR patterns and map them to the pre-adder. The designer can also instantiate the pre-adder explicitly using the `USE_DPORT` attribute on the DSP48E2 primitive.

---

### Q4. What is DSP cascade, and why is it used instead of routing the P output back through the fabric?

**Answer:**

DSP cascade is a set of dedicated point-to-point connections between adjacent DSP48E2 slices in the same column. Three cascade buses exist:

- **PCOUT → PCIN:** 48-bit P output of one DSP feeds directly into the post-adder C or P-feedback input of the next DSP below
- **ACOUT → ACIN:** 30-bit A output carries an A value down the column
- **BCOUT → BCIN:** 18-bit B output carries a B value down the column

**Why cascade instead of fabric routing:**

If the P output of DSP0 is routed to DSP1's input via the general routing fabric:
- Routing delay: approximately 0.5–1.5 ns additional
- This delay is added to the critical path, reducing achievable clock frequency
- The route consumes routing resources that may be needed elsewhere

The dedicated cascade connection has near-zero propagation delay (<50 ps) and requires no routing fabric resources. Cascaded DSPs effectively operate as a single deep arithmetic pipeline.

**Cascade application — MAC accumulator chain:**

A multiply-accumulate over 8 inputs using cascade:

```
DSP0: P0 = A0×B0 + C0              ; PCOUT → DSP1 PCIN
DSP1: P1 = A1×B1 + PCIN1           ; PCOUT → DSP2 PCIN
DSP2: P2 = A2×B2 + PCIN2           ; ...
...
DSP7: P7 = A7×B7 + PCIN7           ; Final result
```

All 8 DSPs operate simultaneously on different data (fully pipelined), producing one accumulated result per clock cycle after the initial fill latency. The PCOUT-to-PCIN cascade is what makes this pipeline physically and timingwise feasible.

**Cascade application — wide multiplier:**

A 48×24-bit multiplier that exceeds DSP48E2's native 27×18 capacity is built from multiple DSPs connected via PCOUT/PCIN cascade to accumulate partial products. This is described in detail in the Advanced section.

---

## Tier 2: Intermediate

### Q5. A designer needs to implement a running accumulator: $P[n] = P[n-1] + A[n] \times B[n]$, operating at 500 MHz. How do you configure the DSP48E2, what is the latency, and what is the maximum accumulation depth before overflow?

**Answer:**

**DSP48E2 configuration:**

The running accumulator feeds P back to the post-adder input. In DSP48E2 terminology:
- `OPMODE[6:4] = 3'b010` — selects P register feedback as the Z input to the post-adder
- `OPMODE[3:0] = 4'b0101` — selects M (multiplier output) as the W input
- `MREG = 1` — register the multiplier output
- `PREG = 1` — register the accumulator output

The accumulation equation mapped to DSP internals:

$$P_{out} = \underbrace{P_{feedback}}_{\text{from PREG}} + \underbrace{A \times B}_{\text{from MREG}}$$

**Pipeline stages and latency:**

With AREG=1, BREG=1, MREG=1, PREG=1:
- Cycle 0: A[n], B[n] arrive, registered into AREG/BREG
- Cycle 1: Multiplier computes A[n]×B[n], result registered into MREG
- Cycle 2: Post-adder sums MREG + P_feedback, result registered into PREG

Effective accumulation latency: **2 clock cycles** from input data to updated P output. The pipeline runs at full clock rate — a new A×B pair enters every cycle, but the accumulation result is valid at P after 2 cycles.

**Timing at 500 MHz ($T_{clk} = 2$ ns):**

- AREG-to-multiplier path: ~1.5 ns (fits in 2 ns)
- MREG-to-PREG path (post-adder): ~0.8 ns (fits in 2 ns)
- 500 MHz is achievable on –1 or –2 speed grade UltraScale+

**Maximum accumulation depth before overflow:**

The A×B product is at most 27+18 = 45 bits wide (signed). For unsigned: $A_{max} = 2^{27}-1$, $B_{max} = 2^{18}-1$. The maximum product is approximately $2^{45}$.

The P accumulator is 48 bits wide. Accumulating $N$ such products:

$$P_{max} = N \times (2^{27}-1)(2^{18}-1) \approx N \times 2^{45}$$

For P to remain within 48 bits: $N \times 2^{45} < 2^{48}$, so $N < 2^3 = 8$.

For 16-bit inputs (A[15:0], B[15:0] — typical DSP precision):

$$P_{max} = N \times (2^{16}-1)^2 \approx N \times 2^{32}$$

$$N \times 2^{32} < 2^{48} \implies N < 2^{16} = 65,536$$

A 16-bit accumulation can safely run for up to 65,536 cycles before overflow. In practice, designs either truncate the accumulator or use the OVERFLOW output flag and reset/saturate on overflow.

---

### Q6. Explain how to implement a 48×24-bit multiplier using multiple DSP48E2 slices and cascade. What is the minimum number of DSPs required?

**Answer:**

A 48×24-bit multiplier exceeds the 27×18 input width of a single DSP48E2. The approach is to decompose the multiply into partial products.

**Decomposition:**

Let $A$ be 48 bits and $B$ be 24 bits. Split A into two 24-bit halves:

$$A = A_H \cdot 2^{24} + A_L$$

where $A_H = A[47:24]$ and $A_L = A[23:0]$.

Then:

$$A \times B = (A_H \cdot 2^{24} + A_L) \times B = A_H \cdot B \cdot 2^{24} + A_L \cdot B$$

Each partial product $A_H \times B$ and $A_L \times B$ is a 24×24-bit multiply, fitting in one DSP48E2 (24 ≤ 27, 24 ≤ 18+6 — note B must be ≤18 bits; 24 bits requires an additional split).

**More careful decomposition for DSP48E2 constraints:**

$A_L$ is 24 bits, $B$ is 24 bits. $B > 18$ bits. Split B too:

$$B = B_H \cdot 2^{18} + B_L, \quad B_H = B[23:18] \text{ (6 bits)}, \quad B_L = B[17:0] \text{ (18 bits)}$$

Now four partial products, each fitting in one DSP:

1. $A_L \times B_L$: 24×18 (fits in DSP; use A[23:0] = 0 || A_L with sign extension)
2. $A_L \times B_H$: 24×6 (fits trivially)
3. $A_H \times B_L$: 24×18
4. $A_H \times B_H$: 24×6

**Shift and sum:**

$$A \times B = A_L \cdot B_L + (A_L \cdot B_H + A_H \cdot B_L) \cdot 2^{18} + A_H \cdot B_H \cdot 2^{36}$$

This requires 4 multiply operations, and the shifts are handled by appropriate alignment of the 48-bit P output from each DSP — feeding PCOUT of the lower DSP into the post-adder (C input) of the next DSP with the implicit $2^{18}$ shift managed by bit alignment.

**Minimum DSP count:**

For a 48×24-bit multiply using the decomposition above: **4 DSP48E2** slices in cascade. Real synthesis tools may use 3 DSPs with careful pre-addition if the structure permits.

**Cascade timing:**

Each DSP in the chain has its PCOUT feeding the next DSP's PCIN. With MREG=1 on each DSP, the carry-save accumulation takes 4 pipeline stages (4 clock cycles latency), then produces a valid 72-bit result (48+24) each cycle thereafter.

---

### Q7. What is the OPMODE bus on a DSP48E2? Give three concrete examples of different OPMODE configurations and what arithmetic operation each implements.

**Answer:**

`OPMODE[8:0]` is a 9-bit control word that selects the source operands for the post-adder and the accumulator within the DSP48E2. It can be a static tie-off (compile-time operation selection) or a dynamic register (run-time selection between operations).

**OPMODE field breakdown:**

| Bits | Name | Function |
|---|---|---|
| [8:7] | W_MUX | Selects input to W adder port |
| [6:4] | Z_MUX | Selects input to Z adder port |
| [3:2] | Y_MUX | Selects M bits [17:0] or 18'h0 |
| [1:0] | X_MUX | Selects M bits [35:18] or 0 |

Post-adder computes: $P = W \pm Z \pm X:Y$ (the exact combination controlled by `ALUMODE`).

**Example 1 — Simple multiply (P = A × B):**

```
OPMODE = 9'b000_000_101
  W_MUX[8:7] = 2'b00 → W = 0
  Z_MUX[6:4] = 3'b000 → Z = 0
  X_MUX[1:0] = 2'b01 → X = M[17:0]
  Y_MUX[3:2] = 2'b01 → Y = M[35:18]
  
Result: P = 0 + M = A×B
ALUMODE = 4'b0000 (addition)
```

**Example 2 — Multiply-accumulate (P = P + A × B):**

```
OPMODE = 9'b000_010_101
  W_MUX[8:7] = 2'b00 → W = 0
  Z_MUX[6:4] = 3'b010 → Z = P (feedback from PREG)
  X_MUX[1:0] = 2'b01, Y_MUX[3:2] = 2'b01 → X:Y = M
  
Result: P = P_feedback + M = P_prev + A×B
ALUMODE = 4'b0000
```

**Example 3 — Three-input add (P = A + B + C) without multiply:**

```
OPMODE = 9'b000_011_011
  W_MUX[8:7] = 2'b00 → W = 0
  Z_MUX[6:4] = 3'b011 → Z = C[47:0]
  X_MUX[1:0] = 2'b11, Y_MUX[3:2] = 2'b11 → X:Y = A+B concatenated

Result: P = C + A + B (using A as the 30-bit extended input, B as 18-bit)
ALUMODE = 4'b0000
```

This avoids using the multiplier at all — the DSP48E2 functions as a fast 3-operand 48-bit adder, which can be valuable in datapaths that need high-speed addition but have no multiplication requirement.

**Dynamic OPMODE:** When the DSP must switch between operations at run time (e.g., a processor ALU), OPMODE is driven from a registered control signal. The register stage for OPMODE must be placed at the same pipeline depth as the data registers (AREG, BREG) to ensure the control arrives in the correct cycle.

---

## Tier 3: Advanced

### Q8. You are implementing a 16-tap complex FIR filter for a software-defined radio application. The input is a 16-bit complex baseband signal (I and Q channels). Coefficient width is 18 bits. Derive the minimum DSP count and sketch the data flow.

**Answer:**

**Problem decomposition:**

A complex multiplication of $(I + jQ) \times (H_r + jH_i)$ expands to:

$$\text{Out}_I = I \cdot H_r - Q \cdot H_i$$
$$\text{Out}_Q = I \cdot H_i + Q \cdot H_r$$

For each tap $k$ of the FIR filter, the input sample $(I[k], Q[k])$ is multiplied by coefficient $(H_r[k], H_i[k])$. Each complex tap requires four real multiplications and two real additions.

**With 16 taps:**

Naive implementation: $16 \times 4 = 64$ real multiplies.

**Optimisation 1 — Symmetric coefficients:**

If the filter has symmetric real and imaginary coefficients (a common case for bandpass filters derived from a real prototype), the pre-adder halves the real multiply count: $16 \times 2 = 32$ DSPs.

**Optimisation 2 — Karatsuba multiplication for complex multiply:**

The Karatsuba identity for complex multiply requires 3 real multiplications instead of 4:

$$I \cdot H_r - Q \cdot H_i = \underbrace{(I-Q)}_{D_1} \cdot \underbrace{H_i}_{M_1} + \underbrace{I}_{D_2} \cdot \underbrace{(H_r - H_i)}_{M_2}$$
$$I \cdot H_i + Q \cdot H_r = \underbrace{(I-Q)}_{D_1} \cdot \underbrace{H_i}_{M_1} + \underbrace{Q}_{D_3} \cdot \underbrace{(H_r + H_i)}_{M_3}$$

This uses 3 multiplies per tap (sharing $M_1$). The pre-adders $(I-Q)$, $(H_r - H_i)$, $(H_r + H_i)$ are computed before the multiply stage.

**16 taps × 3 multiplies = 48 DSPs** — a 25% saving over the naive 64.

**Further: symmetric complex FIR with Karatsuba:**

If the filter is also symmetric (16 taps → 8 unique tap pairs):
$8 \times 3 = 24$ DSPs for the multiply core + 8 DSPs for the complex accumulation tree.

**Minimum DSP count estimate: 24–32 DSPs** depending on whether symmetry and Karatsuba are both applied.

**Data flow sketch:**

```
Input: I[n], Q[n] (16-bit, new sample each clock)
Delay lines: I[n-0]...I[n-15], Q[n-0]...Q[n-15] (via SRL32)

For tap k = 0..7 (symmetric):
  Pre-add: I_sum[k] = I[n-k] + I[n-15+k]  (using DSP pre-adder D port)
           Q_sum[k] = Q[n-k] + Q[n-15+k]
           
  Karatsuba terms:
    M1[k] = (I_sum[k] - Q_sum[k]) * H_i[k]  -- DSP A
    M2[k] = I_sum[k] * (H_r[k] - H_i[k])    -- DSP B
    M3[k] = Q_sum[k] * (H_r[k] + H_i[k])    -- DSP C

  Partial results:
    Out_I_partial[k] = M1[k] + M2[k]
    Out_Q_partial[k] = M1[k] + M3[k]

Accumulation tree (binary):
  Sum_I = sum(Out_I_partial[0..7])  -- 3-level adder tree using PCOUT cascade
  Sum_Q = sum(Out_Q_partial[0..7])
```

**Timing:**

With full DSP pipeline registers (AREG=1, MREG=1, PREG=1): 3-cycle multiply latency per DSP. Accumulation tree via PCOUT cascade adds 1 cycle per cascade level. Total pipeline latency: approximately 3 + 3 = 6 cycles. Throughput: one new complex output per clock cycle.

---

### Q9. What is the "pattern detector" feature of the DSP48E2, and describe a design that uses it?

**Answer:**

The DSP48E2 includes a 48-bit pattern detector: a combinational comparator that checks whether the P accumulator output matches a configurable 48-bit pattern (with an optional "don't care" mask for some bits). The result drives two output flags:

- **PATTERNDETECT:** asserted when P matches the pattern in the same cycle
- **PATTERNBDETECT:** asserted when P matches the bitwise complement of the pattern

Both outputs are registered by PREG and can optionally feed back into the DSP's CARRYIN input via the `CARRYCASCIN` path, enabling single-DSP saturating accumulators without external logic.

**Key configuration attributes:**

```
PATTERN       => 48'hFFFFFFFF0000,  -- 48-bit comparison pattern
MASK          => 48'h000000000000,  -- 0 = compare this bit, 1 = don't care
SEL_MASK      => "MASK",           -- use static MASK attribute
SEL_PATTERN   => "PATTERN",        -- use static PATTERN attribute
USE_PATTERN_DETECT => "PATDET"     -- enable the detector
```

**Design example — 16-bit saturating accumulator:**

A common DSP requirement is an accumulator that clamps to maximum or minimum value on overflow rather than wrapping.

For a signed 16-bit output: maximum = `16'h7FFF`, minimum = `16'h8000`.

Configure two DSP48E2s or one DSP with the pattern detector:

```
PATTERN = 48'h000000007FFF  -- detect when accumulator hits +32767
MASK    = 48'hFFFFFFFF0000  -- only check the lower 16 bits
```

When PATTERNDETECT is asserted (P = 0x7FFF in the lower 16 bits), the logic forces the accumulator to hold at 0x7FFF rather than incrementing further. The PATTERNBDETECT simultaneously detects the negative saturation condition (P = 0x8000).

**Cascade feedback path for auto-saturation:**

The PATTERNDETECT output can be fed back (via CARRYCASCIN or external logic) to the OPMODE/ALUMODE control, switching the accumulator from `P + M` to `hold at P` when saturation is detected — all within the same DSP, requiring no external LUT logic for the saturation decision.

**Other pattern detector applications:**

- **Terminal count detection:** Set the pattern to the target count value. PATTERNDETECT generates the load or reset signal for a programmable counter directly from the DSP.
- **Zero detection:** Pattern = 48'h0 detects when the accumulator reaches zero, triggering a reset or interrupt.
- **Convergent rounding:** The pattern detector can detect the rounding halfway case ($P[n-1:0] = 2^{n-1}$) for round-half-to-even without external comparison logic.

---

## Quick Reference: Key Terms

| Term | Definition |
|---|---|
| DSP48E2 | Xilinx UltraScale/UltraScale+ hardened DSP primitive: 27×18 mult + 48-bit post-adder |
| Pre-adder | D±A adder before the multiplier; halves DSP count for symmetric FIR filters |
| MREG | Multiplier output pipeline register; most important DSP timing register |
| PREG | Post-adder/accumulator output register |
| OPMODE | 9-bit control word selecting source operands for each DSP arithmetic stage |
| ALUMODE | 4-bit control word selecting add/subtract/logic operation in post-adder |
| PCOUT/PCIN | 48-bit dedicated cascade connection between adjacent DSPs in a column |
| ACOUT/BCIN | A/B cascade connections for propagating input operands down a DSP column |
| Pattern detector | 48-bit comparator on P output for saturation, terminal count, and rounding |
| Accumulator | MAC mode where P feeds back to the post-adder Z input (OPMODE Z\_MUX = 010) |
| Symmetric FIR | FIR filter with h[k]=h[N-1-k]; exploits pre-adder to halve DSP count |
| Karatsuba | Algorithm reducing complex multiply from 4 to 3 real multiplications |
| PATTERNDETECT | Output flag from pattern detector; high when P matches configured pattern |
