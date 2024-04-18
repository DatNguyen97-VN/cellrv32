// #################################################################################################
// # << CELLRV32 - Hardware Performance Monitors (HPMs) Demo Program >>                            #
// #################################################################################################


/**********************************************************************//**
 * @file demo_hpm/main.c
 * @author Stephan Nolting
 * @brief Hardware performance monitor (HPM) example program.
 **************************************************************************/
#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/


/**********************************************************************//**
 * Main function
 *
 * @note This program requires the CPU Zihpm extension (with at least 2 regions) and UART0.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  // initialize CELLRV32 run-time environment
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check if UART0 is implemented
  if (cellrv32_uart0_available() == 0) {
    return 1; // UART0 not available, exit
  }

  // check if Zihpm is implemented at all
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_ZIHPM)) == 0) {
    cellrv32_uart0_printf("ERROR! Zihpm CPU extension not implemented!\n");
    return 1;
  }

  // check if at least one HPM counter is implemented
  if (cellrv32_cpu_hpm_get_num_counters() == 0) {
    cellrv32_uart0_printf("ERROR! No HPM counters implemented!\n");
    return 1;
  }


  // intro
  cellrv32_uart0_printf("\n<<< CELLRV32 Hardware Performance Monitors (HPMs) Example Program >>>\n\n");
  cellrv32_uart0_printf("NOTE: This program will use up to 12 HPM counters (if available).\n\n");


  // show HPM hardware configuration
  uint32_t hpm_num = cellrv32_cpu_hpm_get_num_counters();
  uint32_t hpm_width = cellrv32_cpu_hpm_get_size();
  cellrv32_uart0_printf("Check: %u HPM counters detected, each %u bits wide\n", hpm_num, hpm_width);


  // stop all CPU counters including HPMs
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, -1);


  // clear HPM counters (low and high word);
  // there will be NO exception if we access a HPM counter register that has not been implemented
  // as long as Zihpm is implemented
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER3,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER3H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER4,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER4H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER5,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER5H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER6,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER6H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER7,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER7H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER8,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER8H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER9,  0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER9H,  0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER10, 0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER10H, 0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER11, 0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER11H, 0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER12, 0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER12H, 0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER13, 0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER13H, 0); 
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER14, 0); cellrv32_cpu_csr_write(CSR_MHPMCOUNTER14H, 0); 

  // NOTE regarding HPMs 0..2, which are not "actual" HPMs
  // HPM 0 is the machine cycle counter
  // HPM 1 is the machine system timer
  // HPM 2 is the machine instret counter
  // these "HPMs" have fixed event configurations; however, these according events can also be used for any
  // other "real" HPM

  // configure events - one event per counter;
  // we can also configure more than one event; the HPM will increment if _any_ event triggers (logical OR);
  // there will be NO exception if we access a HPM event register that has not been implemented
  // as long as Zihpm is implemented
  cellrv32_cpu_csr_write(CSR_MHPMEVENT3,  1 << HPMCNT_EVENT_CIR); // retired compressed instruction
  cellrv32_cpu_csr_write(CSR_MHPMEVENT4,  1 << HPMCNT_EVENT_WAIT_IF); // instruction fetch wait (due to high bus traffic)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT5,  1 << HPMCNT_EVENT_WAIT_II); // instruction issue wait (due to empty instruction-prefetch buffer)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT6,  1 << HPMCNT_EVENT_WAIT_MC); // wait for multi-cycle ALU operation
  cellrv32_cpu_csr_write(CSR_MHPMEVENT7,  1 << HPMCNT_EVENT_LOAD); // executed memory LOAD
  cellrv32_cpu_csr_write(CSR_MHPMEVENT8,  1 << HPMCNT_EVENT_STORE); // execute memory STORE
  cellrv32_cpu_csr_write(CSR_MHPMEVENT9,  1 << HPMCNT_EVENT_WAIT_LS); // memory access wait (due to high bus traffic)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT10, 1 << HPMCNT_EVENT_JUMP); // jump (conditional or unconditional)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT11, 1 << HPMCNT_EVENT_BRANCH); // condition branch (taken or not taken)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT12, 1 << HPMCNT_EVENT_TBRANCH); // taken conditional branch
  cellrv32_cpu_csr_write(CSR_MHPMEVENT13, 1 << HPMCNT_EVENT_TRAP); // entered trap (exception or interrupt)
  cellrv32_cpu_csr_write(CSR_MHPMEVENT14, 1 << HPMCNT_EVENT_ILLEGAL); // executed illegal instruction


  // enable all CPU counters including HPMs
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, 0);


  // this is the part of the the program that is going to be "benchmarked" using the HPMs
  // here we are just doing some pointless stuff that will trigger the configured HPM events;
  // note that ALL code being executed will be benchmarked - including traps
  {
    cellrv32_uart0_printf("\n > Doing dummy operations...\n");
    cellrv32_uart0_printf(" > Print some number: %u\n", 52983740);
    cellrv32_uart0_printf(" > An exception (environment call) handled by the RTE: ");
    asm volatile ("ecall"); // environment call
    cellrv32_uart0_printf(" > An invalid instruction handled by the RTE: ");
    asm volatile ("csrwi marchid, 1"); // illegal instruction (writing to read-only CSR)
  }


  // stop all CPU counters including HPMs
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, -1);


  // print HPM counter values (low word only)
  cellrv32_uart0_printf("\nHPM results:\n");
  if (hpm_num >  0) { cellrv32_uart0_printf("HPM03.low (compr. instr.)  = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER3));  }
  if (hpm_num >  1) { cellrv32_uart0_printf("HPM04.low (I-fetch waits)  = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER4));  }
  if (hpm_num >  2) { cellrv32_uart0_printf("HPM05.low (I-issue waits)  = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER5));  }
  if (hpm_num >  3) { cellrv32_uart0_printf("HPM06.low (ALU waits)      = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER6));  }
  if (hpm_num >  4) { cellrv32_uart0_printf("HPM07.low (MEM loads)      = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER7));  }
  if (hpm_num >  5) { cellrv32_uart0_printf("HPM08.low (MEM stores)     = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER8));  }
  if (hpm_num >  6) { cellrv32_uart0_printf("HPM09.low (MEM wait)       = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER9));  }
  if (hpm_num >  7) { cellrv32_uart0_printf("HPM10.low (jumps)          = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER10)); }
  if (hpm_num >  8) { cellrv32_uart0_printf("HPM11.low (cond. branches) = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER11)); }
  if (hpm_num >  9) { cellrv32_uart0_printf("HPM12.low (taken branches) = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER12)); }
  if (hpm_num > 10) { cellrv32_uart0_printf("HPM13.low (EXCs + IRQs)    = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER13)); }
  if (hpm_num > 11) { cellrv32_uart0_printf("HPM14.low (illegal instr.) = %u\n", (uint32_t)cellrv32_cpu_csr_read(CSR_MHPMCOUNTER14)); }

  cellrv32_uart0_printf("\nHPM demo program completed.\n");

  return 0;
}
