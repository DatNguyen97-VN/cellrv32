// #################################################################################################
// # << CELLRV32 - Custom Functions Subsystem (CFS) Demo Program >>                                #
// #################################################################################################


/**********************************************************************//**
 * @file demo_cfs/main.c
 * @author Stephan Nolting
 * @brief Simple demo program for the _default_ custom functions subsystem (CFS) module.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/** Number of test cases per CFS function */
#define TESTCASES 4
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
uint32_t xorshift32(void);


/**********************************************************************//**
 * Main function
 *
 * @note This program requires the CFS and UART0.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  uint32_t i, tmp;

  // capture all exceptions and give debug info via UART0
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // print project logo via UART
  cellrv32_rte_print_logo();
  
  // check if CFS is implemented at all
  if (cellrv32_cfs_available() == 0) {
    cellrv32_uart0_printf("Error! No CFS synthesized!\n");
    return 1;
  }


  // intro
  cellrv32_uart0_printf("<<< CELLRV32 Custom Functions Subsystem (CFS) Demo Program >>>\n\n");

  cellrv32_uart0_printf("NOTE: This program assumes the _default_ CFS hardware module, which implements\n"
                       "      simple data conversion functions using four memory-mapped registers.\n\n");

  cellrv32_uart0_printf("Default CFS memory-mapped registers:\n"
                       " * CELLRV32_CFS->REG[0] (r/w): convert binary to gray code\n"
                       " * CELLRV32_CFS->REG[1] (r/w): convert gray to binary code\n"
                       " * CELLRV32_CFS->REG[2] (r/w): bit reversal\n"
                       " * CELLRV32_CFS->REG[3] (r/w): byte swap\n"
                       "The remaining 60 CFS registers are unused and will return 0 when read.\n");


  // function examples
  cellrv32_uart0_printf("\n--- CFS 'binary to gray' function ---\n");
  for (i=0; i<TESTCASES; i++) {
    tmp = xorshift32(); // get random test data
    CELLRV32_CFS->REG[0] = tmp; // write to CFS memory-mapped register 0
    cellrv32_uart0_printf("%u: IN = 0x%x, OUT = 0x%x\n", i, tmp, CELLRV32_CFS->REG[0]); // read from CFS memory-mapped register 0
  }

  cellrv32_uart0_printf("\n--- CFS 'gray to binary' function ---\n");
  for (i=0; i<TESTCASES; i++) {
    tmp = xorshift32(); // get random test data
    CELLRV32_CFS->REG[1] = tmp; // write to CFS memory-mapped register 1
    cellrv32_uart0_printf("%u: IN = 0x%x, OUT = 0x%x\n", i, tmp, CELLRV32_CFS->REG[1]); // read from CFS memory-mapped register 1
  }

  cellrv32_uart0_printf("\n--- CFS 'bit reversal' function ---\n");
  for (i=0; i<TESTCASES; i++) {
    tmp = xorshift32(); // get random test data
    CELLRV32_CFS->REG[2] = tmp; // write to CFS memory-mapped register 2
    cellrv32_uart0_printf("%u: IN = 0x%x, OUT = 0x%x\n", i, tmp, CELLRV32_CFS->REG[2]); // read from CFS memory-mapped register 2
  }

  cellrv32_uart0_printf("\n--- CFS 'byte swap' function ---\n");
  for (i=0; i<TESTCASES; i++) {
    tmp = xorshift32(); // get random test data
    CELLRV32_CFS->REG[3] = tmp; // write to CFS memory-mapped register 3
    cellrv32_uart0_printf("%u: IN = 0x%x, OUT = 0x%x\n", i, tmp, CELLRV32_CFS->REG[3]); // read from CFS memory-mapped register 3
  }


  cellrv32_uart0_printf("\nCFS demo program completed.\n");

  return 0;
}


/**********************************************************************//**
 * Pseudo-Random Number Generator (to generate deterministic test vectors).
 *
 * @return Random data (32-bit).
 **************************************************************************/
uint32_t xorshift32(void) {

  static uint32_t x32 = 314159265;

  x32 ^= x32 << 13;
  x32 ^= x32 >> 17;
  x32 ^= x32 << 5;

  return x32;
}
