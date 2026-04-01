# Problem 02: Constraint Writing

**Difficulty:** Fundamentals to Advanced  
**Skills tested:** SDC/XDC syntax, timing constraint semantics, CDC awareness, I/O timing, constraint completeness  
**Typical interview context:** "Write constraints for this design" — either on a whiteboard or in a text editor. The interviewer will probe reasoning at each step.

---

## Design Specification

You are writing timing constraints for a new FPGA design with the following architecture:

```
Board clock inputs:
  - clk_200_p / clk_200_n: 200 MHz differential LVDS (board reference clock)
  - clk_25_p  / clk_25_n:  25 MHz differential LVDS (Ethernet reference)

On-chip clock generation (MMCM_A):
  - Input:   clk_200 (200 MHz)
  - CLKOUT0: 500 MHz (core processing clock)
  - CLKOUT1: 125 MHz (Ethernet MAC clock)
  - CLKOUT2: 62.5 MHz (half-rate memory controller clock)

Interfaces:
  - DDR4 interface: handled by MIG IP (constrained separately by MIG XDC)
  - Ethernet RGMII: data[3:0] + ctl, clocked by Ethernet PHY (source-synchronous)
    - PHY clock-to-output (T_co): max 2.0 ns, min 0.5 ns
    - PHY setup requirement at destination: 1.0 ns
    - Board trace delay: 0.3 ns (data), 0.2 ns (clock)
    - RGMII clock rate: 125 MHz (1000BASE-T)
  - Control UART: asynchronous, 115200 baud, rx/tx via IOB registers
  - AXI4-Lite bus: runs in 125 MHz domain, connects to 500 MHz processing core
    (data registers are stable for multiple 500 MHz cycles when written)

Additional:
  - Asynchronous reset: rst_n (active low, from external pin, debounced on board)
  - JTAG: standard boundary scan (no user constraints needed)
```

---

## Part 1: Primary and Generated Clocks

**Q: Write all `create_clock` and `create_generated_clock` constraints for the above specification. Explain your reasoning for each.**

**A:**

```tcl
# ============================================================
# FILE: constraints.xdc
# Design: Signal Processing Engine
# Target: Xilinx UltraScale+ (xcvu9p or similar)
# Date: 2026-04-01
# ============================================================

# ============================================================
# PRIMARY CLOCKS — constrain at the physical input port
# ============================================================

# 200 MHz board reference clock (differential)
# Period = 1/200MHz = 5.000 ns
# Waveform: 50% duty cycle → rising at 0, falling at 2.5
create_clock -name clk_200 \
             -period 5.000 \
             -waveform {0.000 2.500} \
             [get_ports clk_200_p]
# Note: clk_200_n is NOT constrained separately.
# The IBUFDS primitive automatically handles the negative leg.

# 25 MHz Ethernet reference clock (differential)
# Period = 1/25MHz = 40.000 ns
create_clock -name clk_eth_ref \
             -period 40.000 \
             -waveform {0.000 20.000} \
             [get_ports clk_25_p]

# ============================================================
# GENERATED CLOCKS — constrain at the MMCM output pins
# ============================================================

# MMCM_A: 200 MHz input
# CLKOUT0: 500 MHz → multiply_by 5, divide_by 2
# Period = 5.000 * 2 / 5 = 2.000 ns
create_generated_clock -name clk_500 \
                       -source    [get_pins MMCM_A/CLKIN1] \
                       -multiply_by 5 \
                       -divide_by   2 \
                       [get_pins MMCM_A/CLKOUT0]

# MMCM_A CLKOUT1: 125 MHz → multiply_by 5, divide_by 8
# Period = 5.000 * 8 / 5 = 8.000 ns
create_generated_clock -name clk_125 \
                       -source    [get_pins MMCM_A/CLKIN1] \
                       -multiply_by 5 \
                       -divide_by   8 \
                       [get_pins MMCM_A/CLKOUT1]

# MMCM_A CLKOUT2: 62.5 MHz → multiply_by 5, divide_by 16
# Period = 5.000 * 16 / 5 = 16.000 ns
create_generated_clock -name clk_62p5 \
                       -source    [get_pins MMCM_A/CLKIN1] \
                       -multiply_by 5 \
                       -divide_by  16 \
                       [get_pins MMCM_A/CLKOUT2]

# ============================================================
# GENERATED CLOCKS AFTER BUFG
# Each MMCM output passes through a BUFG before distribution.
# The BUFG adds ~600 ps delay but does not change frequency.
# ============================================================

create_generated_clock -name clk_500_buf \
                       -source    [get_pins MMCM_A/CLKOUT0] \
                       -divide_by 1 \
                       [get_pins bufg_500/O]

create_generated_clock -name clk_125_buf \
                       -source    [get_pins MMCM_A/CLKOUT1] \
                       -divide_by 1 \
                       [get_pins bufg_125/O]

create_generated_clock -name clk_62p5_buf \
                       -source    [get_pins MMCM_A/CLKOUT2] \
                       -divide_by 1 \
                       [get_pins bufg_62p5/O]

# ============================================================
# RGMII receive clock (source-synchronous, external source)
# The PHY forwards a recovered 125 MHz clock with the data.
# Constrain this clock at the FPGA input pin.
# ============================================================
create_clock -name rgmii_rxclk \
             -period 8.000 \
             -waveform {0.000 4.000} \
             [get_ports rgmii_rxc]
```

**Reasoning:**

- All MMCM outputs are generated clocks because they are **derived** from `clk_200` with a known multiply/divide ratio. Using `create_clock` on an MMCM output instead would declare it as independent, suppressing valid timing checks.
- The BUFG-output clocks are also generated (divide_by 1 from the MMCM output). This is required because the BUFG is on the clock path — if we only constrain at the MMCM output, the generated clock constraint does not propagate through the BUFG correctly in all Vivado versions.
- `rgmii_rxclk` is a **primary clock** because it comes from an external source (the PHY) and has no phase relationship to the MMCM clocks.

---

## Part 2: I/O Timing Constraints

**Q: Write the `set_input_delay` constraints for the RGMII receive interface. Show the formula derivation.**

**A:**

**RGMII receive interface parameters:**

```
PHY T_co (max):  2.0 ns  (data valid this long after PHY clock edge)
PHY T_co (min):  0.5 ns  (data valid this early after PHY clock edge)
Board trace (data): 0.3 ns
Board trace (clock): 0.2 ns
RGMII clock period: 8.000 ns (125 MHz, but DDR — data on both edges)
```

**Formula:**

```
input_delay_max = T_co_max + T_trace_data - T_trace_clk
               = 2.0 + 0.3 - 0.2 = 2.1 ns

input_delay_min = T_co_min + T_trace_data - T_trace_clk
               = 0.5 + 0.3 - 0.2 = 0.6 ns
```

The `-max` value is used for setup analysis (data arrives late → worst case setup).
The `-min` value is used for hold analysis (data arrives early → worst case hold).

**RGMII is DDR** — data changes on both rising and falling edges of the receive clock:

```tcl
# RGMII receive data: DDR on rgmii_rxclk
# Rising-edge data
set_input_delay -clock rgmii_rxclk \
                -max 2.1 \
                [get_ports {rgmii_rxd[*] rgmii_rxctl}]

set_input_delay -clock rgmii_rxclk \
                -min 0.6 \
                [get_ports {rgmii_rxd[*] rgmii_rxctl}]

# Falling-edge data (DDR second half)
# -add_delay accumulates on top of the rising-edge constraint
set_input_delay -clock rgmii_rxclk \
                -clock_fall \
                -max 2.1 \
                -add_delay \
                [get_ports {rgmii_rxd[*] rgmii_rxctl}]

set_input_delay -clock rgmii_rxclk \
                -clock_fall \
                -min 0.6 \
                -add_delay \
                [get_ports {rgmii_rxd[*] rgmii_rxctl}]
```

**RGMII transmit (output) constraints:**

For the transmit path, the FPGA drives data to the PHY. The PHY's setup/hold requirements define the output delay:

```tcl
# Create the forwarded transmit clock (generated from clk_125_buf)
create_generated_clock -name rgmii_txclk_fwd \
                       -source [get_pins bufg_125/O] \
                       -divide_by 1 \
                       [get_ports rgmii_txc]

# Assume PHY requires: T_setup = 1.5 ns, T_hold = 0.5 ns before/after its clock
# T_trace_data = 0.3 ns, T_trace_clock = 0.2 ns
# output_delay_max = T_setup + T_trace_data - T_trace_clk = 1.5 + 0.3 - 0.2 = 1.6 ns
# output_delay_min = -T_hold + T_trace_data - T_trace_clk = -0.5 + 0.3 - 0.2 = -0.4 ns

set_output_delay -clock rgmii_txclk_fwd \
                 -max 1.6 \
                 [get_ports {rgmii_txd[*] rgmii_txctl}]

set_output_delay -clock rgmii_txclk_fwd \
                 -min -0.4 \
                 [get_ports {rgmii_txd[*] rgmii_txctl}]

# DDR falling edge
set_output_delay -clock rgmii_txclk_fwd \
                 -clock_fall -max 1.6 -add_delay \
                 [get_ports {rgmii_txd[*] rgmii_txctl}]

set_output_delay -clock rgmii_txclk_fwd \
                 -clock_fall -min -0.4 -add_delay \
                 [get_ports {rgmii_txd[*] rgmii_txctl}]
```

---

## Part 3: Asynchronous Reset and UART

**Q: Write constraints for the asynchronous reset and the UART RX/TX ports.**

**A:**

**Asynchronous reset:**

The reset pin `rst_n` is asynchronous — it asserts independently of any clock. The path from `rst_n` to flip-flop reset pins has no meaningful timing relationship to the clock. Apply a false path:

```tcl
# Asynchronous reset: no timing check required on assertion path
# The reset synchroniser (if present) handles safe deassertion
set_false_path -from [get_ports rst_n]
```

**Why not constrain it as an input with `set_input_delay`?** The reset is not sampled by a flip-flop in the normal synchronous sense. It drives the asynchronous reset pins of flip-flops directly. There is no setup/hold relationship at the clock edge. The `set_false_path` is the correct constraint.

**Important note:** The reset should still be synchronised before deassertion to avoid metastability when `rst_n` goes high. The synchroniser itself is designed with `DONT_TOUCH` flip-flops; those flip-flops' inputs are covered by the false path above.

**UART:**

UART operates asynchronously at 115200 baud. The UART RX path oversamples the incoming bit stream (typically 16× oversampling). The TX path is simply a shift register. Neither has a meaningful board-level timing constraint relative to the FPGA's clocks.

```tcl
# UART RX: asynchronous serial input — no timing constraint at the FPGA level
# The UART receiver's oversampling logic handles edge detection
set_false_path -from [get_ports uart_rx]

# UART TX: asynchronous serial output
set_false_path -to [get_ports uart_tx]
```

**Interviewer follow-up:** "Why not use `set_input_delay` on `uart_rx` with a 125 MHz reference?" — Because UART is asynchronous. There is no defined clock edge at the transmitter that the FPGA's `clk_125` is derived from. `set_input_delay` requires a reference clock with a phase relationship to the data. For UART, no such relationship exists. The correct approach is `set_false_path`.

---

## Part 4: Clock Domain Crossing Between AXI (125 MHz) and Core (500 MHz)

**Q: Write the clock domain crossing constraints for the AXI4-Lite control bus crossing from 125 MHz to 500 MHz. The specification states that AXI data registers are stable for multiple 500 MHz cycles when written. Explain your constraint choices.**

**A:**

The specification says AXI writes are stable for "multiple 500 MHz cycles." This means the AXI write mechanism uses a handshake that ensures data is stable before the 500 MHz domain samples it. The 125 MHz and 500 MHz clocks are **synchronous and phase-related** (both derived from MMCM_A with a defined ratio: 500/125 = 4).

**Are they truly synchronous?** In MMCM terms, `clk_500` and `clk_125` share the same source (`clk_200`) and have a defined frequency relationship. The MMCM guarantees a defined phase relationship between its outputs. However, they are **not phase-aligned** by default (CLKOUT0 and CLKOUT1 may have different phase offsets). For conservative timing, treat them as related but not phase-aligned.

**Constraint strategy:**

For AXI configuration registers that are stable for 4 cycles (one 125 MHz cycle = four 500 MHz cycles):

```tcl
# Path from 125 MHz AXI registers to 500 MHz logic:
# The data is stable for 4 cycles at 500 MHz → 4-cycle multicycle path
# (data launched at 125 MHz edge, valid for the entire next 8 ns window)

# Setup: data has 4 cycles (8 ns) to arrive instead of 1 cycle (2 ns)
set_multicycle_path -setup 4 \
                    -from [get_clocks clk_125_buf] \
                    -to   [get_clocks clk_500_buf]

# Hold: adjust the hold check reference back by 3 cycles
# (for -setup N, companion -hold is N-1)
set_multicycle_path -hold 3 \
                    -from [get_clocks clk_125_buf] \
                    -to   [get_clocks clk_500_buf]
```

**For the reverse path (500 MHz status registers read by 125 MHz):**

Status registers from the core are written at 500 MHz and read by the AXI master at 125 MHz. The 125 MHz domain has a full 8 ns read window; a path that meets timing at 500 MHz (2 ns) certainly meets timing at 125 MHz. However, the hold check default may be too tight for the 4:1 ratio. Use a safe exception:

```tcl
# 500 MHz → 125 MHz: data from fast domain, captured by slow domain
# Default setup check gives 8 ns (one 125 MHz cycle) — this is satisfied.
# The multicycle path constraint relaxes to the actual crossing structure.
set_multicycle_path -setup 1 \
                    -from [get_clocks clk_500_buf] \
                    -to   [get_clocks clk_125_buf]
# No hold adjustment needed: the default hold check is at the launch edge,
# which is conservative for a slow-capture scenario.
```

**Verification:**

```tcl
# After applying constraints:
report_cdc -severity {Critical Warning Warning}
# Should show no unconstrained CDC paths between clk_125 and clk_500

report_exceptions -from [get_clocks clk_125_buf] -to [get_clocks clk_500_buf]
# Confirms the multicycle path is active on the expected paths
```

---

## Part 5: Complete Constraint Verification Checklist

**Q: List the verification steps you perform after writing the constraint file, before submitting to timing closure.**

**A:**

```tcl
# ============================================================
# VERIFICATION SEQUENCE — run after all constraints are written
# ============================================================

# 1. Verify all clocks are correctly defined
report_clocks
# Check: all expected clocks present, correct periods, correct sources

# 2. Check for unconstrained timing paths
check_timing -verbose -file check_timing.rpt
# Look for:
#   - No clock defined on net X
#   - Unconstrained inputs
#   - Unconstrained outputs
#   - Loops

# 3. Verify CDC coverage
report_cdc -severity {Critical Warning Warning} -file cdc_report.rpt
# All cross-domain paths should either have:
#   - A synchroniser (no warning)
#   - A false_path exception (suppressed from checking)
#   - A multicycle_path exception (if synchronous relationship exists)

# 4. Check exception coverage
report_exceptions -coverage -file exceptions.rpt
# Each exception should cover at least one path.
# Zero-coverage exceptions indicate wrong cell/net names — common bug.

# 5. Spot-check specific paths
# Check a known setup-critical path
report_timing -from [get_cells {fir_filter_bank/*}] \
              -to   [get_cells {magnitude_calc/*}] \
              -delay_type max -max_paths 5

# Check a known hold-critical path (CDC with tight hold)
report_timing -from [get_cells {axi_ctrl/*}] \
              -to   [get_cells {fir_filter_bank/config_sync/*}] \
              -delay_type min -max_paths 5

# 6. Check I/O timing coverage
foreach port [get_ports *] {
    if {[get_property DIRECTION $port] eq "IN"} {
        set delays [get_property INPUT_DELAY $port]
        if {$delays eq ""} {
            puts "WARNING: No input delay on port $port"
        }
    }
}
```

**What to look for in each check:**

| Check | Pass condition | Common failure |
|---|---|---|
| `report_clocks` | All expected clocks listed with correct period | Missing `create_generated_clock` |
| `check_timing` | Zero unconstrained paths | Forgot a clock or I/O port |
| `report_cdc` | Zero Critical Warnings | Missing synchroniser in RTL |
| `report_exceptions` | All exceptions have non-zero path count | Wrong cell/net name in exception |
| Spot-check timing | Paths have expected requirement values | Multicycle/false path not applying |

---

## Summary

The complete constraint file for this design requires:

| Constraint type | Count |
|---|---|
| `create_clock` (primary) | 3 (clk_200, clk_eth_ref, rgmii_rxclk) |
| `create_generated_clock` (MMCM outputs) | 3 (clk_500, clk_125, clk_62p5) |
| `create_generated_clock` (post-BUFG) | 4 (3 MMCM + rgmii_txclk_fwd) |
| `set_input_delay` (RGMII RX, DDR) | 4 (max/min × rising/falling) |
| `set_output_delay` (RGMII TX, DDR) | 4 (max/min × rising/falling) |
| `set_false_path` (async) | 3 (rst_n, uart_rx, uart_tx) |
| `set_multicycle_path` | 3 (125→500 setup+hold, 500→125 setup) |
| `set_clock_groups` or separate MCPs | TBD after confirming MMCM phase relationship |

**Interview tip:** A complete constraint file is not about memorising syntax — it is about methodically accounting for every timing relationship in the design. The most reliable mental checklist is: primary clocks → generated clocks → I/O constraints → exceptions (false paths, multicycle paths) → clock groups → verification.
