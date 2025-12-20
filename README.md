[![CELLRV32](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/figures/cellrv32%20logo.png)](https://github.com/DatNguyen97-VN/cellrv32/tree/main)

# :construction: CONSTRUCTING :construction:
# The CELLRV32 RISC-V Processor
`Note: this project is referred from [The NEORV32 Processor](https://github.com/stnolting/neorv32.git) by Stephan Nolting.`

1. [Overview](#1-Overview)
   * [Key Features](#Key-Features)
   * [Project Status](#Project-Status)
   * [Progress](#Progress)
2. [Features](#2-Features)
3. [FPGA Implementation Results](#3-FPGA-Implementation-Results)
4. [Performance](#4-Performance)
5. [Software Framework & Tooling](#5-Software-Framework-and-Tooling)
6. [Getting Started](#6-Getting-Started)

## 1. Overview
![cellrv32 overview](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/figures/cellrv32%20top.png)


The CELLRV32 Processor is a **customizable microcontroller-like system on chip (SoC)** built around the CELLRV32
[RISC-V](https://riscv.org/) CPU and written in **platform-independent SystemVerilog**. The processor is intended as know about specific arrangement of registers, ALUs, finite state machines (FSMs), memories, and other logic building blocks (microarchitecture) needed to implement an RISC-V architecture and building blocks from theory of operation to combinational and sequential circuits for the internal IPs. The project is intended to work _out of the box_ and targets
FPGA / RISC-V beginners and amateurs.

Special focus is paid on **execution safety** to provide defined and predictable behavior at any time.
Therefore, the CPU ensures that _all_ memory accesses are properly acknowledged and that _all_ invalid/malformed
instructions are always detected as such. Whenever an unexpected situation occurs the application software is
informed via _precise and resumable_ hardware exceptions.


### Key Features

- [x] all-in-one package: **CPU** + **SoC** + **Software Framework & Tooling**
- [x] extensive configuration options for adapting the processor to the requirements of the application
- [ ] aims to be as small as possible while being as RISC-V-compliant as possible - with a reasonable area-vs-performance trade-off
- [x] FPGA friendly (e.g. _all_ internal memories can be mapped to block RAM - including the CPU's register file)
- [ ] optimized for high clock frequencies to ease integration / timing closure
- [x] from zero to _"hello world!"_ - completely open source and documented
- [x] easy to use even for FPGA / RISC-V starters – intended to _work out of the box_


### Project Status

|         | Repository & Status |
|:--------|:----------|
| GitHub Pages (docs)          | [![GitHub Pages](https://img.shields.io/badge/up-00FF00?style=plastic&logo=github&label=NEORV32.pdf)](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/datasheet/NEORV32.pdf) |
| Processor (SoC) verification | [![Processor](https://img.shields.io/badge/Not%20Start-FF0000?style=plastic&logo=adminer&label=Processor%20Check)](https://github.com/DatNguyen97-VN/cellrv32/tree/main)|
| FPGA implementations         | [![Implementation](https://img.shields.io/badge/passing-00FF00?style=plastic&logo=amazonec2&logoColor=DC7633&label=Implementation)](https://github.com/DatNguyen97-VN/cellrv32/tree/main) |
| Prebuilt GCC toolchains      | [![Prebuilt_Toolchains](https://img.shields.io/badge/passing-00FF00?style=plastic&logo=amazondynamodb&label=Prebuilt%20GCC%20toolchains)](https://github.com/stnolting/riscv-gcc-prebuilt) |
| RISCOF core verification     | [![RISCOF core verification](https://img.shields.io/badge/failing-FF0000?style=plastic&logo=amazoncloudwatch&label=cellrv32-riscof)](https://github.com/DatNguyen97-VN/cellrv32-riscof.git)|

### Progress

- [x] Stage 1: The purpose is to learn how to design a risc-v processor with basic peripherals and the RISC-V instruction set architecture.

- [ ] Stage 2: Designed a custom RISC-V MCU-class with lightweight
snooping-based cache coherence and heterogeneous acceleration: integrating multiple CPU cores, vector extensions, scratchpad memory, DMA engine, an INT16/INT32 NPU, and a lightweight programmable GPU with parallel compute cores.
