# FPGA Design Interview Preparation

[![FPGA](https://img.shields.io/badge/Subject-FPGA%20Design-blue)](https://en.wikipedia.org/wiki/Field-programmable_gate_array)

Comprehensive interview preparation material covering FPGA architecture, synthesis, timing closure, Vivado/Quartus toolchains, and implementation best practices. This repository provides structured study material for hardware engineers preparing for FPGA design interviews at leading companies.

## Table of Contents

- [01 FPGA Architecture](#01-fpga-architecture)
- [02 Synthesis and Implementation](#02-synthesis-and-implementation)
- [03 Design Techniques](#03-design-techniques)
- [04 Debug and Bringup](#04-debug-and-bringup)
- [05 Xilinx vs Intel](#05-xilinx-vs-intel)
- [06 Quizzes](#06-quizzes)
- [How to Use](#how-to-use)
- [Contributing](#contributing)
- [Related Repositories](#related-repositories)
- [License](#license)

## 01 FPGA Architecture

Foundational knowledge of FPGA hardware architecture including configurable logic blocks, memory resources, and specialised processing elements.

- [LUT and CLB Architecture](./01_fpga_architecture/lut_and_clb_architecture.md)
- [Block RAM and Distributed RAM](./01_fpga_architecture/block_ram_and_distributed_ram.md)
- [DSP Slices](./01_fpga_architecture/dsp_slices.md)
- [Clock Resources and PLLs](./01_fpga_architecture/clock_resources_and_plls.md)
- [I/O Standards and SerDes](./01_fpga_architecture/io_standards_and_serdes.md)
- [Worked Problems](./01_fpga_architecture/worked_problems/)
  - [Problem 01: Resource Estimation](./01_fpga_architecture/worked_problems/problem_01_resource_estimation.md)
  - [Problem 02: BRAM vs Distributed](./01_fpga_architecture/worked_problems/problem_02_bram_vs_distributed.md)
  - [Problem 03: Clock Planning](./01_fpga_architecture/worked_problems/problem_03_clock_planning.md)

## 02 Synthesis and Implementation

Detailed exploration of the design flow including synthesis optimisation, place and route, timing constraints, and timing closure methodologies.

- [Synthesis Optimisation](./02_synthesis_and_implementation/synthesis_optimisation.md)
- [Place and Route](./02_synthesis_and_implementation/place_and_route.md)
- [Timing Constraints: SDC/XDC](./02_synthesis_and_implementation/timing_constraints_sdc_xdc.md)
- [Timing Closure Strategies](./02_synthesis_and_implementation/timing_closure_strategies.md)
- [Utilisation and Floorplanning](./02_synthesis_and_implementation/utilisation_and_floorplanning.md)
- [Worked Problems](./02_synthesis_and_implementation/worked_problems/)
  - [Problem 01: Timing Failure Debug](./02_synthesis_and_implementation/worked_problems/problem_01_timing_failure_debug.md)
  - [Problem 02: Constraint Writing](./02_synthesis_and_implementation/worked_problems/problem_02_constraint_writing.md)
  - [Problem 03: Utilisation Optimisation](./02_synthesis_and_implementation/worked_problems/problem_03_utilisation_optimisation.md)

## 03 Design Techniques

Core design patterns and methodologies for robust FPGA implementations including CDC, reset strategies, and resource optimisation.

- [Clock Domain Crossing (FPGA)](./03_design_techniques/clock_domain_crossing_fpga.md)
- [Reset Strategies](./03_design_techniques/reset_strategies.md)
- [Pipelining and Retiming](./03_design_techniques/pipelining_and_retiming.md)
- [Resource Sharing](./03_design_techniques/resource_sharing.md)
- [IP Core Integration](./03_design_techniques/ip_core_integration.md)
- [Coding Challenges](./03_design_techniques/coding_challenges/)
  - [Challenge 01: CDC Handshake](./03_design_techniques/coding_challenges/challenge_01_cdc_handshake.sv)
  - [Challenge 02: Gray Code Counter](./03_design_techniques/coding_challenges/challenge_02_gray_code_counter.sv)
  - [Challenge 03: Asynchronous FIFO](./03_design_techniques/coding_challenges/challenge_03_async_fifo.sv)

## 04 Debug and Bringup

Practical debugging and hardware verification techniques including ILA, VIO, JTAG, and board bringup methodologies.

- [ILA and VIO](./04_debug_and_bringup/ila_and_vio.md)
- [JTAG and Boundary Scan](./04_debug_and_bringup/jtag_and_boundary_scan.md)
- [Bitstream Configuration](./04_debug_and_bringup/bitstream_configuration.md)
- [Board Bringup Methodology](./04_debug_and_bringup/board_bringup_methodology.md)
- [Worked Problems](./04_debug_and_bringup/worked_problems/)
  - [Problem 01: Debug Scenario](./04_debug_and_bringup/worked_problems/problem_01_debug_scenario.md)
  - [Problem 02: Bringup Checklist](./04_debug_and_bringup/worked_problems/problem_02_bringup_checklist.md)
  - [Problem 03: ILA Trigger Design](./04_debug_and_bringup/worked_problems/problem_03_ila_trigger_design.md)

## 05 Xilinx vs Intel

Comparative analysis of major FPGA platforms including tool-specific workflows and architectural differences.

- [Vivado vs Quartus](./05_xilinx_vs_intel/vivado_vs_quartus.md)
- [Ultrascale vs Agilex](./05_xilinx_vs_intel/ultrascale_vs_agilex.md)
- [HLS and Vitis](./05_xilinx_vs_intel/hls_and_vitis.md)
- [Zynq and SoC FPGAs](./05_xilinx_vs_intel/zynq_and_soc_fpgas.md)

## 06 Quizzes

Self-assessment quizzes to test understanding across key areas.

- [Quiz: Architecture](./06_quizzes/quiz_architecture.md)
- [Quiz: Timing](./06_quizzes/quiz_timing.md)
- [Quiz: Design Techniques](./06_quizzes/quiz_design_techniques.md)
- [Quiz: Debug](./06_quizzes/quiz_debug.md)

## How to Use

This repository is structured as a progressive learning path for FPGA design interview preparation:

1. **Start with Fundamentals**: Begin with [01 FPGA Architecture](./01_fpga_architecture/) to build a solid understanding of hardware resources and constraints.

2. **Study the Design Flow**: Progress to [02 Synthesis and Implementation](./02_synthesis_and_implementation/) to understand how designs are mapped to silicon, with emphasis on timing and resource constraints.

3. **Learn Design Patterns**: Study [03 Design Techniques](./03_design_techniques/) and complete the coding challenges to develop practical expertise in robust design implementation.

4. **Master Debugging**: Work through [04 Debug and Bringup](./04_debug_and_bringup/) to understand real-world verification and production methodologies.

5. **Compare Toolchains**: Review [05 Xilinx vs Intel](./05_xilinx_vs_intel/) to understand platform-specific differences and tool workflows.

6. **Test Your Knowledge**: Use the [06 Quizzes](./06_quizzes/) to self-assess and identify gaps.

For each major topic section:
- Read the core concept documents
- Work through the provided problems or challenges
- Refer back to earlier sections as needed for foundational concepts
- Use quizzes to identify weak areas and reinforce learning

## Contributing

Contributions are welcome. To contribute:

1. Review the existing material for formatting and style
2. Ensure content is technically accurate and appropriate for interview preparation
3. Add clear examples and explanations
4. Include references to official documentation where applicable
5. Update the README with links to any new sections or resources
6. Submit a pull request with a clear description of changes

## Related Repositories

- [Interview_VHDL](https://github.com/BrendanJamesLynskey/Interview_VHDL) — VHDL design interview preparation
- [Interview_Verilog](https://github.com/BrendanJamesLynskey/Interview_Verilog) — Verilog design interview preparation
- [Interview_SystemVerilog](https://github.com/BrendanJamesLynskey/Interview_SystemVerilog) — SystemVerilog verification interview preparation
- [Interview_Digital_Hardware_Design](https://github.com/BrendanJamesLynskey/Interview_Digital_Hardware_Design) — General digital design principles

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
