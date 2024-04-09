// #################################################################################################
// # << CELLRV32: cellrv32_onewire.h - 1-Wire Interface Controller HW Driver (Header) >>           #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_onewire.h
 * @brief 1-Wire Interface Controller (ONEWIRE) HW driver header file.
 *
 * @note These functions should only be used if the ONEWIRE unit was synthesized (IO_ONEWIRE_EN = true).
 **************************************************************************/

#ifndef cellrv32_onewire_h
#define cellrv32_onewire_h

/**********************************************************************//**
 * @name IO Device: 1-Wire Interface Controller (ONEWIRE)
 **************************************************************************/
/**@{*/
/** ONEWIRE module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL; /**< offset 0: control register (#CELLRV32_ONEWIRE_CTRL_enum) */
  uint32_t DATA; /**< offset 4: transmission data register (#CELLRV32_ONEWIRE_DATA_enum) */
} cellrv32_onewire_t;

/** ONEWIRE module hardware access (#cellrv32_onewire_t) */
#define CELLRV32_ONEWIRE ((cellrv32_onewire_t*) (CELLRV32_ONEWIRE_BASE))

/** ONEWIRE control register bits */
enum CELLRV32_ONEWIRE_CTRL_enum {
  ONEWIRE_CTRL_EN        =  0, /**< ONEWIRE control register(0)  (r/w): ONEWIRE controller enable */
  ONEWIRE_CTRL_PRSC0     =  1, /**< ONEWIRE control register(1)  (r/w): Clock prescaler select bit 0 */
  ONEWIRE_CTRL_PRSC1     =  2, /**< ONEWIRE control register(2)  (r/w): Clock prescaler select bit 1 */
  ONEWIRE_CTRL_CLKDIV0   =  3, /**< ONEWIRE control register(3)  (r/w): Clock divider bit 0 */
  ONEWIRE_CTRL_CLKDIV1   =  4, /**< ONEWIRE control register(4)  (r/w): Clock divider bit 1 */
  ONEWIRE_CTRL_CLKDIV2   =  5, /**< ONEWIRE control register(5)  (r/w): Clock divider bit 2 */
  ONEWIRE_CTRL_CLKDIV3   =  6, /**< ONEWIRE control register(6)  (r/w): Clock divider bit 3 */
  ONEWIRE_CTRL_CLKDIV4   =  7, /**< ONEWIRE control register(7)  (r/w): Clock divider bit 4 */
  ONEWIRE_CTRL_CLKDIV5   =  8, /**< ONEWIRE control register(8)  (r/w): Clock divider bit 5 */
  ONEWIRE_CTRL_CLKDIV6   =  9, /**< ONEWIRE control register(9)  (r/w): Clock divider bit 6 */
  ONEWIRE_CTRL_CLKDIV7   = 10, /**< ONEWIRE control register(10) (r/w): Clock divider bit 7 */
  ONEWIRE_CTRL_TRIG_RST  = 11, /**< ONEWIRE control register(11) (-/w): Trigger reset pulse, auto-clears */
  ONEWIRE_CTRL_TRIG_BIT  = 12, /**< ONEWIRE control register(12) (-/w): Trigger single-bit transmission, auto-clears */
  ONEWIRE_CTRL_TRIG_BYTE = 13, /**< ONEWIRE control register(13) (-/w): Trigger full-byte transmission, auto-clears */

  ONEWIRE_CTRL_SENSE     = 29, /**< ONEWIRE control register(29) (r/-): Current state of the bus line */
  ONEWIRE_CTRL_PRESENCE  = 30, /**< ONEWIRE control register(30) (r/-): Bus presence detected */
  ONEWIRE_CTRL_BUSY      = 31, /**< ONEWIRE control register(31) (r/-): Operation in progress when set */
};

/** ONEWIRE receive/transmit data register bits */
enum CELLRV32_ONEWIRE_DATA_enum {
  ONEWIRE_DATA_LSB = 0, /**< ONEWIRE data register(0) (r/w): Receive/transmit data (8-bit) LSB */
  ONEWIRE_DATA_MSB = 7  /**< ONEWIRE data register(7) (r/w): Receive/transmit data (8-bit) MSB */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int     cellrv32_onewire_available(void);
int     cellrv32_onewire_setup(uint32_t t_base);
void    cellrv32_onewire_enable(void);
void    cellrv32_onewire_disable(void);
int     cellrv32_onewire_sense(void);

int     cellrv32_onewire_busy(void);
void    cellrv32_onewire_reset(void);
int     cellrv32_onewire_reset_get_presence(void);
void    cellrv32_onewire_read_bit(void);
uint8_t cellrv32_onewire_read_bit_get(void);
void    cellrv32_onewire_write_bit(uint8_t bit);
void    cellrv32_onewire_read_byte(void);
uint8_t cellrv32_onewire_read_byte_get(void);
void    cellrv32_onewire_write_byte(uint8_t byte);

int     cellrv32_onewire_reset_blocking(void);
uint8_t cellrv32_onewire_read_bit_blocking(void);
void    cellrv32_onewire_write_bit_blocking(uint8_t bit);
uint8_t cellrv32_onewire_read_byte_blocking(void);
void    cellrv32_onewire_write_byte_blocking(uint8_t byte);
/**@}*/


#endif // cellrv32_onewire_h
