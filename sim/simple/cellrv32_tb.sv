// ##################################################################################################
// # << CELLRV32 - Default Processor Testbench >>                                                   #
// # ********************************************************************************************** #
// # The processor is configured to use a maximum of functional units (for testing purpose).        #
// # Use the "User Configuration" section to configure the testbench according to your needs.       #
// # See NEORV32 data sheet for more information.                                                   #
// # ********************************************************************************************** #

`timescale 1ns/1ns

`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_tb_simple #(
    parameter logic CPU_EXTENSION_RISCV_B        = 1'b1,
    parameter logic CPU_EXTENSION_RISCV_C        = 1'b1,
    parameter logic CPU_EXTENSION_RISCV_E        = 1'b0,
    parameter logic CPU_EXTENSION_RISCV_M        = 1'b1,
    parameter logic CPU_EXTENSION_RISCV_U        = 1'b1,
    parameter logic CPU_EXTENSION_RISCV_Zicsr    = 1'b1,
    parameter logic CPU_EXTENSION_RISCV_Zifencei = 1'b1,
    parameter logic EXT_IMEM_C                   = 1'b0,   // false: use and boot from proc-internal IMEM, true: use and boot from external (initialized) simulated IMEM (ext. mem A)
    parameter int   MEM_INT_IMEM_SIZE            = 32*1024 // size in bytes of processor-internal IMEM / external mem A (not yet)
) (

);
    // User Configuration ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* general */
    localparam logic ext_dmem_c                  = 1'b0;      // false: use proc-internal DMEM, true: use external simulated DMEM (ext. mem B)
    localparam int   dmem_size_c                 = 8*1024;    // size in bytes of processor-internal DMEM / external mem B
    localparam int   f_clock_c                   = 100000000; // main clock in Hz
    localparam int   baud0_rate_c                = 19200;     // simulation UART0 (primary UART) baud rate
    localparam int   baud1_rate_c                = 19200;     // simulation UART1 (secondary UART) baud rate
    localparam logic icache_en_c                 = 1'b1;      // implement i-cache
    localparam int   icache_block_size_c         = 64;        // i-cache block size in bytes
    /* simulated external Wishbone memory A (can be used as external IMEM) */
    localparam logic[31:0] ext_mem_a_base_addr_c = 32'h00000000;      // wishbone memory base address (external IMEM base)
    localparam int         ext_mem_a_size_c      = MEM_INT_IMEM_SIZE; // wishbone memory size in bytes
    localparam int         ext_mem_a_latency_c   = 8;                 // latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
    /* simulated external Wishbone memory B (can be used as external DMEM) */
    localparam logic[31:0] ext_mem_b_base_addr_c = 32'h80000000; // wishbone memory base address (external DMEM base)
    localparam int         ext_mem_b_size_c      = dmem_size_c;  // wishbone memory size in bytes
    localparam int         ext_mem_b_latency_c   = 8;            // latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
    /* simulated external Wishbone memory C (can be used to simulate external IO access) */
    localparam logic[31:0] ext_mem_c_base_addr_c = 32'hF0000000; // wishbone memory base address (default begin of EXTERNAL IO area)
    localparam int         ext_mem_c_size_c      = icache_block_size_c/2; // wishbone memory size in bytes, should be smaller than an iCACHE block
    localparam int         ext_mem_c_latency_c   = 128; // latency in clock cycles (min 1, max 255), plus 1 cycle initial delay
    /* simulation interrupt trigger */
    localparam logic[31:0] irq_trigger_base_addr_c = 32'hFF000000;
    /* -------------------------------------------------------------------------------------------

    /* internals - hands off! */
    localparam logic int_imem_c       = ~ EXT_IMEM_C;
    localparam logic int_dmem_c       = ~ ext_dmem_c;
    localparam real  uart0_baud_val_c = real'(f_clock_c) / real'(baud0_rate_c);
    localparam real  uart1_baud_val_c = real'(f_clock_c) / real'(baud1_rate_c);
    localparam time  t_clock_c        = (1s) / f_clock_c;

    /* generators */
    logic clk_gen, rst_gen;

    /* uart */
    logic uart0_txd, uart1_txd;
    logic uart0_cts_uart1, uart1_cts_uart0, uart0_cts, uart1_cts;

    /* gpio */
    logic [63:0] gpio;
    logic [31:0] gpio_xirq;

    /* twi */
    logic twi_scl, twi_sda;
    logic twi_scl_i, twi_scl_o, twi_sda_i, twi_sda_o;

    /* 1-wire */
    logic onewire;
    logic onewire_i, onewire_o;

    /* spi & sdi */
    logic [7:0] spi_csn;
    logic spi_di, spi_do, spi_clk;
    logic sdi_di, sdi_do, sdi_clk, sdi_csn;

    /* irq */
    logic msi_ring, mei_ring;

    /* Wishbone bus */
    typedef struct {
        logic [31:0] addr;  // address
        logic [31:0] wdata; // master write data
        logic [31:0] rdata; // master read data
        logic        we;    // write enable
        logic [03:0] sel;   // byte enable
        logic        stb;   // strobe
        logic        cyc;   // valid cycle
        logic        ack;   // transfer acknowledge
        logic        err;   // transfer error
        logic [02:0] tag;   // request tag
    } wishbone_t;
    //
    wishbone_t wb_cpu, wb_mem_a, wb_mem_b, wb_mem_c, wb_irq;

    /* Wishbone access latency type */
    typedef logic [255:0][31:0] ext_mem_read_latency_t;

    /* simulated external memory c (IO) */
    logic [ext_mem_c_size_c/4-1 : 0][31:0] ext_ram_c;

    /* simulated external memory bus feedback type */
    typedef struct {
        ext_mem_read_latency_t rdata;
        logic                  acc_en;
        logic [255:0]          ack;
    } ext_mem_t;
    //
    ext_mem_t ext_mem_a, ext_mem_b, ext_mem_c;

    // declare external ram b variable
    logic [ext_mem_b_size_c/4-1 : 0][31:0] ext_ram_b;

    // Clock/Reset Generator ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        clk_gen = 1'b0;
        forever begin
            #(t_clock_c/2) clk_gen = ~ clk_gen;
        end
    end

    initial begin
        rst_gen = 1'b0;
        #(60*(t_clock_c/2)) rst_gen = 1'b1;
    end
    
    // The Core of the Problem -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_top #(
        /* General */
        .CLOCK_FREQUENCY              (f_clock_c),      // clock frequency of clk_i in Hz
        .HW_THREAD_ID                 (0),              // hardware thread id (hartid) (32-bit)
        .CUSTOM_ID                    (32'h12345678),   // custom user-defined ID
        .INT_BOOTLOADER_EN            (1'b0),           // boot configuration: true = boot explicit bootloader; 1'b0 = boot from int/ext (I)MEM
        /* On-Chip Debugger (OCD) */
        .ON_CHIP_DEBUGGER_EN          (1'b1),           // implement on-chip debugger
        /* RISC-V CPU Extensions */
        .CPU_EXTENSION_RISCV_B        (CPU_EXTENSION_RISCV_B), // implement bit-manipulation extension?
        .CPU_EXTENSION_RISCV_C        (CPU_EXTENSION_RISCV_C), // implement compressed extension?
        .CPU_EXTENSION_RISCV_E        (CPU_EXTENSION_RISCV_E), // implement embedded RF extension?
        .CPU_EXTENSION_RISCV_M        (CPU_EXTENSION_RISCV_M), // implement mul/div extension?
        .CPU_EXTENSION_RISCV_U        (CPU_EXTENSION_RISCV_U), // implement user mode extension?
        .CPU_EXTENSION_RISCV_Zfinx    (1'b1),          // implement 32-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zicsr    (CPU_EXTENSION_RISCV_Zicsr), // implement CSR system?
        .CPU_EXTENSION_RISCV_Zicntr   (1'b1),          // implement base counters?
        .CPU_EXTENSION_RISCV_Zicond   (1'b1),          // implement conditional operations extension?
        .CPU_EXTENSION_RISCV_Zihpm    (1'b1),          // implement hardware performance monitors?
        .CPU_EXTENSION_RISCV_Zifencei (CPU_EXTENSION_RISCV_Zifencei), // implement instruction stream sync.?
        .CPU_EXTENSION_RISCV_Zmmul    (1'b0),          // implement multiply-only M sub-extension?
        .CPU_EXTENSION_RISCV_Zxcfu    (1'b1),          // implement custom (instr.) functions unit?
        /* Extension Options */
        .FAST_MUL_EN                  (1'b1),          // use DSPs for M extension's multiplier
        .FAST_SHIFT_EN                (1'b1),          // use barrel shifter for shift operations
        .CPU_IPB_ENTRIES              (1),             // entries is instruction prefetch buffer, has to be a power of 2, min 1
        /* Physical Memory Protection (PMP) */
        .PMP_NUM_REGIONS              (5),             // number of regions (0..16)
        .PMP_MIN_GRANULARITY          (4),             // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
        /* Hardware Performance Monitors (HPM) */
        .HPM_NUM_CNTS                 (12),            // number of implemented HPM counters (0..29)
        .HPM_CNT_WIDTH                (40),            // total size of HPM counters (0..64)
        /* Internal Instruction memory */
        .MEM_INT_IMEM_EN              (int_imem_c),    // implement processor-internal instruction memory
        .MEM_INT_IMEM_SIZE            (MEM_INT_IMEM_SIZE),   // size of processor-internal instruction memory in bytes
        /* Internal Data memory */
        .MEM_INT_DMEM_EN              (int_dmem_c),    // implement processor-internal data memory
        .MEM_INT_DMEM_SIZE            (dmem_size_c),   // size of processor-internal data memory in bytes
        /* Internal Cache memory */
        .ICACHE_EN                    (icache_en_c),   // implement instruction cache
        .ICACHE_NUM_BLOCKS            (8),             // i-cache: number of blocks (min 2), has to be a power of 2
        .ICACHE_BLOCK_SIZE            (icache_block_size_c), // i-cache: block size in bytes (min 4), has to be a power of 2
        .ICACHE_ASSOCIATIVITY         (2),             // i-cache: associativity / number of sets (1=direct_mapped), has to be a power of 2
        /* External memory interface */
        .MEM_EXT_EN                   (1'b1),          // implement external memory bus interface?
        .MEM_EXT_TIMEOUT              (256),           // cycles after a pending bus access auto-terminates (0 = disabled)
        .MEM_EXT_PIPE_MODE            (1'b0),          // protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
        .MEM_EXT_BIG_ENDIAN           (1'b0),          // byte order: true=big-endian, false=little-endian
        .MEM_EXT_ASYNC_RX             (1'b0),          // use register buffer for RX data when false
        .MEM_EXT_ASYNC_TX             (1'b0),          // use register buffer for TX data when false
        /* External Interrupts Controller (XIRQ) */
        .XIRQ_NUM_CH                  (32),            // number of external IRQ channels (0..32)
        .XIRQ_TRIGGER_TYPE            (32'hffffffff), // trigger type: 0=level, 1=edge
        .XIRQ_TRIGGER_POLARITY        (32'hffffffff), // trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge
        /* Processor peripherals */
        .IO_GPIO_NUM                  (64),            // number of GPIO input/output pairs (0..64)
        .IO_MTIME_EN                  (1'b1),          // implement machine system timer (MTIME)?
        .IO_UART0_EN                  (1'b1),          // implement primary universal asynchronous receiver/transmitter (UART0)?
        .IO_UART0_RX_FIFO             (32),            // RX fifo depth, has to be a power of two, min 1
        .IO_UART0_TX_FIFO             (32),            // TX fifo depth, has to be a power of two, min 1
        .IO_UART1_EN                  (1'b1),          // implement secondary universal asynchronous receiver/transmitter (UART1)?
        .IO_UART1_RX_FIFO             (1),             // RX fifo depth, has to be a power of two, min 1
        .IO_UART1_TX_FIFO             (1),             // TX fifo depth, has to be a power of two, min 1
        .IO_SPI_EN                    (1'b1),          // implement serial peripheral interface (SPI)?
        .IO_SPI_FIFO                  (4),             // SPI RTX fifo depth, has to be zero or a power of two
        .IO_SDI_EN                    (1'b1),          // implement serial data interface (SDI)?
        .IO_SDI_FIFO                  (4),             // SDI RTX fifo depth, has to be zero or a power of two
        .IO_TWI_EN                    (1'b1),          // implement two-wire interface (TWI)?
        .IO_PWM_NUM_CH                (12),            // number of PWM channels to implement (0..12); 0 = disabled
        .IO_WDT_EN                    (1'b1),          // implement watch dog timer (WDT)?
        .IO_TRNG_EN                   (1'b1),          // implement true random number generator (TRNG)?
        .IO_TRNG_FIFO                 (4),             // TRNG fifo depth, has to be a power of two, min 1
        .IO_CFS_EN                    (1'b1),          // implement custom functions subsystem (CFS)?
        .IO_CFS_CONFIG                (0),             // custom CFS configuration generic
        .IO_CFS_IN_SIZE               (32),            // size of CFS input conduit in bits
        .IO_CFS_OUT_SIZE              (32),            // size of CFS output conduit in bits
        .IO_NEOLED_EN                 (1'b1),          // implement NeoPixel-compatible smart LED interface (NEOLED)?
        .IO_NEOLED_TX_FIFO            (8),             // NEOLED TX FIFO depth, 1..32k, has to be a power of two
        .IO_GPTMR_EN                  (1'b1),          // implement general purpose timer (GPTMR)?
        .IO_XIP_EN                    (1'b1),          // implement execute in place module (XIP)?
        .IO_ONEWIRE_EN                (1'b1)           // implement 1-wire interface (ONEWIRE)?
    ) cellrv32_top_inst (
        /* Global control */
        .clk_i          (clk_gen),         // global clock, rising edge
        .rstn_i         (rst_gen),         // global reset, low-active, async
        /* JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) */
        .jtag_trst_i    (1'b1),            // low-active TAP reset (optional)
        .jtag_tck_i     (1'b0),            // serial clock
        .jtag_tdi_i     (1'b0),            // serial data input
        .jtag_tdo_o     (    ),            // serial data output
        .jtag_tms_i     (1'b0),            // mode select
        /* Wishbone bus interface (available if MEM_EXT_EN = true) */
        .wb_tag_o       (wb_cpu.tag),      // request tag
        .wb_adr_o       (wb_cpu.addr),     // address
        .wb_dat_i       (wb_cpu.rdata),    // read data
        .wb_dat_o       (wb_cpu.wdata),    // write data
        .wb_we_o        (wb_cpu.we),       // read/write
        .wb_sel_o       (wb_cpu.sel),      // byte enable
        .wb_stb_o       (wb_cpu.stb),      // strobe
        .wb_cyc_o       (wb_cpu.cyc),      // valid cycle
        .wb_ack_i       (wb_cpu.ack),      // transfer acknowledge
        .wb_err_i       (wb_cpu.err),      // transfer error
        /* Advanced memory control signals (available if MEM_EXT_EN = true) */
        .fence_o        (    ),            // indicates an executed FENCE operation
        .fencei_o       (    ),            // indicates an executed FENCEI operation
        /* XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) */
        .xip_csn_o      (    ),            // chip-select, low-active
        .xip_clk_o      (    ),            // serial clock
        .xip_dat_i      (1'b0),            // device data input
        .xip_dat_o      (    ),            // controller data output
        /* GPIO (available if IO_GPIO_NUM > true) */
        .gpio_o         (gpio),            // parallel output
        .gpio_i         (gpio),            // parallel input
        /* primary UART0 (available if IO_UART0_EN = true) */
        .uart0_txd_o    (uart0_txd),       // UART0 send data
        .uart0_rxd_i    (uart0_txd),       // UART0 receive data
        .uart0_rts_o    (uart1_cts),       // HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
        .uart0_cts_i    (               ), // HW flow control: UART0.TX allowed to transmit, low-active, optional
        /* secondary UART1 (available if IO_UART1_EN = true) */
        .uart1_txd_o    (uart1_txd),       // UART1 send data
        .uart1_rxd_i    (uart1_txd),       // UART1 receive data
        .uart1_rts_o    (uart0_cts),       // HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
        .uart1_cts_i    (               ), // HW flow control: UART0.TX allowed to transmit, low-active, optional
        /* SPI (available if IO_SPI_EN = true) */
        .spi_clk_o      (spi_clk),         // SPI serial clock
        .spi_dat_o      (spi_do),          // controller data out, peripheral data in
        .spi_dat_i      (spi_di),          // controller data in, peripheral data out
        .spi_csn_o      (spi_csn),         // SPI CS
        /* SDI (available if IO_SDI_EN = true) */
        .sdi_clk_i      (sdi_clk),         // SDI serial clock
        .sdi_dat_o      (sdi_do),          // controller data out, peripheral data in
        .sdi_dat_i      (sdi_di),          // controller data in, peripheral data out
        .sdi_csn_i      (sdi_csn),         // chip-select
        /* TWI (available if IO_TWI_EN = true) */
        .twi_sda_i      (twi_sda_i),       // serial data line sense input
        .twi_sda_o      (twi_sda_o),       // serial data line output (pull low only)
        .twi_scl_i      (twi_scl_i),       // serial clock line sense input
        .twi_scl_o      (twi_scl_o),       // serial clock line output (pull low only)
        /* 1-Wire Interface (available if IO_ONEWIRE_EN = true) */
        .onewire_i      (onewire_i),       // 1-wire bus sense input
        .onewire_o      (onewire_o),       // 1-wire bus output (pull low only)
        /* PWM (available if IO_PWM_NUM_CH > 0) */
        .pwm_o          (    ),            // pwm channels
        /* Custom Functions Subsystem IO */
        .cfs_in_i       (0),             // custom CFS inputs
        .cfs_out_o      (    ),            // custom CFS outputs
        /* NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) */
        .neoled_o       (    ),            // async serial data line
        /* External platform interrupts (available if XIRQ_NUM_CH > 0) */
        .xirq_i         (gpio_xirq),       // IRQ channels
        /* CPU Interrupts */
        .mtime_irq_i    (1'b0),            // machine software interrupt, available if IO_MTIME_EN = false
        .msw_irq_i      (msi_ring),        // machine software interrupt
        .mext_irq_i     (mei_ring)         // machine external interrupt
    );

    /* connect GPIO to xirq*/
    assign gpio_xirq = gpio[31:0];

    /* TWI tri-state driver */
    assign twi_sda   = (twi_sda_o == 1'b0) ? 1'b0 : 1'bz; // module can only pull the line low actively
    assign twi_scl   = (twi_scl_o == 1'b0) ? 1'b0 : 1'bz;
    assign twi_sda_i = twi_sda;
    assign twi_scl_i = twi_scl;

    /* 1-Wire tri-state driver */
    assign onewire   = (onewire_o == 1'b0) ? 1'b0 : 1'bz; // module can only pull the line low actively
    assign onewire_i = onewire;

    /* TWI termination (pull-ups) */
    //assign twi_scl = 1'b1; //'H'
    //assign twi_sda = 1'b1; //'H'

    /* 1-Wire termination (pull-up) */
    //assign onewire = 1'b1; //'H'

    /* SPI/SDI echo */
    assign sdi_clk = spi_clk;
    assign sdi_csn = spi_csn[7];
    assign sdi_di  = spi_do;
    assign spi_di  = (spi_csn[7] == 1'b0) ? sdi_do : spi_do;

    // UART Simulation Receiver ------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    uart_rx_simple #(
        .name            ("uart0"),
        .uart_baud_val_c (uart0_baud_val_c)
    ) uart0_checker (
        .clk      (clk_gen),
        .uart_txd (uart0_txd)
    );

    uart_rx_simple #(
        .name            ("uart1"),
        .uart_baud_val_c (uart1_baud_val_c)
    ) uart1_checker (
        .clk      (clk_gen),
        .uart_txd (uart1_txd)
    );

    // Wishbone Fabric ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* CPU broadcast signals */
    assign wb_mem_a.addr  = wb_cpu.addr;
    assign wb_mem_a.wdata = wb_cpu.wdata;
    assign wb_mem_a.we    = wb_cpu.we;
    assign wb_mem_a.sel   = wb_cpu.sel;
    assign wb_mem_a.tag   = wb_cpu.tag;
    assign wb_mem_a.cyc   = wb_cpu.cyc;

    assign wb_mem_b.addr  = wb_cpu.addr;
    assign wb_mem_b.wdata = wb_cpu.wdata;
    assign wb_mem_b.we    = wb_cpu.we;
    assign wb_mem_b.sel   = wb_cpu.sel;
    assign wb_mem_b.tag   = wb_cpu.tag;
    assign wb_mem_b.cyc   = wb_cpu.cyc;

    assign wb_mem_c.addr  = wb_cpu.addr;
    assign wb_mem_c.wdata = wb_cpu.wdata;
    assign wb_mem_c.we    = wb_cpu.we;
    assign wb_mem_c.sel   = wb_cpu.sel;
    assign wb_mem_c.tag   = wb_cpu.tag;
    assign wb_mem_c.cyc   = wb_cpu.cyc;

    assign wb_irq.addr    = wb_cpu.addr;
    assign wb_irq.wdata   = wb_cpu.wdata;
    assign wb_irq.we      = wb_cpu.we;
    assign wb_irq.sel     = wb_cpu.sel;
    assign wb_irq.tag     = wb_cpu.tag;
    assign wb_irq.cyc     = wb_cpu.cyc;

    /* CPU read-back signals (no mux here since peripherals have "output gates") */
    assign wb_cpu.rdata = wb_mem_a.rdata | wb_mem_b.rdata | wb_mem_c.rdata | wb_irq.rdata;
    assign wb_cpu.ack   = wb_mem_a.ack   | wb_mem_b.ack   | wb_mem_c.ack   | wb_irq.ack;
    assign wb_cpu.err   = wb_mem_a.err   | wb_mem_b.err   | wb_mem_c.err   | wb_irq.err;

    /* peripheral select via STROBE signal */
    assign wb_mem_a.stb = ((wb_cpu.addr >= ext_mem_a_base_addr_c) && (wb_cpu.addr < (ext_mem_a_base_addr_c + ext_mem_a_size_c))) ? wb_cpu.stb : 1'b0;
    assign wb_mem_b.stb = ((wb_cpu.addr >= ext_mem_b_base_addr_c) && (wb_cpu.addr < (ext_mem_b_base_addr_c + ext_mem_b_size_c))) ? wb_cpu.stb : 1'b0;
    assign wb_mem_c.stb = ((wb_cpu.addr >= ext_mem_c_base_addr_c) && (wb_cpu.addr < (ext_mem_c_base_addr_c + ext_mem_c_size_c))) ? wb_cpu.stb : 1'b0;
    assign wb_irq.stb   =  (wb_cpu.addr == irq_trigger_base_addr_c) ? wb_cpu.stb : 1'b0;

    // Wishbone Memory A (simulated external IMEM) -----------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate;
        if (EXT_IMEM_C == 1'b0) begin : generate_ext_imem_OFF
            assign wb_mem_a.rdata = '0;
            assign wb_mem_a.ack   = 1'b0;
            assign wb_mem_a.err   = 1'b0;
        end : generate_ext_imem_OFF
    endgenerate

    // Wishbone Memory B (simulated external DMEM) -----------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_gen ) begin : ext_mem_b_access
        //
        /* control */
        ext_mem_b.ack[0] <= wb_mem_b.cyc & wb_mem_b.stb; // wishbone acknowledge

        /* write access */
        if (wb_mem_b.cyc && wb_mem_b.stb && wb_mem_b.we) begin // valid write access
            for (int i = 0; i <= 3; ++i) begin
                if (wb_mem_b.sel[i] == 1'b1) begin
                    ext_ram_b[wb_mem_b.addr[index_size_f(ext_mem_b_size_c/4)+1 : 2]][i*8 +: 8] <= wb_mem_b.wdata[i*8 +: 8];
                end
            end
        end

        /* read access */
        ext_mem_b.rdata[0] <= ext_ram_b[wb_mem_b.addr[index_size_f(ext_mem_b_size_c/4)+1 : 2]]; // word aligned
        
        /* virtual read and ack latency */
        if (ext_mem_b_latency_c > 1) begin
            for (int i = 1; i < ext_mem_b_latency_c; ++i) begin
                ext_mem_b.rdata[i] <= ext_mem_b.rdata[i-1];
                ext_mem_b.ack[i]   <= ext_mem_b.ack[i-1] & wb_mem_b.cyc;
            end
        end

        /* bus output register */
        wb_mem_b.err <= 1'b0;
        if ((ext_mem_b.ack[ext_mem_b_latency_c-1] == 1'b1) && (wb_mem_b.cyc == 1'b1)) begin
          wb_mem_b.rdata <= ext_mem_b.rdata[ext_mem_b_latency_c-1];
          wb_mem_b.ack   <= 1'b1;
        end else begin
          wb_mem_b.rdata <= '0;
          wb_mem_b.ack   <= 1'b0;
        end
    end : ext_mem_b_access

    // Wishbone Memory C (simulated external IO) -------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_gen ) begin : ext_mem_c_access
        /* control */
        ext_mem_c.ack[0] <= wb_mem_c.cyc & wb_mem_c.stb; // wishbone acknowledge

        /* write access */
        if ((wb_mem_c.cyc && wb_mem_c.stb && wb_mem_c.we) == 1'b1) begin // valid write access
            for (int i = 0; i <= 3; ++i) begin
                if (wb_mem_c.sel[i] == 1'b1) begin
                    ext_ram_c[wb_mem_c.addr[index_size_f(ext_mem_c_size_c/4)+1 : 2]][i*8 +: 8] <= wb_mem_c.wdata[i*8 +: 8];
                end
            end
        end

        /* read access */
        ext_mem_c.rdata[0] <= ext_ram_c[wb_mem_c.addr[index_size_f(ext_mem_c_size_c/4)+1 : 2]]; // word aligned
        
        /* virtual read and ack latency */
        if (ext_mem_c_latency_c > 1) begin
            for (int i = 1; i < ext_mem_c_latency_c; ++i) begin
                ext_mem_c.rdata[i] <= ext_mem_c.rdata[i-1];
                ext_mem_c.ack[i]   <= ext_mem_c.ack[i-1] & wb_mem_c.cyc;
            end
        end

        /* bus output register */
        if ((ext_mem_c.ack[ext_mem_c_latency_c-1] == 1'b1) && (wb_mem_c.cyc == 1'b1)) begin
          wb_mem_c.rdata <= ext_mem_c.rdata[ext_mem_c_latency_c-1];
          wb_mem_c.ack   <= 1'b1;
          wb_mem_c.err   <= 1'b0;
        end else begin
          wb_mem_c.rdata <= '0;
          wb_mem_c.ack   <= 1'b0;
          wb_mem_c.err   <= 1'b0;
        end
    end : ext_mem_c_access

    // Wishbone IRQ Triggers ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_gen or negedge rst_gen) begin : irq_trigger
        if (rst_gen == 1'b0) begin
            msi_ring <= 1'b0;
            mei_ring <= 1'b0;
        end else begin
            /* bus interface */
            wb_irq.rdata <= '0;
            wb_irq.ack   <= wb_irq.cyc & wb_irq.stb & wb_irq.we & (&wb_irq.sel);
            wb_irq.err   <= 1'b0;
            /* trigger RISC-V platform IRQs */
            if ((wb_irq.cyc && wb_irq.stb && wb_irq.we && (&wb_irq.sel)) == 1'b1) begin
              msi_ring <= wb_irq.wdata[03]; // machine software interrupt
              mei_ring <= wb_irq.wdata[11]; // machine software interrupt
            end
        end
    end : irq_trigger
    
endmodule : cellrv32_tb_simple