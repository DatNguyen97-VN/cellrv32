// #################################################################################################
// # << CELLRV32: cellrv32_sdi.c - Serial Data Interface Controller (SDI) HW Driver >>             #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_sdi.c
 * @brief Serial data interface controller (SDI) HW driver source file.
 *
 * @note These functions should only be used if the SDI unit was synthesized (IO_SDI_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_sdi.h"


/**********************************************************************//**
 * Check if SDI unit was synthesized.
 *
 * @return 0 if SDI was not synthesized, 1 if SPI is available.
 **************************************************************************/
int cellrv32_sdi_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_SDI)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Reset, enable and configure SDI controller.
 * The SDI control register bits are listed in #CELLRV32_SDI_CTRL_enum.
 *
 * @param[in] irq_mask Interrupt configuration mask (CTRL's irq_* bits).
 **************************************************************************/
void cellrv32_sdi_setup(uint32_t irq_mask) {

  CELLRV32_SDI->CTRL = 0; // reset

  uint32_t tmp = 0;
  tmp |= (uint32_t)(1 & 0x01) << SDI_CTRL_EN;
  tmp |= (uint32_t)(irq_mask & (0x0f << SDI_CTRL_IRQ_RX_AVAIL));

  CELLRV32_SDI->CTRL = tmp;
}


/**********************************************************************//**
 * Clear SDI receive FIFO.
 **************************************************************************/
void cellrv32_sdi_rx_clear(void) {

  CELLRV32_SDI->CTRL |= (uint32_t)(1 << SDI_CTRL_CLR_RX);
}


/**********************************************************************//**
 * Disable SDI controller.
 **************************************************************************/
void cellrv32_sdi_disable(void) {

  CELLRV32_SDI->CTRL &= ~((uint32_t)(1 << SDI_CTRL_EN));
}


/**********************************************************************//**
 * Enable SDI controller.
 **************************************************************************/
void cellrv32_sdi_enable(void) {

  CELLRV32_SDI->CTRL |= ((uint32_t)(1 << SDI_CTRL_EN));
}


/**********************************************************************//**
 * Get SDI FIFO depth.
 *
 * @return FIFO depth (number of entries), zero if no FIFO implemented
 **************************************************************************/
int cellrv32_sdi_get_fifo_depth(void) {

  uint32_t tmp = (CELLRV32_SDI->CTRL >> SDI_CTRL_FIFO_LSB) & 0x0f;
  return (int)(1 << tmp);
}


/**********************************************************************//**
 * Push data to SDI output FIFO.
 *
 * @param[in] data Byte to push into TX FIFO.
 * @return -1 if TX FIFO is full.
 **************************************************************************/
int cellrv32_sdi_put(uint8_t data) {

  if (CELLRV32_SDI->CTRL & (1 << SDI_CTRL_TX_FULL)) {
    return -1;
  }
  else {
    CELLRV32_SDI->DATA = (uint32_t)data;
    return 0;
  }
}


/**********************************************************************//**
 * Push data to SDI output FIFO (ignoring TX FIFO status).
 *
 * @param[in] data Byte to push into TX FIFO.
 **************************************************************************/
void cellrv32_sdi_put_nonblocking(uint8_t data) {

  CELLRV32_SDI->DATA = (uint32_t)data;
}


/**********************************************************************//**
 * Get data from SDI input FIFO.
 *
 * @param[in,out] Pointer fro data byte read from RX FIFO.
 * @return -1 if RX FIFO is empty.
 **************************************************************************/
int cellrv32_sdi_get(uint8_t* data) {

  if (CELLRV32_SDI->CTRL & (1 << SDI_CTRL_RX_AVAIL)) {
    *data = (uint8_t)CELLRV32_SDI->DATA;
    return 0;
  }
  else {
    return -1;
  }
}


/**********************************************************************//**
 * Get data from SDI input FIFO (ignoring RX FIFO status).
 *
 * @param[in] data Byte read from RX FIFO.
 **************************************************************************/
uint8_t cellrv32_sdi_get_nonblocking(void) {

  return (uint8_t)CELLRV32_SDI->DATA;
}
