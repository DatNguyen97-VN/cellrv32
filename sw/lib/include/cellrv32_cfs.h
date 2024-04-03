// #################################################################################################
// # << CELLRV32: cellrv32_cfs.h - Custom Functions Subsystem (CFS) HW Driver (stub) >>             #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32             (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cfs.h
 * @brief Custom Functions Subsystem (CFS) HW driver header file.
 *
 * @warning There are no "real" CFS driver functions available here, because these functions are defined by the actual hardware.
 * @warning The CFS designer has to provide the actual driver functions.
 *
 * @note These functions should only be used if the CFS was synthesized (IO_CFS_EN = true).
 **************************************************************************/

#ifndef cellrv32_cfs_h
#define cellrv32_cfs_h

/**********************************************************************//**
 * @name IO Device: Custom Functions Subsystem (CFS)
 **************************************************************************/
/**@{*/
/** CFS module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t REG[64]; /**< offset 4*0..4*63: CFS register 0..63, user-defined */
} cellrv32_cfs_t;

/** CFS module hardware access (#cellrv32_cfs_t) */
#define CELLRV32_CFS ((cellrv32_cfs_t*) (CELLRV32_CFS_BASE))
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int cellrv32_cfs_available(void);
/**@}*/


#endif // cellrv32_cfs_h
