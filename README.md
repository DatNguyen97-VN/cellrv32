[![CELLRV32](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/figures/cellrv32%20logo.png)](https://github.com/DatNguyen97-VN/cellrv32/tree/main)

# The CELLRV32 RISC-V Processor
`Note: this project is referred from [The NEORV32 Processor](https://github.com/stnolting/cellrv32.git) by Stephan Nolting.`

1. [Overview](#1-Overview)
   * [Key Features](#Key-Features)
   * [Project Status](#Project-Status)
2. [Features](#2-Features)
3. [FPGA Implementation Results](#3-FPGA-Implementation-Results)
4. [Performance](#4-Performance)
5. [Software Framework & Tooling](#5-Software-Framework-and-Tooling)
6. [Getting Started](#6-Getting-Started)

## 1. Overview
![cellrv32 overview](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/figures/cellrv32%20top.png)


The CELLRV32 Processor is a **customizable microcontroller-like system on chip (SoC)** built around the CELRV32
[RISC-V](https://riscv.org/) CPU and written in **platform-independent SystemVerilog**. The processor is intended as know about specific arrangement of registers, ALUs, finite state machines (FSMs), memories, and other logic building blocks needed to implement an RISC-V and building block from theoretical to combinational and sequential circuits for the internal IP. The project is intended to work _out of the box_ and targets
FPGA / RISC-V beginners.

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

|         | Repository | CI Status |
|:--------|:-----------|:----------|
| GitHub Pages (docs)          | [cellrv32](https://github.com/DatNguyen97-VN/cellrv32/tree/main)                       | [![GitHub Pages](https://img.shields.io/badge/up-00FF00?style=plastic&logo=github&label=NEORV32.pdf)](https://github.com/DatNguyen97-VN/cellrv32/blob/main/doc/datasheet/NEORV32.pdf) |
| Processor (SoC) verification | [cellrv32](https://github.com/DatNguyen97-VN/cellrv32/tree/main)                       | [![Processor](https://img.shields.io/badge/Not%20Start-FF0000?style=plastic&logo=adminer&label=Processor%20Check)](https://github.com/DatNguyen97-VN/cellrv32/tree/main)|
| FPGA implementations         | [cellrv32-setups](https://github.com/DatNguyen97-VN/cellrv32/tree/main/board/de2-115)         | [![Implementation](https://img.shields.io/badge/up-00FF00?style=plastic&logo=actix&label=Implementation)](https://github.com/DatNguyen97-VN/cellrv32/tree/main) |
| Prebuilt GCC toolchains      | [riscv-gcc-prebuilt](https://github.com/stnolting/riscv-gcc-prebuilt) | [![Prebuilt_Toolchains](https://img.shields.io/github/actions/workflow/status/stnolting/riscv-gcc-prebuilt/main.yml?branch=main&longCache=true&style=flat-square&label=Prebuilt%20Toolchains&logo=Github%20Actions&logoColor=fff)](https://github.com/stnolting/riscv-gcc-prebuilt/actions/workflows/main.yml) |