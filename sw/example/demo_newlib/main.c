// #################################################################################################
// # << CELLRV32 - Newlib Demo/Test Program >>                                                     #
// #################################################################################################


/**********************************************************************//**
 * @file demo_newlib/main.c
 * @author Stephan Nolting
 * @brief Demo/test program for CELLRV32's newlib C standard library support.
 **************************************************************************/
#include <cellrv32.h>
#include <unistd.h>
#include <stdlib.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/


/**********************************************************************//**
 * @name Max heap size (from linker script's "__cellrv32_heap_size")
 **************************************************************************/
extern const unsigned __crt0_max_heap;


/**********************************************************************//**
 * Main function: Check some of newlib's core functions.
 *
 * @note This program requires UART0.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // setup CELLRV32 runtime environment to keep us safe
  // -> catch all traps and give debug information via UART0
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if UART0 is implemented at all
  if (cellrv32_uart0_available() == 0) {
    cellrv32_uart0_printf("Error! UART0 not synthesized!\n");
    return 1;
  }


  // say hello
  cellrv32_uart0_printf("<<< Newlib demo/test program >>>\n\n");

  // heap size definition
  volatile uint32_t max_heap = (uint32_t)&__crt0_max_heap;
  if (max_heap > 0){
    cellrv32_uart0_printf("MAX heap size: %u bytes\n", max_heap);
  }
  else {
    cellrv32_uart0_printf("ERROR! No heap size defined (linker script -> '__cellrv32_heap_size')!\n");
    return -1;
  }

  // check if newlib is really available
#ifndef __NEWLIB__
  cellrv32_uart0_printf("ERROR! Seems like the compiler toolchain does not support newlib...\n");
  return -1;
#endif

  cellrv32_uart0_printf("newlib version %i.%i\n\n", (int32_t)__NEWLIB__, (int32_t)__NEWLIB_MINOR__);

  cellrv32_uart0_printf("<rand> test... ");
  srand(cellrv32_cpu_csr_read(CSR_CYCLE)); // set random seed
  cellrv32_uart0_printf("%i, %i, %i, %i\n", rand() % 100, rand() % 100, rand() % 100, rand() % 100);


  char *char_buffer; // pointer for dynamic memory allocation

  cellrv32_uart0_printf("<malloc> test...\n");
  char_buffer = (char *) malloc(4 * sizeof(char)); // 4 bytes

  // do not test read & write in simulation as there would be no UART RX input
  if (CELLRV32_SYSINFO->SOC & (1<<SYSINFO_SOC_IS_SIM)) {
    cellrv32_uart0_printf("Skipping <read> & <write> tests as this seems to be a simulation.\n");
  }
  else {
    cellrv32_uart0_printf("<read> test (waiting for 4 chars via UART0)... ");
    read((int)STDIN_FILENO, char_buffer, 4 * sizeof(char)); // get 4 chars from "STDIN" (UART0.RX)
    cellrv32_uart0_printf("ok\n");

    cellrv32_uart0_printf("<write> test to 'STDOUT'... (outputting the chars you have send)\n");
    write((int)STDOUT_FILENO, char_buffer, 4 * sizeof(char)); // send 4 chars to "STDOUT" (UART0.TX)
    cellrv32_uart0_printf("\nok\n");

    cellrv32_uart0_printf("<write> test to 'STDERR'... (outputting the chars you have send)\n");
    write((int)STDERR_FILENO, char_buffer, 4 * sizeof(char)); // send 4 chars to "STDERR" (UART0.TX)
    cellrv32_uart0_printf("\nok\n");
  }

  cellrv32_uart0_printf("<free> test...\n");
  free(char_buffer);


  // NOTE: exit is highly over-sized as it also includes clean-up functions (destructors), which
  // are not required for bare-metal or RTOS applications... better use the simple 'return' or even better
  // make sure main never returns. Anyway, let's check if 'exit' works.
  cellrv32_uart0_printf("<exit> test...");
  exit(0);

  return 0; // should never be reached
}


/**********************************************************************//**
 * "after-main" handler that is executed after the application's
 * main function returns (called by crt0.S start-up code)
 **************************************************************************/
void __cellrv32_crt0_after_main(int32_t return_code) {

  cellrv32_uart0_printf("\n<RTE> main function returned with exit code %i </RTE>\n", return_code);
}
