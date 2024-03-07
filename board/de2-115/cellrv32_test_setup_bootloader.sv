// ##################################################################################################
// # << NEORV32 - Test Setup using the default UART-Bootloader to upload and run executables >>     #
// # ********************************************************************************************** #
// # Check out the processor's online documentation for more referential information:               #
// #  HQ:         https://github.com/stnolting/neorv32                                              #
// #  Data Sheet: https://stnolting.github.io/neorv32                                               #
// #  User Guide: https://stnolting.github.io/neorv32/ug                                            #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_test_setup_bootloader #(
    /* boolean define */
    parameter true  = 1'b1,
    parameter false = 1'b0,
    /* adapt these for your setup */
    parameter CLOCK_FREQUENCY              = 50000000, // clock frequency of clk_i in Hz
    parameter MEM_INT_IMEM_SIZE            = 32*1024,  // size of processor-internal instruction memory in bytes
    parameter MEM_INT_DMEM_SIZE            = 8*1024,   // size of processor-internal data memory in bytes
    parameter CPU_EXTENSION_RISCV_B        = true,
    parameter CPU_EXTENSION_RISCV_C        = true,
    parameter CPU_EXTENSION_RISCV_E        = false,
    parameter CPU_EXTENSION_RISCV_M        = true,
    parameter CPU_EXTENSION_RISCV_U        = true,
    parameter CPU_EXTENSION_RISCV_Zicsr    = true,
    parameter CPU_EXTENSION_RISCV_Zifencei = true,
    parameter EXT_IMEM_C                   = false   // false: use and boot from proc-internal IMEM, true: use and boot from external (initialized) simulated IMEM (ext. mem A)
) (
    /* Global control */
    input logic clk_i,          // global clock, rising edge
    input logic rstn_i,         // global reset, low-active, async
    /* GPIO */
    output logic [17:0] gpio_o, // parallel output
    /* UART0 */
    output logic uart0_txd_o,   // UART0 send data
    input  logic uart0_rxd_i    // UART0 receive data
);
    // User Configuration ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* general */
    localparam logic ext_dmem_c          = false;      // false: use proc-internal DMEM, true: use external simulated DMEM (ext. mem B)
    localparam logic icache_en_c         = true;      // implement i-cache
    localparam int   icache_block_size_c = 64;        // i-cache block size in bytes

    /* internals - hands off! */
    localparam logic int_imem_c = ~ EXT_IMEM_C;
    localparam logic int_dmem_c = ~ ext_dmem_c;

    // The Core of the Problem -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    neorv32_top #(
        /* General */
        .CLOCK_FREQUENCY              (CLOCK_FREQUENCY),      // clock frequency of clk_i in Hz
        .HW_THREAD_ID                 (0),              // hardware thread id (hartid) (32-bit)
        .CUSTOM_ID                    (32'h12345678),   // custom user-defined ID
        .INT_BOOTLOADER_EN            (true),           // boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM
        /* On-Chip Debugger (OCD) */
        .ON_CHIP_DEBUGGER_EN          (true),           // implement on-chip debugger
        /* RISC-V CPU Extensions */
        .CPU_EXTENSION_RISCV_B        (CPU_EXTENSION_RISCV_B), // implement bit-manipulation extension?
        .CPU_EXTENSION_RISCV_C        (CPU_EXTENSION_RISCV_C), // implement compressed extension?
        .CPU_EXTENSION_RISCV_E        (CPU_EXTENSION_RISCV_E), // implement embedded RF extension?
        .CPU_EXTENSION_RISCV_M        (CPU_EXTENSION_RISCV_M), // implement mul/div extension?
        .CPU_EXTENSION_RISCV_U        (CPU_EXTENSION_RISCV_U), // implement user mode extension?
        .CPU_EXTENSION_RISCV_Zfinx    (true),          // implement 32-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zicsr    (CPU_EXTENSION_RISCV_Zicsr), // implement CSR system?
        .CPU_EXTENSION_RISCV_Zicntr   (true),          // implement base counters?
        .CPU_EXTENSION_RISCV_Zicond   (true),          // implement conditional operations extension?
        .CPU_EXTENSION_RISCV_Zihpm    (true),          // implement hardware performance monitors?
        .CPU_EXTENSION_RISCV_Zifencei (CPU_EXTENSION_RISCV_Zifencei), // implement instruction stream sync.?
        .CPU_EXTENSION_RISCV_Zmmul    (false),          // implement multiply-only M sub-extension?
        .CPU_EXTENSION_RISCV_Zxcfu    (true),          // implement custom (instr.) functions unit?
        /* Extension Options */
        .FAST_MUL_EN                  (true),          // use DSPs for M extension's multiplier
        .FAST_SHIFT_EN                (true),          // use barrel shifter for shift operations
        .CPU_IPB_ENTRIES              (4),             // entries is instruction prefetch buffer, has to be a power of 2, min 1
        /* Physical Memory Protection (PMP) */
        .PMP_NUM_REGIONS              (5),             // number of regions (0..16)
        .PMP_MIN_GRANULARITY          (4),             // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
        /* Hardware Performance Monitors (HPM) */
        .HPM_NUM_CNTS                 (12),            // number of implemented HPM counters (0..29)
        .HPM_CNT_WIDTH                (40),            // total size of HPM counters (0..64)
        /* Internal Instruction memory */
        .MEM_INT_IMEM_EN              (int_imem_c),          // implement processor-internal instruction memory
        .MEM_INT_IMEM_SIZE            (MEM_INT_IMEM_SIZE),   // size of processor-internal instruction memory in bytes
        /* Internal Data memory */
        .MEM_INT_DMEM_EN              (int_dmem_c),          // implement processor-internal data memory
        .MEM_INT_DMEM_SIZE            (MEM_INT_DMEM_SIZE),   // size of processor-internal data memory in bytes
        /* Internal Cache memory */
        .ICACHE_EN                    (icache_en_c),   // implement instruction cache
        .ICACHE_NUM_BLOCKS            (8),             // i-cache: number of blocks (min 2), has to be a power of 2
        .ICACHE_BLOCK_SIZE            (icache_block_size_c), // i-cache: block size in bytes (min 4), has to be a power of 2
        .ICACHE_ASSOCIATIVITY         (2),             // i-cache: associativity / number of sets (1=direct_mapped), has to be a power of 2
        /* External memory interface */
        .MEM_EXT_EN                   (false),          // implement external memory bus interface?
        .MEM_EXT_TIMEOUT              (256),           // cycles after a pending bus access auto-terminates (0 = disabled)
        .MEM_EXT_PIPE_MODE            (false),          // protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
        .MEM_EXT_BIG_ENDIAN           (false),          // byte order: true=big-endian, false=little-endian
        .MEM_EXT_ASYNC_RX             (false),          // use register buffer for RX data when false
        .MEM_EXT_ASYNC_TX             (false),          // use register buffer for TX data when false
        /* External Interrupts Controller (XIRQ) */
        .XIRQ_NUM_CH                  (32),            // number of external IRQ channels (0..32)
        .XIRQ_TRIGGER_TYPE            ('1),            // trigger type: 0=level, 1=edge
        .XIRQ_TRIGGER_POLARITY        ('1),            // trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge
        /* Processor peripherals */
        .IO_GPIO_NUM                  (64),            // number of GPIO input/output pairs (0..64)
        .IO_MTIME_EN                  (true),          // implement machine system timer (MTIME)?
        .IO_UART0_EN                  (true),          // implement primary universal asynchronous receiver/transmitter (UART0)?
        .IO_UART0_RX_FIFO             (32),            // RX fifo depth, has to be a power of two, min 1
        .IO_UART0_TX_FIFO             (32),            // TX fifo depth, has to be a power of two, min 1
        .IO_UART1_EN                  (true),          // implement secondary universal asynchronous receiver/transmitter (UART1)?
        .IO_UART1_RX_FIFO             (1),             // RX fifo depth, has to be a power of two, min 1
        .IO_UART1_TX_FIFO             (1),             // TX fifo depth, has to be a power of two, min 1
        .IO_SPI_EN                    (true),          // implement serial peripheral interface (SPI)?
        .IO_SPI_FIFO                  (4),             // SPI RTX fifo depth, has to be zero or a power of two
        .IO_SDI_EN                    (true),          // implement serial data interface (SDI)?
        .IO_SDI_FIFO                  (4),             // SDI RTX fifo depth, has to be zero or a power of two
        .IO_TWI_EN                    (true),          // implement two-wire interface (TWI)?
        .IO_PWM_NUM_CH                (12),            // number of PWM channels to implement (0..12); 0 = disabled
        .IO_WDT_EN                    (true),          // implement watch dog timer (WDT)?
        .IO_TRNG_EN                   (true),          // implement true random number generator (TRNG)?
        .IO_TRNG_FIFO                 (4),             // TRNG fifo depth, has to be a power of two, min 1
        .IO_CFS_EN                    (true),          // implement custom functions subsystem (CFS)?
        .IO_CFS_CONFIG                ('b0),           // custom CFS configuration generic
        .IO_CFS_IN_SIZE               (32),            // size of CFS input conduit in bits
        .IO_CFS_OUT_SIZE              (32),            // size of CFS output conduit in bits
        .IO_NEOLED_EN                 (true),          // implement NeoPixel-compatible smart LED interface (NEOLED)?
        .IO_NEOLED_TX_FIFO            (8),             // NEOLED TX FIFO depth, 1..32k, has to be a power of two
        .IO_GPTMR_EN                  (true),          // implement general purpose timer (GPTMR)?
        .IO_XIP_EN                    (true),          // implement execute in place module (XIP)?
        .IO_ONEWIRE_EN                (true)           // implement 1-wire interface (ONEWIRE)?
    ) cellrv32_top_inst (
        /* Global control */
        .clk_i          (clk_i),           // global clock, rising edge
        .rstn_i         (rstn_i),          // global reset, low-active, async
        /* JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) */
        .jtag_trst_i    (1'b1),            // low-active TAP reset (optional)
        .jtag_tck_i     (1'b0),            // serial clock
        .jtag_tdi_i     (1'b0),            // serial data input
        .jtag_tdo_o     (    ),            // serial data output
        .jtag_tms_i     (1'b0),            // mode select
        /* Wishbone bus interface (available if MEM_EXT_EN = true) */
        .wb_tag_o       ( ),     // request tag
        .wb_adr_o       ( ),     // address
        .wb_dat_i       ( ),     // read data
        .wb_dat_o       ( ),     // write data
        .wb_we_o        ( ),     // read/write
        .wb_sel_o       ( ),     // byte enable
        .wb_stb_o       ( ),     // strobe
        .wb_cyc_o       ( ),     // valid cycle
        .wb_ack_i       ( ),     // transfer acknowledge
        .wb_err_i       ( ),     // transfer error
        /* Advanced memory control signals (available if MEM_EXT_EN = true) */
        .fence_o        (    ),            // indicates an executed FENCE operation
        .fencei_o       (    ),            // indicates an executed FENCEI operation
        /* XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) */
        .xip_csn_o      (    ),            // chip-select, low-active
        .xip_clk_o      (    ),            // serial clock
        .xip_dat_i      (1'b0),            // device data input
        .xip_dat_o      (    ),            // controller data output
        /* GPIO (available if IO_GPIO_NUM > true) */
        .gpio_o         (gpio_o),            // parallel output
        .gpio_i         ( ),            // parallel input
        /* primary UART0 (available if IO_UART0_EN = true) */
        .uart0_txd_o    (uart0_txd_o),       // UART0 send data
        .uart0_rxd_i    (uart0_rxd_i),       // UART0 receive data
        .uart0_rts_o    ( ),       // HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
        .uart0_cts_i    ( ), // HW flow control: UART0.TX allowed to transmit, low-active, optional
        /* secondary UART1 (available if IO_UART1_EN = true) */
        .uart1_txd_o    ( ),       // UART1 send data
        .uart1_rxd_i    ( ),       // UART1 receive data
        .uart1_rts_o    ( ),       // HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
        .uart1_cts_i    (               ), // HW flow control: UART0.TX allowed to transmit, low-active, optional
        /* SPI (available if IO_SPI_EN = true) */
        .spi_clk_o      ( ),         // SPI serial clock
        .spi_dat_o      ( ),          // controller data out, peripheral data in
        .spi_dat_i      ( ),          // controller data in, peripheral data out
        .spi_csn_o      ( ),         // SPI CS
        /* SDI (available if IO_SDI_EN = true) */
        .sdi_clk_i      ( ),         // SDI serial clock
        .sdi_dat_o      ( ),          // controller data out, peripheral data in
        .sdi_dat_i      ( ),          // controller data in, peripheral data out
        .sdi_csn_i      ( ),         // chip-select
        /* TWI (available if IO_TWI_EN = true) */
        .twi_sda_i      ( ),       // serial data line sense input
        .twi_sda_o      ( ),       // serial data line output (pull low only)
        .twi_scl_i      ( ),       // serial clock line sense input
        .twi_scl_o      ( ),       // serial clock line output (pull low only)
        /* 1-Wire Interface (available if IO_ONEWIRE_EN = true) */
        .onewire_i      ( ),       // 1-wire bus sense input
        .onewire_o      ( ),       // 1-wire bus output (pull low only)
        /* PWM (available if IO_PWM_NUM_CH > 0) */
        .pwm_o          (    ),            // pwm channels
        /* Custom Functions Subsystem IO */
        .cfs_in_i       ('b0),             // custom CFS inputs
        .cfs_out_o      (    ),            // custom CFS outputs
        /* NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) */
        .neoled_o       (    ),            // async serial data line
        /* External platform interrupts (available if XIRQ_NUM_CH > 0) */
        .xirq_i         ( ),       // IRQ channels
        /* CPU Interrupts */
        .mtime_irq_i    (1'b0),            // machine software interrupt, available if IO_MTIME_EN = false
        .msw_irq_i      ( ),        // machine software interrupt
        .mext_irq_i     ( )         // machine external interrupt
    );
endmodule