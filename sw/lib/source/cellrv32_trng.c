// #################################################################################################
// # << CELLRV32: cellrv32_trng.c - True Random Number Generator (TRNG) HW Driver >>               #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_trng.c
 * @brief True Random Number Generator (TRNG) HW driver source file.
 *
 * @note These functions should only be used if the TRNG unit was synthesized (IO_TRNG_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_trng.h"


/**********************************************************************//**
 * Check if TRNG unit was synthesized.
 *
 * @return 0 if TRNG was not synthesized, 1 if TRNG is available.
 **************************************************************************/
int cellrv32_trng_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_TRNG)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Reset and enable TRNG.
 * @note This will take a while.
 **************************************************************************/
void cellrv32_trng_enable(void) {

  int i;

  CELLRV32_TRNG->CTRL = 0; // reset

  // wait for all internal components to reset
  for (i=0; i<512; i++) {
    asm volatile ("nop");
  }

  CELLRV32_TRNG->CTRL = 1 << TRNG_CTRL_EN; // activate

  // "warm-up"
  for (i=0; i<512; i++) {
    asm volatile ("nop");
  }

  // flush random data "pool"
  cellrv32_trng_fifo_clear();
}


/**********************************************************************//**
 * Reset and disable TRNG.
 **************************************************************************/
void cellrv32_trng_disable(void) {

  CELLRV32_TRNG->CTRL = 0;
}


/**********************************************************************//**
 * Flush TRNG random data FIFO.
 **************************************************************************/
void cellrv32_trng_fifo_clear(void) {

  CELLRV32_TRNG->CTRL |= 1 << TRNG_CTRL_FIFO_CLR; // bit auto clears
}


/**********************************************************************//**
 * Get random data byte from TRNG.
 *
 * @param[in,out] data uint8_t pointer for storing random data byte. Will be set to zero if no valid data available.
 * @return Data is valid when 0 and invalid otherwise.
 **************************************************************************/
int cellrv32_trng_get(uint8_t *data) {

  uint32_t tmp = CELLRV32_TRNG->CTRL;
  *data = (uint8_t)(tmp >> TRNG_CTRL_DATA_LSB);

  if (tmp & (1<<TRNG_CTRL_VALID)) { // output data valid?
    return 0; // valid data
  }
  else {
    return -1;
  }
}


/**********************************************************************//**
 * Check if TRNG is implemented using SIMULATION mode.
 *
 * @warning In simulation mode the physical entropy source is replaced by a PRNG (LFSR) with very bad random quality.
 *
 * @return Simulation mode active when not zero.
 **************************************************************************/
int cellrv32_trng_check_sim_mode(void) {

  if (CELLRV32_TRNG->CTRL & (1<<TRNG_CTRL_SIM_MODE)) {
    return -1; // simulation mode (PRNG)
  }
  else {
    return 0; // real TRUE random number generator mode
  }
}
