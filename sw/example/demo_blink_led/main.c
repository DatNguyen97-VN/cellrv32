// #################################################################################################
// # << CELLRV32 - Blinking LED Demo Program >>                                                    #
// #################################################################################################


/**********************************************************************//**
 * @file demo_blink_led/main.c
 * @author Stephan Nolting
 * @brief Minimal blinking LED demo program using the lowest 8 bits of the GPIO.output port.
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
 * Main function; shows an incrementing 8-bit counter on GPIO.output(7:0).
 *
 * @note This program requires the GPIO controller to be synthesized.
 *
 * @return Will never return.
 **************************************************************************/
int main() {

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart1_setup(BAUD_RATE, 0);

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // print project logo via UART
  cellrv32_rte_print_logo();

  // say hello
  cellrv32_uart1_puts("<<<  Demo Blink LED program  >>>\n");

  // clear GPIO output (set all bits to 0)
  cellrv32_gpio_port_set(0);

  int cnt = 0;

  while (1) {
    cellrv32_gpio_port_set(cnt++ & 0xFFFF); // increment counter and mask for lowest 8 bit
    cellrv32_cpu_delay_ms(200); // wait 100ms using busy wait
  }

  // this should never be reached
  return 0;
}
