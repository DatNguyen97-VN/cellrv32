// #################################################################################################
// # << CELLRV32: cellrv32_xirq.c - External Interrupt controller HW Driver >>                     #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_xirq.c
 * @brief External Interrupt controller HW driver source file.
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_xirq.h"


/**********************************************************************//**
 * The >private< trap vector look-up table of the XIRQ.
 **************************************************************************/
static uint32_t __cellrv32_xirq_vector_lut[32] __attribute__((unused)); // trap handler vector table

// private functions
static void __cellrv32_xirq_core(void);
static void __cellrv32_xirq_dummy_handler(void);


/**********************************************************************//**
 * Check if external interrupt controller was synthesized.
 *
 * @return 0 if XIRQ was not synthesized, 1 if EXTIRQ is available.
 **************************************************************************/
int cellrv32_xirq_available(void) {

  if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_XIRQ)) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Initialize XIRQ controller.
 *
 * @note All interrupt channels will be deactivated, all pending IRQs will be deleted and all
 * handler addresses will be deleted.
 * @return 0 if success, 1 if error.
 **************************************************************************/
int cellrv32_xirq_setup(void) {

  CELLRV32_XIRQ->IER = 0; // disable all input channels
  CELLRV32_XIRQ->IPR = 0; // clear all pending IRQs
  CELLRV32_XIRQ->SCR = 0; // acknowledge (clear) XIRQ interrupt

  int i;
  for (i=0; i<32; i++) {
    __cellrv32_xirq_vector_lut[i] = (uint32_t)(&__cellrv32_xirq_dummy_handler);
  }

  // register XIRQ handler in CELLRV32 RTE
  return cellrv32_rte_handler_install(XIRQ_RTE_ID, __cellrv32_xirq_core);
}


/**********************************************************************//**
 * Globally enable XIRQ interrupts (via according FIRQ channel).
 **************************************************************************/
void cellrv32_xirq_global_enable(void) {

  // enable XIRQ fast interrupt channel
  cellrv32_cpu_csr_set(CSR_MIE, 1 << XIRQ_FIRQ_ENABLE);
}


/**********************************************************************//**
 * Globally disable XIRQ interrupts (via according FIRQ channel).
 **************************************************************************/
void cellrv32_xirq_global_disable(void) {

  // enable XIRQ fast interrupt channel
  cellrv32_cpu_csr_clr(CSR_MIE, 1 << XIRQ_FIRQ_ENABLE);
}


/**********************************************************************//**
 * Get number of implemented XIRQ channels
 *
 * @return Number of implemented channels (0..32).
 **************************************************************************/
int cellrv32_xirq_get_num(void) {

  uint32_t enable;
  int i, cnt;

  if (cellrv32_xirq_available()) {

    cellrv32_cpu_csr_clr(CSR_MIE, 1 << XIRQ_FIRQ_ENABLE); // make sure XIRQ cannot fire
    CELLRV32_XIRQ->IER = 0xffffffff; // try to set all enable flags
    enable = CELLRV32_XIRQ->IER; // read back actually set flags

    // count set bits in enable
    cnt = 0;
    for (i=0; i<32; i++) {
      if (enable & 1) {
        cnt++;
      }
      enable >>= 1;
    }
    return cnt;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Clear pending interrupt.
 *
 * @param[in] ch XIRQ interrupt channel (0..31).
 **************************************************************************/
void cellrv32_xirq_clear_pending(uint8_t ch) {

  if (ch < 32) { // channel valid?
    CELLRV32_XIRQ->IPR = ~(1 << ch);
  }
}


/**********************************************************************//**
 * Enable IRQ channel.
 *
 * @param[in] ch XIRQ interrupt channel (0..31).
 **************************************************************************/
void cellrv32_xirq_channel_enable(uint8_t ch) {

  if (ch < 32) { // channel valid?
    CELLRV32_XIRQ->IER |= 1 << ch;
  }
}


/**********************************************************************//**
 * Disable IRQ channel.
 *
 * @param[in] ch XIRQ interrupt channel (0..31).
 **************************************************************************/
void cellrv32_xirq_channel_disable(uint8_t ch) {

  if (ch < 32) { // channel valid?
    CELLRV32_XIRQ->IER &= ~(1 << ch);
  }
}


/**********************************************************************//**
 * Install exception handler function for XIRQ channel.
 *
 * @note This will also activate the according XIRQ channel and clear a pending IRQ at this channel.
 *
 * @param[in] ch XIRQ interrupt channel (0..31).
 * @param[in] handler The actual handler function for the specified exception (function MUST be of type "void function(void);").
 * @return 0 if success, 1 if error.
 **************************************************************************/
int cellrv32_xirq_install(uint8_t ch, void (*handler)(void)) {

  // channel valid?
  if (ch < 32) {
    __cellrv32_xirq_vector_lut[ch] = (uint32_t)handler; // install handler
    uint32_t mask = 1 << ch;
    CELLRV32_XIRQ->IPR = ~mask; // clear if pending
    CELLRV32_XIRQ->IER |= mask; // enable channel
    return 0;
  }
  return 1;
}


/**********************************************************************//**
 * Uninstall exception handler function for XIRQ channel.
 *
 * @note This will also deactivate the according XIRQ channel and clear pending state.
 *
 * @param[in] ch XIRQ interrupt channel (0..31).
 * @return 0 if success, 1 if error.
 **************************************************************************/
int cellrv32_xirq_uninstall(uint8_t ch) {

  // channel valid?
  if (ch < 32) {
    __cellrv32_xirq_vector_lut[ch] = (uint32_t)(&__cellrv32_xirq_dummy_handler); // override using dummy handler
    uint32_t mask = 1 << ch;
    CELLRV32_XIRQ->IER &= ~mask; // disable channel
    CELLRV32_XIRQ->IPR = ~mask; // clear if pending
    return 0;
  }
  return 1;
}


/**********************************************************************//**
 * This is the actual second-level (F)IRQ handler for the XIRQ. It will
 * call the previously installed handler if an XIRQ fires.
 **************************************************************************/
static void __cellrv32_xirq_core(void) {

  cellrv32_cpu_csr_write(CSR_MIP, ~(1 << XIRQ_FIRQ_PENDING)); // acknowledge XIRQ FIRQ

  uint32_t src = CELLRV32_XIRQ->SCR; // get IRQ source (with highest priority)

  // execute handler
  uint32_t xirq_handler = __cellrv32_xirq_vector_lut[src];
  void (*handler_pnt)(void);
  handler_pnt = (void*)xirq_handler;
  (*handler_pnt)();

  uint32_t mask = 1 << src;
  CELLRV32_XIRQ->IPR = ~mask; // clear current pending interrupt
  CELLRV32_XIRQ->SCR = 0; // acknowledge current XIRQ interrupt
}


/**********************************************************************//**
 * XIRQ dummy handler.
 **************************************************************************/
static void __cellrv32_xirq_dummy_handler(void) {

  asm volatile ("nop");
}

