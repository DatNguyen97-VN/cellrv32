// #################################################################################################
// # << CELLRV32: cellrv32_buskeeper.h - Bus Monitor (BUSKEEPER) HW Driver (stub) >>               #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_buskeeper.h
 * @brief Bus Monitor (BUSKEEPER) HW driver header file.
 **************************************************************************/

#ifndef cellrv32_buskeeper_h
#define cellrv32_buskeeper_h

/**********************************************************************//**
 * @name IO Device: Bus Monitor (BUSKEEPER)
 **************************************************************************/
/**@{*/
/** BUSKEEPER module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t       CTRL;      /**< offset 0: control register (#CELLRV32_BUSKEEPER_CTRL_enum) */
  const uint32_t reserved ; /**< offset 4: reserved */
} cellrv32_buskeeper_t;

/** BUSKEEPER module hardware access (#cellrv32_buskeeper_t) */
#define CELLRV32_BUSKEEPER ((cellrv32_buskeeper_t*) (CELLRV32_BUSKEEPER_BASE))

/** BUSKEEPER control/data register bits */
enum CELLRV32_BUSKEEPER_CTRL_enum {
  BUSKEEPER_ERR_TYPE =  0, /**< BUSKEEPER control register( 0) (r/-): Bus error type: 0=device error, 1=access timeout */
  BUSKEEPER_ERR_FLAG = 31  /**< BUSKEEPER control register(31) (r/-): Sticky error flag, clears after read or write access */
};
/**@}*/


#endif // cellrv32_buskeeper_h
