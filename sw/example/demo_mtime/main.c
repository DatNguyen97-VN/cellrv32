// #################################################################################################
// # << CELLRV32 - RISC-V Machine Timer (MTIME) Demo Program >>                                    #
// #################################################################################################


/**********************************************************************//**
 * @file demo_mtime/main.c
 * @author Stephan Nolting
 * @brief Simple machine timer (MTIME) usage example.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/** GPIO PORT selects*/
#define GPIO_PORT 12
/**@}*/


// Prototypes
void mtime_irq_handler(void);


/**********************************************************************//**
 * This program blinks an LED at GPIO.output(0) at 1Hz using the machine timer interrupt.
 *
 * @note This program requires the MTIME unit to be synthesized (and UART0 and GPIO).
 *
 * @return Should not return;
 **************************************************************************/
int main() {
  
  // capture all exceptions and give debug info via UART
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);


  // check if MTIME unit is implemented at all
  if (cellrv32_mtime_available() == 0) {
    cellrv32_uart0_puts("ERROR! MTIME timer not implemented!\n");
    return 1;
  }

  // Intro
  cellrv32_uart0_printf("RISC-V Machine System Timer (MTIME) demo Program.\n"
                     "Toggles GPIO.output(%i) at 1Hz using the RISC-V 'MTI' interrupt.\n\n", GPIO_PORT);


  // clear GPIO output port
  cellrv32_gpio_port_set(0);


  // install MTIME interrupt handler to RTE
  cellrv32_rte_handler_install(RTE_TRAP_MTI, mtime_irq_handler);

  // configure MTIME timer's first interrupt to appear after SYSTEM_CLOCK / 2 cycles (toggle at 2Hz)
  // starting from _now_
  cellrv32_mtime_set_timecmp(cellrv32_mtime_get_time() + (CELLRV32_SYSINFO->CLK / 2));

  // enable interrupt
  cellrv32_cpu_csr_set(CSR_MIE, 1 << CSR_MIE_MTIE); // enable MTIME interrupt
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE); // enable machine-mode interrupts


  // go to sleep mode and wait for interrupt
  while(1) {
    cellrv32_cpu_sleep();
  }

  return 0;
}


/**********************************************************************//**
 * MTIME IRQ handler.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void mtime_irq_handler(void) {

  // update MTIMECMP value for next IRQ (in SYSTEM_CLOCK / 2 cycles)
  // this will also ack/clear the current MTIME interrupt request
  cellrv32_mtime_set_timecmp(cellrv32_mtime_get_timecmp() + (CELLRV32_SYSINFO->CLK / 2));


  cellrv32_uart0_putc('.'); // send tick symbol via UART
  cellrv32_gpio_pin_toggle(GPIO_PORT); // toggle output port bit 0
}
