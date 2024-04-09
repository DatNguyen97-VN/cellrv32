// #################################################################################################
// # << CELLRV32: cellrv32_twi.c - Two-Wire Interface Controller (TWI) HW Driver >>                #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_twi.c
 * @brief Two-Wire Interface Controller (TWI) HW driver source file.
 *
 * @note These functions should only be used if the TWI unit was synthesized (IO_TWI_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_twi.h"


/**********************************************************************//**
 * Check if TWI unit was synthesized.
 *
 * @return 0 if TWI was not synthesized, 1 if TWI is available.
 **************************************************************************/
int cellrv32_twi_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_TWI)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Enable and configure TWI controller. The TWI control register bits are listed in #CELLRV32_TWI_CTRL_enum.
 *
 * @param[in] prsc Clock prescaler select (0..7). See #CELLRV32_CLOCK_PRSC_enum.
 * @param[in] cdiv Clock divider (0..15).
 * @param[in] csen Allow clock stretching when 1.
 **************************************************************************/
void cellrv32_twi_setup(int prsc, int cdiv, int csen) {

  CELLRV32_TWI->CTRL = 0; // reset

  uint32_t ctrl = 0;
  ctrl |= ((uint32_t)(          1) << TWI_CTRL_EN);
  ctrl |= ((uint32_t)(prsc & 0x07) << TWI_CTRL_PRSC0);
  ctrl |= ((uint32_t)(cdiv & 0x0F) << TWI_CTRL_CDIV0);
  ctrl |= ((uint32_t)(csen & 0x01) << TWI_CTRL_CSEN);
  CELLRV32_TWI->CTRL = ctrl;
}


/**********************************************************************//**
 * Disable TWI controller.
 **************************************************************************/
void cellrv32_twi_disable(void) {

  CELLRV32_TWI->CTRL &= ~((uint32_t)(1 << TWI_CTRL_EN));
}


/**********************************************************************//**
 * Enable TWI controller.
 **************************************************************************/
void cellrv32_twi_enable(void) {

  CELLRV32_TWI->CTRL |= (uint32_t)(1 << TWI_CTRL_EN);
}


/**********************************************************************//**
 * Activate sending ACKs by controller (MACK).
 **************************************************************************/
void cellrv32_twi_mack_enable(void) {

  CELLRV32_TWI->CTRL |= ((uint32_t)(1 << TWI_CTRL_MACK));
}


/**********************************************************************//**
 * Deactivate sending ACKs by controller (MACK).
 **************************************************************************/
void cellrv32_twi_mack_disable(void) {

  CELLRV32_TWI->CTRL &= ~((uint32_t)(1 << TWI_CTRL_MACK));
}


/**********************************************************************//**
 * Check if TWI is busy.
 *
 * @return 0 if idle, 1 if busy
 **************************************************************************/
int cellrv32_twi_busy(void) {

  if (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_BUSY)) {
    return 1;
  }
  else {
    return 0;
  }
}


 /**********************************************************************//**
 * Generate START condition and send first byte (address including R/W bit).
 *
 * @note Blocking function.
 *
 * @param[in] a Data byte including 7-bit address and R/W-bit (lsb).
 * @return 0: ACK received, 1: NACK received.
 **************************************************************************/
int cellrv32_twi_start_trans(uint8_t a) {

  cellrv32_twi_generate_start(); // generate START condition

  return cellrv32_twi_trans(a); // transfer address
}


 /**********************************************************************//**
 * Send data byte and also receive data byte (can be read via cellrv32_twi_get_data()).
 *
 * @note Blocking function.
 *
 * @param[in] d Data byte to be send.
 * @return 0: ACK received, 1: NACK received.
 **************************************************************************/
int cellrv32_twi_trans(uint8_t d) {

  CELLRV32_TWI->DATA = (uint32_t)d; // send data
  while (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_BUSY)); // wait until idle again

  // check for ACK/NACK
  if (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_ACK)) {
    return 0; // ACK received
  }
  else {
    return 1; // NACK received
  }
}


 /**********************************************************************//**
 * Get received data from last transmission.
 *
 * @return 0: Last received data byte.
 **************************************************************************/
uint8_t cellrv32_twi_get_data(void) {

  return (uint8_t)CELLRV32_TWI->DATA; // get RX data from previous transmission
}


 /**********************************************************************//**
 * Generate STOP condition.
 *
 * @note Blocking function.
 **************************************************************************/
void cellrv32_twi_generate_stop(void) {

  CELLRV32_TWI->CTRL |= (uint32_t)(1 << TWI_CTRL_STOP); // generate STOP condition
  while (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_BUSY)); // wait until idle again
}


 /**********************************************************************//**
 * Generate START (or REPEATED-START) condition.
 *
 * @note Blocking function.
 **************************************************************************/
void cellrv32_twi_generate_start(void) {

  CELLRV32_TWI->CTRL |= (1 << TWI_CTRL_START); // generate START condition
  while (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_BUSY)); // wait until idle again
}


 /**********************************************************************//**
 * Check if the TWI bus is currently claimed by any controller.
 *
 * @return 0: 0 if bus is not claimed, 1 if bus is claimed.
 **************************************************************************/
int cellrv32_twi_bus_claimed(void) {

  if (CELLRV32_TWI->CTRL & (1 << TWI_CTRL_CLAIMED)) {
    return 1;
  }
  else {
    return 0;
  }
}
