// #################################################################################################
// # << CELLRV32: cellrv32_spi_irq.h - IRQ driven SPI Controller HW Driver >>                      #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_spi_irq.h
 * @author Andreas Kaeberlein
 * @brief Addition to cellrv32_spi.h, which provides an IRQ driven data flow.
 *
 * @note These functions should only be used if the SPI unit was synthesized (IO_SPI_EN = true).
 **************************************************************************/

#ifndef cellrv32_spi_irq_h
#define cellrv32_spi_irq_h

// MIN macro
//   https://stackoverflow.com/questions/3437404/min-and-max-in-c
#define min(a,b) \
  ({ __typeof__ (a) _a = (a); \
     __typeof__ (b) _b = (b); \
    _a < _b ? _a : _b; })

// data handle for ISR
typedef struct t_cellrv32_spi
{
  uint8_t*          ptrSpiBuf;    /**< SPI buffer data pointer */
  uint8_t           uint8Csn;     /**< SPI chip select channel */
  uint16_t          uint16Fifo;   /**< Number of elements in Fifo */
  uint32_t          uint32Total;  /**< Number of elements in buffer */
  volatile uint32_t uint32Write;  /**< To SPI core write elements */
  volatile uint32_t uint32Read;   /**< From SPI core read elements */
  volatile uint8_t  uint8IsBusy;  /**< Spi Core is Busy*/
} t_cellrv32_spi;


// prototypes
void  cellrv32_spi_init(t_cellrv32_spi *self);
void  cellrv32_spi_isr(t_cellrv32_spi *self);
int   cellrv32_spi_rw(t_cellrv32_spi *self, uint8_t csn, void *spi, uint32_t len);
int   cellrv32_spi_rw_busy(t_cellrv32_spi *self);

#endif // cellrv32_spi_irq_h
