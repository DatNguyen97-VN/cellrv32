// ##################################################################################################
// # << CELLRV32 - System/Processor Configuration Information Memory (SYSINFO) >>                   #
// # ********************************************************************************************** #
// # This unit provides information regarding the CELLRV32 processor system configuration -          #
// # mostly derived from the top's configuration generics.                                          #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_sysinfo #(
    /* General */
    parameter int     CLOCK_FREQUENCY    = 0, // clock frequency of clk_i in Hz
    parameter logic[31:0] CUSTOM_ID          = 32'h00000000, // custom user-defined ID
    parameter logic[00:0] INT_BOOTLOADER_EN  = 1'b0, // boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM
    /* Physical memory protection (PMP) */
    parameter int PMP_NUM_REGIONS = 0, // number of regions (0..64)
    /* Internal Instruction memory */
    parameter logic   MEM_INT_IMEM_EN   = 1'b0, // implement processor-internal instruction memory
    parameter int MEM_INT_IMEM_SIZE = 0, // size of processor-internal instruction memory in bytes
    /* Internal Data memory */
    parameter logic   MEM_INT_DMEM_EN   = 1'b0, // implement processor-internal data memory
    parameter int MEM_INT_DMEM_SIZE = 0, // size of processor-internal data memory in bytes
    /* Internal Cache memory */
    parameter logic   ICACHE_EN            = 1'b0, // implement instruction cache
    parameter int ICACHE_NUM_BLOCKS    = 0, // i-cache: number of blocks (min 2), has to be a power of 2
    parameter int ICACHE_BLOCK_SIZE    = 0, // i-cache: block size in bytes (min 4), has to be a power of 2
    parameter int ICACHE_ASSOCIATIVITY = 0, // i-cache: associativity (min 1), has to be a power 2
    /* External memory interface */
    parameter logic MEM_EXT_EN           = 1'b0, // implement external memory bus interface?
    parameter logic MEM_EXT_BIG_ENDIAN   = 1'b0, // byte order: true=big-endian, false=little-endian
    /* On-Chip Debugger */
    parameter logic ON_CHIP_DEBUGGER_EN  = 1'b0, // implement OCD?
    /* Processor peripherals */
    parameter int IO_GPIO_NUM          = 0, // number of GPIO input/output pairs (0..64)
    parameter logic   IO_MTIME_EN          = 1'b0, // implement machine system timer (MTIME)?
    parameter logic   IO_UART0_EN          = 1'b0, // implement primary universal asynchronous receiver/transmitter (UART0)?
    parameter logic   IO_UART1_EN          = 1'b0, // implement secondary universal asynchronous receiver/transmitter (UART1)?
    parameter logic   IO_SPI_EN            = 1'b0, // implement serial peripheral interface (SPI)?
    parameter logic   IO_SDI_EN            = 1'b0, // implement serial data interface (SDI)?
    parameter logic   IO_TWI_EN            = 1'b0, // implement two-wire interface (TWI)?
    parameter int IO_PWM_NUM_CH        = 0, // number of PWM channels to implement
    parameter logic   IO_WDT_EN            = 1'b0, // implement watch dog timer (WDT)?
    parameter logic   IO_TRNG_EN           = 1'b0, // implement true random number generator (TRNG)?
    parameter logic   IO_CFS_EN            = 1'b0, // implement custom functions subsystem (CFS)?
    parameter logic   IO_NEOLED_EN         = 1'b0, // implement NeoPixel-compatible smart LED interface (NEOLED)?
    parameter int IO_XIRQ_NUM_CH       = 0, // number of external interrupt (XIRQ) channels to implement
    parameter logic   IO_GPTMR_EN          = 1'b0, // implement general purpose timer (GPTMR)?
    parameter logic   IO_XIP_EN            = 1'b0, // implement execute in place module (XIP)?
    parameter logic   IO_ONEWIRE_EN        = 1'b0  // implement 1-wire interface (ONEWIRE)?
) (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    output logic        err_o   // transfer error
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1;    // high address boundary bit
    localparam int lo_abb_c = index_size_f(sysinfo_size_c); // low address boundary bit

    /* access control */
    logic       acc_en; // module access enable
    logic       rden;
    logic       wren;
    logic [2:0] addr;

    /* system information ROM */
    typedef logic [0:7][31:0] info_mem_t;
    info_mem_t sysinfo;

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == sysinfo_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign rden   = acc_en & rden_i; // read access
    assign wren   = acc_en & wren_i; // write access
    assign addr   = addr_i[index_size_f(sysinfo_size_c)-1 : 2];

    // Construct Info ROM ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* SYSINFO(0): Processor (primary) clock frequency */
    assign sysinfo[0] = CLOCK_FREQUENCY;

    /* SYSINFO(1): Custom user-defined ID */
    assign sysinfo[1] = CUSTOM_ID;

    /* SYSINFO(2): Implemented processor devices/features */
    /* Memory */
    assign sysinfo[2][00] = INT_BOOTLOADER_EN;   // processor-internal bootloader implemented?
    assign sysinfo[2][01] = MEM_EXT_EN;          // external memory bus interface implemented?
    assign sysinfo[2][02] = (MEM_INT_IMEM_EN && (MEM_INT_IMEM_SIZE > 0)); // processor-internal instruction memory implemented?
    assign sysinfo[2][03] = (MEM_INT_DMEM_EN && (MEM_INT_DMEM_SIZE > 0)); // processor-internal data memory implemented?
    assign sysinfo[2][04] = MEM_EXT_BIG_ENDIAN;  // is external memory bus interface using BIG-endian byte-order?
    assign sysinfo[2][05] = ICACHE_EN;           // processor-internal instruction cache implemented?
    //
    assign sysinfo[2][12:06] = '0; // reserved
    /* Misc */
    assign sysinfo[2][13] = is_simulation_c;     // is this a simulation?
    assign sysinfo[2][14] = ON_CHIP_DEBUGGER_EN; // on-chip debugger implemented?
    //
    assign sysinfo[2][15] = 1'b0; // reserved
    /* IO */
    assign sysinfo[2][16] = (IO_GPIO_NUM > 0);     // general purpose input/output port unit (GPIO) implemented?
    assign sysinfo[2][17] = IO_MTIME_EN;         // machine system timer (MTIME) implemented?
    assign sysinfo[2][18] = IO_UART0_EN;         // primary universal asynchronous receiver/transmitter (UART0) implemented?
    assign sysinfo[2][19] = IO_SPI_EN;           // serial peripheral interface (SPI) implemented?
    assign sysinfo[2][20] = IO_TWI_EN;           // two-wire interface (TWI) implemented?
    assign sysinfo[2][21] = (IO_PWM_NUM_CH > 0);   // pulse-width modulation unit (PWM) implemented?
    assign sysinfo[2][22] = IO_WDT_EN;           // watch dog timer (WDT) implemented?
    assign sysinfo[2][23] = IO_CFS_EN;           // custom functions subsystem (CFS) implemented?
    assign sysinfo[2][24] = IO_TRNG_EN;          // true random number generator (TRNG) implemented?
    assign sysinfo[2][25] = IO_SDI_EN;           // serial data interface (SDI) implemented?
    assign sysinfo[2][26] = IO_UART1_EN;         // secondary universal asynchronous receiver/transmitter (UART1) implemented?
    assign sysinfo[2][27] = IO_NEOLED_EN;        // NeoPixel-compatible smart LED interface (NEOLED) implemented?
    assign sysinfo[2][28] = (IO_XIRQ_NUM_CH > 0);  // external interrupt controller (XIRQ) implemented?
    assign sysinfo[2][29] = IO_GPTMR_EN;         // general purpose timer (GPTMR) implemented?
    assign sysinfo[2][30] = IO_XIP_EN;           // execute in place module (XIP) implemented?
    assign sysinfo[2][31] = IO_ONEWIRE_EN;       // 1-wire interface (ONEWIRE) implemented?

    /* SYSINFO(3): Cache configuration */
    assign sysinfo[3][03 : 00] = (ICACHE_EN == 1'b1) ? 4'(index_size_f(ICACHE_BLOCK_SIZE))    : '0; // i-cache: log2(block_size_in_bytes)
    assign sysinfo[3][07 : 04] = (ICACHE_EN == 1'b1) ? 4'(index_size_f(ICACHE_NUM_BLOCKS))    : '0; // i-cache: log2(number_of_block)
    assign sysinfo[3][11 : 08] = (ICACHE_EN == 1'b1) ? 4'(index_size_f(ICACHE_ASSOCIATIVITY)) : '0; // i-cache: log2(associativity)
    assign sysinfo[3][15 : 12] =  ((ICACHE_ASSOCIATIVITY > 1) && (ICACHE_EN == 1'b1)) ? 4'b0001 : '0; // i-cache: replacement strategy (LRU only (yet))
    //
    assign sysinfo[3][19 : 16] = '0; // reserved - d-cache: log2(block_size)
    assign sysinfo[3][23 : 20] = '0; // reserved - d-cache: log2(num_blocks)
    assign sysinfo[3][27 : 24] = '0; // reserved - d-cache: log2(associativity)
    assign sysinfo[3][31 : 28] = '0; // reserved - d-cache: replacement strategy

    /* SYSINFO(4): Base address of instruction memory space */
    assign sysinfo[4] = ispace_base_c; // defined in cellrv32_package.sv file

    /* SYSINFO(5): Base address of data memory space */
    assign sysinfo[5] = dspace_base_c; // defined in cellrv32_package.sv file

    /* SYSINFO(6): Size of IMEM in bytes */
    assign sysinfo[6] =  (MEM_INT_IMEM_EN == 1'b1) ? MEM_INT_IMEM_SIZE : '0;

    /* SYSINFO(7): Size of DMEM in bytes */
    assign sysinfo[7] =  (MEM_INT_DMEM_EN == 1'b1) ? MEM_INT_DMEM_SIZE : '0;
    
    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden;
        err_o  <= wren; // read-only!
        data_o <= '0;
        //
        if (rden == 1'b1) begin
           data_o <= sysinfo[addr];
        end
    end : read_access

endmodule