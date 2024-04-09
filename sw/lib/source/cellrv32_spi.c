// #################################################################################################
// # << CELLRV32: cellrv32_spi.c - Serial Peripheral Interface Controller (SPI) HW Driver >>       #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_spi.c
 * @brief Serial peripheral interface controller (SPI) HW driver source file.
 *
 * @note These functions should only be used if the SPI unit was synthesized (IO_SPI_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_spi.h"


/**********************************************************************//**
 * Check if SPI unit was synthesized.
 *
 * @return 0 if SPI was not synthesized, 1 if SPI is available.
 **************************************************************************/
int cellrv32_spi_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_SPI)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Enable and configure SPI controller. The SPI control register bits are listed in #CELLRV32_SPI_CTRL_enum.
 *
 * @param[in] prsc Clock prescaler select (0..7).  See #CELLRV32_CLOCK_PRSC_enum.
 * @prama[in] cdiv Clock divider (0..15).
 * @param[in] clk_phase Clock phase (0=sample on rising edge, 1=sample on falling edge).
 * @param[in] clk_polarity Clock polarity (when idle).
 * @param[in] irq_mask Interrupt configuration mask (CTRL's irq_* bits).
 **************************************************************************/
void cellrv32_spi_setup(int prsc, int cdiv, int clk_phase, int clk_polarity, uint32_t irq_mask) {

  CELLRV32_SPI->CTRL = 0; // reset

  uint32_t tmp = 0;
  tmp |= (uint32_t)(1            & 0x01) << SPI_CTRL_EN;
  tmp |= (uint32_t)(clk_phase    & 0x01) << SPI_CTRL_CPHA;
  tmp |= (uint32_t)(clk_polarity & 0x01) << SPI_CTRL_CPOL;
  tmp |= (uint32_t)(prsc         & 0x07) << SPI_CTRL_PRSC0;
  tmp |= (uint32_t)(cdiv         & 0x0f) << SPI_CTRL_CDIV0;
  tmp |= (uint32_t)(irq_mask     & (0x07 << SPI_CTRL_IRQ_RX_AVAIL));

  CELLRV32_SPI->CTRL = tmp;
}


/**********************************************************************//**
 * Get configured clock speed in Hz.
 *
 * @return Actual configured SPI clock speed in Hz.
 **************************************************************************/
uint32_t cellrv32_spi_get_clock_speed(void) {

  const uint32_t PRSC_LUT[8] = {2, 4, 8, 64, 128, 1024, 2048, 4096};

  uint32_t ctrl = CELLRV32_SPI->CTRL;
  uint32_t prsc_sel = (ctrl >> SPI_CTRL_PRSC0) & 0x7;
  uint32_t clock_div = (ctrl >> SPI_CTRL_CDIV0) & 0xf;

  uint32_t tmp = 2 * PRSC_LUT[prsc_sel] * clock_div;
  return CELLRV32_SYSINFO->CLK / tmp;
}


/**********************************************************************//**
 * Disable SPI controller.
 **************************************************************************/
void cellrv32_spi_disable(void) {

  CELLRV32_SPI->CTRL &= ~((uint32_t)(1 << SPI_CTRL_EN));
}


/**********************************************************************//**
 * Enable SPI controller.
 **************************************************************************/
void cellrv32_spi_enable(void) {

  CELLRV32_SPI->CTRL |= ((uint32_t)(1 << SPI_CTRL_EN));
}


/**********************************************************************//**
 * Get SPI FIFO depth.
 *
 * @return FIFO depth (number of entries), zero if no FIFO implemented
 **************************************************************************/
int cellrv32_spi_get_fifo_depth(void) {

  uint32_t tmp = (CELLRV32_SPI->CTRL >> SPI_CTRL_FIFO_LSB) & 0x0f;
  return (int)(1 << tmp);
}


/**********************************************************************//**
 * Activate single SPI chip select signal.
 *
 * @note The SPI chip select output lines are LOW when activated.
 *
 * @param cs Chip select line to activate (0..7).
 **************************************************************************/
void cellrv32_spi_cs_en(int cs) {

  uint32_t tmp = CELLRV32_SPI->CTRL;
  tmp &= ~(0xf << SPI_CTRL_CS_SEL0); // clear old configuration
  tmp |= (1 << SPI_CTRL_CS_EN) | ((cs & 7) << SPI_CTRL_CS_SEL0); // set new configuration
  CELLRV32_SPI->CTRL = tmp;
}


/**********************************************************************//**
 * Deactivate currently active SPI chip select signal.
 *
 * @note The SPI chip select output lines are HIGH when deactivated.
 **************************************************************************/
void cellrv32_spi_cs_dis(void) {

  CELLRV32_SPI->CTRL &= ~(1 << SPI_CTRL_CS_EN);
}


/**********************************************************************//**
 * Initiate SPI transfer.
 *
 * @note This function is blocking.
 *
 * @param tx_data Transmit data (8-bit, LSB-aligned).
 * @return Receive data (8-bit, LSB-aligned).
 **************************************************************************/
uint8_t cellrv32_spi_trans(uint8_t tx_data) {

  CELLRV32_SPI->DATA = (uint32_t)tx_data; // trigger transfer
  while((CELLRV32_SPI->CTRL & (1<<SPI_CTRL_BUSY)) != 0); // wait for current transfer to finish

  return (uint8_t)CELLRV32_SPI->DATA;
}


/**********************************************************************//**
 * Initiate SPI TX transfer (non-blocking).
 *
 * @param tx_data Transmit data (8-bit, LSB-aligned).
 **************************************************************************/
void cellrv32_spi_put_nonblocking(uint8_t tx_data) {

  CELLRV32_SPI->DATA = (uint32_t)tx_data; // trigger transfer
}


/**********************************************************************//**
 * Get SPI RX data (non-blocking).
 *
 * @return Receive data (8-bit, LSB-aligned).
 **************************************************************************/
uint8_t cellrv32_spi_get_nonblocking(void) {

  return (uint8_t)CELLRV32_SPI->DATA;
}


/**********************************************************************//**
 * Check if SPI transceiver is busy.
 *
 * @return 0 if idle, 1 if busy
 **************************************************************************/
int cellrv32_spi_busy(void) {

  if ((CELLRV32_SPI->CTRL & (1<<SPI_CTRL_BUSY)) != 0) {
    return 1;
  }
  else {
    return 0;
  }
}
