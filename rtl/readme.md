## Hardware RTL Sources


### [`core`](https://github.com/DatNguyen97-VN/cellrv32/tree/main/rtl/core)

This folder contains the core SystemVerilog and VHDL files for the CELLRV32 CPU and the CELLRV32 Processor.
When creating a new synthesis/simulation project make sure that all `*.sv` and `*.vhd` files from this folder are added to a
*new design library* called `cellrv32`.

:warning: The sub-folder [`core/mem`](https://github.com/DatNguyen97-VN/cellrv32/tree/main/rtl/core/mem)
contains the _platform-agnostic_ VHDL architectures of the processor-internal memories.
You can _replace_ inclusion of these files by platform-optimized memory architectures.