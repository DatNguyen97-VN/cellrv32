// #################################################################################################
// # << CELLRV32 - Intrinsics + Emulation Functions for the RISC-V "Vector" CPU extension >>       #
// # ********************************************************************************************* #
// # The intrinsics provided by this library allow to use the hardware vector unit of the          #
// # RISC-V Vector CPU extension without the need for Vector support by the compiler / toolchain.  #
// # ********************************************************************************************* #
// # The NEORV32 Processor - https://github.com/DatNguyen97-VN/cellrv32             (c) Dat Nguyen #
// #################################################################################################


/**********************************************************************//**
 * @file vector_test/cellrv32_v_extension_intrinsics.h
 * @author Dat Nguyen
 *
 * @brief "Intrinsic" library for the CELLRV32 vector (V) extension
 * @brief Also provides emulation functions for all intrinsics (functionality re-built in pure software). The functionality of the emulation
 * @brief functions is based on the RISC-V vector spec.
 *
 * @note All operations from this library use the default GCC "round to nearest, ties to even" rounding mode.
 *
 * @warning This library is just a temporary fall-back until the Vector extensions are supported by the upstream RISC-V GCC port.
 **************************************************************************/
 
#ifndef cellrv32_v_extension_intrinsics_h
#define cellrv32_v_extension_intrinsics_h
#define __USE_GNU

#include <fenv.h>
//#pragma STDC FENV_ACCESS ON

#define _GNU_SOURCE

#include <float.h>
#include <math.h>


/**********************************************************************//**
 * Sanity check
 **************************************************************************/
#if defined __riscv_f || (__riscv_flen == 32) || __riscv_v
  #error Application programs using the Zfinx intrinsic library have to be compiled WITHOUT the <F> MARCH ISA attribute!
#endif


/**********************************************************************//**
 * Custom data type to access floating-point values as native floats and in binary representation
 **************************************************************************/
typedef union
{
  uint32_t binary_value; /**< Access as native float */
  float    float_value;  /**< Access in binary representation */
} float_conv_t;


// ################################################################################################
// Helper functions
// ################################################################################################

/**********************************************************************//**
 * Flush to zero if de-normal number.
 *
 * @warning Subnormal numbers are not supported yet! Flush them to zero.
 *
 * @param[in] tmp Source operand.
 * @return Result.
 **************************************************************************/
float subnormal_flush(float tmp) {

  float res = tmp;

  // flush to zero if subnormal
  if (fpclassify(tmp) == FP_SUBNORMAL) {
    if (signbit(tmp) != 0) {
      res = -0.0f;
    }
    else {
      res = +0.0f;
    }
  }

  return res;
}


// ################################################################################################
// "Vector Intrinsics"
// ################################################################################################


/**********************************************************************//**
 * Conguration-Setting Instructions: the values in vl and vtype
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsetvl(int32_t rs1, int32_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b1000000, rs2, rs1, 0b111, 0b1010111);
}


/**********************************************************************//**
 * Conguration-Setting Instructions: the values in vl and vtype
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] zimm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsetvli(int32_t rs1, uint32_t zimm) {
  
  
}


/**********************************************************************//**
 * Conguration-Setting Instructions: the values in vl and vtype
 *
 * @param[in] uimm Source operand 1.
 * @param[in] zimm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsetivli(int32_t uimm, int32_t zimm) {
  
 
}


/**********************************************************************//**
 * Vector Unit-Stride Load 32-bit elements
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vle32v(int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, 0b00000, rs1, 0b010, 0b0000111);
}


/**********************************************************************//**
 * Vector Unit-Stride Store 32-bit elements
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline void __attribute__ ((always_inline)) riscv_intrinsic_vse32v(int32_t rs1, int32_t vs3) {

  CUSTOM_VECTOR_INSTR_R2_TYPE(0b000000000000, vs3, rs1, 0b010, 0b0100111);
}


/**********************************************************************//**
 * Vector single-width Integer Addition: Vector-Vector
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vaddvv(int32_t vs1, int32_t vs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Addition: Vector-Scalar
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vaddvx(int32_t rs1, int32_t vs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Addition: Vector-Immediate
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vaddvi(uint16_t imm, int32_t vs2) {

  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0000000, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Subtract: Vector-Vector
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsubvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000100, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Subtract: Vector-Scalar
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsubvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000100, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Reverse Subtract: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vrsubvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000110, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Reverse Subtract: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vrsubvi(int32_t vs2, int16_t imm) {

  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0000110, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector And Bitwise Logical: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vandvv(int32_t vs2, int32_t vs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010010, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector And Bitwise Logical: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vandvx(int32_t vs2, int32_t rs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010010, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector And Bitwise Logical: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vandvi(int32_t vs2, int16_t imm) {
  
  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010010, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector Or Bitwise Logical: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vorvv(int32_t vs2, int32_t vs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010100, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector Or Bitwise Logical: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vorvx(int32_t vs2, int32_t rs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010100, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector Or Bitwise Logical: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vorvi(int32_t vs2, int16_t imm) {
  
  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010100, vs2, imm, 0b011, 0b1010111);
}



/**********************************************************************//**
 * Vector Xor Bitwise Logical: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vxorvv(int32_t vs2, int32_t vs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010110, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector Xor Bitwise Logical: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vxorvx(int32_t vs2, int32_t rs1) {
  
  return CUSTOM_INSTR_R3_TYPE(0b0010110, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector Xor Bitwise Logical: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vxorvi(int32_t vs2, int16_t imm) {
  
  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010110, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Left: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsllvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001010, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Left: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsllvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001010, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Left: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsllvi(int32_t vs2, uint16_t imm) {

  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b1001010, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Right: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsrlvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1010000, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Right: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsrlvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1010000, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Logical Shift Right: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsrlvi(int32_t vs2, uint16_t imm) {

  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b1010000, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Arithmetic Shift Right: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsravv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1010010, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Arithmetic Shift Right: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsravx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1010010, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Arithmetic Shift Right: Vector-Immediate
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] imm Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vsravi(int32_t vs2, uint16_t imm) {

  return CUSTOM_VECTOR_INSTR_IMM_TYPE(0b1010010, vs2, imm, 0b011, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Minimum Unsigned: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vminuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001000, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Minimum Unsigned: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vminuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001000, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Minimum Signed: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vminvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001010, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Minimum Signed: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vminvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001010, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Maximum Unsigned: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmaxuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001100, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Maximum Unsigned: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmaxuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001100, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Maximum Signed: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmaxvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001110, vs2, vs1, 0b000, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Maximum Signed: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmaxvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001110, vs2, rs1, 0b100, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Multiply: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001010, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Multiply: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001010, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer High Multiply: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001110, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer High Multiply: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001110, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer High Multiply: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001000, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer High Multiply: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001000, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed/Unsigned Integer High Multiply: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhsuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001100, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed/Unsigned Integer High Multiply: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmulhsuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001100, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer Divide: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vdivuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000000, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer Divide: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vdivuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000000, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Divide: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vdivvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000010, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Divide: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vdivvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000010, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer Remainder: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vremuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000100, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Unsigned Integer Remainder: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vremuvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000100, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Remainder: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vremvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000110, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Remainder: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vremvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1000110, vs2, rs1, 0b110, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Move: Vector-Vector
 *
 * @param[in] vs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmvvv(int32_t vs1) {

  return ({                                      \
            uint32_t __return;                   \
            asm volatile (                       \
              ""                                 \
              : [output] "=r" (__return)         \
              : [input_i] "r" (vs1)              \
            );                                   \
            asm volatile (                       \
              ".word (                           \
                ((( 0x2f ) & 0x7f) << 25) |      \
                ((( 0x00 ) & 0x1f) << 20) |      \
                ((( regnum_%1 ) & 0x1f) << 15) | \
                ((( 0x00) & 0x07) << 12) |       \
                ((( regnum_%0 ) & 0x1f) <<  7) | \
                ((( 0x57) & 0x7f) <<  0)         \
              );"                                \
              : [rd] "=r" (__return)             \
              : "r" (vs1)                        \
            );                                   \
            __return;                            \
        });
}


/**********************************************************************//**
 * Vector single-width Integer Move: Vector-Scalar
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmvvx(int32_t rs1) {

  return ({                                      \
            uint32_t __return;                   \
            asm volatile (                       \
              ""                                 \
              : [output] "=r" (__return)         \
              : [input_i] "r" (rs1)              \
            );                                   \
            asm volatile (                       \
              ".word (                           \
                ((( 0x2f ) & 0x7f) << 25) |      \
                ((( 0x00 ) & 0x1f) << 20) |      \
                ((( regnum_%1 ) & 0x1f) << 15) | \
                ((( 0x04) & 0x07) << 12) |       \
                ((( regnum_%0 ) & 0x1f) <<  7) | \
                ((( 0x57) & 0x7f) <<  0)         \
              );"                                \
              : [rd] "=r" (__return)             \
              : "r" (rs1)                        \
            );                                   \
            __return;                            \
        });
}


/**********************************************************************//**
 * Vector single-width Integer Move: Vector-Immediate
 *
 * @param[in] imm Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vmvvi(int16_t imm) {

  return ({                                       \
            uint32_t __return;                    \
            asm volatile (                        \
              ""                                  \
              : [output] "=r" (__return)          \
              : [input_i] "i" (imm)               \
            );                                    \
            asm volatile (                        \
              ".word (                            \
                ((( 0x2f ) & 0x7f) << 25)      |  \
                ((( 0x00 ) & 0x1f) << 20)      |  \
                ((( %1   ) & 0x1f) << 15)      |  \
                ((( 0x03 ) & 0x07) << 12)      |  \
                ((( regnum_%0 ) & 0x1f) <<  7) |  \
                ((( 0x57 ) & 0x7f) <<  0)         \
              );"                                 \
              : [rd] "=r" (__return)              \
              : "i" (imm)                         \
            );                                    \
            __return;                             \
        });
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Sum: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredsumvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction And: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredandvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000010, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Or: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredorvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000100, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Xor: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredxorvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000110, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Minu: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredminuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001000, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Min: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredminvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001010, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Maxu: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredmaxuvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001100, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Signed Integer Reduction Max: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vredmaxvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0001110, vs2, vs1, 0b010, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Addition: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vfaddvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, vs2, vs1, 0b001, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Addition: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vfaddvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000000, vs2, rs1, 0b101, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Subtraction: Vector-Vector
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] vs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vfsubvv(int32_t vs2, int32_t vs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000100, vs2, vs1, 0b001, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Subtraction: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vfsubvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b0000100, vs2, rs1, 0b101, 0b1010111);
}


/**********************************************************************//**
 * Vector single-width Integer Reverse Reversal Subtraction: Vector-Scalar
 *
 * @param[in] vs2 Source operand 1.
 * @param[in] rs1 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_vfrsubvx(int32_t vs2, int32_t rs1) {

  return CUSTOM_INSTR_R3_TYPE(0b1001110, vs2, rs1, 0b101, 0b1010111);
}
// ################################################################################################
// !!! UNSUPPORTED instructions !!!
// ################################################################################################


// ################################################################################################
// "Single Floating-Point Intrinsics"
// ################################################################################################

/**********************************************************************//**
 * Single-precision floating-point addition
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fadds(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0000000, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point subtraction
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fsubs(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0000100, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point multiplication
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fmuls(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0001000, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point division
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fdivs(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0001100, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point square root
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fsqrts(float rs1) {

  float_conv_t opa, res;
  opa.float_value = rs1;

  res.binary_value = CUSTOM_INSTR_R2_TYPE(0b0101100, 0b00000, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point minimum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fmins(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0010100, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point maximum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fmaxs(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0010100, opb.binary_value, opa.binary_value, 0b001, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point convert float to unsigned integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_wus(float rs1) {

  float_conv_t opa;
  opa.float_value = rs1;

  return CUSTOM_INSTR_R2_TYPE(0b1100000, 0b00001, opa.binary_value, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point convert float to signed integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_ws(float rs1) {

  float_conv_t opa;
  opa.float_value = rs1;

  return (int32_t)CUSTOM_INSTR_R2_TYPE(0b1100000, 0b00000, opa.binary_value, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point convert unsigned integer to float
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fcvt_swu(uint32_t rs1) {

  float_conv_t res;

  res.binary_value = CUSTOM_INSTR_R2_TYPE(0b1101000, 0b00001, rs1, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point convert signed integer to float
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fcvt_sw(int32_t rs1) {

  float_conv_t res;

  res.binary_value = CUSTOM_INSTR_R2_TYPE(0b1101000, 0b00000, rs1, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_feqs(float rs1, float rs2) {

  float_conv_t opa, opb;
  opa.float_value = rs1;
  opb.float_value = rs2;

  return CUSTOM_INSTR_R3_TYPE(0b1010000, opb.binary_value, opa.binary_value, 0b010, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point less-than comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_flts(float rs1, float rs2) {

  float_conv_t opa, opb;
  opa.float_value = rs1;
  opb.float_value = rs2;

  return CUSTOM_INSTR_R3_TYPE(0b1010000, opb.binary_value, opa.binary_value, 0b001, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point less-than-or-equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fles(float rs1, float rs2) {

  float_conv_t opa, opb;
  opa.float_value = rs1;
  opb.float_value = rs2;

  return CUSTOM_INSTR_R3_TYPE(0b1010000, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fsgnjs(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0010000, opb.binary_value, opa.binary_value, 0b000, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection NOT
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fsgnjns(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0010000, opb.binary_value, opa.binary_value, 0b001, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection XOR
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline float __attribute__ ((always_inline)) riscv_intrinsic_fsgnjxs(float rs1, float rs2) {

  float_conv_t opa, opb, res;
  opa.float_value = rs1;
  opb.float_value = rs2;

  res.binary_value = CUSTOM_INSTR_R3_TYPE(0b0010000, opb.binary_value, opa.binary_value, 0b010, 0b1010011);
  return res.float_value;
}


/**********************************************************************//**
 * Single-precision floating-point number classification
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fclasss(float rs1) {

  float_conv_t opa;
  opa.float_value = rs1;

  return CUSTOM_INSTR_R2_TYPE(0b1110000, 0b00000, opa.binary_value, 0b001, 0b1010011);
}


// ################################################################################################
// Emulation functions
// ################################################################################################

/**********************************************************************//**
 * Single-precision floating-point addition
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fadds(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  float res = opa + opb;

  // make NAN canonical
  if (fpclassify(res) == FP_NAN) {
    res = NAN;
  }

  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point subtraction
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fsubs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  float res = opa - opb;

  // make NAN canonical
  if (fpclassify(res) == FP_NAN) {
    res = NAN;
  }

  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point multiplication
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fmuls(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  float res = opa * opb;
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point minimum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fmins(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  union {
  uint32_t binary_value; /**< Access as native float */
  float    float_value;  /**< Access in binary representation */
  } tmp_a, tmp_b;

  if ((fpclassify(opa) == FP_NAN) && (fpclassify(opb) == FP_NAN)) {
    return nanf("");
  }

  if (fpclassify(opa) == FP_NAN) {
    return opb;
  }

  if (fpclassify(opb) == FP_NAN) {
    return opa;
  }

  // RISC-V spec: -0 < +0
  tmp_a.float_value = opa;
  tmp_b.float_value = opb;
  if (((tmp_a.binary_value == 0x80000000) && (tmp_b.binary_value == 0x00000000)) ||
      ((tmp_a.binary_value == 0x00000000) && (tmp_b.binary_value == 0x80000000))) {
    return -0.0f;
  }

  return fmin(opa, opb);
}


/**********************************************************************//**
 * Single-precision floating-point maximum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fmaxs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  union {
  uint32_t binary_value; /**< Access as native float */
  float    float_value;  /**< Access in binary representation */
  } tmp_a, tmp_b;


  if ((fpclassify(opa) == FP_NAN) && (fpclassify(opb) == FP_NAN)) {
    return nanf("");
  }

  if (fpclassify(opa) == FP_NAN) {
    return opb;
  }

  if (fpclassify(opb) == FP_NAN) {
    return opa;
  }

  // RISC-V spec: -0 < +0
  tmp_a.float_value = opa;
  tmp_b.float_value = opb;
  if (((tmp_a.binary_value == 0x80000000) && (tmp_b.binary_value == 0x00000000)) ||
      ((tmp_a.binary_value == 0x00000000) && (tmp_b.binary_value == 0x80000000))) {
    return +0.0f;
  }

  return fmax(opa, opb);
}


/**********************************************************************//**
 * Single-precision floating-point float to unsigned integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
uint32_t __attribute__ ((noinline)) riscv_emulate_fcvt_wus(float rs1) {

  float opa = subnormal_flush(rs1);

  return (uint32_t)roundf(opa);
}


/**********************************************************************//**
 * Single-precision floating-point float to signed integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
int32_t __attribute__ ((noinline)) riscv_emulate_fcvt_ws(float rs1) {

  float opa = subnormal_flush(rs1);

  return (int32_t)roundf(opa);
}


/**********************************************************************//**
 * Single-precision floating-point unsigned integer to float
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fcvt_swu(uint32_t rs1) {

  return (float)rs1;
}


/**********************************************************************//**
 * Single-precision floating-point signed integer to float
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fcvt_sw(int32_t rs1) {

  return (float)rs1;
}


/**********************************************************************//**
 * Single-precision floating-point equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
uint32_t __attribute__ ((noinline)) riscv_emulate_feqs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  if ((fpclassify(opa) == FP_NAN) || (fpclassify(opb) == FP_NAN)) {
    return 0;
  }

  if isless(opa, opb) {
    return 0;
  }
  else if isgreater(opa, opb) {
    return 0;
  }
  else {
    return 1;
  }
}


/**********************************************************************//**
 * Single-precision floating-point less-than comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
uint32_t __attribute__ ((noinline)) riscv_emulate_flts(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  if ((fpclassify(opa) == FP_NAN) || (fpclassify(opb) == FP_NAN)) {
    return 0;
  }

  if isless(opa, opb) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Single-precision floating-point less-than-or-equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
uint32_t __attribute__ ((noinline)) riscv_emulate_fles(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  if ((fpclassify(opa) == FP_NAN) || (fpclassify(opb) == FP_NAN)) {
    return 0;
  }

  if islessequal(opa, opb) {
    return 1;
  }
  else {
    return 0;
  }
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fsgnjs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  int sign_1 = (int)signbit(opa);
  int sign_2 = (int)signbit(opb);
  float res = 0;

  if (sign_2 != 0) { // opb is negative
    if (sign_1 == 0) {
      res = -opa;
    }
    else {
      res = opa;
    }
  }
  else { // opb is positive
    if (sign_1 == 0) {
      res = opa;
    }
    else {
      res = -opa;
    }
  }

  return res;
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection NOT
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fsgnjns(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  int sign_1 = (int)signbit(opa);
  int sign_2 = (int)signbit(opb);
  float res = 0;

  if (sign_2 != 0) { // opb is negative
    if (sign_1 == 0) {
      res = opa;
    }
    else {
      res = -opa;
    }
  }
  else { // opb is positive
    if (sign_1 == 0) {
      res = -opa;
    }
    else {
      res = opa;
    }
  }

  return res;
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection XOR
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fsgnjxs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  int sign_1 = (int)signbit(opa);
  int sign_2 = (int)signbit(opb);
  float res = 0;

  if (((sign_1 == 0) && (sign_2 != 0)) || ((sign_1 != 0) && (sign_2 == 0))) {
    if (sign_1 == 0) {
      res = -opa;
    }
    else {
      res = opa;
    }
  }
  else {
    if (sign_1 == 0) {
      res = opa;
    }
    else {
      res = -opa;
    }
  }

  return res;
}


/**********************************************************************//**
 * Single-precision floating-point number classification
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
uint32_t __attribute__ ((noinline)) riscv_emulate_fclasss(float rs1) {

  float opa = subnormal_flush(rs1);

  union {
    uint32_t binary_value; /**< Access as native float */
    float    float_value;  /**< Access in binary representation */
  } aux;

  // RISC-V classify result layout
  const uint32_t CLASS_NEG_INF    = 1 << 0; // negative infinity
  const uint32_t CLASS_NEG_NORM   = 1 << 1; // negative normal number
  const uint32_t CLASS_NEG_DENORM = 1 << 2; // negative subnormal number
  const uint32_t CLASS_NEG_ZERO   = 1 << 3; // negative zero
  const uint32_t CLASS_POS_ZERO   = 1 << 4; // positive zero
  const uint32_t CLASS_POS_DENORM = 1 << 5; // positive subnormal number
  const uint32_t CLASS_POS_NORM   = 1 << 6; // positive normal number
  const uint32_t CLASS_POS_INF    = 1 << 7; // positive infinity
  const uint32_t CLASS_SNAN       = 1 << 8; // signaling NaN (sNaN)
  const uint32_t CLASS_QNAN       = 1 << 9; // quiet NaN (qNaN)

  int tmp = fpclassify(opa);
  int sgn = (int)signbit(opa);

  uint32_t res = 0;

  // infinity
  if (tmp == FP_INFINITE) {
    if (sgn) { res |= CLASS_NEG_INF; }
    else     { res |= CLASS_POS_INF; }
  }

  // zero
  if (tmp == FP_ZERO) {
    if (sgn) { res |= CLASS_NEG_ZERO; }
    else     { res |= CLASS_POS_ZERO; }
  }

  // normal
  if (tmp == FP_NORMAL) {
    if (sgn) { res |= CLASS_NEG_NORM; }
    else     { res |= CLASS_POS_NORM; }
  }

  // subnormal
  if (tmp == FP_SUBNORMAL) {
    if (sgn) { res |= CLASS_NEG_DENORM; }
    else     { res |= CLASS_POS_DENORM; }
  }

  // NaN
  if (tmp == FP_NAN) {
    aux.float_value = opa;
    if ((aux.binary_value >> 22) & 0b1) { // bit 22 (mantissa's MSB) is set -> canonical (quiet) NAN
      res |= CLASS_QNAN;
    }
    else {
      res |= CLASS_SNAN;
    }
  }

  return res;
}


/**********************************************************************//**
 * Single-precision floating-point division
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fdivs(float rs1, float rs2) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);

  float res = opa / opb;
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point square root
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fsqrts(float rs1) {

  float opa = subnormal_flush(rs1);

  float res = sqrtf(opa);
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point fused multiply-add
 *
 * @warning This instruction is not supported!
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fmadds(float rs1, float rs2, float rs3) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);
  float opc = subnormal_flush(rs3);

  float res = (opa * opb) + opc;
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point fused multiply-sub
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fmsubs(float rs1, float rs2, float rs3) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);
  float opc = subnormal_flush(rs3);

  float res = (opa * opb) - opc;
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point fused negated multiply-sub
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fnmsubs(float rs1, float rs2, float rs3) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);
  float opc = subnormal_flush(rs3);

  float res = -(opa * opb) + opc;
  return subnormal_flush(res);
}


/**********************************************************************//**
 * Single-precision floating-point fused negated multiply-add
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
float __attribute__ ((noinline)) riscv_emulate_fnmadds(float rs1, float rs2, float rs3) {

  float opa = subnormal_flush(rs1);
  float opb = subnormal_flush(rs2);
  float opc = subnormal_flush(rs3);

  float res = -(opa * opb) - opc;
  return subnormal_flush(res);
}


#endif // cellrv32_zfinx_extension_intrinsics_h
 