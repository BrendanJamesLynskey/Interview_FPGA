# Quiz: FPGA Debug and Bringup

## Instructions

15 multiple-choice questions covering ILA (Integrated Logic Analyser), VIO (Virtual I/O),
JTAG and boundary scan, bitstream configuration, and board bringup methodology. Select the
single best answer for each question. Detailed explanations follow each answer in the
Answer Key section.

Difficulty distribution: Q1–Q5 Fundamentals, Q6–Q10 Intermediate, Q11–Q15 Advanced.

---

## Questions

### Q1

What is the primary function of an Integrated Logic Analyser (ILA) core in an FPGA design?

A) It replaces a hardware oscilloscope by routing internal signals to an external probe connector.  
B) It captures internal FPGA signals into on-chip BRAM, triggered by user-defined conditions, and makes them available for inspection over JTAG in the host tool.  
C) It inserts timing assertions between flip-flops to verify setup and hold margins at runtime.  
D) It intercepts AXI transactions between IP cores and logs them to the host PC in real time.  

---

### Q2

A VIO (Virtual I/O) core provides which capabilities in a Vivado hardware debug session?

A) It allows the host PC to read logic analyser waveforms in real time at the full FPGA clock frequency.  
B) It provides software-controllable probe inputs (to drive signals in the FPGA) and probe outputs (to read back signal values) over the JTAG interface at low speed.  
C) It streams captured data to the host via a high-speed USB 3.0 link, bypassing the JTAG bottleneck.  
D) It enables partial reconfiguration of individual LUTs without a full bitstream reload.  

---

### Q3

In a JTAG chain containing three devices (Device 1 → Device 2 → Device 3, from TDI to TDO),
what happens if Device 2 fails to respond to the JTAG scan?

A) Devices 1 and 3 continue to operate normally in the JTAG chain.  
B) Device 3 becomes unreachable via JTAG because its TDI input is fed from Device 2's TDO, which is now undefined.  
C) The JTAG master automatically reroutes around Device 2.  
D) Vivado automatically removes Device 2 from the chain configuration.  

---

### Q4

What does an FPGA bitstream file contain?

A) The HDL source code of the design in compiled form.  
B) The synthesised netlist in EDIF format.  
C) Configuration data that programs every LUT, flip-flop, routing mux, BRAM content, and I/O setting in the FPGA fabric.  
D) A binary executable for the MicroBlaze soft processor included in the design.  

---

### Q5

During initial board bringup, an FPGA fails to configure from a flash memory device on the
PCB. The DONE pin does not go high. What is the correct first step in the debug process?

A) Immediately re-synthesise the design with different settings and load a new bitstream.  
B) Check the configuration mode pins (M[2:0]) on the FPGA to verify they are strapped correctly for the intended configuration mode (e.g., SPI, BPI, JTAG).  
C) Replace the FPGA with a known-good device.  
D) Increase the SPI flash clock frequency to ensure the FPGA can read the bitstream before the power supply sags.  

---

### Q6

An ILA is set up to trigger on a specific AXI signal going high. The trigger fires correctly
in simulation but never fires in hardware. The design is running. What are the two most likely
causes?

A) The ILA sample depth is too small to capture the event; and the AXI signal is too fast for the ILA to sample.  
B) The trigger condition is in a different clock domain from the ILA core's clock; and the signal being probed was optimised away during synthesis.  
C) The JTAG cable has insufficient bandwidth to arm the trigger; and the bitstream was generated with debug probes disabled.  
D) The ILA consumes too much BRAM, causing a routing failure; and the trigger threshold is set to a signed value when the signal is unsigned.  

---

### Q7

When probing a signal with an ILA, the signal must be marked with the `(* MARK_DEBUG = "true" *)`
attribute (or the equivalent `set_property MARK_DEBUG true` XDC constraint). What happens if
this attribute is NOT applied and the signal is connected to an ILA probe during IP Integrator
block diagram debug insertion?

A) Synthesis will remove (optimise away) the signal during constant propagation or dead code
   elimination, and the ILA probe will observe a constant value or behave unexpectedly.  
B) The signal is probed correctly — MARK_DEBUG is optional and only affects simulation.  
C) Vivado will issue an error and refuse to generate the bitstream.  
D) The signal is duplicated, causing double the FPGA resource usage.  

---

### Q8

A boundary scan test (BST / JTAG IEEE 1149.1) is run on a populated PCB with an FPGA and
several other ICs. The test reports that a particular net shows a "stuck-at-0" fault. What
does this most likely indicate?

A) A timing violation on the net caused by an incorrect PCB impedance mismatch.  
B) A short circuit to ground on the PCB net (solder bridge, damaged trace, or component pin
   shorted to a ground plane), or a damaged output driver in one of the ICs.  
C) The FPGA I/O standard for that pin is incorrectly set to LVCMOS18 instead of LVCMOS33.  
D) The boundary scan test was not run at the correct scan frequency and the result is invalid.  

---

### Q9

A design is programmed into an FPGA using JTAG. The FPGA configures successfully (DONE goes
high) but the design appears to behave incorrectly — clocks are running but logic outputs are
wrong. An ILA captures some signals. What should be checked first using the timing tools
before suspecting a hardware bug?

A) The power supply voltage on VCCINT — if it is marginally low, LUT delays increase and
   timing may fail at speed.  
B) Whether the bitstream corresponds to the current RTL source — the project may have been
   built from an out-of-date netlist.  
C) Whether any timing violations exist in the implementation reports — unresolved setup
   violations can cause exactly this symptom.  
D) All of the above are valid first checks and should be examined together.  

---

### Q10

In Vivado Hardware Manager, an ILA is armed with the trigger condition:
`probe0[7:0] == 8'hAA`. After several seconds, the trigger status shows "WAITING FOR TRIGGER"
continuously. The design is actively processing data. What is the most useful next debug step?

A) Increase the ILA sample depth to 65536 samples to capture the event.  
B) Add a second ILA with a simpler trigger (`probe0[0] == 1'b1`) to verify that the probe
   is connected to a toggling signal, and check the trigger comparator value against the
   actual data range in simulation.  
C) Reload the bitstream and re-arm the trigger.  
D) Reduce the FPGA clock frequency to give the ILA more time to detect the trigger condition.  

---

### Q11

A designer is debugging an FPGA that intermittently locks up after several hours of operation.
The ILA is not helpful because the lockup is not related to a specific signal going high —
the design simply stops producing output. Which debug approach is most appropriate?

A) Connect a logic analyser to the FPGA output pins and run until the lockup occurs.  
B) Use a VIO to periodically read back key state registers (FSM state, counter values,
   status flags) over JTAG, and log them to the host PC so that the last known state before
   lockup can be examined.  
C) Re-run the design in simulation for several million clock cycles to reproduce the lockup.  
D) Replace the FPGA with a Zynq device so that a software debugger can be used.  

---

### Q12

A bitstream is generated for an Xilinx XCKU5P (UltraScale+) but the Vivado Hardware Manager
shows "IDCODE mismatch" when attempting to program the device via JTAG. What does this indicate?

A) The bitstream was encrypted with a key that does not match the device's eFUSE key.  
B) The bitstream was generated targeting a different FPGA part number (or the incorrect device
   was selected in the project), and the bitstream header's expected device ID does not match
   the actual silicon ID scanned from the JTAG chain.  
C) The JTAG cable is faulty and cannot correctly scan the device ID register.  
D) The device requires a signed bitstream and the current bitstream is unsigned.  

---

### Q13

A design uses partial reconfiguration (PR). After loading the full (static) bitstream and
then loading a partial bitstream for a reconfigurable module (RM), the static logic continues
to function but the RM behaves incorrectly. What is the most likely cause?

A) Partial reconfiguration is not supported over JTAG — the partial bitstream must be loaded via SelectMAP.  
B) The partial bitstream was generated targeting the wrong reconfigurable partition or with
   an incompatible static image, causing resource misalignment between the PR region and
   the static context.  
C) The FPGA's global set/reset (GSR) was triggered by loading the partial bitstream, resetting
   all static registers.  
D) Partial reconfiguration requires the FPGA to be power-cycled between the static and partial
   bitstream loads.  

---

### Q14

During board bringup of a new design with multiple voltage rails, the FPGA powers up but
several I/O signals are observed toggling at an unexpected frequency on an oscilloscope.
The unexpected oscillation is only on outputs that drive high-capacitance PCB traces. What
is the most likely cause and the first thing to check in the XDC file?

A) The IOSTANDARD is set to LVDS instead of LVCMOS, causing oscillation due to the differential
   driver fighting a single-ended load.  
B) The SLEW rate is set to FAST on those outputs, causing overshoot and ringing on the high-capacitance
   traces that is large enough to cross the input threshold of downstream devices and appear
   as spurious transitions. Setting SLEW to SLOW or adding series resistors are the usual fixes.  
C) The DRIVE strength is set too low, causing the output to not fully swing to VCCO, which the
   downstream device interprets as oscillation.  
D) The KEEPER constraint is set on those pins, causing them to actively fight the external driver.  

---

### Q15

A high-speed 10 Gbps serial link using a GTH transceiver does not achieve link training (the
CPLL or QPLL does not lock, or the RX CDR does not lock). The reference clock is confirmed
present and within specification. What is the correct debug sequence for this transceiver link
failure?

A) Check QPLL/CPLL lock outputs in hardware, verify the PRBS pattern generator/checker
   for bit errors, use the Eye Scan feature (UltraScale IBERT) to visualise the received eye
   diagram, and confirm the PCB differential trace length matching and termination.  
B) Reload the bitstream — transceiver links always recover after a bitstream reload.  
C) Reduce the line rate to 1 Gbps to verify connectivity, then increase in steps until failure.  
D) Replace the physical cable/connector — serial link failures at 10 Gbps are always caused
   by signal integrity issues in the physical medium.  

---

## Answer Key

### A1: B

The ILA is Xilinx's on-chip logic analyser. It consists of a trigger comparator, a capture
controller, and a sample BRAM. When the trigger condition is matched, it captures a
configurable window of signal samples (pre- and post-trigger) into the BRAM. The Vivado
Hardware Manager reads this data over JTAG and displays a waveform. This is invaluable for
debugging design behaviour in real hardware, where external probing is impossible on
BGA-packaged signals.

*Why A is wrong:* the ILA uses BRAM, not a probe connector. Signals are captured internally —
there is no external probe.  
*Why C is wrong:* the ILA does not perform timing assertions; that is the role of timing
analysis (STA). Timing assertions are a simulation/formal verification concept.  
*Why D is wrong:* the ILA can probe AXI signals, but it does not intercept or log transactions
in the protocol sense. It captures raw signal values at the configured probe points.

---

### A2: B

The VIO core provides two types of probes: output probes (host → FPGA) allow the user in
Vivado Hardware Manager to write values to signals inside the FPGA (e.g., force a reset,
drive a control register), and input probes (FPGA → host) allow reading back signal states.
Both operate over JTAG at low speed (milliseconds to read/write). This makes VIO ideal for
runtime control and status monitoring without rebuilding the design.

*Why A is wrong:* the VIO reads signals at JTAG polling speed (tens of milliseconds per
read), not at the FPGA clock frequency. Full-speed waveform capture is the ILA's function.  
*Why C is wrong:* both ILA and VIO communicate over JTAG — there is no USB 3.0 bypass path
in standard Xilinx debug IP.  
*Why D is wrong:* partial reconfiguration of LUTs requires a full partial bitstream load —
it is not achievable via VIO probes.

---

### A3: B

JTAG is a serial chain. TDO of each device feeds TDI of the next. If Device 2 fails (its
TDO is undefined or stuck), the shift register chain is broken. Device 3's TDI receives
garbage, making it impossible for the JTAG master to shift valid instruction or data registers
through Device 3. Device 1 remains accessible only if the JTAG controller can scan just up to
Device 2. In practice, most JTAG controllers lose access to ALL devices after the broken one.

*Why A is wrong:* Device 3 becomes unreachable — Device 1 may still be accessible but Device
3's TDI input is corrupted.  
*Why C is wrong:* JTAG has no automatic re-routing. The chain is physically fixed on the PCB.  
*Why D is wrong:* Vivado discovers the chain dynamically — it does not modify the chain
topology. If a device is unresponsive, Vivado will report a "JTAG chain broken" or similar
error.

---

### A4: C

A bitstream is a binary file that fully specifies the configuration of every programmable
element in the FPGA: the truth table contents of every LUT, the reset/preset state of every
flip-flop, the routing multiplexer settings of the interconnect fabric, the BRAM initial
contents, and the I/O cell settings (IOSTANDARD, drive strength, etc.). Loading a bitstream
is what "programs" an FPGA and makes it perform the intended design function.

*Why A is wrong:* HDL source code is text — the bitstream is binary and bears no resemblance
to HDL.  
*Why B is wrong:* the EDIF netlist is an intermediate synthesis output file, not a bitstream.
It describes connectivity, not the physical programming.  
*Why D is wrong:* MicroBlaze ELF executables are either stored in BRAM (embedded in the
bitstream via initialisation) or loaded separately from external memory. The bitstream itself
is not an executable.

---

### A5: B

Configuration mode pins (M[2:0] on Xilinx devices) must be strapped to the correct voltage
levels on the PCB to select the boot source (SPI flash, BPI flash, JTAG, SD card, etc.). An
incorrect strapping means the FPGA will attempt to boot from the wrong source or in an invalid
mode, and will never assert DONE. This is by far the most common cause of first-boot failures
on new boards and should always be the first thing checked.

*Why A is wrong:* re-synthesising the design is premature — if the bitstream never loads, the
RTL is not the issue.  
*Why C is wrong:* replacing the FPGA is a last resort, not a first step. Most bringup failures
are PCB or configuration issues.  
*Why D is wrong:* during initial bringup, increasing the clock frequency is counterproductive.
FPGA configuration interfaces have defined maximum clock rates; exceeding them can cause
configuration failure, not fix it.

---

### A6: B

Two common causes for an ILA trigger that fires in simulation but not hardware: (1) The ILA
core's clock input must be in the same clock domain as the probed signals — if the trigger
probe is driven by logic in a different clock domain, the ILA may never see the transition
in the correct phase. (2) Synthesis optimisation (particularly with `OPT_LEVEL` set high)
can eliminate internal signals that are not driving outputs or MARK_DEBUG-flagged, making
the probed net a constant value in the implemented netlist.

*Why A is wrong:* sample depth affects how much data is captured AFTER the trigger, not
whether the trigger fires. ILA operates at the full FPGA clock rate — it is not bandwidth-limited
for normal data rates.  
*Why C is wrong:* JTAG bandwidth affects data readback speed, not trigger arming. The trigger
arms immediately after the bitstream loads and the run command is issued.  
*Why D is wrong:* BRAM consumption could cause routing failure at implementation time (which
would be caught before generating a bitstream), not at trigger time in a running design.

---

### A7: A

Without `MARK_DEBUG`, a net that is not connected to any output port, BRAM, or other
sink that the synthesiser considers "visible" may be eliminated by dead-code elimination or
constant propagation. When an ILA probe is connected to such a net in a block diagram
without the attribute, the synthesiser may have already removed the driver, and the ILA will
observe a tied-off constant. `MARK_DEBUG` tells the synthesiser to preserve the net
explicitly so it reaches the ILA probe input.

*Why B is wrong:* MARK_DEBUG is absolutely required for synthesis to preserve the net. It is
not optional in synthesised designs.  
*Why C is wrong:* Vivado does not error out on missing MARK_DEBUG — it silently produces a
probe that may be constant or behave unexpectedly, which is more dangerous than an error.  
*Why D is wrong:* MARK_DEBUG does not duplicate the signal. It only prevents it from being
removed by optimisation.

---

### A8: B

A "stuck-at-0" fault in boundary scan means that the net was driven to '0' and could not be
driven to '1', or vice versa. The most common physical causes are: a solder bridge to a
ground plane, a damaged PCB trace that is shorted to ground, a damaged IC pin with a failed
output driver, or an incorrect pull-down resistor. Boundary scan applies drive and observe
stimuli to every pin in the chain, so this type of fault is detected with high confidence.

*Why A is wrong:* impedance mismatch causes ringing and reflection on high-speed signals,
not a logical stuck-at fault.  
*Why C is wrong:* an incorrect IOSTANDARD setting would affect signal levels and drive
strength, but boundary scan applies its own driver from the BSR cell — it would still observe
the stuck fault if a physical short exists.  
*Why D is wrong:* boundary scan operates at low frequency (kHz range for scan shifts) — scan
frequency issues do not produce stuck-at faults.

---

### A9: D

All three of the listed checks are legitimate and important first steps when a correctly
configured FPGA shows wrong functional behaviour:
- VCCINT marginal voltage increases LUT propagation delays, causing timing failures at speed.
- An out-of-date bitstream is extremely common in iterative debug sessions.
- Unresolved setup timing violations in the implementation reports will manifest as
  intermittent or consistent functional errors, especially at the target clock frequency.

In a real debug session, these three checks take less than five minutes combined and collectively
cover the most common causes of "design configured but behaves incorrectly."

*Why A alone is wrong:* correct, but incomplete.  
*Why B alone is wrong:* correct, but incomplete.  
*Why C alone is wrong:* correct, but incomplete.

---

### A10: B

When an ILA never triggers despite active data, the first hypothesis is that the trigger
condition is never true in the hardware — either the probe is connected to a signal that is
not what you think it is, or the actual data never takes the value 0xAA. The best approach
is to simplify the trigger to catch ANY activity on the probe (e.g., check if probe0[0]
toggles at all), and cross-reference with simulation to understand the actual data range.
If the probe never changes, `MARK_DEBUG` or connectivity is the issue. If it changes but
never reaches 0xAA, the logic is correct but the value does not occur.

*Why A is wrong:* sample depth determines how much is captured AFTER the trigger — it has
no effect on whether the trigger fires.  
*Why C is wrong:* reloading the bitstream is a last resort; it does not address the root cause.  
*Why D is wrong:* the ILA captures data synchronously with the FPGA clock. Reducing the
FPGA clock would not give the ILA "more time" — the ILA samples every clock edge regardless.

---

### A11: B

Intermittent lockups are notoriously difficult to catch with a standard ILA trigger, because
you may not know what signal to trigger on. A VIO-based monitoring approach allows the
designer to poll key state registers (FSM current state, watchdog counter value, error flags,
FIFO fill levels) from the host PC on a scheduled basis (e.g., every 1 second). When the
lockup occurs, the last VIO readback gives the most recent known state, providing a concrete
starting point for root-cause analysis. This technique is especially useful for bugs with
hour-scale mean time to failure.

*Why A is wrong:* BGA FPGAs typically have no accessible pins for the internal signals that
matter. Even if some outputs are accessible, the relevant state is internal.  
*Why C is wrong:* intermittent bugs that take hours to occur are extremely unlikely to be
reproduced in a few million clock cycles of simulation, unless the bug is deterministic and
the simulation setup perfectly matches hardware conditions.  
*Why D is wrong:* replacing the FPGA with a Zynq to use a software debugger is a major
redesign effort. While Zynq + XSDB is a powerful debug platform, it is not the first
response to an intermittent bug on an existing board.

---

### A12: B

Every FPGA has a unique IDCODE value programmed in silicon that identifies the device family,
part number, and stepping. When a bitstream is generated, the header embeds the expected
IDCODE of the target device. During configuration, the FPGA checks the bitstream's expected
IDCODE against its own IDCODE. A mismatch means the bitstream was built for a different
part (e.g., XCKU5P vs. XCKU9P) and configuration is aborted. This protects against
accidentally programming a device with an incompatible bitstream.

*Why A is wrong:* an encryption key mismatch produces a different error — the device will
accept the encrypted bitstream header but fail during decryption, often resulting in a
configuration timeout or specific error code, not an IDCODE mismatch.  
*Why C is wrong:* a faulty JTAG cable typically causes scan failures (partial or zero readback),
not a well-formed IDCODE mismatch message. An IDCODE mismatch means the device was successfully
scanned and responded with a valid (but wrong) ID.  
*Why D is wrong:* bitstream authentication (RSA signing) is a separate mechanism from IDCODE
checking. An unsigned bitstream can be loaded onto a device that does not require signed
bitstreams — authentication failure produces a different error code.

---

### A13: B

Partial reconfiguration requires that the partial bitstream be generated from the same
implementation run (same static routing) as the full bitstream used to initially configure
the device. If the partial bitstream was synthesised or implemented against a different static
context (different PR partition constraints, different floorplan, different static routing),
the resource assignments within the PR region will not align with the routing in the static
image. The result is functional failure of the reconfigured module, while the static logic
(which was never touched) remains correct.

*Why A is wrong:* partial reconfiguration IS supported over JTAG using the `prc` or hardware
programming commands in Vivado Hardware Manager. SelectMAP is an alternative, not a requirement.  
*Why C is wrong:* loading a partial bitstream does NOT trigger GSR. The FPGA architecture
explicitly prohibits GSR during PR operations. The PR fabric architecture ensures only the
targeted reconfigurable region is disturbed.  
*Why D is wrong:* partial reconfiguration is specifically designed to work without power
cycling. Power cycling would defeat the purpose of partial reconfiguration.

---

### A14: B

High-capacitance PCB traces (long traces, wide fanout, or capacitive loads from connectors)
combined with FAST slew rate FPGA outputs create signal integrity problems. The fast edge
rate drives a large instantaneous current into the capacitive load, causing overshoot and
ringing that can exceed the input threshold of downstream components. The ringing appears on
an oscilloscope as oscillation around the final value. Setting `SLEW = SLOW` in the XDC
reduces the edge rate, reducing the peak current and ringing. Alternatively, series resistors
(22–33 ohms) at the FPGA pin are the standard PCB-level fix.

*Why A is wrong:* accidentally setting LVDS on a single-ended net would cause the output to
drive both P and N pins of a differential pair with opposite polarity — this would short
outputs together, not cause oscillation.  
*Why C is wrong:* insufficient drive strength causes signal levels to not reach VCCO
(slow rise time, degraded high level), not oscillation. The symptom is slow edges, not ringing.  
*Why D is wrong:* `KEEPER` is a very weak (tens of kilohm) feedback element — it cannot drive
a net or cause oscillation. It is used to weakly hold floating inputs.

---

### A15: A

Transceiver link debug requires a methodical approach:
1. Verify PLL lock (CPLL or QPLL lock indicator) — if the PLL does not lock, the output
   clock and TX/RX are entirely non-functional.
2. Use IBERT (In-System Bit Error Ratio Tester) in UltraScale to run a PRBS pattern
   loopback and count bit errors — this isolates whether the problem is in the FPGA
   transceiver or the external link.
3. Run Eye Scan (UltraScale IBERT feature) to measure the received eye opening — a
   closed or marginal eye indicates signal integrity issues (jitter, ISI, crosstalk).
4. Examine the PCB layout — GTH reference clock trace routing, differential pair length
   matching, stub lengths, and via count all affect 10 Gbps performance.

*Why B is wrong:* transceiver links do NOT always recover on bitstream reload. If the CDR
cannot lock, the cause is physical (signal integrity, frequency mismatch) or configuration,
not a transient software state.  
*Why C is wrong:* while stepping down the line rate is a reasonable isolation technique if
the transceiver will not link at any rate, it should come after basic PLL lock verification
and loopback testing — not as the first step.  
*Why D is wrong:* cable/connector issues are ONE possible cause but not the only one.
Transceiver misconfiguration (wrong line rate, wrong protocol, wrong reference clock
frequency, wrong equaliser settings) are equally or more common causes of link failure
on new hardware.
