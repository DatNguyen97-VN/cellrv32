// #################################################################################################
// # << CELLRV32 - Conway's Game of Life >>                                                        #
// #################################################################################################


/**********************************************************************//**
 * @file game_of_life/main.c
 * @author Stephan Nolting
 * @brief Conway's game of life in a UART terminal.
 **************************************************************************/

#include <cellrv32.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE     19200
/** Universe x size (has to be a multiple of 8) */
#define NUM_CELLS_X   160
/** Universe y size */
#define NUM_CELLS_Y   40
/** Delay between generations in ms */
#define GEN_DELAY     500
/** Symbol for dead cell */
#define CELL_DEAD  (' ')
/** Symbol for alive cell */
#define CELL_ALIVE ('#')
/**@}*/



/**********************************************************************//**
 * The universe
 **************************************************************************/
uint8_t universe[2][NUM_CELLS_X/8][NUM_CELLS_Y];

// Prototypes
void clear_universe(int u);
void set_cell(int u, int x, int y);
int get_cell(int u, int x, int y);
int get_neighborhood(int u, int x, int y);
void print_universe(int u);
int pop_count(int u);
uint32_t xorshift32(void);


/**********************************************************************//**
 * Conway's Game of Life.
 *
 * @note This program requires the UART to be synthesized (the TRNG is optional).
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


  while (1) {

    int u = 0, cell = 0, n = 0;
    int x, y;
    int trng_available = 0;
    uint8_t trng_data;


    // initialize universe
    uint32_t generation = 0;
    clear_universe(0);
    clear_universe(1);

    // intro
    cellrv32_uart0_printf("\n\n<<< Conways's Game of Life >>>\n\n");
    cellrv32_uart0_printf("This program requires a terminal resolution of at least %ux%u characters.\n", NUM_CELLS_X+2, NUM_CELLS_Y+3);
    cellrv32_uart0_printf("Press any key to start a random-initialized torus-style universe of %ux%u cells.\n", NUM_CELLS_X, NUM_CELLS_Y);
    cellrv32_uart0_printf("You can pause/restart the simulation by pressing any key.\n");


    // check if TRNG was synthesized
    if (cellrv32_trng_available()) {
      cellrv32_uart0_printf("\nTRNG detected. Using TRNG for universe initialization.\n");
      cellrv32_trng_enable();
      trng_available = 1;
    }


    // randomize until key pressed
    while (cellrv32_uart0_char_received() == 0) {
      xorshift32();
    }
    cellrv32_uart0_char_received_get(); // discard received char


    // initialize universe using random data
    for (x=0; x<NUM_CELLS_X/8; x++) {
      for (y=0; y<NUM_CELLS_Y; y++) {
        if (trng_available) {
          while (1) {
            if (cellrv32_trng_get(&trng_data)) {
              continue;
            }
            else {
              break;
            }
          }
          universe[0][x][y] = trng_data; // use data from TRNG
        }
        else {
          universe[0][x][y] = (uint8_t)xorshift32(); // use data from PRNG
        }
      }
    }


    while(1) {

      // user abort?
      if (cellrv32_uart0_char_received()) {
        cellrv32_uart0_char_received_get(); // discard received char
        cellrv32_uart0_printf("\nRestart (y/n)?");
        if (cellrv32_uart0_getc() == 'y') {
          break;
        }
      }

      // print generation, population count and the current universe
      cellrv32_uart0_printf("\n\nGeneration %u: %u/%u living cells\n", (uint32_t)generation, (uint32_t)pop_count(u), NUM_CELLS_X*NUM_CELLS_Y);
      print_universe(u);

      // compute next generation
      clear_universe((u + 1) & 1);

      for (x=0; x<NUM_CELLS_X; x++) {
        for (y=0; y<NUM_CELLS_Y; y++) {

          cell = get_cell(u, x, y); // state of current cell
          n = get_neighborhood(u, x, y); // number of living neighbor cells

          // -- classic rule set --
          // if center cell is dead -> cell comes to life when there are exactly 3 living cells around
          // if center cell is alive -> stay alive if there are 2 or three living cells around
          // else -> cell is/becomes dead
          if (((cell == 0) && (n == 3)) || ((cell != 0) && ((n == 2) || (n == 3)))) {
            set_cell((u + 1) & 1, x, y);
          }

        } // y
      } // x
      u = (u + 1) & 1; // switch universe
      generation++;

      // wait GEN_DELAY ms
      cellrv32_cpu_delay_ms(GEN_DELAY);
    }

  }

  return 0;
}


/**********************************************************************//**
 * Print universe via UARt.
 *
 * @param[in] u Universe select (0 or 1).
 **************************************************************************/
void print_universe(int u){

  int16_t x, y;

  cellrv32_uart0_putc('+');
  for (x=0; x<NUM_CELLS_X; x++) {
    cellrv32_uart0_putc('-');
  }
  cellrv32_uart0_putc('+');
  cellrv32_uart0_putc('\r');
  cellrv32_uart0_putc('\n');

  for (y=0; y<NUM_CELLS_Y; y++) {
    cellrv32_uart0_putc('|');
   
    for (x=0; x<NUM_CELLS_X; x++) {
      if (get_cell(u, x, y))
        cellrv32_uart0_putc((char)CELL_ALIVE);
      else
        cellrv32_uart0_putc((char)CELL_DEAD);
    }

    // end of line
    cellrv32_uart0_putc('|');
    cellrv32_uart0_putc('\r');
    cellrv32_uart0_putc('\n');
  }

  cellrv32_uart0_putc('+');
  for (x=0; x<NUM_CELLS_X; x++) {
    cellrv32_uart0_putc('-');
  }
  cellrv32_uart0_putc('+');
}


/**********************************************************************//**
 * Kill all cells in universe.
 *
 * @param[in] u Universe select (0 or 1).
 **************************************************************************/
void clear_universe(int u){

  uint16_t x, y;

  for (x=0; x<NUM_CELLS_X/8; x++) {
    for (y=0; y<NUM_CELLS_Y; y++) {
      universe[u][x][y] = 0;
    }
  }
}


/**********************************************************************//**
 * Make cell alive.
 *
 * @param[in] u Universe select (0 or 1).
 * @param[in] x X coordinate of cell.
 * @param[in] y Y coordinate of cell.
 **************************************************************************/
void set_cell(int u, int x, int y){

  if ((x >= NUM_CELLS_X) || (y >= NUM_CELLS_Y))
    return; // out of range

  universe[u][x>>3][y] |= (uint8_t)(1 << (7 - (x & 7)));
}


/**********************************************************************//**
 * Get state of cell.
 *
 * @param[in] u Universe select (0 or 1).
 * @param[in] x X coordinate of cell.
 * @param[in] y Y coordinate of cell.
 * @return Cell is dead when 0, cell is alive when 1.
 **************************************************************************/
int get_cell(int u, int x, int y){

  // range check: wrap around -> torus-style universe
  if (x < 0)
    x = NUM_CELLS_X-1;

  if (x > NUM_CELLS_X-1)
    x = 0;

  if (y < 0)
    y = NUM_CELLS_Y-1;

  if (y > NUM_CELLS_Y-1)
    y = 0;

  // check bit according to cell
  uint8_t tmp = universe[u][x>>3][y];
  tmp &= 1 << (7 - (x & 7));

  if (tmp == 0)
    return 0; // DEAD
  else
    return 1; // ALIVE
}


/**********************************************************************//**
 * Get number of living cells in neighborhood.
 *
 * @param[in] u Universe select (0 or 1).
 * @param[in] x X coordinate of the neighborhood's center cell.
 * @param[in] y Y coordinate of the neighborhood's center cell.
 * @return Number of living cells in neighborhood (0..9).
 **************************************************************************/
int get_neighborhood(int u, int x, int y){

// Cell index layout:
// 012
// 3#4
// 567

  int num = 0;
  num += get_cell(u, x-1, y-1); // 0
  num += get_cell(u, x,   y-1); // 1
  num += get_cell(u, x+1, y-1); // 2
  num += get_cell(u, x-1, y);   // 3
  num += get_cell(u, x+1, y);   // 4
  num += get_cell(u, x-1, y+1); // 5
  num += get_cell(u, x,   y+1); // 6
  num += get_cell(u, x+1, y+1); // 7

  return num;
}


/**********************************************************************//**
 * Count living cells in universe.
 *
 * @param[in] u Universe select (0 or 1).
 * @return Number of living cells.
 **************************************************************************/
int pop_count(int u) {

  int x, y, cnt;

  cnt = 0;
  for (x=0; x<NUM_CELLS_X; x++) {
    for (y=0; y<NUM_CELLS_Y; y++) {
      cnt += (int)get_cell(u, x, y);
    }
  }

  return cnt;
}


/**********************************************************************//**
 * Simple pseudo random number generator.
 *
 * @return Random number.
 **************************************************************************/
uint32_t xorshift32(void) {

  static uint32_t x32 = 314159265;

  x32 ^= x32 << 13;
  x32 ^= x32 >> 17;
  x32 ^= x32 << 5;

  return x32;
}
