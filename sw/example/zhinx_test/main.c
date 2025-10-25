// ################################################################################################
// # << CELLRV32 - RISC-V Half-Precision Floating-Point 'Zhinx' Extension Verification Program >> #
// ################################################################################################


/**********************************************************************//**
 * @file zhin_test/main.c
 * @author Dat Nguyen
 * @brief Verification program for the CELLRV32 'Zhinx' extension (floating-point in x registers) using pseudo-random data as input; compares results from hardware against pure-sw reference functions.
 **************************************************************************/

#include <cellrv32.h>
#include <float.h>
#include <math.h>
#include "cellrv32_zhinx_extension_intrinsics.h"

#ifdef NAN
/* NAN is supported */
#else
#warning NAN macro not supported!
#endif
#ifdef INFINITY
/* INFINITY is supported */
#else
#warning INFINITY macro not supported!
#endif


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE          (19200)
//** Number of test cases for each instruction */
#define NUM_TEST_CASES     (1000000)
//** Silent mode (only show actual errors when != 0) */
#define SILENT_MODE        (1)
//** Run conversion tests when != 0 */
#define RUN_CONV_TESTS     (1)
//** Run add/sub tests when != 0 */
#define RUN_ADDSUB_TESTS   (1)
//** Run multiplication tests when != 0 */
#define RUN_MUL_TESTS      (1)
//** Run division tests when != 0 */
#define RUN_DIV_TESTS      (1)
//** Run square root tests when != 0 */
#define RUN_SQRT_TESTS     (1)
//** Run min/max tests when != 0 */
#define RUN_MINMAX_TESTS   (1)
//** Run comparison tests when != 0 */
#define RUN_COMPARE_TESTS  (1)
//** Run sign-injection tests when != 0 */
#define RUN_SGNINJ_TESTS   (1)
//** Run classify tests when != 0 */
#define RUN_CLASSIFY_TESTS (1)
//** Run unsupported instructions tests when != 0 */
#define RUN_UNAVAIL_TESTS  (0)


// Prototypes
uint16_t get_test_vector16(void);
uint32_t get_test_vector32(void);
uint32_t xorshift32(void);
uint32_t verify_result(uint32_t num, uint32_t opa, uint32_t opb, uint32_t ref, uint32_t res);
uint32_t verify_result3(uint32_t num, uint16_t opa, uint16_t opb, uint16_t opc, uint16_t ref, uint16_t res);
void print_report(uint32_t num_err);


/**********************************************************************//**
 * Main function; test all available operations of the CELLRV32 'Zhinx' extensions using bit floating-point hardware intrinsics and software-only reference functions (emulation).
 *
 * @note This program requires the Zhinx CPU extension.
 *
 * @return 0 if execution was successful
 **************************************************************************/
 int main() {

  uint32_t err_cnt = 0;
  uint32_t err_cnt_total = 0;
  uint32_t test_cnt = 0;
  uint32_t i = 0;
  float16_conv_t vector_a;
  float16_conv_t vector_b;
  
  float_conv_t opa;
  float_conv_t opb;
  
  float_conv_t res_hw;
  float_conv_t res_sw;

   // initialize CELLRV32 run-time environment
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // print project logo via UART
  cellrv32_rte_print_logo();

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch


  // Disable compilation by default
#ifndef RUN_CHECK
  #warning Program HAS NOT BEEN COMPILED! Use >>make USER_FLAGS+=-DRUN_CHECK clean_all exe<< to compile it.

  // inform the user if you are actually executing this
  cellrv32_uart0_printf("ERROR! Program has not been compiled. Use >>make USER_FLAGS+=-DRUN_CHECK clean_all exe<< to compile it.\n");

  return 1;
#endif


  // intro
  cellrv32_uart0_printf("<<< Zhinx extension test >>>\n");

  // check if Zhinx extension is implemented at all
  if ((cellrv32_cpu_csr_read(CSR_MXISA) & (1<<CSR_MXISA_ZHINX)) == 0) {
    cellrv32_uart0_puts("Error! <Zhinx> extension not synthesized!\n");
    return 1;
  } else {
    cellrv32_uart0_puts("Info: <Zhinx> extension synthesized.\n");
  }

  //
  // check if GPIO device is implemented at all
  if (cellrv32_gpio_available()) {
    cellrv32_uart0_puts("Info: <GPIO> device synthesized.\n\n");
  } else {
    cellrv32_uart0_puts("Error! <GPIO> device not synthesized!\n\n");
    return 1;
  }

#if (SILENT_MODE != 0)
  cellrv32_uart0_printf("SILENT_MODE enabled (only showing actual errors)\n");
#endif
  cellrv32_uart0_printf("Test cases per instruction: %u\n", (uint32_t)NUM_TEST_CASES);
  cellrv32_uart0_printf("NOTE: The CELLRV32 FPU does not support subnormal numbers yet. Subnormal numbers are flushed to zero.\n");
  cellrv32_uart0_printf("WARNING: The F[N]MADD/SUB reference software is non-fused (it performs multiplication, then rounding, then addition and rounding), so some test cases may fail.\n\n");

  // clear exception status word
  cellrv32_cpu_csr_write(CSR_FFLAGS, 0); // real hardware
  feclearexcept(FE_ALL_EXCEPT); // software runtime (GCC floating-point emulation)
  // clear all gpio pins
  cellrv32_gpio_port_set(0);


// ----------------------------------------------------------------------------
// Conversion Tests
// ----------------------------------------------------------------------------

#if (RUN_CONV_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FCVT.H.WU (unsigned integer to half)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = riscv_emulate_fcvt_swu(vector_a.binary_value);
    res_sw.binary_value = float2half(opa.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fcvt_hwu(vector_a.binary_value);
    // verification
    err_cnt += verify_result(i, vector_a.binary_value, opa.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FCVT.H.W (signed integer to half)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = riscv_emulate_fcvt_sw((int32_t)vector_a.binary_value);
    res_sw.binary_value = float2half(opa.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fcvt_hw((int32_t)vector_a.binary_value);
    // verification
    err_cnt += verify_result(i, vector_a.binary_value, opa.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FCVT.WU.H (half to unsigned integer)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    res_sw.binary_value = riscv_emulate_fcvt_wus(opa.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fcvt_wuh(vector_a.binary_value);
    // verification
    err_cnt += verify_result(i, vector_a.binary_value, opa.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FCVT.W.H (half to signed integer)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    res_sw.binary_value = riscv_emulate_fcvt_ws(opa.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fcvt_wh(vector_a.binary_value);
    // verification
    err_cnt += verify_result(i, vector_a.binary_value, opa.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Add/Sub Tests
// ----------------------------------------------------------------------------

#if (RUN_ADDSUB_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FADD.H (addtion)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fadds(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fadds(vector_a.binary_value, vector_b.binary_value);
     // verification
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FSUB.H (subtraction)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fsubs(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fsubs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Multiplication Tests
// ----------------------------------------------------------------------------

#if (RUN_MUL_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FMUL.H (multiplication)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fmuls(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fmuls(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Division Tests
// ----------------------------------------------------------------------------

#if (RUN_DIV_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FDIV.H (division)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
   // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fdivs(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fdivs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Square Root Tests
// ----------------------------------------------------------------------------

#if (RUN_SQRT_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FSQRT.H (square root)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    res_sw.float_value = riscv_emulate_fsqrts(opa.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fsqrts(vector_a.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, 0, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Min/Max Tests
// ----------------------------------------------------------------------------

#if (RUN_MINMAX_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FMIN.H (select minimum)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fmins(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fmins(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FMAX.H (select maximum)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.float_value = riscv_emulate_fmaxs(opa.float_value, opb.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fmaxs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Comparison Tests
// ----------------------------------------------------------------------------

#if (RUN_COMPARE_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FEQ.H (compare if equal)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.binary_value = riscv_emulate_feqs(opa.float_value, opb.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_feqs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FLT.H (compare if less-than)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.binary_value = riscv_emulate_flts(opa.float_value, opb.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_flts(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FLE.H (compare if less-than-or-equal)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    res_sw.binary_value = riscv_emulate_fles(opa.float_value, opb.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fles(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Sign-Injection Tests
// ----------------------------------------------------------------------------

#if (RUN_SGNINJ_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FSGNJ.H (sign-injection)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    res_sw.binary_value = riscv_emulate_fsgnjh(vector_a.binary_value, vector_b.binary_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fsgnjs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FSGNJN.H (sign-injection NOT)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    res_sw.binary_value = riscv_emulate_fsgnjnh(vector_a.binary_value, vector_b.binary_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fsgnjns(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FSGNJX.H (sign-injection XOR)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    // software emulation
    res_sw.binary_value = riscv_emulate_fsgnjxh(vector_a.binary_value, vector_b.binary_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fsgnjxs(vector_a.binary_value, vector_b.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, vector_b.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Classify Tests
// ----------------------------------------------------------------------------

#if (RUN_CLASSIFY_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: FCLASS.H (classify)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    res_sw.binary_value = riscv_emulate_fclasss(opa.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fclasss(vector_a.binary_value);
    err_cnt += verify_result(i, vector_a.binary_value, opa.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif



// ----------------------------------------------------------------------------
// Unsupported Instructions Tests
// ----------------------------------------------------------------------------

#if (RUN_UNAVAIL_TESTS != 0)
// ----------------------------------------------------------------------------
// Fused-Multiply Add/Sub Tests
// ----------------------------------------------------------------------------
  cellrv32_uart0_printf("\n#%u: FMADD.H (fused-multiply addition)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    vector_c.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    opc.float_value = half2float(vector_c.binary_value);
    res_sw.float_value = riscv_emulate_fmadds(opa.float_value, opb.float_value, opc.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fmadds(vector_a.binary_value, vector_b.binary_value, vector_c.binary_value);
     // verification
    err_cnt += verify_result3(i, vector_a.binary_value, vector_b.binary_value, vector_c.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FMSUB.H (fused-multiply subtraction)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    vector_c.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    opc.float_value = half2float(vector_c.binary_value);
    res_sw.float_value = riscv_emulate_fmsubs(opa.float_value, opb.float_value, opc.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fmsubs(vector_a.binary_value, vector_b.binary_value, vector_c.binary_value);
     // verification
    err_cnt += verify_result3(i, vector_a.binary_value, vector_b.binary_value, vector_c.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


// ----------------------------------------------------------------------------
// Fused-Negated-Multiply Add/Sub Tests
// ----------------------------------------------------------------------------
  cellrv32_uart0_printf("\n#%u: FNMADD.H (fused-negated-multiply addition)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    vector_c.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    opc.float_value = half2float(vector_c.binary_value);
    res_sw.float_value = riscv_emulate_fnmadds(opa.float_value, opb.float_value, opc.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fnmadds(vector_a.binary_value, vector_b.binary_value, vector_c.binary_value);
     // verification
    err_cnt += verify_result3(i, vector_a.binary_value, vector_b.binary_value, vector_c.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  cellrv32_uart0_printf("\n#%u: FNMSUB.H (fused-negated-multiply subtraction)...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    // generate vector
    vector_a.binary_value = get_test_vector16();
    vector_b.binary_value = get_test_vector16();
    vector_c.binary_value = get_test_vector16();
    // software emulation
    opa.float_value = half2float(vector_a.binary_value);
    opb.float_value = half2float(vector_b.binary_value);
    opc.float_value = half2float(vector_c.binary_value);
    res_sw.float_value = riscv_emulate_fnmsubs(opa.float_value, opb.float_value, opc.float_value);
    res_sw.binary_value = float2half(res_sw.float_value);
    // hardware
    res_hw.binary_value = riscv_intrinsic_fnmsubs(vector_a.binary_value, vector_b.binary_value, vector_c.binary_value);
     // verification
    err_cnt += verify_result3(i, vector_a.binary_value, vector_b.binary_value, vector_c.binary_value, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Final report
// ----------------------------------------------------------------------------

  if (err_cnt_total != 0) {
    cellrv32_uart0_printf("\n%c[1m[ZHINX EXTENSION VERIFICATION FAILED!]%c[0m\n", 27, 27);
    cellrv32_uart0_printf("%u errors in %u test cases\n", err_cnt_total, test_cnt*(uint32_t)NUM_TEST_CASES);
    // ----------------------------------------------------------------------------
    // ShutDown Generator
    // ----------------------------------------------------------------------------
    cellrv32_gpio_port_set(0xFFFFFFFFFFFFFFFF);
    return 1;
  }
  else {
    cellrv32_uart0_printf("\n%c[1m[ZHINX EXTENSION VERIFICATION SUCCESSFUL...]%c[0m\n", 27, 27);
    // ----------------------------------------------------------------------------
    // ShutDown Generator
    // ----------------------------------------------------------------------------
    cellrv32_gpio_port_set(0xFFFFFFFFFFFFFFFF);
    return 0;
  }

 }


/**********************************************************************//**
 * Generate 16-bit test data (including special values like INFINITY every now and then).
 *
 * @return Test data (16-bit).
 **************************************************************************/
uint16_t get_test_vector16(void) {

  float_conv_t tmp;

  // generate special value "every" ~256th time this function is called
  if ((xorshift32() & 0xff) == 0xff) {

    switch((xorshift32() >> 5) & 0x7) { // random decision which special value we are taking
      case 0: tmp.binary_value = 0x7C00; break;  // +INF
      case 1: tmp.binary_value = 0xFC00; break;  // -INF
      case 2: tmp.binary_value = 0x0000; break;  // +0
      case 3: tmp.binary_value = 0x8000; break;  // -0
      case 4: tmp.binary_value = 0x7E00; break;  // NaN
      case 5: tmp.binary_value = 0x7FFF; break;  // signaling NaN-ish
      case 6: tmp.binary_value = 0x0001; break;  // smallest subnormal
      case 7: tmp.binary_value = 0x03FF; break;  // max subnormal
      default: tmp.binary_value = 0x3555; break; // random normal
    }
  }
  else {
    tmp.binary_value = (uint16_t)(xorshift32() & 0xFFFF);
  }

  return tmp.binary_value;
}


/**********************************************************************//**
 * Generate 32-bit test data (including special values like INFINITY every now and then).
 *
 * @return Test data (32-bit).
 **************************************************************************/
uint32_t get_test_vector32(void) {

  float_conv_t tmp;

  // generate special value "every" ~256th time this function is called
  if ((xorshift32() & 0xff) == 0xff) {

    switch((xorshift32() >> 10) & 0x3) { // random decision which special value we are taking
      case  0: tmp.float_value  = +INFINITY; break;
      case  1: tmp.float_value  = -INFINITY; break;
      case  2: tmp.float_value  = +0.0f; break;
      case  3: tmp.float_value  = -0.0f; break;
      case  4: tmp.binary_value = 0x7fffffff; break;
      case  5: tmp.binary_value = 0xffffffff; break;
      case  6: tmp.float_value  = NAN; break;
      case  7: tmp.float_value  = NAN; break; // FIXME signaling_NAN?
      default: tmp.float_value  = NAN; break;
    }
  }
  else {
    tmp.binary_value = xorshift32();
  }

  return tmp.binary_value;
}


/**********************************************************************//**
 * PSEUDO-RANDOM number generator.
 *
 * @return Random data (32-bit).
 **************************************************************************/
uint32_t xorshift32(void) {

  static uint32_t x32 = 314339265;

  x32 ^= x32 << 13;
  x32 ^= x32 >> 17;
  x32 ^= x32 << 5;

  return x32;
}


/**********************************************************************//**
 * Verify results (software reference vs. actual hardware).
 *
 * @param[in] num Test case number
 * @param[in] opa Operand 1
 * @param[in] opb Operand 2
 * @param[in] ref Software reference
 * @param[in] res Actual results from hardware
 * @return zero if results are equal.
 **************************************************************************/
uint32_t verify_result(uint32_t num, uint32_t opa, uint32_t opb, uint32_t ref, uint32_t res) {

#if (SILENT_MODE == 0)
  cellrv32_uart0_printf("%u: opa = 0x%x, opb = 0x%x : ref[SW] = 0x%x vs. res[HW] = 0x%x ", num, opa, opb, ref, res);
#endif

  if (ref != res) {
#if (SILENT_MODE != 0)
    cellrv32_uart0_printf("%u: opa = 0x%x, opb = 0x%x : ref[SW] = 0x%x vs. res[HW] = 0x%x ", num, opa, opb, ref, res);
#endif
    cellrv32_uart0_printf("%c[1m[FAILED]%c[0m\n", 27, 27);
    return 1;
  }
  else {
#if (SILENT_MODE == 0)
    cellrv32_uart0_printf("%c[1m[ok]%c[0m\n", 27, 27);
#endif
    return 0;
  }
}


/**********************************************************************//**
 * Verify results (software reference vs. actual hardware).
 *
 * @param[in] num Test case number
 * @param[in] opa Operand 1
 * @param[in] opb Operand 2
 * @param[in] opc Operand 3
 * @param[in] ref Software reference
 * @param[in] res Actual results from hardware
 * @return zero if results are equal.
 **************************************************************************/
uint32_t verify_result3(uint32_t num, uint16_t opa, uint16_t opb, uint16_t opc, uint16_t ref, uint16_t res) {

#if (SILENT_MODE == 0)
  cellrv32_uart0_printf("%u: opa = 0x%x, opb = 0x%x, opc = 0x%x : ref[SW] = 0x%x vs. res[HW] = 0x%x ", num, opa, opb, opc, ref, res);
#endif

  if (ref != res) {
#if (SILENT_MODE != 0)
    cellrv32_uart0_printf("%u: opa = 0x%x, opb = 0x%x, opc = 0x%x : ref[SW] = 0x%x vs. res[HW] = 0x%x ", num, opa, opb, opc, ref, res);
#endif
    cellrv32_uart0_printf("%c[1m[FAILED]%c[0m\n", 27, 27);
    return 1;
  }
  else {
#if (SILENT_MODE == 0)
    cellrv32_uart0_printf("%c[1m[ok]%c[0m\n", 27, 27);
#endif
    return 0;
  }
}


/**********************************************************************//**
 * Print test report.
 *
 * @param[in] num_err Number or errors in this test.
 **************************************************************************/
void print_report(uint32_t num_err) {

  cellrv32_uart0_printf("Errors: %u/%u ", num_err, (uint32_t)NUM_TEST_CASES);

  if (num_err == 0) {
    cellrv32_uart0_printf("%c[1m[ok]%c[0m\n", 27, 27);
  }
  else {
    cellrv32_uart0_printf("%c[1m[FAILED]%c[0m\n", 27, 27);
  }
}

 
