# IP Core Integration

## Overview

Virtually every production FPGA design uses vendor IP cores. Xilinx Vivado's IP Catalog and
IP Integrator (Block Design) environment provide pre-verified, parameterisable modules for
functions ranging from memory controllers to PCIe endpoints to floating-point units. Knowing
how to select, customise, integrate, constrain, and version-manage IP cores is a core
competency that comes up in both FPGA engineer and FPGA verification engineer interviews.

---

## Fundamentals

### Q1. What is the Xilinx IP Catalog, and how do you add an IP core to a Vivado project?

**Question:** Describe the Xilinx IP Catalog workflow: discovery, customisation, generation,
and instantiation. What files are generated and which should be checked into version control?

**Answer:**

**The IP Catalog** is Vivado's library of pre-built, parameterisable IP cores covering
communication protocols, memory interfaces, math functions, DSP blocks, clocking, and more.

**Workflow:**

```
1. Open IP Catalog (IP Catalog tab in Vivado)
2. Search for the required IP (e.g., "FIFO Generator", "AXI4 Interconnect")
3. Double-click to open the IP Customisation GUI
4. Configure parameters (data widths, depths, protocol options)
5. Click "OK" -> IP is added to the project
6. Select "Generate Output Products" (synthesis, simulation, and constraint files)
7. Instantiate the IP in RTL using the provided wrapper
```

**Files generated:**

```
<project>/<project>.srcs/sources_1/ip/<ip_name>/
  <ip_name>.xci          # IP Configuration file (JSON-like) -- CHECK IN
  <ip_name>_stub.v       # Synthesis stub                    -- DO NOT check in
  <ip_name>_sim_netlist.v # Simulation netlist               -- DO NOT check in
  <ip_name>.dcp          # Design checkpoint                 -- DO NOT check in
  hdl/                   # Generated RTL                     -- DO NOT check in
  constraints/           # Generated XDC                     -- DO NOT check in
  doc/                   # Documentation                     -- DO NOT check in
```

**Version control rule:** Only the `.xci` file (IP configuration) should be committed.
All generated output products can be regenerated from `.xci` by running:

```tcl
generate_target all [get_ips <ip_name>]
# or automatically when opening the project in Vivado
```

**The `.xci` approach** ensures that:
- Repository size stays small (no large generated netlists).
- The exact IP version and parameters are reproducible.
- Team members can regenerate products for their Vivado version.

**Instantiation example (FIFO Generator):**

```systemverilog
// Instantiation template from <ip_name>_stub.v
fifo_generator_0 u_fifo (
    .clk         (clk),
    .srst        (srst),
    .din         (write_data),
    .wr_en       (write_enable),
    .rd_en       (read_enable),
    .dout        (read_data),
    .full        (fifo_full),
    .empty       (fifo_empty),
    .data_count  (fill_level)
);
```

---

### Q2. What is the difference between an Out-of-Context (OOC) IP and an in-context IP in Vivado?

**Question:** Explain Out-of-Context synthesis. What are its advantages and when should it
be disabled?

**Answer:**

**In-context synthesis:** The IP is synthesised as part of the top-level design. The full
design hierarchy is synthesised together in one run.

**Out-of-Context (OOC) synthesis:** The IP is synthesised separately from the top-level
design, in its own synthesis run, before the top-level synthesis starts. The result is a
Design Checkpoint (`.dcp`) file that represents a fully synthesised, black-box version of
the IP.

```
OOC synthesis flow:
  1. IP .xci -> OOC synth run -> .dcp (pre-synthesised)
  2. Top-level synthesis -> references the .dcp as a black box
  3. Implementation elaborates the black box from the .dcp

In-context flow:
  1. IP RTL + Top-level RTL -> single synthesis run
```

**Advantages of OOC:**

| Advantage | Explanation |
|---|---|
| Speed | IP only re-synthesises when its parameters change, not on every design rebuild |
| Reproducibility | The same .dcp is used regardless of top-level changes |
| IP portability | .dcp can be delivered as a black box to other teams (IP protection) |
| Parallel synthesis | Multiple IPs can synthesise in parallel |

**When to disable OOC (use in-context):**

- When the IP has parameters that depend on elaboration-time values from the top level.
- When cross-boundary optimisation is needed (e.g., constant propagation into the IP).
- When debugging IP internals (OOC creates a black box; in-context exposes internal signals to ILA).
- Small, simple IPs where the OOC overhead exceeds the benefit.

```tcl
# Disable OOC for a specific IP:
set_property GENERATE_SYNTH_CHECKPOINT false [get_files your_ip.xci]
```

---

### Q3. What is the AXI Interconnect IP, and what are the key parameters to configure when adding it in IP Integrator?

**Question:** Describe the Xilinx AXI Interconnect (or AXI SmartConnect) IP. What are the
critical parameters and what timing/resource implications do they have?

**Answer:**

The **AXI Interconnect** and its replacement **AXI SmartConnect** are bus fabric IPs that
connect multiple AXI master interfaces (e.g., a CPU, a DMA engine) to multiple AXI slave
interfaces (e.g., BRAM controllers, peripheral registers, DDR memory controllers).

**AXI Interconnect vs. AXI SmartConnect:**

| Feature | AXI Interconnect | AXI SmartConnect |
|---|---|---|
| Generation | Older (Vivado legacy) | Recommended (current) |
| Clock crossing | Manual (separate Clock Converter) | Automatic (built-in CDC) |
| Width conversion | Manual (separate Data Width Converter) | Automatic |
| Area efficiency | Higher (configurable) | Lower (automatic logic) |
| Configuration complexity | Higher | Lower |

**Key parameters for AXI SmartConnect:**

```
NUM_SI (Number of Slave Interfaces) = N masters connecting to the bus
NUM_MI (Number of Master Interfaces) = N slaves on the bus
S00_HAS_REGSLICE ... (register slices per port for timing)
```

**Register slices:** The most important timing parameter. A register slice inserts a
pipeline register stage on an AXI channel. This:
- Adds one cycle of latency per channel per stage.
- Breaks timing paths through the interconnect (critical for closing timing above 200 MHz).
- Is the primary tool for resolving timing violations in AXI interconnects.

```tcl
# In IP Integrator, set register slices via property:
set_property CONFIG.REGISTER_SLICE_SETTING {3} [get_bd_cells axi_smc]
# Value 3 = register slices on all channels (AW, W, B, AR, R)
```

**Address map configuration:**

Each master-to-slave connection requires an address assignment:

```tcl
# In IP Integrator Tcl script:
assign_bd_address [get_bd_addr_segs {your_slave/s_axi/reg0}]
set_property offset 0x44A00000 [get_bd_addr_segs {cpu_m_axi/SEG_your_slave_reg0}]
set_property range  4K         [get_bd_addr_segs {cpu_m_axi/SEG_your_slave_reg0}]
```

---

## Intermediate

### Q4. How do you integrate a custom RTL module with AXI-Lite registers into Vivado IP Integrator?

**Question:** Describe the steps to create a custom IP from RTL, make it available in the
IP Catalog, and wire it into a block design with AXI-Lite connectivity.

**Answer:**

**Step 1: Package the custom RTL as a Vivado IP.**

```tcl
# In Vivado Tcl console:
# 1. Create a new IP project for packaging
ipx::open_ipxact_file [get_property DIRECTORY [current_project]]

# Or use the IP Packager GUI:
# Tools -> Create and Package New IP -> Package a specified directory
```

The IP Packager scans the RTL directory and automatically identifies:
- Ports with standard names (e.g., `s_axi_*` ports become an AXI4-Lite bus interface).
- Clocks, resets, and interrupts.

**Step 2: Define the AXI-Lite register map.**

The key interface for control plane access is AXI4-Lite. The IP Packager maps the
`s_axi_*` port group to an AXI4-Lite slave interface automatically if port names follow
the Xilinx AXI naming convention:

```systemverilog
// RTL port declarations using AXI-Lite naming convention:
// Vivado IP Packager auto-infers this as an AXI4-Lite slave interface
module my_custom_ip #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 6
) (
    // AXI-Lite slave interface (naming convention triggers auto-inference)
    input  logic                            s_axi_aclk,
    input  logic                            s_axi_aresetn,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic                            s_axi_awvalid,
    output logic                            s_axi_awready,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  logic [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                            s_axi_wvalid,
    output logic                            s_axi_wready,
    output logic [1:0]                      s_axi_bresp,
    output logic                            s_axi_bvalid,
    input  logic                            s_axi_bready,
    // ... AR, R channels ...
    // User logic ports:
    output logic [31:0]                     control_reg,
    input  logic [31:0]                     status_reg
);
```

**Step 3: Add the packaged IP to the User Repository.**

```tcl
# Add the packaged IP directory to the IP Repository
set_property IP_REPO_PATHS {/path/to/my_ip_repo} [current_project]
update_ip_catalog
# The IP now appears in the IP Catalog under "User Repository"
```

**Step 4: Instantiate in IP Integrator (Block Design).**

```tcl
# Add the custom IP to the block design:
create_bd_cell -type ip -vlnv user.org:user:my_custom_ip:1.0 my_custom_ip_0

# Connect AXI-Lite interface to the SmartConnect / AXI Interconnect:
connect_bd_intf_net [get_bd_intf_pins cpu/M_AXI] \
    [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
    [get_bd_intf_pins my_custom_ip_0/s_axi]

# Assign address:
assign_bd_address [get_bd_addr_segs my_custom_ip_0/s_axi/reg0]
set_property offset 0x43C00000 [get_bd_addr_segs ...]
```

---

### Q5. How do you manage IP versioning when upgrading Vivado versions in a team environment?

**Question:** Describe the IP versioning problem in Vivado. What happens when a project is
opened on a newer Vivado version where some IPs have changed version numbers? What is the
recommended team workflow?

**Answer:**

**The IP versioning problem:**

When Vivado is upgraded (e.g., from 2023.1 to 2023.2), some IP cores ship with new version
numbers (e.g., `fifo_generator_0` upgrades from 13.2 to 13.3). The `.xci` file contains
the exact version number. Opening the project in the newer Vivado generates a warning:

```
[IP_Flow 19-3831] IP 'fifo_generator_0' version '13.2' is
not supported in this version of the tool. Version '13.3' is available.
Please re-customize the IP.
```

The IP is locked and cannot generate output products until it is explicitly upgraded.

**The upgrade process:**

```tcl
# In Vivado Tcl:
# Step 1: Check which IPs need upgrading
report_ip_status

# Step 2: Upgrade specific IPs
upgrade_ip [get_ips fifo_generator_0]
# Or upgrade all:
upgrade_ip [get_ips *]

# Step 3: Regenerate output products
generate_target all [get_ips *]

# Step 4: Verify the design still functions correctly
# (Run simulation and implementation after upgrade)
```

**The `.xci` version change after upgrade:**

After upgrading, the `.xci` file is modified to reference the new version. This change
must be committed to version control, and the team must agree on which Vivado version is
the project baseline.

**Recommended team workflow:**

```
1. Define a project Vivado baseline version (e.g., 2024.1).
   Document this in the README and project settings.

2. Lock IP versions: do not upgrade IP unless there is a specific reason.
   "If it works, don't upgrade."

3. When upgrading: do so in a dedicated branch, run full regression,
   review the .xci diffs, then merge to main.

4. Use the export_ip_user_files Tcl command to export all .xci and
   relevant constraints for offline/CI reproduction:
```

```tcl
# Export all IP sources for reproducible builds:
export_ip_user_files -of_objects [get_ips] \
    -no_script -sync -force -quiet

# Generate a Tcl script that can recreate the entire project
# (including all IP .xci configurations) from scratch:
write_project_tcl recreate_project.tcl
```

**CI/CD recommendation:**

In a CI pipeline, always regenerate IP output products from `.xci` rather than committing
generated files. This ensures the build is always consistent with the checked-in configuration:

```bash
# In CI script:
vivado -mode batch -source regenerate_ip.tcl
# regenerate_ip.tcl:
#   open_project my_project.xpr
#   upgrade_ip [get_ips *]           # upgrade any locked IPs
#   generate_target all [get_ips *]  # regenerate output products
#   export_ip_user_files ...
```

---

### Q6. How do you add timing constraints for a third-party IP core that does not provide XDC constraints?

**Question:** You have instantiated a third-party IP core that generates output products
but includes no XDC constraint file. The implementation shows timing violations on paths
entering and leaving the IP. Describe your approach.

**Answer:**

**Step 1: Understand the IP's timing model.**

Read the IP's datasheet or application note to determine:
- Clock domains inside the IP.
- Input and output timing requirements relative to those clocks.
- Whether internal paths are pipelined (registered inputs/outputs) or combinational pass-through.

**Step 2: Identify unconstrained paths.**

```tcl
# Find paths with no constraints (no launch or capture clock):
report_timing_summary -unconstrained
# Look for: "Unconstrained paths" section

# More targeted:
report_timing -from [get_pins {third_party_ip_inst/*}] -unconstrained
```

**Step 3: Apply constraints based on IP behaviour.**

```tcl
# Case A: IP is fully registered (outputs stable one cycle after inputs)
# Constrain the IP's ports to the system clock:
set_input_delay  -clock [get_clocks clk_sys] -max 2.0 \
    [get_ports {third_party_ip_inst/data_in[*]}]
set_output_delay -clock [get_clocks clk_sys] -max 1.5 \
    [get_ports {third_party_ip_inst/data_out[*]}]

# Case B: IP has internal clock (e.g., it uses a generated clock from PLL)
# First declare the generated clock:
create_generated_clock -name clk_ip_internal \
    -source [get_pins third_party_ip_inst/pll_inst/CLKOUT0] \
    -divide_by 1 \
    [get_nets clk_ip_internal_net]

# Case C: IP has static control signals (e.g., configuration registers)
# that change only at reset -- false path:
set_false_path -from [get_cells {third_party_ip_inst/config_reg*}]

# Case D: IP has CDC internally (documented in datasheet)
# Suppress timing on internal CDC paths:
set_false_path -from [get_clocks clk_src] \
               -to   [get_clocks clk_dst] \
               -through [get_cells {third_party_ip_inst/*}]
```

**Step 4: Verify with timing reports.**

```tcl
report_timing_summary -file timing_after_constraints.txt
# Goal: 0 unconstrained paths, 0 timing violations
```

**Best practice:** If the IP vendor provides no XDC, request one. Document any constraints
you add and their justification in a comment in the XDC file, so future engineers understand
why the constraints exist.

---

## Advanced

### Q7. Describe the Vivado Block Design (IP Integrator) workflow for a Zynq-7000 system with custom IP and AXI connectivity.

**Question:** Walk through the creation of a Zynq-7000 block design that connects a custom
AXI-Lite peripheral to the PS (Processing System) via the M_AXI_GP0 interface. Include the
address map, clock distribution, and reset connections.

**Answer:**

**Block design structure:**

```
┌──────────────────────────────────────────────────────┐
│ Block Design: zynq_system                            │
│                                                      │
│  ┌─────────────┐  M_AXI_GP0  ┌───────────────────┐  │
│  │ Zynq PS7    ├─────────────► AXI SmartConnect   │  │
│  │ (ARM Cortex │             │ (1 master, 1 slave)│  │
│  │  A9)        │             └────────┬──────────┘  │
│  │             │  FCLK_CLK0           │              │
│  │             ├──────────────────────┤ clk          │
│  │             │  FCLK_RESET0_N       │              │
│  │             ├────────────► proc_sys_reset         │
│  └─────────────┘                      │              │
│                                       │ M00_AXI      │
│                              ┌────────▼────────┐    │
│                              │ my_custom_ip_0  │    │
│                              │ (AXI-Lite slave)│    │
│                              └─────────────────┘    │
└──────────────────────────────────────────────────────┘
```

**Tcl script to create the block design:**

```tcl
# Create block design
create_bd_design "zynq_system"

# Add Zynq PS7
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR"} [get_bd_cells ps7_0]

# Configure PS7: enable M_AXI_GP0, set clock to 100 MHz
set_property CONFIG.PCW_USE_M_AXI_GP0 {1} [get_bd_cells ps7_0]
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} [get_bd_cells ps7_0]

# Add proc_sys_reset for synchronised reset
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_0
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] \
               [get_bd_pins reset_0/ext_reset_in]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] \
               [get_bd_pins reset_0/slowest_sync_clk]

# Add AXI SmartConnect (1 master, 1 slave)
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc
set_property CONFIG.NUM_SI {1} [get_bd_cells axi_smc]
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_smc]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] \
               [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins reset_0/interconnect_aresetn] \
               [get_bd_pins axi_smc/aresetn]

# Connect PS7 M_AXI_GP0 to SmartConnect
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_smc/S00_AXI]

# Add custom IP
create_bd_cell -type ip -vlnv user.org:user:my_custom_ip:1.0 my_custom_ip_0
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] \
               [get_bd_pins my_custom_ip_0/s_axi_aclk]
connect_bd_net [get_bd_pins reset_0/peripheral_aresetn] \
               [get_bd_pins my_custom_ip_0/s_axi_aresetn]

# Connect AXI interface
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
                    [get_bd_intf_pins my_custom_ip_0/s_axi]

# Assign address
assign_bd_address [get_bd_addr_segs my_custom_ip_0/s_axi/reg0]
set_property offset 0x43C00000 \
    [get_bd_addr_segs ps7_0/Data/SEG_my_custom_ip_0_reg0]
set_property range 64K \
    [get_bd_addr_segs ps7_0/Data/SEG_my_custom_ip_0_reg0]

# Validate and save
validate_bd_design
save_bd_design

# Generate HDL wrapper for the block design
make_wrapper -files [get_files zynq_system.bd] -top
add_files -norecurse ./zynq_system_wrapper.v
```

**Key points:**

1. **Clock distribution:** All AXI components (SmartConnect, custom IP) must share the same
   clock (`FCLK_CLK0`). Using different clocks on the same SmartConnect interface violates
   the AXI protocol.

2. **Reset hierarchy:** `proc_sys_reset` generates three reset outputs:
   - `interconnect_aresetn`: for AXI interconnect fabric.
   - `peripheral_aresetn`: for slave peripherals.
   - `bus_struct_reset`: for DMA/memory structures.
   Each should be connected to the appropriate component type.

3. **Address alignment:** AXI-Lite peripherals with N registers require an address range
   of at least 4*N bytes, aligned to a power-of-two boundary.

---

### Q8. How do you debug integration problems between IPs in a Vivado Block Design?

**Question:** Describe the debugging methodology for a system-level integration problem
in an IP Integrator design. Your custom AXI-Lite peripheral is not responding to CPU reads.

**Answer:**

**Step 1: Verify block design connectivity and address map.**

```tcl
# In Vivado GUI or Tcl:
validate_bd_design
# Vivado reports connectivity errors, missing connections, and address conflicts.

# Verify address map:
get_bd_addr_segs -of_objects [get_bd_cells my_custom_ip_0]
# Check that the base address matches the CPU's expected address
```

**Step 2: Simulate the block design.**

Export the block design simulation model and run a directed test:

```tcl
# Generate simulation scripts for the block design:
export_simulation -simulator xsim -of_objects [get_files zynq_system.bd] \
    -directory ./sim -force
```

Simulate with a simple AXI-Lite master BFM (or use Xilinx AXI VIP -- AXI Verification IP):

```systemverilog
// Use Xilinx AXI4-Lite VIP master to drive test transactions
// This is the recommended approach for IP Integrator debug simulation:
axi_vip_0_mst_t agent;
xil_axi_resp_t resp;
logic [31:0] rdata;

initial begin
    agent = new("axi_vip_0_mst", tb.axi_vip_0.inst.IF);
    agent.start_master();
    // Write to custom IP register at offset 0x43C00000
    agent.AXI4LITE_WRITE_BURST(64'h43C00000, 0, 32'hDEADBEEF, resp);
    // Read back
    agent.AXI4LITE_READ_BURST(64'h43C00000, 0, rdata, resp);
    $display("Read back: 0x%08X (expected 0xDEADBEEF)", rdata);
end
```

**Step 3: Use ILA to observe AXI transactions in hardware.**

Vivado System ILA is purpose-built for block design debugging. It is inserted directly
on AXI interfaces in IP Integrator:

```tcl
# In IP Integrator, mark the AXI interface for ILA probing:
# Right-click on the AXI net -> Debug -> Insert System ILA
# Or via Tcl:
apply_bd_automation -rule xilinx.com:bd_rule:debug \
    -dict [list \
        [get_bd_intf_nets axi_smc_to_custom_ip_net] \
        {AXI_R_ADDRESS true AXI_R_DATA true AXI_W_ADDRESS true AXI_W_DATA true}]
```

The System ILA captures full AXI4-Lite handshakes, showing AWVALID/AWREADY/WVALID/WREADY
and ARVALID/ARREADY/RVALID/RREADY transactions.

**Common causes of non-responding AXI-Lite slaves:**

| Symptom | Likely cause |
|---|---|
| AWVALID asserted, AWREADY never asserts | Slave reset not released (check aresetn) |
| AWREADY asserts, BVALID never asserts | Write state machine bug in custom IP |
| ARVALID asserted, ARREADY never asserts | Address decode error (wrong address range) |
| RVALID asserts but RDATA = 0xXXXXXXXX | Read state machine not driving RDATA before RVALID |
| AXI timeout (BRESP or RRESP = SLVERR) | Slave asserted error response due to illegal address |

**Step 4: Check the Vivado implementation messages.**

```tcl
# Critical warnings that indicate address or connectivity issues:
report_messages -severity CRITICAL_WARNING
# Look for: address range overlaps, unconnected AXI ports, missing clocks
```

---

## Quick-Reference Summary

```
IP Integration checklist for Vivado:
───────────────────────────────────────────────────────────────────────────
1. Version control: commit .xci only; regenerate output products in CI.
2. OOC synthesis: enabled by default for IP cores -- disables for in-context debug.
3. AXI SmartConnect: use for new designs; set register slices for timing closure.
4. Address assignment: every slave must have a unique, aligned address range.
5. Reset: use proc_sys_reset; connect interconnect_aresetn to fabric,
   peripheral_aresetn to slave peripherals.
6. Clocks: all AXI interfaces on the same SmartConnect must share one clock.
7. IP versioning: define project baseline Vivado version; upgrade IPs in branches.
8. Debug: System ILA for AXI protocol debug; AXI VIP for simulation-level testing.
9. Constraints: third-party IPs without XDC require manual constraint analysis.
10. Port naming: follow Xilinx AXI naming convention for auto-inference in IP Packager.
───────────────────────────────────────────────────────────────────────────
```
