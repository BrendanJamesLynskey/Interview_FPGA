# Problem 02: BRAM vs Distributed RAM

## Problem Statement

You are reviewing the architecture of an FPGA-based packet processing engine targeting a Xilinx UltraScale+ XCKU5P device. The device has the following memory resources:

- **BRAM 36Kb:** 312 total (624 as 18Kb halves)
- **LUT6 (SLICEM, distributed RAM capable):** approximately 30% of 217,800 = ~65,000 SLICEM LUTs

The design has five memory requirements:

| Memory | Depth | Width | Read type | Access pattern | Notes |
|---|---|---|---|---|---|
| A: Packet header cache | 64 entries | 128 bits | Synchronous | One read + one write per clock | Updated on every packet arrival |
| B: Flow table | 8,192 entries | 64 bits | Synchronous | Random reads, occasional writes | Lookup table for millions of flows |
| C: Checksum LUT | 256 entries | 8 bits | Asynchronous | Read-only at runtime, combinational decode | CRC precomputed lookup |
| D: Statistics counters | 32 counters | 32 bits | Synchronous | Read-modify-write every cycle | High-frequency per-counter updates |
| E: Packet reorder buffer | 1,024 entries | 256 bits | Synchronous | Burst write, burst read | Packets stored while awaiting reordering |

For each memory, determine the best implementation (BRAM or distributed RAM), justify your choice, estimate the resource cost, and identify any constraints that affect the decision.

---

## Worked Solution

### Framework for the Decision

Before analysing each memory, establish the decision criteria:

**Choose BRAM when:**
- Total size > 2–4 Kb (BRAM is area-efficient above this threshold)
- Synchronous read is acceptable
- Two independent ports needed at different clock domains
- Density priority outweighs flexibility

**Choose distributed RAM when:**
- Asynchronous (combinational) read is required
- Total size ≤ ~2 Kb (below this, BRAM wastes capacity)
- The memory is co-located with logic that drives it (packing efficiency)
- BRAM resources are scarce and LUTs are available

**Choose registers (FF array) when:**
- Read-modify-write in one cycle with no latency is required
- Depth is very small (≤ 16–32 entries)

---

### Memory A: Packet Header Cache (64 × 128 bits)

**Size:** 64 × 128 = 8,192 bits = 8 Kb.

**Access pattern:** One read and one write per clock — True Dual-Port.

**Analysis:**

8 Kb fits in one 18Kb half-BRAM (as 64 × 128 using two 18Kb BRAMs in parallel for the 128-bit width, or one 36Kb BRAM in 512 × 64 mode with address extension).

For 128-bit width: a single 36Kb BRAM supports a maximum of 64 bits wide (512 × 64 SDP mode). For 128-bit width, two 36Kb BRAMs in parallel are needed, each providing 64 bits.

**BRAM option:**
- 2 × 36Kb BRAMs (one per 64-bit half)
- SDP mode: Port A writes 128 bits, Port B reads 128 bits
- Read latency: 1 cycle (with output register disabled) or 2 cycles (output register enabled)

**Distributed RAM option:**
64 × 128 bits = 8,192 bits. Using RAM64M8 (64 × 8b, 1 LUT cell each): $\frac{128}{8} = 16$ RAM64M8 cells per 64-deep bank. Each RAM64M8 supports dual-port (read + write simultaneously). Total: **16 SLICEM LUTs**.

**Recommendation: Distributed RAM.**

Rationale:
1. 8 Kb is small — two 36Kb BRAMs waste 82% of capacity.
2. The access pattern (read + write each cycle to the same or different addresses) maps well to the RAM64M8 dual-port mode.
3. 16 SLICEM LUTs is negligible on a device with 65,000 available SLICEM LUTs.
4. Distributed RAM allows asynchronous read if needed, providing flexibility.
5. Saving 2 BRAMs preserves them for Memory B and E which need them more.

**Resource cost:** 16 SLICEM LUT6 cells.

---

### Memory B: Flow Table (8,192 × 64 bits)

**Size:** 8,192 × 64 = 524,288 bits = 512 Kb.

**Access pattern:** Random read, occasional write. Synchronous read acceptable.

**Analysis:**

512 Kb is clearly too large for distributed RAM: it would require $\frac{524,288}{64} = 8,192$ RAM64X1S cells = 8,192 SLICEM LUTs. That is 12.6% of all SLICEM LUTs — a significant fraction just for one table. Additionally, 8,192 scattered SLICEM LUTs would create severe routing congestion.

**BRAM option:**
Each 36Kb BRAM in 512 × 64 SDP mode provides 512 entries × 64 bits.
Required: $\frac{8,192}{512} = 16$ BRAM cascaded in depth.

But with 64-bit width, 16 BRAMs cascaded in depth using address MSBs for depth selection:
- 16 BRAMs, address[13:9] selects which BRAM (0–15), address[8:0] selects within it
- Only one BRAM is enabled per read cycle
- Output MUX: 16:1 for 64-bit output — can use BUFGCE + MUX combination, or rely on SDP enable logic with shared output bus

More cleanly: use 16 × 36Kb BRAMs in SDP mode with the `ENA`/`ENB` enable signals to select the active BRAM. Route address[13:9] to a 4:16 decoder driving the enable signals. The 16 DOUTB buses are OR-combined (safe when only one BRAM is enabled at a time — disabled BRAMs output 0 in NO_CHANGE mode).

**URAM option (available on UltraScale+):**

Each URAM is 4K × 72 bits. 8,192 entries ÷ 4,096 = 2 URAMs cascaded in depth using the built-in URAM cascade port. Width: 64 bits ≤ 72 bits — fits in one URAM width. Only **2 URAMs** needed.

URAM read latency: 2 cycles. Must account for in the pipeline.

**Recommendation: URAM (2 URAMs) if available; 16 BRAMs otherwise.**

The XCKU5P is a UltraScale+ device and does have URAMs. Using 2 URAMs saves 14 BRAMs (conserving the BRAM budget for other uses) and uses dedicated cascade connections instead of external MUX logic.

**Resource cost:** 2 URAMs (read latency = 2 cycles), or 16 BRAM 36Kb if URAMs unavailable.

---

### Memory C: Checksum LUT (256 × 8 bits)

**Size:** 256 × 8 = 2,048 bits = 2 Kb.

**Access pattern:** Read-only at runtime. **Asynchronous (combinational) read required** — CRC decode must be purely combinational with no added pipeline latency.

**Analysis:**

This is the defining case where distributed RAM is mandatory regardless of size.

**Why BRAM cannot be used:** BRAM has no asynchronous read mode. Every BRAM read requires at least one clock cycle. If the checksum decode must produce a result combinationally (in the same clock cycle as the input data arrives, with no registered pipeline stage), BRAM is architecturally incompatible.

**Distributed RAM option:**
256 × 8 bits. Using RAM256X1S (256 deep × 1 bit, 4 LUTs per cell): 4 × 8 = 32 SLICEM LUTs.

The synthesis tool can also implement 256 × 8 as a large ROM (read-only memory initialised at synthesis) using LUT INIT strings. Since the table is read-only, synthesis maps it to 8 × LUT8 (8-input LUT using cascaded F7/F8 muxes for 8-wide address) or a combination of standard LUT6 cells with constant outputs (ROM mapping). No distributed RAM primitive is needed — pure LUT logic.

**Recommendation: Distributed RAM or LUT-based ROM.**

For a read-only table initialised from constants, synthesis will use a LUT ROM (INIT-based), not a RAM primitive. This uses approximately **16–32 LUT6 cells** and supports fully combinational lookup.

**Resource cost:** 16–32 LUT6 cells (not SLICEM specifically — any Slice works for ROM).

**Key interview point:** Specifying asynchronous read immediately eliminates BRAM as an option. Always identify read latency requirements before choosing memory type.

---

### Memory D: Statistics Counters (32 × 32 bits)

**Size:** 32 × 32 = 1,024 bits = 1 Kb.

**Access pattern:** Read-modify-write every clock cycle. Counter value read, incremented, and written back — all within one clock.

**Analysis:**

This is the critical case for registers vs. distributed RAM vs. BRAM.

**BRAM option:** BRAM read latency is 1 cycle (or 2 with output register). A read-modify-write in BRAM requires at minimum:
- Cycle N: issue read address
- Cycle N+1: read data available (1-cycle latency) — increment value
- Cycle N+1 or N+2: write incremented value back to BRAM

This creates a 2-cycle read-modify-write loop. At 250 MHz with one counter update per cycle, the pipeline can handle it only if each counter is only updated once every 2 cycles (interleaved). If back-to-back updates to the same counter are required, a write-after-read hazard exists and the pipeline must stall or forward. BRAM does not support forwarding — a RAW hazard would corrupt the counter.

**Distributed RAM option:** Distributed RAM has asynchronous read. The counter value appears combinationally from the address. The increment and write-back happen in one registered cycle:

```vhdl
-- Combinational read
current_count <= counter_ram(to_integer(unsigned(counter_addr)));

-- Registered write (increment)
process(clk)
begin
  if rising_edge(clk) then
    counter_ram(to_integer(unsigned(counter_addr))) 
      <= std_logic_vector(unsigned(current_count) + 1);
  end if;
end process;
```

This works for single-port access (one counter updated per cycle) without a hazard because the read is combinational and the write happens at the clock edge.

32 × 32 bits = 1,024 bits. Using RAM32M (32 × 8b, 2 LUTs per 8-bit cell): $\frac{32}{8} = 4$ RAM32M cells. Total: **8 SLICEM LUTs**.

**Registers option:** 32 × 32-bit registers = 1,024 flip-flops. One register per counter, read combinationally, incremented and registered every cycle. No packing efficiency but maximum flexibility (any counter accessible any cycle, true multi-port). Cost: 1,024 FFs + ~32 LUTs for increment logic.

**Recommendation: Distributed RAM (RAM32M).**

Rationale: 8 SLICEM LUTs for the array is significantly more area-efficient than 1,024 FFs for 32 counters. The async read property enables single-cycle read-modify-write without pipeline hazards. BRAM is incompatible with the single-cycle RMW requirement.

**Resource cost:** 8 SLICEM LUT6 cells + 32-bit increment adder in logic (1 CARRY8 = ~8 LUTs).

---

### Memory E: Packet Reorder Buffer (1,024 × 256 bits)

**Size:** 1,024 × 256 = 262,144 bits = 256 Kb.

**Access pattern:** Burst write, burst read (store-and-forward). Synchronous read. Two independent burst streams (write one packet, read another simultaneously).

**Analysis:**

256 Kb is far too large for distributed RAM efficiently: $\frac{262,144}{64} = 4,096$ SLICEM LUTs (6.3% of available). Not recommended for a simple packet buffer.

**BRAM option:**

Width 256 bits. Each 36Kb BRAM in SDP mode provides 64 bits wide. To achieve 256-bit width: $\frac{256}{64} = 4$ BRAMs in parallel.
Depth: 1,024 ÷ 512 = 2 cascaded for depth.

Total: 4 × 2 = **8 × 36Kb BRAMs**.

Using TDP mode: Port A (write) and Port B (read) can operate simultaneously and independently, supporting the simultaneous write-one-packet / read-another pattern.

**URAM option:**

1,024 × 256 bits. Each URAM: 4,096 × 72 bits. For 256-bit width: $\frac{256}{72} = 3.6$ → 4 URAMs in parallel. Depth 1,024 < 4,096 — fits in depth. Total: **4 URAMs** (4× less than BRAMs, but wastes some width since 4×72 = 288 > 256).

URAMs support simultaneous port A and port B access (different addresses) — perfect for the burst write / burst read pattern.

**Recommendation: URAM (4 URAMs).**

4 URAMs vs 8 BRAMs. The URAM solution:
- Saves 8 BRAMs (large saving on the 312-BRAM KU5P)
- Supports simultaneous write/read via dual-port URAM
- Has 2-cycle read latency — acceptable for a packet reorder buffer (latency is dominated by packet store-and-forward anyway)

**Resource cost:** 4 URAMs.

---

### Summary Table

| Memory | Depth × Width | Total bits | Recommendation | BRAMs | URAMs | LUTs (SLICEM) |
|---|---|---|---|---|---|---|
| A: Header cache | 64 × 128 | 8 Kb | Distributed RAM (RAM64M8) | 0 | 0 | 16 |
| B: Flow table | 8,192 × 64 | 512 Kb | URAM (cascade) | 0 | 2 | 0 |
| C: Checksum LUT | 256 × 8 | 2 Kb | LUT ROM (async read mandatory) | 0 | 0 | 16–32 |
| D: Statistics | 32 × 32 | 1 Kb | Distributed RAM (async RMW) | 0 | 0 | 8 |
| E: Reorder buffer | 1,024 × 256 | 256 Kb | URAM (dual-port burst) | 0 | 4 | 0 |
| **Totals** | | **~779 Kb** | | **0** | **6** | **~56** |

**BRAM usage: 0 out of 312 (0%).**

This is the key insight: by choosing distributed RAM for small/async memories and URAM for large dense memories, all 312 BRAMs on the KU5P remain available for other design requirements (e.g., FIFOs, protocol buffers, IP cores).

**URAM usage: 6 out of the available URAMs on the KU5P** (varies by device grade — typically 48–120 URAMs on KU5P variants).

---

### Key Decision Rules Illustrated by This Problem

**Rule 1 — Async read mandates distributed RAM (or registers):** Memory C is the canonical example. No flexibility here — BRAM is architecturally incompatible.

**Rule 2 — Single-cycle RMW mandates distributed RAM (or registers):** Memory D. BRAM's 1+ cycle read latency creates a write-after-read hazard in tight RMW loops.

**Rule 3 — Small memories (< ~8 Kb) favour distributed RAM:** Memories A and D. BRAM has high minimum overhead — a 36Kb BRAM used for 8 Kb wastes 78% of capacity.

**Rule 4 — Large dense memories favour BRAM or URAM:** Memories B and E. Distributed RAM at these sizes would consume thousands of SLICEM LUTs and create routing congestion.

**Rule 5 — URAM is preferable to BRAM for memories > 64 Kb:** When the aspect ratio is compatible (near 4K × 72), URAM saves BRAMs at a ratio of approximately 8:1. Always check URAM availability (UltraScale+ only).

**Rule 6 — Preserve BRAMs for IP cores:** Many Xilinx IP cores (PCIe, DDR MIG, AXI interconnect, DSP chains) consume BRAMs internally. Consuming BRAMs in user logic competes with IP requirements. Distributed RAM and URAM should be exhausted before BRAM for user memories where possible.

---

### Common Interview Pitfalls

**Defaulting everything to BRAM:** A candidate who maps all five memories to BRAM demonstrates limited architectural thinking. The first question must always be: "What read latency is required?"

**Forgetting URAMs exist:** Many candidates focus on BRAM vs. distributed RAM and omit URAMs entirely. On UltraScale+, URAMs are often the best choice for large dense memories. Mentioning URAMs and their constraints (2-cycle read, fixed 4K × 72, UltraScale+ only) distinguishes a strong candidate.

**Not quantifying the BRAM budget:** Saying "use BRAM for Memory B" without noting it consumes 16 of the 312 available BRAMs (5%) is incomplete. Resource budget awareness is what separates architects from implementers.
