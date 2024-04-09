// #################################################################################################
// # << CELLRV32: cellrv32_cfu.h - CPU Core - CFU Co-Processor Hardware Driver >>                  #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/DatNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file cellrv32_cpu_cfu.h
 * @brief CPU Core custom functions unit HW driver header file.
 **************************************************************************/

#ifndef cellrv32_cpu_cfu_h
#define cellrv32_cpu_cfu_h

// prototypes
int cellrv32_cpu_cfu_available(void);


/**********************************************************************//**
 * @name Low-level CFU custom instructions ("intrinsics")
 **************************************************************************/
/**@{*/
/** R3-type CFU custom instruction prototype */
#define cellrv32_cfu_r3_instr(funct7, funct3, rs1, rs2) CUSTOM_INSTR_R3_TYPE(funct7, rs2, rs1, funct3, RISCV_OPCODE_CUSTOM0)
/** R4-type CFU custom instruction prototype */
#define cellrv32_cfu_r4_instr(funct3, rs1, rs2, rs3) CUSTOM_INSTR_R4_TYPE(rs3, rs2, rs1, funct3, RISCV_OPCODE_CUSTOM1)
/** R5-type CFU custom instruction A prototype  */
#define cellrv32_cfu_r5_instr_a(rs1, rs2, rs3, rs4) CUSTOM_INSTR_R5_TYPE(rs4, rs3, rs2, rs1, RISCV_OPCODE_CUSTOM2)
/** R5-type CFU custom instruction B prototype */
#define cellrv32_cfu_r5_instr_b(rs1, rs2, rs3, rs4) CUSTOM_INSTR_R5_TYPE(rs4, rs3, rs2, rs1, RISCV_OPCODE_CUSTOM3)
/**@}*/

#endif // cellrv32_cpu_cfu_h
