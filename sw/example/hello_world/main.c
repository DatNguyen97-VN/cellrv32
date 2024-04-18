// #################################################################################################
// # << CELLRV32 - "Hello World" Demo Program >>                                                   #
// #################################################################################################


/**********************************************************************//**
 * @file hello_world/main.c
 * @author Stephan Nolting
 * @brief Classic 'hello world' demo program.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/



/**********************************************************************//**
 * Main function; prints some fancy stuff via UART.
 *
 * @note This program requires the UART interface to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // print project logo via UART
  cellrv32_rte_print_logo();

  // say hello
  cellrv32_uart0_puts("Hello world! hjhj:) by uart1\n");


  return 0;
}
