# I/O Standards and SerDes

## Overview

FPGA I/O resources bridge the internal logic fabric and the outside world. They are constrained by physical laws — voltage levels, transmission line impedance, and signal integrity — in ways that logic resources are not. A poorly considered I/O assignment can violate electrical specifications, cause board failures, or produce unexplained data corruption even when the RTL and timing are correct. High-speed serial transceivers (SerDes — Serialiser/Deserialiser) are specialised hardened I/O blocks that implement multi-gigabit point-to-point links using sophisticated equalization and clock-data recovery circuits.

This document covers UltraScale/UltraScale+ I/O banking, voltage standards, SelectIO (LVDS/SSTL/HSTL), and GTH/GTY transceivers.

---

## Tier 1: Fundamentals

### Q1. What is an I/O bank and what constraints does it impose on voltage standards?

**Answer:**

An I/O bank is a group of I/O pins that share a common supply voltage rail (VCCO) for their output drivers. In UltraScale/UltraScale+ devices, each bank contains 26 single-ended pins (or 13 differential pairs), all powered by the same VCCO pin.

**The fundamental rule:** All I/O pins within the same bank must use the same VCCO voltage. Mixing voltage standards requiring different VCCO values in the same bank is not permitted and causes a DRC error (`BIBC-2` in Vivado).

**Why this rule exists:**

The output driver circuit for each I/O pin consists of pull-up transistors connected to VCCO and pull-down transistors connected to GND. The output voltage swing is determined by VCCO:

- VCCO = 3.3 V → output swings 0 V to 3.3 V (LVCMOS33)
- VCCO = 2.5 V → output swings 0 V to 2.5 V (LVCMOS25)
- VCCO = 1.8 V → used for HSTL Class I, LVCMOS18
- VCCO = 1.5 V → used for SSTL15, HSTL15
- VCCO = 1.35 V → used for SSTL135 (DDR3L)
- VCCO = 1.2 V → used for SSTL12, POD12 (DDR4)

Since all pins in a bank share VCCO, all standards in that bank must be compatible with that one supply voltage.

**Bank types in UltraScale:**

| Bank type | Location | Purpose | Special features |
|---|---|---|---|
| HR (High Range) | Periphery | General purpose, 1.2–3.3 V | Widest voltage range |
| HP (High Performance) | Periphery | High-speed interfaces, 1.0–1.8 V | Lower noise, faster slew |
| HD (High Density) | Available in some devices | High pin count at lower performance | — |

**HP vs HR restriction:** HP banks support only 1.0–1.8 V VCCO. If a 3.3 V interface (LVCMOS33) is required, it must go to an HR bank. DDR4 (POD12 at VCCO=1.2 V) must go to HP banks for best signal integrity.

---

### Q2. What is LVDS (Low Voltage Differential Signalling)? Describe how it works and why it is preferred over single-ended signalling at high frequencies.

**Answer:**

LVDS is a differential signalling standard in which data is transmitted as the voltage difference between two conductors (the positive rail P and the negative rail N), rather than as a voltage on a single wire referenced to ground.

**Electrical definition:**

- Logic 1: $V_P - V_N > +100$ mV (typically $V_P = 1.55$ V, $V_N = 1.25$ V → differential swing of +300 mV)
- Logic 0: $V_P - V_N < -100$ mV (typically $V_P = 1.25$ V, $V_N = 1.55$ V → differential swing of -300 mV)
- Common-mode voltage: $V_{CM} = 1.2$ V (centre of swing, set by driver)

The receiver responds only to the differential voltage, ignoring the common-mode level entirely.

**Why differential is preferred at high frequencies:**

**1. Noise immunity through common-mode rejection:**

Any noise that couples equally onto both P and N conductors (ground noise, power supply ripple, electromagnetic interference) appears as a common-mode shift — the same voltage on both lines. The differential receiver subtracts $V_P - V_N$, which cancels the common-mode component exactly:

$$(V_P + V_{noise}) - (V_N + V_{noise}) = V_P - V_N$$

This is why LVDS links are robust in noisy environments.

**2. Reduced voltage swing:**

LVDS uses a 300 mV differential swing vs. 3.3 V or 2.5 V for LVCMOS. Charging and discharging the line capacitance to a smaller voltage range means:

$$E = \frac{1}{2} C V^2 \quad \Rightarrow \quad P = C V^2 f$$

A 10× voltage reduction gives a 100× reduction in switching energy. This enables high-speed operation at lower power.

**3. Reduced electromagnetic emission:**

The P and N conductors carry equal and opposite currents. Their magnetic fields cancel in the far field, dramatically reducing EMI — important for designs that must pass radiated emissions testing.

**LVDS in UltraScale:**

- Available on HR and HP banks
- Maximum data rate: up to 1.25 Gbps single-data-rate (using IOSERDES for higher rates)
- VCCO: must be 2.5 V for LVDS output drivers in HR banks (HP banks use internal biasing)
- Termination: 100 Ω differential termination at the receiver is required; available as an internal on-chip termination (OCT) via the DIFF_TERM attribute

---

### Q3. What is SSTL and HSTL? Why are they used for memory interfaces?

**Answer:**

SSTL (Stub Series Terminated Logic) and HSTL (High-Speed Transceiver Logic) are memory bus standards optimised for single-ended signalling on terminated transmission lines at moderate speeds (DDR memory speeds of 0.5–2.4 Gbps per signal).

**SSTL:**

SSTL uses a reference voltage $V_{REF} = V_{CCO}/2$ as the receiver's input threshold. The driver output swings around this reference with a defined AC and DC voltage margin.

| Standard | VCCO | VREF | Typical use |
|---|---|---|---|
| SSTL15 | 1.5 V | 0.75 V | DDR3 |
| SSTL135 | 1.35 V | 0.675 V | DDR3L (low power) |
| SSTL12 | 1.2 V | 0.6 V | DDR4 (older) |
| POD12 | 1.2 V | — | DDR4 (pseudo-open-drain, newer) |

**HSTL:**

HSTL is similar to SSTL but designed for SRAM interfaces (QDR SRAM, RLDRAM). HSTL Class I is the most common:

| Standard | VCCO | VREF | Typical use |
|---|---|---|---|
| HSTL_I | 1.5 V | 0.75 V | QDR SRAM, synchronous SRAMs |
| HSTL_I_18 | 1.8 V | 0.9 V | Older SRAM interfaces |

**Why dedicated standards (not LVCMOS) for memory:**

1. **Termination topology:** DDR and SRAM buses use stub-terminated transmission lines. SSTL/HSTL define specific AC and DC driver characteristics matched to the termination network, ensuring signal integrity at high speeds.

2. **VREF-based threshold:** Single-ended signalling at 1.5 V with a 0.75 V threshold provides better noise margin than a logic-threshold receiver at low supply voltages.

3. **Slew rate control:** SSTL/HSTL drivers have defined output impedance and slew rate matched to the memory bus impedance (usually 40–50 Ω effective impedance after parallel and series termination).

**POD12 (DDR4):**

DDR4 introduced POD12 — Pseudo-Open Drain at 1.2 V. The driver pulls low aggressively but the high level is achieved via board-side termination to $V_{DDQ}$. This reduces simultaneous switching noise and power consumption. POD12 requires HP banks (not HR) on UltraScale+ to ensure sufficient drive strength and receiver sensitivity at 1.2 V.

---

### Q4. What is SERDES and what does it do at the I/O level? How does the IOSERDES differ from a GTH transceiver?

**Answer:**

SerDes (Serialiser/Deserialiser) is a circuit that converts between parallel and serial data streams:

- **Serialiser:** takes $N$ parallel bits at $f_{clk}$ and outputs them serially at $N \times f_{clk}$
- **Deserialiser:** takes a serial stream at $N \times f_{clk}$ and outputs $N$ parallel bits at $f_{clk}$

This allows a high-bandwidth serial interface to be processed by lower-speed parallel logic inside the FPGA.

**IOSERDES (ISERDESE3/OSERDESE3 in UltraScale+):**

IOSERDES is a serialisation/deserialisation block integrated directly into the FPGA I/O cell, adjacent to the SelectIO (LVDS/HSTL) pad drivers.

| Feature | IOSERDES |
|---|---|
| Maximum data rate | ~1.6 Gbps per pin |
| Serialisation factors | 2, 4, 6, 8, 10 (ISERDESE3) |
| Clock source | BUFIO or BUFR (I/O clock network) |
| Applications | DDR SDRAM, source-synchronous LVDS camera links, HDMI |
| Reference clock | Derived from incoming data strobe (DQS) for DDR |

**GTH/GTY Transceivers:**

GTH (GigaBit Transceiver H) and GTY (GigaBit Transceiver Y) are fully hardened multi-gigabit serial transceiver blocks, located in dedicated columns separate from the general I/O banks. They implement entire protocol physical layers in hardware.

| Feature | GTH | GTY |
|---|---|---|
| Maximum line rate | 16.375 Gbps | 32.75 Gbps |
| Protocols supported | PCIe, 10/25GbE, SATA, SFP+, ... | PCIe Gen4, 100GbE, ... |
| Equalisation | CTLE + DFE | CTLE + DFE (higher order) |
| Loopback modes | Near-end PCS, near-end PMA, far-end PMA | Same |
| Clock recovery | CDR (Clock-Data Recovery) — internal | Same |
| Reference clock | Dedicated REFCLK pins adjacent to quads | Same |

**Key distinction:**

IOSERDES works with the standard I/O pad infrastructure (LVDS, HSTL) and uses an externally provided clock. It handles speeds up to ~1.6 Gbps per pin, which is sufficient for DDR4-3200 (1.6 GT/s per pin, 2 bits per cycle).

GTH/GTY have their own dedicated pad pairs (AC-coupled), on-chip CDR (the receiver recovers the clock from the incoming data stream — no separate clock needed), integrated PLL (QPLL/CPLL), and programmable equalisers to compensate for PCB loss. They operate from 0.5 Gbps to 32 Gbps and implement protocols like PCIe, Ethernet, and CPRI that would be impossible with IOSERDES.

---

## Tier 2: Intermediate

### Q5. Explain the GTH transceiver architecture. What are the QPLL and CPLL and when do you use each?

**Answer:**

A GTH transceiver in UltraScale consists of a **quad** — four transceiver channels sharing common PLL and reference clock resources — plus a common block (GTHE3_COMMON) per quad.

**GTH channel internal blocks:**

```
Reference clock (REFCLK)
        |
   [QPLL or CPLL]   <-- Frequency synthesis
        |
   TX path:                    RX path:
   TX data (32 bits)           RX data (32 bits)
        |                           ^
   [TX buffer + gearbox]      [RX buffer + gearbox]
        |                           |
   [TX PCS: 8b10b/64b66b]    [RX PCS: 8b10b/64b66b]
        |                           |
   [TX PMA: TX serialiser]   [RX PMA: CDR + equalisers]
        |                           |
   TX pad (P/N)               RX pad (P/N)
```

**QPLL (Quad PLL):**

The QPLL is shared among all four channels in a quad. It operates at a higher frequency (the line rate divided by 2 or 4) and produces a VCO output in the range 9.8–16.375 Gbps / 2 (4.9–8.2 GHz VCO range for QPLL1 in GTH).

- One QPLL can clock all four channels simultaneously at the same line rate
- Ideal when all four channels use the same protocol and line rate (e.g., four lanes of 10GbE)
- Lower jitter than CPLL because the VCO operates at a higher frequency (closer to integer multiples of reference)
- Only one reference clock needed for all four channels

**CPLL (Channel PLL):**

The CPLL is private to each individual channel. Its VCO operates at lower frequency (1.6–3.3 GHz for GTH CPLL).

- Each channel can run at a different line rate and use a different reference clock
- Ideal when the four channels in a quad run at different line rates (e.g., mixed PCIe + SATA + SFP+)
- Slightly higher jitter than QPLL
- Supports lower line rates (down to 0.5 Gbps) that QPLL cannot reach

**Decision rule:**

| Scenario | Use QPLL | Use CPLL |
|---|---|---|
| All channels same line rate | Yes | Either |
| Mixed line rates in same quad | No | Yes |
| Highest performance, lowest jitter | Yes | No |
| Line rate < 3.0 Gbps | No (out of range) | Yes |
| PCIe (all lanes same rate) | Yes | Either |

**Practical note:** In PCIe IP, the QPLL is used by default and shared across all GTH channels assigned to the PCIe interface. CPLL is used in configurations like 1GbE (1.25 Gbps) where QPLL minimum frequency is exceeded from below.

---

### Q6. What is pre-emphasis on a GTH transmitter and what is equalization on a GTH receiver? Why are both needed for high-speed links?

**Answer:**

High-speed PCB traces attenuate signal amplitude in a frequency-dependent manner. The attenuation (in dB) increases with frequency due to skin effect and dielectric loss:

$$A(f) \approx A_0 \sqrt{f}$$

For a 10 Gbps NRZ signal, the fundamental frequency is 5 GHz. A 20-inch FR4 trace may attenuate 5 GHz by 15–20 dB compared to DC, severely closing the receive eye.

**TX Pre-Emphasis:**

Pre-emphasis boosts the high-frequency content of the transmitted signal *before* it enters the trace, compensating in advance for the trace's low-pass characteristic.

The GTH transmitter implements pre-emphasis as a finite impulse response (FIR) filter on the serialised data:

$$V_{TX}(t) = C_0 \cdot \text{main cursor} + C_{-1} \cdot \text{pre-cursor} + C_1 \cdot \text{post-cursor 1} + C_2 \cdot \text{post-cursor 2}$$

The cursor coefficients are configurable (positive and negative taps). A typical configuration has a large main cursor ($C_0$) and a negative post-cursor ($C_1 < 0$) — the "de-emphasis" configuration, which reduces the amplitude of consecutive same-level bits (DC content) relative to transitions.

**RX Equalization:**

Equalization at the receiver amplifies the high-frequency content that was attenuated during transmission. Two technologies are used:

**CTLE (Continuous-Time Linear Equaliser):**

A high-frequency-peaking analogue amplifier. It has a configurable zero that boosts frequencies above a set threshold. CTLE is always active and raises the high-frequency content of the received signal to partially restore the eye opening. It is characterised by a "boost" setting in dB.

**DFE (Decision Feedback Equaliser):**

A digital FIR filter applied after the decision (sampling) point. DFE uses the already-determined data values to subtract the inter-symbol interference (ISI) they cause on subsequent bits. Unlike CTLE, DFE does not amplify noise (it uses decided values, not amplified analog signal). DFE is more powerful for long-trace links but adds latency and complexity.

**Why both TX pre-emphasis and RX equalization are needed:**

No single mechanism can fully compensate for 15–20 dB of attenuation without degrading the signal-to-noise ratio:
- Pre-emphasis alone would require 15 dB of boost at TX, reducing the DC amplitude to a tiny fraction of full swing — the signal would be undetectable at the receiver
- CTLE alone amplifies both signal and noise equally, limiting its useful range to ~10 dB of boost
- DFE alone cannot compensate for pre-cursor ISI (echoes from future bits, not past bits)

The combination: TX pre-emphasis reduces post-cursor ISI, CTLE partially compensates mid-frequency loss, DFE removes residual post-cursor ISI at the receiver. Together they enable reliable 10–25 Gbps operation over FR4 PCBs.

**GTH configuration in Vivado:**

GTH equalization settings are configured in the GT Wizard IP or via DRP registers at runtime. Link training procedures (e.g., PCIe LTSSM) automatically optimise these parameters using measured eye metrics.

---

### Q7. What is the difference between the PCIe physical coding layer (8b10b vs 64b66b) and why does the choice of encoding matter for GTH configuration?

**Answer:**

**8b10b encoding:**

Each 8-bit data byte is encoded as a 10-bit symbol. The 2 extra bits ensure:
- DC balance: each 10-bit symbol has equal numbers of 0s and 1s (or ±1 from equal)
- Sufficient transitions for CDR: the encoded stream always has enough bit transitions to allow the receiver's clock-data recovery (CDR) circuit to synchronise

The overhead is $\frac{10 - 8}{10} = 20\%$. For a 10 Gbps line rate, the usable data bandwidth is 8 Gbps.

Special characters (comma symbols K28.5, K28.1) are used for alignment and protocol framing.

**64b66b encoding:**

64 bits of data are encoded as 66 bits by prepending a 2-bit synchronisation header (either `01` or `10`, never `00` or `11`). This ensures at least one transition per 66 bits for CDR.

The overhead is $\frac{66 - 64}{66} \approx 3\%$. For a 10 Gbps line rate, usable bandwidth is approximately 9.7 Gbps.

**Impact on GTH configuration:**

The GTH PCS (Physical Coding Sublayer) implements the encoder/decoder in hardware. The choice affects:

| Parameter | 8b10b | 64b66b |
|---|---|---|
| PCS encoding | Hardened in GTH PCS | Hardened in GTH PCS |
| Minimum line rate | ~0.5 Gbps | ~5 Gbps (scrambler needs transitions) |
| Bandwidth efficiency | 80% | 97% |
| Alignment characters | K28.5 comma | Block sync via header pattern |
| Latency | Low (byte-level sync) | Slightly higher (block-level sync) |
| Error detection | Built in (disparity) | Relies on scrambler + FEC |
| Uses | PCIe Gen1/2, SATA, 1GbE | PCIe Gen3+, 10GbE, 25GbE, 100GbE |

**GTH DW (data width) selection:**

The GTH RX outputs a parallel bus of width 16, 20, 32, 40, 64, or 80 bits to the FPGA fabric. For 8b10b at 10.3125 Gbps (SFP+), the internal word width is 32 bits (4 × 10-bit symbols + control). For 64b66b at 25 Gbps (25GbE), the internal word width is 64 bits.

The RXUSRCLK frequency is: $f_{line\_rate} / (DW \times encoding\_ratio)$. For 10.3125 Gbps / (32 × 10/8) = 258 MHz — this is the clock the FPGA logic operates at to process the data.

---

## Tier 3: Advanced

### Q8. Describe a complete I/O planning process for a design that uses DDR4 memory, 10GbE SFP+, and LVCMOS33 LEDs/pushbuttons. What constraints govern the pin assignment?

**Answer:**

**Step 1 — Identify I/O standards and required bank types:**

| Interface | Standard | VCCO | Bank type required |
|---|---|---|---|
| DDR4 DQ/DQS/CMD | POD12 / SSTL12 | 1.2 V | HP only |
| 10GbE SFP+ TX/RX | GTH transceiver | AC-coupled (no VCCO) | GTH quad |
| 10GbE REFCLK | LVDS (LVPECL from oscillator) | — | REFCLK pins of GTH quad |
| DDR4 CLK differential | DIFF_SSTL12 | 1.2 V | HP (same bank as DDR4 DQ) |
| LEDs, pushbuttons | LVCMOS33 | 3.3 V | HR only |

**Step 2 — Bank assignment rules:**

- DDR4 requires HP banks. Vivado's MIG (Memory Interface Generator) IP automatically assigns DDR4 signals to adjacent HP banks. DDR4 typically requires 2–4 HP banks depending on the data bus width.
- LEDs/pushbuttons at 3.3 V require HR banks (HP banks do not support VCCO > 1.8 V in UltraScale+).
- GTH transceivers are in dedicated GTH quads — no conflict with I/O banks.

**Step 3 — VREF routing for DDR4:**

DDR4 POD12 uses on-die termination at the DDR4 device, not a separate VREF. However, DDR4 CMD/ADDR signals use SSTL12 which requires $V_{REF} = 0.6$ V on the FPGA receiver. In UltraScale+ HP banks, VREF is generated internally (no external VREF pin needed for SSTL12 receivers), simplifying the PCB.

**Step 4 — Byte lane assignment for DDR4:**

MIG assigns DQ bytes to specific byte lanes within HP banks. Each byte lane (8 DQ + 1 DQS pair) must be kept within the same bank and aligned with the DQS strobe. Mixing DQ bits from different byte lanes is not allowed. The MIG IP enforces this automatically through its pin assignment wizard.

**Step 5 — GTH reference clock:**

Each GTH quad has dedicated MGTREFCLK pins (1–2 per quad, differential LVPECL). The SFP+ reference clock (typically 156.25 MHz for 10GbE) must be connected to the MGTREFCLK pin of the quad containing the SFP+ GTH channels. Do not route the reference clock through general I/O or logic fabric — this violates the GTH clocking architecture.

**Step 6 — Decoupling and power domain planning:**

Each HP bank has its own VCCO supply pin (1.2 V). Each HR bank has its own VCCO supply pin (3.3 V). These must be connected to the appropriate power planes on the PCB with adequate decoupling. The GTH quads have their own MGTAVCC (0.9 V) and MGTAVTT supply pins.

**Step 7 — Vivado I/O planning:**

Use Vivado's I/O Planning view (`open_io_design`) to:
1. Set PACKAGE_PIN for each top-level port
2. Set IOSTANDARD, SLEW, DRIVE strength
3. Run the DRC check `report_io_rules` to catch bank voltage conflicts before synthesis
4. Verify clock-capable pins (CC pins) are used for differential clocks entering BUFIO/MMCM

**Common mistakes caught at this stage:**

- Placing a DDR4 DQ pin in an HR bank (VCCO mismatch)
- Using non-CC pin for a clock input (Vivado will warn but some devices prohibit it)
- Assigning the SFP+ REFCLK to a general I/O pin instead of MGTREFCLK

---

### Q9. A GTH link at 10 Gbps is showing elevated bit-error rate (BER) in production. The eye diagram at the GTH receiver shows a partially closed eye with significant jitter. Describe a systematic debug approach.

**Answer:**

Elevated BER with a partially closed eye is a signal integrity problem. The debug process follows a systematic top-down approach.

**Step 1 — Characterise the eye with IBERT:**

Vivado's IBERT (In-System BER Tester) core allows scanning the GTH receiver eye opening from within the FPGA using the GT's internal eye scan capability. The output is a 2D eye contour map (voltage vs. timing offset). Read the:
- Eye width (UI): distance between the left and right eye crossings
- Eye height (mV): voltage margin
- Bathtub curves: BER vs. sampling offset

If eye width < 0.3 UI or BER > $10^{-12}$ at centre, the link has insufficient margin.

**Step 2 — Identify whether the problem is jitter or amplitude:**

- **Predominantly timing jitter (narrow eye, full height):** CDR bandwidth problem, transmitter jitter, or reference clock jitter.
- **Predominantly amplitude closure (full width, reduced height):** Excessive trace attenuation, insufficient equalization, or impedance mismatch.
- **Mixed:** Both are present — typical for long traces at high speed.

**Step 3 — Check reference clock quality:**

Connect an oscilloscope or spectrum analyser to the SFP+ REFCLK oscillator output. Excessive phase noise (jitter) from the reference propagates through the GTH PLL to the CDR. Specification for 10GbE REFCLK: < 200 fs RMS jitter (integrated 12 kHz–80 MHz). If the oscillator exceeds this, it must be replaced.

**Step 4 — Adjust TX pre-emphasis and RX equalization:**

Using Vivado DRP register access (or the IBERT GUI):
1. Sweep TXPOSTCURSOR from 0 to 31 (in steps of 2) — increases post-cursor de-emphasis
2. Monitor BER at each setting using IBERT
3. Set TXPOSTCURSOR to the value giving minimum BER or maximum eye opening
4. Repeat for RXEQCTRL (CTLE boost) and RXDFE settings

If pre-emphasis significantly improves the eye, the problem is trace attenuation (expected). If pre-emphasis has no effect, the problem is upstream of the PCB trace — likely the transmitter clock or the SFP+ module.

**Step 5 — Check for impedance discontinuities:**

Use a TDR (Time Domain Reflectometer) on the differential pair. Impedance discontinuities (vias, connectors, footprint stubs) appear as reflections at specific time offsets. A via through a 6-layer board with no back-drill creates a ~0.3 UI stub resonance at 10 Gbps — potentially catastrophic.

The fix is PCB-level: back-drill the vias, reduce stub length by using a different layer assignment, or change the connector pad geometry.

**Step 6 — Temperature correlation:**

If the BER is temperature-dependent (passes at room temperature, fails at 70°C), the trace loss increases with temperature (~0.3 dB/°C increase in FR4 dielectric loss tangent). The equalization settings that work at 25°C may be insufficient at 85°C. Solution: set equalization for the worst-case temperature, or implement adaptive equalization using IBERT results at temperature.

**Step 7 — Loopback tests to isolate TX vs RX:**

GTH provides three loopback modes:
- **Near-end PCS loopback:** TX PCS output feeds RX PCS input (bypasses PMA entirely) — tests the FPGA fabric interface
- **Near-end PMA loopback:** TX PMA output feeds RX PMA input (bypasses the trace) — tests the GTH analog circuits
- **Far-end PMA loopback:** data travels through the full trace path and back — tests the complete link

If near-end PMA loopback passes but far-end fails, the problem is in the trace or the remote device, not the FPGA transceiver.

---

## Quick Reference: Key Terms

| Term | Definition |
|---|---|
| I/O bank | Group of FPGA I/O pins sharing a common VCCO supply voltage |
| HP bank | High-Performance I/O bank; supports 1.0–1.8 V; used for DDR4, HSTL, SSTL |
| HR bank | High-Range I/O bank; supports 1.2–3.3 V; used for LVCMOS, LVDS, general I/O |
| VCCO | I/O output voltage supply; sets the voltage swing for all pins in a bank |
| LVDS | Low Voltage Differential Signalling; differential, 300 mV swing, 100 Ω termination |
| SSTL | Stub Series Terminated Logic; single-ended memory bus standard with VREF threshold |
| HSTL | High-Speed Transceiver Logic; single-ended standard for SRAM interfaces |
| POD12 | Pseudo-Open Drain at 1.2 V; DDR4 data bus standard |
| IOSERDES | I/O serialiser/deserialiser; up to ~1.6 Gbps; used for DDR DRAM interfaces |
| GTH | GigaBit Transceiver H; hardened multi-Gbps SerDes; up to 16.375 Gbps per channel |
| GTY | GigaBit Transceiver Y; higher-speed variant; up to 32.75 Gbps per channel |
| QPLL | Quad PLL — shared PLL for all four channels in a GTH/GTY quad |
| CPLL | Channel PLL — per-channel PLL for mixed-rate configurations |
| CDR | Clock-Data Recovery; circuit that extracts clock from incoming serial data stream |
| 8b10b | Line encoding: 8-bit data → 10-bit symbol; 20% overhead; DC balanced |
| 64b66b | Line encoding: 64-bit data → 66-bit block; 3% overhead; used in 10G/25G/100G Ethernet |
| CTLE | Continuous-Time Linear Equaliser; analogue high-frequency boost at GTH receiver |
| DFE | Decision Feedback Equaliser; digital ISI cancellation at GTH receiver |
| Pre-emphasis | TX FIR filter that boosts high-frequency content to compensate for trace attenuation |
| MGTREFCLK | Dedicated reference clock input pin for GTH/GTY quads; never use general I/O |
| IBERT | In-System BER Tester; Xilinx IP for live eye scanning via FPGA GTH internals |
| BER | Bit-Error Rate; fraction of received bits in error; target ≤ $10^{-12}$ for 10GbE |
