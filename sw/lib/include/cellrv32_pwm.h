// #################################################################################################
// # << CELLRV32: cellrv32_pwm.h - Pulse Width Modulation Controller (PWM) HW Driver >>            #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_pwm.h
 * @brief Pulse-Width Modulation Controller (PWM) HW driver header file.
 *
 * @note These functions should only be used if the PWM unit was synthesized (IO_PWM_EN = true).
 **************************************************************************/

#ifndef cellrv32_pwm_h
#define cellrv32_pwm_h

/**********************************************************************//**
 * @name IO Device: Pulse Width Modulation Controller (PWM)
 **************************************************************************/
/**@{*/
/** PWM module prototype */
typedef volatile struct __attribute__((packed,aligned(4))) {
  uint32_t CTRL;  /**< offset 0: control register (#CELLRV32_PWM_CTRL_enum) */
  uint32_t DC[3]; /**< offset 4..12: duty cycle register 0..2 */
} cellrv32_pwm_t;

/** PWM module hardware access (#cellrv32_pwm_t) */
#define CELLRV32_PWM ((cellrv32_pwm_t*) (CELLRV32_PWM_BASE))

/** PWM control register bits */
enum CELLRV32_PWM_CTRL_enum {
  PWM_CTRL_EN    =  0, /**< PWM control register(0) (r/w): PWM controller enable */
  PWM_CTRL_PRSC0 =  1, /**< PWM control register(1) (r/w): Clock prescaler select bit 0 */
  PWM_CTRL_PRSC1 =  2, /**< PWM control register(2) (r/w): Clock prescaler select bit 1 */
  PWM_CTRL_PRSC2 =  3  /**< PWM control register(3) (r/w): Clock prescaler select bit 2 */
};
/**@}*/


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
int     cellrv32_pwm_available(void);
void    cellrv32_pwm_setup(int prsc);
void    cellrv32_pwm_disable(void);
void    cellrv32_pwm_enable(void);
int     cellrv32_pmw_get_num_channels(void);
void    cellrv32_pwm_set(int channel, uint8_t dc);
uint8_t cellrv32_pwm_get(int channel);
/**@}*/

#endif // cellrv32_pwm_h
