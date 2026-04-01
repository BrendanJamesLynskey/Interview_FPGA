# Zynq and SoC FPGAs: PS-PL Integration and Architecture

Interview preparation covering AMD/Xilinx Zynq-7000, Zynq UltraScale+ MPSoC, Zynq UltraScale+
RFSoC, and Intel Agilex SoC FPGAs. SoC FPGAs are one of the most commercially important FPGA
product categories, appearing in embedded systems, automotive, aerospace, communications infrastructure,
and medical devices. Interview questions in this area test understanding of the hardware architecture,
the PS-PL interface (particularly AXI), the software stack, and real-world integration tradeoffs.

---

## Tier 1 — Fundamentals

### SoC FPGA Concept

A System-on-Chip FPGA integrates a hardened processor subsystem (PS) and programmable logic (PL)
on the same silicon die. The PS is not soft-core logic synthesised in LUTs: it is a fixed,
hardened processor complex (ARM Cortex cores, memory controllers, peripherals) that cannot be
modified by the FPGA configuration. The PL is standard FPGA fabric that can be programmed to
implement any digital logic.

The fundamental value proposition: high-bandwidth, low-latency coupling between the processor
and programmable accelerator logic, without going through a PCIe bus or other board-level interface.

**AMD/Xilinx SoC FPGA families:**

| Device Family              | Processor                           | Process Node | Key Markets               |
|----------------------------|-------------------------------------|--------------|---------------------------|
| Zynq-7000 (Z-7010 to Z-7100) | Dual Cortex-A9 (up to 1 GHz)      | TSMC 28nm    | Embedded, industrial      |
| Zynq UltraScale+ MPSoC     | Quad Cortex-A53 + Dual Cortex-R5F  | TSMC 16nm    | Automotive, comms, defense|
| Zynq UltraScale+ RFSoC     | Same as MPSoC + hardened ADC/DAC   | TSMC 16nm    | 5G radio, radar, test     |
| Versal ACAP                | Dual Cortex-A72 + Dual Cortex-R5F + AI Engines | TSMC 7nm | AI/ML inference, 5G |

**Intel Agilex SoC FPGAs:**

| Device Family              | Processor                           | Process Node | Key Markets               |
|----------------------------|-------------------------------------|--------------|---------------------------|
| Agilex 7 SoC               | Quad Cortex-A53 (up to 1.5 GHz)    | Intel 10nm   | Datacenter, networking    |
| Agilex 5 SoC               | Dual Cortex-A76 + Dual Cortex-A55  | Intel 7      | Automotive ADAS, embedded |
| Intel SX SoC (Stratix 10 SX)| Quad Cortex-A53                   | Intel 14nm   | Defense, comms            |

---

### The PS-PL Interface

The PS-PL interface is how the processor and FPGA logic communicate. In all AMD SoC FPGAs, this
is implemented using AXI (Advanced eXtensible Interface), part of the ARM AMBA protocol suite.
Intel Agilex SoC uses an Avalon-MM (Memory-Mapped) bridge in addition to AXI.

**AXI protocol family overview:**

```
AXI4         -- Full AXI: burst transactions, multiple outstanding transactions (high bandwidth)
AXI4-Lite    -- Simplified: no bursts, single transaction at a time (simple register access)
AXI4-Stream  -- Streaming: no address, unidirectional, with valid/ready handshake
```

**Zynq-7000 PS-PL interface ports:**

The Zynq-7000 PS exposes specific AXI ports to the PL:

```
From PS to PL (PS is AXI Master):
  M_AXI_GP0, M_AXI_GP1   -- 32-bit General Purpose AXI masters
                              PS CPU reads/writes PL-side registers/memories
                              Bandwidth: ~1 Gb/s each

From PL to PS (PL is AXI Master):
  S_AXI_GP0, S_AXI_GP1   -- 32-bit AXI slaves in PS (access PS DDR3, OCM)
  S_AXI_ACP               -- 64-bit AXI Coherent Port: PL accesses Cortex-A9 cache
                              Maintains cache coherency -- use for DMA to shared memory
  S_AXI_HP0-HP3           -- 64-bit High-Performance ports: PL DMA to PS DDR3
                              Bandwidth: ~1.2 GB/s each; 4 ports = ~5 GB/s total
```

A typical Zynq-7000 design pattern:

```
Cortex-A9 (PS)                    PL
     |                             |
M_AXI_GP0 ────────────────────> Custom registers (AXI4-Lite slave)
                                   - Start/stop accelerator
                                   - Configure parameters
                                   - Read status/interrupts
     |
S_AXI_HP0 <──────────────────── DMA engine (AXI4 master)
                                   - Reads input data from DDR3
                                   - Writes results to DDR3
     |
(PS DDR3 Controller)
     |
   DDR3 SDRAM
```

---

### Fundamentals Interview Questions

**Q1. What is the difference between M_AXI_GP and S_AXI_HP in Zynq-7000, and when would you use each?**

Answer:

These are two fundamentally different types of PS-PL interface ports with opposite directions and
different use cases:

**M_AXI_GP (Master, General Purpose):**
- Direction: PS is the AXI master, PL contains AXI slaves.
- Width: 32 bits.
- The Cortex-A9 processor initiates transactions on this bus to read or write to PL-side logic.
- Use case: The processor configuring or controlling PL accelerators. For example, writing a
  start register to kick off an accelerator, reading a status register to check completion,
  or writing configuration parameters (thresholds, lengths, addresses).
- Bandwidth: ~600 MB/s to 1 GB/s theoretical, in practice much lower due to CPU overhead.
- Limitation: NOT suitable for high-bandwidth data transfer. Each transaction is CPU-initiated
  and the CPU must either poll or use interrupts for every transfer.

**S_AXI_HP (Slave, High Performance):**
- Direction: PL is the AXI master, PS DDR3 controller is the slave.
- Width: 64 bits (or 32-bit mode configurable).
- The PL logic (typically a DMA engine) initiates burst transactions to access PS-side DDR3 memory.
- Use case: High-bandwidth bulk data movement between PL accelerator and system memory.
  For example, a video processing accelerator DMAing a frame from DDR3, processing it in PL,
  and writing results back to DDR3 for the CPU to consume.
- Bandwidth: Up to ~1.2 GB/s per port, four ports available (S_AXI_HP0 through HP3).
- Includes an internal FIFO buffer (read/write command and data FIFOs configurable to 512 or 1024 entries).

**S_AXI_ACP (Slave, Accelerator Coherency Port):**
- Also PL is master, PS is slave, but with cache coherency.
- Data written via ACP is visible in Cortex-A9 L2 cache (if cache-line aligned).
- Use case: Tight producer-consumer between PL accelerator and CPU where cache coherency is
  required (no explicit cache flush/invalidate needed).
- Bandwidth: Lower than HP ports (~600 MB/s), with coherency overhead.
- Risk: Cache thrashing if used incorrectly. Only use when data is subsequently read by the CPU
  in cache-relevant access patterns.

**Typical design choice:**
- CPU configures accelerator → use M_AXI_GP.
- Accelerator bulk transfers → use S_AXI_HP.
- Tight CPU+accelerator sharing of small buffers → consider S_AXI_ACP.

---

**Q2. What is AXI4-Lite and how is it typically used in Zynq designs?**

Answer:

AXI4-Lite is a simplified subset of AXI4 that removes burst transfers and multiple outstanding
transactions. Every transaction consists of exactly one address phase and one data phase.

**AXI4-Lite signal channels (master perspective):**

```
Write address channel:  AWVALID, AWREADY, AWADDR[31:0], AWPROT[2:0]
Write data channel:     WVALID, WREADY, WDATA[31:0], WSTRB[3:0]
Write response channel: BVALID, BREADY, BRESP[1:0]
Read address channel:   ARVALID, ARREADY, ARADDR[31:0], ARPROT[2:0]
Read data channel:      RVALID, RREADY, RDATA[31:0], RRESP[1:0]
```

**Typical use in Zynq:**

The PS Cortex-A9 (via M_AXI_GP) accesses a custom PL peripheral through an AXI4-Lite register
interface. The custom peripheral exposes a set of 32-bit registers at a base address mapped into
the PS address space.

```vhdl
-- AXI4-Lite slave register bank (simplified example)
-- Registers:
--   0x00: CTRL (bit 0 = start, bit 1 = reset)
--   0x04: STATUS (bit 0 = busy, bit 1 = done, bit 2 = error)
--   0x08: DATA_IN_ADDR (32-bit, DMA source address)
--   0x0C: DATA_OUT_ADDR (32-bit, DMA destination address)
--   0x10: LENGTH (number of samples)

architecture rtl of axi_lite_slave is
    -- Register storage
    signal ctrl_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal status_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal din_addr_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal dout_addr_reg: std_logic_vector(31 downto 0) := (others => '0');
    signal length_reg   : std_logic_vector(31 downto 0) := (others => '0');

    -- AXI handshake state
    signal aw_hs : std_logic;  -- Write address handshake complete
    signal w_hs  : std_logic;  -- Write data handshake complete
    
begin
    -- Write address channel: accept immediately
    S_AXI_AWREADY <= '1';
    aw_hs <= S_AXI_AWVALID;   -- simplified; in real design, latch AWADDR

    -- Write data channel: accept immediately
    S_AXI_WREADY <= '1';
    w_hs <= S_AXI_WVALID;

    -- Write response: always OKAY
    S_AXI_BRESP  <= "00";
    S_AXI_BVALID <= aw_hs and w_hs;

    -- Register write logic
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' then
                case S_AXI_AWADDR(4 downto 2) is  -- Word-aligned addressing
                    when "000" => ctrl_reg      <= S_AXI_WDATA;
                    when "010" => din_addr_reg  <= S_AXI_WDATA;
                    when "011" => dout_addr_reg <= S_AXI_WDATA;
                    when "100" => length_reg    <= S_AXI_WDATA;
                    when others => null;
                end case;
            end if;
        end if;
    end process;

    -- Export registers to accelerator logic
    start    <= ctrl_reg(0);
    src_addr <= din_addr_reg;
    dst_addr <= dout_addr_reg;
    n_samples <= length_reg;
    
    -- Status feedback from accelerator
    status_reg(0) <= busy_flag;
    status_reg(1) <= done_flag;
    status_reg(2) <= error_flag;

end architecture rtl;
```

From the Linux driver on the PS, this register bank appears as a memory-mapped device:
```c
/* Linux kernel driver snippet */
void __iomem *base = ioremap(ACCEL_BASE_ADDR, 0x20);

/* Configure and start accelerator */
iowrite32(src_buf_phys, base + 0x08);   /* DATA_IN_ADDR  */
iowrite32(dst_buf_phys, base + 0x0C);   /* DATA_OUT_ADDR */
iowrite32(1024, base + 0x10);            /* LENGTH        */
iowrite32(0x1, base + 0x00);             /* CTRL: start   */

/* Poll for completion (or use interrupt in production) */
while (!(ioread32(base + 0x04) & 0x2))  /* STATUS bit 1 (done) */
    cpu_relax();
```

---

## Tier 2 — Intermediate

### Zynq UltraScale+ MPSoC Architecture

The MPSoC PS is substantially more complex than Zynq-7000:

```
Application Processing Unit (APU): Quad Cortex-A53 (ARMv8-A, 64-bit, up to 1.5 GHz)
                                    Shared 1 MB L2 cache
                                    NEON/FPU

Real-Time Processing Unit (RPU):   Dual Cortex-R5F (ARMv7-R, 32-bit, up to 600 MHz)
                                    Tightly coupled memory (TCM)
                                    Lockstep mode (both cores execute same code for safety)

Platform Management Unit (PMU):    MicroBlaze-based (hardened) for power sequencing
Graphics Processing Unit:          ARM Mali-400 MP2

PS-PL Interfaces:
  HPM0_FPD, HPM1_FPD:   AXI4 Master (PS→PL), full-performance, 128-bit
  HPC0_FPD, HPC1_FPD:   AXI4 High-Performance Coherent (PL→PS DDR4, cache-coherent, 128-bit)
  HP0_FPD to HP3_FPD:   AXI4 High-Performance (PL→PS DDR4, non-coherent, 128-bit)
  LPD_M_AXI:            AXI4 Master from RPU domain
  S_AXI_LPD:            AXI4 Slave in low-power domain

DDR4 Memory Controller: Up to 4 GB LPDDR4 or DDR4 attached to PS
```

The key improvement over Zynq-7000: the PS-PL interface is 128 bits wide (vs 64 bits for HP
in Zynq-7000), and the AXI master from the PL now has two coherent ports (HPC) instead of the
single ACP in Zynq-7000.

**Intel Agilex SoC HPS (Hard Processor System):**

```
Cortex-A53 quad-core (ARMv8-A, 64-bit, up to 1.5 GHz)
L2 cache: 1 MB shared
HPS-to-FPGA bridges:
  HPS-to-FPGA (H2F):          AXI4 Master, 1024-bit wide (!), for high-bandwidth CPU→FPGA
  Lightweight HPS-to-FPGA (LW_H2F): AXI4-Lite, 32-bit, for register access
  FPGA-to-HPS (F2H):          AXI4 Slave, 1024-bit wide, FPGA→HPS DDR4
  FPGA-to-HPS (F2H Coherent): AXI4 cache-coherent variant
HPS memory: DDR4/LPDDR5 controller
```

The 1024-bit H2F bridge in Agilex HPS is notably wider than Zynq MPSoC's 128-bit interfaces,
providing higher peak bandwidth for bulk CPU→FPGA data transfers. However, the effective
bandwidth is still limited by the underlying memory hierarchy.

---

### Intermediate Interview Questions

**Q3. Explain the Zynq UltraScale+ MPSoC PS-PL AXI interconnect hierarchy. How does the Coherency Port (HPC) differ from the High-Performance port (HP)?**

Answer:

The MPSoC PS-PL interface is organised into two functional domains with different performance
and coherency characteristics:

**Full Power Domain (FPD) interfaces** -- connected to APU (Cortex-A53):
- Highest performance.
- 128-bit AXI interface to the FPGA PL.
- Access to PS DDR4 controller and on-chip OCM.

**Low Power Domain (LPD) interfaces** -- connected to RPU (Cortex-R5F):
- Lower bandwidth than FPD.
- Used for real-time control paths from PL to RPU.

**HP vs HPC difference:**

The HP (High-Performance) ports are **non-coherent** AXI slaves in the PS. When the PL DMA
engine writes to a DDR4 buffer via HP0_FPD, that data is written to DRAM directly, bypassing
the Cortex-A53 L1/L2 caches. Before the CPU reads that buffer, software must invalidate the
CPU cache for the relevant memory region:

```c
/* Linux: explicit cache management for non-coherent DMA (HP port) */
dma_addr_t dma_handle;
void *cpu_addr = dma_alloc_coherent(dev, size, &dma_handle, GFP_KERNEL);

/* After FPGA writes to dma_handle via HP port: */
dma_sync_single_for_cpu(dev, dma_handle, size, DMA_FROM_DEVICE);
/* Now CPU can safely read cpu_addr */
```

The HPC (High-Performance Coherent) ports are **cache-coherent** AXI slaves. Transactions
through HPC participate in the APU's ACE (AXI Coherency Extensions) snooping protocol. When
the PL DMA writes to DDR4 via HPC0_FPD:
- If the target address is in the CPU's L2 cache, the write updates the cache line in-place.
- The CPU can subsequently read from that address without a cache flush.
- No software cache management is needed.

**When to use each:**

| Scenario                                         | Use HP     | Use HPC        |
|--------------------------------------------------|------------|----------------|
| Large bulk transfer, CPU reads result later      | Yes (faster, lower overhead) |     |
| Tight producer-consumer: FPGA writes, CPU reads immediately | | Yes (coherency) |
| FPGA writes metadata/control structures CPU polls | | Yes (no flush needed) |
| Multiple FPGA engines writing independent buffers| Yes        |                |
| Real-time with bounded latency requirement       |            | Yes (no flush latency spike) |

**Performance tradeoff:** HPC coherency has overhead from cache snooping. For bulk transfers
where the CPU doesn't immediately re-read the data, HP + explicit cache sync is often faster
because the coherency snooping traffic is avoided.

---

**Q4. Describe the typical software architecture for a Zynq MPSoC accelerator design. How does the Linux driver interact with the PS-PL interface?**

Answer:

A production Zynq MPSoC accelerator typically uses a layered software stack:

```
User Space Application
        |
   XRT / custom library API  (or direct /dev/uio access)
        |
   Linux Kernel Driver  (platform driver or PCIe-like driver)
        |
   Device Tree (hardware description)
        |
   PS-PL Hardware Interface (AXI4-Lite control, AXI4 DMA)
        |
   PL Accelerator Logic
```

**Device Tree:**

The device tree describes the hardware topology to the Linux kernel:

```dts
/* Device tree fragment for a custom accelerator */
my_accelerator: accelerator@a0000000 {
    compatible = "company,my-accel-1.0";
    reg = <0x0 0xa0000000 0x0 0x10000>;  /* AXI4-Lite register space, 64 KB */
    interrupts = <0 89 4>;               /* SPI interrupt 89 (edge-sensitive) */
    interrupt-parent = <&gic>;
    clocks = <&zynqmp_clk 71>;           /* PL clock 0 */
    clock-names = "ap_clk";
    /* DMA configuration */
    dmas = <&fpga_dma 0>;
    dma-names = "rx";
};
```

**Platform driver structure (kernel space):**

```c
#include <linux/platform_device.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>

struct my_accel_dev {
    void __iomem     *base;          /* AXI4-Lite register base */
    struct dma_chan  *dma_chan;       /* DMA channel (AXI DMA or ZDMA) */
    int               irq;           /* Interrupt number */
    struct completion done;          /* Completion for interrupt signalling */
};

static int my_accel_probe(struct platform_device *pdev) {
    struct my_accel_dev *dev;
    struct resource *res;
    
    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    
    /* Map AXI4-Lite register space */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    dev->base = devm_ioremap_resource(&pdev->dev, res);
    
    /* Get interrupt */
    dev->irq = platform_get_irq(pdev, 0);
    devm_request_irq(&pdev->dev, dev->irq, my_accel_irq_handler,
                     IRQF_TRIGGER_RISING, "my_accel", dev);
    
    /* Get DMA channel */
    dev->dma_chan = dma_request_chan(&pdev->dev, "rx");
    
    init_completion(&dev->done);
    platform_set_drvdata(pdev, dev);
    return 0;
}

/* Accelerator invocation function */
int my_accel_run(struct my_accel_dev *dev, dma_addr_t src, dma_addr_t dst, u32 n) {
    /* Configure accelerator via AXI4-Lite */
    iowrite32(src, dev->base + REG_SRC_ADDR);
    iowrite32(dst, dev->base + REG_DST_ADDR);
    iowrite32(n,   dev->base + REG_LENGTH);
    
    reinit_completion(&dev->done);
    
    /* Start accelerator */
    iowrite32(CTRL_START, dev->base + REG_CTRL);
    
    /* Wait for done interrupt (with timeout) */
    if (!wait_for_completion_timeout(&dev->done, msecs_to_jiffies(1000)))
        return -ETIMEDOUT;
    
    return 0;
}

static irqreturn_t my_accel_irq_handler(int irq, void *data) {
    struct my_accel_dev *dev = data;
    u32 status = ioread32(dev->base + REG_STATUS);
    
    if (status & STATUS_DONE) {
        iowrite32(STATUS_DONE, dev->base + REG_STATUS);  /* Clear interrupt */
        complete(&dev->done);
        return IRQ_HANDLED;
    }
    return IRQ_NONE;
}
```

**Interrupt strategy:**

The PL asserts an interrupt to the PS GIC (Generic Interrupt Controller) when processing is
complete. From the Zynq hardware perspective, PL interrupts connect to the GIC via specific
PS-PL interrupt lines (in Zynq-7000: pl_ps_irq[15:0]; in MPSoC: pl_ps_irq[7:0] per domain).
The interrupt line must be configured in the PL logic (e.g., an AXI4-Lite status register bit
drives the interrupt output) and connected in Vivado IP Integrator.

---

**Q5. What is the Zynq UltraScale+ RFSoC and what distinguishes it from MPSoC for RF applications?**

Answer:

The RFSoC (Radio Frequency SoC) is a specialised variant of Zynq UltraScale+ MPSoC that adds
hardened RF data conversion circuitry on the same die:

**Additional hardware in RFSoC (not present in standard MPSoC):**

- **RF-ADC (Analog-to-Digital Converters)**: Up to 16 RF-ADCs depending on the device variant.
  Sampling rates: 2 GSPS to 4 GSPS (2nd generation, e.g., ZU28DR) or 5 GSPS (3rd generation).
  Resolution: 12-bit (earlier), 14-bit (later generations).
  Each ADC includes a Digital Down Converter (DDC) chain: mixer, CIC decimator, FIR decimator.
  The DDC produces IQ samples at a manageable rate for the PL (e.g., 5 GSPS ADC with 16× decimation
  outputs 312 MSPS complex IQ to the PL).

- **RF-DAC (Digital-to-Analog Converters)**: Up to 16 RF-DACs.
  Output rates: up to 10 GSPS.
  Each DAC includes a Digital Up Converter (DUC): FIR interpolation, CIC interpolation, mixer.

**Why this matters for RF design:**

Without RFSoC, a 5G NR base station or radar DSP chain would require:
- Discrete ADC chips (e.g., Texas Instruments ADC32RF45 at 3 GSPS).
- SiGe or GaAs front-end for the mixer/LO.
- JESD204B/C interface FPGA IP to deserialise ADC outputs.
- Multiple PCB layers, signal integrity engineering for multi-Gb/s serial lanes.
- Power regulators, LDOs, and clock distribution across multiple chips.

With RFSoC:
- ADC and DAC are on-chip with the FPGA fabric.
- No JESD204 deserialiser needed (data goes directly onto internal fabric buses).
- The RF front-end (LNA, PA, filter) is still discrete, but the converter stage is integrated.
- Much lower latency from antenna to digital processing (no JESD204 framing delay).

**PL connection:**

The RF-ADC and RF-DAC connect to the PL fabric via AXI4-Stream interfaces (IQ data stream) and
are configured via AXI4-Lite registers. The Xilinx RF Data Converter IP (RFdc) wraps this
interface and provides a software API.

**Agilex equivalent:** Intel does not have a direct RFSoC equivalent (as of 2025). Intel's answer
for 5G O-RAN involves Agilex 7 FPGAs with external ADC/DAC and JESD204C deserialiser IP.
The AMD/Xilinx RFSoC is a unique competitive advantage in the telecom space.

---

## Tier 3 — Advanced

### Advanced Interview Questions

**Q6. A design requires the Cortex-A53 on Zynq MPSoC to share a 64 KB lookup table with a PL accelerator at < 1 microsecond latency. The CPU updates the table; the PL reads it. Describe the memory architecture options and tradeoffs.**

Answer:

This is a real design problem involving shared memory semantics, coherency, and latency. Several
architectural options exist:

**Option 1: OCM (On-Chip Memory) accessed via S_AXI_LPD or similar**

The MPSoC has 256 KB of OCM (On-Chip Memory) that is SRAM inside the PS. It has fixed addresses
(0xFFFC0000 base). The CPU can write to it directly; the PL can access it via the PS-PL interface.

- Latency: OCM access from PL via the low-power domain AXI is ~20--50 ns (low latency because
  it is SRAM, not DDR4).
- 64 KB is well within the 256 KB OCM capacity.
- No cache coherency issue: OCM is not cached by Cortex-A53 L1/L2 (it is separate from DDR4).
  CPU writes go directly to SRAM; PL reads see the latest value immediately.
- Bandwidth: Limited by the LPD AXI interface (~256-bit, ~1 GB/s).

This is often the best solution for small shared tables with latency requirements.

**Option 2: DDR4 via HP port with explicit cache flush**

CPU writes to a DDR4 buffer, flushes the CPU cache, then signals the PL via an interrupt or
status flag. PL DMA reads the buffer via HP0_FPD.

- Latency: Cache flush (`dma_sync_single_for_device`) is deterministic but can take 5--20 µs
  for 64 KB depending on cache state and CPU load. This exceeds the 1 µs requirement.
- Bandwidth: DDR4 via HP has excellent bandwidth for bulk transfers.
- Conclusion: Does NOT meet the 1 µs latency requirement due to cache flush time.

**Option 3: DDR4 via HPC port (cache-coherent)**

CPU writes to a DDR4 buffer via normal store instructions. PL reads via HPC0_FPD (cache-coherent).
No software flush required. The hardware coherency protocol ensures PL reads see the latest data.

- Latency for PL to read updated data: Coherency snoop latency. The HPC coherency path adds
  ~10--50 ns overhead per cache line access. For 64 KB = 1024 cache lines (64 bytes each),
  sequential read latency is acceptable.
- Bandwidth: Lower than HP for sustained transfers due to snoop overhead.
- Latency concern: The CPU write must complete (write buffer drained) before the PL read
  reflects the new data. A memory barrier (`dsb ish`) on the CPU side after the write ensures
  this: `asm volatile("dsb ish" ::: "memory");`
- Conclusion: Can meet < 1 µs if the PL reads occur after CPU write completes. The coherency
  overhead is nanoseconds per access, not microseconds.

**Option 4: PL-side BRAM accessed via AXI4-Lite from PS**

Place a 64 KB BRAM in the PL. The CPU accesses it via M_AXI_GP (AXI4-Lite from PS to PL).
The PL accelerator reads the BRAM directly (port B of a true dual-port BRAM).

- CPU write latency to BRAM: ~20--100 ns per write (AXI4-Lite transaction across M_AXI_GP,
  each transaction is one 32-bit word unless burst is used). Writing 64 KB at 32 bits/transaction
  = 16,384 transactions -- this is slow (milliseconds, not microseconds).
- For updates to a small subset of the table (few entries), this works well.
- For full table replacement, use a DMA transaction: set up a PL-side DMA to pull from DDR4
  and write to BRAM at BRAM burst rates.
- Conclusion: Good for sparse updates; poor for full 64 KB table replacement in < 1 µs.

**Recommended architecture:**

For update latency < 1 µs with full 64 KB table:
- Use OCM for the shared table.
- CPU writes via normal stores (SRAM latency ~5--10 ns per word).
- CPU uses a memory barrier after all writes complete.
- PL reads via the PS-PL AXI port that maps OCM (accessible from PL via S_AXI_LPD in MPSoC).
- PL read latency: ~20--50 ns per access, well within 1 µs.
- No cache coherency management needed in software.

For update latency tolerance of > 10 µs with high bandwidth:
- Use DDR4 via HPC (coherent) or HP (with cache flush).

---

**Q7. Describe the boot sequence for Zynq UltraScale+ MPSoC. What is the role of FSBL, U-Boot, and ATF, and how does the PL get configured?**

Answer:

The MPSoC boot sequence is multi-stage and significantly more complex than Zynq-7000 due to
ARM TrustZone, EL3/EL2/EL1 execution levels, and the PMU power sequencer.

**Boot stages:**

```
Stage 0: On-chip ROM (BootROM)
  - Hardened code in the PMU MicroBlaze and Cortex-A53 ROM.
  - PMU BootROM initialises the PMU and power domains.
  - Cortex-A53 BootROM reads the boot header from the boot device (QSPI, SD, eMMC, JTAG).
  - Loads and authenticates (if secure boot enabled) the FSBL image.
  - Starts the FSBL on Cortex-A53 EL3.
         |
Stage 1: FSBL (First-Stage Boot Loader)
  - Xilinx-provided C code, compiled with Vitis.
  - Runs at EL3 (highest privilege) on Cortex-A53.
  - Initialises: DDR4 (via PS DDR controller), MIO pin configurations, clocks.
  - Loads PL bitstream: writes the .bit or .bin file to the PL Configuration Manager (PCAP).
    The PCAP interface in MPSoC is accessible from the PS. FSBL calls XFpga_PL_BitStream_Load().
  - Loads ATF (ARM Trusted Firmware) to DDR4.
  - Loads U-Boot to DDR4.
  - Hands off to ATF (FSBL sets EL3 vector table to ATF entry point and executes SMC).
         |
Stage 2: ATF (ARM Trusted Firmware / BL31)
  - Open-source ARM reference firmware, customised by Xilinx.
  - Remains resident at EL3 to handle Secure Monitor Calls (SMC) from OS.
  - Provides PSCI (Power State Coordination Interface): CPU hotplug, suspend/resume.
  - Loads U-Boot as BL33 (Non-Secure World BL3-3) at EL2.
         |
Stage 3: U-Boot (Universal Boot Loader)
  - Runs at EL2 (hypervisor level, non-secure).
  - Initialises Ethernet, USB, storage for network/SD boot.
  - Loads Linux kernel Image, DTB (Device Tree Blob), and initrd/rootfs.
  - Passes DTB to kernel, starts kernel at EL1.
         |
Stage 4: Linux Kernel + User Space
  - Runs at EL1 (OS) / EL0 (user space).
  - Loads FPGA bitstream at runtime via Linux FPGA Manager framework (optional, for partial
    reconfiguration or late PL configuration).
  - Platform drivers discover accelerators via Device Tree.
```

**PL configuration methods:**

1. **FSBL (recommended for production)**: FSBL programs the PL during boot before Linux starts.
   The .bit file is embedded in the BOOT.BIN alongside FSBL and U-Boot. PL is ready when Linux
   boots.

2. **Linux FPGA Manager**: For partial reconfiguration or multi-application scenarios where
   different bitstreams are loaded at runtime:
   ```bash
   # Load bitstream from Linux userspace
   mkdir -p /lib/firmware
   cp my_design.bin /lib/firmware/
   echo 0 > /sys/class/fpga_manager/fpga0/flags
   echo my_design.bin > /sys/class/fpga_manager/fpga0/firmware
   ```
   The FPGA Manager framework calls the PS PCAP driver to program the PL. Requires the bitstream
   in .bin format (raw binary, not .bit with header).

3. **JTAG (debug only)**: Vivado Hardware Manager programs the PL directly via JTAG.

**Intel Agilex SoC boot:**

Agilex SoC has a similar multi-stage boot:
- **Boot ROM** (hardened): Reads SDM (Secure Device Manager) configuration.
- **SDM**: Programs the FPGA fabric first (unlike Zynq where PS boots before PL; Agilex
  programs PL very early in the boot sequence).
- **HPS BootROM**: Loads U-Boot SPL from QSPI or SD.
- **U-Boot SPL**: Initialises DDR4, loads full U-Boot.
- **U-Boot**: Loads Linux.

A key architectural difference: in Agilex, the SDM programs the FPGA fabric very early (before
HPS boots). In Zynq, the FSBL runs on Cortex-A53 to program the PL, meaning the processor is
running before PL configuration. This distinction matters for designs where PL peripherals
(e.g., UART, status LEDs) need to be available early in the boot sequence.

---

**Q8. Compare Dynamic Function eXchange (DFX) in UltraScale+ with Partial Reconfiguration in Agilex. What are the constraints on the PS-PL interface during a partial reconfiguration event?**

Answer:

Partial reconfiguration (PR) allows a portion of the FPGA fabric to be reprogrammed at runtime
while the rest of the device continues operating. In Zynq and Agilex SoC devices, this is
particularly powerful because the processor subsystem keeps running while the PL accelerator
is being swapped.

**UltraScale+ / Zynq: DFX (Dynamic Function eXchange):**

DFX requires a specific design structure:
- **Static region**: The portion of the PL that never changes. Contains the PS-PL interface
  logic, DFX Controller IP, clock networks, and any accelerator logic that is always present.
- **Reconfigurable Partition (RP)**: The pblock region that will be reprogrammed. One or more
  RPs can exist.
- **Reconfigurable Module (RM)**: A specific implementation of a function that occupies an RP.
  Multiple RMs can be designed for each RP (e.g., "RM_FFT" and "RM_FIR" for the same RP).
- **Partial bitstream**: A bitstream file that reprograms only the RP region.

```tcl
# Vivado DFX setup in Tcl
# Mark the partition as reconfigurable
set_property HD.RECONFIGURABLE true [get_cells u_accel_partition]

# Create pblock for the reconfigurable region
create_pblock rp_accel
add_cells_to_pblock rp_accel [get_cells u_accel_partition]
resize_pblock rp_accel -add {SLICE_X0Y0:SLICE_X49Y99 DSP48E2_X0Y0:DSP48E2_X3Y39}

# Implement with RM_A
set_property RM_MODULE RM_FFT [get_cells u_accel_partition]
implement_design

# Generate full and partial bitstreams
write_bitstream -cell u_accel_partition ./partial_rm_fft.bit   ;# Partial only
write_bitstream ./full_rm_fft.bit                              ;# Full (for initial config)
```

**PS-PL interface behaviour during DFX reconfiguration:**

This is the critical interview point. When a partial bitstream is being loaded into an RP:
- **Decoupling is mandatory**: All AXI transactions to/from the RP must be stopped before
  reconfiguration begins. If an AXI master sends a transaction to the RP during reconfiguration,
  the result is undefined (fabric is in an unknown state).
- **DFX Decoupler IP**: AMD provides this IP. It sits between the static AXI interconnect and
  the RP's AXI slave. When activated (via an AXI4-Lite register write), it blocks all AXI
  traffic and returns AXI SLVERR to prevent bus lockup.

```c
/* Software sequence for runtime partial reconfiguration */

/* Step 1: Decouple the RP -- stop AXI transactions */
iowrite32(1, decoupler_base + DECOUPLE_REG);  /* DFX Decoupler active */

/* Step 2: Load partial bitstream via FPGA Manager */
write_partial_bitstream("rm_fir.bin");        /* Linux FPGA Manager */

/* Step 3: Wait for reconfiguration complete */
wait_for_fpga_done();

/* Step 4: Re-couple -- resume AXI transactions */
iowrite32(0, decoupler_base + DECOUPLE_REG);  /* DFX Decoupler inactive */

/* Step 5: (Optional) Reset the newly loaded module */
reset_accelerator();
```

**Clocking during reconfiguration:**

The PL clock driving the RP must be stopped or decoupled during reconfiguration on some devices.
In UltraScale+, the ICAP (Internal Configuration Access Port) handles partial bitstream loading
and automatically manages clock gating for the affected region. Clocks in the static region
continue unaffected.

**Agilex Partial Reconfiguration:**

Agilex PR uses a different mechanism managed by the SDM (Secure Device Manager):
- The SDM is a hardened security/configuration controller. Partial bitstreams are sent to the
  SDM via a dedicated interface (Avalon-MM or direct JTAG).
- Agilex PR does not require a software FPGA Manager in the same way; the SDM handles the
  loading sequence atomically.
- The HPS (Cortex-A53) initiates reconfiguration by writing to the SDM interface. The SDM
  verifies the partial bitstream (authentication and decryption if security is configured)
  and programs the PR region.
- Decoupling is still required: Agilex provides PR IP with Avalon-MM or AXI-compatible
  freeze/unfreeze ports for decoupling.

**Key difference:** In Zynq, the PS directly drives the PCAP/ICAP to load bitstreams (via the
Linux FPGA Manager or FSBL). In Agilex, the SDM is the gatekeeper; the HPS requests
reconfiguration through the SDM interface rather than directly controlling the configuration
circuitry. This is more secure (SDM enforces authentication) but adds an extra layer of
indirection.

**Constraints summary:**

| Requirement during PR           | UltraScale+ / Zynq DFX              | Agilex PR                           |
|---------------------------------|--------------------------------------|-------------------------------------|
| AXI decoupling                  | Required (DFX Decoupler IP)         | Required (freeze IP)                |
| Clock gating for RP             | Managed by ICAP automatically       | Managed by SDM                      |
| Bitstream authentication        | Optional (secure boot config)       | Enforced by SDM if security enabled |
| RP must be pblock-constrained   | Yes (must be in defined pblock)     | Yes (PR region must be pre-defined) |
| Static-RP interface             | PR boundary rules (no combinational | Same: registered boundary required  |
|                                 | logic crossing RP boundary)         |                                     |
| Latency of reconfiguration      | ~ms for small RPs, ~100ms for large | Similar (depends on PR region size) |
