// #################################################################################################
// # << CELLRV32: cellrv32_gpio.h - General Purpose Input/Output Port HW Driver (Header) >>        #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_gpio.h
 * @brief General purpose input/output port unit (GPIO) HW driver header file.
 *
 * @note These functions should only be used if the GPIO unit was synthesized (IO_GPIO_EN = true).
 **************************************************************************/

#ifndef cellrv32_gpio_h
#define cellrv32_gpio_h

/**********************************************************************//**
 * @name IO Device: General Purpose Input/Output Port Unit (GPIO)
 **************************************************************************/
/**@{*/
/** GPIO module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  const uint32_t INPUT_LO;  /**< offset 0:  parallel input port lower 32-bit, read-only */
  const uint32_t INPUT_HI;  /**< offset 4:  parallel input port upper 32-bit, read-only */
  uint32_t       OUTPUT_LO; /**< offset 8:  parallel output port lower 32-bit */
  uint32_t       OUTPUT_HI; /**< offset 12: parallel output port upper 32-bit */
} cellrv32_gpio_t;

/** GPIO module hardware access (#cellrv32_gpio_t) */
#define CELLRV32_GPIO ((cellrv32_gpio_t*) (CELLRV32_GPIO_BASE))
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int      cellrv32_gpio_available(void);
void     cellrv32_gpio_pin_set(int pin);
void     cellrv32_gpio_pin_clr(int pin);
void     cellrv32_gpio_pin_toggle(int pin);
uint32_t cellrv32_gpio_pin_get(int pin);

void     cellrv32_gpio_port_set(uint64_t d);
uint64_t cellrv32_gpio_port_get(void);
/**@}*/


#endif // cellrv32_gpio_h
