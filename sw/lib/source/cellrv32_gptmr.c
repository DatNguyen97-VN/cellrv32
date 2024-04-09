// #################################################################################################
// # << CELLRV32: cellrv32_gptmr.c - General Purpose Timer (GPTMR) HW Driver >>                    #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_gptmr.c
 * @brief General purpose timer (GPTMR) HW driver source file.
 *
 * @note These functions should only be used if the GPTMR unit was synthesized (IO_GPTMR_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_gptmr.h"


/**********************************************************************//**
 * Check if general purpose timer unit was synthesized.
 *
 * @return 0 if GPTMR was not synthesized, 1 if GPTMR is available.
 **************************************************************************/
int cellrv32_gptmr_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_GPTMR)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Enable and configure general purpose timer.
 *
 * @param[in] prsc Clock prescaler select (0..7). See #CELLRV32_CLOCK_PRSC_enum.
 * @param[in] mode 0=single-shot mode, 1=continuous mode
 * @param[in] threshold Threshold value to trigger interrupt.
 **************************************************************************/
void cellrv32_gptmr_setup(int prsc, int mode, uint32_t threshold) {

  CELLRV32_GPTMR->CTRL  = 0; // reset
  CELLRV32_GPTMR->THRES = threshold;
  CELLRV32_GPTMR->COUNT = 0; // reset counter

  uint32_t tmp = 0;
  tmp |= (uint32_t)(1    & 0x01) << GPTMR_CTRL_EN;
  tmp |= (uint32_t)(prsc & 0x07) << GPTMR_CTRL_PRSC0;
  tmp |= (uint32_t)(mode & 0x01) << GPTMR_CTRL_MODE;

  CELLRV32_GPTMR->CTRL = tmp;
}


/**********************************************************************//**
 * Disable general purpose timer.
 **************************************************************************/
void cellrv32_gptmr_disable(void) {

  CELLRV32_GPTMR->CTRL &= ~((uint32_t)(1 << GPTMR_CTRL_EN));
}


/**********************************************************************//**
 * Enable general purpose timer.
 **************************************************************************/
void cellrv32_gptmr_enable(void) {

  CELLRV32_GPTMR->CTRL |= ((uint32_t)(1 << GPTMR_CTRL_EN));
}


/**********************************************************************//**
 * Reset general purpose timer's counter register.
 **************************************************************************/
void cellrv32_gptmr_restart(void) {

  CELLRV32_GPTMR->COUNT = 0;
}
