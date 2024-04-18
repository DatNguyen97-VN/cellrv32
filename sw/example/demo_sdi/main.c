// #################################################################################################
// # << CELLRV32 - Serial Data Interface Demo Program >>                                           #
// #################################################################################################


/**********************************************************************//**
 * @file demo_sdi/main.c
 * @author Stephan Nolting
 * @brief SDI test program (direct access to the SDI module).
 **************************************************************************/

#include <cellrv32.h>
#include <string.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/

// Prototypes
void sdi_put(void);
void sdi_get(void);
uint32_t hexstr_to_uint(char *buffer, uint8_t length);


/**********************************************************************//**
 * This program provides an interactive console for the SDI module.
 *
 * @note This program requires UART0 and the SDI to be synthesized.
 *
 * @return Irrelevant.
 **************************************************************************/
int main() {

  char buffer[8];
  int length = 0;

  // capture all exceptions and give debug info via UART
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if UART0 unit is implemented at all
  if (cellrv32_uart0_available() == 0) {
    return 1;
  }

  // intro
  cellrv32_uart0_printf("\n<<< SDI Test Program >>>\n\n");

  // check if SDI unit is implemented at all
  if (cellrv32_sdi_available() == 0) {
    cellrv32_uart0_printf("ERROR! No SDI unit implemented.");
    return 1;
  }

  // info
  cellrv32_uart0_printf("This program allows direct access to the SDI module.\n"
                       "Type 'help' to see the help menu.\n\n");

  // setup SDI module
  cellrv32_sdi_setup(0); // no interrupts

  // Main menu
  for (;;) {
    cellrv32_uart0_printf("SDI_TEST:> ");
    length = cellrv32_uart0_scan(buffer, 15, 1);
    cellrv32_uart0_printf("\n");

    if (!length) { // nothing to be done
      continue;
    }

    // decode input and execute command
    if (!strcmp(buffer, "help")) {
      cellrv32_uart0_printf("Available commands:\n"
                          " help - show this text\n"
                          " put  - write byte to TX buffer\n"
                          " get  - read byte from RX buffer\n"
                          " clr  - clear RX buffer\n");
    }
    else if (!strcmp(buffer, "put")) {
      sdi_put();
    }
    else if (!strcmp(buffer, "get")) {
      sdi_get();
    }
    else if (!strcmp(buffer, "clr")) {
      cellrv32_sdi_rx_clear();
    }
    else {
      cellrv32_uart0_printf("Invalid command. Type 'help' to see all commands.\n");
    }
  }

  return 0;
}


/**********************************************************************//**
 * Write data to SDI TX buffer.
 **************************************************************************/
void sdi_put(void) {

  char terminal_buffer[3];

  cellrv32_uart0_printf("Enter TX data (2 hex chars): 0x");
  cellrv32_uart0_scan(terminal_buffer, sizeof(terminal_buffer), 1);
  uint32_t tx_data = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));

  cellrv32_uart0_printf("\nWriting 0x%x to SDI TX buffer... ", tx_data);

  if (cellrv32_sdi_put((uint8_t)tx_data)) {
    cellrv32_uart0_printf("FAILED! TX buffer is full.\n");
  }
  else {
    cellrv32_uart0_printf("ok\n");
  }
}


/**********************************************************************//**
 * Read data from SDI RX buffer.
 **************************************************************************/
void sdi_get(void) {

  uint8_t rx_data;

  if (cellrv32_sdi_get(&rx_data)) {
    cellrv32_uart0_printf("No RX data available (RX buffer is empty).\n");
  }
  else {
    cellrv32_uart0_printf("Read data: 0x%x\n", (uint32_t)rx_data);
  }
}


/**********************************************************************//**
 * Helper function to convert N hex chars string into uint32_T
 *
 * @param[in,out] buffer Pointer to array of chars to convert into number.
 * @param[in,out] length Length of the conversion string.
 * @return Converted number.
 **************************************************************************/
uint32_t hexstr_to_uint(char *buffer, uint8_t length) {

  uint32_t res = 0, d = 0;
  char c = 0;

  while (length--) {
    c = *buffer++;

    if ((c >= '0') && (c <= '9'))
      d = (uint32_t)(c - '0');
    else if ((c >= 'a') && (c <= 'f'))
      d = (uint32_t)((c - 'a') + 10);
    else if ((c >= 'A') && (c <= 'F'))
      d = (uint32_t)((c - 'A') + 10);
    else
      d = 0;

    res = res + (d << (length*4));
  }

  return res;
}
