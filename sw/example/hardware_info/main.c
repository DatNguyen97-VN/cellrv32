// #################################################################################################
// # << CELLRV32 - Show all available hardware configuration information >>                        #
// #################################################################################################


/**********************************************************************//**
 * @file hardware_info/main.c
 * @author Stephan Nolting
 * @brief Show all available hardware configuration information.
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
 * Main function
 *
 * @note This program requires the UART interface to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // abort if UART0 is not implemented
  if (cellrv32_uart0_available() == 0) {
    return 1;
  }

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // show full HW config report
  cellrv32_rte_print_hw_config();

  cellrv32_uart0_printf("\nExecution completed.\n");

  return 0;
}
