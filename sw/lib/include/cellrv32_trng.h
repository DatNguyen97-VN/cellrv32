// #################################################################################################
// # << CELLRV32: cellrv32_trng.h - True Random Number Generator (TRNG) HW Driver >>               #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_trng.h
 * @brief True Random Number Generator (TRNG) HW driver header file.
 *
 * @note These functions should only be used if the TRNG unit was synthesized (IO_TRNG_EN = true).
 **************************************************************************/

#ifndef cellrv32_trng_h
#define cellrv32_trng_h

/**********************************************************************//**
 * @name IO Device: True Random Number Generator (TRNG)
 **************************************************************************/
/**@{*/
/** TRNG module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL;  /**< offset 0: control register (#CELLRV32_TRNG_CTRL_enum) */
} cellrv32_trng_t;

/** TRNG module hardware access (#cellrv32_trng_t) */
#define CELLRV32_TRNG ((cellrv32_trng_t*) (CELLRV32_TRNG_BASE))

/** TRNG control/data register bits */
enum CELLRV32_TRNG_CTRL_enum {
  TRNG_CTRL_DATA_LSB =  0, /**< TRNG data/control register(0)  (r/-): Random data byte LSB */
  TRNG_CTRL_DATA_MSB =  7, /**< TRNG data/control register(7)  (r/-): Random data byte MSB */

  TRNG_CTRL_FIFO_CLR = 28, /**< TRNG data/control register(28) (-/w): Clear data FIFO (auto clears) */
  TRNG_CTRL_SIM_MODE = 29, /**< TRNG data/control register(29) (r/-): PRNG mode (simulation mode) */
  TRNG_CTRL_EN       = 30, /**< TRNG data/control register(30) (r/w): TRNG enable */
  TRNG_CTRL_VALID    = 31  /**< TRNG data/control register(31) (r/-): Random data output valid */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int  cellrv32_trng_available(void);
void cellrv32_trng_enable(void);
void cellrv32_trng_disable(void);
void cellrv32_trng_fifo_clear(void);
int  cellrv32_trng_get(uint8_t *data);
int  cellrv32_trng_check_sim_mode(void);
/**@}*/


#endif // cellrv32_trng_h
