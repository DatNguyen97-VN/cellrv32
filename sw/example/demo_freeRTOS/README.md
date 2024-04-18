  # FreeRTOS Demo for the CELLRV32 Processor

This example shows how to run [FreeRTOS](https://www.freertos.org/) on the CELLRV32 processor. It features the default
"blinky_demo" and the more sophisticated "full_demo" demo applications. See the comments in `main.c` and the according
source files for more information.

The chip-specific extensions folder (`chip_specific_extensions/cellrv32`) should be in `$(FREERTOS_HOME)/Source/portable/GCC/RISC-V/chip_specific_extensions`,
but is placed in this source directory for simplicity.

**:information_source: Tested with FreeRTOS version V10.4.4+**


## Requirements

* Hardware
  * DMEM/IMEM requirements depend on the actual application (for example: 16kB DMEM and 16kB IMEM for "blinky_demo")
  * peripherals: MTIME (machine timer), UART0, GPIO
  * CPU ISA extensions: `Zicsr`

* Software
  * CELLRV32 software framework
  * RISC-V gcc
  * FreeRTOS
  * application-specific configuration of `FreeRTOSConfig.h` (especially `configCPU_CLOCK_HZ`)
  * application-specific configuration of the CELLRV32 linker script when using non-default IMEM or DMEM configurations (size!) 


## Instructions

Download FreeRTOS from the [official GitHub repository](https://github.com/FreeRTOS/FreeRTOS) or from the its official homepage.

    $ git clone https://github.com/FreeRTOS/FreeRTOS.git

Open the makefile from this example folder and configure the `FREERTOS_HOME` variable to point to your FreeRTOS home folder.

    FREERTOS_HOME ?= /mnt/n/Projects/FreeRTOSv10.4.1

Compile the CELLRV32 executable. Do not forget the `RUN_FREERTOS_DEMO` switch.

    $ make USER_FLAGS+=-DRUN_FREERTOS_DEMO clean_all exe

Note: The *.c sources and the FreeRTOS-specific part of the makefile have (include) guards that test if `RUN_FREERTOS_DEMO` is defined.
This has no practical usage for the user - it is just a work-around for the CELLRV32 CI environment.

Upload the executable (`cellrv32_exe.bin`) to the processor via the bootloader and execute it.

```
CMD:> u
Awaiting cellrv32_exe.bin... OK
CMD:> e
Booting...

FreeRTOS V10.4.4+ on CELLRV32 Demo

Blink
Blink
Blink
Blink
```

## FreeRTOS Plus

To automatically add source and include files from FreeRTOS plus extensions add one (or more) of the following arguments when invoking `make`:

* FreeRTOS-Plus-CLI: `USER_FLAGS+=-FREERTOS_PLUS_CLI`
* FreeRTOS-Plus-TCP: `USER_FLAGS+=-FREERTOS_PLUS_TCP`

Example:

    $ make USER_FLAGS+=-DRUN_FREERTOS_DEMO USER_FLAGS+=-FREERTOS_PLUS_TCP clean_all exe


## CELLRV32-Specific Interrupts and Exceptions

The `main.c` file provides two "trampolines" for CELLRV32-specific interrupts/exceptions:

```c
/* Handle CELLRV32-specific interrupts */
void freertos_risc_v_application_interrupt_handler(void) {

  // acknowledge/clear ALL pending interrupt sources
  cellrv32_cpu_csr_write(CSR_MIP, 0);

  // debug output
  cellrv32_uart0_printf("\n<CELLRV32-IRQ> mcause = 0x%x </CELLRV32-IRQ>\n", cellrv32_cpu_csr_read(CSR_MCAUSE));
}

/* Handle CELLRV32-specific exceptions */
void freertos_risc_v_application_exception_handler(void) {

  // debug output
  cellrv32_uart0_printf("\n<CELLRV32-EXC> mcause = 0x%x </CELLRV32-EXC>\n", cellrv32_cpu_csr_read(CSR_MCAUSE));
}
```

This functions can be used to call specific handlers based on the value from the `mcause` CSR, which indicates
the actual cause of the interrupt or exception (for example FIRQ channel or illegal instruction).


## Notes

The onfiguration of the FreeRTOS home folder (via `FREERTOS_HOME`) is corrupted if the compiler shows the following error:

```
main.c:36:10: fatal error: FreeRTOS.h: No such file or directory
   36 | #include <FreeRTOS.h>
      |          ^~~~~~~~~~~~
compilation terminated.
make: *** [makefile:203: main.c.o] Error 1
```

