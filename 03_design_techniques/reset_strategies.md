# Reset Strategies (FPGA)

## Overview

Reset design is a topic that trips up many engineers because the correct answer changes
depending on context: FPGA vs. ASIC, synchronous vs. asynchronous, Xilinx UltraScale vs.
older 7-Series, and floorplan complexity. A poor reset strategy produces designs with
unreliable initialisation, difficult timing closure, or fragile CDC behaviour. This document
covers the full spectrum from the physics of FF reset to practical Vivado implementation.

---

## Fundamentals

### Q1. What is the difference between a synchronous reset and an asynchronous reset?

**Question:** Define synchronous and asynchronous reset. Explain the synthesis implications
of each and the flip-flop resources consumed in a Xilinx UltraScale FPGA.

**Answer:**

**Synchronous reset:**

The reset condition is checked only on the active clock edge. The reset signal is treated
as a data input to the flip-flop's D multiplexer.

```systemverilog
// Synchronous reset -- reset only takes effect on posedge clk
always_ff @(posedge clk) begin
    if (rst_n == 1'b0)
        q <= '0;        // checked only at clock edge
    else
        q <= d;
end
```

Synthesis maps this to: `D = rst_n ? d : '0` -- the reset drives the D-input MUX.
In Xilinx FPGAs, this uses the standard data path of the flip-flop and may consume one
LUT (to implement the MUX) if the synthesiser cannot absorb it into the FF's CE/R pins.

**Asynchronous reset:**

The reset condition is independent of the clock. The FF immediately clears when reset
is asserted, regardless of where the clock edge is.

```systemverilog
// Asynchronous reset -- reset takes effect immediately, regardless of clock
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= '0;        // executes immediately on negedge rst_n
    else
        q <= d;
end
```

Synthesis maps this to the FF's dedicated `CLR` or `PRE` pin. In UltraScale, the FF has
dedicated synchronous set/reset (`S`/`R`) and asynchronous set/reset (`CE`, `PRE`, `CLR`)
pins. Using these dedicated pins is free — it does not consume a LUT.

**UltraScale-specific detail:**

UltraScale FFs support:
- `SR`: dedicated synchronous set or reset (not both in the same FF)
- Initialisation attribute `INIT`: sets the FF's power-on state (handled by GSR at configuration)

Asynchronous reset maps to the `CLR`/`PRE` pins. However, UltraScale FFs have only one
SR pin, which is configurable as set or reset, synchronous or asynchronous — but not mixed.
This is why reset polarity and type must be consistent across all FFs sharing a clock enable
in a slice.

**Comparison table:**

| Property | Synchronous | Asynchronous |
|---|---|---|
| Effect timing | At clock edge only | Immediately on assertion |
| FPGA resource | May need LUT for MUX | Uses dedicated CLR/PRE pin |
| Timing constraint | Reset path timed like data | Reset path has separate AR timing |
| CDC safety | Easier (treated as data) | Needs reset synchroniser |
| STA coverage | Fully covered by STA | Removal/recovery time must be constrained |
| FPGA recommendation | Preferred for most designs | Use for power-on init or critical safety |

---

### Q2. What is the GSR (Global Set/Reset) in Xilinx FPGAs, and what does it do?

**Question:** Explain the GSR primitive. When does it activate, what does it do to flip-flops,
and what is the significance of the `INIT` attribute?

**Answer:**

The Global Set/Reset (GSR) is a dedicated, low-skew network in Xilinx FPGAs that initialises
every flip-flop and LUT RAM to a known state during configuration loading.

**When GSR activates:**
1. At power-on, during bitstream loading — all FFs are set to their `INIT` attribute value.
2. When the `PROG_B` pin is pulsed (forces re-configuration).
3. Optionally driven explicitly via the `STARTUP_ULTRASCALE` primitive's `GSR` port.

**What it does:**
- Sets every configurable FF to its `INIT` value. `INIT = 1'b0` clears the FF; `INIT = 1'b1` sets it.
- Operates independently of user logic clocks -- the GSR pulse is distributed on a dedicated
  global routing network with extremely low skew.
- Does NOT interact with the user's synchronous or asynchronous reset after configuration.

**The `INIT` attribute:**

```verilog
// Vivado infers INIT from the reset condition in RTL:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= 1'b0;   // Vivado sets INIT=0 on this FF
    else
        q <= d;
end

// If reset value is 1:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= 1'b1;   // Vivado sets INIT=1, maps to FF's PRE pin instead of CLR
    else
        q <= d;
end
```

**Practical implication:** Because GSR initialises all FFs at configuration time, an FPGA
design does not strictly require an explicit user-driven reset for power-on initialisation.
Many production FPGA designs rely on GSR for initial state and use explicit resets only for
runtime re-initialisation (e.g., after an error recovery or a mode change).

**Common mistake:** Relying on GSR alone for a design that also needs runtime reset. GSR
cannot be used as a periodic reset mechanism — it only fires during configuration. After
configuration, runtime reset must use the explicit logic reset network.

---

### Q3. Why is asynchronous reset release (de-assertion) dangerous without synchronisation?

**Question:** Explain the metastability risk at reset de-assertion and why synchronous reset
release is the industry-standard mitigation.

**Answer:**

When an asynchronous reset is de-asserted (reset released), all FFs in the design see the
de-assertion at different times due to routing skew across the FPGA fabric. If the release
happens near a clock edge, different FFs may sample the de-assertion on different clock cycles.
This creates a one-cycle window where some FFs have left reset and others have not, potentially
violating design invariants.

More critically, if reset de-asserts within the setup/hold window of a FF's asynchronous
clear/preset input relative to the clock, the FF can go metastable during the recovery
(technically, this is a violation of the "recovery time" specification of the FF's async reset).

**The recommended pattern — asynchronous assert, synchronous de-assert:**

```
                                    Reset synchroniser
                                 ┌──────────────────────┐
raw_rst_n (async) ───────────┬──► CLR      stage1       │
                             │   ┌──────────────────┐   │
                             │   │ ┌───┐   ┌───┐   │   │
clk ─────────────────────────┼──►│ │FF1│──►│FF2│──► sync_rst_n
                             │   │ └───┘   └───┘   │   │
                             └──► CLR   CLR         │   │
                                 └──────────────────┘   │
                                 └──────────────────────┘
```

```systemverilog
module reset_synchroniser (
    input  logic clk,
    input  logic async_rst_n,   // async assertion (active low)
    output logic sync_rst_n     // synchronised release
);
    // ASYNC_REG is mandatory: ensures adjacent placement and
    // triggers correct CDC analysis in Vivado's report_cdc
    (* ASYNC_REG = "TRUE" *) logic ff1, ff2;

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            ff1 <= 1'b0;    // async assert: both stages immediately clear
            ff2 <= 1'b0;
        end else begin
            ff1 <= 1'b1;    // sync release: '1' walks through the chain
            ff2 <= ff1;
        end
    end

    assign sync_rst_n = ff2;
endmodule
```

**Behaviour:**
- **Assert (raw_rst_n = 0):** Both FFs immediately clear regardless of clock.
  Reset propagates to the entire design instantly.
- **De-assert (raw_rst_n = 1):** The two FFs sample '1' on successive clock edges.
  The design exits reset synchronously with the clock, two cycles after release.

**Why two stages?** FF1 may be metastable if `async_rst_n` releases near a clock edge.
FF2 waits an additional full clock period for FF1 to resolve, then captures a stable value.

---

## Intermediate

### Q4. How do you handle reset distribution for a large FPGA design with high fanout?

**Question:** A design has a single synchronised reset driving 50,000 flip-flops. Describe the
problems this causes and the Vivado-based strategies for solving them.

**Answer:**

**The fanout problem:**

A net with fanout 50,000 has extremely long routing paths to many of its destinations. This
creates:
1. **Timing violations:** High-fanout nets have large RC delays that can violate setup time
   on the reset-to-Q path (recovery time analysis).
2. **Insertion delay variation:** Skew across the reset tree means different FFs exit reset
   at different times, potentially causing transient glitches.
3. **Routing congestion:** A single high-fanout net stresses the routing fabric and may force
   sub-optimal placement of surrounding logic.

**Strategy 1: Automatic replication via MAX_FANOUT**

```tcl
# Tell Vivado to replicate the reset register to limit fanout
set_property MAX_FANOUT 64 [get_cells reset_sync_inst/ff2_reg]
# Vivado will insert copies of the reset FF and distribute them across the fabric
```

**Strategy 2: Manual reset pipeline tree**

Insert explicit pipeline registers close to the logic they serve, forming a tree:

```systemverilog
// Level 0: reset synchroniser (one instance per clock domain)
// Level 1: replicated buffer registers, placed close to load groups
(* DONT_TOUCH = "TRUE" *)
(* KEEP = "TRUE"        *)
logic rst_n_buf [0:NUM_REGIONS-1];

genvar i;
generate
    for (i = 0; i < NUM_REGIONS; i++) begin : gen_rst_buf
        always_ff @(posedge clk or negedge sync_rst_n) begin
            if (!sync_rst_n) rst_n_buf[i] <= 1'b0;
            else             rst_n_buf[i] <= 1'b1;
        end
    end
endgenerate
```

**Strategy 3: Use Pblocks to co-locate reset buffers with their loads**

```tcl
# Create a Pblock per region and assign both the buffer register and its loads
create_pblock pb_region0
add_cells_to_pblock pb_region0 [get_cells {reset_buf[0] datapath_region0/*}]
resize_pblock pb_region0 -add SLICE_X0Y0:SLICE_X50Y100
```

**Strategy 4: Use BUFG for reset (careful use)**

On Xilinx FPGAs, a `BUFG` drives a global clock network with near-zero skew to every FF in
the device. Driving a reset on a `BUFG` ensures ultra-low skew distribution, but consumes a
scarce clock buffer resource. Reserve this for designs with strict reset timing requirements.

```tcl
# Mark the reset net to use a global buffer
set_property CLOCK_BUFFER_TYPE BUFG [get_nets sync_rst_n]
```

**Recommendation for most designs:** MAX_FANOUT replication (strategy 1) handled automatically
by Vivado is the simplest approach. Use manual pblocks and BUFG only when timing closure
cannot be achieved otherwise.

---

### Q5. Explain the differences between synchronous and asynchronous reset in terms of FPGA resource usage, and which Xilinx recommends for UltraScale.

**Question:** Xilinx application notes have historically changed their reset recommendations
across device generations. What does Xilinx recommend for UltraScale and UltraScale+, and why?

**Answer:**

**Historical background:**

For Virtex-4 and earlier devices, asynchronous reset was recommended because the FF's
dedicated async CLR pin was free (no LUT needed) and the synchronous reset path required
a LUT-based MUX.

For 7-Series and later, Xilinx shifted toward recommending synchronous reset for most logic.

**UltraScale recommendation: Synchronous reset preferred**

Reasons:

1. **SRL (Shift Register LUT) compatibility:** SRLs do not have asynchronous reset capability.
   Designs with asynchronous reset on SRLs force synthesis to use standard FFs instead, losing
   the density benefit of SRLs.

2. **Timing closure:** Synchronous reset is treated as a data signal, fully covered by standard
   setup/hold timing analysis. Asynchronous reset requires separate recovery/removal analysis,
   which can be harder to close on large designs.

3. **Clock gating / power:** Synchronous reset integrates cleanly with clock enable signals
   and power-gating strategies. Asynchronous reset can create unexpected power spikes.

4. **Slice packing:** UltraScale slices can pack FFs more densely when all FFs in a slice
   share the same SR polarity and type. A mix of sync and async resets prevents optimal packing.

**When asynchronous reset is still appropriate in UltraScale:**

- Power-on initialisation where GSR cannot be relied upon (e.g., partial reconfiguration).
- Safety-critical functions where the FF must de-assert immediately regardless of clock state.
- Designs migrating from ASIC where async reset is mandated by the design methodology.

**The Xilinx UG949 (UltraScale Design Methodology) guideline:**

> "For most general-purpose logic, use synchronous reset. Reserve asynchronous reset for
> power-on initialisation and interface IPs where specification mandates immediate reset."

---

### Q6. How do you handle resets in a multi-clock design with multiple clock domains?

**Question:** A design has four clock domains: CPU (100 MHz), DDR (200 MHz), Ethernet (125 MHz),
and DSP (400 MHz). Describe the reset architecture.

**Answer:**

Each clock domain requires its own reset synchroniser, because each domain's reset must be
synchronous to its own clock. A single shared reset cannot be used directly.

```
             Raw reset (async, from board or watchdog)
                    |
          ┌─────────┼─────────────────────────────────┐
          │         │                                  │
          ▼         ▼              ▼                   ▼
    reset_sync   reset_sync   reset_sync          reset_sync
    (clk_cpu)   (clk_ddr)    (clk_eth)           (clk_dsp)
          │         │              │                   │
          ▼         ▼              ▼                   ▼
    cpu_rst_n   ddr_rst_n    eth_rst_n           dsp_rst_n
          │         │              │                   │
          └─────────┴──────────────┴───────────────────┘
                   (each drives its own clock domain)
```

**Reset sequencing considerations:**

Some interfaces require specific reset ordering. For example:
- A DDR memory controller must be reset before the user logic that accesses it.
- PCIe requires a specific reset sequence with the link partner.

```systemverilog
// Simple sequenced reset: release DDR reset first, then CPU
// after DDR has had N cycles to initialise
module reset_sequencer (
    input  logic clk,
    input  logic raw_rst_n,
    output logic ddr_rst_n,    // released first
    output logic cpu_rst_n     // released after DDR
);
    (* ASYNC_REG = "TRUE" *) logic stage1, stage2;
    logic [$clog2(64)-1:0] ddr_init_count;
    logic ddr_ready;

    // Step 1: synchronise raw reset
    always_ff @(posedge clk or negedge raw_rst_n) begin
        if (!raw_rst_n) begin
            stage1 <= 1'b0;
            stage2 <= 1'b0;
        end else begin
            stage1 <= 1'b1;
            stage2 <= stage1;
        end
    end

    assign ddr_rst_n = stage2;

    // Step 2: count cycles after DDR reset release, then release CPU reset
    always_ff @(posedge clk or negedge stage2) begin
        if (!stage2) begin
            ddr_init_count <= '0;
            ddr_ready      <= 1'b0;
        end else begin
            if (!ddr_ready) begin
                ddr_init_count <= ddr_init_count + 1'b1;
                if (ddr_init_count == '1)  // all ones
                    ddr_ready <= 1'b1;
            end
        end
    end

    assign cpu_rst_n = ddr_ready;
endmodule
```

**XDC constraints for multi-domain reset:**

```tcl
# Each reset synchroniser output is a clean synchronised signal --
# constrain the async input paths to the synchroniser FFs
set_false_path -from [get_ports raw_rst_n] \
               -to   [get_cells -hier -filter {ASYNC_REG == TRUE}]

# Verify recovery/removal times on async reset paths
set_max_delay -datapath_only -from [get_ports raw_rst_n] \
              -to [get_cells -hier -filter {ASYNC_REG == TRUE}] 10.0
```

---

## Advanced

### Q7. What are the removal and recovery timing constraints for asynchronous reset, and how do you apply them in Vivado?

**Question:** Define recovery time and removal time for an asynchronous reset. Show the XDC
constraints needed to verify them in Vivado.

**Answer:**

For asynchronous reset inputs to a flip-flop, the relevant timing checks are:

**Recovery time:** The minimum time that the asynchronous reset (CLR/PRE) must be de-asserted
(inactive) before the next active clock edge. If reset de-asserts too close to the clock edge,
the FF may not correctly exit reset on that clock cycle.

**Removal time:** The minimum time that the asynchronous reset must remain asserted after
the active clock edge. If reset de-asserts immediately after the clock edge, the FF's output
may be indeterminate.

```
                   Recovery time
                       ◄──►
CLR  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾|         |‾‾‾‾
                             ▲
                           clk posedge
           |◄──►|
          Removal time
CLR  _____|    |_______________
                ▲
              clk posedge
```

**Applying constraints in Vivado:**

```tcl
# Vivado automatically checks recovery/removal when async reset paths exist.
# To ensure proper analysis, constrain the raw reset as an input port:

# Specify maximum input delay for async reset relative to any clock
set_input_delay -clock [get_clocks clk] -max 2.0 [get_ports rst_n]
set_input_delay -clock [get_clocks clk] -min 1.0 [get_ports rst_n]

# For paths that should NOT be timed (fully async resets through synchronisers):
set_false_path -from [get_ports rst_n] \
               -to   [get_cells -hier -filter {ASYNC_REG == TRUE}]

# To explicitly check recovery/removal on the synchroniser output:
# (After the synchroniser, reset is synchronous -- standard setup/hold applies)
```

**Practical note:** In most FPGA designs using the async-assert/sync-de-assert pattern,
the raw reset input to the synchroniser is constrained as a false path (because metastability
is handled by the synchroniser itself). The recovery/removal check only matters if:
- The asynchronous reset is not going through a synchroniser.
- The design requires formal proof of reset timing compliance (e.g., safety-critical).

---

### Q8. How do partial reconfiguration (PR) regions affect reset strategy in Xilinx UltraScale?

**Question:** Describe the reset considerations specific to Partial Reconfiguration (PR) in
Vivado. What happens to FFs in a Reconfigurable Module during and after reconfiguration?

**Answer:**

**Reset during PR:**

When a Reconfigurable Module (RM) is being loaded via ICAP (Internal Configuration Access
Port), the FFs in that PR region are initialised to their `INIT` attribute values — exactly
as they are during full bitstream load. This is essentially a localised GSR for the PR region.

**Critical requirement:** The static region must hold the PR region in a defined safe state
(typically reset) for the entire duration of reconfiguration. This is achieved through the
PR decoupler pattern:

```
Static region interface logic:
  - Assert reset to the RM's ports before triggering reconfiguration
  - Hold reset asserted during the entire ICAP loading sequence
  - Release reset only after the RM bitstream is fully loaded and ICAP reports done
  - This prevents partially-configured logic from driving buses or asserting protocols
```

**Vivado implementation:**

```tcl
# Create the Reconfigurable Module with a reset input from static logic
# The static logic's reset synchroniser drives the RM's reset port

# In the RM's top-level port:
# input logic rst_n_from_static  -- driven by static region only
#                                -- asserted during reconfiguration by static FSM
```

**AXI decoupler IP:**

Xilinx provides the AXI-Lite decoupler IP specifically for PR designs. It stubs out AXI
transactions during reconfiguration, preventing protocol violations. Part of its function
is to manage the reset handshake between the static and reconfigurable regions.

**After reconfiguration:**

When the new RM bitstream is loaded, all FFs in the region are in their `INIT` state. The
static logic's reset FSM then releases reset synchronously, allowing the new RM to start up
cleanly. If the static logic does not wait for the ICAP `DONE` signal, the RM may start
with partially configured logic, leading to unpredictable behaviour.

---

### Q9. Walk through a complete reset architecture for a production Xilinx UltraScale+ design.

**Question:** Describe, from external pin to individual flip-flop, a complete reset architecture
for a production design with synchronous reset, multiple clock domains, and correct Vivado
constraints.

**Answer:**

```
EXTERNAL PIN (active-low, async, from board reset circuitry)
    |
    | [Input buffer, no IO delay -- false path constraint applied]
    |
    ▼
RAW_RST_N (async signal in FPGA fabric)
    |
    ├──► RESET_SYNC (clk_sys, 200 MHz)  -> sys_rst_n   [drives CPU logic]
    ├──► RESET_SYNC (clk_eth, 125 MHz)  -> eth_rst_n   [drives Ethernet MAC]
    ├──► RESET_SYNC (clk_dsp, 400 MHz)  -> dsp_rst_n   [drives DSP pipeline]
    └──► RESET_SYNC (clk_mem, 300 MHz)  -> mem_rst_n   [drives memory controller]

Each RESET_SYNC is a 2-FF async-assert/sync-deassert synchroniser with ASYNC_REG.
```

**Complete RTL skeleton:**

```systemverilog
module top_reset (
    input  logic clk_sys, clk_eth, clk_dsp, clk_mem,
    input  logic raw_rst_n,          // from IBUF

    output logic sys_rst_n,
    output logic eth_rst_n,
    output logic dsp_rst_n,
    output logic mem_rst_n
);
    // One reset synchroniser per clock domain
    reset_synchroniser u_sys_rst  (.clk(clk_sys), .async_rst_n(raw_rst_n), .sync_rst_n(sys_rst_n));
    reset_synchroniser u_eth_rst  (.clk(clk_eth), .async_rst_n(raw_rst_n), .sync_rst_n(eth_rst_n));
    reset_synchroniser u_dsp_rst  (.clk(clk_dsp), .async_rst_n(raw_rst_n), .sync_rst_n(dsp_rst_n));
    reset_synchroniser u_mem_rst  (.clk(clk_mem), .async_rst_n(raw_rst_n), .sync_rst_n(mem_rst_n));

endmodule
```

**Complete XDC constraints:**

```tcl
# 1. Constrain all input clocks
create_clock -period 5.000 -name clk_sys [get_ports clk_sys]
create_clock -period 8.000 -name clk_eth [get_ports clk_eth]
create_clock -period 2.500 -name clk_dsp [get_ports clk_dsp]
create_clock -period 3.333 -name clk_mem [get_ports clk_mem]

# 2. False path from raw_rst_n to all synchroniser FFs
#    (metastability is handled by the synchroniser -- no timing required on this path)
set_false_path -from [get_ports raw_rst_n] \
               -to   [get_cells -hierarchical -filter {ASYNC_REG == TRUE}]

# 3. Verify that synchronised reset outputs have appropriate fanout
#    (if timing fails, increase MAX_FANOUT resolution or add pipeline registers)
set_property MAX_FANOUT 100 \
    [get_cells -hier -filter {NAME =~ *u_*_rst/ff2_reg}]

# 4. Report CDC to verify no uncharacterised crossings
# run: report_cdc -details -file reset_cdc.txt
```

**All downstream logic uses synchronous reset driven from the per-domain synchronised output:**

```systemverilog
// In DSP domain -- uses synchronous reset
always_ff @(posedge clk_dsp) begin
    if (!dsp_rst_n)
        pipeline_reg <= '0;
    else
        pipeline_reg <= pipeline_data;
end
```

This architecture provides:
- Deterministic per-domain reset assertion and release.
- No metastability in any clock domain.
- Vivado CDC clean (`report_cdc` shows zero uncharacterised crossings).
- Correct recovery/removal compliance (verified by `set_false_path` scope).

---

## Quick-Reference Summary

```
Reset Type Selection:
─────────────────────────────────────────────────────────────────────────────
Use synchronous reset when:
  - Targeting UltraScale/UltraScale+ (Xilinx recommendation)
  - Using SRLs (async reset forces full FFs)
  - Timing closure is critical
  - Multiple FFs share a clock enable

Use asynchronous reset when:
  - Safety-critical immediate de-assertion is required
  - Design originates from ASIC with async-reset mandate
  - Power-on initialisation without relying on GSR

Always use async-assert / sync-deassert pattern when:
  - The raw reset source is truly asynchronous (external pin, watchdog, POR)
  - Crossing clock domains with reset signals

Always apply ASYNC_REG to synchroniser FFs.
Apply set_false_path or set_max_delay to the async input of synchroniser FFs.
─────────────────────────────────────────────────────────────────────────────
```
