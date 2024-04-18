// #################################################################################################
// # << CELLRV32 - IRQ driven SPI transfer application example >>                                  #
// #################################################################################################


/**********************************************************************//**
 * @file demo_spi_irq/main.c
 * @author Andreas Kaeberlein
 * @brief Example of an ISR driven SPI transfer
 **************************************************************************/

#include <cellrv32.h>
#include <string.h>
#include "cellrv32_spi_irq.h"


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/


// Global variables
t_cellrv32_spi   g_cellrv32_spi;


/**********************************************************************//**
 * SPI Interrupt Handler
 *
 * @note Captures/Transmits the data to the SPI core
 *
 * @return void.
 **************************************************************************/
void spi_irq_handler(void)
{
    cellrv32_spi_isr(&g_cellrv32_spi);
}


/**********************************************************************//**
 * This program demonstrates the usage of an ISR driven SPI transfer
 *
 * @note This program requires the UART and the SPI to be synthesized.
 *
 * @return Irrelevant.
 **************************************************************************/
int main()
{
  // SPI Transceiver buffer
  uint8_t uint8MemBuf[10];

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if UART0 unit is implemented at all
  if (cellrv32_uart0_available() == 0) {
    return 1;
  }

  // intro
  cellrv32_uart0_printf("\n<<< IRQ driven SPI transfer >>>\n\n");

  // check if SPI unit is implemented at all
  if (cellrv32_spi_available() == 0) {
    cellrv32_uart0_printf("ERROR! No SPI unit implemented.");
    return 1;
  }

  // enable IRQ system
  cellrv32_rte_handler_install(SPI_RTE_ID, spi_irq_handler); // SPI to RTE
  cellrv32_cpu_csr_set(CSR_MIE, 1 << SPI_FIRQ_ENABLE); // enable SPI FIRQ
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE); // enable machine-mode interrupts

  // SPI
    // SPI Control
  cellrv32_spi_init(&g_cellrv32_spi);
    // Configure
  cellrv32_spi_disable();
    // cellrv32_spi_setup(int prsc, int cdiv, int clk_phase, int clk_polarity, uint32_t irq_mask)
  cellrv32_spi_setup(0, 0, 0, 0, 1<<SPI_CTRL_IRQ_TX_EMPTY);  // spi mode 0, IRQ: 0-: PHY going idle, 10: TX fifo less than half full, 11: TX fifo empty
  cellrv32_spi_enable();

  // IRQ based data transfer
  memset(uint8MemBuf, 0, sizeof(uint8MemBuf));  // fill with 0's
  uint8MemBuf[0] = 0x3;
  uint8MemBuf[1] = 0x0;
  uint8MemBuf[2] = 0x0;
  uint8MemBuf[3] = 0x0;
    // int cellrv32_spi_rw(t_cellrv32_spi *self, uint8_t csn, void *spi, uint32_t len)
  cellrv32_spi_rw(&g_cellrv32_spi, 0, uint8MemBuf, sizeof(uint8MemBuf));  // send/receive data

  // Wait for complete, free for other jobs
  while ( cellrv32_spi_rw_busy(&g_cellrv32_spi) ) {
    __asm("nop");
  }

  // stop program counter
  while ( 1 ) { }
  return 0;
}
