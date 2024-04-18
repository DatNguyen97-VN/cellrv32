// #################################################################################################
// # << CELLRV32 - General Purpose Timer (GPTMR) Demo Program >>                                   #
// #################################################################################################


/**********************************************************************//**
 * @file demo_gptmr/main.c
 * @author Stephan Nolting
 * @brief Simple GPTMR usage example.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/


// Prototypes
void gptmr_firq_handler(void);


/**********************************************************************//**
 * This program blinks an LED at GPIO.output(0) at 1Hz using the general purpose timer interrupt.
 *
 * @note This program requires the GPTMR unit to be synthesized (and UART0 and GPIO).
 *
 * @return Should not return;
 **************************************************************************/
int main() {
  
  // setup CELLRV32 runtime environment (for trap handling)
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);


  // check if GPTMR unit is implemented at all
  if (cellrv32_gptmr_available() == 0) {
    cellrv32_uart0_puts("ERROR! General purpose timer not implemented!\n");
    return 1;
  }

  // Intro
  cellrv32_uart0_puts("General purpose timer (GPTMR) demo Program.\n"
                     "Toggles GPIO.output(0) at 1Hz using the GPTMR interrupt.\n\n");


  // clear GPIO output port
  cellrv32_gpio_port_set(0);


  // install GPTMR interrupt handler
  cellrv32_rte_handler_install(GPTMR_RTE_ID, gptmr_firq_handler);

  // configure timer for 1Hz ticks in continuous mode (with clock divisor = 8)
  cellrv32_gptmr_setup(CLK_PRSC_8, 1, CELLRV32_SYSINFO->CLK / (8 * 2));

  // enable interrupt
  cellrv32_cpu_csr_clr(CSR_MIP, 1 << GPTMR_FIRQ_PENDING);  // make sure there is no GPTMR IRQ pending already
  cellrv32_cpu_csr_set(CSR_MIE, 1 << GPTMR_FIRQ_ENABLE);   // enable GPTMR FIRQ channel
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE); // enable machine-mode interrupts


  // go to sleep mode and wait for interrupt
  while(1) {
    cellrv32_cpu_sleep();
  }

  return 0;
}


/**********************************************************************//**
 * GPTMR FIRQ handler.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void gptmr_firq_handler(void) {

  cellrv32_cpu_csr_write(CSR_MIP, ~(1<<GPTMR_FIRQ_PENDING)); // clear/ack pending FIRQ

  cellrv32_uart0_putc('.'); // send tick symbol via UART0
  cellrv32_gpio_pin_toggle(0); // toggle output port bit 0
}
