// ##################################################################################################
// # << The CELLRV32 RISC-V Processor - Top Entity >>                                               #
// # ********************************************************************************************** #
// # Check out the processor's online documentation for more information:                           #
// #  HQ:         https://github.com/stnolting/neorv32                                              #
// #  Data Sheet: https://stnolting.github.io/neorv32                                               #
// #  User Guide: https://stnolting.github.io/neorv32/ug                                            #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////                                        
//                                                                                                                                       //                                        
//                     ██████╗███████╗██╗     ██╗     ██████╗ ██╗   ██╗██████╗ ██████╗     ████████╗ ██████╗ ██████╗                     //                                                        
//                    ██╔════╝██╔════╝██║     ██║     ██╔══██╗██║   ██║╚════██╗╚════██╗    ╚══██╔══╝██╔═══██╗██╔══██╗                    //       
//                    ██║     █████╗  ██║     ██║     ██████╔╝██║   ██║ █████╔╝ █████╔╝       ██║   ██║   ██║██████╔╝                    //                                               
//                    ██║     ██╔══╝  ██║     ██║     ██╔══██╗╚██╗ ██╔╝ ╚═══██╗██╔═══╝        ██║   ██║   ██║██╔═══╝                     //                                                     
//                    ╚██████╗███████╗███████╗███████╗██║  ██║ ╚████╔╝ ██████╔╝███████╗       ██║   ╚██████╔╝██║                         //                                                     
//                     ╚═════╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═════╝ ╚══════╝       ╚═╝    ╚═════╝ ╚═╝                         //                                                   
//                                                                                                                                       //                              
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module neorv32_top #(
    /* General */
    parameter int     CLOCK_FREQUENCY   = 0,            // clock frequency of clk_i in Hz
    parameter int     HW_THREAD_ID      = 0,            // hardware thread id (32-bit)
    parameter logic[31:0] CUSTOM_ID         = 32'h00000000, // custom user-defined ID
    parameter logic       INT_BOOTLOADER_EN = 1'b0,         // boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM

    /* On-Chip Debugger (OCD) */
    parameter logic ON_CHIP_DEBUGGER_EN = 1'b0,  // implement on-chip debugger

    /* RISC-V CPU Extensions */
    parameter logic CPU_EXTENSION_RISCV_B        = 1'b0,  // implement bit-manipulation extension?
    parameter logic CPU_EXTENSION_RISCV_C        = 1'b0,  // implement compressed extension?
    parameter logic CPU_EXTENSION_RISCV_E        = 1'b0,  // implement embedded RF extension?
    parameter logic CPU_EXTENSION_RISCV_M        = 1'b0,  // implement mul/div extension?
    parameter logic CPU_EXTENSION_RISCV_U        = 1'b0,  // implement user mode extension?
    parameter logic CPU_EXTENSION_RISCV_Zfinx    = 1'b0,  // implement 32-bit floating-point extension (using INT regs!)
    parameter logic CPU_EXTENSION_RISCV_Zicsr    = 1'b1,   // implement CSR system?
    parameter logic CPU_EXTENSION_RISCV_Zicntr   = 1'b1,   // implement base counters?
    parameter logic CPU_EXTENSION_RISCV_Zicond   = 1'b0,  // implement conditional operations extension?
    parameter logic CPU_EXTENSION_RISCV_Zihpm    = 1'b0,  // implement hardware performance monitors?
    parameter logic CPU_EXTENSION_RISCV_Zifencei = 1'b0,  // implement instruction stream sync.?
    parameter logic CPU_EXTENSION_RISCV_Zmmul    = 1'b0,  // implement multiply-only M sub-extension?
    parameter logic CPU_EXTENSION_RISCV_Zxcfu    = 1'b0,  // implement custom (instr.) functions unit?

    /* Tuning Options */
    parameter logic   FAST_MUL_EN     = 1'b0,  // use DSPs for M extension's multiplier
    parameter logic   FAST_SHIFT_EN   = 1'b0,  // use barrel shifter for shift operations
    parameter int     CPU_IPB_ENTRIES = 1,     // entries in instruction prefetch buffer, has to be a power of 2, min 1

    /* Physical Memory Protection (PMP) */
    parameter int PMP_NUM_REGIONS     = 0,      // number of regions (0..16)
    parameter int PMP_MIN_GRANULARITY = 4,      // minimal region granularity in bytes, has to be a power of 2, min 4 bytes

    /* Hardware Performance Monitors (HPM) */
    parameter int HPM_NUM_CNTS        = 0,      // number of implemented HPM counters (0..29)
    parameter int HPM_CNT_WIDTH       = 40,     // total size of HPM counters (0..64)

    /* Internal Instruction memory (IMEM) */
    parameter logic   MEM_INT_IMEM_EN     = 1'b0,    // implement processor-internal instruction memory
    parameter int     MEM_INT_IMEM_SIZE   = 16*1024, // size of processor-internal instruction memory in bytes

    /* Internal Data memory (DMEM) */
    parameter logic   MEM_INT_DMEM_EN     = 1'b0,   // implement processor-internal data memory
    parameter int     MEM_INT_DMEM_SIZE   = 8*1024, // size of processor-internal data memory in bytes

    /* Internal Instruction Cache (iCACHE) */
    parameter logic   ICACHE_EN            = 1'b0,   // implement instruction cache
    parameter int     ICACHE_NUM_BLOCKS    = 4,      // i-cache: number of blocks (min 1), has to be a power of 2
    parameter int     ICACHE_BLOCK_SIZE    = 64,     // i-cache: block size in bytes (min 4), has to be a power of 2
    parameter int     ICACHE_ASSOCIATIVITY = 1,      // i-cache: associativity / number of sets (1=direct_mapped), has to be a power of 2

    /* External memory interface (WISHBONE) */
    parameter logic   MEM_EXT_EN         = 1'b0,  // implement external memory bus interface?
    parameter int MEM_EXT_TIMEOUT    = 255,   // cycles after a pending bus access auto-terminates (0 = disabled)
    parameter logic   MEM_EXT_PIPE_MODE  = 1'b0,  // protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
    parameter logic   MEM_EXT_BIG_ENDIAN = 1'b0,  // byte order: true=big-endian, false=little-endian
    parameter logic   MEM_EXT_ASYNC_RX   = 1'b0,  // use register buffer for RX data when false
    parameter logic   MEM_EXT_ASYNC_TX   = 1'b0,  // use register buffer for TX data when false

    /* External Interrupts Controller (XIRQ) */
    parameter int     XIRQ_NUM_CH           = 0,            // number of external IRQ channels (0..32)
    parameter logic[31:0] XIRQ_TRIGGER_TYPE     = 32'hffffffff, // trigger type: 0=level, 1=edge
    parameter logic[31:0] XIRQ_TRIGGER_POLARITY = 32'hffffffff, // trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge

    /* Processor peripherals */
    parameter int     IO_GPIO_NUM       = 0,      // number of GPIO input/output pairs (0..64)
    parameter logic   IO_MTIME_EN       = 1'b0,   // implement machine system timer (MTIME)?
    parameter logic   IO_UART0_EN       = 1'b0,   // implement primary universal asynchronous receiver/transmitter (UART0)?
    parameter int     IO_UART0_RX_FIFO  = 1,      // RX fifo depth, has to be a power of two, min 1
    parameter int     IO_UART0_TX_FIFO  = 1,      // TX fifo depth, has to be a power of two, min 1
    parameter logic   IO_UART1_EN       = 1'b0,   // implement secondary universal asynchronous receiver/transmitter (UART1)?
    parameter int     IO_UART1_RX_FIFO  = 1,      // RX fifo depth, has to be a power of two, min 1
    parameter int     IO_UART1_TX_FIFO  = 1,      // TX fifo depth, has to be a power of two, min 1
    parameter logic   IO_SPI_EN         = 1'b0,   // implement serial peripheral interface (SPI)?
    parameter int     IO_SPI_FIFO       = 1,      // SPI RTX fifo depth, has to be a power of two, min 1
    parameter logic   IO_SDI_EN         = 1'b1,   // implement serial data interface (SDI)?
    parameter int     IO_SDI_FIFO       = 0,      // SDI RTX fifo depth, has to be zero or a power of two
    parameter logic   IO_TWI_EN         = 1'b0,   // implement two-wire interface (TWI)?
    parameter int     IO_PWM_NUM_CH     = 0,      // number of PWM channels to implement (0..12); 0 = disabled
    parameter logic   IO_WDT_EN         = 1'b0,   // implement watch dog timer (WDT)?
    parameter logic   IO_TRNG_EN        = 1'b0,   // implement true random number generator (TRNG)?
    parameter int     IO_TRNG_FIFO      = 1,      // TRNG fifo depth, has to be a power of two, min 1
    parameter logic   IO_CFS_EN         = 1'b0,   // implement custom functions subsystem (CFS)?
    parameter logic[31:0] IO_CFS_CONFIG = 32'h00000000, // custom CFS configuration generic
    parameter int     IO_CFS_IN_SIZE    = 32,     // size of CFS input conduit in bits
    parameter int     IO_CFS_OUT_SIZE   = 32,     // size of CFS output conduit in bits
    parameter logic   IO_NEOLED_EN      = 1'b0,   // implement NeoPixel-compatible smart LED interface (NEOLED)?
    parameter int     IO_NEOLED_TX_FIFO = 1,      // NEOLED FIFO depth, has to be a power of two, min 1
    parameter logic   IO_GPTMR_EN       = 1'b0,   // implement general purpose timer (GPTMR)?
    parameter logic   IO_XIP_EN         = 1'b0,   // implement execute in place module (XIP)?
    parameter logic   IO_ONEWIRE_EN     = 1'b0    // implement 1-wire interface (ONEWIRE)?
) (
    /* Global control */
    input logic clk_i,  // global clock, rising edge
    input logic rstn_i, // global reset, low-active, async

    /* JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) */
    input  logic jtag_trst_i, // low-active TAP reset (optional)
    input  logic jtag_tck_i,  // serial clock
    input  logic jtag_tdi_i,  // serial data input
    output logic jtag_tdo_o,  // serial data output
    input  logic jtag_tms_i,  // mode select

    /* Wishbone bus interface (available if MEM_EXT_EN = true) */
    output logic [02:0] wb_tag_o, // request tag
    output logic [31:0] wb_adr_o, // address
    input  logic [31:0] wb_dat_i, // read data
    output logic [31:0] wb_dat_o, // write data
    output logic        wb_we_o,  // read/write
    output logic [03:0] wb_sel_o, // byte enable
    output logic        wb_stb_o, // strobe
    output logic        wb_cyc_o, // valid cycle
    input  logic        wb_ack_i, // transfer acknowledge
    input  logic        wb_err_i, // transfer error

    /* Advanced memory control signals */
    output logic fence_o,  // indicates an executed FENCE operation
    output logic fencei_o, // indicates an executed FENCEI operation

    /* XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) */
    output logic xip_csn_o, // chip-select, low-active
    output logic xip_clk_o, // serial clock
    input  logic xip_dat_i, // device data input
    output logic xip_dat_o, // controller data output

    /* GPIO (available if IO_GPIO_NUM > 0) */
    output logic [63:0] gpio_o, // parallel output
    input  logic [63:0] gpio_i, // parallel input

    /* primary UART0 (available if IO_UART0_EN = true) */
    output logic uart0_txd_o,        // UART0 send data
    input  logic uart0_rxd_i,        // UART0 receive data
    output logic uart0_rts_o,        // HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
    input  logic uart0_cts_i,        // HW flow control: UART0.TX allowed to transmit, low-active, optional

    /* secondary UART1 (available if IO_UART1_EN = true) */
    output logic uart1_txd_o,        // UART1 send data
    input  logic uart1_rxd_i,        // UART1 receive data
    output logic uart1_rts_o,        // HW flow control: UART1.RX ready to receive ("RTR"), low-active, optional
    input  logic uart1_cts_i,        // HW flow control: UART1.TX allowed to transmit, low-active, optional

    /* SPI (available if IO_SPI_EN = true) */
    output logic        spi_clk_o, // SPI serial clock
    output logic        spi_dat_o, // controller data out, peripheral data in
    input  logic        spi_dat_i, // controller data in, peripheral data out
    output logic [07:0] spi_csn_o, // chip-select

    /* SDI (available if IO_SDI_EN = true) */
    input  logic sdi_clk_i, // SDI serial clock
    output logic sdi_dat_o, // controller data out, peripheral data in
    input  logic sdi_dat_i, // controller data in, peripheral data out
    input  logic sdi_csn_i, // chip-select

    /* TWI (available if IO_TWI_EN = true) */
    input  logic twi_sda_i, // serial data line sense input
    output logic twi_sda_o, // serial data line output (pull low only)
    input  logic twi_scl_i, // serial clock line sense input
    output logic twi_scl_o, // serial clock line output (pull low only)

    /* 1-Wire Interface (available if IO_ONEWIRE_EN = true) */
    input  logic onewire_i, // 1-wire bus sense input
    output logic onewire_o, // 1-wire bus output (pull low only)

    /* PWM (available if IO_PWM_NUM_CH > 0) */
    output logic [11:0] pwm_o, // pwm channels

    /* Custom Functions Subsystem IO (available if IO_CFS_EN = true) */
    input  logic [IO_CFS_IN_SIZE-1 : 0]  cfs_in_i,  // custom CFS inputs conduit
    output logic [IO_CFS_OUT_SIZE-1 : 0] cfs_out_o, // custom CFS outputs conduit

    /* NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) */
    output logic neoled_o, // async serial data line

    /* External platform interrupts (available if XIRQ_NUM_CH > 0) */
    input  logic [31:0] xirq_i, // IRQ channels

    /* CPU interrupts */
    input  logic mtime_irq_i, // machine timer interrupt, available if IO_MTIME_EN = false
    input  logic msw_irq_i,   // machine software interrupt
    input  logic mext_irq_i   // machine external interrupt
    /* DFT signal */
);   
    /* CPU boot configuration */
    localparam logic [31:0] cpu_boot_addr_c = INT_BOOTLOADER_EN ? boot_rom_base_c : ispace_base_c;

    /* alignment check for internal memories */
    localparam logic [index_size_f(MEM_INT_IMEM_SIZE)-1 : 0] imem_align_check_c = '0;
    localparam logic [index_size_f(MEM_INT_DMEM_SIZE)-1 : 0] dmem_align_check_c = '0;

    /* reset generator */
    logic [3:0] rstn_ext_sreg;
    logic [3:0] rstn_int_sreg;
    logic       rstn_ext;
    logic       rstn_int;
    logic       rstn_wdt;

    /* clock generator */
    logic [11:0] clk_div;
    logic [11:0] clk_div_ff;
    logic [07:0] clk_gen;
    logic [10:0] clk_gen_en;
    logic        clk_gen_en_ff;
    //
    logic wdt_cg_en;
    logic uart0_cg_en;
    logic uart1_cg_en;
    logic spi_cg_en;
    logic twi_cg_en;
    logic pwm_cg_en;
    logic cfs_cg_en;
    logic neoled_cg_en;
    logic gptmr_cg_en;
    logic xip_cg_en;
    logic onewire_cg_en;

    /* CPU status */
    typedef struct {
        logic debug; // set when in debug mode
        logic sleep; // set when in sleep mode
    } cpu_status_t;
    //
    cpu_status_t cpu_s;

    /* bus interface - instruction fetch */
    typedef struct {
        logic [31:0] addr;   // bus access address
        logic [31:0] rdata;  // bus read data
        logic        re;     // read request
        logic        ack;    // bus transfer acknowledge
        logic        err;    // bus transfer error
        logic        fence;  // fence.i instruction executed
        logic        src;    // access source (1=instruction fetch, 0=data access)
        logic        cached; // cached transfer
        logic        priv;   // set when in privileged machine mode
    } bus_i_interface_t;
    //
    bus_i_interface_t cpu_i, i_cache;

    /* bus interface - data access */
    typedef struct {
        logic [31:0] addr;  // bus access address
        logic [31:0] rdata; // bus read data
        logic [31:0] wdata; // bus write data
        logic [03:0] ben;   // byte enable
        logic we;     // write request
        logic re;     // read request
        logic ack;    // bus transfer acknowledge
        logic err;    // bus transfer error
        logic fence;  // fence instruction executed
        logic src;    // access source (1=instruction fetch, 0=data access)
        logic cached; // cached transfer
        logic priv;   // set when in privileged machine mode
    } bus_d_interface_t;
    //
    bus_d_interface_t cpu_d, p_bus;

    /* bus access error (from BUSKEEPER) */
    logic bus_error;

    /* debug core interface (DCI) */
    logic dci_ndmrstn;
    logic dci_halt_req;

    /* debug module interface (DMI) */
    typedef struct {
        logic        req_valid;
        logic        req_ready; // DMI is allowed to make new requests when set
        logic [05:0] req_address;
        logic [01:0] req_op;
        logic [31:0] req_data;
        logic        rsp_valid; // response valid when set
        logic        rsp_ready; // ready to receive respond
        logic [31:0] rsp_data;
        logic [01:0] rsp_op;
    } dmi_t;
    //
    dmi_t dmi;

    /* io space access */
    logic io_acc;
    logic io_rden;
    logic io_wren;

    /* module response bus - entry type */
    typedef struct {
        logic [31:0] rdata;
        logic        ack;
        logic        err;
    } resp_bus_entry_t;

    /* termination for unused/unimplemented bus endpoints */
    const resp_bus_entry_t resp_bus_entry_terminate_c = '{rdata : '0, ack : 1'b0, err : 1'b0};

    /* module response bus - device ID */
    enum { RESP_BUSKEEPER, RESP_IMEM, RESP_DMEM, RESP_BOOTROM, RESP_WISHBONE, RESP_GPIO,
           RESP_MTIME, RESP_UART0, RESP_UART1, RESP_SPI, RESP_TWI, RESP_PWM, RESP_WDT,
           RESP_TRNG, RESP_CFS, RESP_NEOLED, RESP_SYSINFO, RESP_OCD, RESP_XIRQ, RESP_GPTMR,
           RESP_XIP_CT, RESP_XIP_ACC, RESP_ONEWIRE, RESP_SDI } resp_bus_id;
    
    /* module response bus */
    resp_bus_entry_t resp_bus [24]; // number of device ID is 24
    // initiate default value of all element in resp_bus array
    // for (genvar i = 0; i < 24; ++i) begin
    //     assign resp_bus[i] = resp_bus_entry_terminate_c;
    // end

    /* IRQs */
    logic [15:0] fast_irq;
    logic        mtime_irq;
    logic        wdt_irq;
    logic        uart0_rx_irq;
    logic        uart0_tx_irq;
    logic        uart1_rx_irq;
    logic        uart1_tx_irq;
    logic        spi_irq;
    logic        sdi_irq;
    logic        twi_irq;
    logic        cfs_irq;
    logic        neoled_irq;
    logic        xirq_irq;
    logic        gptmr_irq;
    logic        onewire_irq;

    /* misc */
    logic       ext_timeout;
    logic       ext_access;
    logic       xip_access;
    logic       xip_enable;
    logic [3:0] xip_page;

    // Processor IO/Peripherals Configuration ----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        /* TIP */
        assert (1'b0) else $info("Tip: Compile application with USER_FLAGS+=-DUART[0/1]_SIM_MODE to auto-enable UART[0/1]'s simulation mode (redirect UART output to simulator console).\n");
       
        assert (1'b0) else $info(
        "CELLRV32 PROCESSOR CONFIG NOTE: Peripherals = %S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S",
        cond_sel_string_f((IO_GPIO_NUM > 0), "GPIO ", ""),
        cond_sel_string_f(IO_MTIME_EN, "MTIME ", ""),
        cond_sel_string_f(IO_UART0_EN, "UART0 ", ""),
        cond_sel_string_f(IO_UART1_EN, "UART1 ", ""),
        cond_sel_string_f(IO_SPI_EN, "SPI ", ""),
        cond_sel_string_f(IO_SDI_EN, "SDI ", ""),
        cond_sel_string_f(IO_TWI_EN, "TWI ", ""),
        cond_sel_string_f((IO_PWM_NUM_CH > 0), "PWM ", ""),
        cond_sel_string_f(IO_WDT_EN, "WDT ", ""),
        cond_sel_string_f(IO_TRNG_EN, "TRNG ", ""),
        cond_sel_string_f(IO_CFS_EN, "CFS ", ""),
        cond_sel_string_f(IO_NEOLED_EN, "NEOLED ", ""),
        cond_sel_string_f((XIRQ_NUM_CH > 0), "XIRQ ", ""),
        cond_sel_string_f(IO_GPTMR_EN, "GPTMR ", ""),
        cond_sel_string_f(IO_XIP_EN, "XIP ", ""),
        cond_sel_string_f(IO_ONEWIRE_EN, "ONEWIRE ", ""));
    end

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        /* boot configuration */
        assert (INT_BOOTLOADER_EN != 1'b1) else
        $info("CELLRV32 PROCESSOR CONFIG NOTE: Boot configuration: Indirect boot via bootloader (processor-internal BOOTROM).");
        assert ((INT_BOOTLOADER_EN != 1'b0) || (MEM_INT_IMEM_EN != 1'b1)) else
        $info("CELLRV32 PROCESSOR CONFIG NOTE: Boot configuration = direct boot from memory (processor-internal IMEM).");
        assert ((INT_BOOTLOADER_EN != 1'b0) || (MEM_INT_IMEM_EN != 1'b0)) else
        $info("CELLRV32 PROCESSOR CONFIG NOTE: Boot configuration = direct boot from memory (processor-external memory).");
        //
        assert ((MEM_EXT_EN != 1'b0) || (MEM_INT_DMEM_EN != 1'b0)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Core cannot fetch data without external memory interface and internal IMEM.");
        assert ((MEM_EXT_EN != 1'b0) || (MEM_INT_IMEM_EN != 1'b0) || (INT_BOOTLOADER_EN != 1'b0)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Core cannot fetch instructions without external memory interface, internal IMEM and bootloader.");
      
        /* memory size */
        assert ((MEM_INT_DMEM_EN != 1'b1) || (is_power_of_two_f(MEM_INT_IMEM_SIZE) != 1'b0)) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! MEM_INT_IMEM_SIZE should be a power of 2 to allow optimal hardware mapping.");
        assert ((MEM_INT_IMEM_EN != 1'b1) || (is_power_of_two_f(MEM_INT_DMEM_SIZE) != 1'b0)) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! MEM_INT_DMEM_SIZE should be a power of 2 to allow optimal hardware mapping.");
      
        /* memory layout */
        assert (ispace_base_c[1:0] == 2'b00) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Instruction memory space base address must be 32-bit-aligned.");
        assert (dspace_base_c[1:0] == 2'b00) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Data memory space base address must be 32-bit-aligned.");
        assert ((ispace_base_c[index_size_f(MEM_INT_IMEM_SIZE)-1 : 0] == imem_align_check_c) || (MEM_INT_IMEM_EN != 1'b1)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Instruction memory space base address has to be aligned to IMEM size.");
        assert ((dspace_base_c[index_size_f(MEM_INT_DMEM_SIZE)-1 : 0] == dmem_align_check_c) || (MEM_INT_DMEM_EN != 1'b1)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR! Data memory space base address has to be aligned to DMEM size.");
        //
        assert (ispace_base_c == 32'h00000000) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! Non-default base address for INSTRUCTION ADDRESS SPACE. Make sure this is sync with the software framework.");
        assert (dspace_base_c == 32'h80000000) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! Non-default base address for DATA ADDRESS SPACE. Make sure this is sync with the software framework.");
      
        /* on-chip debugger */
        assert (ON_CHIP_DEBUGGER_EN != 1'b1) else
        $info("CELLRV32 PROCESSOR CONFIG NOTE: Implementing on-chip debugger (OCD).");
      
        /* instruction cache */
        assert ((ICACHE_EN != 1'b1) || (CPU_EXTENSION_RISCV_Zifencei != 1'b0)) else
        $warning("CELLRV32 CPU CONFIG WARNING! The <CPU_EXTENSION_RISCV_Zifencei> is required to perform i-cache memory sync operations.");
    end

    // ****************************************************************************************************************************
    // Clock and Reset System
    // ****************************************************************************************************************************
    
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                                                                //             
    //           ██████╗ ███████╗███████╗███████╗████████╗     ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ████████╗ ██████╗ ██████╗            //
    //           ██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝    ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗           //
    //           ██████╔╝█████╗  ███████╗█████╗     ██║       ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║   ██║   ██║   ██║██████╔╝           //
    //           ██╔══██╗██╔══╝  ╚════██║██╔══╝     ██║       ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║   ██║   ██║   ██║██╔══██╗           //
    //           ██║  ██║███████╗███████║███████╗   ██║       ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║  ██║           //
    //           ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝        ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝           //
    //                                                                                                                                                //           
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Reset Generator ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(negedge clk_i or negedge rstn_i) begin : reset_generator
        if (rstn_i == 1'b0) begin
            rstn_ext_sreg <= '0;
            rstn_int_sreg <= '0;
            rstn_ext      <= 1'b0;
            rstn_int      <= 1'b0;
        end else begin
            /* external reset */
            rstn_ext_sreg <= {rstn_ext_sreg[$bits(rstn_ext_sreg)-2 : 0], 1'b1}; // active for at least <rstn_ext_sreg'size> clock cycles
            /* internal reset */
            if ((rstn_wdt == 1'b0) || (dci_ndmrstn == 1'b0)) // sync reset sources
               rstn_int_sreg <= '0;
            else
               rstn_int_sreg <= {rstn_int_sreg[$bits(rstn_int_sreg)-2 : 0], 1'b1}; // active for at least <rstn_int_sreg'size> clock cycles
            
            /* reset nets */
            rstn_ext <= &(rstn_ext_sreg); // external reset (via reset pin)
            rstn_int <= &(rstn_int_sreg); // internal reset (via reset pin, WDT or OCD)
        end
    end : reset_generator
    
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                                                                    //                      
    //              ██████╗██╗      ██████╗  ██████╗██╗  ██╗     ██████╗ ███████╗███╗   ██╗███████╗██████╗  █████╗ ████████╗ ██████╗ ██████╗              //         
    //             ██╔════╝██║     ██╔═══██╗██╔════╝██║ ██╔╝    ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗             //        
    //             ██║     ██║     ██║   ██║██║     █████╔╝     ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ██████╔╝███████║   ██║   ██║   ██║██████╔╝             //               
    //             ██║     ██║     ██║   ██║██║     ██╔═██╗     ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║   ██║   ██║   ██║██╔══██╗             //              
    //             ╚██████╗███████╗╚██████╔╝╚██████╗██║  ██╗    ╚██████╔╝███████╗██║ ╚████║███████╗██║  ██║██║  ██║   ██║   ╚██████╔╝██║  ██║             //           
    //              ╚═════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝     ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝             //         
    //                                                                                                                                                    //                                         
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////                      

    // Clock Generator ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : clock_generator
        if (rstn_i == 1'b0) begin
            clk_gen_en_ff <= 1'b0;
            clk_div       <= '0;
            clk_div_ff    <= '0;
        end else begin
            clk_gen_en_ff <= |(clk_gen_en);
            if (clk_gen_en_ff == 1'b1)
              clk_div <= clk_div + 12'd1;
            else // reset if disabled
              clk_div <= '0;
            clk_div_ff <= clk_div;
        end
    end : clock_generator

    /* clock enables: rising edge detectors */
    assign clk_gen[clk_div2_c]    = clk_div[0]  & (~ clk_div_ff[0]);  // CLK/2
    assign clk_gen[clk_div4_c]    = clk_div[1]  & (~ clk_div_ff[1]);  // CLK/4
    assign clk_gen[clk_div8_c]    = clk_div[2]  & (~ clk_div_ff[2]);  // CLK/8
    assign clk_gen[clk_div64_c]   = clk_div[5]  & (~ clk_div_ff[5]);  // CLK/64
    assign clk_gen[clk_div128_c]  = clk_div[6]  & (~ clk_div_ff[6]);  // CLK/128
    assign clk_gen[clk_div1024_c] = clk_div[9]  & (~ clk_div_ff[9]);  // CLK/1024
    assign clk_gen[clk_div2048_c] = clk_div[10] & (~ clk_div_ff[10]); // CLK/2048
    assign clk_gen[clk_div4096_c] = clk_div[11] & (~ clk_div_ff[11]); // CLK/4096

    /* fresh clocks anyone? */
    assign clk_gen_en[0]  = wdt_cg_en;
    assign clk_gen_en[1]  = uart0_cg_en;
    assign clk_gen_en[2]  = uart1_cg_en;
    assign clk_gen_en[3]  = spi_cg_en;
    assign clk_gen_en[4]  = twi_cg_en;
    assign clk_gen_en[5]  = pwm_cg_en;
    assign clk_gen_en[6]  = cfs_cg_en;
    assign clk_gen_en[7]  = neoled_cg_en;
    assign clk_gen_en[8]  = gptmr_cg_en;
    assign clk_gen_en[9]  = xip_cg_en;
    assign clk_gen_en[10] = onewire_cg_en;

    // ****************************************************************************************************************************
    // CPU Core Complex
    // ****************************************************************************************************************************

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                                  //                                                              
    //                           ██████╗██████╗ ██╗   ██╗     ██████╗ ██████╗ ██████╗ ███████╗                          //          
    //                          ██╔════╝██╔══██╗██║   ██║    ██╔════╝██╔═══██╗██╔══██╗██╔════╝                          //
    //                          ██║     ██████╔╝██║   ██║    ██║     ██║   ██║██████╔╝█████╗                            //
    //                          ██║     ██╔═══╝ ██║   ██║    ██║     ██║   ██║██╔══██╗██╔══╝                            //
    //                          ╚██████╗██║     ╚██████╔╝    ╚██████╗╚██████╔╝██║  ██║███████╗                          //
    //                           ╚═════╝╚═╝      ╚═════╝      ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝                          //
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////                                                                            
                                                              
    // CPU Core ----------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    neorv32_cpu #(
        /* General */
        .HW_THREAD_ID                (HW_THREAD_ID),                 // hardware thread id
        .CPU_BOOT_ADDR               (cpu_boot_addr_c),              // cpu boot address
        .CPU_DEBUG_PARK_ADDR         (dm_park_entry_c),              // cpu debug mode parking loop entry address
        .CPU_DEBUG_EXC_ADDR          (dm_exc_entry_c),               // cpu debug mode exception entry address
        /* RISC-V CPU Extensions */
        .CPU_EXTENSION_RISCV_B       (CPU_EXTENSION_RISCV_B),        // implement bit-manipulation extension?
        .CPU_EXTENSION_RISCV_C       (CPU_EXTENSION_RISCV_C),        // implement compressed extension?
        .CPU_EXTENSION_RISCV_E       (CPU_EXTENSION_RISCV_E),        // implement embedded RF extension?
        .CPU_EXTENSION_RISCV_M       (CPU_EXTENSION_RISCV_M),        // implement mul/div extension?
        .CPU_EXTENSION_RISCV_U       (CPU_EXTENSION_RISCV_U),        // implement user mode extension?
        .CPU_EXTENSION_RISCV_Zfinx   (CPU_EXTENSION_RISCV_Zfinx),    // implement 32-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zicsr   (CPU_EXTENSION_RISCV_Zicsr),    // implement CSR system?
        .CPU_EXTENSION_RISCV_Zicntr  (CPU_EXTENSION_RISCV_Zicntr),   // implement base counters?
        .CPU_EXTENSION_RISCV_Zicond  (CPU_EXTENSION_RISCV_Zicond),   // implement conditional operations extension?
        .CPU_EXTENSION_RISCV_Zihpm   (CPU_EXTENSION_RISCV_Zihpm),    // implement hardware performance monitors?
        .CPU_EXTENSION_RISCV_Zifencei(CPU_EXTENSION_RISCV_Zifencei), // implement instruction stream sync.?
        .CPU_EXTENSION_RISCV_Zmmul   (CPU_EXTENSION_RISCV_Zmmul),    // implement multiply-only M sub-extension?
        .CPU_EXTENSION_RISCV_Zxcfu   (CPU_EXTENSION_RISCV_Zxcfu),    // implement custom (instr.) functions unit?
        .CPU_EXTENSION_RISCV_Sdext   (ON_CHIP_DEBUGGER_EN),          // implement external debug mode extension?
        .CPU_EXTENSION_RISCV_Sdtrig  (ON_CHIP_DEBUGGER_EN),          // implement debug mode trigger module extension?
        /* Extension Options */
        .FAST_MUL_EN                 (FAST_MUL_EN),                  // use DSPs for M extension's multiplier
        .FAST_SHIFT_EN               (FAST_SHIFT_EN),                // use barrel shifter for shift operations
        .CPU_IPB_ENTRIES             (CPU_IPB_ENTRIES),              // entries is instruction prefetch buffer, has to be a power of 1
        /* Physical Memory Protection (PMP) */
        .PMP_NUM_REGIONS             (PMP_NUM_REGIONS),              // number of regions (0..16)
        .PMP_MIN_GRANULARITY         (PMP_MIN_GRANULARITY),          // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
        /* Hardware Performance Monitors (HPM) */
        .HPM_NUM_CNTS                (HPM_NUM_CNTS),                 // number of implemented HPM counters (0..29)
        .HPM_CNT_WIDTH               (HPM_CNT_WIDTH)                 // total size of HPM counters (0..64)
    ) neorv32_cpu_inst (
        /* global control */
        .clk_i         (clk_i),       // global clock, rising edge
        .rstn_i        (rstn_int),    // global reset, low-active, async
        .sleep_o       (cpu_s.sleep), // cpu is in sleep mode when set
        .debug_o       (cpu_s.debug), // cpu is in debug mode when set
        /* instruction bus interface */
        .i_bus_addr_o  (cpu_i.addr),  // bus access address
        .i_bus_rdata_i (cpu_i.rdata), // bus read data
        .i_bus_re_o    (cpu_i.re),    // read request
        .i_bus_ack_i   (cpu_i.ack),   // bus transfer acknowledge
        .i_bus_err_i   (cpu_i.err),   // bus transfer error
        .i_bus_fence_o (cpu_i.fence), // executed FENCEI operation
        .i_bus_priv_o  (cpu_i.priv),  // current effective privilege level
        /* data bus interface */
        .d_bus_addr_o  (cpu_d.addr),  // bus access address
        .d_bus_rdata_i (cpu_d.rdata), // bus read data
        .d_bus_wdata_o (cpu_d.wdata), // bus write data
        .d_bus_ben_o   (cpu_d.ben),   // byte enable
        .d_bus_we_o    (cpu_d.we),    // write request
        .d_bus_re_o    (cpu_d.re),    // read request
        .d_bus_ack_i   (cpu_d.ack),   // bus transfer acknowledge
        .d_bus_err_i   (cpu_d.err),   // bus transfer error
        .d_bus_fence_o (cpu_d.fence), // executed FENCE operation
        .d_bus_priv_o  (cpu_d.priv),  // current effective privilege level
        /* non-maskable interrupt */
        .msw_irq_i     (msw_irq_i),   // machine software interrupt
        .mext_irq_i    (mext_irq_i),  // machine external interrupt request
        .mtime_irq_i   (mtime_irq),   // machine timer interrupt
        /* fast interrupts (custom) */
        .firq_i        (fast_irq),    // fast interrupt trigger
        /* debug mode (halt) request */
        .db_halt_req_i (dci_halt_req)
    );

    /* misc */
    assign cpu_i.src    = 1'b1; // initialized but unused
    assign cpu_d.src    = 1'b0; // initialized but unused
    assign cpu_i.cached = 1'b0; // initialized but unused
    assign cpu_d.cached = 1'b0; // no data cache available yet

    /* advanced memory control */
    assign fence_o  = cpu_d.fence; // indicates an executed FENCE operation
    assign fencei_o = cpu_i.fence; // indicates an executed FENCEI operation

    /* fast interrupt requests (FIRQs) - triggers are SINGLE-SHOT */
    assign fast_irq[00] = wdt_irq;      // HIGHEST PRIORITY - watchdog
    assign fast_irq[01] = cfs_irq;      // custom functions subsystem
    assign fast_irq[02] = uart0_rx_irq; // primary UART (UART0) RX
    assign fast_irq[03] = uart0_tx_irq; // primary UART (UART0) TX
    assign fast_irq[04] = uart1_rx_irq; // secondary UART (UART1) RX
    assign fast_irq[05] = uart1_tx_irq; // secondary UART (UART1) TX
    assign fast_irq[06] = spi_irq;      // SPI interrupt
    assign fast_irq[07] = twi_irq;      // TWI transfer done
    assign fast_irq[08] = xirq_irq;     // external interrupt controller
    assign fast_irq[09] = neoled_irq;   // NEOLED buffer IRQ
    assign fast_irq[10] = 1'b0;         // reserved
    assign fast_irq[11] = sdi_irq;      // SDI interrupt
    assign fast_irq[12] = gptmr_irq;    // general purpose timer match
    assign fast_irq[13] = onewire_irq;  // ONEWIRE operation done
    assign fast_irq[14] = 1'b0;         // reserved
    assign fast_irq[15] = 1'b0;         // LOWEST PRIORITY - reserved

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                                                                          //                 
    //            ██╗███╗   ██╗███████╗████████╗██████╗ ██╗   ██╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗     ██████╗ █████╗  ██████╗██╗  ██╗███████╗            //
    //            ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║   ██║██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║    ██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝            //
    //            ██║██╔██╗ ██║███████╗   ██║   ██████╔╝██║   ██║██║        ██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██║     ███████║█████╗              //
    //            ██║██║╚██╗██║╚════██║   ██║   ██╔══██╗██║   ██║██║        ██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██║     ██╔══██║██╔══╝              //
    //            ██║██║ ╚████║███████║   ██║   ██║  ██║╚██████╔╝╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║    ╚██████╗██║  ██║╚██████╗██║  ██║███████╗            //
    //            ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝     ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝            //
    //                                                                                                                                                          //              
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CPU Instruction Cache ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (ICACHE_EN == 1'b1) begin : cellrv32_icache_inst_ON
            neorv32_icache #(
                .ICACHE_NUM_BLOCKS (ICACHE_NUM_BLOCKS),   // number of blocks (min 2), has to be a power of 2
                .ICACHE_BLOCK_SIZE (ICACHE_BLOCK_SIZE),   // block size in bytes (min 4), has to be a power of 2
                .ICACHE_NUM_SETS   (ICACHE_ASSOCIATIVITY) // associativity / number of sets (1=direct_mapped), has to be a power of 2
            ) cellrv32_icache_inst (
                /* global control */
                .clk_i        (clk_i),          // global clock, rising edge
                .rstn_i       (rstn_int),       // global reset, low-active, async
                .clear_i      (cpu_i.fence),    // cache clear
                .miss_o       (    ),           // cache miss
                /* host controller interface */
                .host_addr_i  (cpu_i.addr),     // bus access address
                .host_rdata_o (cpu_i.rdata),    // bus read data
                .host_re_i    (cpu_i.re),       // read enable
                .host_ack_o   (cpu_i.ack),      // bus transfer acknowledge
                .host_err_o   (cpu_i.err),      // bus transfer error
                /* peripheral bus interface */
                .bus_cached_o (i_cache.cached), // set if cached (!) access in progress
                .bus_addr_o   (i_cache.addr),   // bus access address
                .bus_rdata_i  (i_cache.rdata),  // bus read data
                .bus_re_o     (i_cache.re),     // read enable
                .bus_ack_i    (i_cache.ack),    // bus transfer acknowledge
                .bus_err_i    (i_cache.err)     // bus transfer error
            );
            //
            assign i_cache.priv = cpu_i.priv;

        end : cellrv32_icache_inst_ON
    endgenerate

    generate
        if (ICACHE_EN == 1'b0) begin : cellrv32_icache_inst_OFF
            assign i_cache.addr   = cpu_i.addr;
            assign cpu_i.rdata    = i_cache.rdata;
            assign i_cache.re     = cpu_i.re;
            assign cpu_i.ack      = i_cache.ack;
            assign cpu_i.err      = i_cache.err;
            assign i_cache.cached = 1'b0; // single transfer (uncached)
            assign i_cache.priv   = cpu_i.priv;
        end : cellrv32_icache_inst_OFF
    endgenerate

    /* yet unused */
    assign i_cache.fence = 1'b0;
    assign i_cache.src   = 1'b0;
    
    // CPU Data Cache ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // <to be define>

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                                         //                      
    //                       ██████╗ ██╗   ██╗███████╗    ███████╗██╗    ██╗██╗████████╗ ██████╗██╗  ██╗                       //
    //                       ██╔══██╗██║   ██║██╔════╝    ██╔════╝██║    ██║██║╚══██╔══╝██╔════╝██║  ██║                       //
    //                       ██████╔╝██║   ██║███████╗    ███████╗██║ █╗ ██║██║   ██║   ██║     ███████║                       //
    //                       ██╔══██╗██║   ██║╚════██║    ╚════██║██║███╗██║██║   ██║   ██║     ██╔══██║                       //
    //                       ██████╔╝╚██████╔╝███████║    ███████║╚███╔███╔╝██║   ██║   ╚██████╗██║  ██║                       //
    //                       ╚═════╝  ╚═════╝ ╚══════╝    ╚══════╝ ╚══╝╚══╝ ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝                       //
    //                                                                                                                         //                          
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CPU Bus Switch ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    neorv32_busswitch #(
        .PORT_CA_READ_ONLY (1'b0), // set if controller port A is read-only
        .PORT_CB_READ_ONLY (1'b1)  // set if controller port B is read-only
    ) cellrv32_busswitch_inst (
        /* global control */
        .clk_i           (clk_i),          // global clock, rising edge
        .rstn_i          (rstn_int),       // global reset, low-active, async
        /* controller interface a */
        .ca_bus_priv_i   (cpu_d.priv),     // current privilege level
        .ca_bus_cached_i (cpu_d.cached),   // set if cached transfer
        .ca_bus_addr_i   (cpu_d.addr),     // bus access address
        .ca_bus_rdata_o  (cpu_d.rdata),    // bus read data
        .ca_bus_wdata_i  (cpu_d.wdata),    // bus write data
        .ca_bus_ben_i    (cpu_d.ben),      // byte enable
        .ca_bus_we_i     (cpu_d.we),       // write enable
        .ca_bus_re_i     (cpu_d.re),       // read enable
        .ca_bus_ack_o    (cpu_d.ack),      // bus transfer acknowledge
        .ca_bus_err_o    (cpu_d.err),      // bus transfer error
        /* controller interface b */
        .cb_bus_priv_i   (i_cache.priv),   // current privilege level
        .cb_bus_cached_i (i_cache.cached), // set if cached transfer
        .cb_bus_addr_i   (i_cache.addr),   // bus access address
        .cb_bus_rdata_o  (i_cache.rdata),  // bus read data
        .cb_bus_wdata_i  ('b0),
        .cb_bus_ben_i    (4'b0000),
        .cb_bus_we_i     (1'b0),
        .cb_bus_re_i     (i_cache.re),     // read enable
        .cb_bus_ack_o    (i_cache.ack),    // bus transfer acknowledge
        .cb_bus_err_o    (i_cache.err),    // bus transfer error
        /* peripheral bus */
        .p_bus_priv_o    (p_bus.priv),     // current privilege level
        .p_bus_cached_o  (p_bus.cached),   // set if cached transfer
        .p_bus_src_o     (p_bus.src),      // access source: 0 = A (data), 1 = B (instructions)
        .p_bus_addr_o    (p_bus.addr),     // bus access address
        .p_bus_rdata_i   (p_bus.rdata),    // bus read data
        .p_bus_wdata_o   (p_bus.wdata),    // bus write data
        .p_bus_ben_o     (p_bus.ben),      // byte enable
        .p_bus_we_o      (p_bus.we),       // write enable
        .p_bus_re_o      (p_bus.re),       // read enable
        .p_bus_ack_i     (p_bus.ack),      // bus transfer acknowledge
        .p_bus_err_i     (bus_error)       // bus transfer error
    );

    /* any fence operation? */
    assign p_bus.fence = cpu_i.fence | cpu_d.fence;

    /* bus response */
    always_comb begin : bus_response
        logic [31:0] rdata_v;
        logic        ack_v;
        logic        err_v;
        //
        rdata_v = '0;
        ack_v   = 1'b0;
        err_v   = 1'b0;
        // OR all response signals: only the module that has actually
        // been accessed is allowed to *set* its bus output signals
        for (int i = 0; i < $size(resp_bus); ++i) begin
            rdata_v = rdata_v | resp_bus[i].rdata; // read data
            ack_v   = ack_v   | resp_bus[i].ack;   // acknowledge
            err_v   = err_v   | resp_bus[i].err;   // error
        end
        p_bus.rdata = rdata_v; // processor bus: CPU transfer data input
        p_bus.ack   = ack_v;   // processor bus: CPU transfer ACK input
        p_bus.err   = err_v;   // processor bus: CPU transfer data bus error input
    end : bus_response

    // Bus Keeper (BUSKEEPER) --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    neorv32_bus_keeper cellrv32_bus_keeper_inst (
        /* host access */
        .clk_i      (clk_i),                          // global clock line
        .rstn_i     (rstn_int),                       // global reset line, low-active, use as async
        .addr_i     (p_bus.addr),                     // address
        .rden_i     (io_rden),                        // read enable
        .wren_i     (io_wren),                        // byte write enable
        .data_i     (p_bus.wdata),                    // data in
        .data_o     (resp_bus[RESP_BUSKEEPER].rdata), // data out
        .ack_o      (resp_bus[RESP_BUSKEEPER].ack),   // transfer acknowledge
        .err_o      (bus_error),                      // transfer error
        /* bus monitoring */
        .bus_addr_i (p_bus.addr),                     // address
        .bus_rden_i (p_bus.re),                       // read enable
        .bus_wren_i (p_bus.we),                       // write enable
        .bus_ack_i  (p_bus.ack),                      // transfer acknowledge from bus system
        .bus_err_i  (p_bus.err),                      // transfer error from bus system
        .bus_tmo_i  (ext_timeout),                    // transfer timeout (external interface)
        .bus_ext_i  (ext_access),                     // external bus access
        .bus_xip_i  (xip_access)                      // pending XIP access
    );

    /* unused, BUSKEEPER issues error to **directly** the CPU */
    assign resp_bus[RESP_BUSKEEPER].err = 1'b0;

    // ****************************************************************************************************************************
    // Memory System
    // ****************************************************************************************************************************

    // Processor-Internal Instruction Memory (IMEM) ----------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if ((MEM_INT_IMEM_EN == 1'b1) && (MEM_INT_IMEM_SIZE > 0)) begin : cellrv32_int_imem_inst_ON
            neorv32_imem #(
                .IMEM_BASE    (imem_base_c),          // memory base address
                .IMEM_SIZE    (MEM_INT_IMEM_SIZE),    // processor-internal instruction memory size in bytes
                .IMEM_AS_IROM (~ INT_BOOTLOADER_EN)   // implement IMEM as pre-initialized read-only memory?
            ) cellrv32_int_imem_inst (
                .clk_i  (clk_i),                     // global clock line
                .rden_i (p_bus.re),                  // read enable
                .wren_i (p_bus.we),                  // write enable
                .ben_i  (p_bus.ben),                 // byte write enable
                .addr_i (p_bus.addr),                // address
                .data_i (p_bus.wdata),               // data in
                .data_o (resp_bus[RESP_IMEM].rdata), // data out
                .ack_o  (resp_bus[RESP_IMEM].ack),   // transfer acknowledge
                .err_o  (resp_bus[RESP_IMEM].err)    // transfer error
            );
        end : cellrv32_int_imem_inst_ON
    endgenerate

    generate
        if ((MEM_INT_IMEM_EN == 1'b0) || (MEM_INT_IMEM_SIZE == 0)) begin : cellrv32_int_imem_inst_OFF
            assign resp_bus[RESP_IMEM] = resp_bus_entry_terminate_c;
        end : cellrv32_int_imem_inst_OFF
    endgenerate

    // Processor-Internal Data Memory (DMEM) -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if ((MEM_INT_DMEM_EN == 1'b1) && (MEM_INT_DMEM_SIZE > 0)) begin : cellrv32_int_dmem_inst_ON
            neorv32_dmem #(
              .DMEM_BASE (dmem_base_c),      // memory base address
              .DMEM_SIZE (MEM_INT_DMEM_SIZE) // processor-internal data memory size in bytes  
            ) cellrv32_int_dmem_inst (
                .clk_i  (clk_i),                     // global clock line
                .rden_i (p_bus.re),                  // read enable
                .wren_i (p_bus.we),                  // write enable
                .ben_i  (p_bus.ben),                 // byte write enable
                .addr_i (p_bus.addr),                // address
                .data_i (p_bus.wdata),               // data in
                .data_o (resp_bus[RESP_DMEM].rdata), // data out
                .ack_o  (resp_bus[RESP_DMEM].ack)    // transfer acknowledge
            );
            // no access error possible
            assign resp_bus[RESP_DMEM].err = 1'b0; 
        end : cellrv32_int_dmem_inst_ON
    endgenerate

    generate
        if ((MEM_INT_DMEM_EN == 1'b0) || (MEM_INT_DMEM_SIZE == 0)) begin : cellrv32_int_dmem_inst_OFF
            assign resp_bus[RESP_DMEM] = resp_bus_entry_terminate_c;
        end : cellrv32_int_dmem_inst_OFF
    endgenerate

    // Processor-Internal Bootloader ROM (BOOTROM) -----------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (INT_BOOTLOADER_EN == 1'b1) begin : cellrv32_boot_rom_inst_ON
            neorv32_boot_rom #(
                .BOOTROM_BASE(boot_rom_base_c)
            ) cellrv32_boot_rom_inst (
                .clk_i(clk_i), // global clock line
                .rden_i(p_bus.re), // read enable
                .wren_i(p_bus.we), // write enable
                .addr_i(p_bus.addr), // address
                .data_o(resp_bus[RESP_BOOTROM].rdata), // data out
                .ack_o(resp_bus[RESP_BOOTROM].ack), // transfer acknowledge
                .err_o(resp_bus[RESP_BOOTROM].err)  // transfer error
            );
        end : cellrv32_boot_rom_inst_ON
    endgenerate

    generate
        if (INT_BOOTLOADER_EN == 1'b0) begin : cellrv32_boot_rom_inst_OFF
            assign resp_bus[RESP_BOOTROM] = resp_bus_entry_terminate_c;
        end : cellrv32_boot_rom_inst_OFF
    endgenerate

    // External Wishbone Gateway (WISHBONE) ---------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (MEM_EXT_EN == 1'b1) begin : cellrv32_wishbone_inst_ON
            neorv32_wishbone #(
                /* Internal instruction memory */
                .MEM_INT_IMEM_EN   (MEM_INT_IMEM_EN),    // implement processor-internal instruction memory
                .MEM_INT_IMEM_SIZE (MEM_INT_IMEM_SIZE),  // size of processor-internal instruction memory in bytes
                /* Internal data memory */
                .MEM_INT_DMEM_EN   (MEM_INT_DMEM_EN),    // implement processor-internal data memory
                .MEM_INT_DMEM_SIZE (MEM_INT_DMEM_SIZE),  // size of processor-internal data memory in bytes
                /* Interface Configuration */
                .BUS_TIMEOUT       (MEM_EXT_TIMEOUT),    // cycles after an UNACKNOWLEDGED bus access triggers a bus fault exception
                .PIPE_MODE         (MEM_EXT_PIPE_MODE),  // protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
                .BIG_ENDIAN        (MEM_EXT_BIG_ENDIAN), // byte order: true=big-endian, false=little-endian
                .ASYNC_RX          (MEM_EXT_ASYNC_RX),   // use register buffer for RX data when false
                .ASYNC_TX          (MEM_EXT_ASYNC_TX)    // use register buffer for TX data when false
            ) cellrv32_wishbone_inst (
                /* global control */
                .clk_i      (clk_i),                         // global clock line
                .rstn_i     (rstn_int),                      // global reset line, low-active, async
                /* host access */
                .src_i      (p_bus.src),                     // access type (0: data, 1:instruction)
                .addr_i     (p_bus.addr),                    // address
                .rden_i     (p_bus.re),                      // read enable
                .wren_i     (p_bus.we),                      // write enable
                .ben_i      (p_bus.ben),                     // byte write enable
                .data_i     (p_bus.wdata),                   // data in
                .data_o     (resp_bus[RESP_WISHBONE].rdata), // data out
                .ack_o      (resp_bus[RESP_WISHBONE].ack),   // transfer acknowledge
                .err_o      (resp_bus[RESP_WISHBONE].err),   // transfer error
                .tmo_o      (ext_timeout),                   // transfer timeout
                .priv_i     (p_bus.priv),                    // current CPU privilege level
                .ext_o      (ext_access),                    // active external access
                /* xip configuration */
                .xip_en_i   (xip_enable),                    // XIP module enabled
                .xip_page_i (xip_page),                      // XIP memory page
                /* wishbone interface */
                .wb_tag_o   (wb_tag_o),                      // request tag
                .wb_adr_o   (wb_adr_o),                      // address
                .wb_dat_i   (wb_dat_i),                      // read data
                .wb_dat_o   (wb_dat_o),                      // write data
                .wb_we_o    (wb_we_o),                       // read/write
                .wb_sel_o   (wb_sel_o),                      // byte enable
                .wb_stb_o   (wb_stb_o),                      // strobe
                .wb_cyc_o   (wb_cyc_o),                      // valid cycle
                .wb_ack_i   (wb_ack_i),                      // transfer acknowledge
                .wb_err_i   (wb_err_i)                       // transfer error
            );
        end : cellrv32_wishbone_inst_ON
    endgenerate

    generate
        if (MEM_EXT_EN == 1'b0) begin : cellrv32_wishbone_inst_OFF
            assign resp_bus[RESP_WISHBONE] = resp_bus_entry_terminate_c;
            assign ext_timeout = 1'b0;
            assign ext_access  = 1'b0;
            //
            assign wb_adr_o = '0;
            assign wb_dat_o = '0;
            assign wb_we_o  = 1'b0;
            assign wb_sel_o = '0;
            assign wb_stb_o = 1'b0;
            assign wb_cyc_o = 1'b0;
            assign wb_tag_o = '0;
        end : cellrv32_wishbone_inst_OFF
    endgenerate

    // Execute In Place Module (XIP) -------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_XIP_EN == 1'b1) begin : cellrv32_xip_inst_ON
            neorv32_xip cellrv32_xip_inst (
                /* global control */
                .clk_i       (clk_i),                        // global clock line
                .rstn_i      (rstn_int),                     // global reset line, low-active, async
                /* host access: control register access port */
                .ct_addr_i   (p_bus.addr),                   // address
                .ct_rden_i   (io_rden),                      // read enable
                .ct_wren_i   (io_wren),                      // write enable
                .ct_data_i   (p_bus.wdata),                  // data in
                .ct_data_o   (resp_bus[RESP_XIP_CT].rdata),  // data out
                .ct_ack_o    (resp_bus[RESP_XIP_CT].ack),    // transfer acknowledge
                /* host access: transparent SPI access port (read-only) */
                .acc_addr_i  (p_bus.addr),                   // address
                .acc_rden_i  (p_bus.re),                     // read enable
                .acc_wren_i  (p_bus.we),                     // write enable
                .acc_data_o  (resp_bus[RESP_XIP_ACC].rdata), // data out
                .acc_ack_o   (resp_bus[RESP_XIP_ACC].ack),   // transfer acknowledge
                .acc_err_o   (resp_bus[RESP_XIP_ACC].err),   // transfer error
                /* status */
                .xip_en_o    (xip_enable),                   // XIP enable
                .xip_acc_o   (xip_access),                   // pending XIP access
                .xip_page_o  (xip_page),                     // XIP page
                /* clock generator */
                .clkgen_en_o (xip_cg_en),                    // enable clock generator
                .clkgen_i    (clk_gen),
                /* SPI device interface */
                .spi_csn_o   (xip_csn_o),                    // chip-select, low-active
                .spi_clk_o   (xip_clk_o),                    // serial clock
                .spi_dat_i   (xip_dat_i),                    // device data output
                .spi_dat_o   (xip_dat_o)                     // controller data output
            );
            // no access error possible
            assign resp_bus[RESP_XIP_CT].err = 1'b0; 
        end : cellrv32_xip_inst_ON
    endgenerate

    generate
        if (IO_XIP_EN == 1'b0) begin : cellrv32_xip_inst_OFF
            assign resp_bus[RESP_XIP_CT]  = resp_bus_entry_terminate_c;
            assign resp_bus[RESP_XIP_ACC] = resp_bus_entry_terminate_c;
            //
            assign xip_enable = 1'b0;
            assign xip_access = 1'b0;
            assign xip_page   = '0;
            assign xip_cg_en  = 1'b0;
            assign xip_csn_o  = 1'b1;
            assign xip_clk_o  = 1'b0;
            assign xip_dat_o  = 1'b0;
        end : cellrv32_xip_inst_OFF
    endgenerate

    // ****************************************************************************************************************************
    // IO/Peripheral Modules
    // ****************************************************************************************************************************

    // IO Access? --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign io_acc  = (p_bus.addr[31 : index_size_f(io_size_c)] == io_base_c[31 : index_size_f(io_size_c)]) ? 1'b1 : 1'b0;
    assign io_rden = ((io_acc == 1'b1) && (p_bus.re == 1'b1) && (p_bus.src == 1'b0))    ? 1'b1 : 1'b0; // PMA: read access only from data interface
    assign io_wren = ((io_acc == 1'b1) && (p_bus.we == 1'b1) && (p_bus.ben == 4'b1111)) ? 1'b1 : 1'b0; // PMA: full-word write accesses only (reduces HW complexity)
    
    // Custom Functions Subsystem (CFS) ----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_CFS_EN == 1'b1) begin : cellrv32_cfs_inst_ON
            neorv32_cfs #(
                .CFS_CONFIG   (IO_CFS_CONFIG),  // custom CFS configuration generic
                .CFS_IN_SIZE  (IO_CFS_IN_SIZE), // size of CFS input conduit in bits
                .CFS_OUT_SIZE (IO_CFS_OUT_SIZE) // size of CFS output conduit in bits
            ) cellrv32_cfs_inst (
                /* host access */
                .clk_i       (clk_i),                    // global clock line
                .rstn_i      (rstn_int),                 // global reset line, low-active, use as async
                .priv_i      (p_bus.priv),               // current CPU privilege mode
                .addr_i      (p_bus.addr),               // address
                .rden_i      (io_rden),                  // read enable
                .wren_i      (io_wren),                  // word write enable
                .data_i      (p_bus.wdata),              // data in
                .data_o      (resp_bus[RESP_CFS].rdata), // data out
                .ack_o       (resp_bus[RESP_CFS].ack),   // transfer acknowledge
                .err_o       (resp_bus[RESP_CFS].err),   // access error
                /* clock generator */
                .clkgen_en_o (cfs_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),                  // "clock" inputs
                /* interrupt */
                .irq_o       (cfs_irq),                  // interrupt request
                /* custom io (conduit) */
                .cfs_in_i    (cfs_in_i),                 // custom inputs
                .cfs_out_o   (cfs_out_o)                 // custom outputs
            );
        end : cellrv32_cfs_inst_ON
    endgenerate

    generate
        if (IO_CFS_EN == 1'b0) begin : cellrv32_cfs_inst_OFF
            assign resp_bus[RESP_CFS] = resp_bus_entry_terminate_c;
            //
            assign cfs_cg_en = 1'b0;
            assign cfs_irq   = 1'b0;
            assign cfs_out_o = '0;
        end : cellrv32_cfs_inst_OFF
    endgenerate
    
    // Serial Data Interface (SDI) ---------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_SDI_EN == 1'b1) begin : cellrv32_sdi_inst_ON
            neorv32_sdi #(
                .RTX_FIFO (IO_SDI_FIFO) // RTX fifo depth, has to be a power of two, min 1
            ) cellrv32_sdi_inst (
                /* host access */
                .clk_i     (clk_i),                    // global clock line
                .rstn_i    (rstn_int),                 // global reset line, low-active, async
                .addr_i    (p_bus.addr),               // address
                .rden_i    (io_rden),                  // read enable
                .wren_i    (io_wren),                  // write enable
                .data_i    (p_bus.wdata),              // data in
                .data_o    (resp_bus[RESP_SDI].rdata), // data out
                .ack_o     (resp_bus[RESP_SDI].ack),   // transfer acknowledge
                /* SDI receiver input */
                .sdi_csn_i (sdi_csn_i),                // low-active chip-select
                .sdi_clk_i (sdi_clk_i),                // serial clock
                .sdi_dat_i (sdi_dat_i),                // serial data input
                .sdi_dat_o (sdi_dat_o),                // serial data output
                /* interrupts */
                .irq_o     (sdi_irq)
            );
            // no access error possible
            assign resp_bus[RESP_SDI].err = 1'b0; 
        end : cellrv32_sdi_inst_ON
    endgenerate

    generate
        if (IO_SDI_EN == 1'b0) begin : cellrv32_sdi_inst_OFF
            assign resp_bus[RESP_SDI] = resp_bus_entry_terminate_c;
            //
            assign sdi_dat_o = 1'b0;
            assign sdi_irq   = 1'b0;
        end : cellrv32_sdi_inst_OFF
    endgenerate

    // General Purpose Input/Output Port (GPIO) --------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_GPIO_NUM > 0) begin : cellrv32_gpio_inst_ON
            neorv32_gpio #(
                .GPIO_NUM (IO_GPIO_NUM) // number of GPIO input/output pairs (0..64)
            ) cellrv32_gpio_inst (
                /* host access */
                .clk_i  (clk_i),                     // global clock line
                .rstn_i (rstn_int),                  // global reset line, low-active, async
                .addr_i (p_bus.addr),                // address
                .rden_i (io_rden),                   // read enable
                .wren_i (io_wren),                   // write enable
                .data_i (p_bus.wdata),               // data in
                .data_o (resp_bus[RESP_GPIO].rdata), // data out
                .ack_o  (resp_bus[RESP_GPIO].ack),   // transfer acknowledge
                /* parallel io */
                .gpio_o (gpio_o),
                .gpio_i (gpio_i)
            );
            // no access error possible
            assign resp_bus[RESP_GPIO].err = 1'b0; 
        end : cellrv32_gpio_inst_ON
    endgenerate

    generate
        if (IO_GPIO_NUM == 0) begin : cellrv32_gpio_inst_OFF
            assign resp_bus[RESP_GPIO] = resp_bus_entry_terminate_c;
            //
            assign gpio_o = '0;
        end : cellrv32_gpio_inst_OFF
    endgenerate

    // Watch Dog Timer (WDT) ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_WDT_EN == 1'b1) begin : cellrv32_wdt_inst_ON
            neorv32_wdt cellrv32_wdt_inst (
                /* host access */
                .clk_i       (clk_i),                    // global clock line
                .rstn_ext_i  (rstn_ext),                 // external reset line, low-active, async
                .rstn_int_i  (rstn_int),                 // internal reset line, low-active, async
                .rden_i      (io_rden),                  // read enable
                .wren_i      (io_wren),                  // write enable
                .addr_i      (p_bus.addr),               // address
                .data_i      (p_bus.wdata),              // data in
                .data_o      (resp_bus[RESP_WDT].rdata), // data out
                .ack_o       (resp_bus[RESP_WDT].ack),   // transfer acknowledge
                /* CPU status */
                .cpu_debug_i (cpu_s.debug),              // CPU is in debug mode
                .cpu_sleep_i (cpu_s.sleep),              // CPU is in sleep mode
                /* clock generator */
                .clkgen_en_o (wdt_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* timeout event */
                .irq_o       (wdt_irq),                  // timeout IRQ
                .rstn_o      (rstn_wdt)                  // timeout reset, low_active, sync
            );
            // no access error possible
            assign resp_bus[RESP_WDT].err = 1'b0; 
        end : cellrv32_wdt_inst_ON
    endgenerate

    generate
        if (IO_WDT_EN == 1'b0) begin : cellrv32_wdt_inst_OFF
            assign resp_bus[RESP_WDT] = resp_bus_entry_terminate_c;
            //
            assign wdt_irq   = 1'b0;
            assign rstn_wdt  = 1'b1;
            assign wdt_cg_en = 1'b0;
        end : cellrv32_wdt_inst_OFF
    endgenerate

    // Machine System Timer (MTIME) --------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_MTIME_EN == 1'b1) begin : cellrv32_mtime_inst_ON
            neorv32_mtime cellrv32_mtime_inst (
                /* host access */
                .clk_i  (clk_i),                      // global clock line
                .rstn_i (rstn_int),                   // global reset line, low-active, async
                .addr_i (p_bus.addr),                 // address
                .rden_i (io_rden),                    // read enable
                .wren_i (io_wren),                    // write enable
                .data_i (p_bus.wdata),                // data in
                .data_o (resp_bus[RESP_MTIME].rdata), // data out
                .ack_o  (resp_bus[RESP_MTIME].ack),   // transfer acknowledge
                /* interrupt */
                .irq_o  (mtime_irq)                   // interrupt request
            );
            // no access error possible
            assign resp_bus[RESP_MTIME].err = 1'b0; 
        end : cellrv32_mtime_inst_ON
    endgenerate

    generate
        if (IO_MTIME_EN == 1'b0) begin : cellrv32_mtime_inst_OFF
            assign resp_bus[RESP_MTIME] = resp_bus_entry_terminate_c;
            //
            assign mtime_irq = mtime_irq_i; // use external machine timer interrupt
        end : cellrv32_mtime_inst_OFF
    endgenerate

    // Primary Universal Asynchronous Receiver/Transmitter (UART0) -------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_UART0_EN == 1'b1) begin : cellrv32_uart0_inst_ON
            neorv32_uart #(
                .UART_PRIMARY (1'b1),             // true = primary UART (UART0), false = secondary UART (UART1)
                .UART_RX_FIFO (IO_UART0_RX_FIFO), // RX fifo depth, has to be a power of two, min 1
                .UART_TX_FIFO (IO_UART0_TX_FIFO)  // TX fifo depth, has to be a power of two, min 1
            ) cellrv32_uart0_inst (
                /* host access */
                .clk_i       (clk_i),                      // global clock line
                .rstn_i      (rstn_int),                   // global reset line, low-active, async
                .addr_i      (p_bus.addr),                 // address
                .rden_i      (io_rden),                    // read enable
                .wren_i      (io_wren),                    // write enable
                .data_i      (p_bus.wdata),                // data in
                .data_o      (resp_bus[RESP_UART0].rdata), // data out
                .ack_o       (resp_bus[RESP_UART0].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (uart0_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* com lines */
                .uart_txd_o  (uart0_txd_o),
                .uart_rxd_i  (uart0_rxd_i),
                /* hardware flow control */
                .uart_rts_o  (uart0_rts_o),                // UART.RX ready to receive ("RTR"), low-active, optional
                .uart_cts_i  (uart0_cts_i),                // UART.TX allowed to transmit, low-active, optional
                /* interrupts */
                .irq_rx_o    (uart0_rx_irq),               // rx interrupt
                .irq_tx_o    (uart0_tx_irq)                // tx interrupt
            );
            // no access error possible
            assign resp_bus[RESP_UART0].err = 1'b0; 
        end : cellrv32_uart0_inst_ON
    endgenerate

    generate
        if (IO_UART0_EN == 1'b0) begin : cellrv32_uart0_inst_OFF
            assign resp_bus[RESP_UART0] = resp_bus_entry_terminate_c;
            //
            assign uart0_txd_o  = 1'b0;
            assign uart0_rts_o  = 1'b1;
            assign uart0_cg_en  = 1'b0;
            assign uart0_rx_irq = 1'b0;
            assign uart0_tx_irq = 1'b0;
        end : cellrv32_uart0_inst_OFF
    endgenerate

    // Secondary Universal Asynchronous Receiver/Transmitter (UART1) -----------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_UART1_EN == 1'b1) begin : cellrv32_uart1_inst_ON
            neorv32_uart #(
                .UART_PRIMARY (1'b0),             // true = primary UART (UART0), false = secondary UART (UART1)
                .UART_RX_FIFO (IO_UART1_RX_FIFO), // RX fifo depth, has to be a power of two, min 1
                .UART_TX_FIFO (IO_UART1_TX_FIFO)  // TX fifo depth, has to be a power of two, min 1
            ) cellrv32_uart1_inst (
                /* host access */
                .clk_i       (clk_i),                      // global clock line
                .rstn_i      (rstn_int),                   // global reset line, low-active, async
                .addr_i      (p_bus.addr),                 // address
                .rden_i      (io_rden),                    // read enable
                .wren_i      (io_wren),                    // write enable
                .data_i      (p_bus.wdata),                // data in
                .data_o      (resp_bus[RESP_UART1].rdata), // data out
                .ack_o       (resp_bus[RESP_UART1].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (uart1_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* com lines */
                .uart_txd_o  (uart1_txd_o),
                .uart_rxd_i  (uart1_rxd_i),
                /* hardware flow control */
                .uart_rts_o  (uart1_rts_o),                // UART.RX ready to receive ("RTR"), low-active, optional
                .uart_cts_i  (uart1_cts_i),                // UART.TX allowed to transmit, low-active, optional
                /* interrupts */
                .irq_rx_o    (uart1_rx_irq),               // rx interrupt
                .irq_tx_o    (uart1_tx_irq)                // tx interrupt
            );
            // no access error possible
            assign resp_bus[RESP_UART1].err = 1'b0; 
        end : cellrv32_uart1_inst_ON
    endgenerate

    generate
        if (IO_UART1_EN == 1'b0) begin : cellrv32_uart1_inst_OFF
            assign resp_bus[RESP_UART1] = resp_bus_entry_terminate_c;
            //
            assign uart1_txd_o  = 1'b0;
            assign uart1_rts_o  = 1'b1;
            assign uart1_cg_en  = 1'b0;
            assign uart1_rx_irq = 1'b0;
            assign uart1_tx_irq = 1'b0;
        end : cellrv32_uart1_inst_OFF
    endgenerate

    // Serial Peripheral Interface (SPI) ---------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_SPI_EN == 1'b1) begin : cellrv32_spi_inst_ON
            neorv32_spi #(
                .IO_SPI_FIFO (IO_SPI_FIFO) // SPI RTX fifo depth, has to be a power of two, min 1
            ) cellrv32_spi_inst (
                /* host access */
                .clk_i       (clk_i),                    // global clock line
                .rstn_i      (rstn_int),                 // global reset line, low-active, async
                .addr_i      (p_bus.addr),               // address
                .rden_i      (io_rden),                  // read enable
                .wren_i      (io_wren),                  // write enable
                .data_i      (p_bus.wdata),              // data in
                .data_o      (resp_bus[RESP_SPI].rdata), // data out
                .ack_o       (resp_bus[RESP_SPI].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (spi_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* com lines */
                .spi_clk_o   (spi_clk_o),                // SPI serial clock
                .spi_dat_o   (spi_dat_o),                // controller data out, peripheral data in
                .spi_dat_i   (spi_dat_i),                // controller data in, peripheral data out
                .spi_csn_o   (spi_csn_o),                // SPI CS
                /* interrupt */
                .irq_o       (spi_irq)                   // transmission done interrupt
            );
            // no access error possible
            assign resp_bus[RESP_SPI].err = 1'b0; 
        end : cellrv32_spi_inst_ON
    endgenerate

    generate
        if (IO_SPI_EN == 1'b0) begin : cellrv32_spi_inst_OFF
            assign resp_bus[RESP_SPI] = resp_bus_entry_terminate_c;
            //
            assign spi_clk_o = 1'b0;
            assign spi_dat_o = 1'b0;
            assign spi_csn_o = '1; // CS lines are low-active
            assign spi_cg_en = 1'b0;
            assign spi_irq   = 1'b0;
        end : cellrv32_spi_inst_OFF
    endgenerate

    // Two-Wire Interface (TWI) ------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_TWI_EN == 1'b1) begin : cellrv32_twi_inst_ON
            neorv32_twi cellrv32_twi_inst (
                /* host access */
                .clk_i       (clk_i),                    // global clock line
                .rstn_i      (rstn_int),                 // global reset line, low-active, async
                .addr_i      (p_bus.addr),               // address
                .rden_i      (io_rden),                  // read enable
                .wren_i      (io_wren),                  // write enable
                .data_i      (p_bus.wdata),              // data in
                .data_o      (resp_bus[RESP_TWI].rdata), // data out
                .ack_o       (resp_bus[RESP_TWI].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (twi_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* com lines (require external tri-state drivers) */
                .twi_sda_i   (twi_sda_i),                // serial data line input
                .twi_sda_o   (twi_sda_o),                // serial data line output
                .twi_scl_i   (twi_scl_i),                // serial clock line input
                .twi_scl_o   (twi_scl_o),                // serial clock line output
                /* interrupt */
                .irq_o       (twi_irq)                   // transfer done IRQ
            );
            // no access error possible
            assign resp_bus[RESP_TWI].err = 1'b0; 
        end : cellrv32_twi_inst_ON
    endgenerate

    generate
        if (IO_TWI_EN == 1'b0) begin : cellrv32_twi_inst_OFF
            assign resp_bus[RESP_TWI] = resp_bus_entry_terminate_c;
            //
            assign twi_sda_o = 1'b1;
            assign twi_scl_o = 1'b1;
            assign twi_cg_en = 1'b0;
            assign twi_irq   = 1'b0;
        end : cellrv32_twi_inst_OFF
    endgenerate

    // Pulse-Width Modulation Controller (PWM) ---------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_PWM_NUM_CH > 0) begin : cellrv32_pwm_inst_ON
            neorv32_pwm #(
                .NUM_CHANNELS (IO_PWM_NUM_CH) // number of PWM channels (0..12)
            ) cellrv32_pwm_inst (
                /* host access */
                .clk_i       (clk_i),                    // global clock line
                .rstn_i      (rstn_int),                 // global reset line, low-active, async
                .addr_i      (p_bus.addr),               // address
                .rden_i      (io_rden),                  // read enable
                .wren_i      (io_wren),                  // write enable
                .data_i      (p_bus.wdata),              // data in
                .data_o      (resp_bus[RESP_PWM].rdata), // data out
                .ack_o       (resp_bus[RESP_PWM].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (pwm_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* pwm output channels */
                .pwm_o       (pwm_o)
            );
            // no access error possible
            assign resp_bus[RESP_PWM].err = 1'b0; 
        end : cellrv32_pwm_inst_ON
    endgenerate

    generate
        if (IO_PWM_NUM_CH == 0) begin : cellrv32_pwm_inst_OFF
            assign resp_bus[RESP_PWM] = resp_bus_entry_terminate_c;
            //
            assign pwm_cg_en = 1'b0;
            assign pwm_o     = '0;
        end : cellrv32_pwm_inst_OFF
    endgenerate

    // True Random Number Generator (TRNG) ----------------------------------------------------
    // -------------------------------------------------------------------------------------------
 
    generate
        if (IO_TRNG_EN == 1'b1) begin : cellrv32_trng_inst_ON
            neorv32_trng #(
                .IO_TRNG_FIFO (IO_TRNG_FIFO) // RND fifo depth, has to be a power of two, min 1
            ) cellrv32_trng_inst (
                /* host access */
                .clk_i  (clk_i),                     // global clock line
                .rstn_i (rstn_int),                  // global reset line, low-active, async
                .addr_i (p_bus.addr),                // address
                .rden_i (io_rden),                   // read enable
                .wren_i (io_wren),                   // write enable
                .data_i (p_bus.wdata),               // data in
                .data_o (resp_bus[RESP_TRNG].rdata), // data out
                .ack_o  (resp_bus[RESP_TRNG].ack)    // transfer acknowledge
            );
            // no access error possible
            assign resp_bus[RESP_TRNG].err = 1'b0; 
        end : cellrv32_trng_inst_ON
    endgenerate

    generate
        if (IO_TRNG_EN == 1'b0) begin : cellrv32_trng_inst_OFF
            assign resp_bus[RESP_TRNG] = resp_bus_entry_terminate_c;
        end : cellrv32_trng_inst_OFF
    endgenerate

    // Smart LED (WS2811/WS2812) Interface (NEOLED) ----------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_NEOLED_EN == 1'b1) begin : cellrv32_neoled_inst_ON
            neorv32_neoled #(
                .FIFO_DEPTH (IO_NEOLED_TX_FIFO) // NEOLED FIFO depth, has to be a power of two, min 1
            ) cellrv32_neoled_inst (
                /* host access */
                .clk_i       (clk_i),                       // global clock line
                .rstn_i      (rstn_int),                    // global reset line, low-active, async
                .addr_i      (p_bus.addr),                  // address
                .rden_i      (io_rden),                     // read enable
                .wren_i      (io_wren),                     // write enable
                .data_i      (p_bus.wdata),                 // data in
                .data_o      (resp_bus[RESP_NEOLED].rdata), // data out
                .ack_o       (resp_bus[RESP_NEOLED].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (neoled_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* interrupt */
                .irq_o       (neoled_irq),                  // interrupt request
                /* NEOLED output */
                .neoled_o    (neoled_o)                     // serial async data line
            );
            // no access error possible
            assign resp_bus[RESP_NEOLED].err = 1'b0; 
        end : cellrv32_neoled_inst_ON
    endgenerate

    generate
        if (IO_NEOLED_EN == 1'b0) begin : cellrv32_neoled_inst_OFF
            assign resp_bus[RESP_NEOLED] = resp_bus_entry_terminate_c;
            //
            assign neoled_cg_en = 1'b0;
            assign neoled_irq   = 1'b0;
            assign neoled_o     = 1'b0;
        end : cellrv32_neoled_inst_OFF
    endgenerate

    // External Interrupt Controller (XIRQ) ------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (XIRQ_NUM_CH > 0) begin : cellrv32_xirq_inst_ON
            neorv32_xirq #(
                .XIRQ_NUM_CH           (XIRQ_NUM_CH),          // number of external IRQ channels (0..32)
                .XIRQ_TRIGGER_TYPE     (XIRQ_TRIGGER_TYPE),    // trigger type: 0=level, 1=edge
                .XIRQ_TRIGGER_POLARITY (XIRQ_TRIGGER_POLARITY) // trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge
            ) cellrv32_xirq_inst (
                /* host access */
                .clk_i     (clk_i),                     // global clock line
                .rstn_i    (rstn_int),                  // global reset line, low-active, async
                .addr_i    (p_bus.addr),                // address
                .rden_i    (io_rden),                   // read enable
                .wren_i    (io_wren),                   // write enable
                .data_i    (p_bus.wdata),               // data in
                .data_o    (resp_bus[RESP_XIRQ].rdata), // data out
                .ack_o     (resp_bus[RESP_XIRQ].ack),   // transfer acknowledge
                /* external interrupt lines */
                .xirq_i    (xirq_i),
                /* CPU interrupt */
                .cpu_irq_o (xirq_irq)
            );
            // no access error possible
            assign resp_bus[RESP_XIRQ].err = 1'b0; 
        end : cellrv32_xirq_inst_ON
    endgenerate

    generate
        if (XIRQ_NUM_CH == 1'b0) begin : cellrv32_xirq_inst_OFF
             assign resp_bus[RESP_XIRQ] = resp_bus_entry_terminate_c;
             //
             assign xirq_irq = 1'b0;
        end : cellrv32_xirq_inst_OFF
    endgenerate

    // General Purpose Timer (GPTMR) -------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_GPTMR_EN == 1'b1) begin : cellrv32_gptmr_inst_ON
            neorv32_gptmr cellrv32_gptmr_inst (
                /* host access */
                .clk_i       (clk_i),                      // global clock line
                .rstn_i      (rstn_int),                   // global reset line, low-active, async
                .addr_i      (p_bus.addr),                 // address
                .rden_i      (io_rden),                    // read enable
                .wren_i      (io_wren),                    // write enable
                .data_i      (p_bus.wdata),                // data in
                .data_o      (resp_bus[RESP_GPTMR].rdata), // data out
                .ack_o       (resp_bus[RESP_GPTMR].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (gptmr_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* interrupt */
                .irq_o       (gptmr_irq)                   // timer match interrupt
            );
            // no access error possible
            assign resp_bus[RESP_GPTMR].err = 1'b0; 
        end : cellrv32_gptmr_inst_ON
    endgenerate

    generate
        if (IO_GPTMR_EN == 1'b0) begin : cellrv32_gptmr_inst_OFF
            assign resp_bus[RESP_GPTMR] = resp_bus_entry_terminate_c;
            //
            assign gptmr_cg_en = 1'b0;
            assign gptmr_irq   = 1'b0;
        end : cellrv32_gptmr_inst_OFF
    endgenerate

    // 1-Wire Interface Controller (ONEWIRE) -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IO_ONEWIRE_EN == 1'b1) begin : cellrv32_onewire_inst_ON
            neorv32_onewire cellrv32_onewire_inst (
                /* host access */
                .clk_i       (clk_i),                        // global clock line
                .rstn_i      (rstn_int),                     // global reset line, low-active, async
                .addr_i      (p_bus.addr),                   // address
                .rden_i      (io_rden),                      // read enable
                .wren_i      (io_wren),                      // write enable
                .data_i      (p_bus.wdata),                  // data in
                .data_o      (resp_bus[RESP_ONEWIRE].rdata), // data out
                .ack_o       (resp_bus[RESP_ONEWIRE].ack),   // transfer acknowledge
                /* clock generator */
                .clkgen_en_o (onewire_cg_en),                // enable clock generator
                .clkgen_i    (clk_gen),
                /* com lines (require external tri-state drivers) */
                .onewire_i   (onewire_i),                    // 1-wire line state
                .onewire_o   (onewire_o),                    // 1-wire line pull-down
                /* interrupt */
                .irq_o       (onewire_irq)                   // transfer done IRQ
            );
            // no access error possible
            assign resp_bus[RESP_ONEWIRE].err = 1'b0; 
        end : cellrv32_onewire_inst_ON
    endgenerate

    generate
        if (IO_ONEWIRE_EN == 1'b0) begin : cellrv32_onewire_inst_OFF
            assign resp_bus[RESP_ONEWIRE] = resp_bus_entry_terminate_c;
            //
            assign onewire_o     = 1'b1;
            assign onewire_cg_en = 1'b0;
            assign onewire_irq   = 1'b0;
        end : cellrv32_onewire_inst_OFF
    endgenerate

    // System Configuration Information Memory (SYSINFO) -----------------------------------------
    // -------------------------------------------------------------------------------------------
    neorv32_sysinfo #(
        /* General */
        .CLOCK_FREQUENCY      (CLOCK_FREQUENCY),      // clock frequency of clk_i in Hz
        .CUSTOM_ID            (CUSTOM_ID),            // custom user-defined ID
        .INT_BOOTLOADER_EN    (INT_BOOTLOADER_EN),    // implement processor-internal bootloader?
        /* Physical memory protection (PMP) */
        .PMP_NUM_REGIONS      (PMP_NUM_REGIONS),      // number of regions (0..16)
        /* internal Instruction memory */
        .MEM_INT_IMEM_EN      (MEM_INT_IMEM_EN),      // implement processor-internal instruction memory
        .MEM_INT_IMEM_SIZE    (MEM_INT_IMEM_SIZE),    // size of processor-internal instruction memory in bytes
        /* Internal Data memory */
        .MEM_INT_DMEM_EN      (MEM_INT_DMEM_EN),      // implement processor-internal data memory
        .MEM_INT_DMEM_SIZE    (MEM_INT_DMEM_SIZE),    // size of processor-internal data memory in bytes
        /* Internal Cache memory */
        .ICACHE_EN            (ICACHE_EN),            // implement instruction cache
        .ICACHE_NUM_BLOCKS    (ICACHE_NUM_BLOCKS),    // i-cache: number of blocks (min 2), has to be a power of 2
        .ICACHE_BLOCK_SIZE    (ICACHE_BLOCK_SIZE),    // i-cache: block size in bytes (min 4), has to be a power of 2
        .ICACHE_ASSOCIATIVITY (ICACHE_ASSOCIATIVITY), // i-cache: associativity (min 1), has to be a power 2
        /* External memory interface */
        .MEM_EXT_EN           (MEM_EXT_EN),           // implement external memory bus interface?
        .MEM_EXT_BIG_ENDIAN   (MEM_EXT_BIG_ENDIAN),   // byte order: true=big-endian, false=little-endian
        /* On-Chip Debugger */
        .ON_CHIP_DEBUGGER_EN  (ON_CHIP_DEBUGGER_EN),  // implement OCD?
        /* Processor peripherals */
        .IO_GPIO_NUM          (IO_GPIO_NUM),          // number of GPIO input/output pairs (0..64)
        .IO_MTIME_EN          (IO_MTIME_EN),          // implement machine system timer (MTIME)?
        .IO_UART0_EN          (IO_UART0_EN),          // implement primary universal asynchronous receiver/transmitter (UART0)?
        .IO_UART1_EN          (IO_UART1_EN),          // implement secondary universal asynchronous receiver/transmitter (UART1)?
        .IO_SPI_EN            (IO_SPI_EN),            // implement serial peripheral interface (SPI)?
        .IO_SDI_EN            (IO_SDI_EN),            // implement serial data interface (SDI)?
        .IO_TWI_EN            (IO_TWI_EN),            // implement two-wire interface (TWI)?
        .IO_PWM_NUM_CH        (IO_PWM_NUM_CH),        // number of PWM channels to implement
        .IO_WDT_EN            (IO_WDT_EN),            // implement watch dog timer (WDT)?
        .IO_TRNG_EN           (IO_TRNG_EN),           // implement true random number generator (TRNG)?
        .IO_CFS_EN            (IO_CFS_EN),            // implement custom functions subsystem (CFS)?
        .IO_NEOLED_EN         (IO_NEOLED_EN),         // implement NeoPixel-compatible smart LED interface (NEOLED)?
        .IO_XIRQ_NUM_CH       (XIRQ_NUM_CH),          // number of external interrupt (XIRQ) channels to implement
        .IO_GPTMR_EN          (IO_GPTMR_EN),          // implement general purpose timer (GPTMR)?
        .IO_XIP_EN            (IO_XIP_EN),            // implement execute in place module (XIP)?
        .IO_ONEWIRE_EN        (IO_ONEWIRE_EN)         // implement 1-wire interface (ONEWIRE)?
    ) cellrv32_sysinfo_inst (
        /* host access */
        .clk_i  (clk_i),                        // global clock line
        .addr_i (p_bus.addr),                   // address
        .rden_i (io_rden),                      // read enable
        .wren_i (io_wren),                      // write enable
        .data_o (resp_bus[RESP_SYSINFO].rdata), // data out
        .ack_o  (resp_bus[RESP_SYSINFO].ack),   // transfer acknowledge
        .err_o  (resp_bus[RESP_SYSINFO].err)    // transfer error
    );

    // ****************************************************************************************************************************
    // On-Chip Debugger Complex
    // ****************************************************************************************************************************
    generate
        if (ON_CHIP_DEBUGGER_EN == 1'b1) begin : cellv32_ocd_inst_ON
            // On-Chip Debugger - Debug Module (DM) ------------------------------------------------------
            // -------------------------------------------------------------------------------------------
            neorv32_debug_dm cellrv32_debug_dm_inst (
                /* global control */
                .clk_i             (clk_i),                    // global clock line
                .rstn_i            (rstn_ext),                 // external reset, low-active
                /* debug module interface (DMI) */
                .dmi_req_valid_i   (dmi.req_valid),
                .dmi_req_ready_o   (dmi.req_ready),
                .dmi_req_address_i (dmi.req_address),
                .dmi_req_data_i    (dmi.req_data),
                .dmi_req_op_i      (dmi.req_op),
                .dmi_rsp_valid_o   (dmi.rsp_valid),
                .dmi_rsp_ready_i   (dmi.rsp_ready),
                .dmi_rsp_data_o    (dmi.rsp_data),
                .dmi_rsp_op_o      (dmi.rsp_op),
                /* CPU bus access */
                .cpu_debug_i       (cpu_s.debug),              // CPU is in debug mode
                .cpu_addr_i        (p_bus.addr),               // address
                .cpu_rden_i        (p_bus.re),                 // read enable
                .cpu_wren_i        (p_bus.we),                 // write enable
                .cpu_ben_i         (p_bus.ben),                // byte write enable
                .cpu_data_i        (p_bus.wdata),              // data in
                .cpu_data_o        (resp_bus[RESP_OCD].rdata), // data out
                .cpu_ack_o         (resp_bus[RESP_OCD].ack),   // transfer acknowledge
                /* CPU control */
                .cpu_ndmrstn_o     (dci_ndmrstn),              // soc reset
                .cpu_halt_req_o    (dci_halt_req)              // request hart to halt (enter debug mode)
            );
            // no access error possible
            assign resp_bus[RESP_OCD].err = 1'b0; 

            // On-Chip Debugger - Debug Transport Module (DTM) -------------------------------------------
            // -------------------------------------------------------------------------------------------
            neorv32_debug_dtm #(
                .IDCODE_VERSION (jtag_tap_idcode_version_c), // version
                .IDCODE_PARTID  (jtag_tap_idcode_partid_c),  // part number
                .IDCODE_MANID   (jtag_tap_idcode_manid_c)    // manufacturer id
            ) cellrv32_debug_dtm_inst (
                /* global control */
                .clk_i             (clk_i),    // global clock line
                .rstn_i            (rstn_ext), // external reset, low-active
                /* jtag connection */
                .jtag_trst_i       (jtag_trst_i),
                .jtag_tck_i        (jtag_tck_i),
                .jtag_tdi_i        (jtag_tdi_i),
                .jtag_tdo_o        (jtag_tdo_o),
                .jtag_tms_i        (jtag_tms_i),
                /* debug module interface (DMI) */
                .dmi_req_valid_o   (dmi.req_valid),
                .dmi_req_ready_i   (dmi.req_ready),
                .dmi_req_address_o (dmi.req_address),
                .dmi_req_data_o    (dmi.req_data),
                .dmi_req_op_o      (dmi.req_op),
                .dmi_rsp_valid_i   (dmi.rsp_valid),
                .dmi_rsp_ready_o   (dmi.rsp_ready),
                .dmi_rsp_data_i    (dmi.rsp_data),
                .dmi_rsp_op_i      (dmi.rsp_op)
            );
        end : cellv32_ocd_inst_ON
    endgenerate

    generate
        if (ON_CHIP_DEBUGGER_EN == 1'b0) begin : cellv32_ocd_inst_OFF
            assign jtag_tdo_o         = jtag_tdi_i; // JTAG feed-through
            assign resp_bus[RESP_OCD] = resp_bus_entry_terminate_c;
            assign dci_ndmrstn        = 1'b1;
            assign dci_halt_req       = 1'b0;
        end : cellv32_ocd_inst_OFF
    endgenerate
    
    /* DFT signal compute */
endmodule