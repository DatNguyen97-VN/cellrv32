// #################################################################################################
// # << CELLRV32: cellrv32_mtime.c - Machine System Timer (MTIME) HW Driver >>                     #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_mtime.c
 * @brief Machine System Timer (MTIME) HW driver source file.
 *
 * @note These functions should only be used if the MTIME unit was synthesized (IO_MTIME_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_mtime.h"


/**********************************************************************//**
 * Check if MTIME unit was synthesized.
 *
 * @return 0 if MTIME was not synthesized, 1 if MTIME is available.
 **************************************************************************/
int cellrv32_mtime_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_MTIME)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Set current system time.
 *
 * @note The MTIME timer increments with the primary processor clock.
 *
 * @param[in] time New system time (uint64_t)
 **************************************************************************/
void cellrv32_mtime_set_time(uint64_t time) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  cycles.uint64 = time;

  CELLRV32_MTIME->TIME_LO = 0;
  CELLRV32_MTIME->TIME_HI = cycles.uint32[1];
  CELLRV32_MTIME->TIME_LO = cycles.uint32[0];

  asm volatile("nop"); // delay due to write buffer
}


/**********************************************************************//**
 * Get current system time.
 *
 * @note The MTIME timer increments with the primary processor clock.
 *
 * @return Current system time (uint64_t)
 **************************************************************************/
uint64_t cellrv32_mtime_get_time(void) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  uint32_t tmp1, tmp2, tmp3;
  while(1) {
    tmp1 = CELLRV32_MTIME->TIME_HI;
    tmp2 = CELLRV32_MTIME->TIME_LO;
    tmp3 = CELLRV32_MTIME->TIME_HI;
    if (tmp1 == tmp3) {
      break;
    }
  }

  cycles.uint32[0] = tmp2;
  cycles.uint32[1] = tmp3;

  return cycles.uint64;
}


/**********************************************************************//**
 * Set compare time register (MTIMECMP) for generating interrupts.
 *
 * @note The interrupt is triggered when MTIME >= MTIMECMP.
 * @note Global interrupts and the timer interrupt source have to be enabled .
 *
 * @param[in] timecmp System time for interrupt (uint64_t)
 **************************************************************************/
void cellrv32_mtime_set_timecmp(uint64_t timecmp) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  cycles.uint64 = timecmp;

  CELLRV32_MTIME->TIMECMP_LO = -1; // prevent MTIMECMP from temporarily becoming smaller than the lesser of the old and new values
  CELLRV32_MTIME->TIMECMP_HI = cycles.uint32[1];
  CELLRV32_MTIME->TIMECMP_LO = cycles.uint32[0];

  asm volatile("nop"); // delay due to write buffer
}


/**********************************************************************//**
 * Get compare time register (MTIMECMP).
 *
 * @return Current MTIMECMP value.
 **************************************************************************/
uint64_t cellrv32_mtime_get_timecmp(void) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  cycles.uint32[0] = CELLRV32_MTIME->TIMECMP_LO;
  cycles.uint32[1] = CELLRV32_MTIME->TIMECMP_HI;

  return cycles.uint64;
}
