# Quiz: FPGA Architecture

## Instructions

15 multiple-choice questions covering LUT/CLB architecture, Block RAM, DSP slices, clock
resources, and I/O standards. Select the single best answer for each question.
Detailed explanations follow each answer in the Answer Key section.

Difficulty distribution: Q1–Q5 Fundamentals, Q6–Q10 Intermediate, Q11–Q15 Advanced.

---

## Questions

### Q1

A 6-input LUT (LUT6) in a Xilinx UltraScale device can implement any Boolean function of
how many input variables?

A) 4  
B) 5  
C) 6  
D) 8  

---

### Q2

What does the "carry chain" logic within a CLB primarily accelerate?

A) Wide multiplexer operations  
B) Arithmetic operations such as addition and subtraction  
C) Shift register operations  
D) BRAM read latency  

---

### Q3

A Xilinx UltraScale+ BRAM36 primitive can be configured as two independent BRAM18 blocks.
What is the total data capacity of one BRAM36 when used as a simple dual-port 36Kb memory
(ignoring parity bits)?

A) 16 Kb  
B) 32 Kb  
C) 36 Kb  
D) 72 Kb  

---

### Q4

Which of the following correctly describes the function of a DSP48E2 slice's pre-adder?

A) It accumulates the output of the multiplier over multiple cycles.  
B) It adds or subtracts one input from another before the multiplier, enabling efficient FIR filter implementations.  
C) It performs a post-multiplication shift to normalise fixed-point results.  
D) It provides an extra carry input to the main adder.  

---

### Q5

In an FPGA I/O bank, what is the purpose of specifying an `IOSTANDARD` constraint?

A) It sets the internal pull-up or pull-down resistor value.  
B) It selects the voltage level, drive strength, and signalling standard (e.g., LVCMOS33, LVDS) for the I/O pin.  
C) It assigns the pin to a specific global clock buffer.  
D) It defines the output slew rate as FAST or SLOW only.  

---

### Q6

A Xilinx 7-series MMCM (Mixed-Mode Clock Manager) differs from a simple PLL primarily because:

A) An MMCM supports only integer multiplication factors whereas a PLL supports fractional.  
B) An MMCM adds fractional frequency synthesis, fine phase shifting, and spread-spectrum capability beyond what a basic PLL provides.  
C) A PLL can drive global clock networks; an MMCM can only drive regional clock networks.  
D) An MMCM is implemented in fabric LUTs; a PLL is a dedicated hard block.  

---

### Q7

You need to implement a 512-entry, 8-bit wide read-only lookup table in an FPGA. Which
resource is most area-efficient?

A) Distributed RAM using LUT RAM primitives  
B) A BRAM18 configured in ROM mode  
C) A register file using 512 flip-flops  
D) A cascade of 4-input LUTs implementing the lookup as combinational logic  

---

### Q8

A design uses LVDS (Low Voltage Differential Signalling) for high-speed I/O. What constraint
is mandatory in addition to `IOSTANDARD = LVDS`?

A) `DRIVE = 16` to ensure sufficient differential output swing  
B) `DIFF_TERM = TRUE` on the receiving end to enable the on-chip 100-ohm differential termination  
C) `SLEW = FAST` to meet LVDS rise/fall time requirements  
D) `KEEPER = TRUE` to hold the line state when no driver is active  

---

### Q9

In a Xilinx UltraScale CLB, a SLICEM differs from a SLICEL in that SLICEM:

A) Contains more flip-flops per slice.  
B) Has LUTs that can be configured as distributed RAM or shift registers (SRL).  
C) Is located exclusively in the DSP column.  
D) Supports wider carry chains (up to 16-bit per slice vs. 4-bit).  

---

### Q10

A clock signal enters an FPGA on a dedicated `MRCC` (Multi-Region Clock Capable) pin.
Compared to an `SRCC` (Single-Region Clock Capable) pin, what additional routing capability
does an `MRCC` pin provide?

A) An MRCC pin can drive global clock networks across multiple clock regions; an SRCC pin can only drive its local clock region.  
B) An MRCC pin supports differential input standards; an SRCC pin supports only single-ended.  
C) An MRCC pin bypasses the MMCM/PLL and connects directly to the global clock backbone.  
D) An MRCC pin has lower input jitter than an SRCC pin due to a dedicated low-noise power supply.  

---

### Q11

A DSP48E2 slice is cascaded with a second DSP48E2 using the `PCOUT → PCIN` cascade path.
What is the primary advantage of using this cascade path rather than routing the result
through fabric?

A) The cascade path adds an extra pipeline register, automatically retiming the design.  
B) The 48-bit cascade path eliminates the routing delay and LUT overhead of carrying a wide bus through the CLB fabric, enabling higher clock frequencies in multi-accumulate chains.  
C) The cascade path allows the second DSP to operate at twice the clock frequency.  
D) The cascade path provides automatic overflow detection between the two DSP slices.  

---

### Q12

You are implementing a 4096 x 32-bit synchronous dual-port RAM. The target device has BRAM36
primitives configurable as 16K x 2, 8K x 4, 4K x 9, 2K x 18, or 1K x 36. Which BRAM36
configuration and how many primitives are required for the exact fit?

A) 4K x 9 configuration, 4 primitives  
B) 1K x 36 configuration, 4 primitives  
C) 2K x 18 configuration, 4 primitives  
D) 4K x 9 configuration, 8 primitives  

---

### Q13

An UltraScale+ device's I/O supports the `HPIOBDIFFOUTBUF` primitive for differential output.
A colleague suggests placing a series resistor on each leg of the differential pair on the PCB
for impedance matching. What is the correct approach?

A) Incorrect — LVDS drivers already have on-chip series termination and adding series resistors will attenuate the differential swing below the LVDS standard minimum.  
B) Correct — FPGA LVDS drivers have no output impedance control, so external 50-ohm series resistors on each leg are always required.  
C) Correct — the resistors should be 100 ohms each to match the differential impedance.  
D) Incorrect — series resistors are used for single-ended signals only; LVDS pairs must never have series termination.  

---

### Q14

In a Xilinx UltraScale+ device, a `BUFGCE` global clock buffer differs from a `BUFGCE_DIV`
in that `BUFGCE_DIV`:

A) Has lower insertion delay.  
B) Can divide the clock frequency by integer values from 1 to 8, generating a derived clock from the global clock network without using an MMCM.  
C) Can drive both global and regional clock networks simultaneously.  
D) Is instantiated automatically by Vivado; `BUFGCE` must be manually instantiated.  

---

### Q15

A design targets a device with GTH transceivers. The transceiver reference clock is provided
by an external oscillator. Which of the following statements about the reference clock input
path is correct?

A) The reference clock can be driven through a BUFG and then into the transceiver's REFCLK port.  
B) The reference clock must enter the device on a dedicated `MGTREFCLK` pin and connect directly to the transceiver's reference clock port — it must NOT pass through BUFG or fabric routing.  
C) The reference clock may be generated internally by an MMCM and routed to the transceiver via the global clock network.  
D) Any I/O pin can be used for the reference clock as long as it is in the same I/O bank as the transceiver.  

---

## Answer Key

### A1: C

A LUT6 has 6 input ports (I0–I5) and implements any Boolean function of those 6 variables. The
truth table has 2^6 = 64 entries, each stored as a SRAM bit. This is fundamental to understanding
FPGA fabric — the LUT is the universal building block of combinational logic on most modern FPGAs.

*Why A is wrong:* 4-input LUTs (LUT4) were common in older Xilinx Spartan/Virtex devices but
UltraScale uses LUT6.  
*Why B is wrong:* LUT5 exists as half of a LUT6 (the LUT6 can be split into two LUT5s sharing
inputs), but the LUT6 itself is a 6-input function.  
*Why D is wrong:* 8-input LUTs do not exist as a standard primitive; wider functions are built
by cascading multiple LUT6 primitives.

---

### A2: B

The carry chain (implemented as `CARRY8` in UltraScale) provides dedicated fast carry propagation
between adjacent LUTs in the same CLB column. This allows multi-bit adders and subtractors to
be built with near-zero propagation delay per bit, far faster than routing carry through general
interconnect. Without the carry chain, a 32-bit adder would require routing through dozens of
LUTs with accumulated routing delays.

*Why A is wrong:* wide multiplexers use the LUT cascade inputs (MUX primitives like `MUXF7`,
`MUXF8`), not the carry chain.  
*Why C is wrong:* shift registers use the LUT RAM shift register (SRL) mode, not the carry chain.  
*Why D is wrong:* BRAM latency is fixed by the memory architecture, not the carry chain.

---

### A3: C

One BRAM36 stores 36 Kb (36,864 bits) of data, which includes 32 Kb of data bits plus 4 Kb of
parity bits. The question specifies ignoring parity bits — but "36Kb" is the total including
parity. The answer is 36 Kb as the branded capacity. The usable data-only capacity is 32 Kb.
Since the question asks for the capacity "as a 36Kb memory," the answer is 36 Kb.

*Why A is wrong:* 16 Kb is the capacity of a BRAM16 found in older Spartan-3 devices.  
*Why B is wrong:* 32 Kb is the data-only portion excluding parity — the full BRAM36 capacity
is labelled 36 Kb.  
*Why D is wrong:* 72 Kb would require two BRAM36 blocks.

---

### A4: B

The pre-adder in a DSP48E2 computes `A ± D` before the multiplier. This directly maps to the
symmetric coefficient structure in FIR filters, where two taps symmetric around the centre share
the same coefficient. Adding or subtracting the corresponding input samples first and multiplying
once halves the number of multiplications required, dramatically reducing DSP slice usage.

*Why A is wrong:* accumulation is performed by the post-adder/accumulator (the P register in
feedback mode), not the pre-adder.  
*Why C is wrong:* post-multiplication shifts are applied by routing the result appropriately in
the cascade — the pre-adder has no shift function.  
*Why D is wrong:* carry inputs to the main adder come from the cascade path (`PCIN`) or carry
input port, not the pre-adder.

---

### A5: B

The `IOSTANDARD` constraint tells the tool which electrical standard to use for the I/O cell.
This determines the reference voltage (VCCO), the input/output thresholds, the drive strength
range, and whether the pin operates in single-ended or differential mode. Selecting the wrong
IOSTANDARD can cause electrical incompatibility, marginal signal integrity, or damage to the
device if VCCO is mismatched.

*Why A is wrong:* pull-up/pull-down resistors are set via the `PULLUP`, `PULLDOWN`, or `KEEPER`
constraints, not `IOSTANDARD`.  
*Why C is wrong:* assigning a signal to a clock buffer is done via placement constraints
(`LOC`) or by instantiating a BUFG/BUFR primitive.  
*Why D is wrong:* slew rate is a separate constraint (`SLEW = FAST | SLOW`); `IOSTANDARD`
encompasses far more than slew rate.

---

### A6: B

An MMCM (Mixed-Mode Clock Manager) is a superset of a PLL. It adds: fractional multiply/divide
factors (e.g., multiply by 6.125), fine-grained dynamic phase adjustment in small increments
(as low as ~5 ps), spread-spectrum clock generation, and phase offset capabilities. A basic
PLL provides integer multiply/divide only. In Xilinx 7-series and later, MMCMs are the
primary clock management tile; PLLs are secondary with fewer features.

*Why A is wrong:* it is the reverse — the MMCM supports fractional, the basic PLL supports
only integer.  
*Why C is wrong:* both MMCMs and PLLs can drive global clock networks (via BUFGs connected to
their outputs).  
*Why D is wrong:* both MMCMs and PLLs are hard silicon blocks, not fabric implementations.

---

### A7: B

A 512 x 8 ROM requires 512 × 8 = 4096 bits of storage. A BRAM18 holds 18 Kb (~18,432 bits
including parity), which easily accommodates 4 Kb of data in a single primitive. Using a
BRAM18 in ROM mode (initialise with `INIT_xx` attributes, write-enable tied low) uses zero
LUTs and zero flip-flops — a single dedicated hard block.

*Why A is wrong:* distributed RAM using LUT RAM is area-efficient only for small memories
(typically 64 entries or fewer). 512 entries would consume ~128 LUT6s just for storage, wasting
significant fabric.  
*Why C is wrong:* 512 flip-flops for storage is extremely wasteful — flip-flops have no
address decode logic and are the most expensive resource for memory.  
*Why D is wrong:* implementing a lookup table entirely in combinational LUTs (as a truth table)
for 512 entries with 8-bit output is not practical; it would require far more LUTs than a
distributed RAM approach.

---

### A8: B

LVDS inputs require a 100-ohm differential termination at the receiver to prevent reflections
on the transmission line. Xilinx 7-series and UltraScale devices provide an on-chip
differential termination that is enabled by setting `DIFF_TERM = TRUE`. Without termination,
the differential signal will ring, causing multiple transitions and potential metastability.

*Why A is wrong:* `DRIVE` sets the output drive strength for single-ended standards. LVDS has
a current-mode output with fixed output impedance — `DRIVE` is not a valid attribute for LVDS.  
*Why C is wrong:* while LVDS has defined rise/fall time requirements, `SLEW = FAST` is a
single-ended output attribute. LVDS output slew is controlled by the driver architecture.  
*Why D is wrong:* `KEEPER` is a weak feedback element to prevent floating inputs — it is not
appropriate for LVDS termination and is far too weak to serve as termination.

---

### A9: B

SLICEM (M = Memory) LUTs can operate in two additional modes beyond pure combinational logic:
as distributed RAM (LUT RAM) and as shift registers (SRL16/SRL32). This makes SLICEM tiles
essential for small on-chip memories and pipeline delay elements. SLICEL (L = Logic) LUTs can
only implement combinational functions — they do not support the distributed memory or shift
register modes.

*Why A is wrong:* both SLICEM and SLICEL contain the same number of flip-flops per slice (8 FFs
in UltraScale).  
*Why C is wrong:* SLICEM tiles are distributed throughout the CLB fabric, not confined to DSP
columns.  
*Why D is wrong:* carry chain width is the same in both SLICEM and SLICEL; UltraScale uses
CARRY8 (8-bit per slice) in both types.

---

### A10: A

In Xilinx 7-series and UltraScale devices, I/O pins designated as MRCC can drive the global
clock backbone across multiple clock regions (an entire side of the device or even the full
device). SRCC pins can only drive clock networks within their single local clock region. For a
board-level clock that needs to reach all logic in the FPGA, the clock input pin must be a
MRCC-capable pin; otherwise, Vivado will issue a DRC error or route it through fabric with
additional jitter.

*Why B is wrong:* both MRCC and SRCC pins support differential standards. The MRCC/SRCC
designation is about clock routing reach, not electrical standard.  
*Why C is wrong:* both MRCC and SRCC can connect to an MMCM/PLL or directly to a BUFG — the
designation does not bypass the clock management tile.  
*Why D is wrong:* jitter performance is related to the clock management tile and PCB design, not
directly to whether the pin is MRCC or SRCC.

---

### A11: B

The `PCOUT → PCIN` 48-bit cascade path is a direct silicon connection between adjacent DSP
slices. It carries the full-precision 48-bit accumulator or product result without loading
the fabric interconnect. In long MAC chains (e.g., matrix multiply, FIR filters with many taps),
routing a 48-bit bus through fabric between every DSP would introduce significant routing delay
and consume numerous LUTs as registers. The cascade path allows near-zero delay between DSPs,
enabling multi-stage accumulation at full DSP speed.

*Why A is wrong:* the cascade path does not add pipeline registers automatically; you must
explicitly register via the `PREG` attribute if pipelining is desired.  
*Why C is wrong:* all DSP slices operate at the same system clock frequency — the cascade path
does not enable any form of frequency multiplexing.  
*Why D is wrong:* overflow detection is not provided by the cascade path; you must implement
overflow checking on the `OVERFLOW` and `UNDERFLOW` output ports of the DSP.

---

### A12: B

The requirement is 4096 entries × 32 bits = 131,072 bits = 128 Kb of storage. A BRAM36 in
`1K x 36` configuration provides 1024 addresses × 36 bits (32 data + 4 parity). Using only
the 32-bit data portion: 1024 × 32 = 32 Kb per BRAM36. To store 4096 × 32 bits = 128 Kb,
you need 128 / 32 = 4 BRAM36 primitives. Each BRAM36 stores 1024 of the 4096 rows — the 4K
address space is split across 4 BRAMs with address decoding on bits [11:10].

*Why A is wrong:* 4K x 9 configuration gives 4096 × 9 bits = 36 Kb per BRAM36. You would need
the data width to be 32, not 9. Four BRAM36s in 4K x 9 mode gives only 4096 × 36 bits = 18 Kb
of 32-bit-wide data — this does not cleanly implement a 32-bit-wide memory.  
*Why C is wrong:* 2K x 18 configuration gives 2048 entries × 18 bits; two of these in parallel
give 2048 × 36 bits = one 36-bit-wide, 2048-deep memory. Four of these would give 2048 × 72
bits — not a clean mapping to a 4096 x 32 requirement.  
*Why D is wrong:* 4K x 9 mode with 8 BRAMs gives 4096 × 72 bits, which is double the required
depth-width product and a wasteful mapping.

---

### A13: A

Xilinx LVDS output drivers (and most FPGA LVDS drivers) have controlled output impedance built
into the driver circuit. The driver is designed to match the 100-ohm differential trace impedance
directly. Adding external series resistors attenuates the voltage swing and can cause the
differential amplitude to fall below the LVDS standard minimum (250 mV differential). Series
termination is appropriate for single-ended CMOS signals to reduce reflections — not for LVDS,
which uses source termination inherent to the driver design.

*Why B is wrong:* FPGA LVDS drivers do have output impedance control; external 50-ohm series
resistors are not universally required and can violate the LVDS standard.  
*Why C is wrong:* 100 ohms each leg would give a 200-ohm differential impedance — far too high
and not a standard termination practice.  
*Why D is wrong:* LVDS differential pairs CAN have series termination in specific cases (e.g.,
back-termination on very long lines), but the assertion "must never" is too absolute and the
general guidance for FPGA LVDS outputs is that no external series termination is needed.

---

### A14: B

`BUFGCE_DIV` is a clock divider primitive that divides the input clock by an integer value
(1, 2, 3, 4, 5, 6, 7, or 8) and distributes the result on the global clock network. This
allows generation of a lower-frequency derived clock without consuming an MMCM, which is a
limited and more complex resource. The divided clock is phase-aligned with the input clock
(no phase shift is introduced relative to the original edges).

*Why A is wrong:* `BUFGCE_DIV` generally has higher insertion delay than a simple `BUFGCE`
because it includes the divider logic.  
*Why C is wrong:* BUFGCE and BUFGCE_DIV both drive the global clock network; neither drives
regional and global simultaneously as a standard feature.  
*Why D is wrong:* neither BUFGCE nor BUFGCE_DIV is automatically inferred by Vivado for
user-defined clock dividers; both require explicit instantiation or Clocking Wizard IP.

---

### A15: B

GTH/GTY/GTP transceiver reference clocks must arrive on dedicated `MGTREFCLK` differential
input pins and connect directly to the transceiver channel's `GTREFCLK0` or `GTREFCLK1` port
using a `IBUFDS_GTE4` (or equivalent) input buffer. Routing the reference clock through BUFG
or fabric introduces jitter that violates the transceiver's reference clock jitter specification
(typically < 1 ps RMS). The transceiver's CDR (Clock and Data Recovery) circuit requires an
ultra-low-jitter reference clock to achieve its rated BER performance.

*Why A is wrong:* routing through BUFG adds jitter from the global clock network, violating
transceiver reference clock specs. This would cause degraded or failed link training.  
*Why C is wrong:* an MMCM-generated clock inherits MMCM output jitter on top of the MMCM
reference jitter — this is never acceptable for transceiver reference clocks.  
*Why D is wrong:* `MGTREFCLK` pins are not general-purpose I/O pins. They are dedicated pins
in the transceiver bank (GT bank) — standard I/O pins in regular I/O banks cannot be used
as transceiver reference clocks.
