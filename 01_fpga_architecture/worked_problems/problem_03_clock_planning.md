# Problem 03: Clock Planning

## Problem Statement

You are the lead FPGA designer for a network processing card. The FPGA is a Xilinx UltraScale+ **XCKU15P** (13 clock regions). The design must support the following clock domains:

| ID | Clock | Source | Frequency | Purpose |
|---|---|---|---|---|
| CLK1 | sys_clk_250 | MMCM output | 250 MHz | Main datapath — packet processing |
| CLK2 | sys_clk_125 | MMCM output | 125 MHz | AXI interconnect and control plane |
| CLK3 | sys_clk_62p5 | MMCM output | 62.5 MHz | Management CPU interface |
| CLK4 | eth_rx_clk_0 | GTH CDR recovered | 312.5 MHz | 25GbE receive lane 0 |
| CLK5 | eth_rx_clk_1 | GTH CDR recovered | 312.5 MHz | 25GbE receive lane 1 |
| CLK6 | eth_tx_clk_0 | GTH PLL derived | 312.5 MHz | 25GbE transmit lane 0 |
| CLK7 | eth_tx_clk_1 | GTH PLL derived | 312.5 MHz | 25GbE transmit lane 1 |
| CLK8 | ddr4_ui_clk | MIG generated | 300 MHz | DDR4 user interface clock |
| CLK9 | pcie_aclk | PCIe IP generated | 250 MHz | PCIe AXI stream interface |
| CLK10 | ref_100 | External oscillator → BUFG | 100 MHz | PCIe/misc reference |
| CLK11 | debug_clk | MMCM output | 50 MHz | ILA debug core |
| CLK12 | jtag_clk | JTAG TCK | ~10 MHz | Boundary scan / JTAG |
| CLK13 | aux_io_clk | HR bank BUFR | 25 MHz | Slow I/O peripheral interface |

**Constraints:**

- XCKU15P: 13 clock regions, 12 clock networks per region
- All 13 clocks must co-exist simultaneously
- The packet processing logic (CLK1) occupies approximately 60% of the device fabric
- DDR4 and PCIe IP blocks have fixed placement requirements (IP auto-placement)
- The GTH quads for 25GbE are in clock regions R4C2 and R5C2

**Questions:**

1. Identify the clock region budget problem and quantify it.
2. Propose a clock region strategy that allows all 13 clocks to co-exist within the hardware limit.
3. Describe the MMCM configuration for CLK1–CLK3 and CLK11, assuming a 200 MHz reference input.
4. Specify the CDC handling between CLK1 (250 MHz) and CLK4/CLK5 (312.5 MHz GTH recovered).
5. Identify any clocks that should use BUFR instead of BUFG, and justify why.

---

## Worked Solution

### Step 1 — Quantify the Clock Region Budget Problem

The XCKU15P has 13 clock regions. Each region supports a maximum of 12 distinct clock networks. A BUFG clock that spans the entire device consumes one clock slot in **every** clock region, even those with no logic on that clock.

If all 13 clocks use BUFG, then every region carries 13 clock networks — which exceeds the limit of 12. The violation affects **all 13 regions**.

Vivado DRC error: `CLOCK-10`: "The design has more clocks in this clock region than can be routed."

**Severity:** This is not a warning — it is a hard routing failure. The design will not close routing with 13 BUFGs spanning all regions.

**Minimum reduction needed:** At least 1 BUFG must be converted to BUFR, removed, or clock domains must be spatially separated so that no region sees more than 12 clocks simultaneously.

**Before applying fixes, inventory which clocks are BUFG candidates:**

| Clock | Candidate for BUFG? | Notes |
|---|---|---|
| CLK1 sys_clk_250 | Yes | 60% fabric — must be global |
| CLK2 sys_clk_125 | Yes | AXI interconnect spans device |
| CLK3 sys_clk_62p5 | Maybe | CPU interface — localised? |
| CLK4 eth_rx_clk_0 | Yes | GTH recovered, drives RX logic |
| CLK5 eth_rx_clk_1 | Yes | GTH recovered, drives RX logic |
| CLK6 eth_tx_clk_0 | Yes | GTH TX |
| CLK7 eth_tx_clk_1 | Yes | GTH TX |
| CLK8 ddr4_ui_clk | Yes (MIG uses BUFG internally) | MIG manages its own buffer |
| CLK9 pcie_aclk | Yes (PCIe IP uses BUFG internally) | PCIe IP manages its own buffer |
| CLK10 ref_100 | Maybe | PCIe reference — localised? |
| CLK11 debug_clk | Maybe | ILA — often localised |
| CLK12 jtag_clk | No (JTAG has dedicated routing) | JTAG does not use global clock |
| CLK13 aux_io_clk | BUFR candidate | I/O peripheral, often localised |

**CLK12 (JTAG)** uses dedicated JTAG routing infrastructure — it does not consume a clock network slot. This immediately reduces the effective count from 13 to **12 clocks competing for clock slots**.

However, 12 clocks in every region still hits the limit exactly, with zero margin.

---

### Step 2 — Clock Region Strategy

**Strategy 1 — BUFR for localised clocks:**

CLK13 (aux_io_clk at 25 MHz) is a slow peripheral clock for HR bank I/O. If all the HR bank I/O logic is confined to one or two clock regions at the device periphery, CLK13 should use BUFR instead of BUFG.

- BUFR placement: in the HR bank region(s) where the I/O peripherals are located
- Clocks consumed in non-I/O regions: 0 (BUFR does not drive outside its region)

This reduces global clock count from 12 (effective) to **11**, giving 1 slot of margin everywhere.

**Strategy 2 — BUFR for the debug clock:**

CLK11 (debug_clk at 50 MHz) drives ILA debug cores. ILA cores are placed by Vivado wherever the debug probes are in the design. If the ILA is placed in a specific region (via `set_property C_PROBE_*` constraints or Pblock), BUFR can drive just that region.

However, with probes spanning multiple regions (since CLK1 datapath is 60% of the device), CLK11 may need to be BUFG. Accept this trade-off only if probe consolidation is possible.

**Strategy 3 — Spatial separation of GTH clocks:**

CLK4, CLK5 (25GbE RX recovered clocks) are generated by GTH CDR blocks in regions R4C2 and R5C2. The recovered clocks, after passing through a BUFG, must reach the MAC/PCS logic that processes RX data. If the RX processing logic is placed in a Pblock confined to the same regions as the GTH quad (R4C2, R5C2, and adjacent), CLK4 and CLK5 are only active in those regions.

This requires assigning all ETH RX logic to a Pblock:

```tcl
create_pblock pblock_eth_rx
add_cells_to_pblock pblock_eth_rx [get_cells u_eth_rx_*]
resize_pblock pblock_eth_rx -add {CLOCKREGION_X2Y4:CLOCKREGION_X2Y5}
```

Now CLK4 and CLK5 are local to 2 of the 13 regions. In the other 11 regions, these two clock slots are freed.

**Resulting per-region clock distribution:**

| Clock | R1-R3 | R4-R5 (GTH+ETH) | R6-R9 (main datapath) | R10-R13 (DDR/PCIe) |
|---|---|---|---|---|
| CLK1 sys_clk_250 | yes | yes | yes | yes |
| CLK2 sys_clk_125 | yes | yes | yes | yes |
| CLK3 sys_clk_62p5 | yes | — | yes | — |
| CLK4 eth_rx_clk_0 | — | yes | — | — |
| CLK5 eth_rx_clk_1 | — | yes | — | — |
| CLK6 eth_tx_clk_0 | — | yes | — | — |
| CLK7 eth_tx_clk_1 | — | yes | — | — |
| CLK8 ddr4_ui_clk | — | — | — | yes |
| CLK9 pcie_aclk | — | — | — | yes |
| CLK10 ref_100 | — | — | — | yes |
| CLK11 debug_clk | yes | yes | yes | yes |
| CLK13 aux_io_clk (BUFR) | yes | — | — | — |
| **Count** | **5–6** | **8** | **5–6** | **7** |

Maximum per-region count: **8 (in the GTH regions)**. Well within the limit of 12.

---

### Step 3 — MMCM Configuration for CLK1, CLK2, CLK3, CLK11

**Reference input:** 200 MHz (5 ns period).

**Output requirements:**

| Clock | Target frequency |
|---|---|
| CLK1 | 250 MHz |
| CLK2 | 125 MHz |
| CLK3 | 62.5 MHz |
| CLK11 | 50 MHz |

**Find VCO frequency:**

The VCO must be between 600 MHz and 1600 MHz (UltraScale+ MMCM).

All outputs must divide evenly from the VCO:
- 250 MHz: VCO / O = 250 → VCO = 250k for integer k
- 125 MHz: VCO / O = 125 → VCO = 125k
- 62.5 MHz: VCO / O = 62.5 → VCO = 62.5k (requires non-integer if VCO is integer MHz)
- 50 MHz: VCO / O = 50 → VCO = 50k

The 62.5 MHz requirement creates a challenge: it is not an integer multiple of 50 or 250 MHz in a simple ratio from a common integer VCO.

**Solution:** Use CLKOUT0's fractional divider for CLK3 (62.5 MHz).

Try VCO = 1000 MHz (M=5, D=1):

| Clock | VCO / divider | Divider | Integer? |
|---|---|---|---|
| CLK1 (250 MHz) | 1000 / 4 | O=4 | Yes |
| CLK2 (125 MHz) | 1000 / 8 | O=8 | Yes |
| CLK3 (62.5 MHz) | 1000 / 16 | O=16 | Yes |
| CLK11 (50 MHz) | 1000 / 20 | O=20 | Yes |

62.5 MHz: 1000 / 62.5 = 16.0 exactly — all four are integer dividers from VCO = 1000 MHz.

**MMCM configuration:**

```vhdl
MMCME4_ADV generic map (
  CLKIN1_PERIOD    => 5.0,          -- 200 MHz reference
  CLKFBOUT_MULT_F  => 5.0,          -- M=5: VCO = 200*5 = 1000 MHz
  DIVCLK_DIVIDE    => 1,            -- D_in=1
  CLKOUT0_DIVIDE_F => 4.0,          -- CLK1: 1000/4 = 250 MHz
  CLKOUT1_DIVIDE   => 8,            -- CLK2: 1000/8 = 125 MHz
  CLKOUT2_DIVIDE   => 16,           -- CLK3: 1000/16 = 62.5 MHz
  CLKOUT3_DIVIDE   => 20,           -- CLK11: 1000/20 = 50 MHz
  CLKOUT0_PHASE    => 0.0,
  CLKOUT1_PHASE    => 0.0,
  CLKOUT2_PHASE    => 0.0,
  CLKOUT3_PHASE    => 0.0,
  CLKOUT0_DUTY_CYCLE => 0.5,
  CLKOUT1_DUTY_CYCLE => 0.5,
  CLKOUT2_DUTY_CYCLE => 0.5,
  CLKOUT3_DUTY_CYCLE => 0.5,
  BANDWIDTH        => "OPTIMIZED",
  REF_JITTER1      => 0.010         -- Reference oscillator jitter (100 fs RMS → 0.010 ns)
)
```

**Verify VCO in range:** $600 \le 1000 \le 1600$ MHz. Valid.

**BUFG connections:**

```vhdl
BUFG_CLK1:  BUFG port map (I => mmcm_out0, O => clk_250);
BUFG_CLK2:  BUFG port map (I => mmcm_out1, O => clk_125);
BUFG_CLK3:  BUFG port map (I => mmcm_out2, O => clk_62p5);
BUFG_CLK11: BUFG port map (I => mmcm_out3, O => clk_debug);
```

**Phase relationship:** All four clocks are derived from the same MMCM VCO with zero phase offsets. They are synchronous — Vivado can analyse register paths between them with known timing relationships. CLK2 is exactly 2× slower than CLK1; CLK3 is exactly 4× slower.

---

### Step 4 — CDC Handling: CLK1 (250 MHz) to CLK4/CLK5 (312.5 MHz GTH Recovered)

**Why this CDC is challenging:**

CLK1 comes from the MMCM; CLK4/CLK5 come from GTH CDR (recovered from the incoming 25GbE data stream). These are **asynchronous** clocks — they have no phase relationship and potentially different frequencies (even if nominally both are 250 MHz derivatives, the GTH CDR is tracking the remote transmitter's clock, which is independent of the FPGA's local reference).

At the boundary between the 25GbE MAC (CLK4/CLK5 domain) and the packet processing core (CLK1 domain), data must cross safely.

**Step 4a — Declare asynchronous clock groups in XDC:**

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks clk_250] \
  -group [get_clocks eth_rx_clk_0]

set_clock_groups -asynchronous \
  -group [get_clocks clk_250] \
  -group [get_clocks eth_rx_clk_1]
```

This prevents Vivado from attempting timing analysis across these domains (which would produce false violations on the synchroniser FFs themselves).

**Step 4b — Choose the correct CDC structure:**

The 25GbE MAC produces 64-bit data words at 312.5 MHz (one word per cycle). The packet processing core runs at 250 MHz. The ratio is 312.5 / 250 = 1.25 — neither an integer ratio nor a simple fraction. A standard async FIFO is required.

**Async FIFO design:**

- Write clock: CLK4 (312.5 MHz)
- Read clock: CLK1 (250 MHz)
- Width: 64-bit data + 8-bit control (EtherType, valid, start-of-frame, end-of-frame)
- Depth: sufficient to absorb burst transfers — minimum 16 entries (2× maximum Ethernet frame delay), recommend 64 entries for margin

Implementation: Xilinx FIFO Generator IP (`xpm_fifo_async`) configured with:
- WRITE_DATA_WIDTH = 72
- READ_DATA_WIDTH = 72
- FIFO_DEPTH = 64
- USE_ADV_FEATURES = enabled for programmable empty/full thresholds
- PROG_EMPTY_THRESH = 8 (early warning to downstream arbiter)

**Gray-code pointers:** The FIFO uses Gray-coded write and read pointers that are synchronised across the clock domain crossing. Gray coding ensures only one bit changes per pointer increment, making the two-flop synchroniser safe (no multi-bit glitch).

**Step 4c — Backpressure:**

The FIFO FULL flag (in CLK4 domain) must be fedback to the upstream MAC to apply pause flow control if the FIFO fills. The EMPTY flag (in CLK1 domain) gates the downstream arbiter.

**Step 4d — CLK1 to CLK4 for TX path:**

The transmit direction (CLK1 → CLK6/CLK7) follows the same async FIFO pattern with the clock roles reversed. A separate `xpm_fifo_async` instance is used per TX lane.

---

### Step 5 — BUFR vs BUFG Assignments

**CLK13 (aux_io_clk, 25 MHz) — use BUFR:**

Justification:
- The I/O peripherals on the HR bank are physically confined to one clock region
- BUFR drives only the local region (and adjacent regions if needed)
- BUFR has a built-in divide function (`BUFR_DIVIDE`) — if the source is CLK3 (62.5 MHz MMCM output), BUFR with BUFR_DIVIDE=2 produces exactly 31.25 MHz (close but not exact). Instead, the 25 MHz should come from a dedicated MMCM output or the 100 MHz reference divided by BUFR_DIVIDE=4
- Using BUFR saves one global clock slot in all regions except the HR bank region

**BUFR configuration for CLK13:**

```tcl
-- Route CLK10 (100 MHz) through BUFR with /4 to produce 25 MHz
-- Place BUFR in the HR bank clock region
```

Or add CLK13 as a fifth output of the MMCM: 1000 MHz VCO / 40 = 25 MHz. One extra MMCM output saves a BUFR complexity.

**CLK11 (debug_clk, 50 MHz) — evaluate BUFR:**

If the ILA debug core can be constrained to one or two clock regions (by using Pblocks for the debugged logic), CLK11 should use BUFR. However, since CLK1 logic occupies 60% of the device and the debug probes tap signals across multiple regions, CLK11 likely needs to remain a BUFG.

**Recommendation for CLK11:** Keep as BUFG. Accept the global clock slot consumption. Mitigate by noting that the spatial separation strategy (Step 2) already reduces per-region maximum to 8, well below 12.

**CLK3 (sys_clk_62p5, 62.5 MHz) — evaluate BUFR:**

The management CPU interface is typically a small, localised block. If all CLK3 logic fits in one or two clock regions, CLK3 can be BUFR, saving a global clock slot. The MMCM output would feed a BUFR instead of a BUFG.

**Recommended final buffer assignments:**

| Clock | Buffer type | Justification |
|---|---|---|
| CLK1 (250 MHz) | BUFG | 60% of fabric — must be global |
| CLK2 (125 MHz) | BUFG | AXI interconnect spans device |
| CLK3 (62.5 MHz) | BUFR (if CPU localised) or BUFG | Evaluate after placement |
| CLK4/CLK5 (ETH RX) | BUFG (from GTH RXOUTCLK) | RX logic in dedicated Pblock, spans 2 regions |
| CLK6/CLK7 (ETH TX) | BUFG (from GTH TXOUTCLK) | TX logic co-located with RX Pblock |
| CLK8 (DDR4 UI) | BUFG (managed by MIG IP) | MIG inserts BUFG internally |
| CLK9 (PCIe AXI) | BUFG (managed by PCIe IP) | PCIe IP inserts BUFG internally |
| CLK10 (ref_100) | BUFG or BUFR | Only PCIe reference; localised to PCIe region |
| CLK11 (debug) | BUFG | ILA probes span multiple regions |
| CLK12 (JTAG) | Dedicated JTAG routing | Does not use global clock network |
| CLK13 (aux_io) | BUFR | HR bank only; 25 MHz, 1 region |

---

### Timing Constraint Summary

The following XDC constraints are required for correct timing analysis:

```tcl
# Define all clocks
create_clock -period 4.000 -name clk_250     [get_pins u_mmcm/CLKOUT0]
create_clock -period 8.000 -name clk_125     [get_pins u_mmcm/CLKOUT1]
create_clock -period 16.000 -name clk_62p5   [get_pins u_mmcm/CLKOUT2]
create_clock -period 20.000 -name clk_debug  [get_pins u_mmcm/CLKOUT3]
create_clock -period 3.200  -name eth_rx_0   [get_pins u_gth_0/RXOUTCLK]
create_clock -period 3.200  -name eth_rx_1   [get_pins u_gth_1/RXOUTCLK]
create_clock -period 3.200  -name eth_tx_0   [get_pins u_gth_0/TXOUTCLK]
create_clock -period 3.200  -name eth_tx_1   [get_pins u_gth_1/TXOUTCLK]
create_clock -period 3.333  -name ddr4_ui    [get_pins u_mig/ui_clk]
create_clock -period 4.000  -name pcie_aclk  [get_pins u_pcie/axi_aclk]
create_clock -period 10.000 -name ref_100    [get_ports ref_clk_100]

# Asynchronous clock groups
set_clock_groups -asynchronous \
  -group {clk_250 clk_125 clk_62p5 clk_debug} \
  -group {eth_rx_0} \
  -group {eth_rx_1} \
  -group {eth_tx_0} \
  -group {eth_tx_1} \
  -group {ddr4_ui} \
  -group {pcie_aclk}

# Note: clk_250 and pcie_aclk are both 250 MHz but asynchronous
# (different sources — do not assume phase relationship)
```

---

### Common Interview Pitfalls

**Not knowing the 12-clock-per-region limit:** Many candidates describe BUFGs and MMCMs but are unaware of the per-region clock count limit. This is a real, hard constraint that has caused late-stage failures in production designs. Knowing it and being able to quantify the violation is what separates experienced engineers from beginners.

**Treating all 250 MHz clocks as synchronous:** CLK1 (MMCM) and CLK9 (PCIe IP) are both 250 MHz. Candidates sometimes assume they are synchronous. They are not — they come from independent PLLs with no phase relationship. The correct treatment is `set_clock_groups -asynchronous` between them, and an async FIFO at the PCIe–to–datapath boundary.

**Forgetting JTAG clock is special:** CLK12 does not use the global clock network. Counting it as a BUFG clock is an error that inflates the clock budget by 1.

**Specifying BUFG for everything:** A strong candidate proactively identifies which clocks are localised and uses BUFR for them, even without being asked. This demonstrates understanding of the clock hierarchy beyond the basic BUFG level.

**Missing the CDC async FIFO requirement:** The 312.5 MHz GTH recovered clock and 250 MHz fabric clock are asynchronous. A candidate who proposes a 2-flop synchroniser for 64-bit wide data has missed a critical requirement — multi-bit CDC requires an async FIFO or handshake, not a simple synchroniser.
