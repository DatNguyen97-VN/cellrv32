// ##################################################################################################
// # << CELLRV32: cellrv32_uart.h - Universal Asynchronous Receiver/Transmitter (UART) HW Driver >> #
// # ********************************************************************************************** #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen  #
// ##################################################################################################


/**********************************************************************//**
 * @file cellrv32_uart.h
 * @brief Universal asynchronous receiver/transmitter (UART0/UART1) HW driver header file
 **************************************************************************/

#ifndef cellrv32_uart_h
#define cellrv32_uart_h

// Libs required by functions
#include <stdarg.h>

/**********************************************************************//**
 * @name IO Device: Primary/Secondary Universal Asynchronous Receiver and Transmitter (UART0 / UART1)
 **************************************************************************/
/**@{*/
/** UART module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL;  /**< offset 0: control register (#CELLRV32_UART_CTRL_enum) */
  uint32_t DATA;  /**< offset 4: data register */
} cellrv32_uart_t;

/** UART0 module hardware access (#cellrv32_uart_t) */
#define CELLRV32_UART0 ((cellrv32_uart_t*) (CELLRV32_UART0_BASE))

/** UART1 module hardware access (#cellrv32_uart_t) */
#define CELLRV32_UART1 ((cellrv32_uart_t*) (CELLRV32_UART1_BASE))

/** UART control register bits */
enum CELLRV32_UART_CTRL_enum {
  UART_CTRL_EN            =  0, /**< UART control register(0)  (r/w): UART global enable */
  UART_CTRL_SIM_MODE      =  1, /**< UART control register(1)  (r/w): Simulation output override enable */
  UART_CTRL_HWFC_EN       =  2, /**< UART control register(2)  (r/w): Enable RTS/CTS hardware flow-control */
  UART_CTRL_PRSC0         =  3, /**< UART control register(3)  (r/w): clock prescaler select bit 0 */
  UART_CTRL_PRSC1         =  4, /**< UART control register(4)  (r/w): clock prescaler select bit 1 */
  UART_CTRL_PRSC2         =  5, /**< UART control register(5)  (r/w): clock prescaler select bit 2 */
  UART_CTRL_BAUD0         =  6, /**< UART control register(6)  (r/w): BAUD rate divisor, bit 0 */
  UART_CTRL_BAUD1         =  7, /**< UART control register(7)  (r/w): BAUD rate divisor, bit 1 */
  UART_CTRL_BAUD2         =  8, /**< UART control register(8)  (r/w): BAUD rate divisor, bit 2 */
  UART_CTRL_BAUD3         =  9, /**< UART control register(9)  (r/w): BAUD rate divisor, bit 3 */
  UART_CTRL_BAUD4         = 10, /**< UART control register(10) (r/w): BAUD rate divisor, bit 4 */
  UART_CTRL_BAUD5         = 11, /**< UART control register(11) (r/w): BAUD rate divisor, bit 5 */
  UART_CTRL_BAUD6         = 12, /**< UART control register(12) (r/w): BAUD rate divisor, bit 6 */
  UART_CTRL_BAUD7         = 13, /**< UART control register(13) (r/w): BAUD rate divisor, bit 7 */
  UART_CTRL_BAUD8         = 14, /**< UART control register(14) (r/w): BAUD rate divisor, bit 8 */
  UART_CTRL_BAUD9         = 15, /**< UART control register(15) (r/w): BAUD rate divisor, bit 9 */

  UART_CTRL_RX_NEMPTY     = 16, /**< UART control register(16) (r/-): RX FIFO not empty */
  UART_CTRL_RX_HALF       = 17, /**< UART control register(17) (r/-): RX FIFO at least half-full */
  UART_CTRL_RX_FULL       = 18, /**< UART control register(18) (r/-): RX FIFO full */
  UART_CTRL_TX_EMPTY      = 19, /**< UART control register(19) (r/-): TX FIFO empty */
  UART_CTRL_TX_NHALF      = 20, /**< UART control register(20) (r/-): TX FIFO not at least half-full */
  UART_CTRL_TX_FULL       = 21, /**< UART control register(21) (r/-): TX FIFO full */

  UART_CTRL_IRQ_RX_NEMPTY = 22, /**< UART control register(22) (r/w): Fire IRQ if RX FIFO not empty */
  UART_CTRL_IRQ_RX_HALF   = 23, /**< UART control register(23) (r/w): Fire IRQ if RX FIFO at least half-full */
  UART_CTRL_IRQ_RX_FULL   = 24, /**< UART control register(24) (r/w): Fire IRQ if RX FIFO full */
  UART_CTRL_IRQ_TX_EMPTY  = 25, /**< UART control register(25) (r/w): Fire IRQ if TX FIFO empty */
  UART_CTRL_IRQ_TX_NHALF  = 26, /**< UART control register(26) (r/w): Fire IRQ if TX FIFO not at least half-full */

  UART_CTRL_RX_OVER       = 30, /**< UART control register(30) (r/-): RX FIFO overflow */
  UART_CTRL_TX_BUSY       = 31  /**< UART control register(31) (r/-): Transmitter busy or TX FIFO not empty */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int  cellrv32_uart_available(cellrv32_uart_t *UARTx);
void cellrv32_uart_setup(cellrv32_uart_t *UARTx, uint32_t baudrate, uint32_t irq_mask);
void cellrv32_uart_enable(cellrv32_uart_t *UARTx);
void cellrv32_uart_disable(cellrv32_uart_t *UARTx);
void cellrv32_uart_rtscts_enable(cellrv32_uart_t *UARTx);
void cellrv32_uart_rtscts_disable(cellrv32_uart_t *UARTx);
void cellrv32_uart_putc(cellrv32_uart_t *UARTx, char c);
int  cellrv32_uart_tx_busy(cellrv32_uart_t *UARTx);
char cellrv32_uart_getc(cellrv32_uart_t *UARTx);
int  cellrv32_uart_char_received(cellrv32_uart_t *UARTx);
char cellrv32_uart_char_received_get(cellrv32_uart_t *UARTx);
void cellrv32_uart_puts(cellrv32_uart_t *UARTx, const char *s);
void cellrv32_uart_printf(cellrv32_uart_t *UARTx, const char *format, ...);
int  cellrv32_uart_scan(cellrv32_uart_t *UARTx, char *buffer, int max_size, int echo);
/**@}*/


#endif // cellrv32_uart_h
