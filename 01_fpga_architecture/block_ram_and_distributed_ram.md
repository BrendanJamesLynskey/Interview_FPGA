# Block RAM and Distributed RAM

## Overview

FPGAs provide two fundamentally different mechanisms for implementing on-chip memory: Block RAM (BRAM), which is a dedicated hardened memory macro, and distributed RAM, which repurposes LUT cells in SLICEM slices as SRAM storage. Understanding when to use each, how they behave under different access patterns, and how their architectural constraints affect design decisions is a core competency for FPGA designers.

This document uses Xilinx UltraScale/UltraScale+ as the primary reference (36Kb BRAM, URAM). Intel equivalents (M20K, MLAB) are noted where differences are significant.

---

## Tier 1: Fundamentals

### Q1. What is Block RAM? Describe its basic organisation in UltraScale devices.

**Answer:**

Block RAM (BRAM) is a hard macro — a physically dedicated piece of synchronous SRAM embedded in the FPGA fabric, not constructed from LUT cells. In UltraScale/UltraScale+, each BRAM primitive stores 36 kilobits (36Kb = 4,096 bytes with parity, or 32,768 bits of data). BRAMs are arranged in columns distributed across the device fabric, interleaved with CLB and DSP columns.

**Physical organisation:**

Each 36Kb BRAM can be configured as:
- One 36Kb BRAM
- Two independent 18Kb BRAMs (top half and bottom half)

The 36Kb BRAM has two fully independent ports, each with:
- Its own address bus
- Its own read-data and write-data buses
- Its own clock input
- Its own write-enable and chip-enable signals

**Width × depth configurations (36Kb, one port):**

| Depth | Width (data) | Width (with parity) |
|---|---|---|
| 32K × 1 | 1 bit | — |
| 16K × 2 | 2 bits | — |
| 8K × 4 | 4 bits | — |
| 4K × 8 | 8 bits | 9 bits |
| 2K × 16 | 16 bits | 18 bits |
| 1K × 32 | 32 bits | 36 bits |
| 512 × 64 | 64 bits | 72 bits |

**Key operational characteristic:** BRAMs are always synchronous. A read or write takes one clock cycle. There is no combinational (asynchronous) read mode (unlike distributed RAM). This means any logic reading a BRAM value must account for the one-cycle read latency in its pipeline.

**Intel/Altera equivalent:** Intel UltraScale-equivalent devices use M20K BRAMs (20Kb each) with similar two-port organisation. Agilex adds a larger HBM-adjacent memory tier.

---

### Q2. What is the difference between True Dual-Port (TDP) and Simple Dual-Port (SDP) BRAM configurations? When would you choose each?

**Answer:**

**True Dual-Port (TDP):**

Both ports (Port A and Port B) can independently perform reads and writes. Each port has its own clock, address, data, and control signals. The two ports can have different widths. This allows simultaneous access from two independent clock domains with no coordination logic.

```
Port A: CLKA, ADDRA[14:0], DINA[15:0], WEA, ENA
Port B: CLKB, ADDRB[14:0], DINB[15:0], WEB, ENB
```

**Use TDP when:**
- The memory must be accessed from two independent clock domains (e.g., write from a 125 MHz Ethernet MAC, read from a 250 MHz DSP datapath)
- Two independent control blocks need simultaneous read or write access
- Implementing a simple two-port register file

**Simple Dual-Port (SDP):**

Port A is dedicated to writing (write-only) and Port B is dedicated to reading (read-only). This restriction allows the full 36Kb to be accessed as a single wide data path: Port B can deliver 64-bit data at a time (vs. 32-bit max in TDP mode). SDP effectively treats the BRAM as 512 × 64 bits rather than two independent 1K × 32 ports.

```
Port A (write): CLKA, ADDRA[8:0], DINA[63:0], WEA[7:0], ENA
Port B (read):  CLKB, ADDRB[8:0], DOUTB[63:0], ENB
```

**Use SDP when:**
- The design needs maximum memory width (64 or 72 bits)
- One clock domain writes, one reads (e.g., a pixel line buffer in an image processing pipeline)
- Implementing a standard FIFO where one pointer writes, one reads

**Collision behaviour:** When both ports access the same address simultaneously (a write collision), the BRAM behaviour depends on the `READ_FIRST`/`WRITE_FIRST`/`NO_CHANGE` mode setting. This is a common source of subtle bugs and is discussed in the Advanced section.

---

### Q3. What is distributed RAM? How is it implemented in FPGA fabric, and what are its key characteristics?

**Answer:**

Distributed RAM uses the SRAM cells that normally store LUT truth tables as general-purpose addressable memory. In SLICEM Slices, each LUT6 can be repurposed as a 64-deep × 1-bit synchronous-write, asynchronous-read RAM cell.

**Primitive forms available in UltraScale SLICEM:**

| Primitive | Depth | Width | Ports |
|---|---|---|---|
| RAM32X1S | 32 × 1 | 1b | Single-port |
| RAM64X1S | 64 × 1 | 1b | Single-port |
| RAM128X1S | 128 × 1 | 1b | 2 LUTs, single-port |
| RAM256X1S | 256 × 1 | 1b | 4 LUTs, single-port |
| RAM32X1D | 32 × 1 | 1b | Dual-port |
| RAM64X1D | 64 × 1 | 1b | Dual-port |
| RAM32M | 32 × 8 | 8b | Dual-port |
| RAM64M | 64 × 4 | 4b | Dual-port |
| RAM64M8 | 64 × 8 | 8b | Dual-port |

Multiple primitive cells can be combined (with additional LUT logic for address decoding) to build wider or deeper memories.

**Key characteristics of distributed RAM:**

1. **Asynchronous read:** The read data output responds combinationally to address changes — there is no read clock. This is the critical difference from BRAM.

2. **Synchronous write:** Writes are clocked. The memory updates on the rising edge of the write clock.

3. **No dedicated read-enable:** The output changes whenever the address changes, whether or not the data is needed.

4. **LUT cells consumed:** Each RAM32X1S uses one SLICEM LUT6. A 32-bit-wide, 64-deep memory requires 32 LUT cells (RAM64X1S × 32).

5. **Placement constraints:** Must be placed in SLICEM Slices. This constrains placement flexibility in regions with limited SLICEM availability.

**Synthesis inference:** In Verilog/VHDL, an array with synchronous write and asynchronous read is automatically inferred as distributed RAM by synthesis. A combinational read-through pattern in an `always` block (or concurrent signal assignment) signals to the tool that asynchronous read is intended.

---

### Q4. What is URAM (UltraRAM)? How does it differ from BRAM, and what problems does it solve?

**Answer:**

UltraRAM (URAM) is a third dedicated memory type introduced in UltraScale+ devices. Each URAM stores 288 Kb — 8× larger than a 36Kb BRAM — using a more efficient hardened SRAM compiler within a physically larger macro.

**URAM specifications:**

| Parameter | Value |
|---|---|
| Depth | 4K addresses |
| Width | 72 bits (64 data + 8 parity) |
| Read latency | 2 clock cycles (pipeline stages) |
| Write latency | 1 clock cycle |
| Number of ports | 2 (A and B), independent clocks |
| Cascade support | Yes — URAMs stack vertically |
| ECC support | No (BRAMs have optional ECC) |

**URAM vs BRAM comparison:**

| Feature | BRAM 36Kb | URAM 288Kb |
|---|---|---|
| Size | 36 Kb | 288 Kb |
| Aspect ratio flexibility | Many configurations | Fixed 4K × 72 only |
| Read latency | 1 cycle | 2 cycles |
| Power per bit | Higher | Lower |
| Cascade | Manual only | Dedicated hardware cascade |
| ECC | Yes | No |
| Available in | All UltraScale | UltraScale+ only |

**Problems URAM solves:**

1. **Large dense memories:** Implementing 1 MB of on-chip storage would require $\frac{1 \text{ MB}}{4 \text{ KB}} = 256$ BRAMs, consuming a significant fraction of device BRAM resources. The same storage uses only 32 URAMs.

2. **High-bandwidth accumulation:** URAMs support a read-modify-write (cascade pipeline) mode where the output of one read is piped directly to write-back logic within two cycles, enabling high-bandwidth accumulators.

3. **Cascade for deep memories:** URAMs have a dedicated cascade interface. Stacking multiple URAMs in cascade builds a deeper memory without additional address decoder logic or routing.

**When NOT to use URAM:**

- When read latency of 2 cycles is incompatible with the pipeline structure (BRAMs are preferable)
- When ECC is required
- When shallow, wide, or irregularly-shaped memories are needed (BRAM's configurability wins)
- On non-UltraScale+ devices (URAMs are not available)

---

## Tier 2: Intermediate

### Q5. Explain BRAM read modes: READ_FIRST, WRITE_FIRST, and NO_CHANGE. What happens when a simultaneous read-write to the same address occurs in each mode?

**Answer:**

The BRAM read mode determines what the read-data output presents during the clock cycle in which a write occurs to the same address — a write-then-read or read-then-write collision.

**READ_FIRST:**

The data that was stored at the address *before* the write cycle is presented on the read-data output. The write still completes and the new data is in memory afterward.

```
Cycle N:   Write addr=5, data=0xAB  |  simultaneously read addr=5
DOUT:      → 0x00 (old value before write)
Memory after cycle N, addr=5: 0xAB
```

**Use case:** When implementing a FIFO with read and write pointers that may momentarily coincide at start-up (empty condition). READ_FIRST prevents spurious data from appearing at the output.

**WRITE_FIRST (also called "transparent" mode):**

The newly written data is immediately forwarded to the read-data output in the same clock cycle as the write — the output "looks through" the write.

```
Cycle N:   Write addr=5, data=0xAB  |  simultaneously read addr=5
DOUT:      → 0xAB (new value just written)
Memory after cycle N, addr=5: 0xAB
```

**Use case:** When a write-and-readback-immediately pattern is needed, such as register files where the same cycle can write and read the same register (forwarding without an extra cycle penalty).

**NO_CHANGE:**

The read-data output does not change during a write cycle. It retains whatever value was last read. This prevents unnecessary switching on the DOUT bus (power reduction) and avoids the address decoder driving both read and write simultaneously.

```
Cycle N-1: Read addr=3, DOUT → 0x55
Cycle N:   Write addr=5, data=0xAB  (read disabled or same address)
DOUT:      → 0x55 (held, no change)
```

**Use case:** Power-sensitive designs, or any use where simultaneous read-write to the same address never occurs by design (e.g., FIFO where empty/full flags prevent collision).

**Collision hazard in TDP mode:** In True Dual-Port mode when Port A writes and Port B reads (or vice versa) to the same address in the same cycle, the read mode determines the outcome. This is a non-trivial source of bugs in dual-clock BRAMs — the collision behaviour is defined per port. Xilinx strongly recommends avoiding same-address simultaneous access in TDP mode when the two ports use different clocks, as the outcome is implementation-specific at the boundary of metastability.

---

### Q6. You need a 2K × 16-bit synchronous-read memory. Describe the implementation options using BRAM vs distributed RAM, and make a recommendation based on typical design constraints.

**Answer:**

**Memory requirements:**

- Depth: 2,048 addresses
- Width: 16 bits
- Total: 32,768 bits = 32 Kb

**Option A — Single 36Kb BRAM:**

A 36Kb BRAM configured as 2K × 18 (using 18 data bits with 2 parity bits unused, or exactly 2K × 16 using the data bits only) covers the requirement in one primitive.

| Attribute | Value |
|---|---|
| BRAM primitives used | 1 |
| LUT cells used | 0 |
| Read latency | 1 cycle (synchronous) |
| Power | ~6 mW dynamic per BRAM |
| Placement | Fixed to BRAM column |

**Option B — Distributed RAM:**

2,048 × 16 bits using RAM64X1S primitives:
- Each RAM64X1S is 64 deep × 1 bit wide = 64 bits
- Width 16 bits requires 16 cells per address group
- Depth 2,048: $\frac{2048}{64} = 32$ address groups
- Total LUT cells: $32 \times 16 = 512$ RAM64X1S cells = **512 SLICEM LUTs**

But distributed RAM has asynchronous read. For synchronous-read behaviour, an output register must be added: 16 FFs for the output stage.

| Attribute | Value |
|---|---|
| LUT cells used (SLICEM) | 512 |
| FF cells used | 16 (optional output register) |
| BRAM primitives used | 0 |
| Read latency | 0 cycles async, 1 cycle with output FF |
| Routing congestion | Moderate (512 cells in one region) |

**Option C — URAM (UltraScale+ only):**

URAM is 4K × 72. The 2K × 16 requirement would waste 50% of the depth and 77% of the width — poor efficiency. Avoid.

**Recommendation:**

Use a **single BRAM** unless:

1. BRAMs are already nearly exhausted in the design and LUTs have headroom — then distribute to LUT RAM
2. The memory must be read combinationally (async read) — BRAM cannot do this; use distributed RAM
3. The memory is very small (e.g., ≤ 64 × 16 = 1 Kb) — overhead of a full BRAM is wasteful; use distributed RAM

In this case (2K × 16, no async read requirement), a **single BRAM** is the correct choice: it consumes no LUTs, has predictable timing (one clock cycle read latency), and has lower routing congestion than 512 scattered SLICEM LUTs.

**Practical note:** On a high-utilisation design (>70% LUTs), each BRAM saved translates to an opportunity to reduce LUT pressure by using distributed RAM for small lookup tables. The architectural trade-off is therefore context-dependent.

---

### Q7. Explain BRAM cascade. How do you build a 4K × 16-bit memory from 36Kb BRAMs, and what timing considerations apply?

**Answer:**

A single 36Kb BRAM cannot implement 4K × 16 bits directly: its maximum depth in 16-bit wide configuration is 2K (2K × 18 with parity). To build 4K × 16, two BRAMs must be cascaded in depth.

**Cascade implementation:**

```
Address bus [11:0] (12 bits for 4K depth)

Address[11]:  MSB selects BRAM A (addr=0) or BRAM B (addr=1)
Address[10:0]: Lower 11 bits drive both BRAMs simultaneously

BRAM_A: depth=2K, width=16 — handles addresses 0x000–0x7FF
BRAM_B: depth=2K, width=16 — handles addresses 0x800–0xFFF

Enable control:
  BRAM_A enable = ~Address[11]
  BRAM_B enable =  Address[11]

Output mux (registered):
  DOUT = Address[11]_reg ? BRAM_B_DOUT : BRAM_A_DOUT
```

The address MSB must be registered synchronously with the BRAM read cycle to correctly select the output MUX one cycle after the read.

**Timing consideration — output MUX delay:**

After the BRAM read completes (1 clock cycle), the output MUX selects between BRAM_A and BRAM_B output. This MUX uses one LUT level, adding approximately 0.1–0.2 ns to the BRAM read-to-output-valid timing. In a tight pipeline this extra delay can matter.

**Better alternative — using BRAM built-in enable for cascade:**

Rather than using an external MUX, tie the BRAM enable signals to the address MSB directly. Only one BRAM is enabled per read, so only one DOUT will be valid. Wire the two DOUT buses through an OR gate (safe because the disabled BRAM outputs 0 when not enabled in NO_CHANGE mode, or use a MUX). Tools recognise this pattern and may use the `REGCEA`/`REGCEB` output register enable to minimise the MUX cost.

**URAM cascade alternative:**

For larger memories (e.g., 32K × 72), URAMs have a dedicated hardware cascade port (CASIN/CASOUT). Up to 8 URAMs can be cascaded in a column without any external logic or routing, providing 32K × 72 with a cascade latency of only 1 extra clock cycle. This is significantly more efficient than manually cascading BRAMs with external MUXes.

---

### Q8. What is "BRAM output register" and why should you almost always enable it?

**Answer:**

Each BRAM port has an optional output pipeline register — a row of FFs placed between the BRAM's internal read-data latch and the DOUT pins. It adds exactly one cycle of read latency (total latency becomes 2 cycles instead of 1) but has two significant benefits.

**Benefit 1 — Timing improvement:**

Without the output register, DOUT is driven directly from the BRAM's internal SRAM sense amplifier through the BRAM output pins to the routing fabric and the next register's D input. This path includes the BRAM sense-amplifier settling time plus the BRAM output pin capacitance. Adding the output register places a register physically inside the BRAM macro, at the boundary of the hardened cell. The route from BRAM output register Q to the next logic stage is now a standard register-to-register path, typically 20–30% faster than the unregistered BRAM output path.

**Benefit 2 — BRAM collision safety:**

In READ_FIRST mode, the output register holds the read data stable until the next read, preventing glitches on DOUT during write cycles (since the unregistered output can momentarily show undefined values during write-phase internal transitions).

**XDC constraint and Vivado setting:**

```vhdl
-- In VHDL instantiation
DOA_REG => 1,  -- Enable output register on Port A
DOB_REG => 1,  -- Enable output register on Port B
```

Or via the Vivado IP core GUI under "Port A Options → Output Register → Core Registers."

**When to disable the output register:**

Only when the extra 1-cycle latency is architecturally incompatible with the design — for example, in a content-addressable memory (CAM) or a cache lookup where read and response must be combinationally coupled to a downstream decision within one cycle. In such cases, accept the timing penalty or restructure the pipeline.

**Rule of thumb:** Enable the BRAM output register by default. Add a pipeline register stage in the consuming logic to absorb the extra latency. The timing improvement justifies the change in nearly all cases.

---

## Tier 3: Advanced

### Q9. You have a design requiring a 512-entry register file with 4 read ports and 2 write ports, operating at 300 MHz on UltraScale+. Describe an implementation strategy using available FPGA memory primitives.

**Answer:**

A 512 × 32-bit register file with 4 read ports and 2 write ports is architecturally challenging. No single BRAM or SRAM primitive natively provides 4 read ports. There are three approaches:

**Approach 1 — BRAM replication:**

Replicate the register file $R$ times, where $R$ = number of read ports. Each replicated copy is kept identical (all writes go to all copies).

- 4 read ports = 4 copies of the register file
- Each copy: 512 × 32 bits = 16 Kb → one 18Kb BRAM (or half a 36Kb BRAM)
- Each copy uses one BRAM port for reading (Port B = dedicated read port)
- All 4 copies share write data: Port A of each BRAM receives the same write address, write data, and write-enable
- 2 write ports: two write buses, each fanned out to all 4 BRAMs; arbitration logic ensures the two write ports never conflict at the same address in the same cycle (or define a priority)

**Resource cost:**
- BRAMs: 4 (one per read port)
- LUTs: ~50 for write arbitration and address decoding

**Approach 2 — Distributed RAM with multi-port primitives:**

RAM64M8 in SLICEM provides a 64-deep × 8-bit dual-port RAM per LUT. For 512 × 32-bit with 4 read ports, a combination of multi-port SRAMs with banking is needed. This is complex and LUT-intensive at 512 depth — distributed RAM becomes unwieldy above ~128 entries.

Not recommended at 512 depth due to LUT cost: approximately 512 LUTs per read port copy.

**Approach 3 — Banked URAM with read-port time-multiplexing:**

If 300 MHz allows 4 time-multiplexed reads within one clock cycle (it does not — only one read per cycle per URAM port), this approach fails. URAMs provide only 2 independent ports. Not suitable for 4 read ports without replication.

**Recommended solution: BRAM replication (Approach 1):**

For 300 MHz timing, the BRAM output register must be enabled (2-cycle read latency). The write path requires the write to reach all 4 BRAM copies in the same cycle. With 2 write ports:

```
Write Port 1 arbiter:
  Port A of BRAM_0, BRAM_1, BRAM_2, BRAM_3 all receive:
    ADDRA = write1_addr, DINA = write1_data, WEA = write1_en

Write Port 2 arbiter:
  Port B of BRAM_0, BRAM_1, BRAM_2, BRAM_3 all receive:
    ADDRB = write2_addr, DINB = write2_data, WEB = write2_en
    (using TDP mode for simultaneous dual-port write)
```

Wait — TDP BRAM allows Port B to write as well. Using TDP with both ports as write, and the read multiplexed via a separate registered read path, is feasible if reads are staggered.

**Practical implementation at 300 MHz:**

Use **4 × 36Kb BRAMs in SDP mode** (Port A = write, Port B = read). Drive all write ports in parallel to all 4 BRAMs. Read ports are independent via the 4 Port B interfaces. This requires 2 additional BRAMs for the second write port — use Port A for write port 1 and a separate BRAM bank with Port A for write port 2. Total: **8 BRAMs** for full independence.

At 300 MHz, all BRAM timing is met with output registers enabled. The constraint is routing the write data to all 8 BRAMs simultaneously — use a proper fanout tree with Pblock constraints to keep routing short.

---

### Q10. Explain the concept of "memory packing efficiency" for BRAMs. A design requires fourteen 128 × 8-bit memories. How many 36Kb BRAMs does this consume, and can you improve efficiency?

**Answer:**

**Base calculation:**

Each memory: 128 × 8 = 1,024 bits.
Total storage required: 14 × 1,024 = 14,336 bits.

A 36Kb BRAM in its smallest useful configuration (18Kb mode as 2K × 9) wastes enormous capacity for a 128 × 8-bit memory.

If each 128 × 8 memory is mapped to one BRAM:
- The minimum BRAM configuration that holds 128 × 8 is 128 × 9 (using the 9-bit width with parity disabled)
- Each uses a half-BRAM (18Kb)
- 14 half-BRAMs = 7 full 36Kb BRAMs

**Packing efficiency:**

Each half-BRAM stores $128 \times 8 = 1,024$ bits.
Each 18Kb half-BRAM capacity: 16,384 bits.
Packing efficiency per BRAM: $\frac{1,024}{16,384} = 6.25\%$.

This is very poor: 93.75% of each BRAM is wasted.

**Improved approach — multiplexed memory:**

Pack multiple logical memories into one BRAM by using a wider address space and a few additional address bits as a "memory select."

14 memories × 128 entries = 1,792 total entries. Rounding up to a power of two: 2,048 entries. A 2K × 8-bit BRAM fits exactly in one 36Kb BRAM (2K × 9 mode).

Logical addressing:
- Address[10:7] = 4-bit memory select (selects which of 14 memories, 0–13)
- Address[6:0] = 7-bit index within the selected memory (0–127)

Total address bits: 11 bits for 2K depth.

**Resource after packing:**

- BRAM primitives: **1** (vs 7 before)
- Overhead: 1 LUT for address decode, 4-bit comparator/decoder for select logic

**Packing efficiency after:** $\frac{14 \times 1024}{18 \times 1024} = 77.8\%$. (Using one 18Kb half of a 36Kb BRAM, with 2K × 8 = 16K bits needed out of 16K available — near-perfect.)

**Trade-off of packing:**

- The 14 memories can no longer be read simultaneously from independent addresses in the same clock cycle. All reads and writes share the one BRAM port. If the design requires parallel access, packing is not viable.
- If accesses are naturally time-multiplexed (e.g., a round-robin arbiter services each memory in sequential cycles), packing is transparent to the design.

**Alternative — distributed RAM:**

For 14 × 128 × 8-bit memories, distributed RAM is also viable:

Each RAM128X1S needs 2 LUT6 cells (128 deep × 1 bit = 2 × 64 cells).
Width 8 bits: 8 × 2 = 16 LUTs per memory.
14 memories: 14 × 16 = **224 SLICEM LUTs**.

With 224 LUTs, distributed RAM is competitive here — especially if the device has spare LUTs and scarce BRAMs. The asynchronous read property of distributed RAM is a bonus if combinational reads are needed.

**Decision rule:**

$$\text{Use BRAM if:} \quad \frac{\text{Total bits required}}{\text{BRAM capacity per primitive}} > 25\%$$

Below 25% utilisation per BRAM, strongly consider distributed RAM or memory packing.

---

## Quick Reference: Key Terms

| Term | Definition |
|---|---|
| BRAM | Block RAM — dedicated hardened 36Kb SRAM macro in FPGA fabric |
| 18Kb BRAM | Half of a 36Kb BRAM; operates independently or as part of a 36Kb cell |
| TDP | True Dual-Port — both BRAM ports can independently read and write |
| SDP | Simple Dual-Port — Port A writes only, Port B reads only; enables max width |
| URAM | UltraRAM — 288Kb dedicated memory in UltraScale+ only; 4K × 72 bits |
| Distributed RAM | SLICEM LUT cells repurposed as SRAM with asynchronous read |
| SRL32 | Shift Register LUT — LUT configured as a 32-deep serial delay line |
| READ_FIRST | BRAM read mode: old value visible on DOUT during same-address write |
| WRITE_FIRST | BRAM read mode: new write data forwarded to DOUT immediately (transparent) |
| NO_CHANGE | BRAM read mode: DOUT held during writes (lowest power) |
| Output register | Optional FF inside BRAM macro; adds 1 cycle latency, improves timing |
| BRAM cascade | Chaining BRAMs in depth using address MSB selection and output MUX |
| Memory packing | Mapping multiple logical memories into one BRAM using wider addressing |
| Packing efficiency | Fraction of BRAM capacity actually used by the design |
