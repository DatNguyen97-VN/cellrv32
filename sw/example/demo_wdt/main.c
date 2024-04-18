// #################################################################################################
// # << CELLRV32 - Watchdog Demo Program >>                                                        #
// #################################################################################################


/**********************************************************************//**
 * @file demo_wdt/main.c
 * @author Stephan Nolting
 * @brief Watchdog demo program.
 **************************************************************************/
#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/** WDT timeout (until system reset) in seconds */
#define WDT_TIMEOUT_S 4
/**@}*/


/**********************************************************************//**
 * Watchdog FIRQ handler - executed when the WDT has reached half of
 * the configured timeout interval.
 **************************************************************************/
void wdt_firq_handler(void) {

  cellrv32_cpu_csr_write(CSR_MIP, ~(1<<WDT_FIRQ_PENDING)); // clear/ack pending FIRQ
  cellrv32_uart0_puts("WDT IRQ! Timeout imminent!\n");
}


/**********************************************************************//**
 * Main function
 *
 * @note This program requires the WDT and UART0 to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // setup CELLRV32 runtime environment for capturing all traps
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if WDT is implemented at all
  if (cellrv32_wdt_available() == 0) {
    return 1; // WDT not synthesized
  }

  // check if UART0 is implemented at all
  if (cellrv32_uart0_available() == 0) {
    return 1; // UART0 not synthesized
  }


  // intro
  cellrv32_uart0_puts("\n<< Watchdog Demo Program >>\n\n");


  // show the cause of the last processor reset
  cellrv32_uart0_puts("Cause of last processor reset: ");
  if (cellrv32_wdt_get_cause() == 0) {
    cellrv32_uart0_puts("External reset\n\n");
  }
  else {
    cellrv32_uart0_puts("Watchdog timeout\n\n");
  }


  // configure and enable WDT interrupt
  // this IRQ will trigger when half of the configured WDT timeout interval has been reached
  cellrv32_uart0_puts("Configuring WDT interrupt...\n");
  cellrv32_rte_handler_install(WDT_RTE_ID, wdt_firq_handler);
  cellrv32_cpu_csr_set(CSR_MIE, 1 << WDT_FIRQ_ENABLE); // enable WDT FIRQ channel
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE); // enable machine-mode interrupts


  // compute WDT timeout value
  // - the WDT counter increments at f_wdt = f_main / 4096
  uint32_t timeout = WDT_TIMEOUT_S * (CELLRV32_SYSINFO->CLK / 4096);
  if (timeout & 0xFF000000U) { // check if timeout value fits into 24-bit
    cellrv32_uart0_puts("Timeout value does not fit into 24-bit!\n");
    return -1;
  }

  // setup watchdog: no lock, disable in debug mode, enable in sleep mode
  cellrv32_uart0_puts("Starting WDT...\n");
  cellrv32_wdt_setup(timeout, 0, 0, 1);


  // feed the watchdog
  cellrv32_uart0_puts("Resetting WDT...\n");
  cellrv32_wdt_feed(); // reset internal counter to zero


  // go to sleep mode and wait for watchdog to kick in
  cellrv32_uart0_puts("Entering sleep mode and waiting for WDT timeout...\n");
  while(1) {
    cellrv32_cpu_sleep();
  }

  return 0; // will never be reached
}
