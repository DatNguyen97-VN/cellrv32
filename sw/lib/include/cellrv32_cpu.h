// #################################################################################################
// # << CELLRV32: cellrv32_cpu.h - CPU Core Functions HW Driver >>                                 #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cpu.h
 * @brief CPU Core Functions HW driver header file.
 **************************************************************************/

#ifndef cellrv32_cpu_h
#define cellrv32_cpu_h


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
void     cellrv32_cpu_irq_enable(int irq_sel);
void     cellrv32_cpu_irq_disable(int irq_sel);
uint64_t cellrv32_cpu_get_cycle(void);
void     cellrv32_cpu_set_mcycle(uint64_t value);
uint64_t cellrv32_cpu_get_instret(void);
void     cellrv32_cpu_set_minstret(uint64_t value);
void     cellrv32_cpu_delay_ms(uint32_t time_ms);
uint32_t cellrv32_cpu_get_clk_from_prsc(int prsc);
uint32_t cellrv32_cpu_pmp_get_num_regions(void);
uint32_t cellrv32_cpu_pmp_get_granularity(void);
int      cellrv32_cpu_pmp_configure_region(uint32_t index, uint32_t base, uint8_t config);
uint32_t cellrv32_cpu_hpm_get_num_counters(void);
uint32_t cellrv32_cpu_hpm_get_size(void);
void     cellrv32_cpu_goto_user_mode(void);
/**@}*/


/**********************************************************************//**
 * Prototype for "after-main handler". This function is called if main() returns.
 *
 * @param[in] return_code Return value of main() function.
 **************************************************************************/
extern void __attribute__ ((weak)) __cellrv32_crt0_after_main(int32_t return_code);


/**********************************************************************//**
 * Store unsigned word to address space.
 *
 * @note An unaligned access address will raise an alignment exception.
 *
 * @param[in] addr Address (32-bit).
 * @param[in] wdata Data word (32-bit) to store.
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_store_unsigned_word(uint32_t addr, uint32_t wdata) {

  uint32_t reg_addr = addr;
  uint32_t reg_data = wdata;

  asm volatile ("sw %[da], 0(%[ad])" : : [da] "r" (reg_data), [ad] "r" (reg_addr));
}


/**********************************************************************//**
 * Store unsigned half-word to address space.
 *
 * @note An unaligned access address will raise an alignment exception.
 *
 * @param[in] addr Address (32-bit).
 * @param[in] wdata Data half-word (16-bit) to store.
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_store_unsigned_half(uint32_t addr, uint16_t wdata) {

  uint32_t reg_addr = addr;
  uint32_t reg_data = (uint32_t)wdata;

  asm volatile ("sh %[da], 0(%[ad])" : : [da] "r" (reg_data), [ad] "r" (reg_addr));
}


/**********************************************************************//**
 * Store unsigned byte to address space.
 *
 * @param[in] addr Address (32-bit).
 * @param[in] wdata Data byte (8-bit) to store.
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_store_unsigned_byte(uint32_t addr, uint8_t wdata) {

  uint32_t reg_addr = addr;
  uint32_t reg_data = (uint32_t)wdata;

  asm volatile ("sb %[da], 0(%[ad])" : : [da] "r" (reg_data), [ad] "r" (reg_addr));
}


/**********************************************************************//**
 * Load unsigned word from address space.
 *
 * @note An unaligned access address will raise an alignment exception.
 *
 * @param[in] addr Address (32-bit).
 * @return Read data word (32-bit).
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) cellrv32_cpu_load_unsigned_word(uint32_t addr) {

  uint32_t reg_addr = addr;
  uint32_t reg_data;

  asm volatile ("lw %[da], 0(%[ad])" : [da] "=r" (reg_data) : [ad] "r" (reg_addr));

  return reg_data;
}


/**********************************************************************//**
 * Load unsigned half-word from address space.
 *
 * @note An unaligned access address will raise an alignment exception.
 *
 * @param[in] addr Address (32-bit).
 * @return Read data half-word (16-bit).
 **************************************************************************/
inline uint16_t __attribute__ ((always_inline)) cellrv32_cpu_load_unsigned_half(uint32_t addr) {

  uint32_t reg_addr = addr;
  uint16_t reg_data;

  asm volatile ("lhu %[da], 0(%[ad])" : [da] "=r" (reg_data) : [ad] "r" (reg_addr));

  return reg_data;
}


/**********************************************************************//**
 * Load signed half-word from address space.
 *
 * @note An unaligned access address will raise an alignment exception.
 *
 * @param[in] addr Address (32-bit).
 * @return Read data half-word (16-bit).
 **************************************************************************/
inline int16_t __attribute__ ((always_inline)) cellrv32_cpu_load_signed_half(uint32_t addr) {

  uint32_t reg_addr = addr;
  int16_t reg_data;

  asm volatile ("lh %[da], 0(%[ad])" : [da] "=r" (reg_data) : [ad] "r" (reg_addr));

  return reg_data;
}


/**********************************************************************//**
 * Load unsigned byte from address space.
 *
 * @param[in] addr Address (32-bit).
 * @return Read data byte (8-bit).
 **************************************************************************/
inline uint8_t __attribute__ ((always_inline)) cellrv32_cpu_load_unsigned_byte(uint32_t addr) {

  uint32_t reg_addr = addr;
  uint8_t reg_data;

  asm volatile ("lbu %[da], 0(%[ad])" : [da] "=r" (reg_data) : [ad] "r" (reg_addr));

  return reg_data;
}


/**********************************************************************//**
 * Load signed byte from address space.
 *
 * @param[in] addr Address (32-bit).
 * @return Read data byte (8-bit).
 **************************************************************************/
inline int8_t __attribute__ ((always_inline)) cellrv32_cpu_load_signed_byte(uint32_t addr) {

  uint32_t reg_addr = addr;
  int8_t reg_data;

  asm volatile ("lb %[da], 0(%[ad])" : [da] "=r" (reg_data) : [ad] "r" (reg_addr));

  return reg_data;
}


/**********************************************************************//**
 * Read data from CPU control and status register (CSR).
 *
 * @param[in] csr_id ID of CSR to read. See #CELLRV32_CSR_enum.
 * @return Read data (uint32_t).
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) cellrv32_cpu_csr_read(const int csr_id) {

  uint32_t csr_data;

  asm volatile ("csrr %[result], %[input_i]" : [result] "=r" (csr_data) : [input_i] "i" (csr_id));

  return csr_data;
}


/**********************************************************************//**
 * Write data to CPU control and status register (CSR).
 *
 * @param[in] csr_id ID of CSR to write. See #CELLRV32_CSR_enum.
 * @param[in] data Data to write (uint32_t).
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_csr_write(const int csr_id, uint32_t data) {

  uint32_t csr_data = data;

  asm volatile ("csrw %[input_i], %[input_j]" :  : [input_i] "i" (csr_id), [input_j] "r" (csr_data));
}


/**********************************************************************//**
 * Set bit(s) in CPU control and status register (CSR).
 *
 * @param[in] csr_id ID of CSR to write. See #CELLRV32_CSR_enum.
 * @param[in] mask Bit mask (high-active) to set bits (uint32_t).
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_csr_set(const int csr_id, uint32_t mask) {

  uint32_t csr_data = mask;

  asm volatile ("csrs %[input_i], %[input_j]" :  : [input_i] "i" (csr_id), [input_j] "r" (csr_data));
}


/**********************************************************************//**
 * Clear bit(s) in CPU control and status register (CSR).
 *
 * @param[in] csr_id ID of CSR to write. See #CELLRV32_CSR_enum.
 * @param[in] mask Bit mask (high-active) to clear bits (uint32_t).
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_csr_clr(const int csr_id, uint32_t mask) {

  uint32_t csr_data = mask;

  asm volatile ("csrc %[input_i], %[input_j]" :  : [input_i] "i" (csr_id), [input_j] "r" (csr_data));
}


/**********************************************************************//**
 * Put CPU into "sleep" mode.
 *
 * @note This function executes the WFI instruction.
 * The WFI (wait for interrupt) instruction will make the CPU stall until
 * an interrupt request is detected. Interrupts have to be globally enabled
 * and at least one external source must be enabled (like the MTI machine
 * timer interrupt) to allow the CPU to wake up again. If 'Zicsr' CPU extension is disabled,
 * this will permanently stall the CPU.
 **************************************************************************/
inline void __attribute__ ((always_inline)) cellrv32_cpu_sleep(void) {

  asm volatile ("wfi");
}


#endif // cellrv32_cpu_h
