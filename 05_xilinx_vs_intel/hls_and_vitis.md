# HLS and Vitis: High-Level Synthesis and the Vitis Unified Platform

Interview preparation covering AMD/Xilinx Vitis HLS (formerly Vivado HLS), the Vitis unified
software platform, Intel HLS Compiler, and OneAPI for FPGAs. HLS is an increasingly important
skill in FPGA interviews, particularly at companies developing data-centre accelerators, DSP
processing chains, and compute offload engines. The central interview challenge is demonstrating
not just HLS syntax knowledge, but the judgment to know when HLS is the right tool versus RTL.

---

## Tier 1 — Fundamentals

### What is High-Level Synthesis?

High-Level Synthesis (HLS) compiles a behavioural description written in C, C++, or SystemC into
synthesisable RTL (VHDL or Verilog). The generated RTL is then processed through the standard
FPGA implementation flow (Vivado or Quartus). HLS does not eliminate timing closure, place and
route, or constraint writing -- it replaces the manual RTL authoring step for the algorithmic
portion of the design.

**AMD Vitis HLS** (formerly Vivado HLS, rebranded ~2020):
- Input languages: C, C++, SystemC
- Output: Synthesisable Verilog or VHDL RTL + IP-XACT metadata for Vivado IP integrator
- Interface synthesis: Automatically generates AXI4, AXI4-Stream, FIFO, and handshake interfaces
  from C function argument types and pragmas
- Targets: UltraScale+, Versal, Zynq, older 7-series

**Intel HLS Compiler** (i++ compiler):
- Input languages: C, C++
- Output: Synthesisable Verilog for Quartus
- Part of Intel oneAPI toolkit; also available as a standalone component
- Targets: Agilex, Stratix 10, Arria 10

### The HLS Design Abstraction

A C++ function compiled by Vitis HLS becomes an RTL module. The function interface (arguments)
becomes the module port interface. Internal variables become registers or wires. Loops and
conditional branches become datapath control logic.

```cpp
// Simple C++ function: vector dot product
// This exact code can be synthesised by Vitis HLS
#include <ap_int.h>          // Arbitrary-precision integer types

typedef ap_int<16>  data_t;  // 16-bit signed integer
typedef ap_int<32>  acc_t;   // 32-bit accumulator

acc_t dot_product(data_t a[64], data_t b[64]) {
    acc_t result = 0;
    for (int i = 0; i < 64; i++) {
        result += a[i] * b[i];
    }
    return result;
}
```

Without any pragmas, Vitis HLS synthesises this as a sequential loop: one multiply-accumulate per
clock cycle, 64 cycles total. Adding pragmas changes the microarchitecture:

```cpp
acc_t dot_product(data_t a[64], data_t b[64]) {
    acc_t result = 0;
    #pragma HLS PIPELINE II=1    // Pipeline the loop: accept new data every 1 cycle
    for (int i = 0; i < 64; i++) {
        result += a[i] * b[i];
    }
    return result;
}
```

With `PIPELINE II=1`, the loop body is pipelined to accept new iteration data every clock cycle.
This increases throughput to one multiply-accumulate per cycle but may increase resource usage
as multiple iterations are in-flight simultaneously.

---

### Key HLS Concepts

**Initiation Interval (II)**: The number of clock cycles between accepting successive inputs.
II=1 means the function (or loop) can accept new input data every cycle. II=2 means every two
cycles. II=1 is the ideal pipelined case; II > 1 indicates a resource conflict or dependency
preventing full pipelining.

**Latency**: The number of clock cycles from first input valid to last output valid for a single
transaction. A pipelined design with II=1 still has latency > 1; subsequent inputs are accepted
every cycle but the first result takes multiple cycles to emerge.

**Throughput vs latency tradeoff**: HLS makes this tradeoff explicit. RTL engineers face the same
tradeoff but manage it manually. In HLS, pragmas adjust the tradeoff systematically.

---

### Fundamentals Interview Questions

**Q1. What is the initiation interval (II) in HLS and why does achieving II=1 matter?**

Answer:

The initiation interval is the number of clock cycles that must elapse between the start of
consecutive invocations of a pipelined loop body or function. It represents the throughput
bottleneck.

- **II=1**: The loop body starts processing new data on every clock cycle. If the loop body
  contains a multiplier with 3-cycle latency and an adder with 1-cycle latency, they can all be
  in-flight simultaneously at different stages. Full hardware pipelining.
  
- **II=2**: Two cycles must pass between consecutive loop start times. Effective throughput is
  halved. Common causes: a loop-carried dependency (current iteration reads a result written by
  the previous iteration), memory port conflicts (single-port BRAM accessed twice per cycle), or
  a resource constraint (only one multiplier available but the loop body needs two).

**Why II=1 matters:**

For streaming data-processing kernels (e.g., processing every sample of a 1 Gsps ADC stream),
II > 1 means the hardware cannot keep up with the input data rate at the target clock frequency.
If data arrives every clock cycle and II=2, you either need two parallel instances (resource
doubling) or you accept that samples will be dropped.

**Example of II=1 violation:**

```cpp
// This loop has a loop-carried dependency: result is read and written each iteration
acc_t running_sum(data_t x[N]) {
    acc_t result = 0;
    loop: for (int i = 0; i < N; i++) {
        #pragma HLS PIPELINE II=1
        result += x[i];  // result depends on previous iteration's result
    }
    return result;
}
```

The dependency `result += x[i]` means iteration `i` cannot start until iteration `i-1` writes
its result. If the accumulator add takes 1 cycle, the minimum achievable II is 1 (the accumulator
resolves in one cycle). If the accumulator is pipelined (e.g., a floating-point adder with 5-cycle
latency), the loop-carried dependency forces II >= 5.

Vitis HLS reports this in the synthesis report as:
```
WARNING: [SCHED 204-68] Unable to schedule a 1-cycle latency operation
  in a 1-cycle time frame on the accumulator.
  The resource limit causes II = 5.
```

---

**Q2. Name four common Vitis HLS pragmas and explain what each does to the microarchitecture.**

Answer:

**1. `#pragma HLS PIPELINE II=<N>`**

Applies to a loop or function. Tells the HLS tool to pipeline the specified scope so that new
inputs are accepted every N clock cycles. The tool unrolls loop-carried dependencies as needed
and inserts pipeline registers between stages.

Effect on RTL: Generates a pipeline with N-cycle II. Internal state registers hold in-flight
data across multiple concurrent iterations. Combinational logic is balanced across pipeline
stages using retiming.

**2. `#pragma HLS UNROLL factor=<N>`**

Replicates the loop body N times (or fully if no factor given), executing N iterations in
parallel per clock cycle. Increases resource usage (N times the operators) but reduces the
number of cycles by factor N.

```cpp
// Without UNROLL: 8 multiplications over 8 cycles
// With UNROLL factor=4: 4 multiplications per cycle, 2 cycles total
for (int i = 0; i < 8; i++) {
    #pragma HLS UNROLL factor=4
    result[i] = a[i] * b[i];
}
```

Full unroll (`#pragma HLS UNROLL`) of an 8-iteration loop instantiates 8 multipliers and 8
adders, completing in the latency of the deepest path in one pass.

**3. `#pragma HLS ARRAY_PARTITION variable=<array> type=<complete|cyclic|block> factor=<N>`**

Splits an array variable into multiple smaller arrays (or individual registers) so that multiple
elements can be accessed in the same clock cycle. Without partitioning, an array maps to a
single BRAM with one or two read ports -- a bottleneck when an unrolled loop needs to read
multiple elements per cycle.

```cpp
data_t coeff[16];
#pragma HLS ARRAY_PARTITION variable=coeff complete  // 16 separate registers

// Now an unrolled loop can read all 16 coefficients in 1 cycle
```

- `complete`: Each element becomes an individual register. Maximum parallelism, maximum resources.
- `cyclic factor=N`: Elements are round-robin distributed across N banks (index 0 to bank 0,
  index 1 to bank 1, ...). Good for stride-1 access patterns.
- `block factor=N`: Consecutive N elements go to each bank. Good for blocked access patterns.

**4. `#pragma HLS DATAFLOW`**

Enables task-level pipelining across multiple functions or loops. Without DATAFLOW, sequential
function calls execute one after the other (function B waits for function A to finish). With
DATAFLOW, Vitis HLS creates a producer-consumer pipeline: function A starts processing the next
input while function B processes the previous output.

```cpp
void top_function(data_t* in, data_t* out, int N) {
    #pragma HLS DATAFLOW
    
    hls::stream<data_t> s1, s2;  // Channels between tasks
    
    task_A(in,  s1, N);   // Producer
    task_B(s1,  s2, N);   // Intermediate
    task_C(s2, out, N);   // Consumer
}
```

DATAFLOW requires that data flows in one direction only (no feedback between tasks). The
channels between tasks are implemented as FIFOs or PINGs-pong buffers. This is the HLS equivalent
of a hardware pipeline between RTL modules.

---

**Q3. When should you use HLS instead of writing RTL directly? Give examples of both good and poor HLS use cases.**

Answer:

This is a judgment question. The interviewer wants to see nuanced thinking, not "HLS is always
better" or "RTL engineers should never use HLS."

**HLS is well-suited for:**

- **Algorithm implementation with complex control flow**: A Viterbi decoder, LDPC decoder,
  or H.264 inter-prediction has many conditional branches and loop structures that are
  labour-intensive to write in RTL but map naturally to C++.

- **Floating-point datapaths**: Writing IEEE 754 operators in RTL manually is extremely tedious
  and error-prone. HLS automatically maps `float` operations to vendor DSPs and LUT structures.

- **Rapid prototyping and algorithm exploration**: An HLS design can be synthesised in minutes
  to get area/timing estimates, allowing architects to compare multiple algorithmic approaches
  before committing to a full RTL implementation.

- **SW/HW co-design with existing C models**: Many algorithm teams develop and verify C/C++
  models before RTL is written. If the C model is already verified, HLS can produce hardware
  that matches the software model by construction, reducing verification effort.

- **Non-timing-critical control logic**: A configuration parser, command processor, or error
  logging module where maximum frequency is not critical.

**HLS is poorly suited for:**

- **Very-high-speed interfaces**: At 400 MHz+ with tight timing budgets, the HLS-generated RTL
  may not meet timing because the tool has less control over pipeline stage balancing than a
  skilled RTL engineer. The generated RTL is correct but not always optimal.

- **Custom memory interfaces**: If a design requires very specific BRAM access patterns
  (e.g., alternating read-modify-write on a specific address schedule), HLS may generate
  suboptimal or incorrect memory access sequences. RTL gives direct control.

- **Clock domain crossing logic**: HLS has no concept of multiple clock domains. CDC logic
  (synchronisers, async FIFOs, handshakes) must be written in RTL.

- **Designs requiring vendor primitives**: If you need to instantiate ISERDES, GTY transceivers,
  MMCM, or other hard IP, HLS cannot express these. These are always RTL.

- **Latency-deterministic pipelines**: If a protocol requires exactly N cycles of latency
  through a block (e.g., a synchronous pipeline feeding a PCIe TLP formatter), HLS latency
  can change between tool versions, making the design fragile.

**The pragmatic answer for an interview:** HLS and RTL are complementary. In a real design, the
outer shell (I/O interfaces, clock infrastructure, CDC, hard IP) is RTL; the algorithmic core
(signal processing, data transformation, protocol parsing) is often a good HLS candidate. The
HLS output is treated as a black-box IP core and integrated into the RTL framework.

---

## Tier 2 — Intermediate

### Vitis Unified Platform

The Vitis platform (introduced 2019) is AMD's attempt to unify FPGA application development
under a single software-centric framework. It sits above Vivado and targets accelerated computing
workloads on Alveo data-centre cards and Zynq MPSoC/Versal embedded systems.

**Vitis architecture layers:**

```
Application layer:   C++/Python host code using XRT (Xilinx Runtime)
                                |
Kernel layer:        HLS kernels or RTL kernels (compiled to .xo objects)
                                |
Platform layer:      Shell/platform providing PCIe DMA, AXI interconnect, DDR4 controllers
                                |
Hardware layer:      Vivado implementation on target device (Alveo U250, Zynq MPSoC, etc.)
```

**XRT (Xilinx Runtime)**: A standardised API (C++/Python) for managing FPGA kernels from host
code. Handles buffer allocation, kernel invocation, and synchronisation:

```cpp
// Host-side XRT code to invoke an HLS kernel on Alveo
#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>

int main() {
    auto device = xrt::device(0);                         // Open FPGA device
    auto xclbin = device.load_xclbin("my_kernel.xclbin"); // Load bitstream
    auto kernel = xrt::kernel(device, xclbin, "dot_product"); // Get kernel handle
    
    // Allocate device-side buffers (FPGA DDR4)
    auto bo_a = xrt::bo(device, 64 * sizeof(int16_t), kernel.group_id(0));
    auto bo_b = xrt::bo(device, 64 * sizeof(int16_t), kernel.group_id(1));
    
    // Write input data to device buffers
    auto a_map = bo_a.map<int16_t*>();
    // ... fill a_map with data ...
    bo_a.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    
    // Launch kernel (non-blocking)
    auto run = kernel(bo_a, bo_b, 64);
    run.wait();  // Wait for completion
    
    // Read result back
    // ...
    return 0;
}
```

**Intel oneAPI for FPGA:**

Intel's equivalent is the oneAPI toolkit with SYCL (a C++ abstraction over heterogeneous compute).
FPGA kernels are written as SYCL `submit` lambdas with Intel-specific extensions:

```cpp
#include <sycl/sycl.hpp>
#include <sycl/ext/intel/fpga_extensions.hpp>

int main() {
    sycl::queue q(sycl::ext::intel::fpga_selector_v);  // Target FPGA device
    
    sycl::buffer<int16_t, 1> buf_a(a_data.data(), 64);
    sycl::buffer<int16_t, 1> buf_b(b_data.data(), 64);
    sycl::buffer<int32_t, 1> buf_out(&result, 1);
    
    q.submit([&](sycl::handler& h) {
        auto a   = buf_a.get_access<sycl::access::mode::read>(h);
        auto b   = buf_b.get_access<sycl::access::mode::read>(h);
        auto out = buf_out.get_access<sycl::access::mode::write>(h);
        
        h.single_task<class DotProduct>([=]() {
            int32_t sum = 0;
            for (int i = 0; i < 64; i++) {
                sum += a[i] * b[i];
            }
            out[0] = sum;
        });
    });
    q.wait();
    return 0;
}
```

---

### Intermediate Interview Questions

**Q4. What is the DATAFLOW pragma and what are the architectural requirements for using it correctly?**

Answer:

`#pragma HLS DATAFLOW` enables task-level pipelining (also called function-level pipelining) in
Vitis HLS. It transforms a sequence of functions or loops into a concurrent pipeline where each
stage operates on different data simultaneously, similar to an assembly line.

**Architectural requirements:**

1. **Single-producer, single-consumer channels**: Data must flow in a directed acyclic graph
   (DAG) pattern. Each intermediate variable or array must be written by exactly one producer
   function and read by exactly one consumer function. Feedback (a downstream function writing
   to an upstream function's input) is not supported.

2. **Channel implementation**: Intermediate data between DATAFLOW tasks is implemented as
   FIFOs or ping-pong buffers (double buffers):
   - Use `hls::stream<T>` for FIFO channels (preferred for streaming data).
   - Use arrays for ping-pong buffers (automatically inferred when the access pattern allows).
   - The FIFO depth must be sufficient to absorb rate differences between producer and consumer.

3. **Consistent iteration count**: Each task in a DATAFLOW region should process the same number
   of data items per invocation to ensure the pipeline drains correctly. Mixed-length pipelines
   cause stalls.

4. **Bypass prohibition**: A variable must not be read by a task that comes after the task that
   consumes it in the pipeline (no "skipping" tasks in the chain).

**What happens in the generated RTL:**

Each DATAFLOW task becomes an RTL module. The top-level module instantiates all tasks and
connects them via FIFO primitives (typically implemented as BRAM or registers). A simple
handshake protocol (valid/ready or start/done) coordinates the tasks. The result is a deeply
pipelined structure where:
- Task latency = sum of individual task latencies (first result is slow to emerge)
- Throughput = determined by the slowest stage (the bottleneck task)

```cpp
// Correct DATAFLOW use: streaming FIR pipeline
void fir_pipeline(hls::stream<data_t>& in,
                  hls::stream<data_t>& out,
                  coeff_t coeff[N_TAPS]) {
    #pragma HLS DATAFLOW
    
    hls::stream<data_t> s_delay, s_mac;
    #pragma HLS STREAM variable=s_delay depth=N_TAPS
    #pragma HLS STREAM variable=s_mac   depth=4
    
    sample_delay(in,      s_delay, N_TAPS);  // Shift register delay line
    mac_tree    (s_delay, s_mac,   coeff);    // Multiply-accumulate tree
    output_reg  (s_mac,   out);               // Optional output register stage
}
```

**Common DATAFLOW mistakes:**

- Using regular arrays (not `hls::stream`) for channels: FIFO inference fails and the tool
  falls back to ping-pong buffers, which doubles memory usage and can cause deadlocks if the
  buffer depth is insufficient.
- Producer and consumer functions in separate compilation units (DATAFLOW requires them in the
  same function scope).
- Reading an intermediate result multiple times (fans out from one producer to two consumers),
  which violates the single-consumer rule.

---

**Q5. Compare Vitis HLS interface synthesis modes. When would you choose AXI4-Lite vs AXI4-Stream for a kernel?**

Answer:

Vitis HLS can synthesise several interface types from C++ function argument declarations and
pragmas. The choice determines how the RTL module connects to the rest of the system.

**AXI4-Lite (`s_axilite`):**

A memory-mapped register interface for scalar control signals and configuration. The host
(CPU or another AXI master) reads/writes specific addresses to pass scalar arguments and
check status.

```cpp
void kernel(int32_t scalar_arg, int32_t* array_ptr, int N) {
    #pragma HLS INTERFACE s_axilite port=scalar_arg  bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=N           bundle=CTRL
    #pragma HLS INTERFACE s_axilite port=return      bundle=CTRL
    #pragma HLS INTERFACE m_axi     port=array_ptr   bundle=GMEM
    // ...
}
```

AXI4-Lite is appropriate for:
- Scalars: Loop counts, thresholds, configuration parameters.
- Kernel start/done handshake (the `return` port).
- Status registers read by software.

AXI4-Lite is NOT appropriate for streaming data because it is a request-response bus with
high overhead per transaction.

**AXI4-Stream (`axis`):**

A streaming interface with `valid`/`ready`/`data`/`last`/`keep` signals. No addresses.
Data flows continuously as long as both sides are ready.

```cpp
void stream_kernel(hls::stream<ap_axiu<32,0,0,0>>& in_stream,
                   hls::stream<ap_axiu<32,0,0,0>>& out_stream) {
    #pragma HLS INTERFACE axis port=in_stream
    #pragma HLS INTERFACE axis port=out_stream
    #pragma HLS INTERFACE s_axilite port=return bundle=CTRL
    
    // Process streaming data
    while (!in_stream.empty()) {
        auto word = in_stream.read();
        // ... transform word ...
        out_stream.write(processed_word);
    }
}
```

AXI4-Stream is appropriate for:
- Video pixel streams.
- Network packet data.
- DSP sample streams (ADC data, IQ samples).
- Any data that arrives continuously without address.

**AXI4 Master (`m_axi`):**

For accessing external memory (DDR4 on Alveo, PS DDR in Zynq). The HLS tool generates burst
access logic automatically from pointer-based memory accesses in C++.

```cpp
void dma_kernel(int32_t* src, int32_t* dst, int size) {
    #pragma HLS INTERFACE m_axi port=src depth=1024 bundle=GMEM0
    #pragma HLS INTERFACE m_axi port=dst depth=1024 bundle=GMEM0
    
    memcpy(dst, src, size * sizeof(int32_t));  // HLS synthesises AXI burst read+write
}
```

**Selection guideline for an interview:**

| Scenario                         | Interface Choice              |
|----------------------------------|-------------------------------|
| Pass a threshold value to kernel | `s_axilite`                   |
| Stream pixels from image sensor  | `axis`                        |
| Access DDR4 frame buffer         | `m_axi`                       |
| Start/stop kernel from CPU       | `s_axilite` on `return` port  |
| High-throughput matrix multiply  | `m_axi` (burst) + `s_axilite` |
| Real-time audio processing       | `axis` in + `axis` out        |

---

**Q6. What is Intel HLS Compiler and how does it differ from Vitis HLS in its approach to memory interfaces and loop analysis?**

Answer:

Intel HLS Compiler (part of the Intel oneAPI HPC Toolkit, also available as `i++`) compiles
annotated C++ to Verilog for Quartus. It shares goals with Vitis HLS but has some architectural
and philosophical differences.

**Memory interface approach:**

Vitis HLS: The default is to map arrays to BRAM. Memory partitioning requires explicit `ARRAY_PARTITION`
pragmas. External memory access requires `m_axi` interface pragma.

Intel HLS: Supports `ihc::mm_host` (memory-mapped host interface) and `ihc::stream` (streaming).
For local memory, Intel HLS automatically analyses access patterns and selects stall-free
(no arbitration needed) or arbitrated (time-multiplexed) memory topologies. The memory
subsystem is more automatically optimised in Intel HLS without requiring explicit partitioning
pragmas in many cases.

**Loop analysis differences:**

Intel HLS has stronger automatic loop analysis for:
- **Loop-carried dependency detection**: Intel HLS's loop analyser detects true dependencies
  vs false dependencies (where the C++ code appears to have a dependency but the compiler can
  prove it does not). This leads to better automatic II=1 achievement without pragmas.
- **Loop coalescing**: Adjacent nested loops with the same trip count are automatically coalesced
  into a single loop for better pipeline utilisation.
- **Speculative execution**: Intel HLS can speculatively execute loop iterations past conditional
  branches in some cases, which Vitis HLS does not do.

**Pragma syntax comparison:**

```cpp
// Vitis HLS (Xilinx/AMD)
#pragma HLS PIPELINE II=1
#pragma HLS UNROLL factor=4
#pragma HLS ARRAY_PARTITION variable=buf cyclic factor=4

// Intel HLS Compiler
#pragma ii 1                      // Equivalent to PIPELINE II=1
#pragma unroll 4                  // Equivalent to UNROLL factor=4
// Memory partitioning: use ihc::local_mem or explicit bank configuration
```

**SYCL vs Vitis HLS programming model:**

A key difference is the programming model for the larger platform:

- Vitis HLS is used standalone or through Vitis platform (OpenCL-heritage XRT API).
- Intel HLS is used standalone or through SYCL/oneAPI. SYCL `single_task` kernels are compiled
  by the FPGA backend of the DPC++ compiler, which uses Intel HLS under the hood.

The SYCL model is more portable: the same SYCL code (with device-specific attributes for FPGA)
can in principle target Intel FPGA, Intel GPU, or Intel CPU. Vitis HLS is Xilinx/AMD-specific.

**When Intel HLS has an advantage:**

- Designs targeting Agilex that benefit from Hyperflex: Intel HLS-generated RTL is aware of
  hyper-register opportunities and generates RTL that the Quartus fitter can pipeline more
  aggressively than manually written HLS output from Vitis.
- Floating-point heavy designs: Agilex's DSP block supports native FP32, and Intel HLS
  generates RTL that targets these blocks efficiently.

---

## Tier 3 — Advanced

### Advanced Interview Questions

**Q7. A Vitis HLS kernel processes a stream of 1024-sample blocks with a 16-tap FIR filter. Walk through how you would structure the HLS code to achieve II=1 at 300 MHz, and what the resource implications are.**

Answer:

This question tests the ability to combine multiple HLS techniques into a coherent design.

**The problem:**
- Input: stream of 16-bit samples, block size = 1024 samples
- Operation: 16-tap FIR filter (16 multiply-accumulate operations per output sample)
- Target: II=1 at 300 MHz (one output sample per clock)

**Approach:**

A 16-tap FIR filter at II=1 requires all 16 multiply-accumulate operations to complete within
one clock cycle, which means running them in parallel:

```cpp
#include <hls_stream.h>
#include <ap_int.h>
#include <ap_fixed.h>

// Use fixed-point arithmetic: 16.0 bit input, 16.16 bit coefficient
typedef ap_fixed<16, 16>  sample_t;    // 16-bit signed input sample
typedef ap_fixed<16, 0>   coeff_t;     // Coefficient in [-1, 1)
typedef ap_fixed<32, 16>  accum_t;     // Accumulator: 32-bit to avoid overflow

#define N_TAPS 16

void fir_filter(
    hls::stream<sample_t>& in_stream,
    hls::stream<sample_t>& out_stream,
    const coeff_t coeff[N_TAPS],
    int n_samples
) {
    // Partition coeff to allow all 16 reads in one cycle
    #pragma HLS ARRAY_PARTITION variable=coeff complete dim=1
    
    // Shift register delay line (N_TAPS-1 samples deep)
    sample_t delay_line[N_TAPS];
    #pragma HLS ARRAY_PARTITION variable=delay_line complete dim=1
    
    // Initialise delay line
    for (int i = 0; i < N_TAPS; i++) {
        #pragma HLS UNROLL
        delay_line[i] = 0;
    }
    
    // Main processing loop
    sample_loop: for (int n = 0; n < n_samples; n++) {
        #pragma HLS PIPELINE II=1
        
        // Read new sample
        sample_t new_sample = in_stream.read();
        
        // Shift delay line: delay_line[0] is newest, delay_line[N_TAPS-1] is oldest
        shift_loop: for (int i = N_TAPS - 1; i > 0; i--) {
            #pragma HLS UNROLL
            delay_line[i] = delay_line[i-1];
        }
        delay_line[0] = new_sample;
        
        // Compute FIR output: sum of (delay_line[i] * coeff[i])
        accum_t acc = 0;
        mac_loop: for (int i = 0; i < N_TAPS; i++) {
            #pragma HLS UNROLL  // All 16 MACs in parallel
            acc += delay_line[i] * coeff[i];
        }
        
        // Write output (cast back to sample_t -- truncates fractional bits)
        out_stream.write(acc);
    }
}
```

**Why this achieves II=1:**

1. `ARRAY_PARTITION complete` on both `coeff` and `delay_line` creates 16 individual registers
   for each, so all 16 reads happen in the same clock cycle.

2. `UNROLL` on `mac_loop` instantiates 16 multipliers operating in parallel. The results are
   summed in an adder tree (log2(16) = 4 levels of adders).

3. The adder tree depth is ~4 levels of 32-bit additions. At 300 MHz (3.33 ns budget), this
   fits comfortably in UltraScale+ (a 32-bit adder takes ~0.5--0.8 ns).

4. The shift operation is also unrolled: 15 register moves happen simultaneously.

5. There is no loop-carried dependency on the critical path (the accumulator `acc` is local
   to each iteration, not carried over).

**Resource implications:**

- **DSP48E2 usage**: 16 multipliers. Each `sample_t * coeff_t` is a 16×16 multiplication
  fitting in one DSP48E2. Total: 16 DSP48E2.
- **Adder tree**: A 16-input 32-bit adder tree. Vitis HLS can implement this in DSPs (using
  the accumulator path) or LUTs. With DSPs: ~4--8 additional DSPs for the adder tree.
- **Delay line registers**: 16 × 16-bit = 256 flip-flops (fits in ~16 slices).
- **BRAM**: None (coefficients and delay line are fully in registers due to ARRAY_PARTITION complete).

If N_TAPS were 256 instead of 16, `complete` partition would create 256 registers per array
and 256 DSP instantiations -- probably too many. For large tap counts, a partial-unroll with
`factor=8` and II=32 might be more area-efficient.

---

**Q8. What is the Vitis HLS cosimulation flow, and what are its limitations compared to RTL-level simulation?**

Answer:

HLS cosimulation (also called RTL co-simulation) is a verification step in the Vitis HLS flow
that automatically wraps the generated RTL in a testbench driver and runs an RTL simulation,
comparing outputs against the C++ simulation reference.

**Flow:**

```
C++ Testbench (tb_fir.cpp)
         |
    C/C++ Simulation  ──── Golden reference outputs
         |
    HLS Synthesis (RTL generation)
         |
    Cosimulation
      - Vitis HLS wraps generated Verilog in a SystemC/Verilog testbench
      - Drives RTL ports from C++ testbench stimulus via an AXI/FIFO BFM
      - Captures RTL outputs and compares against C++ golden reference
         |
    Pass/Fail + timing analysis (latency, II verification)
```

```tcl
# In Vivado HLS Tcl flow:
open_project fir_project
set_top fir_filter
add_files fir_filter.cpp
add_files -tb tb_fir.cpp
open_solution "solution1"
set_part {xczu9eg-ffvb1156-2-e}
create_clock -period 3.33 -name default   ;# 300 MHz
csynth_design
cosim_design -rtl verilog -tool xsim      ;# Run cosimulation with Vivado Simulator
```

**What cosimulation validates:**
- Functional correctness: Output bit patterns match C++ simulation.
- Measured initiation interval: How many cycles actually elapse between consecutive inputs.
- Measured latency: Cycles from first input to first output.
- AXI interface protocol compliance (basic): AXI handshake is correctly generated.

**Limitations of HLS cosimulation:**

1. **Testbench-driven, not streaming**: The cosimulation testbench is driven by the C++ test
   function. It does not model a real AXI interconnect with backpressure, burst transactions,
   or concurrent kernel invocations. A real integration test in Vivado with a full AXI verification
   environment is needed to validate AXI compliance.

2. **Single-thread execution model**: HLS cosimulation runs one kernel invocation at a time
   (no concurrent operation of multiple kernels or DMA + kernel simultaneously).

3. **No power/timing accuracy**: Cosimulation tells you the cycle count, not the actual clock
   frequency achieved. The tool's own timing estimate is a post-synthesis approximation; real
   timing is only known after Vivado place and route.

4. **FIFO depth sensitivity**: If DATAFLOW FIFOs are too shallow, cosimulation will deadlock.
   The FIFO depths must be tuned -- a correct C++ simulation does not guarantee correct cosimulation
   without proper FIFO sizing.

5. **No coverage**: HLS cosimulation does not generate code coverage or toggle coverage for the
   generated RTL. Formal or directed RTL simulation is needed for coverage-driven verification.

6. **Floating-point precision differences**: C++ `float` and HLS `float` arithmetic may differ
   by the last bit due to rounding mode differences between x86 FPU and the synthesised IEEE 754
   implementation. `ap_fixed` types usually produce exact matches.

**Best practice:** Use HLS cosimulation as a quick sanity check after synthesis. Do full
integration testing in Vivado simulation using the exported IP core with a complete AXI
verification IP environment before taping out.

---

**Q9. Describe how Vitis HLS handles loop-carried dependencies in floating-point accumulators, and what techniques can achieve II=1 for such patterns.**

Answer:

This is one of the most common and difficult HLS problems in practice, because it appears in
nearly every DSP algorithm (FIR filters, FFTs, neural network layer outputs).

**The problem:**

```cpp
float sum = 0.0f;
for (int i = 0; i < N; i++) {
    #pragma HLS PIPELINE II=1   // WARNING: Will NOT achieve II=1
    sum += data[i];              // Loop-carried dependency through 'sum'
}
```

IEEE 754 single-precision floating-point addition has a latency of 5--7 clock cycles in FPGA
implementations (it cannot be pipelined to II=1 trivially because the result of each add feeds
the next). The loop-carried dependency forces II >= 5--7.

**Technique 1: Tree reduction (if associativity is acceptable)**

If the application can tolerate associativity reordering (numerically, floating-point addition
is not strictly associative, so results will differ slightly):

```cpp
// Partial sums in registers, then combine
float partial[8];
#pragma HLS ARRAY_PARTITION variable=partial complete

// Initialise
for (int j = 0; j < 8; j++) partial[j] = 0.0f;

// Accumulate into 8 independent partial sums (II=1 achievable -- no dependency within each lane)
for (int i = 0; i < N; i++) {
    #pragma HLS PIPELINE II=1
    partial[i % 8] += data[i];  // Each partial[j] has independent dependency chain
}

// Final tree reduction (small, fixed cost, done post-loop)
float sum = 0.0f;
for (int j = 0; j < 8; j++) {
    #pragma HLS UNROLL
    sum += partial[j];
}
```

With 8 independent partial sums, the loop-carried dependency on each `partial[j]` is 8 cycles
apart (iteration `i` and iteration `i+8` both touch `partial[i%8]`). If the float adder latency
is <= 8, the tool can achieve II=1 by scheduling each `partial[j]` update independently.

**Technique 2: Use `ap_fixed` instead of `float`**

If the application can tolerate fixed-point arithmetic:
```cpp
typedef ap_fixed<32, 8> acc_t;  // 32-bit fixed-point
acc_t sum = 0;
for (int i = 0; i < N; i++) {
    #pragma HLS PIPELINE II=1
    sum += data[i];  // Fixed-point add: 1-cycle latency -- II=1 achievable
}
```

Fixed-point adders in FPGA fabric have 1-cycle latency (or sometimes 2 cycles for very wide
adders with pipeline registers). The loop-carried dependency is resolved in one cycle, so II=1
is achievable.

**Technique 3: `DEPENDENCE` pragma (use with caution)**

```cpp
for (int i = 0; i < N; i++) {
    #pragma HLS PIPELINE II=1
    #pragma HLS DEPENDENCE variable=sum inter false  // Assert no inter-iteration dependence
    sum += data[i];  // DANGEROUS: this IS a dependency -- using pragma incorrectly produces wrong results
}
```

The `DEPENDENCE false` pragma tells the tool to ignore the dependency. This is only valid if
the programmer can prove (outside the tool) that the dependency does not exist. For a real
floating-point accumulator, this pragma produces incorrect hardware that overwrites `sum` before
the previous addition completes. Do not use this pragma to "fix" II violations unless you have
mathematically proven the dependency is false.

**Technique 4: Restructure as DSP cascade (RTL insertion)**

For designs where II=1 at high frequency is non-negotiable, the floating-point accumulator is
often best implemented as a custom RTL module and instantiated as an HLS black-box:

```cpp
// Declare RTL black-box in HLS
void fp_accum_rtl(
    hls::stream<float>& in,
    hls::stream<float>& out,
    int N
);
#pragma HLS BIND_OP variable=fp_accum_rtl latency=1  // Tell HLS to treat as 1-cycle

// Use the black-box in the HLS design
fp_accum_rtl(sample_stream, result_stream, N);
```

The RTL module uses a pipelined floating-point adder with output feedback through a register
that compensates for the pipeline depth, a common pattern in DSP FPGA design.

This question has no single right answer -- the interviewer is looking for awareness that
the problem exists, multiple solution strategies, and understanding of the tradeoffs (numerical
accuracy vs II vs resource cost).
