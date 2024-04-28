// #################################################################################################
// # << CELLRV32: cellrv32_rte.h - CELLRV32 Runtime Environment >>                                 #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_rte.h
 * @brief CELLRV32 Runtime Environment.
 **************************************************************************/

#ifndef cellrv32_rte_h
#define cellrv32_rte_h


/**********************************************************************//**
 * CELLRV32 runtime environment: Number of available traps.
 **************************************************************************/
#define CELLRV32_RTE_NUM_TRAPS 29


/**********************************************************************//**
 * CELLRV32 runtime environment trap IDs.
 **************************************************************************/
enum CELLRV32_RTE_TRAP_enum {
  RTE_TRAP_I_MISALIGNED =  0, /**< Instruction address misaligned */
  RTE_TRAP_I_ACCESS     =  1, /**< Instruction (bus) access fault */
  RTE_TRAP_I_ILLEGAL    =  2, /**< Illegal instruction */
  RTE_TRAP_BREAKPOINT   =  3, /**< Breakpoint (EBREAK instruction) */
  RTE_TRAP_L_MISALIGNED =  4, /**< Load address misaligned */
  RTE_TRAP_L_ACCESS     =  5, /**< Load (bus) access fault */
  RTE_TRAP_S_MISALIGNED =  6, /**< Store address misaligned */
  RTE_TRAP_S_ACCESS     =  7, /**< Store (bus) access fault */
  RTE_TRAP_UENV_CALL    =  8, /**< Environment call from user mode (ECALL instruction) */
  RTE_TRAP_MENV_CALL    =  9, /**< Environment call from machine mode (ECALL instruction) */
  RTE_TRAP_MSI          = 10, /**< Machine software interrupt */
  RTE_TRAP_MTI          = 11, /**< Machine timer interrupt */
  RTE_TRAP_MEI          = 12, /**< Machine external interrupt */
  RTE_TRAP_FIRQ_0       = 13, /**< Fast interrupt channel 0 */
  RTE_TRAP_FIRQ_1       = 14, /**< Fast interrupt channel 1 */
  RTE_TRAP_FIRQ_2       = 15, /**< Fast interrupt channel 2 */
  RTE_TRAP_FIRQ_3       = 16, /**< Fast interrupt channel 3 */
  RTE_TRAP_FIRQ_4       = 17, /**< Fast interrupt channel 4 */
  RTE_TRAP_FIRQ_5       = 18, /**< Fast interrupt channel 5 */
  RTE_TRAP_FIRQ_6       = 19, /**< Fast interrupt channel 6 */
  RTE_TRAP_FIRQ_7       = 20, /**< Fast interrupt channel 7 */
  RTE_TRAP_FIRQ_8       = 21, /**< Fast interrupt channel 8 */
  RTE_TRAP_FIRQ_9       = 22, /**< Fast interrupt channel 9 */
  RTE_TRAP_FIRQ_10      = 23, /**< Fast interrupt channel 10 */
  RTE_TRAP_FIRQ_11      = 24, /**< Fast interrupt channel 11 */
  RTE_TRAP_FIRQ_12      = 25, /**< Fast interrupt channel 12 */
  RTE_TRAP_FIRQ_13      = 26, /**< Fast interrupt channel 13 */
  RTE_TRAP_FIRQ_14      = 27, /**< Fast interrupt channel 14 */
  RTE_TRAP_FIRQ_15      = 28  /**< Fast interrupt channel 15 */
};


/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
void cellrv32_rte_setup(void);
int  cellrv32_rte_handler_install(uint8_t id, void (*handler)(void));
int  cellrv32_rte_handler_uninstall(uint8_t id);

void cellrv32_rte_print_hw_config(void);
void cellrv32_rte_print_hw_version(void);
void cellrv32_rte_print_credits(void);
void cellrv32_rte_print_icon(void);
void cellrv32_rte_print_logo(void);
void cellrv32_rte_print_license(void);

uint32_t cellrv32_rte_get_compiler_isa(void);
int      cellrv32_rte_check_isa(int silent);
/**@}*/


#endif // cellrv32_rte_h
