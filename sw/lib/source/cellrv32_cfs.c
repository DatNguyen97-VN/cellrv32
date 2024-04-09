// #################################################################################################
// # << CELLRV32: cellrv32_cfs.c - Custom Functions Subsystem (CFS) HW Driver (stub) >>            #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cfs.c
 * @brief Custom Functions Subsystem (CFS) HW driver source file.
 *
 * @warning There are no "real" CFS driver functions available here, because these functions are defined by the actual hardware.
 * @warning Hence, the CFS designer has to provide the actual driver functions.
 *
 * @note These functions should only be used if the CFS was synthesized (IO_CFS_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_cfs.h"


/**********************************************************************//**
 * Check if custom functions subsystem was synthesized.
 *
 * @return 0 if CFS was not synthesized, 1 if CFS is available.
 **************************************************************************/
int cellrv32_cfs_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_CFS)) {
    return 1;
  }
  else {
    return 0;
  }
}

