// ###################################################################################################
// # << CELLRV32: cellrv32_uart.c - Universal Asynchronous Receiver/Transmitter (UART) HW Driver >>  #
// ###################################################################################################


/**********************************************************************//**
 * @file cellrv32_uart.c
 * @brief Universal asynchronous receiver/transmitter (UART0/UART1) HW driver source file.
 *
 * @note These functions should only be used if the UART0/UART1 unit was synthesized.
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_uart.h"
#include <string.h>
#include <stdarg.h>

// Private functions
static void __cellrv32_uart_itoa(uint32_t x, char *res) __attribute__((unused)); // GCC: do not output a warning when this variable is unused
static void __cellrv32_uart_tohex(uint32_t x, char *res) __attribute__((unused)); // GCC: do not output a warning when this variable is unused
static void __cellrv32_uart_touppercase(uint32_t len, char *ptr) __attribute__((unused)); // GCC: do not output a warning when this variable is unused


/**********************************************************************//**
 * Check if UART unit was synthesized.
 *
 * @param[in,out] Hardware handle to UART register struct, #cellrv32_uart_t.
 * @return 0 if UART0/1 was not synthesized, 1 if UART0/1 is available.
 **************************************************************************/
int cellrv32_uart_available (cellrv32_uart_t *UARTx) {

  int available = 0;

  if ( ((int)UARTx == CELLRV32_UART0_BASE) && (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_UART0)) ) {
    available = 1;
  }
  if ( ((int)UARTx == CELLRV32_UART1_BASE) && (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_UART1)) ) {
    available = 1;
  }
  return(available);
}


/**********************************************************************//**
 * Reset, configure and enable UART.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @param[in] baudrate Targeted BAUD rate (e.g. 19200).
 * @param[in] irq_mask Interrupt configuration mask (CTRL's irq_* bits).
 **************************************************************************/
void cellrv32_uart_setup(cellrv32_uart_t *UARTx, uint32_t baudrate, uint32_t irq_mask) {

  uint32_t prsc_sel = 0;
  uint32_t baud_div = 0;

  // reset
  UARTx->CTRL = 0;

  // raw clock prescaler
  uint32_t clock = CELLRV32_SYSINFO->CLK; // system clock in Hz
#ifndef make_bootloader // use div instructions
  baud_div = clock / (2*baudrate);
#else // division via repeated subtraction (minimal size, only for bootloader)
  while (clock >= 2*baudrate) {
    clock -= 2*baudrate;
    baud_div++;
  }
#endif

  // find baud prescaler (10-bit wide))
  while (baud_div >= 0x3ffU) {
    if ((prsc_sel == 2) || (prsc_sel == 4))
      baud_div >>= 3;
    else
      baud_div >>= 1;
    prsc_sel++;
  }

  uint32_t tmp = 0;
  tmp |= (uint32_t)(1              & 1U)     << UART_CTRL_EN;
  tmp |= (uint32_t)(prsc_sel       & 3U)     << UART_CTRL_PRSC0;
  tmp |= (uint32_t)((baud_div - 1) & 0x3ffU) << UART_CTRL_BAUD0;
  tmp |= (uint32_t)(irq_mask & (0x1fU << UART_CTRL_IRQ_RX_NEMPTY));

#ifdef UART0_SIM_MODE
#warning UART0_SIM_MODE (primary UART) enabled! Sending all UART0.TX data to text.io simulation output instead of real UART0 transmitter. Use this for simulations only!
  if (((uint32_t)UARTx) == CELLRV32_UART0_BASE) {
    tmp |= 1U << UART_CTRL_SIM_MODE;
  }
#endif

#ifdef UART1_SIM_MODE
#warning UART1_SIM_MODE (secondary UART) enabled! Sending all UART1.TX data to text.io simulation output instead of real UART1 transmitter. Use this for simulations only!
  if (((uint32_t)UARTx) == CELLRV32_UART1_BASE) {
    tmp |= 1U << UART_CTRL_SIM_MODE;
  }
#endif

  UARTx->CTRL = tmp;
}


/**********************************************************************//**
 * Enable UART.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 **************************************************************************/
void cellrv32_uart_enable(cellrv32_uart_t *UARTx) {

  UARTx->CTRL |= ((uint32_t)(1 << UART_CTRL_EN));
}


/**********************************************************************//**
 * Disable UART.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 **************************************************************************/
void cellrv32_uart_disable(cellrv32_uart_t *UARTx) {

  UARTx->CTRL &= ~((uint32_t)(1 << UART_CTRL_EN));
}


/**********************************************************************//**
 * Enable RTS/CTS hardware flow-control.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 **************************************************************************/
void cellrv32_uart_rtscts_enable(cellrv32_uart_t *UARTx) {

  UARTx->CTRL |= ((uint32_t)(1 << UART_CTRL_HWFC_EN));
}


/**********************************************************************//**
 * Disable RTS/CTS hardware flow-control.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 **************************************************************************/
void cellrv32_uart_rtscts_disable(cellrv32_uart_t *UARTx) {

  UARTx->CTRL &= ~((uint32_t)(1 << UART_CTRL_HWFC_EN));
}


/**********************************************************************//**
 * Send single char via UART.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @param[in] c Char to be send.
 **************************************************************************/
void cellrv32_uart_putc(cellrv32_uart_t *UARTx, char c) {

  // wait for previous transfer to finish
  while ((UARTx->CTRL & (1<<UART_CTRL_TX_FULL))); // wait for free space in TX FIFO
  UARTx->DATA = (uint32_t)c;
}


/**********************************************************************//**
 * Check if UART TX is busy (transmitter busy or data left in TX buffer).
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @return 0 if idle, 1 if busy
 **************************************************************************/
int cellrv32_uart_tx_busy(cellrv32_uart_t *UARTx) {

  if (UARTx->CTRL & (1 << UART_CTRL_TX_BUSY)) {  // TX engine busy
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Get char from UART.
 *
 * @note This function is blocking.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @return Received char.
 **************************************************************************/
char cellrv32_uart_getc(cellrv32_uart_t *UARTx) {

  while (1) {
    if (UARTx->CTRL & (1<<UART_CTRL_RX_NEMPTY)) { // data available?
      return (char)UARTx->DATA;
    }
  }
}


/**********************************************************************//**
 * Check if UART has received a char.
 *
 * @note This function is non-blocking.
 * @note Use cellrv32_uart_char_received_get(void) to get the char.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @return 1 when a char has been received, 0 otherwise.
 **************************************************************************/
int cellrv32_uart_char_received(cellrv32_uart_t *UARTx) {

  if (UARTx->CTRL & (1<<UART_CTRL_RX_NEMPTY)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Get a received char from UART.
 *
 * @note This function is non-blocking.
 * @note Should only be used in combination with cellrv32_uart_char_received(void).
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @return Received char.
 **************************************************************************/
char cellrv32_uart_char_received_get(cellrv32_uart_t *UARTx) {

  return (char)(UARTx->DATA);
}


/**********************************************************************//**
 * Print string (zero-terminated) via UART. Print full line break "\r\n" for every '\n'.
 *
 * @note This function is blocking.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @param[in] s Pointer to string.
 **************************************************************************/
void cellrv32_uart_puts(cellrv32_uart_t *UARTx, const char *s) {

  char c = 0;
  while ((c = *s++)) {
    if (c == '\n') {
      cellrv32_uart_putc(UARTx, '\r');
    }
    cellrv32_uart_putc(UARTx, c);
  }
}


/**********************************************************************//**
 * Custom version of 'printf' function using UART.
 *
 * @note This function is blocking.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @param[in] format Pointer to format string.
 *
 * <TABLE>
 * <TR><TD>%s</TD><TD>String (array of chars, zero-terminated)</TD></TR>
 * <TR><TD>%c</TD><TD>Single char</TD></TR>
 * <TR><TD>%d/%i</TD><TD>32-bit signed number, printed as decimal</TD></TR>
 * <TR><TD>%u</TD><TD>32-bit unsigned number, printed as decimal</TD></TR>
 * <TR><TD>%x</TD><TD>32-bit number, printed as 8-char hexadecimal - lower-case</TD></TR>
 * <TR><TD>%X</TD><TD>32-bit number, printed as 8-char hexadecimal - upper-case</TD></TR>
 * <TR><TD>%p</TD><TD>32-bit pointer, printed as 8-char hexadecimal - lower-case</TD></TR>
 * </TABLE>
 **************************************************************************/
void cellrv32_uart_printf(cellrv32_uart_t *UARTx, const char *format, ...) {

  char c, string_buf[11];
  int32_t n;

  va_list a;
  va_start(a, format);

  while ((c = *format++)) {
    if (c == '%') {
      c = *format++;
      switch (c) {
        case 's': // string
          cellrv32_uart_puts(UARTx, va_arg(a, char*));
          break;
        case 'c': // char
          cellrv32_uart_putc(UARTx, (char)va_arg(a, int));
          break;
        case 'i': // 32-bit signed
        case 'd':
          n = (int32_t)va_arg(a, int32_t);
          if (n < 0) {
            n = -n;
            cellrv32_uart_putc(UARTx, '-');
          }
          __cellrv32_uart_itoa((uint32_t)n, string_buf);
          cellrv32_uart_puts(UARTx, string_buf);
          break;
        case 'u': // 32-bit unsigned
          __cellrv32_uart_itoa(va_arg(a, uint32_t), string_buf);
          cellrv32_uart_puts(UARTx, string_buf);
          break;
        case 'x': // 32-bit hexadecimal
        case 'p':
        case 'X':
          __cellrv32_uart_tohex(va_arg(a, uint32_t), string_buf);
          if (c == 'X') {
            __cellrv32_uart_touppercase(11, string_buf);
          }
          cellrv32_uart_puts(UARTx, string_buf);
          break;
        case '%': // escaped percent sign
          cellrv32_uart_putc(UARTx, '%');
          break;
        default: // unsupported format
          cellrv32_uart_putc(UARTx, '%');
          cellrv32_uart_putc(UARTx, c);
          break;
      }
    }
    else {
      if (c == '\n') {
        cellrv32_uart_putc(UARTx, '\r');
      }
      cellrv32_uart_putc(UARTx, c);
    }
  }
  va_end(a);
}


/**********************************************************************//**
 * Simplified custom version of 'scanf' function for UART.
 *
 * @note This function is blocking.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #cellrv32_uart_t.
 * @param[in,out] buffer Pointer to array of chars to store string.
 * @param[in] max_size Maximum number of chars to sample.
 * @param[in] echo Echo UART input when 1.
 * @return Number of chars read.
 **************************************************************************/
int cellrv32_uart_scan(cellrv32_uart_t *UARTx, char *buffer, int max_size, int echo) {

  char c = 0;
  int length = 0;

  while (1) {
    c = cellrv32_uart_getc(UARTx);
    if (c == '\b') { // BACKSPACE
      if (length != 0) {
        if (echo) {
          cellrv32_uart_puts(UARTx, "\b \b"); // delete last char in console
        }
        buffer--;
        length--;
      }
    }
    else if (c == '\r') // carriage return
      break;
    else if ((c >= ' ') && (c <= '~') && (length < (max_size-1))) {
      if (echo) {
        cellrv32_uart_putc(UARTx, c); // echo
      }
      *buffer++ = c;
      length++;
    }
  }
  *buffer = '\0'; // terminate string

  return length;
}


/**********************************************************************//**
 * Private function for 'cellrv32_printf' to convert into decimal.
 *
 * @param[in] x Unsigned input number.
 * @param[in,out] res Pointer for storing the reuslting number string (11 chars).
 **************************************************************************/
static void __cellrv32_uart_itoa(uint32_t x, char *res) {

  static const char numbers[] = "0123456789";
  char buffer1[11];
  uint16_t i, j;

  buffer1[10] = '\0';
  res[10] = '\0';

  // convert
  for (i=0; i<10; i++) {
    buffer1[i] = numbers[x%10];
    x /= 10;
  }

  // delete 'leading' zeros
  for (i=9; i!=0; i--) {
    if (buffer1[i] == '0')
      buffer1[i] = '\0';
    else
      break;
  }

  // reverse
  j = 0;
  do {
    if (buffer1[i] != '\0')
      res[j++] = buffer1[i];
  } while (i--);

  res[j] = '\0'; // terminate result string
}


/**********************************************************************//**
 * Private function for 'cellrv32_printf' to convert into hexadecimal.
 *
 * @param[in] x Unsigned input number.
 * @param[in,out] res Pointer for storing the resulting number string (9 chars).
 **************************************************************************/
static void __cellrv32_uart_tohex(uint32_t x, char *res) {

  static const char symbols[] = "0123456789abcdef";

  int i;
  for (i=0; i<8; i++) { // nibble by nibble
    uint32_t num_tmp = x >> (4*i);
    res[7-i] = (char)symbols[num_tmp & 0x0f];
  }

  res[8] = '\0'; // terminate result string
}


/**********************************************************************//**
 * Private function to cast a string to UPPERCASE.
 *
 * @param[in] len Total length of input string.
 * @param[in,out] ptr Pointer for input/output string.
 **************************************************************************/
static void __cellrv32_uart_touppercase(uint32_t len, char *ptr) {

  char tmp;

  while (len > 0) {
    tmp = *ptr;
    if ((tmp >= 'a') && (tmp <= 'z')) {
      *ptr = tmp - 32;
    }
    ptr++;
    len--;
  }
}


// ================================================================================================
// ================================================================================================


/**********************************************************************//**
 * STDIO: Send char via UART0
 *
 * @param[in] Char to be send.
 * @return Char that has been sent.
 **************************************************************************/
int putchar(int ch) {

  cellrv32_uart_putc(CELLRV32_UART0, (char)ch);
  return ch;
}


/**********************************************************************//**
 * STDIO: Read char from UART0.
 *
 * @return Read char.
 **************************************************************************/
int getchar(void) {

  return (int)cellrv32_uart_getc(CELLRV32_UART0);
}
