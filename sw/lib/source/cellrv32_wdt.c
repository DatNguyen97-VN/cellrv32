// #################################################################################################
// # << CELLRV32: cellrv32_wdt.c - Watchdog Timer (WDT) HW Driver >>                               #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_wdt.c
 * @brief Watchdog Timer (WDT) HW driver source file.
 *
 * @note These functions should only be used if the WDT unit was synthesized (IO_WDT_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_wdt.h"


/**********************************************************************//**
 * Check if WDT unit was synthesized.
 *
 * @return 0 if WDT was not synthesized, 1 if WDT is available.
 **************************************************************************/
int cellrv32_wdt_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_WDT)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Configure and enable watchdog timer. The WDT control register bits are listed in #CELLRV32_WDT_CTRL_enum.
 *
 * @warning Once the lock bit is set it can only be removed by a hardware reset!
 *
 * @param[in] timeout 24-bit timeout value. A WDT IRQ is triggered when the internal counter reaches
 * 'timeout/2'. A system hardware reset is triggered when the internal counter reaches 'timeout'.
 * @param[in] lock Control register will be locked when 1 (until next reset).
 * @param[in] debug_en Allow watchdog to continue operation even when CPU is in debug mode.
 * @param[in] sleep_en Allow watchdog to continue operation even when CPU is in sleep mode.
 **************************************************************************/
void cellrv32_wdt_setup(uint32_t timeout, int lock, int debug_en, int sleep_en) {

  CELLRV32_WDT->CTRL = 0; // reset and disable

  uint32_t enable_int   = ((uint32_t)(1))                    << WDT_CTRL_EN;
  uint32_t timeout_int  = ((uint32_t)(timeout  & 0xffffffU)) << WDT_CTRL_TIMEOUT_LSB;
  uint32_t debug_en_int = ((uint32_t)(debug_en & 0x1U))      << WDT_CTRL_DBEN;
  uint32_t sleep_en_int = ((uint32_t)(sleep_en & 0x1U))      << WDT_CTRL_SEN;

  // update WDT control register
  CELLRV32_WDT->CTRL = enable_int | timeout_int | debug_en_int | sleep_en_int;

  // lock configuration?
  if (lock) {
    CELLRV32_WDT->CTRL |= 1 << WDT_CTRL_LOCK;
  }
}


/**********************************************************************//**
 * Disable watchdog timer.
 *
 * @return Returns 0 if WDT is really deactivated, -1 otherwise.
 **************************************************************************/
int cellrv32_wdt_disable(void) {

  const uint32_t en_mask_c =  (uint32_t)(1 << WDT_CTRL_EN);

  CELLRV32_WDT->CTRL &= en_mask_c; // try to disable

  // check if WDT is really off
  if (CELLRV32_WDT->CTRL & en_mask_c) {
    return -1; // still active
  }
  else {
    return 0; // WDT is disabled
  }
}


/**********************************************************************//**
 * Feed watchdog (reset timeout counter).
 **************************************************************************/
void cellrv32_wdt_feed(void) {

  CELLRV32_WDT->CTRL |= (uint32_t)(1 << WDT_CTRL_RESET);
}


/**********************************************************************//**
 * Get cause of last system reset.
 *
 * @return Cause of last reset (0: system reset - OCD or external, 1: watchdog timeout).
 **************************************************************************/
int cellrv32_wdt_get_cause(void) {

  if (CELLRV32_WDT->CTRL & (1 << WDT_CTRL_RCAUSE)) { // reset caused by watchdog
    return 1;
  }
  else { // reset caused by system (external or OCD)
    return 0;
  }
}
