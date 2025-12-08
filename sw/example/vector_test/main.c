// ################################################################################################
// # << CELLRV32 - RISC-V Vector 'V' Extension Verification Program >>                            #
// ################################################################################################


/**********************************************************************//**
 * @file vector_test/main.c
 * @author Dat Nguyen
 * @brief Verification program for the CELLRV32 'V' extension using pseudo-random data as input; compares results from hardware against pure-sw reference functions.
 **************************************************************************/


#include <cellrv32.h>
#include <float.h>
#include <math.h>
#include "cellrv32_v_extension_intrinsics.h"

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
#define BAUD_RATE 19200
//** Silent mode (only show actual errors when != 0) */
#define SILENT_MODE        (0)
//** Number of test cases for each instruction */
#define NUM_TEST_CASES     (20)
//** Run FPU CSR tests when != 0 */
#define RUN_CSR_TESTS      (1)
/**@}*/

// Prototypes
uint32_t get_test_vector(void);
uint32_t xorshift32(void);
uint32_t verify_result(uint32_t num, uint32_t opa, uint32_t opb, uint32_t ref, uint32_t res);
void print_report(uint32_t num_err);

/**********************************************************************//**
 * Main function; prints some fancy stuff via UART.
 *
 * @note This program requires the UART interface to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main() {

  uint32_t err_cnt = 0;
  uint32_t err_cnt_total = 0;
  uint32_t test_cnt = 0;
  uint32_t i = 0;
  float_conv_t opa;
  float_conv_t opb;
  float_conv_t opc;
  
  float_conv_t res_hw;
  float_conv_t res_sw;
  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // print project logo via UART
  cellrv32_rte_print_logo();
  
  // intro
  cellrv32_uart0_printf("<<< <V> Vector extension test >>>\n");

  // check if V extension is implemented at all
  if ((cellrv32_cpu_csr_read(CSR_MISA) & (1<<CSR_MISA_V)) == 0) {
    cellrv32_uart0_puts("Error! <V> extension not synthesized!\n");
    return 1;
  } else {
    cellrv32_uart0_puts("Info: <V> extension synthesized.\n");
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

  // ----------------------------------------------------------------------------
  // CSR Read/Write Tests
  // ----------------------------------------------------------------------------
#if (RUN_CSR_TESTS != 0)
  cellrv32_uart0_printf("\n#%u: VSTART CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    opa.binary_value = get_test_vector() & 0xFF;
    cellrv32_cpu_csr_write(CSR_VSTART, opa.binary_value);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VSTART);
    res_sw.binary_value = opa.binary_value;
    err_cnt += verify_result(i, opa.binary_value, 0, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


  cellrv32_uart0_printf("\n#%u: VXRM CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    opa.binary_value = get_test_vector() & 0x3;
    cellrv32_cpu_csr_write(CSR_VXRM, opa.binary_value);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VXRM);
    res_sw.binary_value = opa.binary_value;
    err_cnt += verify_result(i, opa.binary_value, 0, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


  cellrv32_uart0_printf("\n#%u: VCSR CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    opa.binary_value = get_test_vector() & 0x7;
    cellrv32_cpu_csr_write(CSR_VCSR, opa.binary_value);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VCSR);
    res_sw.binary_value = opa.binary_value;
    err_cnt += verify_result(i, opa.binary_value, 0, res_sw.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


  cellrv32_uart0_printf("\n#%u: vsetvl: VL, VTYPE CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)NUM_TEST_CASES; i++) {
    opa.binary_value = get_test_vector();
    opb.binary_value = get_test_vector() & 0x800000FF; // only valid VTYPE bits
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VL);
    err_cnt += verify_result(i, opa.binary_value, opb.binary_value, opc.binary_value, res_hw.binary_value);
    
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VTYPE);
    err_cnt += verify_result(i, opa.binary_value, opb.binary_value, opb.binary_value, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


  cellrv32_uart0_printf("\n#%u: vsetvli: VL, VTYPE CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)1; i++) {
    opa.binary_value = get_test_vector();
    // vsetvli uses immediate operand for vtype
    opc.binary_value = CUSTOM_INSTR_I_TYPE(0b010001010010, opa.binary_value, 0b111, 0b1010111);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VL);
    err_cnt += verify_result(i, opa.binary_value, 0, opc.binary_value, res_hw.binary_value);
    
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VTYPE);
    err_cnt += verify_result(i, opa.binary_value, 0, 0b010001010010, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;


  cellrv32_uart0_printf("\n#%u: vsetivli: VL, VTYPE CSR...\n", test_cnt);
  err_cnt = 0;
  for (i=0;i<(uint32_t)1; i++) {
    opa.binary_value = get_test_vector();
    // vsetivli uses immediate operand for vtype and source
    opc.binary_value = CUSTOM_INSTR_I_TYPE(0b111001010010, opa.binary_value, 0b111, 0b1010111);
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VL);
    err_cnt += verify_result(i, opa.binary_value, 0, opc.binary_value, res_hw.binary_value);
    
    res_hw.binary_value = cellrv32_cpu_csr_read(CSR_VTYPE);
    err_cnt += verify_result(i, opa.binary_value, 0, 0b111001010010, res_hw.binary_value);
  }
  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


// ----------------------------------------------------------------------------
// Final report
// ----------------------------------------------------------------------------

  if (err_cnt_total != 0) {
    cellrv32_uart0_printf("\n%c[1m[VECTOR EXTENSION VERIFICATION FAILED!]%c[0m\n", 27, 27);
    cellrv32_uart0_printf("%u errors in %u test cases\n", err_cnt_total, test_cnt*(uint32_t)NUM_TEST_CASES);
    // ----------------------------------------------------------------------------
    // ShutDown Generator
    // ----------------------------------------------------------------------------
    cellrv32_gpio_port_set(0xFFFFFFFFFFFFFFFF);
    return 1;
  }
  else {
    cellrv32_uart0_printf("\n%c[1m[Vector extension verification successful.]%c[0m\n", 27, 27);
    // ----------------------------------------------------------------------------
    // ShutDown Generator
    // ----------------------------------------------------------------------------
    cellrv32_gpio_port_set(0xFFFFFFFFFFFFFFFF);
    return 0;
  }
}


/**********************************************************************//**
 * Generate 32-bit test data (including special values like INFINITY every now and then).
 *
 * @return Test data (32-bit).
 **************************************************************************/
uint32_t get_test_vector(void) {

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
