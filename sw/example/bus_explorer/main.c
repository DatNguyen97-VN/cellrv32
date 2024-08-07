// #################################################################################################
// # << CELLRV32 - Bus Explorer - Processor Memory Space Inspector >>                              #
// #################################################################################################


/**********************************************************************//**
 * @file bus_explorer/main.c
 * @author Stephan Nolting
 * @brief Interactive memory inspector.
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

// Global variables
char access_size;

// Prototypes
void read_memory(void);
void setup_access(void);
void write_memory(void);
void dump_memory(void);
void hexdump(void);
uint32_t hexstr_to_uint(char *buffer, uint8_t length);
void aux_print_hex_byte(uint8_t byte);


/**********************************************************************//**
 * This program provides an interactive console to read/write memory.
 *
 * @note This program requires the UART to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  char buffer[8];
  int length = 0;

  access_size = 0;

  // check if UART unit is implemented at all
  if (cellrv32_uart0_available() == 0) {
    return 1;
  }


  // capture all exceptions and give debug info via UART
  cellrv32_rte_setup();

  // disable all interrupt sources
  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // intro
  cellrv32_uart0_printf("\n<<< CELLRV32 Bus Explorer >>>\n\n");

  // info
  cellrv32_uart0_printf("This program allows to read/write/dump memory space by hand.\n"
                       "Type 'help' to see the help menu.\n\n");

  // Main menu
  for (;;) {
    cellrv32_uart0_printf("BUS_EXPLORER:> ");
    length = cellrv32_uart0_scan(buffer, 8, 1);
    cellrv32_uart0_printf("\n");

    if (!length) // nothing to be done
     continue;

    // decode input and execute command
    if (!strcmp(buffer, "help")) {
      cellrv32_uart0_printf("Available commands:\n"
                          " > help  - show this text\n"
                          " > setup - configure memory access width (byte,half,word)\n"
                          " > read  - read from address (byte,half,word)\n"
                          " > write - write to address (byte,half,word)\n"
                          " > dump  - dump several bytes/halfs/words from base address\n"
                          " > hex   - hex dump (bytes + ASCII) from base address\n");
    }

    else if (!strcmp(buffer, "setup")) {
      setup_access();
    }

    else if (!strcmp(buffer, "read")) {
      read_memory();
    }

    else if (!strcmp(buffer, "write")) {
      write_memory();
    }

    else if (!strcmp(buffer, "dump")) {
      dump_memory();
    }

    else if (!strcmp(buffer, "hex")) {
      hexdump();
    }

    else {
      cellrv32_uart0_printf("Invalid command. Type 'help' to see all commands.\n");
    }
  }

  return 0;
}


/**********************************************************************//**
 * Configure memory access size
 **************************************************************************/
void setup_access(void) {

  cellrv32_uart0_printf("Select data size (press 'x' to abort):\n"
                       " 'b' - byte, 8-bit, unsigned\n"
                       " 'h' - half-word, 16-bit, unsigned\n"
                       " 'w' - word, 32-bit, unsigned\n");

  while(1) {
    cellrv32_uart0_printf("selection: ");
    char tmp = cellrv32_uart0_getc();
    cellrv32_uart0_putc(tmp);
    if ((tmp == 'b') || (tmp == 'h') || (tmp == 'w')) {
      access_size = tmp;
      cellrv32_uart0_printf("\n");
      return;
    }
    else if (tmp == 'x') {
      cellrv32_uart0_printf("\n");
      return;
    }
    else {
      cellrv32_uart0_printf("\nInvalid selection!\n");
    }
  }
}


/**********************************************************************//**
 * Read from memory address
 **************************************************************************/
void read_memory(void) {

  char terminal_buffer[16];

  if (access_size == 0) {
    cellrv32_uart0_printf("Configure data size using 'setup' first.\n");
    return;
  }

  // enter address
  cellrv32_uart0_printf("Enter address (8 hex chars): 0x");
  cellrv32_uart0_scan(terminal_buffer, 8+1, 1); // 8 hex chars for address plus '\0'
  register uint32_t mem_address = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));

  // perform read access
  cellrv32_uart0_printf("\n[0x%x] => ", mem_address);

  cellrv32_cpu_csr_write(CSR_MCAUSE, 0);

  uint8_t mem_data_b = 0;
  uint16_t mem_data_h = 0;
  uint32_t mem_data_w = 0;
  if (access_size == 'b') { mem_data_b = (uint32_t)cellrv32_cpu_load_unsigned_byte(mem_address); }
  if (access_size == 'h') { mem_data_h = (uint32_t)cellrv32_cpu_load_unsigned_half(mem_address); }
  if (access_size == 'w') { mem_data_w = (uint32_t)cellrv32_cpu_load_unsigned_word(mem_address); }

  // show memory content if there was no exception
  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == 0) {
    cellrv32_uart0_printf("0x");
    if (access_size == 'b') {
      aux_print_hex_byte(mem_data_b);
    }
    if (access_size == 'h') {
      aux_print_hex_byte((uint8_t)(mem_data_h >>  8));
      aux_print_hex_byte((uint8_t)(mem_data_h >>  0));
    }
    if (access_size == 'w') {
      aux_print_hex_byte((uint8_t)(mem_data_w >> 24));
      aux_print_hex_byte((uint8_t)(mem_data_w >> 16));
      aux_print_hex_byte((uint8_t)(mem_data_w >>  8));
      aux_print_hex_byte((uint8_t)(mem_data_w >>  0));
    }
  } else {cellrv32_uart0_printf("Failed ...");}

  cellrv32_uart0_printf("\n");
}


/**********************************************************************//**
 * Write to memory address
 **************************************************************************/
void write_memory(void) {

  char terminal_buffer[16];

  if (access_size == 0) {
    cellrv32_uart0_printf("Configure data size using 'setup' first.\n");
    return;
  }

  // enter address
  cellrv32_uart0_printf("Enter address (8 hex chars): 0x");
  cellrv32_uart0_scan(terminal_buffer, 8+1, 1); // 8 hex chars for address plus '\0'
  uint32_t mem_address = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));

  // enter data
  uint8_t mem_data_b = 0;
  uint16_t mem_data_h = 0;
  uint32_t mem_data_w = 0;
  if (access_size == 'b') {
    cellrv32_uart0_printf("\nEnter data (2 hex chars): 0x");
    cellrv32_uart0_scan(terminal_buffer, 2+1, 1); // 2 hex chars for address plus '\0'
    mem_data_b = (uint8_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));
    cellrv32_uart0_printf("\n[0x%x] <= 0x", mem_address);
    aux_print_hex_byte(mem_data_b);
  }
  if (access_size == 'h') {
    cellrv32_uart0_printf("\nEnter data (4 hex chars): 0x");
    cellrv32_uart0_scan(terminal_buffer, 4+1, 1); // 4 hex chars for address plus '\0'
    mem_data_h = (uint16_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));
    cellrv32_uart0_printf("\n[0x%x] <= 0x", mem_address);
    aux_print_hex_byte((uint8_t)(mem_data_h >> 8));
    aux_print_hex_byte((uint8_t)(mem_data_h >> 0));
  }
  if (access_size == 'w') {
    cellrv32_uart0_printf("\nEnter data (8 hex chars): 0x");
    cellrv32_uart0_scan(terminal_buffer, 8+1, 1); // 8 hex chars for address plus '\0'
    mem_data_w = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));
    cellrv32_uart0_printf("\n[0x%x] <= 0x", mem_address);
    aux_print_hex_byte((uint8_t)(mem_data_w >> 24));
    aux_print_hex_byte((uint8_t)(mem_data_w >> 16));
    aux_print_hex_byte((uint8_t)(mem_data_w >> 8));
    aux_print_hex_byte((uint8_t)(mem_data_w >> 0));
  }

  // perform write access
  if (access_size == 'b') { cellrv32_cpu_store_unsigned_byte(mem_address, mem_data_b); }
  if (access_size == 'h') { cellrv32_cpu_store_unsigned_half(mem_address, mem_data_h); }
  if (access_size == 'w') { cellrv32_cpu_store_unsigned_word(mem_address, mem_data_w); }

  cellrv32_uart0_printf("\n");
}


/**********************************************************************//**
 * Read several bytes/halfs/word from memory base address
 **************************************************************************/
void dump_memory(void) {

  char terminal_buffer[16];

  if (access_size == 0) {
    cellrv32_uart0_printf("Configure data size using 'setup' first.\n");
    return;
  }

  // enter base address
  cellrv32_uart0_printf("Enter base address (8 hex chars): 0x");
  cellrv32_uart0_scan(terminal_buffer, 8+1, 1); // 8 hex chars for address plus '\0'
  uint32_t mem_address = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));

  cellrv32_uart0_printf("\nPress key to start dumping. Press any key to abort.\n");

  cellrv32_uart0_getc(); // wait for key

  // perform read accesses
  while(cellrv32_uart0_char_received() == 0) {

    cellrv32_uart0_printf("[0x%x] = ", mem_address);

    cellrv32_cpu_csr_write(CSR_MCAUSE, 0);

    uint8_t mem_data_b = 0;
    uint16_t mem_data_h = 0;
    uint32_t mem_data_w = 0;
    if (access_size == 'b') { mem_data_b = (uint32_t)cellrv32_cpu_load_unsigned_byte(mem_address); }
    if (access_size == 'h') { mem_data_h = (uint32_t)cellrv32_cpu_load_unsigned_half(mem_address); }
    if (access_size == 'w') { mem_data_w = (uint32_t)cellrv32_cpu_load_unsigned_word(mem_address); }

    // show memory content if there was no exception
    if (cellrv32_cpu_csr_read(CSR_MCAUSE) == 0) {
      cellrv32_uart0_printf("0x");
      if (access_size == 'b') {
        aux_print_hex_byte(mem_data_b);
      }
      if (access_size == 'h') {
        aux_print_hex_byte((uint8_t)(mem_data_h >>  8));
        aux_print_hex_byte((uint8_t)(mem_data_h >>  0));
      }
      if (access_size == 'w') {
        aux_print_hex_byte((uint8_t)(mem_data_w >> 24));
        aux_print_hex_byte((uint8_t)(mem_data_w >> 16));
        aux_print_hex_byte((uint8_t)(mem_data_w >>  8));
        aux_print_hex_byte((uint8_t)(mem_data_w >>  0));
      }
      cellrv32_uart0_printf("\n");
    }
    else {
     break;
    }

    if (access_size == 'b') {
      mem_address += 1;
    }
    else if (access_size == 'h') {
      mem_address += 2;
    }
    else if (access_size == 'w') {
      mem_address += 4;
    }

  }
  cellrv32_uart0_char_received_get(); // clear UART rx buffer
  cellrv32_uart0_printf("\n");
}


/**********************************************************************//**
 * Make pretty hexadecimal + ASCII dump (byte-wise)
 **************************************************************************/
void hexdump(void) {

  char terminal_buffer[16];

  // enter base address
  cellrv32_uart0_printf("Enter base address (8 hex chars): 0x");
  cellrv32_uart0_scan(terminal_buffer, 8+1, 1); // 8 hex chars for address plus '\0'
  uint32_t mem_address = (uint32_t)hexstr_to_uint(terminal_buffer, strlen(terminal_buffer));

  cellrv32_uart0_printf("\nPress key to start dumping. Press any key to abort.\n");
  cellrv32_uart0_getc(); // wait for key

  // start at 16-byte boundary
  mem_address &= 0xfffffff0UL;

  uint8_t tmp;
  uint8_t line[16];
  uint32_t i;

  cellrv32_cpu_csr_write(CSR_MCAUSE, 0);

  cellrv32_uart0_printf("\n");
  while(cellrv32_uart0_char_received() == 0) {

    cellrv32_uart0_printf("0x%x |", mem_address);

    // get 16 bytes
    for (i=0; i<16; i++) {
      line[i] = cellrv32_cpu_load_unsigned_byte(mem_address + i);
      if (cellrv32_cpu_csr_read(CSR_MCAUSE) != 0) {
        return;
      }
    }

    // print 16 bytes as hexadecimal
    for (i=0; i<16; i++) {
      cellrv32_uart0_putc(' ');
      aux_print_hex_byte(line[i]);
    }

    cellrv32_uart0_printf(" | ");

    // print 16 bytes as ASCII
    for (i=0; i<16; i++) {
      tmp = line[i];
      if ((tmp < 32) || (tmp > 126)) { // printable?
        tmp = '.';
      }
      cellrv32_uart0_putc((char)tmp);
    }

    cellrv32_uart0_printf("\n");
    mem_address += 16;

  }
  cellrv32_uart0_char_received_get(); // clear UART rx buffer
  cellrv32_uart0_printf("\n");
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


/**********************************************************************//**
 * Print HEX byte.
 *
 * @param[in] byte Byte to be printed as 2-cahr hex value.
 **************************************************************************/
void aux_print_hex_byte(uint8_t byte) {

  static const char symbols[] = "0123456789abcdef";

  cellrv32_uart0_putc(symbols[(byte >> 4) & 0x0f]);
  cellrv32_uart0_putc(symbols[(byte >> 0) & 0x0f]);
}
