# JTAG and Boundary Scan

## Overview

JTAG (IEEE 1149.1) is the universal mechanism for programming, debugging, and testing FPGAs in
the field. Every FPGA family exposes a JTAG Test Access Port (TAP) that supports boundary scan,
device programming, and access to internal debug infrastructure. Understanding the JTAG state
machine, chain topology, boundary scan cells, and the ARM Debug Access Port (DAP) used in
Zynq-class SoC FPGAs is essential for board-level debug, production test, and embedded
firmware bring-up.

---

## Fundamentals

### Question 1

**Describe the JTAG TAP controller state machine. What are the key states and what happens in
each?**

**Answer:**

The TAP controller is a 16-state Moore FSM driven by TMS (Test Mode Select) on each rising edge
of TCK (Test Clock). TDI provides serial input and TDO serial output.

```
                         TMS=1
           ┌─────────────────────────────────────────┐
           ▼                                         │
     ┌──────────┐  TMS=0   ┌──────────┐   TMS=1  ┌──────────┐
──►  │Test-Logic│ ───────► │  Run-    │ ──────►  │  Select  │
     │  Reset   │          │ Test/Idle│           │ DR-Scan  │
     └──────────┘          └──────────┘           └──────────┘
      (TMS=1 ×5                                  TMS=0│  TMS=1│
       from any                                       ▼       ▼
       state)                               ┌──────────┐  ┌──────────┐
                                            │ Capture  │  │  Select  │
                                            │    DR    │  │ IR-Scan  │
                                            └──────────┘  └──────────┘
                                           TMS=0│  TMS=1│  (IR path mirrors
                                                ▼       ▼   DR path)
                                         ┌──────────┐ ┌──────────┐
                                         │  Shift   │ │  Exit1   │
                                         │    DR    │ │    DR    │
                                         └──────────┘ └──────────┘
                                          (data shifts
                                           TDI→TDO)
```

**Key states:**

| State             | Description                                                                  |
|-------------------|------------------------------------------------------------------------------|
| Test-Logic-Reset  | All test logic reset. Entered by holding TMS=1 for 5+ TCK cycles.            |
| Run-Test/Idle     | Idle state between operations. Some instructions (e.g., RUNBIST) execute here.|
| Select-DR-Scan    | Decision point: go to DR scan path or to Select-IR-Scan.                     |
| Capture-DR        | Parallel load of data into the selected DR shift register.                    |
| Shift-DR          | Serially shift data through TDI → shift register → TDO.                      |
| Update-DR         | Parallel unload of shifted data into the output latch (applies the data).     |
| Select-IR-Scan    | Entry to instruction register scan path.                                      |
| Shift-IR          | Load a new instruction into the IR. MSB exits TDO first.                      |
| Update-IR         | New instruction takes effect.                                                 |

**Critical detail:** In Shift-DR and Shift-IR, TDI is sampled on the rising edge of TCK and
TDO changes on the falling edge. This allows safe capture by the host on the subsequent rising
edge.

---

### Question 2

**What is boundary scan and what problem does it solve?**

**Answer:**

Boundary scan solves the problem of testing board-level interconnects (solder joints, traces,
connectors) that are inaccessible to bed-of-nails probes in modern fine-pitch and BGA assemblies.

Each I/O pin of a boundary-scan-capable device has a **boundary scan cell (BSC)** — a small
register with two modes:

1. **Capture mode:** the BSC samples the pin's actual logic state (input or output) and shifts
   this value out through the JTAG TDO chain.
2. **Update mode (EXTEST):** the BSC drives the pin from the shift register, overriding the
   device's normal function. This forces a known value onto board traces.

**What you can test:**

- **Stuck-at faults:** drive a pin to '0' and '1'; if the board neighbour always reads the same
  value, there is a stuck-at fault or short.
- **Net continuity (opens):** drive '1' on a net, verify all expected destinations read '1'.
- **Net shorts:** drive '0' on one net while driving '1' on adjacent nets; if an adjacent net
  reads '0', there is a bridge fault.
- **Device presence:** if a device in the JTAG chain fails to respond with its IDCODE, it may
  be missing, unpowered, or mis-oriented.

**Boundary scan chain:**

```
JTAG connector → Device A TDI → [BSCs] → Device A TDO → Device B TDI → ... → TDO → JTAG connector
```

All boundary scan cells of all devices in the chain form a single shift register during EXTEST.

---

### Question 3

**What are the mandatory JTAG instructions and what does each do?**

**Answer:**

IEEE 1149.1 mandates three instructions and recommends several others.

**Mandatory:**

| Instruction  | IR code (per BSDL) | Action                                                              |
|--------------|-------------------|----------------------------------------------------------------------|
| `BYPASS`     | All 1s            | Connects a single 1-bit bypass register between TDI and TDO. Allows other devices in chain to be reached with minimal shift length. |
| `EXTEST`     | All 0s            | Places boundary scan cells in drive mode. Used for board interconnect testing. |
| `SAMPLE/PRELOAD` | Device-specific | Captures current pin states without disturbing function; preloads initial values for EXTEST. |

**Commonly supported optional instructions:**

| Instruction  | Action                                                               |
|--------------|----------------------------------------------------------------------|
| `IDCODE`     | Shifts out the 32-bit device identification register (manufacturer, part, version). |
| `USERCODE`   | Shifts out a user-programmable 32-bit code (e.g., firmware version). |
| `INTEST`     | Applies test vectors to the device core logic via BSCs (internal test). |
| `RUNBIST`    | Executes an on-chip built-in self-test while in Run-Test/Idle.        |
| `HIGHZ`      | Forces all outputs to high-impedance. Useful for board isolation.     |
| `CLAMP`      | Holds outputs at values preloaded by SAMPLE/PRELOAD while bypassing. |

**Xilinx-specific extensions** (used by Vivado programmer):

- `USER1`–`USER4`: routes TDI/TDO to user-defined logic in the FPGA fabric (used by the debug
  hub to expose ILA/VIO cores).
- `CFG_IN`, `CFG_OUT`, `JSTART`, `JSHUTDOWN`: configuration instructions for programming the
  device over JTAG.

---

### Question 4

**What is the JTAG IDCODE register format? Why is it useful during board bring-up?**

**Answer:**

The IDCODE is a 32-bit register defined by IEEE 1149.1 with the following fields:

```
Bit 31–28: Version      (4 bits)  — device revision, set by manufacturer
Bit 27–12: Part number  (16 bits) — identifies the specific device
Bit 11–1:  Manufacturer (11 bits) — JEDEC manufacturer ID
Bit 0:     Fixed '1'   (1 bit)   — always 1, distinguishes IDCODE from BYPASS (all zeros)
```

**Example — Xilinx Kintex-7 325T:**

```
0x3671093
Bits 27-12: 0x3671 → XC7K325T part code
Bits 11-1:  0x049  → Xilinx JEDEC ID (0x049 = 73 decimal)
Bit 0:      1
```

**Why useful during board bring-up:**

1. **Chain verification:** read back IDCODE from all devices to confirm:
   - All expected devices are present and powered.
   - No device is missing (a missing device causes the chain to appear shorter — subsequent
     IDCODEs shift by one position).
   - Device orientation is correct (a backwards-inserted device with JTAG exposed will show a
     different or corrupted IDCODE).

2. **IR length calculation:** the IR length (needed for correct JTAG sequence generation) is
   device-specific and found in the BSDL file. Verifying the IDCODE first confirms you are
   talking to the right device before attempting programming.

3. **Version tracking:** the version field identifies die stepping, which matters for errata
   applicability.

**Tcl command in Vivado:**

```tcl
open_hw_manager
connect_hw_server -host localhost
open_hw_target
get_property IDCODE [get_hw_devices]
# Returns: 0x3671093 for XC7K325T
```

---

## Intermediate

### Question 5

**You have a JTAG chain with four devices (two FPGAs, one CPLD, one ARM debug component). The
programmer can see only two devices. What are the likely causes and how do you diagnose each?**

**Answer:**

A JTAG chain presents fewer devices than expected when the chain is broken between two devices.
The visible devices are those upstream of the break.

**Likely causes:**

| Cause                                         | Diagnosis                                                         |
|-----------------------------------------------|-------------------------------------------------------------------|
| Device unpowered or in power-down mode        | Measure VCC on the missing device; check power sequencing         |
| TCK, TMS, TDI, TDO signal integrity issue     | Scope the JTAG signals at the missing device's pins               |
| Incorrect IR length setting in tools          | Use auto-scan/auto-detect in Vivado or OpenOCD                    |
| TDO of device N not connected to TDI of N+1  | Check schematic and continuity with DMM                           |
| Device in hard reset (TRST asserted)          | Check TRST net — if pulled low permanently, TAP stays reset       |
| JTAG pins overridden by device mode pins      | On Xilinx, MODE pins select JTAG vs other boot modes; verify settings |
| Device has JTAG disabled (fused off)          | Check device-specific security/fuse documentation                 |

**Systematic diagnosis:**

1. Confirm TCK reaches the missing device with a scope — verify frequency and signal quality.
2. Confirm TDI reaches the device: inject a known pattern on TDI and probe with a scope.
3. Confirm TDO from the missing device: probe TDO output and see if it toggles when shifting
   data through the chain.
4. If TDO is stuck, the device TAP is non-functional. Check power, reset state, and JTAG pin
   muxing.
5. Insert a BYPASS-only scan (all TMS=1 to reset, then load all-1s instruction, shift 10 bits,
   count delay from TDI to TDO) to determine the physical length of the working chain.

---

### Question 6

**What is the ARM Debug Access Port (DAP) and how does it relate to JTAG in a Zynq or Zynq
UltraScale+ device?**

**Answer:**

The ARM DAP is the debug infrastructure defined by the ARM Debug Interface Architecture (ADIv5/v6).
It sits behind the JTAG TAP on ARM-based devices and provides structured access to internal
debug resources.

**DAP components:**

```
JTAG TAP
    │
    ▼
┌──────────────────────────────────────────┐
│              Debug Access Port (DAP)      │
│  ┌─────────────────────────────────────┐ │
│  │   JTAG-DP (or SWJ-DP for SWD)      │ │  ← TAP to DP bridge
│  └────────────────┬────────────────────┘ │
│                   │  AP bus              │
│    ┌──────────────┼──────────────────┐   │
│    ▼              ▼                  ▼   │
│  MEM-AP         MEM-AP           JTAG-AP │  ← Access Ports
│ (Cortex-A)    (Cortex-R5)      (CoreSight│
│                                  ETM/CTI)│
└──────────────────────────────────────────┘
```

**In Zynq-7000:**

The processing system (PS) ARM Cortex-A9 cores expose their debug resources through a DAP that
shares the same JTAG TAP as the PL (programmable logic / FPGA). Vivado's hardware manager and
debuggers like Xilinx System Debugger (XSDB) both access resources through this DAP.

**MEM-AP:** provides memory-mapped access to the Cortex-A9 debug registers, allowing a debugger
to halt the CPU, read/write registers, set breakpoints, and single-step — all over JTAG without
a trace cable.

**Practical implication during bring-up:** if you need to debug both PL logic (via ILA) and PS
firmware (via XSDB) simultaneously, Vivado's Hardware Manager and SDK/Vitis share the JTAG
connection through the DAP. They use separate AP addresses, so simultaneous use is possible but
requires using Vivado as the JTAG server (via `connect_hw_server`) and pointing Vitis to the
same server rather than opening competing JTAG connections.

---

### Question 7

**What is boundary scan description language (BSDL) and why is it needed?**

**Answer:**

BSDL (Boundary Scan Description Language) is a standardised subset of VHDL that describes a
device's JTAG implementation. Every JTAG-compliant device should have a manufacturer-supplied
BSDL file. It specifies:

- **IR length:** how many bits the instruction register is.
- **IR capture value:** what the IR captures during Capture-IR (used to verify correct JTAG
  communication).
- **Mandatory instruction codes:** the bit patterns for BYPASS, EXTEST, SAMPLE/PRELOAD, IDCODE.
- **Optional instruction codes:** device-specific codes and the data registers they select.
- **Port mapping:** which package pins are TDI, TDO, TCK, TMS, TRST, and which are I/O with
  boundary scan cells.
- **BSC descriptions:** for each I/O pin, the cell type (input, output, bidirectional), cell
  index in the chain, and safe values for EXTEST.

**Why it is needed:**

1. **JTAG chain configuration:** automated test equipment (ATE) and JTAG programmers need IR
   lengths to correctly position instructions in a multi-device chain. A chain with three devices
   having IR lengths 6, 10, and 5 requires 21 bits to address all three IRs simultaneously.

2. **Board test generation:** BSDL files are parsed by boundary scan test tools (e.g., XJTAG,
   Goepel, Corelis) to automatically generate test vectors for interconnect testing.

3. **Device identification:** the BSDL-specified IDCODE value is compared against what the
   device returns to confirm device identity and correct BSDL file selection.

**Finding BSDL files:** available from the device manufacturer (e.g., Xilinx/AMD support pages,
packaged with Vivado under `<install_dir>/data/bsdl/`).

---

## Advanced

### Question 8

**Describe the JTAG programming flow for a Xilinx FPGA. What instructions are used and in what
order? What is the difference between direct JTAG configuration and SPI indirect programming?**

**Answer:**

**Direct JTAG configuration (to volatile SRAM configuration memory):**

This programs the FPGA's internal configuration cells directly. The bitstream goes into the
device but is lost on power cycle.

Instruction sequence (Xilinx 7-series, simplified):

```
1. JSHUTDOWN    — gracefully shut down current configuration (if device was configured)
2. CFG_IN       — select the configuration input register as the active DR
   + Shift in: CFG_IN data packet → SYNC word (0xAA995566) + configuration data
3. JSTART       — clock the startup sequence (activates the newly loaded configuration)
   + Run-Test/Idle for required startup cycles (device-specific, typically 12 TCK)
4. BYPASS       — return to safe state
```

**SPI indirect programming (to non-volatile SPI flash via JTAG):**

The FPGA acts as an intermediary — you use JTAG to control the FPGA's SPI master, which in turn
writes the bitstream into the attached SPI flash. The FPGA is not directly configured by this
operation; it uses the flash for the next power-on boot.

```
1. Program FPGA with a small "indirect programming" bitstream (jtagspi_init.bit or equivalent)
   — this loads a minimal configuration that exposes the SPI flash interface to JTAG.
2. JTAG USER1 instruction → access the virtual JTAG interface inside the partial config.
3. Send SPI flash write-enable and erase commands through the virtual JTAG → SPI bridge.
4. Stream the full production bitstream as SPI data → flash write cycles.
5. Power-cycle or send CFG_IN with IPROG command to trigger a reload from flash.
```

**Comparison:**

| Aspect                  | Direct JTAG (CFG_IN)          | SPI Indirect                       |
|-------------------------|-------------------------------|-------------------------------------|
| Speed                   | Moderate (~1–5 Mb/s)          | Slower (limited by flash write)     |
| Persistence             | Volatile (lost on power-off)  | Non-volatile (survives power cycle) |
| Complexity              | Simple, single step           | Requires intermediate bitstream     |
| Use case                | Debug/test iteration          | Production flash programming        |
| Requires flash hardware | No                            | Yes                                 |

**Key point:** the `write_bitstream` + "Program Device" in Vivado Hardware Manager handles all
of this automatically. Understanding the underlying instruction sequence is important for
scripted programming, custom test harnesses, and debugging programming failures.

---

### Question 9

**A production test fixture programs 20 FPGAs in a daisy-chained JTAG chain. Programming
takes 45 seconds and sometimes fails on device 12 with a CRC error mid-stream. How would you
diagnose and fix this?**

**Answer:**

A CRC error during configuration indicates that the bitstream data received by the device does
not match the CRC appended by the bitstream generator. In a long JTAG chain, this has specific
causes.

**Diagnosis steps:**

**1. Isolate whether it is data corruption or chain integrity.**

Run IDCODE scan before and after programming attempt. If the IDCODE scan passes (all 20 devices
present) but CRC fails at device 12, the physical chain is intact — the corruption occurs during
data transmission.

**2. Characterise the failure pattern.**

- Does it always fail at the same bit position in device 12's bitstream, or at a random position?
- Consistent bit position → suggests signal integrity issue (reflections, crosstalk) on a
  specific chain segment.
- Random position → suggests a timing margin issue (TCK rate too high for the chain length or
  signal levels).

**3. Measure signal integrity at device 12's TDI pin.**

In a 20-device chain, TDI of device 12 has already passed through 11 TDO→TDI junctions plus
PCB traces. Each stage adds propagation delay and may reduce signal amplitude.

Scope TDI at device 12 during active programming:
- Check for undershoot, overshoot, ringing, or slow edges.
- Verify voltage levels meet the device's input threshold (typically 0.8V for '0', 2.0V for
  '1' on a 3.3V LVCMOS device).

**4. Check JTAG cable driver strength and termination.**

Long JTAG chains benefit from series resistors on TDO outputs (typically 33–47 Ohm) to damp
reflections. Verify that devices 1–11 have appropriate output drive strength settings.

**5. Reduce TCK frequency.**

Drop from the current programming frequency (e.g., 10 MHz) to 1 MHz or lower. If failures
disappear, the chain has a timing margin problem, not a connectivity problem. The fix is either
a lower programming frequency, signal re-conditioning, or chain splitting with a hub.

**6. Split the chain.**

If signal integrity cannot be fixed at the current chain length, split the 20-device chain into
two 10-device chains with separate JTAG headers. This halves the chain capacitance and reduces
the driver loading on each segment.

**7. Check for thermal effects.**

If failures occur after the fixture has been running for minutes but not on cold-first power-on,
check whether device 12's junction temperature is rising enough to cause signal margining at the
I/O. This can happen if devices near the fixture power supply are running hot.

**Root cause summary:** most intermittent JTAG CRC failures in long chains are caused by either
excessive TCK frequency for the chain's cumulative signal degradation, inadequate termination,
or insufficient drive strength on intermediate TDO outputs.

---

### Question 10

**Explain how Virtual JTAG (USER1/USER2 instructions) works and describe a practical use case
for it beyond standard ILA/VIO debug.**

**Answer:**

Xilinx devices implement four JTAG USER instructions (`USER1`–`USER4`). When any of these is
loaded into the TAP's IR, the JTAG DR path (TDI→TDO shift data) is routed into the FPGA fabric
rather than to a standard device register.

Inside the fabric, the `BSCAN` primitive captures this connection:

```vhdl
-- VHDL: instantiate BSCAN to receive USER1 JTAG data
BSCAN_7SERIES_inst : BSCAN_7SERIES
    generic map (JTAG_CHAIN => 1)  -- USER1
    port map (
        TCK    => jtag_tck,    -- TCK routed into fabric
        TMS    => open,        -- TMS not directly available in fabric
        TDI    => jtag_tdi,    -- serial data in from host
        TDO    => jtag_tdo,    -- serial data out to host
        SEL    => jtag_sel,    -- high when USER1 instruction active
        SHIFT  => jtag_shift,  -- high during Shift-DR state
        UPDATE => jtag_update, -- pulses at Update-DR
        CAPTURE=> jtag_capture,-- pulses at Capture-DR
        RESET  => jtag_reset,  -- TAP reset
        RUNTEST=> jtag_runtest  -- high in Run-Test/Idle
    );
```

**The Vivado Debug Hub uses this mechanism** — all ILA/VIO traffic travels through USER1 or
USER2 via the automatically-instantiated `dbg_hub` which internally uses `BSCAN`.

**Practical use case: custom in-system software update mechanism.**

In a safety-critical industrial system where a dedicated UART or Ethernet is not available, you
can implement firmware update over JTAG using Virtual JTAG:

1. Implement a simple 8-bit parallel interface in the FPGA fabric, connected to the BSCAN
   primitive. The fabric accumulates serial bits into bytes, writes bytes to a FIFO, and
   streams the FIFO to a SPI controller that writes the update image to flash.

2. On the host (test fixture or field service tool), write a Tcl script or compiled tool that:
   - Opens a Vivado Hardware Manager connection.
   - Loads USER1 instruction via JTAG.
   - Shifts the firmware binary in byte-by-byte, monitoring a `READY` status bit in the
     Capture-DR data.

3. After transfer completes, pulse a `COMMIT` signal via a VIO to trigger the bootloader to
   validate and apply the image.

This requires no dedicated debug pins beyond JTAG, no firmware running on the device to be
updated (the FPGA fabric handles all the transport logic), and works on an otherwise locked-down
production board with only a JTAG header exposed.
