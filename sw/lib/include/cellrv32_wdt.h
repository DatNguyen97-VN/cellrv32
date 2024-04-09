// #################################################################################################
// # << CELLRV32: cellrv32_wdt.h - Watchdog Timer (WDT) HW Driver >>                               #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_wdt.h
 * @brief Watchdog Timer (WDT) HW driver header file.
 *
 * @note These functions should only be used if the WDT unit was synthesized (IO_WDT_EN = true).
 **************************************************************************/

#ifndef cellrv32_wdt_h
#define cellrv32_wdt_h

/**********************************************************************//**
 * @name IO Device: Watchdog Timer (WDT)
 **************************************************************************/
/**@{*/
/** WDT module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL; /**< offset 0: control register (#CELLRV32_WDT_CTRL_enum) */
} cellrv32_wdt_t;

/** WDT module hardware access (#cellrv32_wdt_t) */
#define CELLRV32_WDT ((cellrv32_wdt_t*) (CELLRV32_WDT_BASE))

/** WDT control register bits */
enum CELLRV32_WDT_CTRL_enum {
  WDT_CTRL_EN          =  0, /**< WDT control register(0) (r/w): Watchdog enable */
  WDT_CTRL_LOCK        =  1, /**< WDT control register(1) (r/w): Lock write access to control register, clears on reset only */
  WDT_CTRL_DBEN        =  2, /**< WDT control register(2) (r/w): Allow WDT to continue operation even when CPU is in debug mode */
  WDT_CTRL_SEN         =  3, /**< WDT control register(3) (r/w): Allow WDT to continue operation even when CPU is in sleep mode */
  WDT_CTRL_RESET       =  4, /**< WDT control register(4) (-/w): Reset WDT counter when set, auto-clears */
  WDT_CTRL_RCAUSE      =  5, /**< WDT control register(5) (r/-): Cause of last system reset: 0=external reset, 1=watchdog */

  WDT_CTRL_TIMEOUT_LSB =  8, /**< WDT control register(8)  (r/w): Timeout value, LSB */
  WDT_CTRL_TIMEOUT_MSB = 31  /**< WDT control register(31) (r/w): Timeout value, MSB */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int  cellrv32_wdt_available(void);
void cellrv32_wdt_setup(uint32_t timeout, int lock, int debug_en, int sleep_en);
int  cellrv32_wdt_disable(void);
void cellrv32_wdt_feed(void);
int  cellrv32_wdt_get_cause(void);
/**@}*/


#endif // cellrv32_wdt_h
