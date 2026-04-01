# Clock Resources and PLLs

## Overview

Clock distribution is one of the most critical aspects of FPGA design. Unlike ASICs where the clock network is custom routed, FPGAs provide a structured hierarchy of dedicated clock routing resources — global buffers, regional buffers, I/O-specific buffers, phase-locked loops (PLLs), and Mixed-Mode Clock Managers (MMCMs). Understanding this hierarchy determines whether a design meets its clock requirements, how many independent clock domains can be supported, and whether the clock network will introduce harmful skew or jitter.

This document focuses on Xilinx UltraScale/UltraScale+ clock architecture. Intel equivalents (PLLs, fractional PLLs, GCLK networks in Stratix/Agilex) are noted where significant.

---

## Tier 1: Fundamentals

### Q1. What is a clock buffer (BUFG) and why is it required for most FPGA clock signals?

**Answer:**

A BUFG (Global Buffer) is a dedicated clock driving element that connects a clock source (PLL output, input pad, or internal logic) to the global clock network — a set of low-skew, high-fanout metal routes that span the entire device.

**Why it is required:**

FPGA logic cells (LUT flip-flops) have a dedicated clock input pin connected directly to the clock routing network. This clock input is not connected to the general routing fabric. A signal driving a large number of flip-flop clock inputs through the general routing fabric would:

1. **Incur massive fanout delay:** A general route driving 10,000+ FF clock inputs would have enormous capacitance, causing 2–5 ns of clock delay and significant clock-to-clock skew across the device.

2. **Violate timing constraints:** Synthesis tools model clocks as ideal (zero-skew) unless driven through a BUFG onto the dedicated clock network. A clock signal on the general fabric does not benefit from clock network timing models, leading to inaccurate — and usually violating — timing analysis.

3. **Cause excessive power consumption:** Clock routing is optimised for low-impedance, so the dedicated network drives large capacitive loads efficiently. General routing is not.

**BUFG function:** The BUFG has one input and one output. It amplifies the clock signal and places it onto the global clock network. The global network is balanced: every leaf flip-flop in the device receives the clock with approximately equal delay (low skew, typically <50 ps across the device).

**Inference:** Synthesis tools automatically insert BUFGs for signals inferred as clocks (driving >100 FF clock pins). Explicit instantiation is needed for clock gating or when combining a BUFG with a MMCM/PLL output.

**UltraScale BUFG count:** UltraScale devices provide 544 BUFGs, organised as sets of 24 BUFGs per clock region. In practice, a design rarely uses more than 20–30 global clock networks simultaneously.

---

### Q2. What is an MMCM and how does it differ from a PLL? Describe the typical use cases for each.

**Answer:**

Both MMCM (Mixed-Mode Clock Manager) and PLL (Phase-Locked Loop) are on-chip clock conditioning circuits that lock to an input clock reference and generate one or more output clocks with programmable frequency, phase, and duty cycle.

**PLL (Phase-Locked Loop):**

A PLL uses a voltage-controlled oscillator (VCO), phase detector, and loop filter to lock the VCO frequency to a multiple of the input reference. In UltraScale, PLL output clocks are limited to:

- 6 output clocks (CLKOUT0–CLKOUT5)
- Output frequency derived by integer M (multiply) and D (divide) factors:

$$f_{out} = f_{in} \times \frac{M}{D}$$

- Phase offset: discrete steps of 45° increments (coarse), not continuous
- Jitter: lower than MMCM for basic frequency synthesis (no fractional component)

**MMCM (Mixed-Mode Clock Manager):**

MMCM is a superset of PLL functionality. Key additional capabilities:

| Feature | PLL | MMCM |
|---|---|---|
| Output clocks | 6 | 7 (CLKOUT0–CLKOUT6, plus CLKFBOUT) |
| Fractional divide | No | Yes (CLKOUT0 supports fractional D) |
| Phase offset | 45° steps | Continuous (1/8 VCO period resolution) |
| Dynamic reconfig | No | Yes (DRP port) |
| Spread-spectrum | No | Yes |
| Cascading | Not directly | Yes (MMCM output can feed another MMCM) |
| Jitter | Lower | Slightly higher (fractional modes) |

**The VCO frequency constraint:**

Both PLL and MMCM have a VCO operating range. For UltraScale+ (–1 speed grade), the MMCM VCO must operate between 600 MHz and 1600 MHz:

$$f_{VCO} = f_{in} \times \frac{M}{D_{in}}, \quad 600 \le f_{VCO} \le 1600 \text{ MHz}$$

This constraint drives the choice of M and D: M must be large enough to push the VCO above 600 MHz even with a low input frequency.

**Use case guidance:**

- **Use PLL when:** Simple integer frequency synthesis, lowest jitter requirement, no phase alignment or dynamic reconfiguration needed.
- **Use MMCM when:** Non-integer frequency ratios (fractional divider), fine-grained phase alignment between clocks, spread-spectrum for EMI reduction, or dynamic reconfiguration via DRP.

**Intel equivalent:** Intel Stratix/Agilex devices use Fractional PLLs (fPLLs) which combine PLL and MMCM-equivalent functions in a single primitive.

---

### Q3. Describe the clock region hierarchy in a UltraScale device. What limits how many distinct clocks can be used?

**Answer:**

UltraScale devices organise the fabric into **clock regions** — rectangular areas of approximately 60 CLB columns × 60 CLB rows. A mid-range UltraScale device (e.g., KU040) may have 12 clock regions arranged in a 3×4 grid.

**Clock distribution hierarchy:**

```
MMCM/PLL output
       |
   BUFGCE / BUFG (global buffer, spans entire device)
       |
   Global clock network (H-tree or spine)
       |
   Clock region distribution network (regional BUFR or BUFG distribution)
       |
   Leaf clock lines → FF clock pins in each Slice
```

**Per-region clock limit:**

Each clock region can use a maximum of **12 distinct clock networks** simultaneously. This is the critical constraint for multi-clock designs.

The 12-clock limit per region comes from the number of horizontal clock distribution lines available in each region's routing infrastructure. When a design uses more than 12 clocks in a single region, the placer must either:
- Overlap clock domains (not always possible)
- Spread logic across regions to reduce per-region clock count
- Fail to route (DRC error: `CLOCK-10`)

**Global vs regional clocks:**

- **Global (BUFG):** Drives all clock regions simultaneously. Each BUFG consumes one clock slot in every clock region it passes through — even in regions where no logic uses that clock. This is wasteful when a clock is only needed in one or two regions.

- **Regional (BUFR):** Drives only the clock region in which it is instantiated plus its adjacent regions. Does not consume clock slots in unrelated regions. Used for clocks needed only in a localised area.

- **I/O-specific (BUFIO):** Drives only the I/O column adjacent to the BUFIO's clock region. Used for source-synchronous interface clocks (e.g., DDR IOSERDES). BUFIO cannot drive logic Slices — only IOSERDES and I/O primitives.

**Practical implication:**

A design with 15 distinct clock domains will violate the 12-per-region limit unless the logic for each clock is carefully placed in separate regions. Floorplanning (Pblocks per clock domain) is required when approaching this limit. The DRC check `report_clock_interaction` identifies potential problems before routing.

---

### Q4. What is clock enable (CE) gating, and how does it differ from using a BUFGCE to gate a clock?

**Answer:**

Clock gating reduces dynamic power by preventing the clock from toggling flip-flops that are not performing useful work. There are two mechanisms:

**Clock enable (CE) on individual flip-flops:**

Every flip-flop in an FPGA has a clock-enable (CE) input. When CE is de-asserted, the flip-flop's output is held constant despite the clock continuing to toggle. The flip-flop still receives the clock edge — the CE prevents the D input from being captured.

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if ce = '1' then
      q <= d;
    end if;
  end if;
end process;
```

This infers the FF with CE connected. The clock network still switches; power saving comes only from the flip-flop's D-Q switching activity being suppressed, not from stopping the clock.

**BUFGCE — gated global clock buffer:**

BUFGCE is a BUFG with an enable input. When CE is de-asserted, the BUFGCE stops driving its output, freezing the clock for all downstream flip-flops at once. The clock network itself stops switching.

**Power comparison:**

Clock network switching contributes significantly to FPGA dynamic power because the network has high capacitance (it drives millions of FF clock pins). Gating the clock at BUFGCE eliminates this switching:

$$P_{dynamic} = \alpha \cdot C \cdot V^2 \cdot f$$

where $\alpha$ is activity factor. BUFGCE gating sets $\alpha = 0$ for all FF clock inputs and the routing network in the affected domain — a much larger power saving than individual CE gating.

**When to use BUFGCE vs CE:**

| Scenario | Recommendation |
|---|---|
| Large block idle for many cycles (e.g., DSP not processing) | BUFGCE — eliminates clock network power |
| Individual FF or small group of FFs | CE on FF — simpler, no clock network impact |
| Low-power mode for an entire clock domain | BUFGCE |
| Fine-grained per-register enable | FF CE |

**Hazard of BUFGCE:** The enable transition must be glitch-free and synchronous to the clock it is gating, or it can cause metastability on the downstream flip-flops. The CE input should be synchronised to the gated clock domain before driving BUFGCE. In practice, BUFGCE is safe when CE changes are synchronous and stable for at least one full clock period before and after the enable edge.

---

## Tier 2: Intermediate

### Q5. How does an MMCM achieve fine phase alignment between two output clocks? Why is this needed for DDR memory interfaces?

**Answer:**

**Phase offset mechanism in MMCM:**

The MMCM VCO runs at $f_{VCO}$ (600–1600 MHz in UltraScale+). The VCO produces 8 phase-shifted versions of its output, spaced $\frac{1}{8} T_{VCO}$ apart (i.e., 45° steps at the VCO frequency). Each output clock (CLKOUT0–CLKOUT6) can select one of these 8 phase taps, then apply an additional fine phase offset via the `PHASE_MUXF` parameter in units of $\frac{1}{56}$ of the VCO period.

The total phase offset of output $k$ relative to the reference:

$$\phi_k = \frac{M_k}{8} \times T_{VCO} + \text{PHASE offset in degrees}$$

**Continuous phase adjustment:**

MMCM `PHASE_SHIFT` attribute allows setting phase offset in degrees (0.0° to 360.0°) per output clock. Vivado converts this to the nearest discrete step, with resolution of approximately $\frac{360°}{8 \times 56} \approx 0.8°$ at 800 MHz VCO.

**Dynamic phase shift via DRP:**

The MMCM Dynamic Reconfiguration Port (DRP) allows the phase offset to be adjusted at runtime by writing to internal registers. This enables run-time training of interface phase alignment — exactly what DDR calibration algorithms require.

**DDR memory interface requirement:**

In a DDR3/DDR4 interface, data arrives on DQS (data strobe) edges. The FPGA must capture data using a clock that is phase-aligned to the centre of the data eye — the point of maximum noise margin. This centre varies between boards, temperatures, and process corners.

The IOSERDES calibration sequence:
1. Send a training pattern from the DDR device
2. Scan the DRP-controlled MMCM phase offset across 360°
3. Find the phase window where data captures correctly (the eye opening)
4. Set the MMCM phase to the centre of that window

Without MMCM fine phase alignment, this calibration would require external phase interpolators or acceptance of worst-case timing margins.

**BUFIO for DDR clocks:**

The DQS strobe must be routed from the pad to the IOSERDES clock input with minimum, predictable delay. BUFIO is used here: it connects the DQS pad directly to the IOSERDES clock input via the I/O clock network, bypassing the general routing fabric. BUFIO cannot drive Slice FFs — only IOSERDES. A separate BUFG distributes the MMCM-generated fabric clock to the rest of the design.

---

### Q6. What is clock domain crossing (CDC) and what makes it dangerous from a clocking resource perspective? How does proper MMCM phase relationship help?

**Answer:**

A clock domain crossing (CDC) occurs when a signal registered in clock domain A drives a register in clock domain B, where A and B are generated by independent sources (or have no guaranteed phase relationship). The hazard is **metastability**: the destination register samples the input during its setup/hold window, spending an indeterminate time in a metastable state before resolving to 0 or 1. If the metastable state persists past the downstream logic's setup time, a logic failure results.

**Synchronous CDC (same PLL/MMCM source):**

If both clocks are derived from the same MMCM output (e.g., CLKOUT0 at 100 MHz and CLKOUT1 at 200 MHz), their phase relationship is fixed and known. Vivado can characterise the timing relationship. A 2:1 frequency relationship with a known phase offset can be made timing-safe without a synchroniser FIFO — just with proper phase alignment ensuring hold time is met.

**Asynchronous CDC (independent sources):**

When two clocks come from separate MMCMs or external oscillators, no phase relationship exists. Vivado treats these as "asynchronous" clocks. Any combinational path between them is a CDC violation. Solutions:
- 2-flop synchroniser for single-bit signals
- Async FIFO (handshake or Gray-coded pointer) for multi-bit data
- Pulse synchroniser for control signals

**MMCM output clock skew:**

Within one MMCM, all output clocks are phase-controlled relative to the same VCO. The MMCM guarantees that the phase relationship between CLKOUT0 and CLKOUT1 is the value programmed in the PHASE attributes. This makes intra-MMCM CDC deterministic.

**Clocking constraint for CDC:**

In XDC, CDCs between clocks that share an MMCM are handled automatically. CDCs between truly independent clocks must be explicitly declared:

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks clk_sys] \
  -group [get_clocks clk_eth]
```

This tells the timing analyser to ignore paths between these groups (because they are handled by synchronisers), preventing false timing violations.

---

### Q7. A design requires five output clocks: 250 MHz, 125 MHz, 62.5 MHz, 100 MHz, and 25 MHz, all from a 200 MHz reference. Show how to configure an MMCM to generate all five.

**Answer:**

**Step 1 — Find a common VCO frequency:**

The VCO must be in the range 600–1600 MHz (UltraScale+ –1 speed grade). We need all output dividers to be integers.

Desired outputs: 250, 125, 62.5, 100, 25 MHz.

The MMCM output frequency for each clock is:

$$f_{out,k} = \frac{f_{VCO}}{O_k}$$

where $O_k$ is the output divider (1–128, or fractional for CLKOUT0).

Try $f_{VCO} = 1000$ MHz (achievable with $M=5$, $D_{in}=1$ from 200 MHz reference: $200 \times 5 = 1000$).

| Output | Target | Divider $O_k = f_{VCO}/f_{out}$ | Integer? |
|---|---|---|---|
| CLKOUT0 | 250 MHz | 1000/250 = **4** | Yes |
| CLKOUT1 | 125 MHz | 1000/125 = **8** | Yes |
| CLKOUT2 | 62.5 MHz | 1000/62.5 = **16** | Yes |
| CLKOUT3 | 100 MHz | 1000/100 = **10** | Yes |
| CLKOUT4 | 25 MHz | 1000/25 = **40** | Yes |

All five outputs are achievable with integer dividers from $f_{VCO} = 1000$ MHz.

**Step 2 — Verify VCO is in range:**

$600 \le 1000 \le 1600$ MHz — within the valid range.

**Step 3 — XDC/attribute configuration:**

```vhdl
MMCME4_ADV generic map (
  CLKIN1_PERIOD   => 5.0,        -- 200 MHz input (5 ns period)
  CLKFBOUT_MULT_F => 5.0,        -- M = 5, VCO = 200*5 = 1000 MHz
  DIVCLK_DIVIDE   => 1,          -- D_in = 1
  CLKOUT0_DIVIDE_F => 4.0,       -- 1000/4 = 250 MHz
  CLKOUT1_DIVIDE  => 8,          -- 1000/8 = 125 MHz
  CLKOUT2_DIVIDE  => 16,         -- 1000/16 = 62.5 MHz
  CLKOUT3_DIVIDE  => 10,         -- 1000/10 = 100 MHz
  CLKOUT4_DIVIDE  => 40,         -- 1000/40 = 25 MHz
  -- Phase shifts (0 degrees, no offset needed)
  CLKOUT0_PHASE   => 0.0,
  CLKOUT1_PHASE   => 0.0,
  CLKOUT2_PHASE   => 0.0,
  CLKOUT3_PHASE   => 0.0,
  CLKOUT4_PHASE   => 0.0,
  -- Duty cycle (50% default)
  CLKOUT0_DUTY_CYCLE => 0.5,
  CLKOUT1_DUTY_CYCLE => 0.5,
  BANDWIDTH       => "OPTIMIZED" -- or "HIGH", "LOW"
)
```

**Step 4 — Verify MMCM output count:**

Five outputs (CLKOUT0–CLKOUT4) — well within the MMCM's 7-output limit.

**Step 5 — Clock routing:**

Each MMCM output must be connected to a BUFG before driving the design's flip-flops:

```vhdl
BUFG_250: BUFG port map (I => mmcm_clk0, O => clk_250);
BUFG_125: BUFG port map (I => mmcm_clk1, O => clk_125);
-- etc.
```

All five BUFGs consume 5 of the 12 available clock slots per clock region. This leaves 7 slots for other clocks, which is adequate for most designs.

---

## Tier 3: Advanced

### Q8. Describe the MMCM jitter budget for a high-speed SerDes application. What are the sources of jitter, and how do you minimise each?

**Answer:**

Jitter is the deviation of clock edge timing from its ideal position. In SerDes applications, excessive jitter directly reduces the eye opening and increases bit-error rate. The MMCM jitter budget must be understood at the system level.

**Sources of jitter in an MMCM-based clock system:**

**1. Input reference jitter ($J_{in}$):**

The MMCM tracks its input. Reference jitter above the MMCM bandwidth (typically 100–200 kHz for "OPTIMIZED" bandwidth setting) passes through to the output. Jitter below the MMCM bandwidth is filtered by the PLL loop. A high-quality reference oscillator with <150 fs RMS jitter is required for high-speed SerDes.

**2. MMCM intrinsic jitter ($J_{mmcm}$):**

The MMCM's internal VCO and charge pump introduce jitter. For UltraScale+ MMCM in "HIGH" bandwidth mode, intrinsic RMS jitter is typically 50–80 ps.

**3. Frequency multiplication factor ($M$):**

Phase noise scales with frequency ratio. If the MMCM multiplies by $M$:

$$J_{out,rms} \approx \sqrt{(M \cdot J_{in})^2 + J_{mmcm}^2}$$

A large $M$ amplifies reference jitter. Keep $M$ as small as practical while remaining within the VCO range.

**4. Clock network jitter ($J_{net}$):**

The BUFG and global clock distribution network add deterministic skew (balanced) but also a small additional jitter component from supply and substrate coupling. This is typically 20–30 ps peak-to-peak.

**5. Power supply noise ($J_{PSN}$):**

Voltage noise on VCCINT causes VCO frequency variation, appearing as jitter. Decoupling capacitors, stable power delivery, and separating MMCM supply (VCCAUX) from digital switching supply are all important.

**Total jitter budget:**

$$J_{total} = \sqrt{J_{in,filtered}^2 + J_{mmcm}^2 + J_{net}^2 + J_{PSN}^2}$$

For a 10 Gbps SerDes link with a 100 ps eye, the total RMS clock jitter must remain below approximately 20–25 ps RMS to meet the bit-error-rate specification.

**Mitigation strategies:**

| Source | Mitigation |
|---|---|
| Input reference jitter | Use a low-noise TCXO/OCXO; minimise PCB trace impedance discontinuities |
| MMCM bandwidth | Set `BANDWIDTH = "LOW"` to filter more input jitter (at cost of lock time) |
| Multiplication factor | Choose $M$ minimally: prefer M=2 over M=8 for same $f_{VCO}$ if possible |
| Power supply noise | MMCM on dedicated VCCAUX with independent filtering; VCCAUX decoupling |
| Clock network | Use BUFG (not fabric routing) for all clock distribution |

**Jitter reporting in Vivado:**

`report_clock_interaction` and the MMCM IP core's "Summary" tab report the estimated output jitter (in ns, peak-to-peak and RMS) for each output clock based on the configured M, D, and bandwidth settings. Always verify the reported jitter is within the SerDes reference clock specification.

---

### Q9. Your design has 14 independent clock domains. UltraScale supports 12 clocks per region. What techniques can you use to fit the design without DRC violations?

**Answer:**

With 14 clock domains and a 12-per-region limit, at least 3 regions will have ≥ 2 "extra" clocks relative to the limit. The approaches fall into four categories:

**Approach 1 — Regional isolation via Pblocks:**

Assign the logic of each clock domain to a Pblock. Design clock domains so that no more than 12 are ever co-located in the same clock region. If domain A only has logic in regions R1 and R2, and domain B only has logic in regions R3 and R4, they do not compete for the same regional clock slots.

This requires analysing which domains co-exist spatially. Vivado's `report_clock_utilization` shows per-region clock consumption after placement. Use `set_property CONTAIN_ROUTING true [get_pblocks ...]` to prevent routes from crossing regions and mixing clock domains.

**Approach 2 — BUFR instead of BUFG for localised clocks:**

BUFG drives the global clock network (all regions). If a clock domain's logic is confined to one or two regions, using BUFR instead of BUFG means it only consumes a clock slot in those specific regions, not globally.

- Replace `BUFG` with `BUFR` for clocks used in ≤ 2 contiguous regions
- `BUFR` has a `BUFR_DIVIDE` attribute (1–8) that can also halve or quarter a regional clock — potentially eliminating a separate MMCM output

**Approach 3 — Clock domain merging:**

Review whether all 14 domains are truly independent. Common consolidation opportunities:
- Domains at the same frequency from the same MMCM that are treated as separate for functional reasons can be re-architectured to share one clock with enable-based gating
- Slow-moving control domains (< 10 MHz) that consume an entire BUFG slot can be replaced with a divided BUFR from a faster domain using BUFR_DIVIDE

**Approach 4 — Time-multiplexed clock sharing:**

If two clock domains operate at the same frequency but are used alternately (e.g., two processing blocks that never operate simultaneously), they can share one BUFG. A BUFGMUX (multiplexed BUFG) switches between two clock inputs. The switch must be glitch-free and is typically performed only when both sources are in known states. Only one BUFG slot is consumed.

**Practical sequence:**

1. Run `report_clock_utilization -verbose` after placement
2. Identify which regions exceed 12 clocks (highlighted in red in the report)
3. Apply Pblocks to separate domains spatially (Approach 1) — lowest risk change
4. If Pblocks alone are insufficient, convert non-critical BUFGs to BUFRs (Approach 2)
5. If still over limit, evaluate domain merging (Approach 3)

**Avoiding the problem upfront:**

During architecture definition, document the clock region budget alongside the resource budget. At ≥ 10 independent clock domains, plan the floorplan before writing RTL — retrofitting is significantly harder.

---

## Quick Reference: Key Terms

| Term | Definition |
|---|---|
| BUFG | Global clock buffer; drives the full-device low-skew clock network |
| BUFGCE | BUFG with clock-enable input; gates the entire clock to save power |
| BUFR | Regional clock buffer; drives only its local clock region(s); supports divide |
| BUFIO | I/O clock buffer; drives IOSERDES only, not fabric FFs |
| BUFGMUX | Glitch-free multiplexed BUFG; selects between two clock sources |
| MMCM | Mixed-Mode Clock Manager; frequency synthesis, phase alignment, fractional divide |
| PLL | Phase-Locked Loop; simpler than MMCM, lower jitter, integer divides only |
| VCO | Voltage-Controlled Oscillator; internal MMCM/PLL element; must stay in 600–1600 MHz range |
| Clock region | Rectangular FPGA sub-region; maximum 12 clock networks simultaneously |
| M, D parameters | MMCM multiply (M) and divide (D) to set VCO frequency: $f_{VCO} = f_{in} \times M / D$ |
| DRP | Dynamic Reconfiguration Port; allows run-time changes to MMCM configuration |
| CDC | Clock Domain Crossing; signal transferred between asynchronous clock domains |
| Phase offset | Configurable delay applied to one MMCM output relative to others |
| Jitter | Clock edge timing deviation; limits SerDes and high-speed interface performance |
| CLKFBOUT | MMCM feedback output; must be routed back to CLKFBIN for PLL lock |
