// #################################################################################################
// # << CELLRV32: cellrv32_cfu.c - CPU Core - CFU Co-Processor Hardware Driver >>                  #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cpu_cfu.c
 * @brief CPU Core custom functions unit HW driver source file.
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_cpu_cfu.h"


/**********************************************************************//**
 * Check if custom functions unit was synthesized.
 *
 * @return 0 if CFU was not synthesized, 1 if CFU is available.
 **************************************************************************/
int cellrv32_cpu_cfu_available(void) {

  // this is an ISA extension - not a SoC module
  if (cellrv32_cpu_csr_read(CSR_MXISA) & (1 << CSR_MXISA_ZXCFU)) {
    return 1;
  }
  else {
    return 0;
  }
}
