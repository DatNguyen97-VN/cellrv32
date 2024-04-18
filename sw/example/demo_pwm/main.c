// #################################################################################################
// # << CELLRV32 - PWM Demo Program >>                                                             #
// #################################################################################################


/**********************************************************************//**
 * @file demo_pwm/main.c
 * @author Stephan Nolting
 * @brief Simple PWM demo program.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/** Maximum PWM output intensity (8-bit) */
#define PWM_MAX 200
/**@}*/



/**********************************************************************//**
 * This program generates a simple dimming sequence for PWM channels 0 to 3.
 *
 * @note This program requires the PWM controller to be synthesized (the UART is optional).
 *
 * @return !=0 if error.
 **************************************************************************/
int main() {

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // use UART0 if implemented
  if (cellrv32_uart0_available()) {

    // setup UART at default baud rate, no interrupts
    cellrv32_uart0_setup(BAUD_RATE, 0);

    // say hello
    cellrv32_uart0_printf("<<< PWM demo program >>>\n");
  }

  // check if PWM unit is implemented at all
  if (cellrv32_pwm_available() == 0) {
    if (cellrv32_uart0_available()) {
      cellrv32_uart0_printf("ERROR: PWM module not implemented!\n");
    }
    return 1;
  }

  int num_pwm_channels = cellrv32_pmw_get_num_channels();

  // check number of PWM channels
  if (cellrv32_uart0_available()) {
    cellrv32_uart0_printf("Implemented PWM channels: %i\n\n", num_pwm_channels);
  }


  // deactivate all PWM channels
  int i;
  for (i=0; i<num_pwm_channels; i++) {
    cellrv32_pwm_set(i, 0);
  }

  // configure and enable PWM
  cellrv32_pwm_setup(CLK_PRSC_64);

  uint8_t pwm = 0;
  uint8_t up = 1;
  uint8_t ch = 0;

  // animate!
  while(1) {
  
    // update duty cycle
    if (up) {
      if (pwm == PWM_MAX) {
        up = 0;
      }
      else {
        pwm++;
      }
    }
    else {
      if (pwm == 0) {
        ch = (ch + 1) & 3; // goto next channel
        up = 1;
      }
      else {
        pwm--;
      }
    }

    cellrv32_pwm_set(ch, pwm); // output new duty cycle
    cellrv32_cpu_delay_ms(3); // wait ~3ms
  }

  return 0;
}
