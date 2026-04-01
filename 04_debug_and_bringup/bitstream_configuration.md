# Bitstream Configuration

## Overview

An FPGA bitstream is the binary file that programs the device's configuration memory —
interconnect switches, LUT contents, flip-flop initial values, I/O standard settings, and
clocking configurations. Understanding bitstream structure, configuration modes (how the
bitstream reaches the device), security mechanisms (encryption and authentication), partial
reconfiguration, and multi-boot strategies is critical for both production-quality designs and
robust field deployments. These topics appear frequently in hardware engineering interviews
because they sit at the boundary between hardware design, system architecture, and security.

---

## Fundamentals

### Question 1

**What are the main FPGA configuration modes? How does the device know which mode to use?**

**Answer:**

Configuration mode is selected by the values on dedicated MODE pins (on Xilinx devices, `M[2:0]`
or `M[1:0]` depending on the family). These pins are sampled at power-on deassertion of
`PROG_B` (the active-low program pin).

**Xilinx 7-series and UltraScale configuration modes:**

| Mode pins (M[2:0]) | Mode              | Description                                                      |
|---------------------|-------------------|------------------------------------------------------------------|
| 000                 | Master Serial     | FPGA drives SCK; reads bitstream from SPI flash (single x1)     |
| 001                 | Master SPI (x1/x2/x4) | FPGA drives SPI bus; reads from SPI flash (up to x4 quad) |
| 010                 | Master BPI        | FPGA drives parallel NOR flash (x8 or x16 data bus)             |
| 011                 | Master SelectMAP  | FPGA drives 8-bit or 32-bit parallel bus (host-driven variant)  |
| 100                 | JTAG              | Bitstream pushed via JTAG CFG_IN instruction                     |
| 101                 | Slave SelectMAP   | Host drives 8/16/32-bit parallel bus into FPGA                  |
| 110                 | Slave Serial      | Host drives single-bit serial data into FPGA CCLK/DIN           |
| 111                 | (reserved)        |                                                                  |

**Power-on sequence (simplified):**

1. All supply rails reach operating voltage.
2. `PROG_B` is released (deasserted high), or the device's internal power-on reset completes.
3. MODE pins sampled → configuration source selected.
4. Device initiates configuration: if master mode, drives the external memory; if slave mode,
   waits for the host to send data.
5. Bitstream received, CRC checked, startup sequence runs (`DONE` pin goes high).

**Key point:** if `DONE` never asserts, the device failed to configure. The first debug step is
to confirm which mode is actually selected (scope or logic analyse the MODE pins at power-on).

---

### Question 2

**What is the FPGA startup sequence and what signals indicate a successful configuration?**

**Answer:**

After the full bitstream has been loaded and its CRC verified, the device runs an internal
startup state machine before releasing the user design to operate. Xilinx devices use a startup
pipeline controlled by `STARTUP` block settings in the bitstream.

**Startup phases (default ordering, configurable in Vivado):**

```
Phase 0: CRC check completes
Phase 1: Wake up DCMs/MMCMs (release clock management blocks)
Phase 2: Release DCI (digitally-controlled impedance on matched I/Os)
Phase 3: Assert DONE (signals configuration success to external circuitry)
Phase 4: Release internal 3-state (I/Os driven by user design for first time)
Phase 5: Release global reset (GSR deasserted, flip-flops transition to initial values)
Phase 6: Release GTS (global 3-state removed, outputs become active)
```

**Key observable signals:**

| Signal     | Location     | Meaning                                                          |
|------------|--------------|------------------------------------------------------------------|
| `DONE`     | Device pin   | Asserts high when configuration completed successfully           |
| `INIT_B`   | Device pin   | Low during initialisation; released when configuration memory cleared |
| `PROG_B`   | Device pin   | Driving low forces reconfiguration from scratch                  |
| `CCLK`     | Device pin   | Configuration clock (master mode: driven by device; slave: driven by host) |

**During bring-up:** if `DONE` does not assert, check:
1. `INIT_B` — did it ever go high? If not, the device did not start its configuration attempt.
2. CRC error — the bitstream may be corrupted (wrong file, truncated download, SPI timing issue).
3. Power — are all rails within specification before `PROG_B` was released?
4. Bitstream target match — is the bitstream compiled for this exact device part number?

---

### Question 3

**What information is contained in a Xilinx bitstream file (.bit)? What is the difference
between a .bit file and a .bin file?**

**Answer:**

A `.bit` file contains:

1. **ASCII header:** design name, part target, date/time of generation (human-readable prefix).
2. **Sync word:** `0xAA995566` — the device searches for this to find the start of configuration
   data within the bitstream stream.
3. **Configuration packets:** a sequence of Type-1 and Type-2 packets in Xilinx's proprietary
   packet format. Each packet writes data to a named register (e.g., `FDRI` — frame data register
   input, `CTL0` — control register, `MASK`, `CRC`).
4. **Frame data:** the actual configuration memory contents, organised as configuration frames
   (the smallest addressable unit of FPGA configuration memory).
5. **CRC packets:** periodic CRC checks embedded in the stream; the device verifies these as
   it loads.
6. **Startup commands:** instructions to run the startup sequence at the end.

**Difference between .bit and .bin:**

| Format | Contents                                          | Use case                                           |
|--------|---------------------------------------------------|----------------------------------------------------|
| `.bit` | Header + configuration data                       | Vivado Hardware Manager, direct JTAG programming   |
| `.bin` | Configuration data only (no ASCII header)         | SPI/BPI flash programming, Slave SelectMAP hosts   |
| `.mcs` | Intel Hex format wrapping flash layout data       | Flash programming with address map                 |
| `.ltx` | Logic analyser probe description (not bitstream)  | ILA probe name association in Hardware Manager     |

When programming SPI flash, you use `.mcs` or `.bin` because the flash stores raw bytes without
the ASCII header. The FPGA's configuration engine reads raw bytes from flash starting at a
specified address; the ASCII header would confuse it.

---

## Intermediate

### Question 4

**Explain FPGA bitstream encryption. What problem does it solve, how does it work, and what
are its limitations?**

**Answer:**

**The problem:** an unencrypted bitstream can be read back from SPI flash or captured during
configuration and reverse-engineered to extract:
- Proprietary algorithms implemented in the FPGA.
- Security keys embedded as constants.
- IP worth protecting (DSP algorithms, cryptographic implementations, etc.).

**How encryption works (Xilinx AES-256-CBC):**

1. A 256-bit AES key is generated by the designer and stored in either:
   - The device's battery-backed non-volatile key storage (BBRAM) — volatile, lost when battery
     removed, suitable for field deployable systems.
   - The device's eFUSE key storage — permanently programmed, cannot be erased, suitable for
     high-security production.

2. During bitstream generation in Vivado, the bitstream is encrypted with this key using
   AES-256 in CBC mode. The encrypted bitstream is stored in flash.

3. At power-on, the FPGA reads the encrypted bitstream, decrypts it internally using the stored
   key, and loads the configuration. The plaintext configuration data never leaves the device.

```tcl
# Vivado: generate encrypted bitstream
set_property BITSTREAM.ENCRYPTION.ENCRYPT YES [current_design]
set_property BITSTREAM.ENCRYPTION.ENCRYPTKEYSELECT BBRAM [current_design]
set_property BITSTREAM.ENCRYPTION.KEY0 \
    0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF \
    [current_design]
write_bitstream -force encrypted_design.bit
```

**Limitations:**

| Limitation                          | Detail                                                        |
|-------------------------------------|---------------------------------------------------------------|
| Key management complexity           | The key must be securely provisioned to every device in production; a stolen key compromises all devices. |
| BBRAM volatility                    | BBRAM requires a battery; dead battery = device fails to configure. Must plan for battery replacement. |
| eFUSE irreversibility               | Once burned, eFUSE key cannot be changed; a compromised key requires device replacement. |
| Passive side-channel attacks        | Power analysis during decryption can potentially recover the AES key (though Xilinx implements countermeasures). |
| Does not prevent device cloning     | Encryption protects the bitstream, not the device itself. A sophisticated attacker may extract the key via invasive methods. |
| Readback disabling required         | Encryption without disabling readback still allows configuration readback of a decrypted version. Must also set `BITSTREAM.SECURITY.ENCRYPT_ONLY` or disable readback. |

---

### Question 5

**What is bitstream authentication and how does it complement encryption?**

**Answer:**

Encryption provides confidentiality — an observer cannot read the bitstream contents. However,
it does not prevent an attacker from feeding a modified or substituted bitstream into the device
(a bitstream substitution attack). Authentication adds integrity — the device verifies that the
bitstream was signed by a trusted party before loading it.

**Xilinx RSA authentication (UltraScale/UltraScale+):**

1. The designer generates a 2048-bit RSA key pair. The public key hash is burned into the
   device's eFUSEs.
2. During bitstream generation, the bitstream is signed with the RSA private key. The signature
   and public key are prepended to the bitstream file (stored in flash alongside it).
3. At configuration time, the FPGA reads the public key from the bitstream, computes its hash,
   and compares against the eFUSE-stored hash. If they match, it verifies the RSA signature
   over the bitstream digest. Only if both checks pass is the bitstream loaded.

**Combined use (encrypt + authenticate):**

Most high-security deployments use both:
- **Authenticate first** — reject counterfeit or tampered bitstreams before decryption begins.
- **Encrypt second** — keep the plaintext bitstream confidential.

The boot header format for UltraScale+ supports an ordered chain:
`RSA signature → SHA-3 hash → AES-256 encrypted payload`.

**Key distinction from encryption alone:**

Without authentication, an attacker who has physically modified the flash can replace the
encrypted bitstream with an arbitrary payload (even a blank configuration). With authentication,
the device will refuse to load any bitstream that was not signed with the trusted private key.

---

### Question 6

**Describe the three most common SPI flash configuration scenarios for production FPGA designs:
single-chip, dual-chip (redundant), and multi-image (MultiBoot). When would you choose each?**

**Answer:**

**Single-chip (standard boot):**

One SPI flash device stores one bitstream at address 0x000000 (or a configurable golden address).
FPGA reads from address 0 on power-on.

```
SPI Flash Layout:
0x000000: Bitstream (design.bit / design.bin)
```

Use when: simple designs, no field update requirement, no fallback needed. Low cost and minimal
complexity.

**Dual-chip (hardware redundancy):**

Two independent SPI flash chips, each containing the same bitstream. A hardware mux or the
FPGA itself selects which flash to read from. One flash is the primary, the other is the backup.

```
Primary SPI Flash     Fallback SPI Flash
├── Bitstream v2.1    ├── Bitstream v1.0 (known good)
                      └── (never updated in field)
```

Use when: safety-critical applications (aerospace, industrial control) where a corrupted primary
flash must not prevent operation. The fallback flash is write-protected permanently.

**Multi-image / MultiBoot:**

One SPI flash contains multiple bitstreams at defined offsets. The FPGA bootloader (hardware
state machine) can be directed to load from a fallback address if the primary fails.

```
SPI Flash Layout (MultiBoot example):
0x000000: Golden bitstream (v1.0, write-protected)
0x400000: Application bitstream (v2.1, field-updatable)
0x800000: (Optional second application slot)
```

The device starts at the golden image address. If the application bitstream fails (CRC error,
`DONE` not asserted within timeout), the MultiBoot logic automatically falls back to the golden
image address.

In Vivado, the fallback address is embedded in the bitstream using:

```tcl
set_property BITSTREAM.CONFIG.NEXT_CONFIG_ADDR 0x400000 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK Enable [current_design]
```

Use when: field-updatable designs where a failed update must not brick the device. The golden
image is permanently protected; only the application slot is updated over-the-air or via a
service interface.

**Summary:**

| Scenario        | Fault tolerance             | Cost     | Update capability         |
|-----------------|----------------------------|----------|---------------------------|
| Single-chip     | None                       | Lowest   | Manual lab reprogram only |
| Dual-chip       | Hardware redundancy        | Higher   | Primary updateable        |
| MultiBoot       | Software/hardware fallback | Medium   | Application slot updateable |

---

## Advanced

### Question 7

**Describe partial reconfiguration (PR) in detail: what it achieves, how the design is
partitioned, and the key constraints that must be respected.**

**Answer:**

Partial reconfiguration allows a portion of the FPGA's configuration memory to be updated while
the rest of the device continues operating. The device is divided into:

- **Static region:** logic that runs continuously; never reconfigured.
- **Reconfigurable partition (RP):** one or more defined regions that can be swapped out at
  runtime by loading a partial bitstream (`.bit` suffix, but only covers the RP).

**Design flow:**

```
1. Define Reconfigurable Partitions in Vivado (Pblock assignments, PR-specific attributes)
2. Synthesise static region + all reconfigurable modules (RMs) separately
3. Implement: place-and-route static region first (locked floorplan)
4. Implement each RM within its Pblock boundary with static region locked
5. Generate full bitstream (static + RM_0) and partial bitstreams (RM_1, RM_2, ...)
6. At runtime: load partial bitstream via ICAP (Internal Configuration Access Port) 
   or PCAP (on Zynq PS) while static region continues running
```

**Key constraints:**

1. **Pblock boundaries must be respected.** The RP must be contained within a rectangular
   Pblock. Resources outside the Pblock are static. Signals crossing the Pblock boundary use
   `Partition Pins` — registered interfaces automatically inserted by Vivado.

2. **Partition pins are registers, not wires.** All signals crossing the static/RP boundary are
   registered at the boundary. This adds one clock cycle of latency and means direct
   combinational paths across the boundary are not supported.

3. **Clocks must come from the static region.** Clock resources (MMCM, BUFG) cannot be inside
   the RP. The RP receives clocks from the static region via clock routing that is fixed.

4. **Blanking (reset) before reconfiguration.** The RP must be driven to a safe state (all
   outputs gated or a known safe value) before the partial bitstream is loaded. The Vivado PR
   design guidelines provide a `reconfig_module` wrapper pattern for this.

5. **ICAP access must be exclusive.** Only one source should access the ICAP at a time. On
   Zynq, arbitration between the PS PCAP and PL ICAP is managed via the `DEVCFG` register.

**ICAP instantiation example (for PL-driven PR):**

```vhdl
-- Instantiate ICAPE2 to load partial bitstreams from BRAM or AXI stream
ICAPE2_inst : ICAPE2
    generic map (
        ICAP_WIDTH => "X32",
        SIM_CFG_FILE_NAME => "NONE"
    )
    port map (
        CLK   => icap_clk,
        CSIB  => icap_csn,    -- active low chip select
        RDWRB => icap_rdwrn,  -- 0=write (program), 1=read (readback)
        I     => icap_data,   -- 32-bit data in (bit-reversed per Xilinx spec!)
        O     => icap_dout
    );
```

**Important gotcha:** ICAPE2 data must be byte-swapped and bit-reversed relative to the bitstream
file byte order. Xilinx documentation (UG470) specifies the exact transformation. Failing to
apply this transformation results in CRC errors during partial reconfiguration.

---

### Question 8

**You are implementing a secure firmware update system for a deployed FPGA board. The system
must: (1) update the application bitstream over an untrusted network link, (2) survive a
power loss during update without bricking, (3) authenticate the new image before applying it,
and (4) roll back automatically if the new image fails to configure. Describe your complete
architecture.**

**Answer:**

This is a multi-layer design problem combining MultiBoot, authentication, and fail-safe update
sequencing.

**Flash layout:**

```
SPI Flash (128 Mbit):
┌─────────────────────────────────────────────────────┐
│ 0x00000000  Golden bitstream (WP=1, hardware locked) │  ← Factory image, never overwritten
│ 0x01000000  Application slot A (current active)      │  ← Normally booted
│ 0x02000000  Application slot B (update staging)      │  ← New image written here first
│ 0x03000000  Metadata block                           │  ← Slot status, version, commit flag
└─────────────────────────────────────────────────────┘
```

**Update sequence (A/B scheme):**

```
Phase 1: Receive update
  - Download new encrypted+authenticated bitstream over the network
  - Write new bitstream to slot B only (slot A continues running)
  - If download fails mid-way, slot B is marked "incomplete" in metadata
  - Power loss here: safe — slot A still valid, system reboots to slot A

Phase 2: Authenticate
  - Compute SHA-256 of received slot B bitstream
  - Verify RSA signature (public key stored in static logic / eFUSE)
  - If signature fails: mark slot B "invalid", abort, stay on slot A
  - Power loss here: safe — authentication result is not committed until Phase 3

Phase 3: Commit
  - Write "slot B staged, pending verification" to metadata block (atomic write)
  - Set MultiBoot next-config address to slot B
  - Initiate reboot (IPROG command via ICAP or PROG_B assertion)

Phase 4: Verify boot
  - FPGA attempts to configure from slot B
  - If CRC error: FPGA's MultiBoot hardware falls back to golden image automatically
  - If success: application in slot B runs a watchdog health check
  - If health check passes within N seconds: application writes "slot B verified, commit A←B" 
    to metadata, and updates slot A next cycle
  - If health check fails or watchdog fires: application explicitly jumps back to golden image
    via ICAP IPROG command
```

**Authentication mechanism:**

The FPGA's static region (loaded from the golden image) contains:
- An RSA-2048 public key (or a hash of it, cross-referenced against eFUSE).
- A SHA-256 engine (can reuse a standard IP core).
- A small state machine that runs the verify-then-boot sequence.

The authentication runs before any partial reconfiguration or MultiBoot jump.

**Power-loss safety analysis:**

| Power-loss point              | State on recovery                              |
|-------------------------------|------------------------------------------------|
| During download to slot B     | Slot B incomplete flag → boot from slot A      |
| During authentication         | Authentication result discarded → boot slot A  |
| During metadata commit        | Atomic write either committed or not; slot A still valid |
| During boot to slot B         | MultiBoot fallback → golden image              |
| During health check           | Watchdog fires → explicit IPROG to golden      |

**The golden image must be absolutely minimal** — just enough logic to run the update engine
and communicate over the network. It should never be in the field-update path; it is the
last-resort fallback.
