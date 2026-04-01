# UltraScale+ vs Intel Agilex: Architecture Comparison

Comparative interview preparation covering AMD/Xilinx UltraScale+ and Intel Agilex FPGA
architectures. Both families represent the current high-end production offerings from their
respective vendors (as of 2025--2026), both are built on TSMC advanced nodes, and both target
datacenter, 5G/telecom, aerospace, and high-performance computing markets. Understanding the
architectural differences is critical for platform selection decisions and for explaining design
tradeoffs in interviews.

---

## Tier 1 — Fundamentals

### Device Families Overview

**AMD/Xilinx UltraScale+** (launched 2015--2016):
- Process: TSMC 16nm FinFET+
- Logic: Kintex UltraScale+ (mid-range), Virtex UltraScale+ (high-end), Spartan UltraScale+ (cost-optimised)
- Key devices: XCKU, XCVU series. The VU19P is the largest monolithic FPGA ever made (~9M cells).
- Successor: AMD Versal (ACAP -- Adaptive Compute Acceleration Platform), which adds AI Engines.

**Intel Agilex** (launched 2020):
- Process: Intel 10nm SuperFin (Agilex 7/5) / Intel 7 (Agilex 3)
- Families: Agilex 7 (high-performance), Agilex 5 (mid-range), Agilex 3 (embedded/cost), Agilex M-Series (HBM integrated)
- Key technology: Hyperflex architecture (hyper-registers in routing), chiplet-based construction
  using EMIB (Embedded Multi-die Interconnect Bridge).
- Predecessor: Stratix 10 (Intel 14nm, also Hyperflex).

### Logic Fabric

**UltraScale+ CLB (Configurable Logic Block):**

Each CLB contains one slice. Two types of slices:
- **SLICEL**: 8 x LUT6 (6-input LUTs), 16 x flip-flops, carry chain. LUTs can be used as
  LUT5 with independent outputs (two functions per LUT) giving up to 16 logic functions per slice.
- **SLICEM**: Same as SLICEL plus the LUTs can be configured as 32-bit distributed RAM or
  32-bit shift register (SRL32). Only SLICEM can implement distributed RAM; approximately 25%
  of slices are SLICEM.

Each LUT6 can be split into two independent LUT5s (with shared inputs), effectively doubling
throughput for narrow functions. Flip-flops can be clocked, reset, set, and have clock enable.
The carry chain (CARRY8) spans 8 bits per CLB and is optimised for fast adders and comparators.

**Intel Agilex ALM (Adaptive Logic Module):**

The ALM is the Intel equivalent of the slice. Each ALM contains:
- One 8-input fracturable LUT (can implement one 6-input function, two independent 5-input
  functions sharing at most 4 inputs, or certain combinations of 4-input functions).
- 4 x dedicated flip-flops (2 with full control, 2 with shared control).
- A carry chain supporting both ripple-carry and fast-carry modes.
- Optional register feedback path.

ALMs are grouped into Logic Array Blocks (LABs) of 10 ALMs each. A LAB shares clock, clock
enable, synchronous clear, and asynchronous clear signals among its 10 ALMs, which creates a
local clock domain that reduces routing load for these control signals.

**Key fabric comparison:**

| Metric                        | UltraScale+ CLB           | Agilex ALM/LAB             |
|-------------------------------|---------------------------|----------------------------|
| LUT inputs                    | 6 (fracturable to 2x LUT5)| 8 (fracturable, various modes) |
| FFs per logic unit            | 8 per SLICEL/SLICEM       | 4 per ALM (40 per LAB)     |
| Carry chain granularity       | 8-bit (CARRY8)            | Per-ALM (1-bit increments) |
| Distributed RAM               | SLICEM only (~25%)        | MLAB (Memory LAB, subset)  |
| Shift register                | SRL16/SRL32 in SLICEM     | Via MLAB                   |
| Local routing                 | Local/long line hierarchy | LAB-local interconnect      |
| Hyper-registers in routing    | No                        | Yes (Hyperflex)             |

The Hyperflex hyper-register is the most important architectural distinction. Every routing segment
in Agilex (and Stratix 10) has a register site that can be enabled by the fitter. This allows the
fitter to automatically pipeline long routes without any RTL change. The consequence is that designs
targeting Agilex should be written with retiming in mind: deep combinational trees are acceptable
because the fitter will insert pipeline stages. However, this means latency through the device is
not fixed and must be accounted for in timing-sensitive protocols.

---

### Fundamentals Interview Questions

**Q1. What is a hyper-register and why does it change how you think about RTL design for Agilex?**

Answer:

A hyper-register is a flip-flop site that exists within the routing interconnect fabric of Intel
Stratix 10 and Agilex devices. Unlike traditional FPGA routing where wire segments are purely
passive, Hyperflex routing segments are "pipelined wires": each segment has an optional register
that the fitter can enable to absorb routing delay.

**What this means architecturally:**

In a traditional FPGA (UltraScale+), a long combinational path from register A to register B passes
through LUTs and routing. If that path is too slow, you must add a pipeline register in RTL --
which changes the latency and requires changes to downstream control logic.

In Agilex with Hyperflex, the fitter can insert pipeline registers at arbitrary points along the
routing path without any RTL change. The tool automatically adjusts all other paths to maintain
correct relative timing. This is called **retiming** at the routing level.

**Implications for RTL style:**

- Long combinational trees (e.g., a 64-bit priority encoder with no pipeline) are more acceptable
  in Agilex because the fitter can break them up. In UltraScale+, such a tree might require manual
  pipelining.
- **Latency is not RTL-deterministic**: The exact number of pipeline stages inserted by the fitter
  depends on the physical placement and routing. The same RTL can have different latencies on
  different compilations. This is critical for protocols that depend on fixed latency (PCIe TLP
  processing, cache coherency, deterministic ADC pipelines).
- Control paths that must match data path latency need explicit synchronisation, not assumptions
  about combinational delay.
- Intel recommends writing Agilex RTL with an "II=1" pipelined style (initiation interval of 1)
  to give the fitter maximum freedom to insert hyper-registers.

---

**Q2. What is the difference between UltraScale+ BRAM and UltraScale+ UltraRAM? When would you choose each?**

Answer:

UltraScale+ has two embedded memory primitives:

**Block RAM (BRAM -- RAMB36E2):**
- Capacity: 36 Kb per primitive (or configured as two 18 Kb)
- Ports: True dual-port (TDP) or simple dual-port (SDP)
- Width: Configurable, up to 72 bits wide (SDP mode)
- Read latency: 1 clock cycle (registered read), or combinational (BRAM output register disabled)
- Optional output register (adds 1 cycle, improves timing)
- ECC: Available in 72-bit SDP mode (SECDED -- single-error correct, double-error detect)
- Location: Distributed throughout the device in columns
- Max cascade depth: Limited; deep memories require multiple BRAMs and address decode logic

**UltraRAM (URAM -- RAMB288):**
- Capacity: 288 Kb per primitive (8x larger than BRAM36)
- Ports: Single true dual-port with 72-bit wide data (fixed width)
- Read latency: 2 clock cycles minimum (cannot be reduced -- output register is mandatory)
- ECC: Supported (72-bit width with 8 ECC bits)
- Location: Grouped in columns separate from BRAM columns; cascadeable in vertical stacks
  using dedicated cascade connections
- Cascade: URAMs in the same column can be cascaded with URAM-specific cascade ports,
  enabling large memories (e.g., 18 Mb) without any routing congestion

**Selection guidelines:**

Use **BRAM** when:
- Memory depth is small to moderate (< ~64K entries for 18-bit data).
- Single-cycle read latency is required (e.g., lookup tables in a data pipeline where you
  cannot afford extra pipeline stages).
- Mixed widths are needed (BRAM supports asymmetric port widths).
- The memory is used as a shift register or FIFO with tight timing.

Use **UltraRAM** when:
- Large memory arrays are required (> 1 Mb). URAMs pack 8x the capacity per site.
- Two-cycle read latency is acceptable (most pipelined datapaths can absorb this).
- You are implementing caches, packet buffers, or frame buffers where capacity dominates.
- You need cascade-able large memories: URAM cascade is much more efficient than BRAM cascade
  because the cascade path is a dedicated route (not general routing).

**Intel Agilex equivalent:**
- **M20K**: 20 Kb embedded SRAM blocks, similar role to UltraScale+ BRAM. True dual-port, various
  width/depth configurations, 1--2 clock read latency.
- **MLAB**: 640-bit distributed RAM inside LABs (Memory LABs), equivalent to UltraScale+
  distributed RAM in SLICEM.
- Agilex M-Series: Has integrated HBM2e stacks (up to 32 GB) connected via a dedicated
  memory controller inside the FPGA die -- there is no direct UltraScale+ equivalent in
  standard devices (Versal HBM is the closest Xilinx equivalent).

---

**Q3. Describe the DSP resources in UltraScale+ and Agilex. What operations does each support natively?**

Answer:

**UltraScale+ DSP48E2:**

The DSP48E2 is an 18x27 two's-complement multiplier feeding a 48-bit accumulator with pre-adder:

```
      A (30-bit) ──┐
                   ├─[pre-adder: A±D]──[multiplier 18x27]──[P register 48-bit]──[PCOUT cascade]
      D (27-bit) ──┘
      B (18-bit) ──────────────────────────────────────────────────────────────────┘
                                                        │
      C (48-bit) ──────────────────────────[ALU: P op C]──[out]
```

Operations natively supported by DSP48E2:
- `P = A * B` (18x27 multiply, result in 48 bits)
- `P = A * B + C` (multiply-accumulate)
- `P = (A ± D) * B` (pre-adder enables efficient FIR filter with symmetrical coefficients)
- `P = P + A * B` (accumulation over multiple cycles)
- `P = A:B` (concatenation -- 48-bit wide path without multiply)
- `P = C ± P` (pure adder/accumulator without multiply)
- Pattern detect: hardware comparator on P vs a programmable 48-bit pattern (useful for
  overflow detection and counter terminal count)
- SIMD mode: Two independent 24-bit or four independent 12-bit accumulations in one DSP48E2

The DSP48E2 cascade bus (PCOUT→PCIN, ACOUT→ACIN, BCOUT→BCIN) allows chaining multiple
DSPs without general routing, critical for FIR filters and systolic arrays.

**Intel Agilex DSP Block:**

Agilex DSPs are more configurable than DSP48E2. The DSP block can be configured as:
- 27x27 multiply (larger than DSP48E2's 18x27)
- Two independent 18x19 multiplies sharing one DSP block
- Fixed-point multiply-accumulate with 64-bit accumulator
- Floating-point operations: The Agilex DSP block natively supports IEEE 754 single-precision
  and half-precision float operations (FP32 and FP16 multiply-add) in hardware -- a capability
  not present in DSP48E2.
- INT8 and INT4 dot-product operations in selected Agilex AI-oriented variants.

**Comparison summary:**

| Feature                  | UltraScale+ DSP48E2        | Agilex DSP Block            |
|--------------------------|----------------------------|-----------------------------|
| Multiplier size          | 18 x 27 (signed)           | 27 x 27 (signed)            |
| Accumulator width        | 48 bits                    | 64 bits                     |
| Pre-adder                | Yes (D path)               | Yes                         |
| Native floating-point    | No (must use LUT+DSP)      | Yes (FP32, FP16, INT8)      |
| SIMD mode                | Yes (24x2 or 12x4)         | Yes                         |
| Cascade bus              | Yes (P, A, B cascades)     | Yes                         |
| Two multipliers per block| No                         | Yes (two 18x19 mode)        |

For DSP-heavy designs (e.g., FIR filters, FFTs), Agilex's larger multiplier and wider accumulator
provide more precision headroom and can implement larger multiply operations in a single DSP.
UltraScale+ designs often need two DSP48E2s to implement a 27x27 multiply.

---

## Tier 2 — Intermediate

### Intermediate Concepts

**UltraScale+ transceiver hierarchy:**
- GTY: 32.75 Gb/s per lane. Used for 100GbE, PCIe Gen4, Interlaken.
- GTH: 16.375 Gb/s per lane. Used for 25GbE, SATA, DisplayPort.
- GTM: 58 Gb/s per lane (PAM4). Only in Virtex UltraScale+ HBM devices. Used for 400GbE.
- GTYP: 28.21 Gb/s (Versal).

**Agilex transceiver hierarchy:**
- E-tile: Up to 58 Gb/s per lane (NRZ and PAM4). Used for 400GbE, PCIe Gen5 (in some variants).
- P-tile: PCIe Gen4 hard IP tile, up to 16 GT/s per lane, x16 link.
- F-tile: 112 Gb/s per lane (PAM4). Used for 800GbE (emerging).
- R-tile: PCIe Gen5 + CXL 2.0 hard IP.

**Super Logic Regions (SLR) -- UltraScale+:**
Large UltraScale+ devices are built from multiple dice stacked using CoWoS (Chip-on-Wafer-on-Substrate)
with Silicon Interposer technology. Each die is an SLR. Crossing SLR boundaries (via SLLs --
Super Long Lines) has additional latency (~2--3 ns) and limited bandwidth. Floorplanning critical
paths to stay within a single SLR is an important optimisation technique.

**Agilex die-to-die connectivity -- EMIB:**
Agilex uses EMIB (Embedded Multi-die Interconnect Bridge) to connect the core FPGA die to
transceiver tiles, HBM stacks, and other chiplets. EMIB is a short-range, high-density 2.5D
interconnect embedded in the package substrate. Unlike Xilinx's silicon interposer (which spans
the entire die), EMIB connects only at specific die edges, reducing cost. The latency across EMIB
is higher than on-die but lower than PCB-level connections.

---

### Intermediate Interview Questions

**Q4. A design requires four 100GbE links and runs a 400 MHz processing pipeline. Which UltraScale+ device features are critical to consider in device selection?**

Answer:

This question tests knowledge of transceiver resources, SLR topology, and clock region planning.

**Transceiver requirement:**

100GbE (100 Gigabit Ethernet) in CAUI-4 mode uses four lanes at 25.78125 Gb/s each. Each lane
requires one GTH or GTY transceiver. Four 100GbE links = 16 GTH/GTY transceivers minimum (4 links
× 4 lanes). The transceivers must be in the same quad (group of 4 transceivers sharing a PLL) or
adjacent quads for multi-link implementations.

Key selection constraint: Transceivers are located at the device periphery. Ensure the transceiver
quads and their reference clock inputs are available on the selected device/package combination.
Not all packages expose all transceiver quads.

**400 MHz pipeline:**

At 400 MHz in UltraScale+, setup timing budget per clock cycle = 2.5 ns. This is near the limit
of what Vivado can achieve without aggressive directives. Critical considerations:
- Target a device with speed grade -2 or -3 (e.g., XCVU9P-2).
- The critical path must fit within ~1.8--2.0 ns of logic delay (leaving ~0.5--0.7 ns for routing).
- Consider floorplanning the critical path within one SLR to avoid the ~2--3 ns SLL penalty.

**SLR topology:**

Devices like the XCVU9P have three SLRs. The 400 MHz path that processes 100GbE data should
ideally be in the same SLR as the GTY/GTH transceivers feeding it. A cross-SLR register in the
pipeline costs roughly one pipeline stage worth of budget.

**Clock planning:**

Each SLR has independent global clock buffers. A 400 MHz global clock fed by an MMCM in SLR0
can reach SLR1 and SLR2 via horizontal and vertical clock routes, but the SLL clock routing
adds skew. For 400 MHz, it is common to instantiate one MMCM per SLR with the same reference
clock, keeping skew within each SLR manageable.

**Equivalent Agilex consideration:**

For Agilex, the E-tile or F-tile transceivers are on a separate chiplet connected via EMIB. The
Hyperflex architecture means 400 MHz is more achievable without manual pipelining, but the EMIB
latency between transceiver tile and fabric must be accounted for in the MAC-to-logic data path.

---

**Q5. Explain the UltraScale+ MMCM vs PLL, and compare to Agilex fPLL and ATX PLL.**

Answer:

**UltraScale+ MMCM (Mixed-Mode Clock Manager):**

The MMCM generates up to 7 output clocks from a single input reference. Key capabilities:
- Frequency synthesis: output = input × M / D, where M is the VCO multiplier and D is the
  output divider. Each output has an independent divide (O0--O6).
- Phase shifting: Each output can be phase-shifted in steps. CLKOUT0 supports fractional
  phase shifting (1/8 VCO period resolution).
- Fractional divide: CLKFBOUT_MULT_F can be non-integer (e.g., 6.125) for frequencies that
  are not achievable with integer divide chains.
- Dynamic reconfiguration: MMCM can be reconfigured at runtime via the DRP (Dynamic
  Reconfiguration Port) to change frequency/phase without device reconfiguration.
- Clock deskew: The feedback path (CLKFBIN) allows the MMCM to eliminate insertion delay on
  a specific clock tree, aligning the MMCM output clock with the upstream reference.
- Jitter filtering: MMCM's bandwidth filter attenuates input jitter.

**UltraScale+ PLL (PLLE4_ADV):**

Simpler than MMCM. Generates up to 6 output clocks. No fractional multiply, no dynamic phase
shifting, no spread spectrum. Consumes fewer resources and has lower jitter floor for some
applications. Used when MMCM features are not needed.

**Intel Agilex fPLL (Fractional PLL):**

Each fPLL generates up to 7 output clocks. Supports:
- Integer and fractional N counters for frequency synthesis.
- Spread spectrum modulation (for EMI reduction in consumer products).
- Dynamic reconfiguration via Avalon-MM interface.
- Clock switchover (two reference inputs, automatic or manual switch).
- Bandwidth modes: Low bandwidth (better jitter filtering), high bandwidth (lower phase noise
  for high-speed clocks).

**Intel Agilex ATX PLL (Advanced Transmit PLL):**

The ATX PLL is purpose-built for transceiver reference clocks. It generates a high-frequency
VCO output (up to ~14 GHz) that feeds the transceiver CDR circuits. Key characteristics:
- Lower phase noise floor than fPLL at multi-GHz frequencies.
- Not directly accessible as a fabric clock -- output goes to the transceiver tile, not the
  FPGA fabric clock network.
- One ATX PLL per transceiver bank.

**Comparison table:**

| Feature               | UltraScale+ MMCM        | UltraScale+ PLL          | Agilex fPLL            | Agilex ATX PLL         |
|-----------------------|--------------------------|--------------------------|------------------------|------------------------|
| Output clocks         | 7                        | 6                        | 7                      | Transceiver use only   |
| Fractional multiply   | Yes (CLKFBOUT_MULT_F)    | No                       | Yes                    | No                     |
| Phase shift per output| Yes (fractional for O0)  | No                       | Yes                    | No                     |
| Dynamic reconfig      | Yes (DRP)                | No                       | Yes (Avalon-MM)        | Yes                    |
| Clock deskew          | Yes (feedback path)      | Yes                      | Yes (cascade mode)     | No                     |
| Spread spectrum       | Yes                      | No                       | Yes                    | No                     |
| Primary use case      | Fabric clocking          | Fabric clocking          | Fabric clocking        | Transceiver reference  |

---

**Q6. What is the UltraScale+ Integrated Block for PCIe, and how does Agilex P-tile differ?**

Answer:

**UltraScale+ PCIe Integrated Block (PCIE4 / PCIE4C):**

UltraScale+ devices contain a hardened PCIe endpoint/root-port IP block (PCIE4C in most devices).
It is a physical macro sitting in a fixed location on the die, not constructed from LUT logic.

Capabilities:
- PCIe Gen1/2/3/4 (Gen4 in XCVU/XCKU -3 speed grade devices)
- Up to x16 link width (16 lanes)
- Integrated DMA and AXI4-Stream interface to the FPGA fabric
- 256-bit AXI interface at fabric clock (~250 MHz), hiding the 16 GT/s SerDes detail
- TLP processing in hardware (header parsing, credit management, flow control)

The PCIe block must be in the same SLR as its associated GTY/GTH transceivers. In multi-SLR
devices, only one SLR typically contains the PCIe hard block.

**Intel Agilex P-tile:**

The P-tile is a separate chiplet connected to the FPGA fabric via EMIB. It is a standalone
hardened PCIe Gen4 (and Gen5 in some variants) + CXL complex:

Capabilities:
- PCIe Gen4 x16, Gen5 x8 (device-dependent)
- CXL 1.1 / 2.0 protocol support (hardened -- not available in any UltraScale+ device)
- Separate AXI4-ST interface to the FPGA fabric across EMIB
- The P-tile operates at its own clock domain; the EMIB crossing adds ~10--15 ns latency
  compared to on-die PCIe blocks

**R-tile (newer Agilex):**

The R-tile extends P-tile with PCIe Gen5 and CXL 2.0 (Type 1, 2, and 3 device support). This
is a significant competitive advantage: as of 2025, no UltraScale+ device has hardened CXL
support. Versal (AMD's next-generation ACAP) includes CXL in some variants.

**Key interview point:** The P/R-tile EMIB latency is a real concern for PCIe TLP processing
pipelines. In UltraScale+, the PCIe block is on the same die so fabric access latency is
~100--200 ns end-to-end. With P-tile EMIB, add ~50 ns for the EMIB crossing, which matters
for CXL memory coherency protocols where latency is a key metric.

---

## Tier 3 — Advanced

### Advanced Interview Questions

**Q7. A 400GbE implementation needs to fit in a single FPGA. Compare UltraScale+ VU19P versus an Agilex 7 device for this requirement, addressing fabric, transceivers, and memory bandwidth.**

Answer:

This is a platform selection question common in networking FPGA roles. The answer requires
synthesising knowledge across multiple architectural dimensions.

**400GbE framing:**

400GbE (IEEE 802.3bs/cd) can be implemented as:
- 400GBASE-R16: 16 lanes × 26.5625 Gb/s NRZ (CAUI-16)
- 400GBASE-R8: 8 lanes × 53.125 Gb/s PAM4 (CAUI-8)
- 400GBASE-R4: 4 lanes × 106.25 Gb/s PAM4 (emerging)

**UltraScale+ VU19P analysis:**

Transceivers: The VU19P has 96 GTY transceivers (16 GT/s NRZ) and GTM transceivers (58 Gb/s
PAM4) in VU+ HBM devices. For 400GBASE-R8 (8 lanes at 53.125 Gb/s), you need PAM4-capable
transceivers. Standard GTY tops out at 32.75 Gb/s NRZ. GTM supports 58 Gb/s, so 400GBASE-R8
is feasible on VU+ devices with GTM.

For CAUI-16 (16 lanes at 26.5625 Gb/s), standard GTY works. A single VU19P has enough GTY
transceivers for multiple 400GbE ports in CAUI-16 mode.

Fabric: VU19P has ~8.9 million logic cells. 400GbE MAC + PCS consumes significant fabric but
the device is large enough. The SLR boundary (VU19P has 4 SLRs) must be managed carefully
to avoid the ~2--3 ns SLL penalty on the 350 MHz+ core MAC pipeline.

Memory: The standard VU19P has 75 Mb of BRAM and 270 Mb of UltraRAM. For packet buffering
at 400 Gb/s: at 1500-byte MTU, line-rate buffering for 1 ms requires ~50 Mb. UltraRAM can
provide this but URAM bandwidth (each URAM at 64-bit × 500 MHz = 32 Gb/s read and write)
means you need multiple URAMs in parallel to match 400 Gb/s line rate.

**Agilex 7 analysis:**

Transceivers: Agilex 7 with E-tile supports 58 Gb/s PAM4 per lane, making 400GBASE-R8
natural (8 lanes × 53.125 Gb/s). F-tile supports 112 Gb/s PAM4 for future 800GbE. For 400GbE
the E-tile is the primary choice.

Fabric: Agilex 7 top devices have ~2M ALMs (~4M equivalent LUT4s). The Hyperflex architecture
allows higher clock frequencies with less manual pipelining, which is valuable in a MAC pipeline.

Memory bandwidth advantage (M-Series): Agilex M-Series devices integrate HBM2e (High-Bandwidth
Memory) on-package. HBM2e provides up to 819 GB/s bandwidth vs URAM-based solutions. For
400GbE packet processing with stateful operations (per-flow tracking, traffic shaping), HBM
is transformative: you can store and access millions of flow table entries at line rate.

CXL advantage: If the 400GbE implementation is part of a SmartNIC that connects to a host CPU
via CXL (for memory-pooling or cache-coherent access), Agilex's R-tile CXL 2.0 support is a
decisive advantage. UltraScale+ does not have hardened CXL.

**Recommendation framework for an interview:**

- Pure fabric size: UltraScale+ VU19P wins (largest monolithic device).
- Transceiver line rate: Agilex E-tile (58 Gb/s) vs GTY (32.75 Gb/s NRZ). Agilex wins for
  PAM4 400GbE without needing GTM devices.
- Memory bandwidth: Agilex M-Series wins decisively with HBM2e.
- CXL/PCIe Gen5: Agilex R-tile wins.
- Tool maturity and ecosystem: UltraScale+ Vivado has more user-reported stability and a
  larger reference design library for Ethernet (Xilinx 100G Ethernet subsystem is widely used).
- Production availability and pricing: Depends on procurement context.

---

**Q8. Explain the UltraScale+ I/O bank structure, IDELAYE3, and OSERDESE3 primitives. What is the Agilex equivalent for source-synchronous interfaces?**

Answer:

**UltraScale+ I/O Bank Structure:**

I/O pins are organised into banks of 52 pins (HP -- High Performance) or 26 pins (HD -- High
Density). Each bank has:
- A shared VCCIO supply setting the output drive voltage (1.0 V for HP, 1.2--3.3 V for HD).
- One BITSLICE_CONTROL per nibble (13 pins) for RX/TX bit slip, ISERDES, and OSERDES control.
- IDELAY / ODELAY chains for fine-grained delay adjustment.

**IDELAYE3 (Input Delay Element):**

IDELAYE3 inserts a calibrated delay on an input signal, critical for source-synchronous
interfaces (DDR4, QSPI, LVDS camera interfaces). Key parameters:

- Delay type: FIXED, VARIABLE, or VAR_LOAD.
- Delay resolution: ~2.5 ps steps (device speed grade dependent).
- Total maximum delay: ~1.25 ns (500 taps × 2.5 ps).
- Calibration: IDELAYCTRL must be instantiated in each bank region to calibrate the delay
  chain against REFCLK (200 MHz or 300 MHz).

```vhdl
-- IDELAYE3 instantiation for centre-aligned DDR data capture
IDELAYE3_inst : IDELAYE3
    generic map (
        DELAY_FORMAT    => "TIME",      -- Delay in picoseconds (vs COUNT for raw taps)
        DELAY_TYPE      => "VARIABLE",  -- Runtime adjustable via INC/CE
        DELAY_VALUE     => 0,           -- Initial delay (ps)
        REFCLK_FREQUENCY => 300.0,      -- IDELAYCTRL reference clock frequency
        UPDATE_MODE     => "ASYNC"      -- Load new delay value asynchronously
    )
    port map (
        IDATAIN  => dq_pad,             -- From I/O pad (via IBUF)
        DATAOUT  => dq_delayed,         -- To ISERDESE3
        CLK      => clk_fabric,
        CE       => idelay_ce,
        INC      => idelay_inc,         -- Increment/decrement for CDR alignment
        RST      => idelay_rst,
        LOAD     => '0',
        CNTVALUEIN  => (others => '0'),
        CNTVALUEOUT => idelay_count     -- Read current tap count for debug
    );
```

**OSERDESE3 (Output Serialiser):**

OSERDESE3 serialises parallel fabric data to high-speed serial output. Used for DDR4 DQ write
data, LVDS source-synchronous output, and MIPI interfaces:
- Modes: SDR, DDR, or x4/x8 serialisation ratios.
- The DDR mode outputs 2 bits per clock cycle (data valid on both edges of the output clock).

**Intel Agilex equivalent:**

Agilex uses **LVDS I/O** (for differential) and **GPIO** (for single-ended) banks.

For source-synchronous interfaces:
- **ALTDDIO_IN / ALTDDIO_OUT IP**: Implements DDR capture/drive using dedicated DDR registers
  in the I/O block.
- **ALTLVDS_RX / ALTLVDS_TX**: High-speed LVDS source-synchronous deserialisation up to
  ~1 Gb/s per channel (for video, sensor interfaces).
- **Delay lines**: Agilex I/O blocks contain input delay elements configurable through the I/O
  PLL (IOPLL) for phase alignment. The granularity is similar to UltraScale+ IDELAYE3
  (~ps-level steps).
- **Hard Memory Controller**: For DDR4/LPDDR4/DDR5 interfaces, both vendors recommend using
  the vendor's hard memory controller IP rather than constructing source-synchronous interfaces
  manually. Agilex has a hardened external memory interface (EMIF) subsystem.

**Key interview point:** A common interview scenario is: "You have a 400 MHz DDR4-3200 interface.
How do you capture the source-synchronous data in UltraScale+?" The answer involves IDELAYE3
for delay adjustment, ISERDESE3 for 8:1 deserialisation, and either a training sequence or
manual tap-scan to centre the eye. Agilex's EMIF IP handles this automatically.

---

**Q9. Compare SLR crossing strategy in UltraScale+ multi-die devices with Agilex EMIB crossing strategy. What are the latency and bandwidth implications?**

Answer:

**UltraScale+ SLR crossing (Silicon Interposer / CoWoS):**

Large UltraScale+ devices (e.g., VU9P with 3 SLRs, VU19P with 4 SLRs) are built by connecting
multiple dies on a passive silicon interposer. The connection between SLRs uses Super Long Lines
(SLLs).

Properties of SLL:
- Wire delay: ~2--3 ns per SLR boundary crossing (unregistered).
- Must register before/after SLL: Vivado's place and route automatically inserts SLL register
  stages if paths cross SLR boundaries, consuming a full clock cycle at the fabric frequency.
- Available SLL bandwidth: ~23,000 SLL connections between adjacent SLRs on VU9P.
  Each SLL is a single wire, so bulk data (e.g., 512-bit data bus) consumes 512 SLLs.
- SLL usage is a critical resource: if you exhaust SLLs, routing fails entirely.

Practical guidance:
```tcl
# Force critical paths to stay within SLR0 to avoid SLL crossing
create_pblock pblock_slr0
add_cells_to_pblock pblock_slr0 [get_cells {u_mac u_pcs u_fifo}]
resize_pblock pblock_slr0 -add {SLR0}
```

**Agilex EMIB crossing:**

EMIB connects dies within the package using short, high-density interconnect embedded in the
package substrate. The EMIB spans only the die edges, not the full die area (unlike a full
silicon interposer).

Properties of EMIB crossing:
- Wire delay: ~5--15 ns (longer than SLL, shorter than BGA package routing).
- Interface logic: The EMIB crossing is managed by hardened interface logic on each die that
  includes clock domain crossing FIFOs. This is not raw wires -- it is a packetised interface.
- Bandwidth: Each EMIB interface can sustain hundreds of Gb/s aggregate bandwidth.
- Latency asymmetry: Read accesses across EMIB (e.g., FPGA fabric → HBM2e) have latency that
  depends on the EMIB interface controller, typically 30--60 ns for the EMIB crossing itself
  plus memory latency.

**Comparison:**

| Metric                    | UltraScale+ SLL             | Agilex EMIB                  |
|---------------------------|-----------------------------|------------------------------|
| Crossing latency          | 2--3 ns (+ 1 register stage)| 5--15 ns (hardened FIFOs)    |
| Max parallel wires        | ~23,000 (VU9P SLR0-SLR1)   | Depends on die-edge width    |
| Interface type            | Raw wires (general routing) | Packetised (hardened IP)     |
| Crossing transparency     | Relatively transparent      | Must use specific interface  |
| Clock domain isolation    | No (same fabric clock OK)   | Yes (EMIB has own CDC logic) |
| Die-to-die types          | FPGA die to FPGA die        | FPGA to transceiver/HBM/PCIe|

**Interview insight:** The architectural difference is philosophical. Xilinx's SLL approach gives
the engineer relatively transparent access to the multi-die fabric -- a path that crosses an SLR
boundary looks almost like a same-die path to the tool, just slower. Intel's EMIB approach is
explicitly heterogeneous: each chiplet (transceiver tile, HBM, PCIe) has its own hardened
interface. The FPGA engineer does not route across EMIB directly; they instantiate the
vendor-provided IP that manages the EMIB. This reduces routing flexibility but increases
reliability and allows mixing very different process nodes (e.g., FPGA fabric on Intel 10nm
and HBM using standard HBM2e DRAM process).
