// ########################################################################################################
// # << CELLRV32 - Intrinsics + Emulation Functions for the RISC-V "Zhinx" CPU extension >>               #
// # **************************************************************************************************** #
// # The intrinsics provided by this library allow to use the hardware half-precision floating-point unit #
// # of the RISC-V Zhinx CPU extension without the need for Zhinx support by the compiler / toolchain.    #
// # **************************************************************************************************** #
// # The NEORV32 Processor - https://github.com/DatNguyen97-VN/cellrv32                    (c) Dat Nguyen #
// ########################################################################################################


/**********************************************************************//**
 * @file zfhinx_test/cellrv32_zhinx_extension_intrinsics.h
 * @author Dat Nguyen
 *
 * @brief "Intrinsic" library for the CELLRV32 half-precision floating-point in x registers (Zhinx) extension
 * @brief Also provides emulation functions for all intrinsics (functionality re-built in pure software). The functionality of the emulation
 * @brief functions is based on the RISC-V floating-point spec.
 *
 * @note All operations from this library use the default GCC "round to nearest, ties to even" rounding mode.
 *
 * @warning This library is just a temporary fall-back until the Zfhinx extensions are supported by the upstream RISC-V GCC port.
 **************************************************************************/

#ifndef cellrv32_zhinx_extension_intrinsics_h
#define cellrv32_zhinx_extension_intrinsics_h

#define __USE_GNU

#include <fenv.h>
//#pragma STDC FENV_ACCESS ON

#define _GNU_SOURCE

#include <float.h>
#include <math.h>


/**********************************************************************//**
 * Sanity check
 **************************************************************************/
#if defined __riscv_f  || __riscv_zfh || (__riscv_flen == 32)
  #error Application programs using the Zfhinx intrinsic library have to be compiled WITHOUT the <Zfh> MARCH ISA attribute!
#endif


/**********************************************************************//**
 * Custom data type to access floating-point values as native floats and in binary representation
 **************************************************************************/
typedef union
{
  uint32_t binary_value; /**< Access as native float */
  float float_value;     /**< Access in binary representation */
} float_conv_t;


/**********************************************************************//**
 * Custom data type to access half-precision floating-point values
 **************************************************************************/
typedef union {
    uint16_t binary_value;  /**< Access as native float */
    struct {
        uint16_t frac : 10; /**< fraction */
        uint16_t exp  : 5;  /**< exponent */
        uint16_t sign : 1;  /**< signed */
    };
} float16_conv_t;


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

  float res = (float)tmp;

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


/**********************************************************************//**
 * Flush to zero if de-normal number.
 *
 * @warning Subnormal numbers are not supported yet! Flush them to zero.
 *
 * @param[in] h 16-bit half-precision floating-point
 * @return Flushed 16-bit result
 **************************************************************************/
int16_t subnormal_flush16(int16_t h) {
  int16_t sign = h & 0x8000;
  int16_t exp  = (h >> 10) & 0x1F;
  int16_t frac = h & 0x03FF;

  // Subnormal if exponent == 0 and fraction != 0
  if (exp == 0 && frac != 0) {
    // Flush to signed zero
    return sign; // 0x8000 if negative, 0x0000 if positive
  }

  // Otherwise, return unchanged
  return h;
}


/**********************************************************************//**
 * Convert the half-precision floating-point to the single-precision floating-point.
 *
 * @param[in] h Source operand.
 * @return Result.
 **************************************************************************/
float half2float(uint16_t h) {
    float16_conv_t f16 = { .binary_value = h };
    union { uint32_t u; float f; } v;

    uint32_t sign = f16.sign << 31;
    uint32_t exp, frac;

    if (f16.exp == 0x1F) { // NaN or Inf
        exp = 0xFF << 23;

        // infinity
        if (!f16.frac) {
          frac = 0;
        } else if (f16.frac & 0x200) { // qNAN
          frac = 0x400000;
        } else { //sNAN
          frac = 0x200000;
        }
    } else if (f16.exp == 0) { // subnormal or zero
        exp = 0;
        frac = 0;
    } else {
        exp = (f16.exp - 15 + 127) << 23;
        frac = f16.frac << 13;
    }

    v.u = sign | exp | frac;
    return v.f;
}


/**********************************************************************//**
 * Convert the single-precision floating-point to the half-precision floating-point.
 *
 * @param[in] f Source operand.
 * @return Result.
 **************************************************************************/
uint16_t float2half(float f) {
    union { float f; uint32_t u; } v = { f };
    uint32_t sign = (v.u >> 31) & 0x1;
    uint32_t exp  = (v.u >> 23) & 0xFF;
    uint32_t frac = v.u & 0x7FFFFF;

    uint32_t h_exp, h_frac;

    if (exp == 0xFF) { // NaN or Inf
        h_exp = 0x1F;
        h_frac = (frac != 0) ? 0x200 : 0;
    } else if (exp > 0x70 + 0x1E) { // overflow
        h_exp = 0x1F;
        h_frac = 0;
    } else if (exp <= 0x70) { // underflow -> subnormal flush them to zero or zero
        h_exp = 0;
        h_frac = 0;
    } else {
        h_exp = exp - 112;

        uint32_t mant = frac;
        uint32_t round_mask = 0x1FFF; // 13-bits are truncated
    
        uint32_t lsb = (mant >> 13) & 1;
        uint32_t round_bits = mant & round_mask;

    
        // Round to nearest even
        if (round_bits > 0x1000 || (round_bits == 0x1000 && lsb)) {
            mant += 0x2000;
        }

        h_frac = mant >> 13;
    
        // handle mant overflow (1.111... → 10.000)
        if (h_frac & 0x400) {
            h_frac = 0;
            h_exp++;
            if (h_exp >= 0x1F) { // overflow
                h_exp = 0x1F;
            }
        }
    }

    uint16_t result = (sign << 15) | (h_exp << 10) | h_frac;
    return result;
}


// ################################################################################################
// "Intrinsics"
// ################################################################################################


/**********************************************************************//**
 * Single-precision floating-point addition
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fadds(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0000010, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point subtraction
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fsubs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0000110, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point multiplication
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fmuls(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0001010, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point fused multiply-add
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fmadds(int16_t rs1, int16_t rs2, int16_t rs3) {

  return CUSTOM_INSTR_R4_TYPE(rs3, rs2, rs1, 0b000, 0b10, 0b1000011);
}


/**********************************************************************//**
 * Single-precision floating-point fused multiply-sub
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fmsubs(int16_t rs1, int16_t rs2, int16_t rs3) {

  return CUSTOM_INSTR_R4_TYPE(rs3, rs2, rs1, 0b000, 0b10, 0b1000111);
}


/**********************************************************************//**
 * Single-precision floating-point fused negated multiply-sub
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fnmsubs(int16_t rs1, int16_t rs2, int16_t rs3) {
 
  return CUSTOM_INSTR_R4_TYPE(rs3, rs2, rs1, 0b000, 0b10, 0b1001011);
}


/**********************************************************************//**
 * Single-precision floating-point fused negated multiply-add
 *
 * @param[in] rs1 Source operand 1
 * @param[in] rs2 Source operand 2
 * @param[in] rs3 Source operand 3
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fnmadds(int16_t rs1, int16_t rs2, int16_t rs3) {

  return CUSTOM_INSTR_R4_TYPE(rs3, rs2, rs1, 0b000, 0b10, 0b1001111);;
}


/**********************************************************************//**
 * Single-precision floating-point division
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fdivs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0001110, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point square root
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fsqrts(int16_t rs1) {
 
  return CUSTOM_INSTR_R2_TYPE(0b0101110, 0b00000, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point minimum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fmins(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0010110, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point maximum
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fmaxs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0010110, rs2, rs1, 0b001, 0b1010011);
}


/**********************************************************************//**
 * Half-precision floating-point convert half to unsigned integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_wuh(int16_t rs1) {

  return CUSTOM_INSTR_R2_TYPE(0b1100010, 0b00001, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Half-precision floating-point convert half to signed integer
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_wh(int32_t rs1) {

  return (int32_t)CUSTOM_INSTR_R2_TYPE(0b1100010, 0b00000, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Half-precision floating-point convert unsigned integer to half
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_hwu(uint32_t rs1) {

  return (int32_t)CUSTOM_INSTR_R2_TYPE(0b1101010, 0b00001, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Half-precision floating-point convert signed integer to half
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fcvt_hw(int32_t rs1) {

  return (int32_t)CUSTOM_INSTR_R2_TYPE(0b1101010, 0b00000, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_feqs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b1010010, rs2, rs1, 0b010, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point less-than comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_flts(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b1010010, rs2, rs1, 0b001, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point less-than-or-equal comparison
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fles(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b1010010, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fsgnjs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0010010, rs2, rs1, 0b000, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection NOT
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fsgnjns(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0010010, rs2, rs1, 0b001, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point sign-injection XOR
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
inline int32_t __attribute__ ((always_inline)) riscv_intrinsic_fsgnjxs(int16_t rs1, int16_t rs2) {

  return CUSTOM_INSTR_R3_TYPE(0b0010010, rs2, rs1, 0b010, 0b1010011);
}


/**********************************************************************//**
 * Single-precision floating-point number classification
 *
 * @param[in] rs1 Source operand 1.
 * @return Result.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) riscv_intrinsic_fclasss(int16_t rs1) {

  return CUSTOM_INSTR_R2_TYPE(0b1110010, 0b00000, rs1, 0b001, 0b1010011);
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
 * Half-precision floating-point sign-injection
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
int32_t __attribute__ ((noinline)) riscv_emulate_fsgnjh(int16_t rs1, int16_t rs2) {

  uint16_t opa = subnormal_flush16(rs1);
  uint16_t opb = subnormal_flush16(rs2);

  uint16_t exp_man_a = opa & 0x7fff;
  uint16_t sign_2 = opb & 0x8000;
  int32_t res = 0;

  res = sign_2 | exp_man_a;

  return res;
}


/**********************************************************************//**
 * Half-precision floating-point sign-injection NOT
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
int32_t __attribute__ ((noinline)) riscv_emulate_fsgnjnh(int16_t rs1, int16_t rs2) {

  uint16_t opa = subnormal_flush16(rs1);
  uint16_t opb = subnormal_flush16(rs2);

  uint16_t exp_man_a = opa & 0x7fff;
  uint16_t sign_2 = opb & 0x8000;
  int32_t res = 0;

  // NOT
  if (sign_2) {
    sign_2 = 0x0000;
  } else {
    sign_2 = 0x8000;
  }

  res = sign_2 | exp_man_a;

  return res;
}


/**********************************************************************//**
 * Half-precision floating-point sign-injection XOR
 *
 * @param[in] rs1 Source operand 1.
 * @param[in] rs2 Source operand 2.
 * @return Result.
 **************************************************************************/
int32_t __attribute__ ((noinline)) riscv_emulate_fsgnjxh(int16_t rs1, int16_t rs2) {

  uint16_t opa = subnormal_flush16(rs1);
  uint16_t opb = subnormal_flush16(rs2);

  uint16_t exp_man_a = opa & 0x7fff;
  uint16_t sign_1 = opa & 0x8000;
  uint16_t sign_2 = opb & 0x8000;
  int32_t res = 0;

  // XOR
  if ((!sign_1 && sign_2) || (sign_1 && !sign_2)) {
    sign_2 = 0x8000;
  } else {
    sign_2 = 0x0000;
  }

  res = sign_2 | exp_man_a;

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

#endif // cellrv32_zhinx_extension_intrinsics_h