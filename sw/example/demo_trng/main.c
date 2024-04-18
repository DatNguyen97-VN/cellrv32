// #################################################################################################
// # << CELLRV32 - TRNG Demo Program >>                                                            #
// #################################################################################################


/**********************************************************************//**
 * @file demo_trng/main.c
 * @author Stephan Nolting
 * @brief True random number generator demo program.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 19200
/**@}*/


// prototypes
void print_random_data(void);
void repetition_count_test(void);
void adaptive_proportion_test(void);
void generate_histogram(void);


/**********************************************************************//**
 * Simple true random number test/demo program.
 *
 * @note This program requires the UART and the TRNG to be synthesized.
 *
 * @return 0 if execution was successful
 **************************************************************************/
int main(void) {

  // check if UART unit is implemented at all
  if (cellrv32_uart0_available() == 0) {
    return 1;
  }

  // capture all exceptions and give debug info via UART
  // this is not required, but keeps us safe
  cellrv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  cellrv32_uart0_setup(BAUD_RATE, 0);

  // check available hardware extensions and compare with compiler flags
  cellrv32_rte_check_isa(0); // silent = 0 -> show message if isa mismatch

  // intro
  cellrv32_uart0_printf("\n<<< CELLRV32 TRNG Demo >>>\n");

  // check if TRNG unit is implemented at all
  if (cellrv32_trng_available() == 0) {
    cellrv32_uart0_printf("No TRNG implemented.\n");
    return 1;
  }

  // check if TRNG is using simulation mode
  if (cellrv32_trng_check_sim_mode() != 0) {
    cellrv32_uart0_printf("WARNING! TRNG uses simulation-only mode implementing a pseudo-RNG (LFSR)\n");
    cellrv32_uart0_printf("         instead of the physical entropy sources!\n");
  }

  // enable TRNG
  cellrv32_trng_enable();
  cellrv32_cpu_delay_ms(100); // TRNG "warm up"

  while(1) {

    // main menu
    cellrv32_uart0_printf("\nCommands:\n"
                         " n: Print 8-bit random numbers (abort by pressing any key)\n"
                         " h: Generate histogram and analyze data\n"
                         " 1: Run repetition count test (NIST SP 800-90B)\n"
                         " 2: Run adaptive proportion test (NIST SP 800-90B)\n");

    cellrv32_uart0_printf("CMD:> ");
    char cmd = cellrv32_uart0_getc();
    cellrv32_uart0_putc(cmd); // echo
    cellrv32_uart0_printf("\n");

    if (cmd == 'n') {
      print_random_data();
    }
    else if (cmd == 'h') {
      generate_histogram();
    }
    else if (cmd == '1') {
      repetition_count_test();
    }
    else if (cmd == '2') {
      adaptive_proportion_test();
    }
    else {
      cellrv32_uart0_printf("Invalid command.\n");
    }
  }

  return 0;
}


/**********************************************************************//**
 * Print random numbers until a key is pressed.
 **************************************************************************/
void print_random_data(void) {

  uint32_t num_samples = 0;
  uint8_t trng_data;

  while(1) {
    if (cellrv32_trng_get(&trng_data)) {
      continue;
    }
    cellrv32_uart0_printf("%u ", (uint32_t)(trng_data));
    num_samples++;
    if (cellrv32_uart0_char_received()) { // abort when key pressed
      cellrv32_uart0_char_received_get(); // discard received char
      break;
    }
  }
  cellrv32_uart0_printf("\nPrinted samples: %u\n", num_samples);
}


/**********************************************************************//**
 * Run repetition count test (NIST SP 800-90B)
 **************************************************************************/
void repetition_count_test(void) {

  int fail = 0;
  uint8_t a, x;
  int b = 0;
  const int c = 10; // cutoff value

  cellrv32_uart0_printf("\nRunning test... Press any key to stop.\n");
  cellrv32_uart0_printf("Cut-off value = %u\n", c);

  while (cellrv32_trng_get(&a));
  b = 1;
  while (1) {
    while (cellrv32_trng_get(&x));

    if (x == a) {
      b++;
      if (b >= c) {
        fail = 1;
      }
    }
    else {
      a = x;
      b = 1;
    }

    if (fail) {
      break;
    }
    if (cellrv32_uart0_char_received()) { // abort when key pressed
      cellrv32_uart0_char_received_get(); // discard received char
      break;
    }
  }

  if (fail) {
    cellrv32_uart0_printf("Test failed!\n");
  }
  else {
    cellrv32_uart0_printf("Test ok!\n");
  }
}


/**********************************************************************//**
 * Run adaptive proportion test (NIST SP 800-90B)
 **************************************************************************/
void adaptive_proportion_test(void) {

  int fail = 0;
  uint8_t a,x;
  int b = 0;
  const int c = 13; // cutoff value
  const int w = 512; // window size
  int i;

  cellrv32_uart0_printf("\nRunning test... Press any key to stop.\n");
  cellrv32_uart0_printf("Cut-off value = %u, windows size = %u\n", c, w);

  while (1) {
    while (cellrv32_trng_get(&a));
    b = 1;
    for (i=1; i<w; i++) {
      while(cellrv32_trng_get(&x));
      if (a == x) {
        b++;
      }
      if (b >= c) {
        fail = 1;
      }
    }

    if (fail) {
      break;
    }
    if (cellrv32_uart0_char_received()) { // abort when key pressed
      cellrv32_uart0_char_received_get(); // discard received char
      break;
    }
  }

  if (fail) {
    cellrv32_uart0_printf("Test failed!\n");
  }
  else {
    cellrv32_uart0_printf("Test ok!\n");
  }
}


/**********************************************************************//**
 * Generate and print histogram. Samples random data until a key is pressed.
 **************************************************************************/
void generate_histogram(void) {

  uint32_t hist[256];
  uint32_t i;
  uint32_t cnt = 0;
  uint8_t trng_data;
  uint64_t average = 0;

  cellrv32_uart0_printf("Press any key to start.\n");

  while(cellrv32_uart0_char_received() == 0);
  cellrv32_uart0_char_received_get(); // discard received char

  cellrv32_uart0_printf("Sampling... Press any key to stop.\n");

  // clear histogram
  for (i=0; i<256; i++) {
    hist[i] = 0;
  }


  // sample random data
  while(1) {

    // get raw TRNG data
    if (cellrv32_trng_get(&trng_data)) {
      continue;
    }

    // add to histogram
    hist[trng_data & 0xff]++;
    cnt++;

    // average
    average += (uint64_t)trng_data;

    // abort conditions
    if ((cellrv32_uart0_char_received()) || // abort when key pressed
        (cnt & 0x80000000UL)) { // to prevent overflow
      cellrv32_uart0_char_received_get(); // discard received char
      break;
    }
  }

  average = average / cnt;


  // deviation (histogram samples)
  uint32_t avg_occurence = cnt / 256;
  int32_t tmp_int;
  int32_t dev_int;
  int32_t dev_int_max = 0x80000000UL; uint32_t bin_max = 0;
  int32_t dev_int_min = 0x7fffffffUL; uint32_t bin_min = 0;
  int32_t dev_int_avg = 0;
  for (i=0; i<256; i++) {
    tmp_int = (int32_t)hist[i];
    dev_int = tmp_int - avg_occurence;

    dev_int_avg += (uint64_t)dev_int;

    if (dev_int < dev_int_min) {
      dev_int_min = dev_int;
      bin_min = i;
    }
    if (dev_int > dev_int_max) {
      dev_int_max = dev_int;
      bin_max = i;
    }
  }

  dev_int_avg = dev_int_avg / 256;

  // print histogram
  cellrv32_uart0_printf("Histogram [random data value] : [# occurrences]\n");
  for (i=0; i<256; i++) {
    cellrv32_uart0_printf("%u: %u\n", (uint32_t)i, hist[i]);
  }
  cellrv32_uart0_printf("\n");


  // print results
  cellrv32_uart0_printf("Analysis results (integer only)\n\n");
  cellrv32_uart0_printf("Number of samples: %u\n", cnt);
  cellrv32_uart0_printf("Arithmetic mean:   %u\n", (uint32_t)average);
  cellrv32_uart0_printf("\nArithmetic deviation\n");
  cellrv32_uart0_printf("Avg. occurrence: %u\n", avg_occurence);
  cellrv32_uart0_printf("Avg. deviation:  %i\n", dev_int_avg);
  cellrv32_uart0_printf("Minimum:         %i (histogram bin %u)\n", dev_int_min, bin_min);
  cellrv32_uart0_printf("Maximum:         %i (histogram bin %u)\n", dev_int_max, bin_max);
}
