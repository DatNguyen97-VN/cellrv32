// #################################################################################################
// # << CELLRV32 - Physical Memory Protection Example Program >>                                   #
// #################################################################################################


/**********************************************************************//**
 * @file demo_pmp/main.c
 * @author Stephan Nolting
 * @brief Physical memory protection (PMP) example program.
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
 * Example variable that will be protected by the PMP
 **************************************************************************/
uint32_t protected_var[4] = {
  0x11223344,
  0x55667788,
  0x00CAFE00,
  0xDEADC0DE
};


/**********************************************************************//**
 * Main function
 *
 * @note This program requires the CPU PMP extension (with at least 2 regions) and UART0.
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

  // check if PMP is implemented at all
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_PMP)) == 0) {
    cellrv32_uart0_printf("ERROR! PMP CPU extension not implemented!\n");
    return 1;
  }


  // intro
  cellrv32_uart0_printf("\n<<< CELLRV32 Physical Memory Protection (PMP) Example Program >>>\n\n");

  cellrv32_uart0_printf("NOTE: This program requires at least 2 PMP regions (PMP_NUM_REGIONS >= 2)\n"
                       "and a minimal granularity of 4 bytes (PMP_MIN_GRANULARITY = 4).\n\n");


  // show PMP configuration
  cellrv32_uart0_printf("PMP hardware configuration:\n");
  cellrv32_uart0_printf("> Number of regions: %u\n", cellrv32_cpu_pmp_get_num_regions());
  cellrv32_uart0_printf("> Min. granularity:  %u bytes (minimal region size)\n\n", cellrv32_cpu_pmp_get_granularity());


  // PMP hardware configuration sufficient?
  uint32_t tmp;

  tmp = cellrv32_cpu_pmp_get_num_regions();
  if (tmp < 2) {
    cellrv32_uart0_printf("ERROR! Insufficient PMP region! Regions required = 2; region available = %u\n", tmp);
    return 1;
  }
  tmp = cellrv32_cpu_pmp_get_granularity();
  if (tmp > 4) {
    cellrv32_uart0_printf("ERROR! Insufficient PMP granularity! Granularity required = 4 bytes; granularity available = %u bytes\n", tmp);
    return 1;
  }


  cellrv32_uart0_printf("NOTE: A 4-word array 'protected_var[4]' is created, which will be probed from\n"
                       "machine-mode. The region provides the following access permissions:\n"
                       "> !X - no execute permission\n"
                       "> !W - no write permission\n"
                       ">  R - read permission\n"
                       ">  L - enforce access rights for machine-mode software\n\n");


  // The "protected_var" variable will be protected: No execute and no write access, just allow read access

  // create protected region
  int pmp_status;
  uint8_t permissions;
  cellrv32_uart0_printf("Creating protected regions (any access within [REGION_BEGIN <= address < REGION_END] will match the PMP rules)...\n");

  // any access in "region_begin <= address < region_end" will match the PMP rule
  uint32_t region_begin = (uint32_t)(&protected_var[0]);
  uint32_t region_end   = (uint32_t)(&protected_var[3]) + 4;
  cellrv32_uart0_printf("REGION_BEGIN = 0x%x\n", region_begin);
  cellrv32_uart0_printf("REGION_END   = 0x%x\n", region_end);


  // base (region begin)
  permissions = PMP_OFF << PMPCFG_A_LSB; // mode = OFF
  cellrv32_uart0_printf("> Region begin (PMP entry 0): Base = 0x%x, Mode = OFF (base of region)  ", region_begin);
  pmp_status = cellrv32_cpu_pmp_configure_region(0, region_begin, permissions);
  if (pmp_status) {
    cellrv32_uart0_printf("[FAILED]\n");
  }
  else {
    cellrv32_uart0_printf("[ok]\n");
  }

  // bound (region end)
  permissions = (PMP_TOR << PMPCFG_A_LSB) | // enable entry as TOR = top of region
                (0 << PMPCFG_X) | // no "execute" permission
                (0 << PMPCFG_W) | // no "write" permission
                (1 << PMPCFG_R) | // set "read" permission
                (1 << PMPCFG_L);  // locked: enforce PMP rule for machine-mode software
  cellrv32_uart0_printf("> Region end   (PMP entry 1): Base = 0x%x, Mode = TOR (bound of region) ", region_end);
  pmp_status = cellrv32_cpu_pmp_configure_region(1, region_end, permissions);
  if (pmp_status) {
    cellrv32_uart0_printf("[FAILED]\n");
  }
  else {
    cellrv32_uart0_printf("[ok]\n");
  }


  // test access
  cellrv32_uart0_printf("\n\nTesting access to 'protected_var' - invalid accesses will raise an exception, which will be\n"
                       "captured by the CELLRV32 runtime environment's dummy/debug handlers ('<RTE> ... </RTE>').\n\n");

  cellrv32_uart0_printf("Reading protected_var[0] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[0]), protected_var[0]);
  cellrv32_uart0_printf("Reading protected_var[1] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[1]), protected_var[1]);
  cellrv32_uart0_printf("Reading protected_var[2] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[2]), protected_var[2]);
  cellrv32_uart0_printf("Reading protected_var[3] @ 0x%x = 0x%x\n\n", (uint32_t)(&protected_var[3]), protected_var[3]);

  cellrv32_uart0_printf("Trying to write protected_var[0] @ 0x%x... \n", (uint32_t)(&protected_var[0]));
  protected_var[0] = 0; // should fail!
  cellrv32_uart0_printf("Trying to write protected_var[1] @ 0x%x... \n", (uint32_t)(&protected_var[1]));
  protected_var[1] = 0; // should fail!
  cellrv32_uart0_printf("Trying to write protected_var[2] @ 0x%x... \n", (uint32_t)(&protected_var[2]));
  protected_var[2] = 0; // should fail!
  cellrv32_uart0_printf("Trying to write protected_var[3] @ 0x%x... \n", (uint32_t)(&protected_var[3]));
  protected_var[3] = 0; // should fail!

  cellrv32_uart0_printf("\nReading again protected_var[0] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[0]), protected_var[0]);
  cellrv32_uart0_printf("Reading again protected_var[1] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[1]), protected_var[1]);
  cellrv32_uart0_printf("Reading again protected_var[2] @ 0x%x = 0x%x\n", (uint32_t)(&protected_var[2]), protected_var[2]);
  cellrv32_uart0_printf("Reading again protected_var[3] @ 0x%x = 0x%x\n\n", (uint32_t)(&protected_var[3]), protected_var[3]);


  cellrv32_uart0_printf("\nPMP demo program completed.\n");

  return 0;
}
