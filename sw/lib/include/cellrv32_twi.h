// #################################################################################################
// # << CELLRV32: cellrv32_twi.h - Two-Wire Interface Controller (TWI) HW Driver >>                #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_twi.h
 * @brief Two-Wire Interface Controller (TWI) HW driver header file.
 *
 * @note These functions should only be used if the TWI unit was synthesized (IO_TWI_EN = true).
 **************************************************************************/

#ifndef cellrv32_twi_h
#define cellrv32_twi_h

/**********************************************************************//**
 * @name IO Device: Two-Wire Interface Controller (TWI)
 **************************************************************************/
/**@{*/
/** TWI module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL;  /**< offset 0: control register (#CELLRV32_TWI_CTRL_enum) */
  uint32_t DATA;  /**< offset 4: data register (#CELLRV32_TWI_DATA_enum) */
} cellrv32_twi_t;

/** TWI module hardware access (#cellrv32_twi_t) */
#define CELLRV32_TWI ((cellrv32_twi_t*) (CELLRV32_TWI_BASE))

/** TWI control register bits */
enum CELLRV32_TWI_CTRL_enum {
  TWI_CTRL_EN      =  0, /**< TWI control register(0)  (r/w): TWI enable */
  TWI_CTRL_START   =  1, /**< TWI control register(1)  (-/w): Generate START condition, auto-clears */
  TWI_CTRL_STOP    =  2, /**< TWI control register(2)  (-/w): Generate STOP condition, auto-clears */
  TWI_CTRL_MACK    =  3, /**< TWI control register(3)  (r/w): Generate ACK by controller for each transmission */
  TWI_CTRL_CSEN    =  4, /**< TWI control register(4)  (r/w): Allow clock stretching when set */
  TWI_CTRL_PRSC0   =  5, /**< TWI control register(5)  (r/w): Clock prescaler select bit 0 */
  TWI_CTRL_PRSC1   =  6, /**< TWI control register(6)  (r/w): Clock prescaler select bit 1 */
  TWI_CTRL_PRSC2   =  7, /**< TWI control register(7)  (r/w): Clock prescaler select bit 2 */
  TWI_CTRL_CDIV0   =  8, /**< TWI control register(8)  (r/w): Clock divider bit 0 */
  TWI_CTRL_CDIV1   =  9, /**< TWI control register(9)  (r/w): Clock divider bit 1 */
  TWI_CTRL_CDIV2   = 10, /**< TWI control register(10) (r/w): Clock divider bit 2 */
  TWI_CTRL_CDIV3   = 11, /**< TWI control register(11) (r/w): Clock divider bit 3 */

  TWI_CTRL_CLAIMED = 29, /**< TWI control register(29) (r/-): Set if the TWI bus is currently claimed by any controller */
  TWI_CTRL_ACK     = 30, /**< TWI control register(30) (r/-): ACK received when set */
  TWI_CTRL_BUSY    = 31  /**< TWI control register(31) (r/-): Transfer in progress, busy flag */
};

/** TWI receive/transmit data register bits */
enum CELLRV32_TWI_DATA_enum {
  TWI_DATA_LSB = 0, /**< TWI data register(0) (r/w): Receive/transmit data (8-bit) LSB */
  TWI_DATA_MSB = 7  /**< TWI data register(7) (r/w): Receive/transmit data (8-bit) MSB */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int     cellrv32_twi_available(void);
void    cellrv32_twi_setup(int prsc, int cdiv, int csen);
void    cellrv32_twi_disable(void);
void    cellrv32_twi_enable(void);
void    cellrv32_twi_mack_enable(void);
void    cellrv32_twi_mack_disable(void);
int     cellrv32_twi_busy(void);
int     cellrv32_twi_start_trans(uint8_t a);
int     cellrv32_twi_trans(uint8_t d);
uint8_t cellrv32_twi_get_data(void);
void    cellrv32_twi_generate_stop(void);
void    cellrv32_twi_generate_start(void);
int     cellrv32_twi_bus_claimed(void);
/**@}*/


#endif // cellrv32_twi_h
