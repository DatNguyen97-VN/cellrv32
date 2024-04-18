// #################################################################################################
// # << CELLRV32 - External Interrupt Controller (XIRQ) Demo Program >>                            #
// #################################################################################################


/**********************************************************************//**
 * @file demo_xirq/main.c
 * @author Stephan Nolting
 * @brief External interrupt controller (XIRQ) demo program (using hardware-assisted prioritization).
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/

// prototypes
void xirq_handler_ch0(void);
void xirq_handler_ch1(void);
void xirq_handler_ch2(void);
void xirq_handler_ch3(void);


/**********************************************************************//**
 * Main function
 *
 * @note This program requires the XIRQ and the UART to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // initialize the cellrv32 runtime environment
  // this will take care of handling all CPU traps (interrupts and exceptions)
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if XIRQ unit is implemented at all
  if (cellrv32_xirq_available() == 0) {
    cellrv32_uart0_printf("XIRQ not synthesized!\n");
    return 1;
  }


  // intro
  cellrv32_uart0_printf("External interrupt controller (XIRQ) demo program\n\n");

  int err_cnt = 0;


  // initialize XIRQ controller
  // this will disable all XIRQ channels and will also clear any pending external interrupts
  // (details: this will register the XIRQ's second-level interrupt handler in the CELLRV32 RTE)
  err_cnt = cellrv32_xirq_setup();

  // check if setup went fine
  if (err_cnt) {
    cellrv32_uart0_printf("Error during XIRQ setup!\n");
    return 1;
  }


  // install handler functions for XIRQ channel 0,1,2,3. note that these functions are "normal" functions!
  // (details: these are "third-level" interrupt handlers)
  // cellrv32_xirq_install() also enables the specified XIRQ channel and clears any pending interrupts
  err_cnt = 0;
  err_cnt += cellrv32_xirq_install(0, xirq_handler_ch0); // handler function for channel 0
  err_cnt += cellrv32_xirq_install(1, xirq_handler_ch1); // handler function for channel 1
  err_cnt += cellrv32_xirq_install(2, xirq_handler_ch2); // handler function for channel 2
  err_cnt += cellrv32_xirq_install(3, xirq_handler_ch3); // handler function for channel 3

  // check if installation went fine
  if (err_cnt) {
    cellrv32_uart0_printf("Error during XIRQ install!\n");
    return 1;
  }

  // allow XIRQ to trigger CPU interrupt
  cellrv32_xirq_global_enable();

  // enable machine-mode interrupts
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);


  // the code below assumes the XIRQ inputs are connected to the processor's GPIO output port
  // so we can trigger the IRQs from software; if you have connected the XIRQs to buttons you
  // can remove the code below (note the trigger configuration using the XIRQ generics!)
  {
    // trigger XIRQs 3:0 at once
    // assumes xirq_i(31:0) <= gpio.output(31:0)

    // due to the prioritization this will execute
    // -> xirq_handler_ch0
    // -> xirq_handler_ch1
    // -> xirq_handler_ch2
    // -> xirq_handler_ch3
    cellrv32_gpio_port_set(0xF); // set output pins 3:0 -> trigger XIRQ 3:0
    cellrv32_gpio_port_set(0x0);
  }


  // --- wait for interrupts ---
  // All incoming XIRQ interrupt requests are "prioritized" in this example. The XIRQ FIRQ handler
  // reads the ID of the interrupt with the highest priority from the XIRQ controller ("source" register) and calls the according
  // handler function (installed via cellrv32_xirq_install();).
  // Non-prioritized handling of interrupts (or custom prioritization) can be implemented by manually reading the
  // XIRQ controller's "pending" register. Then it is up to the software to define which pending IRQ should be served first.
  while(1);


  // just as an example: to disable certain XIRQ interrupt channels, we can
  // un-install the according handler. this will also clear a pending interrupt for that channel
  cellrv32_xirq_uninstall(0); // disable XIRQ channel 0 and remove associated handler
  cellrv32_xirq_uninstall(1); // disable XIRQ channel 1 and remove associated handler
  cellrv32_xirq_uninstall(2); // disable XIRQ channel 2 and remove associated handler
  cellrv32_xirq_uninstall(3); // disable XIRQ channel 3 and remove associated handler

  // you can also manually clear pending interrupts
  cellrv32_xirq_clear_pending(0); // clear pending interrupt of channel 0

  // manually enable and disable XIRQ channels
  cellrv32_xirq_channel_enable(0); // enable channel 0
  cellrv32_xirq_channel_disable(0); // disable channel 0

  // globally enable/disable XIRQ CPU interrupt
  // this will not affect the XIR configuration / pending interrupts
  cellrv32_xirq_global_enable();
  cellrv32_xirq_global_disable();

  return 0;
}


/**********************************************************************//**
 * XIRQ handler channel 0.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void xirq_handler_ch0(void) {

  cellrv32_uart0_printf("XIRQ interrupt from channel %i\n", 0);
}

/**********************************************************************//**
 * XIRQ handler channel 1.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void xirq_handler_ch1(void) {

  cellrv32_uart0_printf("XIRQ interrupt from channel %i\n", 1);
}

/**********************************************************************//**
 * XIRQ handler channel 2.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void xirq_handler_ch2(void) {

  cellrv32_uart0_printf("XIRQ interrupt from channel %i\n", 2);
}

/**********************************************************************//**
 * XIRQ handler channel 3.
 *
 * @warning This function has to be of type "void xyz(void)" and must not use any interrupt attributes!
 **************************************************************************/
void xirq_handler_ch3(void) {

  cellrv32_uart0_printf("XIRQ interrupt from channel %i\n", 3);
}
