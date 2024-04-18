
# Introduction

CoreMark's primary goals are simplicity and providing a method for testing only a processor's core features. For more information about EEMBC's comprehensive embedded benchmark suites, please see www.eembc.org.

For a more compute-intensive version of CoreMark that uses larger datasets and execution loops taken from common applications, please check out EEMBC's [CoreMark-PRO](https://www.github.com/eembc/coremark-pro) benchmark, also on GitHub.

This project folder is a port of CoreMark (from the official [GitHub repository](https://github.com/eembc/coremark)) for the CELLRV32 processor.

# Building

To build the executable (`cellrv32_exe.bin`) of the benchmark, type:

`> make USER_FLAGS+=-DRUN_COREMARK clean_all exe`

Make sure to define `RUN_COREMARK` *when invoking* `make` (via `USER_FLAGS+=-DRUN_COREMARK`).

To build the executable for a certain CPU configuration and a certain optimization level of the benchmark, type (`rv32imc` and `O3` in this example):

`> make USER_FLAGS+=-DRUN_COREMARK MARCH=rv32imc EFFORT=-Ofast clean_all exe`


# Running

Upload the generated executable `cellrv32_exe.bin` via the bootloader ('u' command) and execute it ('e' command):

```
<< CELLRV32 Bootloader >>

BLDV: Aug 26 2022
HWV:  0x01070605
CID:  0x00000000
CLK:  0x05f5e100
ISA:  0x40901104 + 0xc000068b
SOC:  0xff7f400f
IMEM: 0x00008000 bytes @0x00000000
DMEM: 0x00002000 bytes @0x80000000

Autoboot in 8s. Press any key to abort.
Aborted.

Available CMDs:
 h: Help
 r: Restart
 u: Upload
 s: Store to flash
 l: Load from flash
 x: Boot from flash (XIP)
 e: Execute
CMD:> u
Awaiting cellrv32_exe.bin... OK
CMD:> e
Booting from 0x00000000...

CELLRV32: Processor running at 100000000 Hz
CELLRV32: Executing coremark (2000 iterations). This may take some time...

2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 2140481 k
Total time (secs): 21
Iterations/Sec   : 95
Iterations       : 2000
Compiler version : GCC12.1.0
Compiler flags   : -> default, see makefile
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0x4983
Correct operation validated. See README.md for run and reporting rules.

CELLRV32: All reported numbers only show the integer part.

CELLRV32: HPM results (low words only)
no HPMs available

CELLRV32: Executed instructions:       0x0000000023472cce
CELLRV32: CoreMark core clock cycles:  0x000000007f95277d
CELLRV32: Average CPI (integer  only): 3 cycles/instruction
```
