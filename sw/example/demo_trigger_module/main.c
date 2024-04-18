// #################################################################################################
// # << CELLRV32 - RISC-V Trigger Module Example >>                                                #
// #################################################################################################

/**********************************************************************//**
 * @file demo_trigger_module/main.c
 * @author Stephan Nolting
 * @brief Using the RISC-V trigger module from machine-mode.
 **************************************************************************/
#include <cellrv32.h>
#include <string.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/

// Prototypes
void dummy_function(void);


/**********************************************************************//**
 * Example program to show how to cause an exception when reaching a specific
 * instruction address using the RISC-V trigger module.
 *
 * @note This program requires the 'Sdtrig' ISA extension.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // intro
  cellrv32_uart0_printf("\n<< RISC-V Trigger Module Example >>\n\n");

  // check if trigger module unit is implemented at all
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_SDTRIG)) == 0) {
    cellrv32_uart0_printf("Trigger module ('Sdtrig' ISA extension) not implemented!");
    return -1;
  }

  // info
  cellrv32_uart0_printf("This program show how to use the trigger module to raise an EBREAK exception\n"
                       "when the instruction at a specific address gets executed.\n\n");

  // configure trigger module
  uint32_t trig_addr = (uint32_t)(&dummy_function);
  cellrv32_cpu_csr_write(CSR_TDATA2, trig_addr); // trigger address
  cellrv32_uart0_printf("Trigger address set to 0x%x.\n", trig_addr);

  cellrv32_cpu_csr_write(CSR_TDATA1, (1 <<  2) | // exe = 1: enable trigger module operation
                                    (0 << 12) | // action = 0: raise ebereak exception but do not enter debug-mode
                                    (0 << 27)); // dnode = 0: no exclusive access to trigger module from debug-mode

  cellrv32_uart0_printf("Calling dummy function... (this will cause the EBREAK exception)\n");
  // call function - this will cause the trigger module to fire, which will result in an EBREAK
  // exception that is captured by the RTE's debug handler
  dummy_function();

  cellrv32_uart0_printf("\nProgram completed.\n");
  return 0;
}


/**********************************************************************//**
 * Just a simple dummy function that will fire the trigger module.
 * @note Make sure this is not inlined.
 **************************************************************************/
void __attribute__ ((noinline)) dummy_function(void) {

  cellrv32_uart0_printf("Hello from the dummy function!\n");
}
