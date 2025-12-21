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
#define SILENT_MODE          (1)
//** Number of test cases for each instruction */
#define NUM_TEST_CASES       (235)
//** Number of element for each array */
#define NUM_ELEM_ARRAY       (234)
//** Run Vector CSR tests when != 0 */
#define RUN_CSR_TESTS        (0)
//** Run Load/Store tests when != 0 */
#define RUN_LOAD_STORE_TESTS (0)
//** Run Add/Sub tests when != 0 */
#define RUN_ADD_SUB_TESTS    (0)
//** Run Bitwise tests when != 0 */
#define RUN_BITWISE_TESTS    (1)
/**@}*/

// Prototypes
uint32_t get_test_vector(void);
uint32_t xorshift32(void);
uint32_t verify_result(uint32_t num, uint32_t opa, uint32_t opb, uint32_t ref, uint32_t res);
void print_report(uint32_t num_err);
void print_vector_report(uint32_t num_err);

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
  uint32_t round =0;

  float_conv_t opa;
  float_conv_t opb;
  float_conv_t opc;
  float_conv_t opd;
  float_conv_t ope;
  float_conv_t opf;
  float_conv_t oph;
  
  float_conv_t res_hw;
  float_conv_t res_sw;

  int32_t vec_mem1_load[NUM_ELEM_ARRAY]; // memory for vector load/store tests
  int32_t vec_mem2_load[NUM_ELEM_ARRAY]; // vector register emulation
  int32_t vec_mem3_load[NUM_ELEM_ARRAY]; // memory for vector load/store tests
  int32_t vec_mem4_load[NUM_ELEM_ARRAY]; // vector register emulation

  int32_t vec_mem1_store[NUM_ELEM_ARRAY]; // memory for vector load/store tests
  int32_t vec_mem2_store[NUM_ELEM_ARRAY]; // vector register emulation
  int32_t vec_mem3_store[NUM_ELEM_ARRAY]; // memory for vector load/store tests
  int32_t vec_mem4_store[NUM_ELEM_ARRAY]; // vector register emulation

  uint32_t ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  uint32_t ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  uint32_t ptr3_load = (uint32_t)&vec_mem3_load[0]; // base address memory
  uint32_t ptr4_load = (uint32_t)&vec_mem4_load[0]; // base address memory

  uint32_t ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  uint32_t ptr2_store = (uint32_t)&vec_mem2_store[0]; // base address memory
  uint32_t ptr3_store = (uint32_t)&vec_mem3_store[0]; // base address memory
  uint32_t ptr4_store = (uint32_t)&vec_mem4_store[0]; // base address memory

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
  //
  cellrv32_uart0_puts("[WARNING] RISC-V Vector: Ensure array size matches available memory to prevent overflow!\n\n");

#if (SILENT_MODE != 0)
  cellrv32_uart0_printf("SILENT_MODE enabled (only showing actual errors)\n");
#endif
  cellrv32_uart0_printf("Test cases per instruction: %u\n", (uint32_t)NUM_TEST_CASES);
  cellrv32_uart0_printf("Number of array per instruction: %u\n", (uint32_t)NUM_ELEM_ARRAY);

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


#if (RUN_LOAD_STORE_TESTS != 0)
  // ----------------------------------------------------------------------------
  // Load/Store Tests
  // ----------------------------------------------------------------------------
  cellrv32_uart0_printf("\n#%u: Vector Load/Store Instructions...\n", test_cnt);
  err_cnt = 0;
  round = 0;

  // initialize memory with test data
  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem1_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem1 = 0x%x", i, vec_mem1_load[i]);
  }

  cellrv32_uart0_printf("\nvec_mem1 is successfully initialized.");

  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem2_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem2 = 0x%x", i, vec_mem2_load[i]);
  }
  
  cellrv32_uart0_printf("\nvec_mem2 is successfully initialized.");

  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem3_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem2 = 0x%x", i, vec_mem2_load[i]);
  }
  
  cellrv32_uart0_printf("\nvec_mem3 is successfully initialized.");

  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem4_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem2 = 0x%x", i, vec_mem2_load[i]);
  }
  
  cellrv32_uart0_printf("\nvec_mem4 is successfully initialized.");

  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Load Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 1 = 0x%x", ptr1_load);
  cellrv32_uart0_printf("\n End address 1 = 0x%x", &vec_mem1_load[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 2 = 0x%x", ptr2_load);
  cellrv32_uart0_printf("\n End address 2 = 0x%x", &vec_mem2_load[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 3 = 0x%x", ptr3_load);
  cellrv32_uart0_printf("\n End address 3 = 0x%x", &vec_mem3_load[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 4 = 0x%x", ptr4_load);
  cellrv32_uart0_printf("\n End address 4 = 0x%x", &vec_mem4_load[NUM_ELEM_ARRAY-1]);

  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Store Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 1 = 0x%x", ptr1_store);
  cellrv32_uart0_printf("\n End address 1 = 0x%x", &vec_mem1_store[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 2 = 0x%x", ptr2_store);
  cellrv32_uart0_printf("\n End address 2 = 0x%x", &vec_mem2_store[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 3 = 0x%x", ptr3_store);
  cellrv32_uart0_printf("\n End address 3 = 0x%x", &vec_mem3_store[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n Base address 4 = 0x%x", ptr4_store);
  cellrv32_uart0_printf("\n End address 4 = 0x%x\n", &vec_mem4_store[NUM_ELEM_ARRAY-1]);

  opa.binary_value = NUM_ELEM_ARRAY;

  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Load/Store Phase");
  cellrv32_uart0_printf("\n---------------------------------");

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // ================== CONFIGURARE =================
    // SEW=32b, VLMUL=1, only valid VTYPE bits
    //opb.binary_value = 0x00000010 & 0x800000FF;
    // SEW=32b, VLMUL=2, only valid VTYPE bits
    //opb.binary_value = 0x00000011 & 0x800000FF;
    // SEW=32b, VLMUL=4, only valid VTYPE bits
    //opb.binary_value = 0x00000012 & 0x800000FF;
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    opf.binary_value = riscv_intrinsic_vle32v(ptr3_load);
    oph.binary_value = riscv_intrinsic_vle32v(ptr4_load);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, opd.binary_value);
    riscv_intrinsic_vse32v(ptr2_store, ope.binary_value);
    riscv_intrinsic_vse32v(ptr3_store, opf.binary_value);
    riscv_intrinsic_vse32v(ptr4_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    ptr3_load += opc.binary_value * 4;
    ptr4_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    ptr2_store += opc.binary_value * 4;
    ptr3_store += opc.binary_value * 4;
    ptr4_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector Load/Store Verification 1\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    err_cnt += verify_result(i, vec_mem1_load[i], vec_mem1_store[i], vec_mem1_load[i], vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\nVector Load/Store Verification 2\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    err_cnt += verify_result(i, vec_mem2_load[i], vec_mem2_store[i], vec_mem2_load[i], vec_mem2_store[i]);
  }
  
  cellrv32_uart0_printf("\n\nVector Load/Store Verification 3\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    err_cnt += verify_result(i, vec_mem3_load[i], vec_mem3_store[i], vec_mem3_load[i], vec_mem3_store[i]);
  }
  
  cellrv32_uart0_printf("\n\nVector Load/Store Verification 4\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    err_cnt += verify_result(i, vec_mem4_load[i], vec_mem4_store[i], vec_mem4_load[i], vec_mem4_store[i]);
  }
  cellrv32_uart0_printf("\n\n[INF]: Vector Load/Store Instructions completed.\n");

  print_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;
#endif


#if (RUN_ADD_SUB_TESTS != 0)
  // ----------------------------------------------------------------------------
  // Add/Sub Tests
  // ----------------------------------------------------------------------------
  cellrv32_uart0_printf("\n#%u: Vector Add/Sub Instructions...\n", test_cnt);
  err_cnt = 0;

  // initialize memory with test data
  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem1_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem1 = 0x%x", i, vec_mem1_load[i]);
  }

  cellrv32_uart0_printf("\nvec_mem1 is successfully initialized.");

  // initialize memory with test data
  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem2_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem1 = 0x%x", i, vec_mem1_load[i]);
  }
  
  cellrv32_uart0_printf("\nvec_mem2 is successfully initialized.");

  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Source 1 Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 1 = 0x%x", ptr1_load);
  cellrv32_uart0_printf("\n End address 1 = 0x%x", &vec_mem1_load[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Source 2 Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 2 = 0x%x", ptr1_load);
  cellrv32_uart0_printf("\n End address 2 = 0x%x", &vec_mem2_load[NUM_ELEM_ARRAY-1]);


  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Destination Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address Dst = 0x%x", ptr1_store);
  cellrv32_uart0_printf("\n End address Dst = 0x%x", &vec_mem1_store[NUM_ELEM_ARRAY-1]);

  opa.binary_value = NUM_ELEM_ARRAY;

  // ===================================================
  // VADD.VV
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVADD.VV Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vaddvv(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VADD.VV Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i]+vec_mem2_load[i];
    err_cnt += verify_result(i, vec_mem1_load[i], vec_mem2_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VADD.VV Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VADD.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVADD.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vaddvx(ope.binary_value, opd.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VADD.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] + ope.binary_value;
    err_cnt += verify_result(i, ope.binary_value, vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VADD.VX Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VADD.VI
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVADD.VI Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = 0x00000007;

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    //oph.binary_value = riscv_intrinsic_vaddvi(0x001F, opd.binary_value);
    oph.binary_value = CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0000000, opd.binary_value, 0x0007, 0b011, 0b1010111);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VADD.VI Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] + ope.binary_value;
    err_cnt += verify_result(i, 0, 0, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VADD.VI Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VSUB.VV
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVSUB.VV Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vsubvv(ope.binary_value, opd.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VSUB.VV Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem2_load[i] - vec_mem1_load[i];
    err_cnt += verify_result(i, vec_mem2_load[i], vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VSUB.VV Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VSUB.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVSUB.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vsubvx(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VSUB.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] - ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VSUB.VX Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VRSUB.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVRSUB.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vrsubvx(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VRSUB.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = ope.binary_value - vec_mem1_load[i];
    err_cnt += verify_result(i, ope.binary_value, vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VRSUB.VX Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VRSUB.VI
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVRSUB.VI Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = 0x00000007;

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    //oph.binary_value = riscv_intrinsic_vrsubvi(opd.binary_value, 0x0007);
    oph.binary_value = CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0000110, opd.binary_value, 0x0007, 0b011, 0b1010111);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VRSUB.VI Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = ope.binary_value - vec_mem1_load[i];
    err_cnt += verify_result(i, ope.binary_value, vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VRSUB.VI Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++; 
#endif


#if (RUN_BITWISE_TESTS != 0)
  // ----------------------------------------------------------------------------
  // Bitwise Tests
  // ----------------------------------------------------------------------------
  cellrv32_uart0_printf("\n\n----------------------------------------------------------------------------");
  cellrv32_uart0_printf("\n#%u: Vector Bitwise Instructions...\n", test_cnt);
  cellrv32_uart0_printf("----------------------------------------------------------------------------\n");
  err_cnt = 0;

  // initialize memory with test data
  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem1_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem1 = 0x%x", i, vec_mem1_load[i]);
  }
  cellrv32_uart0_printf("\nvec_mem1 is successfully initialized.");

  // initialize memory with test data
  for (i=0;i<(uint32_t)NUM_ELEM_ARRAY; i++) {
    vec_mem2_load[i] = get_test_vector();
    //cellrv32_uart0_printf("\n%d vec_mem1 = 0x%x", i, vec_mem1_load[i]);
  }
  
  cellrv32_uart0_printf("\nvec_mem2 is successfully initialized.");

  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Source 1 Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 1 = 0x%x", ptr1_load);
  cellrv32_uart0_printf("\n End address 1 = 0x%x", &vec_mem1_load[NUM_ELEM_ARRAY-1]);
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Source 2 Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address 2 = 0x%x", ptr1_load);
  cellrv32_uart0_printf("\n End address 2 = 0x%x", &vec_mem2_load[NUM_ELEM_ARRAY-1]);


  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVector Destination Base Address");
  cellrv32_uart0_printf("\n---------------------------------");
  cellrv32_uart0_printf("\n Base address Dst = 0x%x", ptr1_store);
  cellrv32_uart0_printf("\n End address Dst = 0x%x", &vec_mem1_store[NUM_ELEM_ARRAY-1]);

  // ===================================================
  // VAND.VV
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVAND.VV Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vandvv(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VAND.VV Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem2_load[i] & vec_mem1_load[i];
    err_cnt += verify_result(i, vec_mem2_load[i], vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VAND.VV Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VAND.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVAND.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vandvx(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VAND.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] & ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VAND.VX Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  
  // ===================================================
  // VAND.VI
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVAND.VI Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = 0x0000000F;

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    //oph.binary_value = riscv_intrinsic_vandvi(opd.binary_value, 0x0007);
    oph.binary_value = CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010010, opd.binary_value, 0x000F, 0b011, 0b1010111);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VAND.VI Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] & ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VAND.VI Instructions completed.\n");

  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VOR.VV
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVOR.VV Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vorvv(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VOR.VV Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem2_load[i] | vec_mem1_load[i];
    err_cnt += verify_result(i, vec_mem2_load[i], vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VOR.VV Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VOR.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVOR.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vorvx(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VOR.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] | ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VOR.VX Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  
  // ===================================================
  // VOR.VI
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVOR.VI Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = 0x0000000F;

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    //oph.binary_value = riscv_intrinsic_vorvi(opd.binary_value, 0x000F);
    oph.binary_value = CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010100, opd.binary_value, 0x000F, 0b011, 0b1010111);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VOR.VI Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] | ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VOR.VI Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VXOR.VV
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVXOR.VV Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr2_load = (uint32_t)&vec_mem2_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    ope.binary_value = riscv_intrinsic_vle32v(ptr2_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vxorvv(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    ptr2_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VXOR.VV Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem2_load[i] ^ vec_mem1_load[i];
    err_cnt += verify_result(i, vec_mem2_load[i], vec_mem1_load[i], res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VXOR.VV Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  // ===================================================
  // VXOR.VX
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVXOR.VX Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = get_test_vector();

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    oph.binary_value = riscv_intrinsic_vxorvx(opd.binary_value, ope.binary_value);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VXOR.VX Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] ^ ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VXOR.VX Instructions completed.\n");
  print_vector_report(err_cnt);
  err_cnt_total += err_cnt;
  test_cnt++;

  
  // ===================================================
  // VXOR.VI
  // ===================================================
  cellrv32_uart0_printf("\n\n---------------------------------");
  cellrv32_uart0_printf("\nVXOR.VI Test");
  cellrv32_uart0_printf("\n---------------------------------");

  round = 0;
  opa.binary_value = NUM_ELEM_ARRAY;
  ptr1_load = (uint32_t)&vec_mem1_load[0]; // base address memory
  ptr1_store = (uint32_t)&vec_mem1_store[0]; // base address memory
  ope.binary_value = 0xFFFFFFFF;

  do {
    // ================== INTRO ==================
    cellrv32_uart0_printf("\n Start ROUND: %d", round);
    // SEW=32b, VLMUL=8, only valid VTYPE bits
    opb.binary_value = 0x00000013 & 0x800000FF;
    opc.binary_value = riscv_intrinsic_vsetvl(opa.binary_value, opb.binary_value);
    // ================== LOAD PHASE ==================
    opd.binary_value = riscv_intrinsic_vle32v(ptr1_load);
    // ================== ADD PHASE ==================
    //oph.binary_value = riscv_intrinsic_vxorvi(opd.binary_value, 0x000F);
    oph.binary_value = CUSTOM_VECTOR_INSTR_IMM_TYPE(0b0010110, opd.binary_value, 0xFFFF, 0b011, 0b1010111);
    // ================== STORE PHASE ==================
    riscv_intrinsic_vse32v(ptr1_store, oph.binary_value);
    // increate pointer, each element is 4 bytes
    ptr1_load += opc.binary_value * 4;
    //
    ptr1_store += opc.binary_value * 4;
    // decreate number of elements to load
    opa.binary_value -= opc.binary_value;
    //
    round += 1;
  } while (opa.binary_value > 0);

  // verification
  cellrv32_uart0_printf("\n\nVector VXOR.VI Verification\n");
  for (int i = 0; i < NUM_ELEM_ARRAY; i++) {
    res_sw.binary_value = vec_mem1_load[i] ^ ope.binary_value;
    err_cnt += verify_result(i, vec_mem1_load[i], ope.binary_value, res_sw.binary_value, vec_mem1_store[i]);
  }

  cellrv32_uart0_printf("\n\n[INF]: Vector VXOR.VI Instructions completed.\n");
  print_vector_report(err_cnt);
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

void print_vector_report(uint32_t num_err) {

  cellrv32_uart0_printf("Errors: %u/%u ", num_err, (uint32_t)NUM_ELEM_ARRAY);

  if (num_err == 0) {
    cellrv32_uart0_printf("%c[1m[ok]%c[0m\n", 27, 27);
  }
  else {
    cellrv32_uart0_printf("%c[1m[FAILED]%c[0m\n", 27, 27);
  }
}
