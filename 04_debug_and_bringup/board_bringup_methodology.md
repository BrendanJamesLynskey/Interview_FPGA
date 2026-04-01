# Board Bringup Methodology

## Overview

Board bring-up is the process of verifying that a newly assembled PCB functions correctly,
progressing from bare-metal power-on through full system validation. For FPGA-based boards
this process is especially structured: the FPGA is both a subject of testing (it must configure
correctly) and a key instrument of testing (it can be programmed to run self-tests, generate
known signals, and monitor its own interfaces). A methodical, phased approach is essential —
rushing to run complex firmware before confirming power supply integrity and JTAG connectivity
wastes days and risks damaging hardware. This topic appears in interviews as a test of real-world
engineering judgment and experience.

---

## Fundamentals

### Question 1

**What is the overall phased structure of an FPGA board bring-up? What are the goals of each
phase?**

**Answer:**

Board bring-up is performed in a strict sequence, where each phase must pass before the next
begins. Skipping phases introduces compounding uncertainty — you cannot debug a logic failure if
you do not know whether the power rails are within specification.

**Phase 0 — Pre-power visual inspection (before applying any power):**

- Verify component orientation (FPGAs, flash, power ICs, crystals).
- Check for solder bridges on fine-pitch packages using microscopy or X-ray.
- Verify decoupling capacitor values and positions against BOM.
- Confirm pull-up/pull-down resistors on FPGA configuration mode pins match the intended
  configuration mode.
- Check fuse values, jumper positions, and any revision-tracking markings.

Goal: catch assembly errors before they damage components.

**Phase 1 — Bench power-up (current-limited):**

- Set bench power supply with current limit set 20–30% above expected idle current.
- Apply power with no bitstream loaded (FPGA in unconfigured state).
- Measure all supply rails: core voltage, I/O voltage, auxiliary voltages.
- Verify power-on sequencing order matches the device datasheet requirements.
- Confirm current draw is within expected idle range.

Goal: confirm power integrity before FPGA is exposed to full operation.

**Phase 2 — JTAG connectivity:**

- Connect JTAG cable; scan chain; verify all expected devices found by IDCODE.
- Confirm all device IR lengths correct (matching BSDL files).
- Program a simple test bitstream ("DONE blinker" — toggles an LED using an internal oscillator,
  no external clocks needed). Verify `DONE` asserts.

Goal: confirm JTAG path is functional and FPGA configures correctly.

**Phase 3 — Clock and oscillator verification:**

- Load a bitstream that routes external clock sources to observable outputs (e.g., route
  through a BUFG and toggle an output pin or feed an ILA).
- Measure clock frequencies with an oscilloscope or frequency counter.
- Bring up PLLs/MMCMs; confirm lock indicators assert.

Goal: confirm all oscillators are populated, operating at correct frequency, and reaching
FPGA inputs cleanly.

**Phase 4 — Memory interface bring-up:**

- Test DDR, QDR, HBM interfaces using Xilinx MIG (Memory Interface Generator) IP with its
  built-in traffic generator.
- Confirm calibration completes and BIST (built-in self-test) passes at full speed.

Goal: confirm memory is accessible at rated speed before any user design depends on it.

**Phase 5 — Peripheral and interface bring-up:**

- Test each interface (PCIe, Ethernet, UART, SPI, I2C, HDMI, etc.) individually using loopback
  or known-good test equipment.
- Use ILAs and VIOs to monitor interface handshakes.

Goal: validate each interface independently before integration.

**Phase 6 — Integrated system test:**

- Load the full system design.
- Run end-to-end functional tests.
- Profile power consumption at realistic workloads.
- Run thermal soak tests (if applicable to the application).

---

### Question 2

**What checks should be performed before applying power to a new FPGA board for the first time?**

**Answer:**

Pre-power checks fall into three categories: visual, electrical (passive), and documentation.

**Visual inspection checklist:**

- [ ] FPGA orientation correct (pin 1 marker aligned with schematic)
- [ ] BGA solder visible under component (X-ray or edge inspection where possible)
- [ ] No visible solder bridges on connector or fine-pitch component pins
- [ ] All electrolytic capacitors oriented correctly (positive to VCC)
- [ ] Crystals/oscillators present and in correct footprint orientation
- [ ] Configuration mode resistors (Xilinx M[2:0]) correct values and present
- [ ] JTAG header pin 1 correct; TDI/TDO not swapped
- [ ] Voltage regulators for correct output voltage marking

**Passive electrical checks (DMM, no power):**

- Measure resistance from each power rail to ground: should not be near 0 Ohm (short). A
  typical minimum resistance for a power rail is 10–50 Ohm before power-on.
- Check resistance from each supply to adjacent supplies: should be open or high impedance.
- Verify continuity of JTAG chain: TDO of one device to TDI of next.
- Check for open circuits on critical single-point connections (clock traces, reset).

**Documentation checks:**

- Confirm the bitstream is compiled for the exact device part number on the board (wrong
  package or speed grade causes configuration failure with cryptic errors).
- Confirm SPI flash is programmed with a valid bitstream if using master SPI boot mode
  (attempting to boot an erased or blank flash results in a continuous config attempt loop).
- Review the power sequencing requirements for the specific FPGA family and confirm the
  regulator enable sequencing circuit matches.

---

### Question 3

**What is power sequencing for an FPGA and why is it critical?**

**Answer:**

Power sequencing is the order in which multiple supply voltages are ramped up and down.
FPGAs require specific supply rails (core voltage, I/O voltage, auxiliary, transceiver
voltages, etc.) and the datasheet specifies which must come up first, which can be
simultaneous, and which must come down first during power-off.

**Why it matters:**

1. **Latch-up prevention:** if an I/O supply rail rises before the core supply, I/O pins may
   be driven by external signals while the core is unpowered. This can forward-bias internal
   ESD protection diodes, causing latch-up (a parasitic thyristor conduction that causes large
   destructive current flow). Latch-up can permanently damage the device.

2. **Undefined configuration state:** if the configuration memory supply is absent when core
   power is present, the device boots into an undefined state and may fail to configure or
   configure incorrectly.

3. **Phase-locked loop stability:** transceiver supply voltages (MGTAVCC, MGTAVTT) must be
   stable before the transceivers are released from reset.

**Example Kintex-7 power-up sequence (simplified):**

```
1. VCCINT (core, 1.0V)         ─── comes up first
2. VCCBRAM (BRAM supply, 1.0V) ─── simultaneous with VCCINT
3. VCCAUX (auxiliary, 1.8V)    ─── after VCCINT stable
4. VCCO_x (I/O banks, 1.8/2.5/3.3V) ─── after VCCAUX stable
5. MGTAVCC, MGTAVTT            ─── transceiver supplies, after core stable
```

Power-down is the reverse order.

**How to verify sequencing:**

Use an oscilloscope with multiple channels to capture all supply rails simultaneously with
a slow timebase (10–100 ms/div). Trigger on the enable signal and confirm each rail ramps
in the correct order. Most modern FPGA boards use a sequencer IC (e.g., UCD9000 series,
LTC2977) that enforces ordering; verify it is correctly configured.

---

## Intermediate

### Question 4

**Describe a "minimum viable bitstream" strategy for early bring-up. What should it do and
what should it avoid?**

**Answer:**

A minimum viable bitstream (MVB) is the simplest possible design that proves the hardware
path from JTAG programming through device configuration to observable output. Its purpose
is to eliminate all software and complex-design variables during the earliest bring-up phase.

**What it should do:**

1. **Toggle an LED** at a frequency visible to the human eye (~1 Hz) using an internal
   oscillator (e.g., the FPGA's internal ring oscillator / STARTUPE2 or a divided-down
   clock). This proves the device configured and internal clocking works without any external
   oscillator being present.

2. **Assert `DONE`** — Vivado will confirm this over JTAG, but a physical `DONE` LED on the
   board provides immediate visual confirmation.

3. **Drive mode-indicator outputs** — use GPIO outputs to signal which configuration mode
   was used (useful if multiple modes are possible on the board).

4. **Include a VIO** to allow toggling of any available debug GPIO pins from Vivado, verifying
   I/O bank connectivity without requiring additional firmware.

**What it should avoid:**

- Any PLL or MMCM that could prevent configuration completion if the source clock is absent
  (a locked check in the startup prevents DONE if PLL doesn't lock).
- Any external memory interfaces (DDR MIG calibration failure stops the design working).
- Any AXI infrastructure or complex IP that might have implementation issues.
- Any interfaces that require an external stimulus to not be idle/stalled.

**The rule:** the MVB should configure successfully and produce observable output on a completely
blank board (no external clocks, no SFPs, no DRAM populated) if possible. Add dependencies
incrementally as each one is verified.

**Implementation in Vivado:**

```vhdl
-- Minimum viable bitstream: blink an LED using internal oscillator
-- Uses STARTUPE2 primitive on 7-series for internal clock access
architecture rtl of mvb_top is
    signal clk_int   : std_logic;
    signal divider   : unsigned(23 downto 0) := (others => '0');
    signal led_state : std_logic := '0';
begin
    -- Use STARTUPE2 to access the configuration clock as a free-running source
    -- Alternatively use BUFG with a ring oscillator. Here we use STARTUPE2:
    u_startup : STARTUPE2
        generic map (PROG_USR => "FALSE", SIM_CCLK_FREQ => 0.0)
        port map (
            CLK => '0', GSR => '0', GTS => '0',
            KEYCLEARB => '1', PACK => '0',
            USRCCLKO => clk_int,   -- driven by internal osc
            USRCCLKTS => '0',
            USRDONEO => '1', USRDONETS => '0'
        );

    process(clk_int)
    begin
        if rising_edge(clk_int) then
            divider <= divider + 1;
            if divider = 0 then
                led_state <= not led_state;
            end if;
        end if;
    end process;

    led <= led_state;
end architecture rtl;
```

---

### Question 5

**You power up a new FPGA board for the first time. The DONE LED does not light up. Describe
your systematic diagnostic process.**

**Answer:**

`DONE` not asserting means the FPGA did not complete configuration. There are five categories
of root cause.

**Step 1 — Check power supplies (most common root cause).**

Measure each supply rail with a DMM:
- Is `VCCINT` present and within ±5% of nominal?
- Is `VCCAUX` present and within spec?
- Are `VCCO` banks at the correct voltage for their intended I/O standard?
- Are all supply rails sequenced in the correct order?

A missing or out-of-tolerance supply (especially `VCCAUX`) prevents configuration from starting.

**Step 2 — Check `INIT_B` behaviour.**

`INIT_B` should pulse low during the FPGA's internal power-on reset, then go high. If `INIT_B`
stays low, the device is stuck in reset — suspect `VCCAUX` absent, a strong external pulldown
on `INIT_B`, or a hardware issue on the device itself.

If `INIT_B` goes high but `DONE` never asserts, the device started configuration but failed.

**Step 3 — Check configuration mode.**

Scope or DMM-check the MODE pins. If they are incorrect (e.g., floating instead of pulled to
define master SPI mode), the device may be attempting slave serial mode and waiting for data
that never arrives, or attempting BPI mode when only SPI flash is present.

**Step 4 — Attempt JTAG programming.**

Connect JTAG cable and run "Open Hardware Manager → Auto Connect → Program Device" with the
bitstream `.bit` file directly. This bypasses the flash and eliminates flash-related failures.
- If JTAG programming succeeds and `DONE` asserts: the problem is in the flash (blank, wrong
  image, SPI timing, wrong mode pins for flash boot).
- If JTAG programming fails with CRC error: the bitstream file is wrong (wrong device target),
  or there is a signal integrity issue on the JTAG chain.
- If the device is not detected in JTAG scan: JTAG chain problem (power issue, bad TDI/TDO
  connection, device latch-up).

**Step 5 — Check JTAG chain if device not detected.**

- Confirm `VCCAUX` is present (JTAG TAP requires `VCCAUX`).
- Probe TDI at the device pin — is data reaching it?
- Probe TDO at the device pin — does it toggle during a scan?
- Check for shorts on JTAG lines to power or ground.

**Step 6 — Check bitstream target.**

Confirm the `.bit` or `.mcs` file was compiled for the exact device part number. A bitstream
compiled for XC7K325T will not configure an XC7K160T, and Vivado will report a device ID
mismatch error in the Hardware Manager output.

**Decision tree summary:**

```
DONE not asserted
│
├── INIT_B never went high → Check VCCAUX, PROG_B
├── INIT_B went high, device not in JTAG scan → Check JTAG chain, VCCAUX
├── Device in JTAG scan, JTAG program works → Flash problem (image, mode, timing)
├── Device in JTAG scan, JTAG program fails CRC → Wrong bitstream part, signal integrity
└── Device in JTAG scan, JTAG program times out → FPGA locked in boot loop, check PROG_B
```

---

### Question 6

**What is a board bring-up "blinky" and why is it considered best practice for every new board
design, even complex ones?**

**Answer:**

A "blinky" is the simplest possible test design — typically just toggling an LED at a visible
rate. It is universally recommended as the first test on any new board, regardless of the
system's ultimate complexity.

**Why it is best practice:**

1. **Binary pass/fail observable without instruments:** if the LED blinks, you know the device
   is powered, configured, and clocked. This single observation eliminates the most fundamental
   failure modes before any instruments are connected.

2. **No external dependencies:** a blinky using an internal oscillator (as described in
   Question 4) requires nothing external to work — no clock oscillator, no RAM, no peripheral.
   This means it can identify whether the FPGA itself and its power supplies are functional
   in complete isolation.

3. **Establishes the JTAG programming baseline:** successfully programming the blinky bitstream
   confirms that the JTAG chain, the host software, the cable, and the bitstream delivery flow
   all work. This is the foundation on which all subsequent testing depends.

4. **Separates hardware problems from design problems:** if the blinky works but the production
   bitstream does not, the problem is in the design or its dependencies, not in the board
   hardware. If the blinky does not work, there is a hardware issue to resolve first.

5. **Validates the board schematic/layout for the most basic paths:** a successful blinky means
   the FPGA package, solder joints, power delivery, and decoupling are sufficient for basic
   operation.

**Anti-pattern:** teams under schedule pressure sometimes skip the blinky and load the full
production design on first power-on. When this fails (as it often does), they have no baseline
and spend hours debugging whether the failure is a hardware issue, a configuration mode issue,
a PLL not locking, a memory calibration failure, or a logic bug. The blinky's 30-minute
investment saves days.

---

## Advanced

### Question 7

**You are leading the bring-up of a new FPGA board that includes an UltraScale+ FPGA, DDR4 SDRAM,
a 100G Ethernet MAC, and a PCIe Gen4 x16 slot. The board just arrived from the assembler. Walk
through your complete bring-up plan for the first week.**

**Answer:**

**Day 1 — Incoming inspection and passive checks.**

Before power: visual inspection (see Question 2). Check BGA profiles with X-ray. Verify BOM
compliance for critical components (core voltage, I/O voltage regulators, SFP+ cages, DDR4
DRAM part numbers and density).

Passive electrical: measure resistance of each supply rail to ground. Check JTAG chain
continuity. Verify PCIe connector signal integrity stubs are correctly terminated.

**Day 1 (afternoon) — First power-on.**

Use a bench supply with current limiting:
- Set limit to 1.5× the calculated idle current from the power estimator tool.
- Apply `VCCINT_IO` first (UltraScale+: 0.85V), then `VCCAUX`, then `VCCO` banks.
- Measure all rails under load. Check for unexpected current draw on any rail.
- Scope the power sequencer outputs to confirm ordering meets XAPP1233 requirements.

If current draw is within 20% of estimate: proceed. If significant overcurrent: power off,
investigate for shorts or wrong regulator output voltage.

**Day 2 — JTAG and first bitstream.**

- Scan JTAG chain: verify FPGA IDCODE, any on-board CPLDs or ARM DAP.
- Program the MVB (LED blinker + VIO). Verify `DONE` asserts, LED blinks.
- Use VIO to toggle GPIO outputs; scope them. Confirms I/O banks are functional.
- If board has a CPLD for configuration management, test CPLD JTAG and GPIO paths now.

**Day 3 — Clock and transceiver power bring-up.**

- Load a clock measurement bitstream: routes all clock inputs through `IBUFG`/`BUFG` to
  counters, readable via ILA or VIO.
- Verify all oscillator frequencies. Check for missing oscillators (blank frequency reading).
- Bring up MMCM/PLL blocks: confirm lock assertions within the expected lock time.
- Power up MGTAVCC, MGTAVTT (transceiver power rails). Verify voltages, confirm no
  thermal issues on transceiver tiles.
- Run IBERT on PCIe reference clock path to characterise the 100 MHz/156.25 MHz reference
  signal quality.

**Day 4 — DDR4 bring-up.**

- Load MIG IP with training bitstream. Run DDR4 calibration.
  - Check calibration status registers: `init_calib_complete` should assert.
  - If calibration fails: check DRAM address/command bus routing, check `CK`/`CKB`
    differential pair routing, verify pull-up/pull-down on ODT, CS, CKE.
- Run MIG BIST at 512 MB for 30 minutes. Verify zero errors.
- Run at both nominal and at `Tc=70C` (hot air gun on DRAM) to confirm thermal margin.

**Day 5 — PCIe Gen4 bring-up.**

- Insert board into PCIe Gen4-capable host (or test fixture with PCIe slot).
- Load a Xilinx PCIe DMA example design (XDMA or CIP).
- Confirm PCIe link trains (check link status register — width and speed).
- Start at Gen1 x1, then step to Gen4 x16.
- Run memory-mapped read/write loopback. Confirm error-free operation.
- If link does not train: check reference clock, check TX/RX pair orientation, check AC
  coupling capacitors on PCIe TX lanes.

**Day 6 — 100G Ethernet bring-up.**

- Load CMAC IP example design with internal loopback mode.
- Confirm all 10G lanes lock (PCS lock status bits).
- Run internal traffic generator/checker at line rate. Confirm zero FCS errors, zero
  alignment errors.
- Switch to external loopback (SFP+ loopback plug), repeat.
- Connect to known-good 100G test equipment, transmit test frames, confirm received correctly.

**Day 7 — Integration and thermal.**

- Load full production design with all IP active.
- Run end-to-end system test (board-specific test plan).
- Monitor XADC/System Monitor for junction temperature, VCCINT, VCCAUX readings under load.
- Confirm all temperatures within rated limits at ambient.
- Run 4-hour burn-in at elevated ambient (if thermal chamber available) to check for
  infant mortality and marginal components.

**Documentation during bring-up (important in interviews):**

Maintain a bring-up log noting: which tests passed/failed, measured values for each power rail,
IBERT eye opening measurements, DDR calibration margin data, and any deviations from expected
values. This log is essential when debugging failures in the field post-production.

---

### Question 8

**During DDR4 bring-up, the MIG calibration fails at the "Write Levelling" stage. What does
write levelling accomplish and what are the likely hardware causes of this failure?**

**Answer:**

**What write levelling accomplishes:**

DDR4 memory uses a fly-by topology for address, command, and clock signals, meaning the clock
(`CK`/`CKB`) reaches different DRAM chips at different times due to PCB trace length differences.
Write levelling compensates for this by adjusting the DQS strobe delay at the FPGA output to
align each DQS edge with the corresponding clock edge at each DRAM chip.

During write levelling, the DRAM enters write levelling mode (via MRS command). The FPGA sweeps
the DQS output delay and reads back a signal from the DRAM indicating whether DQS arrived
before or after `CK`. The MIG controller finds the transition point and sets the DQS delay
to the centre of the valid window.

**If write levelling fails, the DQS adjustment cannot find a valid calibration window. Causes:**

1. **Clock trace length mismatch too large:** if the fly-by clock skew between the FPGA and
   the farthest DRAM chip exceeds the DQS adjustment range (typically ±several UI), calibration
   cannot compensate. Check PCB trace lengths from the FPGA CK output to each DRAM chip `CK`
   input against the MIG-specified maximum skew budget (typically 200–400 ps).

2. **DQS trace length problem:** if a DQS trace has an extreme mismatch vs. its expected
   relationship to `CK`, write levelling finds no valid window. Verify DQS group trace lengths
   in the PCB layout versus the design constraints.

3. **Clock or DQS signal integrity:** insufficient amplitude, excessive crosstalk, or a PCB
   via stub resonance can cause the DRAM's write levelling feedback signal to be unreliable.
   Probe `CK`/`CKB` and `DQS`/`DQSB` at the DRAM side with a differential probe.

4. **Missing or wrong termination:** DDR4 requires on-die termination (ODT) enabled correctly.
   If the FPGA's ODT drive is not reaching the DRAM (open net, wrong drive strength), the DQS
   signal will ring and write levelling will fail.

5. **Power supply margining:** write levelling is sensitive to `VDDQ` (DRAM I/O power). If
   `VDDQ` is out of tolerance (should be 1.2V ±2%), signal margins shrink and calibration
   becomes unreliable. Measure `VDDQ` under active calibration load.

6. **Wrong DRAM part or MIG configuration:** if the MIG project was generated with a different
   DRAM speed grade or density than what is physically populated, calibration timing calculations
   will be incorrect. Verify the exact DRAM part number and regenerate MIG if needed.

**Diagnostic approach:**

Enable MIG's calibration debug bitstream option. This exposes detailed per-byte-lane calibration
status registers and the delay tap values found at each stage. These registers pinpoint exactly
which byte lane failed and at which delay tap value the calibration signal transitioned — allowing
comparison against the expected PCB delay budget.
