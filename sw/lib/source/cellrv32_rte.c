// #################################################################################################
// # << CELLRV32: cellrv32_rte.c - CELLRV32 Runtime Environment >>                                 #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################

/**********************************************************************//**
 * @file cellrv32_rte.c
 * @brief CELLRV32 Runtime Environment.
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_rte.h"

/**********************************************************************//**
 * The >private< trap vector look-up table of the CELLRV32 RTE.
 **************************************************************************/
static uint32_t __cellrv32_rte_vector_lut[CELLRV32_RTE_NUM_TRAPS] __attribute__((unused)); // trap handler vector table

// private functions
static void __attribute__((__interrupt__)) __cellrv32_rte_core(void) __attribute__((aligned(4)));
static void __cellrv32_rte_debug_handler(void);
static void __cellrv32_rte_print_true_false(int state);
static void __cellrv32_rte_print_checkbox(int state);
static void __cellrv32_rte_print_hex_word(uint32_t num);
static void __cellrv32_rte_print_hex_half(uint16_t num);


/**********************************************************************//**
 * Setup CELLRV32 runtime environment.
 *
 * @note This function installs a debug handler for ALL trap sources, which
 * gives detailed information about the trap. Actual handler can be installed afterwards
 * via cellrv32_rte_handler_install(uint8_t id, void (*handler)(void)).
 **************************************************************************/
void cellrv32_rte_setup(void) {

  // configure trap handler base address
  cellrv32_cpu_csr_write(CSR_MTVEC, (uint32_t)(&__cellrv32_rte_core));

  // disable all IRQ channels
  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // clear all pending IRQs
  cellrv32_cpu_csr_write(CSR_MIP, 0);

  // clear BUSKEEPER error flags
  CELLRV32_BUSKEEPER->CTRL = 0;

  // install debug handler for all trap sources
  uint8_t id;
  for (id = 0; id < (sizeof(__cellrv32_rte_vector_lut)/sizeof(__cellrv32_rte_vector_lut[0])); id++) {
    cellrv32_rte_handler_uninstall(id); // this will configure the debug handler
  }
}


/**********************************************************************//**
 * Install trap handler function to CELLRV32 runtime environment.
 *
 * @param[in] id Identifier (type) of the targeted trap. See #CELLRV32_RTE_TRAP_enum.
 * @param[in] handler The actual handler function for the specified trap (function MUST be of type "void function(void);").
 * @return 0 if success, 1 if error (invalid id or targeted trap not supported).
 **************************************************************************/
int cellrv32_rte_handler_install(uint8_t id, void (*handler)(void)) {

  // id valid?
  if ((id >= RTE_TRAP_I_MISALIGNED) && (id <= RTE_TRAP_FIRQ_15)) {
    __cellrv32_rte_vector_lut[id] = (uint32_t)handler; // install handler
    return 0;
  }
  return 1;
}


/**********************************************************************//**
 * Uninstall trap handler function from CELLRV32 runtime environment, which was
 * previously installed via cellrv32_rte_handler_install(uint8_t id, void (*handler)(void)).
 *
 * @param[in] id Identifier (type) of the targeted trap. See #CELLRV32_RTE_TRAP_enum.
 * @return 0 if success, 1 if error (invalid id or targeted trap not supported).
 **************************************************************************/
int cellrv32_rte_handler_uninstall(uint8_t id) {

  // id valid?
  if ((id >= RTE_TRAP_I_MISALIGNED) && (id <= RTE_TRAP_FIRQ_15)) {
    __cellrv32_rte_vector_lut[id] = (uint32_t)(&__cellrv32_rte_debug_handler); // use dummy handler in case the trap is accidentally triggered
    return 0;
  }
  return 1;
}


/**********************************************************************//**
 * This is the [private!] core of the CELLRV32 RTE.
 *
 * @warning When using the the RTE, this function is the ONLY function that uses the 'interrupt' attribute!
 **************************************************************************/
static void __attribute__((__interrupt__)) __attribute__((aligned(4))) __cellrv32_rte_core(void) {

  uint32_t rte_mcause = cellrv32_cpu_csr_read(CSR_MCAUSE);

  // find according trap handler
  uint32_t rte_handler;
  switch (rte_mcause) {
    case TRAP_CODE_I_MISALIGNED: rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_I_MISALIGNED]; break;
    case TRAP_CODE_I_ACCESS:     rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_I_ACCESS]; break;
    case TRAP_CODE_I_ILLEGAL:    rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_I_ILLEGAL]; break;
    case TRAP_CODE_BREAKPOINT:   rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_BREAKPOINT]; break;
    case TRAP_CODE_L_MISALIGNED: rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_L_MISALIGNED]; break;
    case TRAP_CODE_L_ACCESS:     rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_L_ACCESS]; break;
    case TRAP_CODE_S_MISALIGNED: rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_S_MISALIGNED]; break;
    case TRAP_CODE_S_ACCESS:     rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_S_ACCESS]; break;
    case TRAP_CODE_UENV_CALL:    rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_UENV_CALL]; break;
    case TRAP_CODE_MENV_CALL:    rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_MENV_CALL]; break;
    case TRAP_CODE_MSI:          rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_MSI]; break;
    case TRAP_CODE_MTI:          rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_MTI]; break;
    case TRAP_CODE_MEI:          rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_MEI]; break;
    case TRAP_CODE_FIRQ_0:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_0]; break;
    case TRAP_CODE_FIRQ_1:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_1]; break;
    case TRAP_CODE_FIRQ_2:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_2]; break;
    case TRAP_CODE_FIRQ_3:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_3]; break;
    case TRAP_CODE_FIRQ_4:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_4]; break;
    case TRAP_CODE_FIRQ_5:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_5]; break;
    case TRAP_CODE_FIRQ_6:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_6]; break;
    case TRAP_CODE_FIRQ_7:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_7]; break;
    case TRAP_CODE_FIRQ_8:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_8]; break;
    case TRAP_CODE_FIRQ_9:       rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_9]; break;
    case TRAP_CODE_FIRQ_10:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_10]; break;
    case TRAP_CODE_FIRQ_11:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_11]; break;
    case TRAP_CODE_FIRQ_12:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_12]; break;
    case TRAP_CODE_FIRQ_13:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_13]; break;
    case TRAP_CODE_FIRQ_14:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_14]; break;
    case TRAP_CODE_FIRQ_15:      rte_handler = __cellrv32_rte_vector_lut[RTE_TRAP_FIRQ_15]; break;
    default:                     rte_handler = (uint32_t)(&__cellrv32_rte_debug_handler); break;
  }

  // execute handler
  void (*handler_pnt)(void);
  handler_pnt = (void*)rte_handler;
  (*handler_pnt)();

  // compute return address
  // WARNING: some traps might NOT be resumable! (e.g. instruction access fault)
  if (((int32_t)rte_mcause) >= 0) { // modify pc only if not interrupt (MSB cleared)

    uint32_t rte_mepc = cellrv32_cpu_csr_read(CSR_MEPC);

    // get low half word of faulting instruction
    uint32_t rte_trap_inst = (uint32_t)cellrv32_cpu_load_unsigned_half(rte_mepc);

    rte_mepc += 4; // default: faulting instruction is uncompressed
    if (cellrv32_cpu_csr_read(CSR_MISA) & (1 << CSR_MISA_C)) { // C extension implemented?
      if ((rte_trap_inst & 3) != 3) { // faulting instruction is compressed instruction
        rte_mepc -= 2;
      }
    }

    // store new return address
    cellrv32_cpu_csr_write(CSR_MEPC, rte_mepc);
  }
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Debug trap handler, printing various information via UART.
 * @note This function is used by cellrv32_rte_handler_uninstall(void) only.
 **************************************************************************/
static void __cellrv32_rte_debug_handler(void) {

  if (cellrv32_uart0_available() == 0) {
    return; // handler cannot output anything if UART0 is not implemented
  }

  // intro
  cellrv32_uart0_puts("<RTE> ");

  // cause
  uint32_t trap_cause = cellrv32_cpu_csr_read(CSR_MCAUSE);
  switch (trap_cause) {
    case TRAP_CODE_I_MISALIGNED: cellrv32_uart0_puts("Instruction address misaligned"); break;
    case TRAP_CODE_I_ACCESS:     cellrv32_uart0_puts("Instruction access fault"); break;
    case TRAP_CODE_I_ILLEGAL:    cellrv32_uart0_puts("Illegal instruction"); break;
    case TRAP_CODE_BREAKPOINT:   cellrv32_uart0_puts("Breakpoint"); break;
    case TRAP_CODE_L_MISALIGNED: cellrv32_uart0_puts("Load address misaligned"); break;
    case TRAP_CODE_L_ACCESS:     cellrv32_uart0_puts("Load access fault"); break;
    case TRAP_CODE_S_MISALIGNED: cellrv32_uart0_puts("Store address misaligned"); break;
    case TRAP_CODE_S_ACCESS:     cellrv32_uart0_puts("Store access fault"); break;
    case TRAP_CODE_UENV_CALL:    cellrv32_uart0_puts("Environment call from U-mode"); break;
    case TRAP_CODE_MENV_CALL:    cellrv32_uart0_puts("Environment call from M-mode"); break;
    case TRAP_CODE_MSI:          cellrv32_uart0_puts("Machine software IRQ"); break;
    case TRAP_CODE_MTI:          cellrv32_uart0_puts("Machine timer IRQ"); break;
    case TRAP_CODE_MEI:          cellrv32_uart0_puts("Machine external IRQ"); break;
    case TRAP_CODE_FIRQ_0:
    case TRAP_CODE_FIRQ_1:
    case TRAP_CODE_FIRQ_2:
    case TRAP_CODE_FIRQ_3:
    case TRAP_CODE_FIRQ_4:
    case TRAP_CODE_FIRQ_5:
    case TRAP_CODE_FIRQ_6:
    case TRAP_CODE_FIRQ_7:
    case TRAP_CODE_FIRQ_8:
    case TRAP_CODE_FIRQ_9:
    case TRAP_CODE_FIRQ_10:
    case TRAP_CODE_FIRQ_11:
    case TRAP_CODE_FIRQ_12:
    case TRAP_CODE_FIRQ_13:
    case TRAP_CODE_FIRQ_14:
    case TRAP_CODE_FIRQ_15:      cellrv32_uart0_puts("Fast IRQ "); __cellrv32_rte_print_hex_word(trap_cause & 0xf); break;
    default:                     cellrv32_uart0_puts("Unknown trap cause: "); __cellrv32_rte_print_hex_word(trap_cause); break;
  }

  // check if FIRQ
  if ((trap_cause >= TRAP_CODE_FIRQ_0) && (trap_cause <= TRAP_CODE_FIRQ_15)) {
    cellrv32_cpu_csr_clr(CSR_MIP, 1 << trap_cause & 0xf); // clear pending FIRQ
  }
  // check specific cause if bus access fault exception
  else if ((trap_cause == TRAP_CODE_I_ACCESS) || (trap_cause == TRAP_CODE_L_ACCESS) || (trap_cause == TRAP_CODE_S_ACCESS)) {
    uint32_t bus_err = CELLRV32_BUSKEEPER->CTRL;
    if (bus_err & (1<<BUSKEEPER_ERR_FLAG)) { // exception caused by bus system?
      if (bus_err & (1<<BUSKEEPER_ERR_TYPE)) {
        cellrv32_uart0_puts(" [TIMEOUT_ERR]");
      }
      else {
        cellrv32_uart0_puts(" [DEVICE_ERR]");
      }
    }
    else { // exception was not caused by bus system -> has to be caused by PMP rule violation
      cellrv32_uart0_puts(" [PMP_ERR]");
    }
  }

  // instruction address
  cellrv32_uart0_puts(" @ PC=");
  uint32_t mepc = cellrv32_cpu_csr_read(CSR_MEPC);
  __cellrv32_rte_print_hex_word(mepc);

  // additional info
  if (trap_cause == TRAP_CODE_I_ILLEGAL) { // illegal instruction
    cellrv32_uart0_puts(", INST=");
    uint32_t instr_lo = (uint32_t)cellrv32_cpu_load_unsigned_half(mepc);
    uint32_t instr_hi = (uint32_t)cellrv32_cpu_load_unsigned_half(mepc + 2);
    if ((instr_lo & 3) != 3) { // is compressed instruction
      __cellrv32_rte_print_hex_half(instr_lo);
    }
    else {
      __cellrv32_rte_print_hex_word(((uint32_t)instr_hi << 16) | (uint32_t)instr_lo);
    }
  }
  else if ((trap_cause & 0x80000000U) == 0) { // not an interrupt
    cellrv32_uart0_puts(", ADDR=");
    __cellrv32_rte_print_hex_word(cellrv32_cpu_csr_read(CSR_MTVAL));
  }

  // outro
  cellrv32_uart0_puts(" </RTE>\n");
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Print hardware configuration information via UART
 **************************************************************************/
void cellrv32_rte_print_hw_config(void) {

  if (cellrv32_uart0_available() == 0) {
    return; // cannot output anything if UART0 is not implemented
  }

  uint32_t tmp;
  int i;
  char c;

  cellrv32_uart0_printf("\n\n<< CELLRV32 Processor Configuration >>\n");

  // CPU configuration
  cellrv32_uart0_printf("\n====== Core ======\n");

  // general
  cellrv32_uart0_printf("Is simulation:     "); __cellrv32_rte_print_true_false(cellrv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_IS_SIM));
  cellrv32_uart0_printf("Clock speed:       %u Hz\n", CELLRV32_SYSINFO->CLK);
  cellrv32_uart0_printf("On-chip debugger:  "); __cellrv32_rte_print_true_false(CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_OCD));

  // IDs
  cellrv32_uart0_printf("Custom ID:         0x%x\n"
                       "Hart ID:           0x%x\n"
                       "Vendor ID:         0x%x\n"
                       "Architecture ID:   0x%x\n"
                       "Implementation ID: 0x%x",
                       CELLRV32_SYSINFO->CUSTOM_ID,
                       cellrv32_cpu_csr_read(CSR_MHARTID),
                       cellrv32_cpu_csr_read(CSR_MVENDORID),
                       cellrv32_cpu_csr_read(CSR_MARCHID),
                       cellrv32_cpu_csr_read(CSR_MIMPID));

  cellrv32_uart0_printf(" (v");
  cellrv32_rte_print_hw_version();
  cellrv32_uart0_printf(")\n");

  // CPU architecture and endianness
  cellrv32_uart0_printf("Architecture:      ");
  tmp = cellrv32_cpu_csr_read(CSR_MISA);
  tmp = (tmp >> 30) & 0x03;
  if (tmp == 1) {
    cellrv32_uart0_printf("rv32-little");
  }
  else {
    cellrv32_uart0_printf("unknown");
  }

  // CPU extensions
  cellrv32_uart0_printf("\nISA extensions:    ");
  tmp = cellrv32_cpu_csr_read(CSR_MISA);
  for (i=0; i<26; i++) {
    if (tmp & (1 << i)) {
      c = (char)('A' + i);
      cellrv32_uart0_putc(c);
      cellrv32_uart0_putc(' ');
    }
  }

  // Z* CPU extensions
  tmp = cellrv32_cpu_csr_read(CSR_MXISA);
  if (tmp & (1<<CSR_MXISA_ZICSR)) {
    cellrv32_uart0_printf("Zicsr ");
  }
  if (tmp & (1<<CSR_MXISA_ZICNTR)) {
    cellrv32_uart0_printf("Zicntr ");
  }
  if (tmp & (1<<CSR_MXISA_ZICOND)) {
    cellrv32_uart0_printf("Zicond ");
  }
  if (tmp & (1<<CSR_MXISA_ZIFENCEI)) {
    cellrv32_uart0_printf("Zifencei ");
  }
  if (tmp & (1<<CSR_MXISA_ZFINX)) {
    cellrv32_uart0_printf("Zfinx ");
  }
  if (tmp & (1<<CSR_MXISA_ZIHPM)) {
    cellrv32_uart0_printf("Zihpm ");
  }
  if (tmp & (1<<CSR_MXISA_ZMMUL)) {
    cellrv32_uart0_printf("Zmmul ");
  }
  if (tmp & (1<<CSR_MXISA_ZXCFU)) {
    cellrv32_uart0_printf("Zxcfu ");
  }
  if (tmp & (1<<CSR_MXISA_SDEXT)) {
    cellrv32_uart0_printf("Sdext ");
  }
  if (tmp & (1<<CSR_MXISA_SDTRIG)) {
    cellrv32_uart0_printf("Sdtrig ");
  }

  // CPU tuning options
  cellrv32_uart0_printf("\nTuning options:    ");
  if (tmp & (1<<CSR_MXISA_FASTMUL)) {
    cellrv32_uart0_printf("FAST_MUL ");
  }
  if (tmp & (1<<CSR_MXISA_FASTSHIFT)) {
    cellrv32_uart0_printf("FAST_SHIFT ");
  }

  // check physical memory protection
  cellrv32_uart0_printf("\nPhys. Mem. Prot.:  ");
  uint32_t pmp_num_regions = cellrv32_cpu_pmp_get_num_regions();
  if (pmp_num_regions != 0)  {
    cellrv32_uart0_printf("%u region(s), %u bytes minimal granularity, OFF/TOR mode only", pmp_num_regions, cellrv32_cpu_pmp_get_granularity());
  }
  else {
    cellrv32_uart0_printf("not implemented");
  }

  // check hardware performance monitors
  cellrv32_uart0_printf("\nHPM Counters:      ");
  uint32_t hpm_num = cellrv32_cpu_hpm_get_num_counters();
  if (hpm_num != 0) {
    cellrv32_uart0_printf("%u counter(s), %u bit(s) wide", hpm_num, cellrv32_cpu_hpm_get_size());
  }
  else {
    cellrv32_uart0_printf("not implemented");
  }


  // Memory configuration
  cellrv32_uart0_printf("\n\n====== Memory ======\n");

  cellrv32_uart0_printf("Boot configuration:  Boot ");
  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_BOOTLOADER)) {
    cellrv32_uart0_printf("via Bootloader\n");
  }
  else {
    cellrv32_uart0_printf("from memory (@ 0x%x)\n", CELLRV32_SYSINFO->ISPACE_BASE);
  }

  cellrv32_uart0_printf("Instr. base address: 0x%x\n", CELLRV32_SYSINFO->ISPACE_BASE);

  // IMEM
  cellrv32_uart0_printf("Internal IMEM:       ");
  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_MEM_INT_IMEM)) {
    cellrv32_uart0_printf("yes, %u bytes\n", CELLRV32_SYSINFO->IMEM_SIZE);
  }
  else {
    cellrv32_uart0_printf("no\n");
  }

  // DMEM
  cellrv32_uart0_printf("Data base address:   0x%x\n", CELLRV32_SYSINFO->DSPACE_BASE);
  cellrv32_uart0_printf("Internal DMEM:       ");
  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_MEM_INT_DMEM)) {
    cellrv32_uart0_printf("yes, %u bytes\n", CELLRV32_SYSINFO->DMEM_SIZE);
  }
  else {
    cellrv32_uart0_printf("no\n");
  }

  // i-cache
  cellrv32_uart0_printf("Internal i-cache:    ");
  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_ICACHE)) {
    cellrv32_uart0_printf("yes, ");

    uint32_t ic_block_size = (CELLRV32_SYSINFO->CACHE >> SYSINFO_CACHE_IC_BLOCK_SIZE_0) & 0x0F;
    if (ic_block_size) {
      ic_block_size = 1 << ic_block_size;
    }
    else {
      ic_block_size = 0;
    }

    uint32_t ic_num_blocks = (CELLRV32_SYSINFO->CACHE >> SYSINFO_CACHE_IC_NUM_BLOCKS_0) & 0x0F;
    if (ic_num_blocks) {
      ic_num_blocks = 1 << ic_num_blocks;
    }
    else {
      ic_num_blocks = 0;
    }

    uint32_t ic_associativity = (CELLRV32_SYSINFO->CACHE >> SYSINFO_CACHE_IC_ASSOCIATIVITY_0) & 0x0F;
    ic_associativity = 1 << ic_associativity;

    cellrv32_uart0_printf("%u bytes, %u set(s), %u block(s) per set, %u bytes per block", ic_associativity*ic_num_blocks*ic_block_size, ic_associativity, ic_num_blocks, ic_block_size);
    if (ic_associativity == 1) {
      cellrv32_uart0_printf(" (direct-mapped)\n");
    }
    else if (((CELLRV32_SYSINFO->CACHE >> SYSINFO_CACHE_IC_REPLACEMENT_0) & 0x0F) == 1) {
      cellrv32_uart0_printf(" (LRU replacement policy)\n");
    }
    else {
      cellrv32_uart0_printf("\n");
    }
  }
  else {
    cellrv32_uart0_printf("no\n");
  }

  cellrv32_uart0_printf("Ext. bus interface:  ");
  __cellrv32_rte_print_true_false(CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_MEM_EXT));
  cellrv32_uart0_printf("Ext. bus endianness: ");
  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_MEM_EXT_ENDIAN)) {
    cellrv32_uart0_printf("big\n");
  }
  else {
    cellrv32_uart0_printf("little\n");
  }

  // peripherals
  cellrv32_uart0_printf("\n====== Peripherals ======\n");

  tmp = CELLRV32_SYSINFO->SOC;
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_GPIO));    cellrv32_uart0_printf(" GPIO\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_MTIME));   cellrv32_uart0_printf(" MTIME\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_UART0));   cellrv32_uart0_printf(" UART0\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_UART1));   cellrv32_uart0_printf(" UART1\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_SPI));     cellrv32_uart0_printf(" SPI\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_SDI));     cellrv32_uart0_printf(" SDI\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_TWI));     cellrv32_uart0_printf(" TWI\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_PWM));     cellrv32_uart0_printf(" PWM\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_WDT));     cellrv32_uart0_printf(" WDT\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_TRNG));    cellrv32_uart0_printf(" TRNG\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_CFS));     cellrv32_uart0_printf(" CFS\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_NEOLED));  cellrv32_uart0_printf(" NEOLED\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_XIRQ));    cellrv32_uart0_printf(" XIRQ\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_GPTMR));   cellrv32_uart0_printf(" GPTMR\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_XIP));     cellrv32_uart0_printf(" XIP\n");
  __cellrv32_rte_print_checkbox(tmp & (1 << SYSINFO_SOC_IO_ONEWIRE)); cellrv32_uart0_printf(" ONEWIRE\n");
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Private function to print yes or no.
 * @note This function is used by cellrv32_rte_print_hw_config(void) only.
 *
 * @param[in] state Print 'yes' when !=0, print 'no' when 0
 **************************************************************************/
static void __cellrv32_rte_print_true_false(int state) {

  if (state) {
    cellrv32_uart0_puts("yes\n");
  }
  else {
    cellrv32_uart0_puts("no\n");
  }
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Private function to print [x] or [ ].
 * @note This function is used by cellrv32_rte_print_hw_config(void) only.
 *
 * @param[in] state Print '[x]' when !=0, print '[ ]' when 0
 **************************************************************************/
static void __cellrv32_rte_print_checkbox(int state) {

  cellrv32_uart0_putc('[');
  if (state) {
    cellrv32_uart0_putc('x');
  }
  else {
    cellrv32_uart0_putc(' ');
  }
  cellrv32_uart0_putc(']');
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Private function to print 32-bit number
 * as 8-digit hexadecimal value (with "0x" suffix).
 *
 * @param[in] num Number to print as hexadecimal.
 **************************************************************************/
void __cellrv32_rte_print_hex_word(uint32_t num) {

  static const char hex_symbols[16] = "0123456789ABCDEF";

  cellrv32_uart0_puts("0x");

  int i;
  for (i=0; i<8; i++) {
    uint32_t index = (num >> (28 - 4*i)) & 0xF;
    cellrv32_uart0_putc(hex_symbols[index]);
  }
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Private function to print 16-bit number
 * as 4-digit hexadecimal value (with "0x" suffix).
 *
 * @param[in] num Number to print as hexadecimal.
 **************************************************************************/
void __cellrv32_rte_print_hex_half(uint16_t num) {

  static const char hex_symbols[16] = "0123456789ABCDEF";

  cellrv32_uart0_puts("0x");

  int i;
  for (i=0; i<4; i++) {
    uint32_t index = (num >> (12 - 4*i)) & 0xF;
    cellrv32_uart0_putc(hex_symbols[index]);
  }
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Print the processor version in human-readable format.
 **************************************************************************/
void cellrv32_rte_print_hw_version(void) {

  uint32_t i;
  char tmp, cnt;

  if (cellrv32_uart0_available() == 0) {
    return; // cannot output anything if UART0 is not implemented
  }

  for (i=0; i<4; i++) {

    tmp = (char)(cellrv32_cpu_csr_read(CSR_MIMPID) >> (24 - 8*i));

    // serial division
    cnt = 0;
    while (tmp >= 16) {
      tmp = tmp - 16;
      cnt++;
    }

    if (cnt) {
      cellrv32_uart0_putc('0' + cnt);
    }
    cellrv32_uart0_putc('0' + tmp);
    if (i < 3) {
      cellrv32_uart0_putc('.');
    }
  }
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Print project credits
 **************************************************************************/
void cellrv32_rte_print_credits(void) {

  if (cellrv32_uart0_available() == 0) {
    return; // cannot output anything if UART0 is not implemented
  }

  cellrv32_uart0_puts("The CELLRV32 RISC-V Processor, github.com/stnolting/neorv32\n"
                     "(c) 2023 by Dipl.-Ing. Stephan Nolting, BSD 3-Clause License\n\n");
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Print project logo
 **************************************************************************/
void cellrv32_rte_print_logo(void) {
                                                                                                                                        
  const uint16_t logo_data_c[9][7] = {                                                                                                             
    {0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000110000000,0b1100011000110000},
    {0b0011111111101111,0b1111101100000001,0b1000000000111111,0b1100110000001100,0b1111111100011111,0b1110000110000011,0b1111111111111100},
    {0b0110000000011000,0b0000001100000001,0b1000000001100000,0b0110110000001101,0b1000000110110000,0b0011000110001111,0b0000000000001111},
    {0b0110000000011000,0b0000001100000001,0b1000000001100000,0b0110110000001100,0b0000000110000000,0b0110000110000011,0b0001111110001100},
    {0b0110000000011111,0b1111001100000001,0b1000000001111111,0b1100110000001100,0b0001111100000001,0b1000000110001111,0b0001111110001111},
    {0b0110000000011000,0b0000001100000001,0b1000000001100001,0b1000011000011000,0b0000000110000110,0b0000000110000011,0b0001111110001100},
    {0b0110000000011000,0b0000001100000001,0b1000000001100000,0b1100001100110001,0b1000000110011000,0b0000000110001111,0b0000000000001111},
    {0b0011111111101111,0b1111100111111110,0b1111111101100000,0b0110000011000000,0b1111111100111111,0b1111000110000011,0b1111111111111100},
    {0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000000000000,0b0000000110000000,0b1100011000110000}
  };

  int u,v,w;
  uint16_t tmp;
  char c;

  if (cellrv32_uart0_available() == 0) {
    return; // cannot output anything if UART0 is not implemented
  }

  for (u=0; u<9; u++) {
    cellrv32_uart0_puts("\n");
    for (v=0; v<7; v++) {
      tmp = logo_data_c[u][v];
      for (w=0; w<16; w++){
        c = ' ';
        if (((int16_t)tmp) < 0) { // check MSB
          c = '#';
        }
        cellrv32_uart0_putc(c);
        tmp <<= 1;
      }
    }
  }
  cellrv32_uart0_puts("\n");
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Print project license
 **************************************************************************/
void cellrv32_rte_print_license(void) {

  if (cellrv32_uart0_available() == 0) {
    return; // cannot output anything if UART0 is not implemented
  }

  cellrv32_uart0_puts(
    "\n"
    "BSD 3-Clause License\n"
    "\n"
    "Copyright (c) 2023, Stephan Nolting. All rights reserved.\n"
    "\n"
    "Redistribution and use in source and binary forms, with or without modification, are\n"
    "permitted provided that the following conditions are met:\n"
    "\n"
    "1. Redistributions of source code must retain the above copyright notice, this list of\n"
    "   conditions and the following disclaimer.\n"
    "\n"
    "2. Redistributions in binary form must reproduce the above copyright notice, this list of\n"
    "   conditions and the following disclaimer in the documentation and/or other materials\n"
    "   provided with the distribution.\n"
    "\n"
    "3. Neither the name of the copyright holder nor the names of its contributors may be used to\n"
    "   endorse or promote products derived from this software without specific prior written\n"
    "   permission.\n"
    "\n"
    "THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS\n"
    "OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF\n"
    "MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE\n"
    "COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,\n"
    "EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE\n"
    "GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED\n"
    "AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING\n"
    "NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED\n"
    "OF THE POSSIBILITY OF SUCH DAMAGE.\n"
    "\n"
    "\n"
  );
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Get MISA CSR value according to *compiler/toolchain configuration*.
 *
 * @return MISA content according to compiler configuration.
 **************************************************************************/
uint32_t cellrv32_rte_get_compiler_isa(void) {

  uint32_t misa_cc = 0;

#if defined __riscv_atomic || defined __riscv_a
  misa_cc |= 1 << CSR_MISA_A;
#endif

#ifdef __riscv_b
  misa_cc |= 1 << CSR_MISA_B;
#endif

#if defined __riscv_compressed || defined __riscv_c
  misa_cc |= 1 << CSR_MISA_C;
#endif

#if (__riscv_flen == 64) || defined __riscv_d
  misa_cc |= 1 << CSR_MISA_D;
#endif

#ifdef __riscv_32e
  misa_cc |= 1 << CSR_MISA_E;
#else
  misa_cc |= 1 << CSR_MISA_I;
#endif

#if (__riscv_flen == 32) || defined __riscv_f
  misa_cc |= 1 << CSR_MISA_F;
#endif

#if defined __riscv_mul || defined __riscv_m
  misa_cc |= 1 << CSR_MISA_M;
#endif

#if (__riscv_xlen == 32)
  misa_cc |= 1 << CSR_MISA_MXL_LO;
#elif (__riscv_xlen == 64)
  misa_cc |= 2 << CSR_MISA_MXL_LO;
#else
  misa_cc |= 3 << CSR_MISA_MXL_LO;
#endif

  return misa_cc;
}


/**********************************************************************//**
 * CELLRV32 runtime environment: Check required ISA extensions (via compiler flags) against available ISA extensions (via MISA csr).
 *
 * @param[in] silent Show error message (via cellrv32.uart) if isa_sw > isa_hw when = 0.
 * @return MISA content according to compiler configuration.
 **************************************************************************/
int cellrv32_rte_check_isa(int silent) {

  uint32_t misa_sw = cellrv32_rte_get_compiler_isa();
  uint32_t misa_hw = cellrv32_cpu_csr_read(CSR_MISA);

  // mask hardware features that are not used by software
  uint32_t check = misa_hw & misa_sw;

  if (check == misa_sw) {
    return 0;
  }
  else {
    if ((silent == 0) && (cellrv32_uart0_available() != 0)) {
      cellrv32_uart0_printf("\nWARNING! SW_ISA (features required) vs HW_ISA (features available) mismatch!\n"
                          "SW_ISA = 0x%x (compiler flags)\n"
                          "HW_ISA = 0x%x (misa csr)\n\n", misa_sw, misa_hw);
    }
    return 1;
  }
}

