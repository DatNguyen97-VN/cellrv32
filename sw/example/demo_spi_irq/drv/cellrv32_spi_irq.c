// #################################################################################################
// # << CELLRV32: cellrv32_spi_irq.c - IRQ driven SPI Controller HW Driver >>                      #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_spi_irq.c
 * @author Andreas Kaeberlein
 * @brief Addition to cellrv32_spi.c, which provides an IRQ driven data flow.
 *
 * @note These functions should only be used if the SPI unit was synthesized (IO_SPI_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_spi_irq.h"


/**********************************************************************//**
 * Initializes SPI flow control handle. The data structure elements are listed in #t_cellrv32_spi.
 *
 * @param[in,out] *self SPI driver common data handle. See #t_cellrv32_spi.
 **************************************************************************/
void cellrv32_spi_init(t_cellrv32_spi *self) {

  self->uint8IsBusy = 0;
  self->uint16Fifo = (uint16_t) cellrv32_spi_get_fifo_depth(); // acquire FIFO depth in elements
  self->uint32Total = 0;
  self->uint32Write = 0;  // write element count
  self->uint32Read = 0; // read element count
  return;
}


/**********************************************************************//**
 * SPI interrupt service routine. The data structure elements are listed in #t_cellrv32_spi.
 *
 * @param[in,out] *self SPI driver common data handle. See #t_cellrv32_spi.
 **************************************************************************/
void cellrv32_spi_isr(t_cellrv32_spi *self) {

  uint32_t  uint32Lim;  // loop limit

  if ( 0 == self->uint32Total ) { // leave if accidentally called ISR
    return;
  }

  // read data from SPI from last transfer
  for ( ; self->uint32Read<self->uint32Write; (self->uint32Read)++ ) {
    (self->ptrSpiBuf)[self->uint32Read] = (uint8_t) (CELLRV32_SPI->DATA & 0xff);  // capture from last transfer
  }
  if ( self->uint32Read == self->uint32Total ) {  // transfer done, no new data
    cellrv32_spi_cs_dis(); // deselect slave
    self->uint32Total = 0;
    self->uint8IsBusy = 0;
    cellrv32_cpu_csr_clr(CSR_MIP, 1 << SPI_FIRQ_PENDING); // ack/clear pending FIRQ
    return;
  }

  // write next packet
  uint32Lim = min(self->uint32Write+self->uint16Fifo, self->uint32Total);
  for ( ; self->uint32Write<uint32Lim; (self->uint32Write)++ ) {
    CELLRV32_SPI->DATA = (uint32_t) (self->ptrSpiBuf)[self->uint32Write]; // next transfer
  }
  cellrv32_cpu_csr_clr(CSR_MIP, 1 << SPI_FIRQ_PENDING); // ack/clear pending FIRQ
  return;
}


/**********************************************************************//**
 * Starts ISR driven read/write SPI transfer.
 *
 * @param[in,out] *self SPI driver common data handle. See #t_cellrv32_spi.
 * @param[in] csn Used chip select index for transfer.
 * @param[in,out] *spi write/read data buffer for SPI. Before transmission contents the write data and after the read data.
 * @param[in] len number of bytes to transfer.
 * @return int status of function.
 * @retval 0 new transfer started.
 * @retval 1 transfer active, refused request.
 * @retval 2 unsupported data size, only 1/2/4 allowed.
 **************************************************************************/
int cellrv32_spi_rw(t_cellrv32_spi *self, uint8_t csn, void *spi, uint32_t len) {

  if ( 0 != self->uint8IsBusy ) {
    return 1; // transfer active, no new request
  }

  self->uint32Total = len;
  self->uint32Write = 0;  // write element count
  self->uint32Read = 0;   // read element count
  self->ptrSpiBuf = (uint8_t*) spi; // spi is byte orientated
  self->uint8Csn = csn;
  self->uint8IsBusy = 1;  // mark as busy

  cellrv32_spi_cs_en(self->uint8Csn);  // select SPI channel

  (self->uint32Write)++;
  CELLRV32_SPI->DATA = (uint32_t) (self->ptrSpiBuf)[0];  // sent first element

  return 0; // successful end
}


/**********************************************************************//**
 * Check if transfer is active. see #cellrv32_spi_rw
 *
 * @param[in,out] *self SPI driver common data handle. See #t_cellrv32_spi.
 * @return int status of function.
 * @retval 0 idle.
 * @retval 1 busy.
 **************************************************************************/
int cellrv32_spi_rw_busy(t_cellrv32_spi *self) {

  if ( 0 != self->uint8IsBusy ) {
    return 1;
  }
  return 0;
}
