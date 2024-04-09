// #################################################################################################
// # << CELLRV32: legacy.h - Backwards compatibility wrappers and functions >>                     #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file legacy.h
 * @brief Wrappers and functions for backwards compatibility.
 * @warning Do not use these functions for new designs as they are no longer
 * supported and might get removed in the future.
 **************************************************************************/

#ifndef cellrv32_legacy_h
#define cellrv32_legacy_h


// ================================================================================================
// UART0 & UART1
// ================================================================================================

/**********************************************************************//**
 * @name UART0: Backward compatibility Wrapper, #cellrv32_uart_h
 **************************************************************************/
/**@{*/
#define cellrv32_uart0_available()                  cellrv32_uart_available(CELLRV32_UART0)
#define cellrv32_uart0_setup(baudrate, irq_mask)    cellrv32_uart_setup(CELLRV32_UART0, baudrate, irq_mask)
#define cellrv32_uart0_disable()                    cellrv32_uart_disable(CELLRV32_UART0)
#define cellrv32_uart0_enable()                     cellrv32_uart_enable(CELLRV32_UART0)
#define cellrv32_uart0_rtscts_disable()             cellrv32_uart_rtscts_disable(CELLRV32_UART0)
#define cellrv32_uart0_rtscts_enable()              cellrv32_uart_rtscts_enable(CELLRV32_UART0)
#define cellrv32_uart0_putc(c)                      cellrv32_uart_putc(CELLRV32_UART0, c)
#define cellrv32_uart0_tx_busy()                    cellrv32_uart_tx_busy(CELLRV32_UART0)
#define cellrv32_uart0_getc()                       cellrv32_uart_getc(CELLRV32_UART0)
#define cellrv32_uart0_char_received()              cellrv32_uart_char_received(CELLRV32_UART0)
#define cellrv32_uart0_char_received_get()          cellrv32_uart_char_received_get(CELLRV32_UART0)
#define cellrv32_uart0_puts(s)                      cellrv32_uart_puts(CELLRV32_UART0, s)
#define cellrv32_uart0_printf(...)                  cellrv32_uart_printf(CELLRV32_UART0, __VA_ARGS__)
#define cellrv32_uart0_scan(buffer, max_size, echo) cellrv32_uart_scan(CELLRV32_UART0, buffer, max_size, echo)
/**@}*/

/**********************************************************************//**
 * @name UART1: Backward compatibility Wrapper, #cellrv32_uart_h
 **************************************************************************/
/**@{*/
#define cellrv32_uart1_available()                  cellrv32_uart_available(CELLRV32_UART1)
#define cellrv32_uart1_setup(baudrate, irq_mask)    cellrv32_uart_setup(CELLRV32_UART1, baudrate, irq_mask)
#define cellrv32_uart1_disable()                    cellrv32_uart_disable(CELLRV32_UART1)
#define cellrv32_uart1_enable()                     cellrv32_uart_enable(CELLRV32_UART1)
#define cellrv32_uart1_rtscts_disable()             cellrv32_uart_rtscts_disable(CELLRV32_UART1)
#define cellrv32_uart1_rtscts_enable()              cellrv32_uart_rtscts_enable(CELLRV32_UART1)
#define cellrv32_uart1_putc(c)                      cellrv32_uart_putc(CELLRV32_UART1, c)
#define cellrv32_uart1_tx_busy()                    cellrv32_uart_tx_busy(CELLRV32_UART1)
#define cellrv32_uart1_getc()                       cellrv32_uart_getc(CELLRV32_UART1)
#define cellrv32_uart1_char_received()              cellrv32_uart_char_received(CELLRV32_UART1)
#define cellrv32_uart1_char_received_get()          cellrv32_uart_char_received_get(CELLRV32_UART1)
#define cellrv32_uart1_puts(s)                      cellrv32_uart_puts(CELLRV32_UART1, s)
#define cellrv32_uart1_printf(...)                  cellrv32_uart_printf(CELLRV32_UART1, __VA_ARGS__)
#define cellrv32_uart1_scan(buffer, max_size, echo) cellrv32_uart_scan(CELLRV32_UART1, buffer, max_size, echo)
/**@}*/

/**********************************************************************//**
 * Print string (zero-terminated) via UART0. Print full line break "\r\n" for every '\n'.
 * @note This function is blocking.
 * @warning This function is deprecated!
 * @param[in] s Pointer to string.
 **************************************************************************/
inline void __attribute__((deprecated("Use 'cellrv32_uart0_puts()' instead."))) cellrv32_uart0_print(const char *s) {
  cellrv32_uart0_puts(s);
}

/**********************************************************************//**
 * Print string (zero-terminated) via UART1. Print full line break "\r\n" for every '\n'.
 * @note This function is blocking.
 * @warning This function is deprecated!
 * @param[in] s Pointer to string.
 **************************************************************************/
inline void __attribute__((deprecated("Use 'cellrv32_uart0_puts()' instead."))) cellrv32_uart1_print(const char *s) {
  cellrv32_uart1_puts(s);
}


// ================================================================================================
// Custom Functions Unit (CFU)
// ================================================================================================

/**********************************************************************//**
 * @name Backward-compatibility layer (before version v1.7.8.2)
 * @warning This function is deprecated!
 **************************************************************************/
/**@{*/
/** R3-type CFU custom instruction 0 (funct3 = 000) */
#define cellrv32_cfu_cmd0(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 0, rs1, rs2)
/** R3-type CFU custom instruction 1 (funct3 = 001) */
#define cellrv32_cfu_cmd1(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 1, rs1, rs2)
/** R3-type CFU custom instruction 2 (funct3 = 010) */
#define cellrv32_cfu_cmd2(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 2, rs1, rs2)
/** R3-type CFU custom instruction 3 (funct3 = 011) */
#define cellrv32_cfu_cmd3(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 3, rs1, rs2)
/** R3-type CFU custom instruction 4 (funct3 = 100) */
#define cellrv32_cfu_cmd4(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 4, rs1, rs2)
/** R3-type CFU custom instruction 5 (funct3 = 101) */
#define cellrv32_cfu_cmd5(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 5, rs1, rs2)
/** R3-type CFU custom instruction 6 (funct3 = 110) */
#define cellrv32_cfu_cmd6(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 6, rs1, rs2)
/** R3-type CFU custom instruction 7 (funct3 = 111) */
#define cellrv32_cfu_cmd7(funct7, rs1, rs2) cellrv32_cfu_r3_instr(funct7, 7, rs1, rs2)
/**@}*/


// ================================================================================================
// CPU Core
// ================================================================================================

/**********************************************************************//**
 * Get current system time from time[h] CSR.
 * @note This function requires the MTIME system timer to be implemented.
 * @return Current system time (64 bit).
 **************************************************************************/
inline uint64_t __attribute__((deprecated("Use 'cellrv32_mtime_get_time()' instead."))) cellrv32_cpu_get_systime(void) {
  return cellrv32_mtime_get_time();
}

/**********************************************************************//**
 * Enable global CPU interrupts (via MIE flag in mstatus CSR).
 * @note Interrupts are always enabled when the CPU is in user-mode.
 **************************************************************************/
inline void __attribute__ ((always_inline, deprecated("Use 'cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE)' instead."))) cellrv32_cpu_eint(void) {
  cellrv32_cpu_csr_set(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);
}

/**********************************************************************//**
 * Disable global CPU interrupts (via MIE flag in mstatus CSR).
 * @note Interrupts are always enabled when the CPU is in user-mode.
 **************************************************************************/
inline void __attribute__ ((always_inline, deprecated("Use 'cellrv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE)' instead."))) cellrv32_cpu_dint(void) {
  cellrv32_cpu_csr_clr(CSR_MSTATUS, 1 << CSR_MSTATUS_MIE);
}


#endif // cellrv32_legacy_h
