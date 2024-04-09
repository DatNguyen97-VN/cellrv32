// #################################################################################################
// # << CELLRV32: cellrv32_cpu.c - CPU Core Functions HW Driver >>                                 #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cpu.c
 * @brief CPU Core Functions HW driver source file.
 **************************************************************************/

#include "cellrv32.h"
#include "cellrv32_cpu.h"


/**********************************************************************//**
 * Unavailable extensions warning.
 **************************************************************************/
#if defined __riscv_d || (__riscv_flen == 64)
  #error Double-precision floating-point extension <D/Zdinx> is NOT supported!
#endif

#if (__riscv_xlen > 32)
  #error Only 32-bit <rv32> is supported!
#endif

#ifdef __riscv_fdiv
  #warning Floating-point division instruction <FDIV> is NOT supported yet!
#endif

#ifdef __riscv_fsqrt
  #warning Floating-point square root instruction <FSQRT> is NOT supported yet!
#endif


/**********************************************************************//**
 * >Private< helper functions.
 **************************************************************************/
static uint32_t __cellrv32_cpu_pmp_cfg_read(uint32_t index);
static void __cellrv32_cpu_pmp_cfg_write(uint32_t index, uint32_t data);


/**********************************************************************//**
 * Enable specific interrupt channel.
 * @note This functions also tries to clear the pending flag of the interrupt.
 *
 * @param[in] irq_sel CPU interrupt select. See #CELLRV32_CSR_MIE_enum.
 **************************************************************************/
void cellrv32_cpu_irq_enable(int irq_sel) {

  cellrv32_cpu_csr_clr(CSR_MIP, 1 << (irq_sel & 0x1f)); // clear pending
  cellrv32_cpu_csr_set(CSR_MIE, 1 << (irq_sel & 0x1f)); // enable
}


/**********************************************************************//**
 * Disable specific interrupt channel.
 * @note This functions also tries to clear the pending flag of the interrupt.
 *
 * @param[in] irq_sel CPU interrupt select. See #CELLRV32_CSR_MIE_enum.
 **************************************************************************/
void cellrv32_cpu_irq_disable(int irq_sel) {

  cellrv32_cpu_csr_clr(CSR_MIE, 1 << (irq_sel & 0x1f)); // disable
  cellrv32_cpu_csr_clr(CSR_MIP, 1 << (irq_sel & 0x1f)); // clear pending
}


/**********************************************************************//**
 * Get cycle counter from cycle[h].
 *
 * @return Current cycle counter (64 bit).
 **************************************************************************/
uint64_t cellrv32_cpu_get_cycle(void) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  uint32_t tmp1, tmp2, tmp3;
  while(1) {
    tmp1 = cellrv32_cpu_csr_read(CSR_CYCLEH);
    tmp2 = cellrv32_cpu_csr_read(CSR_CYCLE);
    tmp3 = cellrv32_cpu_csr_read(CSR_CYCLEH);
    if (tmp1 == tmp3) {
      break;
    }
  }

  cycles.uint32[0] = tmp2;
  cycles.uint32[1] = tmp3;

  return cycles.uint64;
}


/**********************************************************************//**
 * Set machine cycle counter mcycle[h].
 *
 * @param[in] value New value for mcycle[h] CSR (64-bit).
 **************************************************************************/
void cellrv32_cpu_set_mcycle(uint64_t value) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  cycles.uint64 = value;

  // prevent low-to-high word overflow while writing
  cellrv32_cpu_csr_write(CSR_MCYCLE,  0);
  cellrv32_cpu_csr_write(CSR_MCYCLEH, cycles.uint32[1]);
  cellrv32_cpu_csr_write(CSR_MCYCLE,  cycles.uint32[0]);

  asm volatile("nop"); // delay due to CPU-internal cycle write buffer
}


/**********************************************************************//**
 * Get retired instructions counter from instret[h].
 *
 * @return Current instructions counter (64 bit).
 **************************************************************************/
uint64_t cellrv32_cpu_get_instret(void) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  uint32_t tmp1, tmp2, tmp3;
  while(1) {
    tmp1 = cellrv32_cpu_csr_read(CSR_INSTRETH);
    tmp2 = cellrv32_cpu_csr_read(CSR_INSTRET);
    tmp3 = cellrv32_cpu_csr_read(CSR_INSTRETH);
    if (tmp1 == tmp3) {
      break;
    }
  }

  cycles.uint32[0] = tmp2;
  cycles.uint32[1] = tmp3;

  return cycles.uint64;
}


/**********************************************************************//**
 * Set machine retired instructions counter minstret[h].
 *
 * @param[in] value New value for mcycle[h] CSR (64-bit).
 **************************************************************************/
void cellrv32_cpu_set_minstret(uint64_t value) {

  union {
    uint64_t uint64;
    uint32_t uint32[sizeof(uint64_t)/sizeof(uint32_t)];
  } cycles;

  cycles.uint64 = value;

  // prevent low-to-high word overflow while writing
  cellrv32_cpu_csr_write(CSR_MINSTRET,  0);
  cellrv32_cpu_csr_write(CSR_MINSTRETH, cycles.uint32[1]);
  cellrv32_cpu_csr_write(CSR_MINSTRET,  cycles.uint32[0]);

  asm volatile("nop"); // delay due to CPU-internal instret write buffer
}


/**********************************************************************//**
 * Delay function using busy wait.
 *
 * @note This function uses the cycle CPU counter if available. Otherwise
 * the MTIME system timer is used if available. A simple loop is used as
 * alternative fall-back (imprecise!).
 *
 * @param[in] time_ms Time in ms to wait (unsigned 32-bit).
 **************************************************************************/
void cellrv32_cpu_delay_ms(uint32_t time_ms) {

  uint32_t clock = CELLRV32_SYSINFO->CLK; // clock ticks per second
  clock = clock / 1000; // clock ticks per ms
  uint64_t wait_cycles = ((uint64_t)clock) * ((uint64_t)time_ms);
  uint64_t tmp = 0;

  // use CYCLE CSRs
  // -------------------------------------------
  if ( (cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZICNTR)) && // cycle counter available?
       ((cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT) & (1<<CSR_MCOUNTINHIBIT_CY)) == 0) ) { // counter is running?

    tmp = cellrv32_cpu_get_cycle() + wait_cycles;
    while (cellrv32_cpu_get_cycle() < tmp);
  }

  // use MTIME machine timer
  // -------------------------------------------
  else if (CELLRV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_MTIME)) { // MTIME timer available?

    tmp = cellrv32_mtime_get_time() + wait_cycles;
    while (cellrv32_mtime_get_time() < tmp);
  }

  // simple loop as fall-back (imprecise!)
  // -------------------------------------------
  else {

    const uint32_t loop_cycles_c = 16; // clock cycles per iteration of the ASM loop
    uint32_t iterations = (uint32_t)(wait_cycles / loop_cycles_c);

    asm volatile (" .balign 4                                        \n" // make sure this is 32-bit aligned
                  " __cellrv32_cpu_delay_ms_start:                    \n"
                  " beq  %[cnt_r], zero, __cellrv32_cpu_delay_ms_end  \n" // 3 cycles (not taken)
                  " beq  %[cnt_r], zero, __cellrv32_cpu_delay_ms_end  \n" // 3 cycles (never taken)
                  " addi %[cnt_w], %[cnt_r], -1                      \n" // 2 cycles
                  " nop                                              \n" // 2 cycles
                  " j    __cellrv32_cpu_delay_ms_start                \n" // 6 cycles
                  " __cellrv32_cpu_delay_ms_end: "
                  : [cnt_w] "=r" (iterations) : [cnt_r] "r" (iterations));
  }
}


/**********************************************************************//**
 * Get actual clocking frequency from prescaler select #CELLRV32_CLOCK_PRSC_enum
 *
 * @param[in] prsc Prescaler select #CELLRV32_CLOCK_PRSC_enum.
 * return Actual _raw_ clock frequency in Hz.
 **************************************************************************/
uint32_t cellrv32_cpu_get_clk_from_prsc(int prsc) {

  if ((prsc < CLK_PRSC_2) || (prsc > CLK_PRSC_4096)) { // out of range?
    return 0;
  }

  uint32_t res = 0;
  uint32_t clock = CELLRV32_SYSINFO->CLK; // SoC main clock in Hz

  switch(prsc & 7) {
    case CLK_PRSC_2    : res = clock/2    ; break;
    case CLK_PRSC_4    : res = clock/4    ; break;
    case CLK_PRSC_8    : res = clock/8    ; break;
    case CLK_PRSC_64   : res = clock/64   ; break;
    case CLK_PRSC_128  : res = clock/128  ; break;
    case CLK_PRSC_1024 : res = clock/1024 ; break;
    case CLK_PRSC_2048 : res = clock/2048 ; break;
    case CLK_PRSC_4096 : res = clock/4096 ; break;
    default: break;
  }

  return res;
}


/**********************************************************************//**
 * Physical memory protection (PMP): Get number of available regions.
 *
 * @warning This function overrides all available PMPCFG* CSRs!
 * @note This function requires the PMP CPU extension.
 *
 * @return Returns number of available PMP regions.
 **************************************************************************/
uint32_t cellrv32_cpu_pmp_get_num_regions(void) {

  // PMP implemented at all?
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_PMP)) == 0) {
    return 0;
  }

  // try setting R bit in all PMPCFG CSRs
  const uint32_t mask = 0x01010101;
  __cellrv32_cpu_pmp_cfg_write(0, mask);
  __cellrv32_cpu_pmp_cfg_write(1, mask);
  __cellrv32_cpu_pmp_cfg_write(2, mask);
  __cellrv32_cpu_pmp_cfg_write(3, mask);

  // sum up all written ones (only available PMPCFG* CSRs/entries will return =! 0)
  union {
    uint32_t uint32;
    uint8_t  uint8[sizeof(uint32_t)/sizeof(uint8_t)];
  } cnt;

  cnt.uint32 = 0;
  cnt.uint32 += __cellrv32_cpu_pmp_cfg_read(0) & mask;
  cnt.uint32 += __cellrv32_cpu_pmp_cfg_read(1) & mask;
  cnt.uint32 += __cellrv32_cpu_pmp_cfg_read(2) & mask;
  cnt.uint32 += __cellrv32_cpu_pmp_cfg_read(3) & mask;

  // sum up bytes
  uint32_t num_regions = 0;
  num_regions += (uint32_t)cnt.uint8[0];
  num_regions += (uint32_t)cnt.uint8[1];
  num_regions += (uint32_t)cnt.uint8[2];
  num_regions += (uint32_t)cnt.uint8[3];

  return num_regions;
}


/**********************************************************************//**
 * Physical memory protection (PMP): Get minimal region size (granularity).
 *
 * @warning This function overrides PMPCFG0[0] and PMPADDR0 CSRs!
 * @note This function requires the PMP CPU extension.
 *
 * @return Returns minimal region size in bytes. Returns zero on error.
 **************************************************************************/
uint32_t cellrv32_cpu_pmp_get_granularity(void) {

  // PMP implemented at all?
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_PMP)) == 0) {
    return 0;
  }

  cellrv32_cpu_csr_write(CSR_PMPCFG0, cellrv32_cpu_csr_read(CSR_PMPCFG0) & 0xffffff00); // disable entry 0
  cellrv32_cpu_csr_write(CSR_PMPADDR0, -1); // try to set all bits
  uint32_t tmp = cellrv32_cpu_csr_read(CSR_PMPADDR0);

  // no bits set at all -> fail
  if (tmp == 0) {
    return 0;
  }

  // count trailing zeros
  uint32_t i = 2;
  while(1) {
    if (tmp & 1) {
      break;
    }
    tmp >>= 1;
    i++;
  }

  return 1<<i;
}


/**********************************************************************//**
 * Physical memory protection (PMP): Configure region.
 *
 * @warning Only TOR mode is supported.
 *
 * @note This function requires the PMP CPU extension.
 * @note Only use available PMP regions. Check before via cellrv32_cpu_pmp_get_regions(void).
 *
 * @param[in] index Region number (index, 0..PMP_NUM_REGIONS-1).
 * @param[in] base Region base address.
 * @param[in] config Region configuration byte (see #CELLRV32_PMPCFG_ATTRIBUTES_enum).
 * @return Returns 0 on success, !=0 on failure.
 **************************************************************************/
int cellrv32_cpu_pmp_configure_region(uint32_t index, uint32_t base, uint8_t config) {

  if ((index > 15) || ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_PMP)) == 0)) {
    return 1;
  }

  // set base address
  base = base >> 2;
  switch(index & 0xf) {
    case 0:  cellrv32_cpu_csr_write(CSR_PMPADDR0,  base); break;
    case 1:  cellrv32_cpu_csr_write(CSR_PMPADDR1,  base); break;
    case 2:  cellrv32_cpu_csr_write(CSR_PMPADDR2,  base); break;
    case 3:  cellrv32_cpu_csr_write(CSR_PMPADDR3,  base); break;
    case 4:  cellrv32_cpu_csr_write(CSR_PMPADDR4,  base); break;
    case 5:  cellrv32_cpu_csr_write(CSR_PMPADDR5,  base); break;
    case 6:  cellrv32_cpu_csr_write(CSR_PMPADDR6,  base); break;
    case 7:  cellrv32_cpu_csr_write(CSR_PMPADDR7,  base); break;
    case 8:  cellrv32_cpu_csr_write(CSR_PMPADDR8,  base); break;
    case 9:  cellrv32_cpu_csr_write(CSR_PMPADDR9,  base); break;
    case 10: cellrv32_cpu_csr_write(CSR_PMPADDR10, base); break;
    case 11: cellrv32_cpu_csr_write(CSR_PMPADDR11, base); break;
    case 12: cellrv32_cpu_csr_write(CSR_PMPADDR12, base); break;
    case 13: cellrv32_cpu_csr_write(CSR_PMPADDR13, base); break;
    case 14: cellrv32_cpu_csr_write(CSR_PMPADDR14, base); break;
    case 15: cellrv32_cpu_csr_write(CSR_PMPADDR15, base); break;
    default: break;
  }

  // pmpcfg register index
  uint32_t pmpcfg_index = index >> 4; // 4 entries per pmpcfg csr

  // get current configuration
  uint32_t tmp = __cellrv32_cpu_pmp_cfg_read(pmpcfg_index);

  // clear old configuration
  uint32_t config_mask = (((uint32_t)0xFF) << ((index%4)*8));
  tmp = tmp & (~config_mask);

  // set configuration
  uint32_t config_new = ((uint32_t)config) << ((index%4)*8);
  tmp = tmp | config_new;
  __cellrv32_cpu_pmp_cfg_write(pmpcfg_index, tmp);

  // flush instruction and data queues and caches
  if (cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZIFENCEI)) {
    asm volatile ("fence.i");
  }
  asm volatile ("fence");

  // check if update was successful
  if ((__cellrv32_cpu_pmp_cfg_read(pmpcfg_index) & config_mask) == config_new) {
    return 0;
  } else {
    return 2;
  }
}


/**********************************************************************//**
 * Internal helper function: Read PMP configuration register 0..15.
 *
 * @param[in] index PMP CFG configuration register ID (0..15).
 * @return PMP CFG read data.
 **************************************************************************/
static uint32_t __cellrv32_cpu_pmp_cfg_read(uint32_t index) {

  uint32_t tmp = 0;
  switch (index & 3) {
    case 0: tmp = cellrv32_cpu_csr_read(CSR_PMPCFG0); break;
    case 1: tmp = cellrv32_cpu_csr_read(CSR_PMPCFG1); break;
    case 2: tmp = cellrv32_cpu_csr_read(CSR_PMPCFG2); break;
    case 3: tmp = cellrv32_cpu_csr_read(CSR_PMPCFG3); break;
    default: break;
  }

  return tmp;
}


/**********************************************************************//**
 * Internal helper function: Write PMP configuration register 0..3.
 *
 * @param[in] index PMP CFG configuration register ID (0..4).
 * @param[in] data PMP CFG write data.
 **************************************************************************/
static void __cellrv32_cpu_pmp_cfg_write(uint32_t index, uint32_t data) {

  switch (index & 3) {
    case 0: cellrv32_cpu_csr_write(CSR_PMPCFG0, data); break;
    case 1: cellrv32_cpu_csr_write(CSR_PMPCFG1, data); break;
    case 2: cellrv32_cpu_csr_write(CSR_PMPCFG2, data); break;
    case 3: cellrv32_cpu_csr_write(CSR_PMPCFG3, data); break;
    default: break;
  }
}


/**********************************************************************//**
 * Hardware performance monitors (HPM): Get number of available HPM counters.
 *
 * @return Returns number of available HPM counters (0..29).
 **************************************************************************/
uint32_t cellrv32_cpu_hpm_get_num_counters(void) {

  // HPMs implemented at all?
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZIHPM)) == 0) {
    return 0;
  }

  uint32_t mcountinhibit_tmp = cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT);

  // try to set all HPM bits
  uint32_t tmp = mcountinhibit_tmp;
  tmp |= 0xfffffff8U;
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, tmp);

  // count actually set bits
  uint32_t cnt = 0;
  tmp = cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT) >> 3; // remove IR, TM and CY
  while (tmp) {
    cnt++;
    tmp >>= 1;
  }

  // restore
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, mcountinhibit_tmp);

  return cnt;
}


/**********************************************************************//**
 * Hardware performance monitors (HPM): Get total counter width
 *
 * @warning This function overrides the mhpmcounter3[h] CSRs.
 *
 * @return Size of HPM counters (1-64, 0 if not implemented at all).
 **************************************************************************/
uint32_t cellrv32_cpu_hpm_get_size(void) {

  uint32_t tmp, cnt;

  // HPMs implemented at all?
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZIHPM)) == 0) {
    return 0;
  }

  // inhibit auto-update of HPM counter3
  tmp = cellrv32_cpu_csr_read(CSR_MCOUNTINHIBIT);
  tmp |= 1 << CSR_MCOUNTINHIBIT_HPM3;
  cellrv32_cpu_csr_write(CSR_MCOUNTINHIBIT, tmp);

  // try to set all 64 counter bits
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER3, -1);
  cellrv32_cpu_csr_write(CSR_MHPMCOUNTER3H, -1);

  // count actually set bits
  cnt = 0;

  tmp = cellrv32_cpu_csr_read(CSR_MHPMCOUNTER3);
  while (tmp) {
    cnt++;
    tmp >>= 1;
  }

  tmp = cellrv32_cpu_csr_read(CSR_MHPMCOUNTER3H);
  while (tmp) {
    cnt++;
    tmp >>= 1;
  }

  return cnt;
}


/**********************************************************************//**
 * Switch from privilege mode MACHINE to privilege mode USER.
 *
 * @note This function will **return** with the CPU being in user mode.
 **************************************************************************/
void __attribute__((naked,noinline)) cellrv32_cpu_goto_user_mode(void) {

  // make sure to use NO registers in here! -> naked

  asm volatile ("csrw  mepc, ra          \n" // move return address to mepc so we can return using "mret". also, we can now use ra as temp register
                "li    ra, %[input_imm]  \n" // bit mask to clear the two MPP bits
                "csrrc zero, mstatus, ra \n" // clear MPP bits -> MPP=u-mode
                "mret                    \n" // return and switch to user mode
                :  : [input_imm] "i" ((1 << CSR_MSTATUS_MPP_H) | (1 << CSR_MSTATUS_MPP_L)));
}
