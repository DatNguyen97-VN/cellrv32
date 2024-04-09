// #################################################################################################
// # << CELLRV32: cellrv32_gptmr.h - General Purpose Timer (GPTMR) HW Driver >>                    #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_gptmr.h
 * @brief General purpose timer (GPTMR) HW driver header file.
 *
 * @note These functions should only be used if the GPTMR unit was synthesized (IO_GPTMR_EN = true).
 **************************************************************************/

#ifndef cellrv32_gptmr_h
#define cellrv32_gptmr_h

/**********************************************************************//**
 * @name IO Device: General Purpose Timer (GPTMR)
 **************************************************************************/
/**@{*/
/** GPTMR module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL;           /**< offset  0: control register (#CELLRV32_GPTMR_CTRL_enum) */
  uint32_t THRES;          /**< offset  4: threshold register */
  uint32_t COUNT;          /**< offset  8: counter register */
  const uint32_t reserved; /**< offset 12: reserved */
} cellrv32_gptmr_t;

/** GPTMR module hardware access (#cellrv32_gptmr_t) */
#define CELLRV32_GPTMR ((cellrv32_gptmr_t*) (CELLRV32_GPTMR_BASE))

/** GPTMR control/data register bits */
enum CELLRV32_GPTMR_CTRL_enum {
  GPTMR_CTRL_EN    = 0, /**< GPTIMR control register(0) (r/w): Timer unit enable */
  GPTMR_CTRL_PRSC0 = 1, /**< GPTIMR control register(1) (r/w): Clock prescaler select bit 0 */
  GPTMR_CTRL_PRSC1 = 2, /**< GPTIMR control register(2) (r/w): Clock prescaler select bit 1 */
  GPTMR_CTRL_PRSC2 = 3, /**< GPTIMR control register(3) (r/w): Clock prescaler select bit 2 */
  GPTMR_CTRL_MODE  = 4  /**< GPTIMR control register(4) (r/w): Timer mode: 0=single-shot mode, 1=continuous mode */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int  cellrv32_gptmr_available(void);
void cellrv32_gptmr_setup(int prsc, int mode, uint32_t threshold);
void cellrv32_gptmr_disable(void);
void cellrv32_gptmr_enable(void);
void cellrv32_gptmr_restart(void);
/**@}*/


#endif // cellrv32_gptmr_h
