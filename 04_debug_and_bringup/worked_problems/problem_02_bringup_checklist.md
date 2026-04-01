# Problem 02: FPGA Board Bring-Up Checklist

## Problem Statement

You are the lead FPGA engineer responsible for qualifying a newly assembled prototype of a
carrier-grade line card. The board contains:

- 1× Xilinx Virtex UltraScale+ VU13P FPGA (FCGA2104 package)
- 4× 8 GB DDR4-2666 RDIMM memory (512-bit wide interface via four MIG instances)
- 1× 256 Mb SPI flash (primary configuration)
- 1× 64 Mb SPI flash (golden/fallback configuration, hardware write-protected)
- 6× QSFP28 cages (100G optical)
- 1× PCIe Gen4 x16 edge connector
- 1× Zynq UltraScale+ ZU19EG PS+PL companion chip for board management
- Multiple power domains (12V input, multiple point-of-load regulators)

The board has just arrived from the contract manufacturer. Five boards were assembled. You have
one week before design review. Your task is to qualify at least two boards to a defined
standard.

Below is a comprehensive bring-up checklist with acceptance criteria, ordered by phase.

---

## Phase 0 — Pre-Power Inspection

### Visual and Mechanical

- [ ] **VU13P orientation verified** — pin A1 marker (small dot or chamfered corner on
  component) aligned with pin A1 silkscreen marker on PCB. Confirm with schematic.

- [ ] **ZU19EG orientation verified** — same check as above.

- [ ] **DDR4 DIMM slots populated** — confirm correct DIMM type (RDIMM vs UDIMM vs LRDIMM).
  VU13P MIG is configured for RDIMM; installing UDIMMs will cause calibration failure.

- [ ] **SPI flash devices present** — verify both primary and golden flash chips are populated,
  correct orientation, and correct device code visible under magnification.

- [ ] **QSFP28 cages mechanically intact** — no bent pins inside cage; all six cages flush
  to PCB.

- [ ] **PCIe edge connector** — gold fingers clean, no oxidation or scratches. Edge
  connector aligned correctly.

- [ ] **No visible solder bridges** — inspect under 10× magnification all fine-pitch QFN,
  BGA edges (where visible), DIMM connector pads.

- [ ] **No missing components** — cross-reference against BOM for all passive components
  visible on top and bottom layers.

### Passive Electrical (No Power Applied)

- [ ] **VCCINT rail resistance to GND** — expected: 5–30 Ω. A value <2 Ω indicates a short
  on the core supply (typically caused by a solder bridge on VCCINT decoupling capacitors).
  Measure at the output of the core voltage regulator.

- [ ] **VCCAUX rail resistance to GND** — expected: 10–50 Ω.

- [ ] **VCCO bank rail resistance to GND** — measure each bank separately; expected: 10–100 Ω
  depending on bank population.

- [ ] **JTAG chain continuity** — with DMM in continuity mode, check:
  - PCIe JTAG header pin 3 (TDI) → VU13P TDI pin (per schematic)
  - VU13P TDO → ZU19EG TDI (or next device in chain)
  - Final TDO → PCIe header pin 1 (TDO)

- [ ] **No supply-to-supply shorts** — measure resistance between VCCINT and VCCAUX nodes;
  expected: >1 kΩ.

- [ ] **Mode pin pull resistors present** — measure voltage divider ratio at VU13P M[2:0] pins
  with DMM (passive, before power). Should match the intended SPI master mode settings.

- [ ] **SPI flash write-protect pin** — golden flash WP# pin: confirm pulled low (write-
  protected). Primary flash WP#: confirm pulled high (writeable) or under FPGA GPIO control.

### Documentation

- [ ] **Bitstream compiled for correct device** — confirm `.bit` file header shows `VU13P`
  and the correct package and speed grade.

- [ ] **Golden flash pre-programmed** — confirm factory-programmed golden bitstream is
  present (record flash programmer log and checksum).

- [ ] **Power budget verified** — confirm calculated peak power (from Vivado Power Estimator)
  does not exceed regulator ratings at worst-case Tj.

---

## Phase 1 — Bench Power-On

### Equipment Setup

- [ ] **Current-limited bench supply configured** — 12V input, current limit set to 8A
  (expected idle: ~5A for UltraScale+ board at no-load configuration). Set alarm at 7A.

- [ ] **Oscilloscope channels assigned:**
  - CH1: VCCINT (0.85V nominal)
  - CH2: VCCAUX (1.8V nominal)
  - CH3: VCCO_bank65 (1.2V nominal, DDR4 I/O)
  - CH4: VCCO_bank28 (3.3V, general I/O)
  - Trigger: power enable signal from ZU19EG

### Measurements

- [ ] **Power-on sequence captured** — scope capture confirms:
  1. VCCINT rises first (target: T=0–5 ms from enable)
  2. VCCAUX rises within 5 ms of VCCINT stable
  3. VCCO banks rise after VCCAUX stable
  4. Sequence matches UG583 Table 1-3 requirements for VU13P

- [ ] **All rail voltages within tolerance at T+100ms:**

  | Rail          | Nominal | Min    | Max    | Measured |
  |---------------|---------|--------|--------|----------|
  | VCCINT        | 0.85V   | 0.808V | 0.893V | ________ |
  | VCCAUX        | 1.80V   | 1.710V | 1.890V | ________ |
  | VCCAUX_IO     | 1.80V   | 1.710V | 1.890V | ________ |
  | VCCO_DDR4     | 1.20V   | 1.140V | 1.260V | ________ |
  | VTT_DDR4      | 0.60V   | 0.570V | 0.630V | ________ |
  | MGTAVCC       | 0.90V   | 0.855V | 0.945V | ________ |
  | MGTAVTT       | 1.20V   | 1.140V | 1.260V | ________ |
  | MGTVCCAUX     | 1.80V   | 1.710V | 1.890V | ________ |

- [ ] **Idle current within budget:**
  - Board total (12V input): expected 4–6A at idle with FPGA unconfigured. Record: ________A
  - Anomaly threshold: >7A indicates a problem before bitstream load.

- [ ] **No thermal anomalies** — after 2 minutes at idle, thermally scan board with IR camera
  or handheld thermocouple. No component should exceed 60°C at ambient 25°C during idle.

- [ ] **ZU19EG INIT_B and DONE** — verify ZU19EG (board management chip) configures correctly
  from its own SPI flash. ZU19EG DONE should assert within 5 seconds of power-on.

---

## Phase 2 — JTAG Chain Verification

- [ ] **JTAG cable connected** — Xilinx Platform Cable USB II to JTAG header on PCIe bracket.

- [ ] **Vivado Hardware Manager auto-scan** — "Auto Connect" finds target. Expected devices
  in chain:

  | Position | Device      | IDCODE      | IR Length |
  |----------|-------------|-------------|-----------|
  | 1        | VU13P       | 0x14b79093  | 18        |
  | 2        | ZU19EG      | 0x147e5093  | 12        |

- [ ] **Both IDCODEs match expected values** — if either is wrong, note which device fails
  and check power to that device.

- [ ] **JTAG chain scan at 3 MHz and 10 MHz** — both frequencies pass without timeout.
  Failure at 10 MHz but not 3 MHz indicates a signal integrity issue on the JTAG chain
  (check series resistors, stubs, and cable length).

---

## Phase 3 — First Bitstream and LED Test

- [ ] **MVB (minimum viable bitstream) programmed via JTAG** — LED1 blinks at ~1 Hz.
  `DONE` pin on VU13P asserts (LED2 on board lights solid).

- [ ] **VU13P `INIT_B` behaviour confirmed** — `INIT_B` went low then high during
  configuration (verify from Hardware Manager status or scope if accessible).

- [ ] **VIO connected in Vivado Hardware Manager** — VIO probes readable; VIO output
  toggles GPIO1 and GPIO2 on PMOD header. Scope confirms both pins toggle correctly.

- [ ] **Internal oscillator frequency measured** — route internal STARTUPE2 clock to a
  countable output. Confirm approximately 65 MHz ±10% (device-dependent).

- [ ] **Current with MVB loaded:** expected 5–7A at 12V. Record: ________A

---

## Phase 4 — Clock Bring-Up

- [ ] **Si5341 clock synthesiser I2C communication** — ZU19EG PS I2C driver confirms device
  ACKs at address 0x74. Read device ID register; confirm `0x0341`.

- [ ] **Si5341 programmed with clock configuration** — load register map generated by
  ClockBuilder Pro. Confirm PLL lock bit set within 50 ms.

- [ ] **Reference clocks measured at FPGA inputs:**

  | Clock source      | Expected    | Measured    | BUFG locked |
  |-------------------|-------------|-------------|-------------|
  | SYSCLK0 (156.25M) | 156.250 MHz | ___________ | ___         |
  | SYSCLK1 (200 MHz) | 200.000 MHz | ___________ | ___         |
  | GTY ref (161.1M)  | 161.132 MHz | ___________ | ___         |
  | PCIe ref (100M)   | 100.000 MHz | ___________ | ___         |

- [ ] **VU13P MMCM0 lock** — test bitstream with MMCM0 generating 250 MHz and 125 MHz
  from SYSCLK0. `mmcm0_locked` probe on ILA: asserts within 100 µs of SYSCLK0 stable.

- [ ] **Frequency deviation check** — all measured frequencies within ±50 ppm of nominal.
  >±200 ppm indicates wrong crystal or incorrect Si5341 configuration.

---

## Phase 5 — DDR4 Bring-Up

### Per Memory Channel (Repeat for Channels 0–3)

- [ ] **MIG calibration passes** — `init_calib_complete` asserts for channel N within 5
  seconds of MIG reset deassertion.

- [ ] **Calibration report reviewed** — enable MIG debug output bitstream; read calibration
  tap values from status registers. All byte lanes show positive margin.

  Acceptance criteria: write levelling tap < 80% of maximum tap range on all byte lanes.
  If any byte lane uses >80% of tap range, flag for PCB layout review (trace length mismatch).

- [ ] **BIST test at 512 MB, 30 minutes:**
  - Pattern: alternating 0xAA55AA55 / 0x55AA55AA (catches bit-coupling faults)
  - Error count: 0 required for pass.
  - Record: ______ errors on Channel ______

- [ ] **Four-channel simultaneous BIST, 60 minutes** — all four channels active simultaneously.
  Error count: 0 on all channels. This tests power supply stability under full DDR4 load.

- [ ] **BIST at elevated temperature** — run 30-minute BIST with heat gun heating DRAM
  modules to approximately 70°C surface temperature (verify with thermocouple). Error
  count: 0 required.

---

## Phase 6 — Transceiver Bring-Up

### PCIe Gen4 x16

- [ ] **IBERT eye scan on PCIe reference clock lane** — confirm eye opening >300 mUI wide.

- [ ] **PCIe link trains at Gen1 x1** in test host. Device visible in `lspci` output.

- [ ] **PCIe link trains at Gen4 x16** — link status register shows:
  - Link width: 16
  - Link speed: Gen4 (16.0 GT/s)

- [ ] **PCIe DMA bandwidth test:**
  - Read bandwidth: >14 GB/s (theory 16 GB/s at Gen4 x16)
  - Write bandwidth: >14 GB/s
  - Latency (64B read): <1.5 µs

- [ ] **PCIe AER (Advanced Error Reporting) — zero errors** after 10 minutes of sustained
  transfer. `lspci -vvv` shows 0 correctable, 0 uncorrectable errors.

### 100G Ethernet (CMAC) — Per QSFP28 Port (0–5)

- [ ] **QSFP28 loopback module inserted** in port N.

- [ ] **CMAC PCS lock** — all 20 PCS lanes lock in internal loopback mode within 1 second
  of CMAC reset.

- [ ] **Line rate traffic test (internal loopback):**
  - Transmit 10M frames at 100G line rate.
  - RX FCS errors: 0
  - RX alignment errors: 0
  - Packet count match: TX == RX

- [ ] **External loopback test (loopback module)**:
  - Transmit 100M frames at 100G line rate.
  - RX FCS errors: 0
  - Confirm optical power reading from QSFP28 I2C status: TX power within ±3 dB of nominal
    for installed module.

- [ ] **BER measurement via IBERT on one lane of each CMAC port** — measure at nominal
  equalization settings for 10 seconds. BER < 1e-12 (zero errors in 10s at 25.78 Gbaud =
  ~2.5×10^11 bits transmitted).

---

## Phase 7 — Thermal and Power Qualification

- [ ] **XADC junction temperature at idle** — read via `get_hw_probes` in Hardware Manager
  or Linux HWMON driver. Record: VU13P Tj = ________ °C.

- [ ] **XADC junction temperature at full load** — load all DDR4 channels with BIST +
  all CMAC ports active + PCIe DMA running simultaneously:
  - VU13P Tj: ________ °C (pass criteria: <100°C at 25°C ambient)
  - DDR4 DRAM surface: ________ °C (pass criteria: <85°C at 25°C ambient)

- [ ] **Total board power at full load** — measure 12V input current × voltage:
  - Measured power: ________ W
  - Budgeted power: ________ W
  - Exceeds budget by more than 10%: raise flag for thermal design review.

- [ ] **Thermal shutdown test** — confirm that if ZU19EG board management firmware detects
  VU13P Tj > 110°C, it asserts power-off sequence within 500 ms. Test by simulating the
  threshold in firmware (do not actually heat to 110°C during bring-up).

---

## Phase 8 — Long-Run Soak

- [ ] **8-hour burn-in** — run all BIST and traffic patterns simultaneously for 8 hours at
  ambient temperature. Zero errors required on all channels.

- [ ] **Error log review** — read FPGA error registers, PCIe AER registers, and DDR4
  ECC registers at end of soak. All zero.

- [ ] **Post-soak supply measurements** — repeat all Phase 1 voltage measurements. Confirm
  all rails still within specification (checks for contact resistance changes, thermal drift
  in regulators).

---

## Pass/Fail Summary

| Phase                    | Board 1 Pass | Board 2 Pass | Board 3 Pass |
|--------------------------|-------------|-------------|-------------|
| 0 — Pre-power inspection | [ ]         | [ ]         | [ ]         |
| 1 — Bench power-on       | [ ]         | [ ]         | [ ]         |
| 2 — JTAG chain           | [ ]         | [ ]         | [ ]         |
| 3 — First bitstream      | [ ]         | [ ]         | [ ]         |
| 4 — Clock bring-up       | [ ]         | [ ]         | [ ]         |
| 5 — DDR4                 | [ ]         | [ ]         | [ ]         |
| 6 — Transceivers         | [ ]         | [ ]         | [ ]         |
| 7 — Thermal/power        | [ ]         | [ ]         | [ ]         |
| 8 — Soak test            | [ ]         | [ ]         | [ ]         |

**Acceptance criteria for design review:** minimum two boards must pass all phases. Any board
failing Phase 0 or Phase 1 is reworked before proceeding. Failures in Phases 4–8 that are
consistently reproduced across multiple boards indicate a PCB layout or schematic issue
requiring ECO. Single-board failures in Phases 4–8 may indicate an assembly defect.

---

## Common Failures and Diagnostic Shortcuts

| Symptom                           | First check                                    |
|-----------------------------------|------------------------------------------------|
| `DONE` does not assert            | Power sequencing, MODE pins, JTAG program test |
| JTAG chain shorter than expected  | Power to missing device, TDI/TDO swap          |
| DDR4 write-levelling failure      | PCB CK trace length, VDDQ voltage              |
| DDR4 read DQS failure             | ODT not enabled, DQS trace impedance           |
| PCIe link trains Gen1 not Gen4    | Reference clock quality, equalization settings |
| CMAC PCS unlock after linking     | TX/RX polarity swap on a lane, SFP optical power |
| VU13P Tj too high at idle         | Missing/inadequate heatsink, thermal pad not seated |
| Intermittent DDR4 ECC errors      | VDDQ margining, RDIMM DQ trace length mismatch  |
