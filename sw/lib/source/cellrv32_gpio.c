// #################################################################################################
// # << CELLRV32: cellrv32_gpio.c - General Purpose Input/Output Port HW Driver (Source) >>        #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_gpio.c
 * @brief General purpose input/output port unit (GPIO) HW driver source file.
 *
 * @note These functions should only be used if the GPIO unit was synthesized (IO_GPIO_EN = true).
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_gpio.h"


/**********************************************************************//**
 * Check if GPIO unit was synthesized.
 *
 * @return 0 if GPIO was not synthesized, 1 if GPIO is available.
 **************************************************************************/
int cellrv32_gpio_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_GPIO)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Set single pin of GPIO's output port.
 *
 * @param[in] pin Output pin number to be set (0..63).
 **************************************************************************/
void cellrv32_gpio_pin_set(int pin) {

  uint32_t mask = (uint32_t)(1 << (pin & 0x1f));

  if (pin < 32) {
    CELLRV32_GPIO->OUTPUT_LO |= mask;
  }
  else {
    CELLRV32_GPIO->OUTPUT_HI |= mask;
  }
}


/**********************************************************************//**
 * Clear single pin of GPIO's output port.
 *
 * @param[in] pin Output pin number to be cleared (0..63).
 **************************************************************************/
void cellrv32_gpio_pin_clr(int pin) {

  uint32_t mask = (uint32_t)(1 << (pin & 0x1f));

  if (pin < 32) {
    CELLRV32_GPIO->OUTPUT_LO &= ~mask;
  }
  else {
    CELLRV32_GPIO->OUTPUT_HI &= ~mask;
  }
}


/**********************************************************************//**
 * Toggle single pin of GPIO's output port.
 *
 * @param[in] pin Output pin number to be toggled (0..63).
 **************************************************************************/
void cellrv32_gpio_pin_toggle(int pin) {

  uint32_t mask = (uint32_t)(1 << (pin & 0x1f));

  if (pin < 32) {
    CELLRV32_GPIO->OUTPUT_LO ^= mask;
  }
  else {
    CELLRV32_GPIO->OUTPUT_HI ^= mask;
  }
}


/**********************************************************************//**
 * Get single pin of GPIO's input port.
 *
 * @param[in] pin Input pin to be read (0..63).
 * @return =0 if pin is low, !=0 if pin is high.
 **************************************************************************/
uint32_t cellrv32_gpio_pin_get(int pin) {

  uint32_t mask = (uint32_t)(1 << (pin & 0x1f));

  if (pin < 32) {
    return CELLRV32_GPIO->INPUT_LO & mask;
  }
  else {
    return CELLRV32_GPIO->INPUT_HI & mask;
  }
}


/**********************************************************************//**
 * Set complete GPIO output port.
 *
 * @param[in] port_data New output port value (64-bit).
 **************************************************************************/
void cellrv32_gpio_port_set(uint64_t port_data) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } data;

  data.uint64 = port_data;
  CELLRV32_GPIO->OUTPUT_LO = data.uint32[0];
  CELLRV32_GPIO->OUTPUT_HI = data.uint32[1];
}


/**********************************************************************//**
 * Get complete GPIO input port.
 *
 * @return Current input port state (64-bit).
 **************************************************************************/
uint64_t cellrv32_gpio_port_get(void) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } data;

  data.uint32[0] = CELLRV32_GPIO->INPUT_LO;
  data.uint32[1] = CELLRV32_GPIO->INPUT_HI;

  return data.uint64;
}

