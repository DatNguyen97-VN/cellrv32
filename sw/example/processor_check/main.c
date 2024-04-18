// #################################################################################################
// # << CELLRV32 - Processor Test Program >>                                                       #
// #################################################################################################


/**********************************************************************//**
 * @file processor_check/main.c
 * @author Stephan Nolting
 * @brief CPU/Processor test program.
 **************************************************************************/

#include <cellrv32.h>
#include <string.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE           (19200)
//** Reachable unaligned address */
#define ADDR_UNALIGNED_1    (0x00000001)
//** Reachable unaligned address */
#define ADDR_UNALIGNED_2    (0x00000002)
//** Unreachable word-aligned address */
#define ADDR_UNREACHABLE    (IO_BASE_ADDRESS-4)
//**Read-only word-aligned address */
#define ADDR_READONLY       ((uint32_t)&CELLRV32_SYSINFO->CLK)
//** external memory base address */
#define EXT_MEM_BASE        (0xF0000000)
/**@}*/


/**********************************************************************//**
 * @name UART print macros
 **************************************************************************/
/**@{*/
//** for simulation only! */
#ifdef SUPPRESS_OPTIONAL_UART_PRINT
//** print standard output to UART0 */
#define PRINT_STANDARD(...)
//** print critical output to UART1 */
#define PRINT_CRITICAL(...) cellrv32_uart1_printf(__VA_ARGS__)
#else
//** print standard output to UART0 */
#define PRINT_STANDARD(...) cellrv32_uart0_printf(__VA_ARGS__)
//** print critical output to UART0 */
#define PRINT_CRITICAL(...) cellrv32_uart0_printf(__VA_ARGS__)
#endif
/**@}*/


// Prototypes
void sim_irq_trigger(uint32_t sel);
void global_trap_handler(void);
void xirq_trap_handler0(void);
void xirq_trap_handler1(void);
void test_ok(void);
void test_fail(void);

// MCAUSE value that will be NEVER set by the hardware
const uint32_t mcause_never_c = 0x80000000U; // = reserved

// Global variables (also test initialization of global vars here)
/// Global counter for failing tests
int cnt_fail = 0;
/// Global counter for successful tests
int cnt_ok   = 0;
/// Global counter for total number of tests
int cnt_test = 0;
/// Global number of available HPMs
uint32_t num_hpm_cnts_global = 0;
/// XIRQ trap handler acknowledge
uint32_t xirq_trap_handler_ack = 0;

/// Variable to test store accesses
volatile uint32_t store_access_addr[2];

/// Variable to test PMP
volatile uint32_t pmp_access_addr;

/// Number of implemented PMP regions
uint32_t pmp_num_regions;


/**********************************************************************//**
 * High-level CPU/processor test program.
 *
 * @note Applications has to be compiler with <USER_FLAGS+=-DRUN_CPUTEST>
 * @warning This test is intended for simulation only.
 * @warning This test requires all optional extensions/modules to be enabled.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  uint32_t tmp_a, tmp_b;
  uint8_t id;

  // disable machine-mode interrupts
  cellrv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);

  // setup UARTs at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);
  CELLRV32_UART1->CTRL = 0;
  CELLRV32_UART1->CTRL = CELLRV32_UART0->CTRL;

#ifdef SUPPRESS_OPTIONAL_UART_PRINT
  cellrv32_uart0_disable(); // do not generate any UART0 output
#endif

// Disable processor_check compilation by default
#ifndef RUN_CHECK
  #warning processor_check HAS NOT BEEN COMPILED! Use >>make USER_FLAGS+=-DRUN_CHECK clean_all exe<< to compile it.

  // inform the user if you are actually executing this
  PRINT_CRITICAL("ERROR! processor_check has not been compiled. Use >>make USER_FLAGS+=-DRUN_CHECK clean_all exe<< to compile it.\n");

  return 1;
#endif


  // setup RTE
  // -----------------------------------------------
  cellrv32_rte_setup(); // this will install a full-detailed debug handler for ALL traps
  int install_err = 0;
  // initialize ALL provided trap handler (overriding the default debug handlers)
  for (id=0; id<CELLRV32_RTE_NUM_TRAPS; id++) {
    install_err += cellrv32_rte_handler_install(id, global_trap_handler);
  }
  if (install_err) {
    PRINT_CRITICAL("RTE fail!\n");
    return 1;
  }


  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // intro
  PRINT_STANDARD("\n<< PROCESSOR CHECK >>\n");

  // prepare (performance) counters
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, 0); // enable counter auto increment (ALL counters)
  cellrv32_cpu_csr_write(CSR_MCOUNTEREN, 7); // allow access from user-mode code to standard counters only

  // set CMP of machine system timer MTIME to max to prevent an IRQ
  cellrv32_mtime_set_timecmp(-1);
  cellrv32_mtime_set_time(0);

  // get number of implemented PMP regions
  pmp_num_regions = cellrv32_cpu_pmp_get_num_regions();


  // fancy intro
  // -----------------------------------------------
  // show CELLRV32 ASCII logo
  cellrv32_rte_print_logo();

  // show project credits
  cellrv32_rte_print_credits();

  // show full hardware configuration report
  cellrv32_rte_print_hw_config();


  // **********************************************************************************************
  // Run CPU and SoC tests
  // **********************************************************************************************

  // tests intro
  PRINT_STANDARD("\nStarting tests...\n\n");

  // clear testbench IRQ triggers
  sim_irq_trigger(0);

  // clear all interrupts, enable only where needed
  cellrv32_cpu_csr_write(CSR_MIE, 0);
  cellrv32_cpu_csr_write(CSR_MIP, 0);

  // enable machine-mode interrupts
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);


  // ----------------------------------------------------------
  // Setup PMP for tests
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Initial PMP setup ", cnt_test);

  // check if PMP is already locked
  tmp_a = cellrv32_cpu_csr_read(CSR_PMPCFG0);
  if ((tmp_a & ((1 << PMPCFG_L) << 0*8)) ||
      (tmp_a & ((1 << PMPCFG_L) << 1*8)) ||
      (tmp_a & ((1 << PMPCFG_L) << 2*8)) ||
      (tmp_a & ((1 << PMPCFG_L) << 3*8))) {
    PRINT_CRITICAL("\nERROR! PMP locked!\n");
    return 1;
  }

  if (pmp_num_regions >= 4) { // sufficient regions for tests
    cnt_test++;

    // full access for M & U mode
    // use entries 2 & 3 so we can use entries 0 & 1 later on for higher-prioritized configurations
    tmp_a  = cellrv32_cpu_pmp_configure_region(0, 0x00000000, (PMP_OFF << PMPCFG_A_LSB));
    tmp_a  = cellrv32_cpu_pmp_configure_region(1, 0x00000000, (PMP_OFF << PMPCFG_A_LSB));
    tmp_a  = cellrv32_cpu_pmp_configure_region(2, 0x00000000, (PMP_OFF << PMPCFG_A_LSB));
    tmp_a += cellrv32_cpu_pmp_configure_region(3, 0xFFFFFFFF, (PMP_TOR << PMPCFG_A_LSB) | (1 << PMPCFG_L)  | (1 << PMPCFG_R) | (1 << PMPCFG_W) | (1 << PMPCFG_X));

    if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c) && (tmp_a == 0)) {
      test_ok();
    }
    else {
      test_fail();
    }
  }
  else if ((pmp_num_regions > 0) && (pmp_num_regions < 4)) {
    PRINT_CRITICAL("\nERROR! Insufficient PMP regions!\n");
    return 1;
  }


  // ----------------------------------------------------------
  // Test fence instructions
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FENCE(.I) ", cnt_test);

  cnt_test++;

  asm volatile ("fence");
  if (cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZIFENCEI)) {
    asm volatile ("fence.i");
  }

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test performance counter: setup as many events and counters as possible
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Setup HPM events ", cnt_test);

  num_hpm_cnts_global = cellrv32_cpu_hpm_get_num_counters();

  if (num_hpm_cnts_global != 0) {
    cnt_test++;

    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER3,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT3,  1 << HPMCNT_EVENT_CIR);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER4,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT4,  1 << HPMCNT_EVENT_WAIT_IF);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER5,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT5,  1 << HPMCNT_EVENT_WAIT_II);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER6,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT6,  1 << HPMCNT_EVENT_WAIT_MC);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER7,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT7,  1 << HPMCNT_EVENT_LOAD);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER8,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT8,  1 << HPMCNT_EVENT_STORE);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER9,  0); cellrv32_cpu_csr_write(CSR_MHPMEVENT9,  1 << HPMCNT_EVENT_WAIT_LS);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER10, 0); cellrv32_cpu_csr_write(CSR_MHPMEVENT10, 1 << HPMCNT_EVENT_JUMP);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER11, 0); cellrv32_cpu_csr_write(CSR_MHPMEVENT11, 1 << HPMCNT_EVENT_BRANCH);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER12, 0); cellrv32_cpu_csr_write(CSR_MHPMEVENT12, 1 << HPMCNT_EVENT_TBRANCH);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER13, 0); cellrv32_cpu_csr_write(CSR_MHPMEVENT13, 1 << HPMCNT_EVENT_TRAP);
    cellrv32_cpu_csr_write(CSR_MHPMCOUNTER14, 0); cellrv32_cpu_csr_write(CSR_MHPMEVENT14, 1 << HPMCNT_EVENT_ILLEGAL);

    cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, 0); // enable all counters

    // make sure there was no exception
    if (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c) {
      test_ok();
    }
    else {
      test_fail();
    }
  }
  else {
    PRINT_STANDARD("[skipped, n.a.]\n");
  }


  // ----------------------------------------------------------
  // Test standard RISC-V performance counter [m]cycle[h]
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] cycle counter ", cnt_test);

  cnt_test++;

  // make sure counter is enabled
  asm volatile ("csrci %[addr], %[imm]" : : [addr] "i" (CSR_MCOUNTINHIBIT), [imm] "i" (1<<CSR_MCOUNTINHIBIT_CY));

  // prepare overflow
  cellrv32_cpu_set_mcycle(0x00000000FFFFFFFFULL);

  asm volatile ("nop"); // counter LOW should overflow here

  // get current cycle counter HIGH
  tmp_a = cellrv32_cpu_csr_read(CSR_MCYCLEH);

  // make sure cycle counter high has incremented and there was no exception during access
  if ((tmp_a == 1) && (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c)) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test standard RISC-V performance counter [m]instret[h]
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] instret counter ", cnt_test);

  cnt_test++;

  // make sure counter is enabled
  asm volatile ("csrci %[addr], %[imm]" : : [addr] "i" (CSR_MCOUNTINHIBIT), [imm] "i" (1<<CSR_MCOUNTINHIBIT_IR));

  // prepare overflow
  cellrv32_cpu_set_minstret(0x00000000FFFFFFFFULL);

  asm volatile ("nop"); // counter LOW should overflow here

  // get instruction counter HIGH
  tmp_a = cellrv32_cpu_csr_read(CSR_INSTRETH);

  // make sure instruction counter high has incremented and there was no exception during access
  if ((tmp_a == 1) && (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c)) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test mcountinhibt: inhibit auto-inc of [m]cycle
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] mcountinhibt.cy CSR ", cnt_test);

  cnt_test++;

  // inhibit [m]cycle CSR
  tmp_a = cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT);
  tmp_a |= (1<<CSR_MCOUNTINHIBIT_CY); // inhibit cycle counter auto-increment
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, tmp_a);

  // get current cycle counter
  tmp_a = cellrv32_cpu_csr_read(CSR_CYCLE);

  // wait some time to have a nice "increment" (there should be NO increment at all!)
  asm volatile ("nop");

  tmp_b = cellrv32_cpu_csr_read(CSR_CYCLE);

  // make sure instruction counter has NOT incremented and there was no exception during access
  if ((tmp_a == tmp_b) && (tmp_a != 0) && (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c)) {
    test_ok();
  }
  else {
    test_fail();
  }

  // re-enable [m]cycle CSR
  tmp_a = cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT);
  tmp_a &= ~(1<<CSR_MCOUNTINHIBIT_CY); // clear inhibit of cycle counter auto-increment
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, tmp_a);


  // ----------------------------------------------------------
  // Execute MRET in U-mode (has to trap!)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] MRET in U-mode ", cnt_test);

  cnt_test++;

  // switch to user mode (hart will be back in MACHINE mode when trap handler returns)
  cellrv32_cpu_goto_user_mode();
  {
    asm volatile ("mret");
  }

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // External memory interface test
  // (and iCache block-/word-wise error check)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Ext. memory access (@0x%x) ", cnt_test, (uint32_t)EXT_MEM_BASE);

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_MEM_EXT)) {
    cnt_test++;

    // clear scratch CSR
    cellrv32_cpu_csr_write(CSR_MSCRATCH, 0);

    // setup test program in external memory
    cellrv32_cpu_store_unsigned_word((uint32_t)EXT_MEM_BASE+0, 0x3407D073); // csrwi mscratch, 15
    cellrv32_cpu_store_unsigned_word((uint32_t)EXT_MEM_BASE+4, 0x00008067); // ret (32-bit)

    // execute program
    asm volatile ("fence.i"); // flush i-cache
    tmp_a = (uint32_t)EXT_MEM_BASE; // call the dummy sub program
    asm volatile ("jalr ra, %[input_i]" :  : [input_i] "r" (tmp_a));

    if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c) && // make sure there was no exception
        (cellrv32_cpu_csr_read(CSR_MSCRATCH) == 15)) { // make sure the program was executed in the right way
      test_ok();
    }
    else {
      test_fail();
    }
  }
  else {
    PRINT_STANDARD("[skipped, n.a.]\n");
  }


  // ----------------------------------------------------------
  // Illegal CSR access
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Illegal CSR ", cnt_test);

  cnt_test++;

  tmp_a = cellrv32_cpu_csr_read(CSR_DSCRATCH0); // only accessible in debug mode

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Write-access to read-only CSR
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Read-only CSR write ", cnt_test);

  cnt_test++;

  cellrv32_cpu_csr_write(CSR_CYCLE, 0); // cycle CSR is read-only

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // No "real" CSR write access (because rs1 = r0)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Read-only CSR 'no-write' (rs1=x0) access ", cnt_test);

  cnt_test++;

  // cycle CSR is read-only, but no actual write is performed because rs1=r0
  // -> should cause no exception
  asm volatile ("csrrs zero, cycle, zero");

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Unaligned instruction address
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] I_ALG (instr. align) EXC ", cnt_test);

  // skip if C-mode is implemented
  if ((cellrv32_cpu_csr_read(CSR_MISA) & (1<<CSR_MISA_C)) == 0) {

    cnt_test++;

    // call unaligned address
    ((void (*)(void))ADDR_UNALIGNED_2)();
    asm volatile ("nop");

    if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_MISALIGNED) {
      test_ok();
    }
    else {
      test_fail();
    }

  }
  else {
    PRINT_STANDARD("[skipped, n.a. with C-ext]\n");
  }


  // ----------------------------------------------------------
  // Instruction access fault
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] I_ACC (instr. bus access) EXC ", cnt_test);
  cnt_test++;

  // put two "ret" instructions to the beginning of the external memory module
  cellrv32_cpu_store_unsigned_word((uint32_t)EXT_MEM_BASE+0, 0x00008067); // exception handler hack will see this instruction as exception source
  cellrv32_cpu_store_unsigned_word((uint32_t)EXT_MEM_BASE+4, 0x00008067); // and will try to resume execution here

  // jump to beginning of external memory minus 4 bytes
  // this will cause an instruction access fault as there is no module responding to the fetch request
  // the exception handler will try to resume at the instruction 4 bytes ahead, which is the "ret" we just created
  asm volatile ("fence.i"); // flush i-cache
  tmp_a = ((uint32_t)EXT_MEM_BASE) - 4;
  asm volatile ("jalr ra, %[input_i]" :  : [input_i] "r" (tmp_a));

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ACCESS) && // correct exception cause
      (cellrv32_cpu_csr_read(CSR_MTVAL) == tmp_a))  { // correct trap value (address of instruction that caused ifetch error)
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Illegal instruction
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] I_ILL (illegal instr.) EXC ", cnt_test);

  cnt_test++;

  // clear mstatus.mie and set mstatus.mpie
  cellrv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MPIE);

  // illegal 32-bit instruction (MRET with incorrect opcode)
  asm volatile (".align 4 \n"
                ".word 0x3020007f");

  // make sure this has caused an illegal exception
  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) && // illegal instruction exception
      ((cellrv32_cpu_csr_read(CSR_MSTATUS) & (1 << CSR_MSTATUS_MIE)) == 0)) { // MIE should still be cleared
    test_ok();
  }
  else {
    test_fail();
  }

  // reenable machine-mode interrupts
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);


  // ----------------------------------------------------------
  // Illegal compressed instruction
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] CI_ILL (illegal compr. instr.) EXC ", cnt_test);

  // skip if C-mode is not implemented
  if ((cellrv32_cpu_csr_read(CSR_MISA) & (1<<CSR_MISA_C))) {

    cnt_test++;

    // illegal 16-bit instruction (official UNIMP instruction)
    asm volatile (".align 2     \n"
                  ".half 0x0001 \n" // NOP
                  ".half 0x0000");  // UNIMP

    if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
      test_ok();
    }
    else {
      test_fail();
    }
  }
  else {
    PRINT_STANDARD("[skipped, n.a. with C-ext]\n");
  }


  // ----------------------------------------------------------
  // Breakpoint instruction
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] BREAK EXC ", cnt_test);

  // skip on real hardware since ebreak will make problems when running this test program via gdb
  if (CELLRV32_SYSINFO->SOC & (1<<SYSINFO_SOC_IS_SIM)) {
    cnt_test++;

    asm volatile ("ebreak");

    if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_BREAKPOINT) {
      test_ok();
    }
    else {
      test_fail();
    }
  }
  else {
    PRINT_STANDARD("[skipped]\n");
  }


  // ----------------------------------------------------------
  // Unaligned load address
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] L_ALG (load align) EXC ", cnt_test);
  cnt_test++;

  // load from unaligned address
  asm volatile ("li %[da], 0xcafe1230 \n" // initialize destination register with known value
                "lw %[da], 0(%[ad])     " // must not update destination register to to exception
                : [da] "=r" (tmp_b) : [ad] "r" (ADDR_UNALIGNED_1));

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_L_MISALIGNED) &&
      (cellrv32_cpu_csr_read(CSR_MTVAL) == ADDR_UNALIGNED_1) &&
      (tmp_b == 0xcafe1230)) { // make sure dest. reg is not updated
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Load access fault
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] L_ACC (load access) EXC ", cnt_test);
  cnt_test++;

  tmp_a = (1 << BUSKEEPER_ERR_FLAG) | (1 << BUSKEEPER_ERR_TYPE);

  // load from unreachable aligned address
  asm volatile ("li %[da], 0xcafe1230 \n" // initialize destination register with known value
                "lw %[da], 0(%[ad])     " // must not update destination register to to exception
                : [da] "=r" (tmp_b) : [ad] "r" (ADDR_UNREACHABLE));

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_L_ACCESS) && // load bus access error exception
      (cellrv32_cpu_csr_read(CSR_MTVAL) == ADDR_UNREACHABLE) &&
      (tmp_b == 0xcafe1230) && // make sure dest. reg is not updated
      (CELLRV32_BUSKEEPER->CTRL = tmp_a)) { // buskeeper: error flag + timeout error
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Unaligned store address
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] S_ALG (store align) EXC ", cnt_test);
  cnt_test++;

  // initialize test variable
  store_access_addr[0] = 0x11223344;
  store_access_addr[1] = 0x55667788;
  tmp_a = (uint32_t)(&store_access_addr[0]);
  tmp_a += 2; // make word-unaligned

  // store to unaligned address
  cellrv32_cpu_store_unsigned_word(tmp_a, 0);

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_S_MISALIGNED) &&
      (cellrv32_cpu_csr_read(CSR_MTVAL) == tmp_a) &&
      (store_access_addr[0] == 0x11223344) &&
      (store_access_addr[1] == 0x55667788)) { // make sure memory was not altered
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Store access fault
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] S_ACC (store access) EXC ", cnt_test);
  cnt_test++;

  tmp_a = (1 << BUSKEEPER_ERR_FLAG) | (0 << BUSKEEPER_ERR_TYPE);

  // store to unreachable aligned address
  cellrv32_cpu_store_unsigned_word(ADDR_READONLY, 0);

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_S_ACCESS) && // store bus access error exception
      (cellrv32_cpu_csr_read(CSR_MTVAL) == ADDR_READONLY) &&
      (CELLRV32_BUSKEEPER->CTRL == tmp_a)) { // buskeeper: error flag + device error
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Environment call from M-mode
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] ENVCALL M EXC ", cnt_test);
  cnt_test++;

  asm volatile ("ecall");

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_MENV_CALL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Environment call from U-mode
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] ENVCALL U EXC ", cnt_test);
  cnt_test++;

  // switch to user mode (hart will be back in MACHINE mode when trap handler returns)
  cellrv32_cpu_goto_user_mode();
  {
    asm volatile ("ecall");
  }

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_UENV_CALL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Machine timer interrupt (MTIME)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] MTI (MTIME) IRQ ", cnt_test);
  cnt_test++;

  // configure MTIME (and check overflow from low word to high word)
  cellrv32_mtime_set_timecmp(0x0000000100000000ULL);
  cellrv32_mtime_set_time(   0x00000000FFFFFFFEULL);
  // enable interrupt
  cellrv32_cpu_csr_write(CSR_MIE, 1 << CSR_MIE_MTIE);

  // wait some time for the IRQ to trigger and arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_MTI) {
    test_ok();
  }
  else {
    test_fail();
  }

  // no more MTIME interrupts
  cellrv32_mtime_set_timecmp(-1);


  // ----------------------------------------------------------
  // Machine software interrupt (MSI) via testbench
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] MSI (sim) IRQ ", cnt_test);
  cnt_test++;

  // enable interrupt
  cellrv32_cpu_csr_write(CSR_MIE, 1 << CSR_MIE_MSIE);

  // trigger IRQ
  sim_irq_trigger(1 << CSR_MIE_MSIE);

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);
  sim_irq_trigger(0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_MSI) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Machine external interrupt (MEI) via testbench
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] MEI (sim) IRQ ", cnt_test);
  cnt_test++;

  // enable interrupt
  cellrv32_cpu_csr_write(CSR_MIE, 1 << CSR_MIE_MEIE);

  // trigger IRQ
  sim_irq_trigger(1 << CSR_MIE_MEIE);

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);
  sim_irq_trigger(0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_MEI) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Permanent IRQ (make sure interrupted program advances)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Permanent IRQ (MTIME) ", cnt_test);
  cnt_test++;

  // fire MTIME IRQ
  cellrv32_cpu_csr_write(CSR_MIE, 1 << CSR_MIE_MTIE);
  cellrv32_mtime_set_timecmp(0); // force interrupt

  int test_cnt = 0;
  while(test_cnt < 2) {
    test_cnt++;
  }

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (test_cnt == 2) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test pending interrupt
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Pending IRQ (MTIME) ", cnt_test);
  cnt_test++;

  // disable all interrupt setting
  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // fire MTIME IRQ
  cellrv32_mtime_set_timecmp(0); // force interrupt

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  uint32_t was_pending = cellrv32_cpu_csr_read(CSR_MIP) & (1 << CSR_MIP_MTIP); // should be pending now

  // clear pending MTI
  cellrv32_mtime_set_timecmp(-1);

  uint32_t is_pending = cellrv32_cpu_csr_read(CSR_MIP) & (1 << CSR_MIP_MTIP); // should NOT be pending anymore

  if ((was_pending != 0) && (is_pending == 0)) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 0 (WDT)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ0 (WDT) ", cnt_test);
  cnt_test++;

  // enable fast interrupt
  cellrv32_cpu_irq_enable(WDT_FIRQ_ENABLE);

  // configure WDT:
  // timeout = 1*4096 cycles, no lock, disable in debug mode, enable in sleep mode
  cellrv32_wdt_setup(1, 0, 0, 1);

  // wait in sleep mode for WDT interrupt
  asm volatile ("wfi");

  cellrv32_cpu_csr_write(CSR_MIE, 0);
  CELLRV32_WDT->CTRL = 0;

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == WDT_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 1 (CFS)
  // ----------------------------------------------------------
  PRINT_STANDARD("[%i] FIRQ1 (CFS) ", cnt_test);
  PRINT_STANDARD("[skipped, n.a.]\n");


  // ----------------------------------------------------------
  // Fast interrupt channel 2 (UART0.RX)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ2 (UART0.RX) ", cnt_test);
  cnt_test++;

  // wait for UART to finish transmitting
  while(cellrv32_uart0_tx_busy());

  // backup current UART configuration
  tmp_a = CELLRV32_UART0->CTRL;
  // enable IRQ if RX FIFO not empty
  cellrv32_uart0_setup(BAUD_RATE, 1 << UART_CTRL_IRQ_RX_NEMPTY);
  // make sure sim mode is disabled
  CELLRV32_UART0->CTRL &= ~(1 << UART_CTRL_SIM_MODE);

  // enable fast interrupt
  cellrv32_cpu_irq_enable(UART0_RX_FIRQ_ENABLE);

  cellrv32_uart0_putc(0);
  while(cellrv32_uart0_tx_busy());

  // sleep until interrupt
  cellrv32_cpu_sleep();

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // restore original configuration
  CELLRV32_UART0->CTRL = tmp_a;

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == UART0_RX_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 3 (UART0.TX)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ3 (UART0.TX) ", cnt_test);
  cnt_test++;

  // wait for UART to finish transmitting
  while(cellrv32_uart0_tx_busy());

  // backup current UART configuration
  tmp_a = CELLRV32_UART0->CTRL;
  // enable IRQ if TX FIFO empty
  cellrv32_uart0_setup(BAUD_RATE, 1 << UART_CTRL_IRQ_TX_EMPTY);
  // make sure sim mode is disabled
  CELLRV32_UART0->CTRL &= ~(1 << UART_CTRL_SIM_MODE);

  cellrv32_uart0_putc(0);
  while(cellrv32_uart0_tx_busy());

  // UART0 TX interrupt enable
  cellrv32_cpu_irq_enable(UART0_TX_FIRQ_ENABLE);

  // sleep until interrupt
  cellrv32_cpu_sleep();

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // restore original configuration
  CELLRV32_UART0->CTRL = tmp_a;

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == UART0_TX_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 4 (UART1.RX)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ4 (UART1.RX) ", cnt_test);
  cnt_test++;

  // backup current UART1 configuration
  tmp_a = CELLRV32_UART1->CTRL;
  // enable IRQ if RX FIFO not empty
  cellrv32_uart1_setup(BAUD_RATE, 1 << UART_CTRL_IRQ_RX_NEMPTY);
  // make sure sim mode is disabled
  CELLRV32_UART1->CTRL &= ~(1 << UART_CTRL_SIM_MODE);

  // UART1 RX interrupt enable
  cellrv32_cpu_irq_enable(UART1_RX_FIRQ_ENABLE);

  cellrv32_uart1_putc(0);
  while(cellrv32_uart1_tx_busy());

  // sleep until interrupt
  cellrv32_cpu_sleep();

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // restore original configuration
  CELLRV32_UART1->CTRL = tmp_a;

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == UART1_RX_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 5 (UART1.TX)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ5 (UART1.TX) ", cnt_test);
  cnt_test++;

  // backup current UART1 configuration
  tmp_a = CELLRV32_UART1->CTRL;
  // enable IRQ if TX FIFO empty
  cellrv32_uart1_setup(BAUD_RATE, 1 << UART_CTRL_IRQ_TX_EMPTY);
  // make sure sim mode is disabled
  CELLRV32_UART1->CTRL &= ~(1 << UART_CTRL_SIM_MODE);

  cellrv32_uart1_putc(0);
  while(cellrv32_uart1_tx_busy());

  // UART0 TX interrupt enable
  cellrv32_cpu_irq_enable(UART1_TX_FIRQ_ENABLE);

  // sleep until interrupt
  cellrv32_cpu_sleep();

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // restore original configuration
  CELLRV32_UART1->CTRL = tmp_a;

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == UART1_TX_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Fast interrupt channel 6 (SPI)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ6 (SPI) ", cnt_test);
  cnt_test++;

  // configure SPI
  cellrv32_spi_setup(CLK_PRSC_8, 0, 0, 0, 1<<SPI_CTRL_IRQ_RX_AVAIL); // IRQ when RX FIFO is not empty

  // enable fast interrupt
  cellrv32_cpu_irq_enable(SPI_FIRQ_ENABLE);

  // trigger SPI IRQ
  cellrv32_spi_trans(0); // blocking

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == SPI_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }

  // disable SPI
  cellrv32_spi_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 7 (TWI)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ7 (TWI) ", cnt_test);
  cnt_test++;

  // configure TWI, fastest clock, no clock stretching
  cellrv32_twi_setup(CLK_PRSC_2, 0, 0);

  // enable TWI FIRQ
  cellrv32_cpu_irq_enable(TWI_FIRQ_ENABLE);

  // trigger TWI IRQ
  cellrv32_twi_start_trans(0xA5);

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TWI_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }

  // disable TWI
  cellrv32_twi_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 8 (XIRQ)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ8 (XIRQ) ", cnt_test);
  cnt_test++;

  int xirq_err_cnt = 0;
  xirq_trap_handler_ack = 0;

  xirq_err_cnt += cellrv32_xirq_setup(); // initialize XIRQ
  xirq_err_cnt += cellrv32_xirq_install(0, xirq_trap_handler0); // install XIRQ IRQ handler channel 0
  xirq_err_cnt += cellrv32_xirq_install(1, xirq_trap_handler1); // install XIRQ IRQ handler channel 1

  // enable XIRQ FIRQ
  cellrv32_cpu_irq_enable(XIRQ_FIRQ_ENABLE);

  // trigger XIRQ channel 1 and 0
  cellrv32_gpio_port_set(3);

  // wait for IRQs to arrive CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == XIRQ_TRAP_CODE) && // FIRQ8 IRQ
      (xirq_err_cnt == 0) && // no errors during XIRQ configuration
      (xirq_trap_handler_ack == 4)) { // XIRQ channel handler 0 executed before handler 1
    test_ok();
  }
  else {
    test_fail();
  }

  CELLRV32_XIRQ->IER = 0;
  CELLRV32_XIRQ->IPR = -1;


  // ----------------------------------------------------------
  // Fast interrupt channel 9 (NEOLED)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ9 (NEOLED) ", cnt_test);
  cnt_test++;

  // enable fast interrupt
  cellrv32_cpu_irq_enable(NEOLED_FIRQ_ENABLE);

  // configure NEOLED, IRQ if FIFO  empty
  cellrv32_neoled_setup(CLK_PRSC_4, 0, 0, 0, 0);

  // send dummy data
  cellrv32_neoled_write_nonblocking(0);
  cellrv32_neoled_write_nonblocking(0);

  // sleep until interrupt
  cellrv32_cpu_sleep();

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == NEOLED_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }

  // no more NEOLED interrupts
  cellrv32_neoled_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 10 (reserved)
  // ----------------------------------------------------------
  PRINT_STANDARD("[%i] FIRQ10 [skipped, n.a.]\n", cnt_test);


  // ----------------------------------------------------------
  // Fast interrupt channel 11 (SDI)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ11 (SDI) ", cnt_test);
  cnt_test++;

  // configure and enable SDI + SPI
  cellrv32_sdi_setup(1 << SDI_CTRL_IRQ_RX_AVAIL);
  cellrv32_spi_setup(CLK_PRSC_4, 0, 0, 0, 0);

  // enable fast interrupt
  cellrv32_cpu_irq_enable(SDI_FIRQ_ENABLE);

  // write test data to SDI
  cellrv32_sdi_rx_clear();
  cellrv32_sdi_put(0xab);

  // trigger SDI IRQ by sending data via SPI
  cellrv32_spi_cs_en(7); // select SDI
  tmp_a = cellrv32_spi_trans(0x83);
  cellrv32_spi_cs_dis();

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == SDI_TRAP_CODE) && // correct trap code
      (cellrv32_sdi_get_nonblocking() == 0x83) && // correct SDI read data
      ((tmp_a & 0xff) == 0xab)) { // correct SPI read data
    test_ok();
  }
  else {
    test_fail();
  }

  // disable SDI + SPI
  cellrv32_sdi_disable();
  cellrv32_spi_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 12 (GPTMR)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ12 (GPTMR) ", cnt_test);
  cnt_test++;

  // enable GPTMR FIRQ
  cellrv32_cpu_irq_enable(GPTMR_FIRQ_ENABLE);

  // configure timer IRQ for one-shot mode after CLK_PRSC_2*2=4 clock cycles
  cellrv32_gptmr_setup(CLK_PRSC_2, 0, 2);

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // check if IRQ
  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == GPTMR_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }

  // disable GPTMR
  cellrv32_gptmr_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 13 (ONEWIRE)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] FIRQ13 (ONEWIRE) ", cnt_test);
  cnt_test++;

  // enable ONEWIRE FIRQ
  cellrv32_cpu_irq_enable(ONEWIRE_FIRQ_ENABLE);

  // configure interface for minimal timing
  cellrv32_onewire_setup(200); // t_base = 200ns

  // read single bit from bus
  cellrv32_onewire_read_bit_blocking();

  // wait some time for the IRQ to arrive the CPU
  asm volatile ("nop");
  asm volatile ("nop");

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  // check if IRQ
  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == ONEWIRE_TRAP_CODE) {
    test_ok();
  }
  else {
    test_fail();
  }

  // disable ONEWIRE
  cellrv32_onewire_disable();


  // ----------------------------------------------------------
  // Fast interrupt channel 14..15 (reserved)
  // ----------------------------------------------------------
  PRINT_STANDARD("[%i] FIRQ14..15 [skipped, n.a.]\n", cnt_test);


  // ----------------------------------------------------------
  // Test WFI ("sleep") instruction (executed in user mode), wakeup via MTIME
  // mstatus.mie is cleared before to check if machine-mode IRQ still trigger in user-mode
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] user-mode WFI (wake-up via MTIME) ", cnt_test);
  cnt_test++;

  // program wake-up timer
  cellrv32_mtime_set_timecmp(cellrv32_mtime_get_time() + 500);

  // enable mtime interrupt
  cellrv32_cpu_csr_write(CSR_MIE, 1 << CSR_MIE_MTIE);

  // clear mstatus.TW to allow execution of WFI also in user-mode
  // clear mstatus.MIE and mstatus.MPIE to check if IRQ can still trigger in User-mode
  cellrv32_cpu_csr_clr(CSR_MSTATUS, (1<<CSR_MSTATUS_TW) | (1<<CSR_MSTATUS_MIE) | (1<<CSR_MSTATUS_MPIE));

  // put CPU into sleep mode (from user mode)
  cellrv32_cpu_goto_user_mode();
  {
    asm volatile ("wfi");
  }

  cellrv32_cpu_csr_write(CSR_MIE, 0);

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) != TRAP_CODE_MTI) {
    test_fail();
  }
  else {
    test_ok();
  }


  // ----------------------------------------------------------
  // Test un-allowed WFI ("sleep") instruction (executed in user mode)
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] WFI (not allowed in u-mode) ", cnt_test);
  cnt_test++;

  // set mstatus.TW to disallow execution of WFI in user-mode
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_TW);

  // put CPU into sleep mode (from user mode)
  cellrv32_cpu_goto_user_mode();
  {
    asm volatile ("wfi"); // this has to fail
  }

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test invalid CSR access in user mode
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] Invalid CSR access from U-mode ", cnt_test);
  cnt_test++;

  // switch to user mode (hart will be back in MACHINE mode when trap handler returns)
  cellrv32_cpu_goto_user_mode();
  {
    // access to misa not allowed for user-level programs
    tmp_a = cellrv32_cpu_csr_read(CSR_MISA);
  }

  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }


  // ----------------------------------------------------------
  // Test RTE debug trap handler
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] RTE debug trap handler ", cnt_test);
  cnt_test++;

  // uninstall custom handler and use default RTE debug handler
  cellrv32_rte_handler_uninstall(RTE_TRAP_I_ILLEGAL);

  // trigger illegal instruction exception
  cellrv32_cpu_csr_read(0xfff); // CSR not available

  PRINT_STANDARD(" ");
  if (cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_I_ILLEGAL) {
    test_ok();
  }
  else {
    test_fail();
  }

  // restore original handler
  cellrv32_rte_handler_install(RTE_TRAP_I_ILLEGAL, global_trap_handler);


  // ----------------------------------------------------------
  // Test physical memory protection
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
  PRINT_STANDARD("[%i] PMP:\n", cnt_test);

  // check if PMP is implemented
  if (pmp_num_regions >= 4)  {

    // Create PMP protected region
    // ---------------------------------------------
    cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
    cnt_test++;

    pmp_access_addr = 0xcafe1234; // initialize
    tmp_a = (uint32_t)(&pmp_access_addr); // base address of protected region

    // configure new region (with highest priority)
    int pmp_res = 0;
    // base
    PRINT_STANDARD(" Setup PMP(0) OFF [-,-,-,-] @ 0x%x\n", tmp_a);
    pmp_res += cellrv32_cpu_pmp_configure_region(0, tmp_a, 0);
    // bound
    PRINT_STANDARD(" Setup PMP(1) TOR [!L,!X,!W,R] @ 0x%x ", tmp_a+4);
    pmp_res += cellrv32_cpu_pmp_configure_region(1, tmp_a+4, (PMP_TOR << PMPCFG_A_LSB) | (1 << PMPCFG_R)); // read-only

    if ((pmp_res == 0) && (cellrv32_cpu_csr_read(CSR_MCAUSE) == mcause_never_c)) {
      test_ok();
    }
    else {
      test_fail();
    }


    // ------ LOAD from U-mode: should succeed ------
    cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
    PRINT_STANDARD("[%i] PMP: U-mode read (SUCCEED) ", cnt_test);
    cnt_test++;

    // switch to user mode (hart will be back in MACHINE mode when trap handler returns)
    cellrv32_cpu_goto_user_mode();
    {
      tmp_b = 0;
      tmp_b = cellrv32_cpu_load_unsigned_word((uint32_t)(&pmp_access_addr));
    }

    asm volatile ("ecall"); // switch back to machine mode
    if (tmp_b == 0xcafe1234) {
      test_ok();
    }
    else {
      test_fail();
    }


    // ------ STORE from U-mode: should fail ------
    cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
    PRINT_STANDARD("[%i] PMP: U-mode write (FAIL) ", cnt_test);
    cnt_test++;

    // switch to user mode (hart will be back in MACHINE mode when trap handler returns)
    cellrv32_cpu_goto_user_mode();
    {
      cellrv32_cpu_store_unsigned_word((uint32_t)(&pmp_access_addr), 0); // store access -> should fail
    }

    asm volatile ("ecall"); // switch back to machine mode
    if (pmp_access_addr == 0xcafe1234) {
      test_ok();
    }
    else {
      test_fail();
    }


    // ------ STORE from M mode using U mode permissions: should fail ------
    cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
    PRINT_STANDARD("[%i] PMP: M-mode (U-mode permissions) write (FAIL) ", cnt_test);
    cnt_test++;

    // make M-mode load/store accesses use U-mode rights
    cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MPRV); // set MPRV: M uses U permissions for load/stores
    cellrv32_cpu_csr_clr(CSR_MSTATUS, 3 << CSR_MSTATUS_MPP_L); // clear MPP: use U as effective privilege mode

    cellrv32_cpu_store_unsigned_word((uint32_t)(&pmp_access_addr), 0); // store access -> should fail

    cellrv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MPRV);

    if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_S_ACCESS) && (pmp_access_addr == 0xcafe1234)) {
      test_ok();
    }
    else {
      test_fail();
    }


    // ------ STORE from M mode with LOCKED: should fail ------
    cellrv32_cpu_csr_write(CSR_MCAUSE, mcause_never_c);
    PRINT_STANDARD("[%i] PMP: M-mode (LOCKED) write (FAIL) ", cnt_test);
    cnt_test++;

    // set lock bit
    tmp_a = cellrv32_cpu_csr_read(CSR_PMPCFG0);
    tmp_a |= (1 << PMPCFG_L) << 8; // set lock bit in entry 1
    cellrv32_cpu_csr_write(CSR_PMPCFG0, tmp_a);

    cellrv32_cpu_store_unsigned_word((uint32_t)(&pmp_access_addr), 0); // store access -> should fail

    if ((cellrv32_cpu_csr_read(CSR_MCAUSE) == TRAP_CODE_S_ACCESS) && (pmp_access_addr == 0xcafe1234)) {
      test_ok();
    }
    else {
      test_fail();
    }

  }
  else {
    PRINT_STANDARD("[skipped, n.a.]\n");
  }


  // ----------------------------------------------------------
  // HPM reports
  // ----------------------------------------------------------
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, -1); // stop all HPM counters
  PRINT_STANDARD("\n\n--<< HPM.low (%u) >>--\n", num_hpm_cnts_global);
  PRINT_STANDARD("#00 Instr.:   %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_INSTRET));
  // HPM #01 does not exist
  PRINT_STANDARD("#02 Clocks:   %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_CYCLE));
  PRINT_STANDARD("#03 C-instr.: %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER3));
  PRINT_STANDARD("#04 IF wait:  %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER4));
  PRINT_STANDARD("#05 II wait:  %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER5));
  PRINT_STANDARD("#06 ALU wait: %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER6));
  PRINT_STANDARD("#07 M loads:  %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER7));
  PRINT_STANDARD("#08 M stores: %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER8));
  PRINT_STANDARD("#09 M wait:   %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER9));
  PRINT_STANDARD("#10 Jumps:    %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER10));
  PRINT_STANDARD("#11 Branch.:  %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER11));
  PRINT_STANDARD("#12 > taken:  %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER12));
  PRINT_STANDARD("#13 EXCs:     %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER13));
  PRINT_STANDARD("#14 Illegals: %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER14));


  // ----------------------------------------------------------
  // Final test reports
  // ----------------------------------------------------------
  PRINT_CRITICAL("\n\nTest results:\nPASS: %i/%i\nFAIL: %i/%i\n\n", cnt_ok, cnt_test, cnt_fail, cnt_test);

  // final result
  if (cnt_fail == 0) {
    PRINT_STANDARD("%c[1m[PROCESSOR TEST COMPLETED SUCCESSFULLY!]%c[0m\n", 27, 27);
  }
  else {
    PRINT_STANDARD("%c[1m[PROCESSOR TEST FAILED!]%c[0m\n", 27, 27);
  }

  return (int)cnt_fail; // return error counter for after-main handler
}


/**********************************************************************//**
 * Simulation-based function to set/clear CPU interrupts (MSI, MEI).
 *
 * @param[in] sel IRQ select mask (bit positions according to #CELLRV32_CSR_MIE_enum).
 **************************************************************************/
void sim_irq_trigger(uint32_t sel) {

  *((volatile uint32_t*) (0xFF000000)) = sel;
}


/**********************************************************************//**
 * Trap handler for ALL exceptions/interrupts.
 **************************************************************************/
void global_trap_handler(void) {

  uint32_t cause = cellrv32_cpu_csr_read(CSR_MCAUSE);

  // clear pending FIRQ
  if (cause & (1<<31)) {
    cellrv32_cpu_csr_write(CSR_MIP, ~(1 << (cause & 0xf)));
  }

  // hack: make "instruction access fault" exception resumable as we *exactly* know how to handle it in this case
  if (cause == TRAP_CODE_I_ACCESS) {
    cellrv32_cpu_csr_write(CSR_MEPC, cellrv32_cpu_csr_read(CSR_MEPC) + 4);
  }

  // hack: always come back in MACHINE MODE
  cellrv32_cpu_csr_set(CSR_MSTATUS, (1<<CSR_MSTATUS_MPP_H) | (1<<CSR_MSTATUS_MPP_L));
}


/**********************************************************************//**
 * XIRQ handler channel 0.
 **************************************************************************/
void xirq_trap_handler0(void) {

  xirq_trap_handler_ack += 2;
}


/**********************************************************************//**
 * XIRQ handler channel 1.
 **************************************************************************/
void xirq_trap_handler1(void) {

  xirq_trap_handler_ack *= 2;
}


/**********************************************************************//**
 * Test results helper function: Shows "[ok]" and increments global cnt_ok
 **************************************************************************/
void test_ok(void) {

  PRINT_STANDARD("%c[1m[ok]%c[0m\n", 27, 27);
  cnt_ok++;
}


/**********************************************************************//**
 * Test results helper function: Shows "[FAIL]" and increments global cnt_fail
 **************************************************************************/
void test_fail(void) {

  PRINT_CRITICAL("%c[1m[fail(%u)]%c[0m\n", 27, cnt_test, 27);
  cnt_fail++;
}


/**********************************************************************//**
 * "after-main" handler that is executed after the application's
 * main function returns (called by crt0.S start-up code): Output minimal
 * test report to physical UART
 **************************************************************************/
void __cellrv32_crt0_after_main(int32_t return_code) {

  // make sure sim mode is disabled and UARTs are actually enabled
  CELLRV32_UART0->CTRL |=  (1 << UART_CTRL_EN);
  CELLRV32_UART0->CTRL &= ~(1 << UART_CTRL_SIM_MODE);
  CELLRV32_UART1->CTRL = CELLRV32_UART0->CTRL;

  // minimal result report
  PRINT_CRITICAL("%u/%u\n", (uint32_t)return_code, (uint32_t)cnt_test);
}