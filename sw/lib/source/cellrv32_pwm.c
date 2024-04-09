// #################################################################################################
// # << CELLRV32: cellrv32_pwm.c - Pulse Width Modulation Controller (PWM) HW Driver >>            #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_pwm.c
 * @brief Pulse-Width Modulation Controller (PWM) HW driver source file.
 *
 * @note These functions should only be used if the PWM unit was synthesized (IO_PWM_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_pwm.h"


/**********************************************************************//**
 * Check if PWM unit was synthesized.
 *
 * @return 0 if PWM was not synthesized, 1 if PWM is available.
 **************************************************************************/
int cellrv32_pwm_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_PWM)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Enable and configure pulse width modulation controller.
 * The PWM control register bits are listed in #CELLRV32_PWM_CTRL_enum.
 *
 * @param[in] prsc Clock prescaler select (0..7). See #CELLRV32_CLOCK_PRSC_enum.
 **************************************************************************/
void cellrv32_pwm_setup(int prsc) {

  CELLRV32_PWM->CTRL = 0; // reset

  uint32_t ct_enable = 1;
  ct_enable = ct_enable << PWM_CTRL_EN;

  uint32_t ct_prsc = (uint32_t)(prsc & 0x07);
  ct_prsc = ct_prsc << PWM_CTRL_PRSC0;

  CELLRV32_PWM->CTRL = ct_enable | ct_prsc;
}


/**********************************************************************//**
 * Disable pulse width modulation controller.
 **************************************************************************/
void cellrv32_pwm_disable(void) {

  CELLRV32_PWM->CTRL &= ~((uint32_t)(1 << PWM_CTRL_EN));
}


/**********************************************************************//**
 * Enable pulse width modulation controller.
 **************************************************************************/
void cellrv32_pwm_enable(void) {

  CELLRV32_PWM->CTRL |= ((uint32_t)(1 << PWM_CTRL_EN));
}


/**********************************************************************//**
 * Get number of implemented channels.
 * @warning This function will override all duty cycle configuration registers.
 *
 * @return Number of implemented channels.
 **************************************************************************/
int cellrv32_pmw_get_num_channels(void) {

  cellrv32_pwm_disable();

  int i = 0;
  uint32_t cnt = 0;

  for (i=0; i<12; i++) {
    cellrv32_pwm_set(i, 1);
    cnt += cellrv32_pwm_get(i);
  }

  return (int)cnt;
}


/**********************************************************************//**
 * Set duty cycle for channel.
 *
 * @param[in] channel Channel select (0..11).
 * @param[in] dc Duty cycle (8-bit, LSB-aligned).
 **************************************************************************/
void cellrv32_pwm_set(int channel, uint8_t dc) {

  if (channel > 11) {
    return; // out-of-range
  }

  const uint32_t dc_mask = 0xff;
  uint32_t dc_new  = (uint32_t)dc;

  uint32_t tmp = CELLRV32_PWM->DC[channel/4];

  tmp &= ~(dc_mask << ((channel % 4) * 8)); // clear previous duty cycle
  tmp |=   dc_new  << ((channel % 4) * 8);  // set new duty cycle

  CELLRV32_PWM->DC[channel/4] = tmp;
}


/**********************************************************************//**
 * Get duty cycle from channel.
 *
 * @param[in] channel Channel select (0..11).
 * @return Duty cycle (8-bit, LSB-aligned) of channel 'channel'.
 **************************************************************************/
uint8_t cellrv32_pwm_get(int channel) {

  if (channel > 11) {
    return 0; // out of range
  }

  uint32_t rd = CELLRV32_PWM->DC[channel/4] >> (((channel % 4) * 8));

  return (uint8_t)rd;
}
