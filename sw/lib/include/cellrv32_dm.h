// #################################################################################################
// # << CELLRV32: cellrv32_dm.h - On-Chip Debugger HW Driver (Header) >>                           #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_dm.h
 * @brief On-Chip Debugger (should NOT be used by application software at all!)
 **************************************************************************/

#ifndef cellrv32_dm_h
#define cellrv32_dm_h

/**********************************************************************//**
 * @name IO Device: On-Chip Debugger (should NOT be used by application software at all!)
 **************************************************************************/
/**@{*/
/** on-chip debugger - debug module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  const uint32_t CODE[16];      /**< offset 0: park loop code ROM (r/-) */
  const uint32_t PBUF[4];       /**< offset 64: program buffer (r/-) */
  const uint32_t reserved1[12]; /**< reserved */
  uint32_t       DATA;          /**< offset 128: data exchange register (r/w) */
  const uint32_t reserved2[15]; /**< reserved */
  uint32_t       SREG;          /**< offset 192: control and status register (r/w) */
  const uint32_t reserved3[15]; /**< reserved */
} cellrv32_dm_t;

/** on-chip debugger debug module hardware access (#cellrv32_dm_t) */
#define CELLRV32_DM ((cellrv32_dm_t*) (CELLRV32_DM_BASE))
/**@}*/


#endif // cellrv32_dm_h
