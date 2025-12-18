// ##################################################################################################
// # << CELLRV32 - CPU Top Entity >>                                                                #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu #(
    /* General */
    parameter int   HW_THREAD_ID        = 0, // hardware thread id (32-bit)
    parameter int   CPU_BOOT_ADDR       = 0, // cpu boot address
    parameter int   CPU_DEBUG_PARK_ADDR = 0, // cpu debug mode parking loop entry address
    parameter int   CPU_DEBUG_EXC_ADDR  = 0, // cpu debug mode exception entry address
    /* RISC-V CPU Extensions */
    parameter logic CPU_EXTENSION_RISCV_B = 1'b0,        // implement bit-manipulation extension?
    parameter logic CPU_EXTENSION_RISCV_C = 1'b0,        // implement compressed extension?
    parameter logic CPU_EXTENSION_RISCV_E = 1'b0,        // implement embedded RF extension?
    parameter logic CPU_EXTENSION_RISCV_M = 1'b0,        // implement mul/div extension?
    parameter logic CPU_EXTENSION_RISCV_U = 1'b0,        // implement user mode extension?
    parameter logic CPU_EXTENSION_RISCV_V = 1'b0,        // implement vector extension?
    parameter logic CPU_EXTENSION_RISCV_Zfinx = 1'b0,    // implement 32-bit floating-point extension (using INT reg!)
    parameter logic CPU_EXTENSION_RISCV_Zhinx = 1'b0,    // implement 16-bit floating-point extension (using INT reg!)
    parameter logic CPU_EXTENSION_RISCV_Zicsr = 1'b0,    // implement CSR system?
    parameter logic CPU_EXTENSION_RISCV_Zicntr = 1'b0,   // implement base counters?
    parameter logic CPU_EXTENSION_RISCV_Zicond = 1'b0,   // implement conditional operations extension?
    parameter logic CPU_EXTENSION_RISCV_Zihpm = 1'b0,    // implement hardware performance monitors?
    parameter logic CPU_EXTENSION_RISCV_Zifencei = 1'b0, // implement instruction stream sync.?
    parameter logic CPU_EXTENSION_RISCV_Zmmul = 1'b0,    // implement multiply-only M sub-extension?
    parameter logic CPU_EXTENSION_RISCV_Zxcfu = 1'b0,    // implement custom (instr.) functions unit?
    parameter logic CPU_EXTENSION_RISCV_Sdext = 1'b0,    // implement external debug mode extension?
    parameter logic CPU_EXTENSION_RISCV_Sdtrig = 1'b0,   // implement trigger module extension?
    /* Extension Options */
    parameter logic FAST_MUL_EN = 1'b0,                  // use DSPs for M extension's multiplier
    parameter logic FAST_SHIFT_EN = 1'b0,                // use barrel shifter for shift operations
    parameter int   CPU_IPB_ENTRIES = 1,                 // entries in instruction prefetch buffer, has to be a power of 2, min 1
    parameter int   VLEN = 256,                          // max size of element vector
    parameter int   ELEN = 32,                           // size of vector register
    /* Physical Memory Protection (PMP) */
    parameter int PMP_NUM_REGIONS = 0,               // number of regions (0..16)
    parameter int PMP_MIN_GRANULARITY = 4,           // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
    /* Hardware Performance Monitors (HPM) */
    parameter int HPM_NUM_CNTS = 0,                  // number of implemented HPM counters (0..29)
    parameter int HPM_CNT_WIDTH = 0                  // total size of HPM counters (0..64)
) (
    /* global control */
    input  logic clk_i,                // global clock, rising edge
    input  logic rstn_i,               // global reset, low-active, async
    output logic sleep_o,              // cpu is in sleep mode when set
    output logic debug_o,              // cpu is in debug mode when set
    /* instruction bus interface */
    output logic [31:0] i_bus_addr_o,  // bus access address
    input  logic [31:0] i_bus_rdata_i, // bus read data
    output logic i_bus_re_o,           // read request
    input  logic i_bus_ack_i,          // bus transfer acknowledge
    input  logic i_bus_err_i,          // bus transfer error
    output logic i_bus_fence_o,        // executed FENCEI operation
    output logic i_bus_priv_o,         // current effective privilege level
    /* data bus interface */
    output logic [31:0] d_bus_addr_o , // bus access address
    input  logic [31:0] d_bus_rdata_i, // bus read data
    output logic [31:0] d_bus_wdata_o, // bus write data
    output logic [03:0] d_bus_ben_o,   // byte enable
    output logic d_bus_we_o,           // write request
    output logic d_bus_re_o,           // read request
    input  logic d_bus_ack_i,          // bus transfer acknowledge
    input  logic d_bus_err_i,          // bus transfer error
    output logic d_bus_fence_o,        // executed FENCE operation
    output logic d_bus_priv_o,         // current effective privilege level
    output logic d_bus_multi_en_o,     // multi-cycle access in progress
    input  logic d_bus_multi_rsp_i,    // multi-cycle access response valid
    output logic [03:0] d_bus_req_ticket_o,   // data bus access request ticket
    input  logic [03:0] d_bus_resp_ticket_i,  // data bus access response ticket
    /* interrupts (risc-v compliant) */
    input logic msw_irq_i,   // machine software interrupt
    input logic mext_irq_i,  // machine external interrupt
    input logic mtime_irq_i, // machine timer interrupt
    /* fast interrupts (custom) */
    input logic [15:0] firq_i,
    /* debug mode (halt) request */
    input logic db_halt_req_i
);
    // RV64: WORK IN PROGRESS -----------------------------------------------------------------------
    // not available as CPU generic as rv64 ISA extension is not (fully) supported yet!
    localparam int XLEN = 32; // data path width
    // ----------------------------------------------------------------------------------------------

    /* local constants: additional register file read ports */
    localparam logic regfile_rs3_en_c = CPU_EXTENSION_RISCV_Zxcfu | CPU_EXTENSION_RISCV_Zfinx; // 3rd register file read port (rs3)
    localparam logic regfile_rs4_en_c = CPU_EXTENSION_RISCV_Zxcfu; // 4th register file read port (rs4)

    /* local constant: instruction prefetch buffer depth */
    localparam logic ipb_override_c = (CPU_EXTENSION_RISCV_C == 1) & (CPU_IPB_ENTRIES < 2); // override IPB size: set to 2?
    localparam int   ipb_depth_c    = cond_sel_natural_f(ipb_override_c, 2, CPU_IPB_ENTRIES);

    /* local signals */
    ctrl_bus_t ctrl; // main control bus
    logic [XLEN-1:0] imm;     // immediate
    logic [XLEN-1:0] rs1;     // source register 1
    logic [XLEN-1:0] rs2;     // source register 2
    logic [XLEN-1:0] rs3;     // source register 3
    logic [XLEN-1:0] rs4;     // source register 4
    logic [XLEN-1:0] alu_res; // alu result
    logic [XLEN-1:0] alu_add; // alu address result
    logic [1:0]      alu_cmp; // comparator result
    logic [XLEN-1:0] mem_rdata;  // memory read data
    logic  cp_done;              // ALU co-prefetch operation done
    logic  alu_exc;              // ALU exception
    logic  bus_d_wait;           // wait for current bus data access
    logic  [XLEN-1:0] csr_rdata; // csr read data
    logic  [XLEN-1:0] mar;       // current memory address register
    logic  ma_load;              // misaligned load data address
    logic  ma_store;             // misaligned store data address
    logic  be_load;              // bus error on load data access
    logic  be_store;             // bus error on store data access
    logic  [XLEN-1:0] fetch_pc;  // pc for instruction fetch
    logic  [XLEN-1:0] curr_pc;   // current pc (for current executed instruction)
    logic  [XLEN-1:0] next_pc;   // next pc (for next executed instruction)
    logic  [4:0] fpu_flags;      // FPU exception flags
    logic  i_pmp_fault;          // instruction fetch PMP fault

    /* pmp interface */
    pmp_addr_if_t pmp_addr;
    pmp_ctrl_if_t pmp_ctrl;

    /* vector memory interface */
    vector_mem_req  mem_req;
    vector_mem_resp mem_resp;
    logic           req_valid;
    logic           resp_valid;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        // -------------------------------------------------------------------------------------------
        /* say hello */
        assert (1'b0)
        else $info("The CELLRV32 RISC-V Processor (Version 0x%h) - https://github.com/DatNguyen97-VN/cellrv32", hw_version_c);

        // -------------------------------------------------------------------------------------------
        /* CPU ISA configuration */
        assert (1'b0)
        else $info("CELLRV32 CPU CONFIG NOTE: Core ISA ('MARCH') = RV32 %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s",
                    cond_sel_string_f(CPU_EXTENSION_RISCV_E,        "E", "I"),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_M,        "M", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_C,        "C", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_B,        "B", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_U,        "U", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_V,        "V", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zicsr,    "_Zicsr", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zicntr,   "_Zicntr", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zicond,   "_Zicond", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zifencei, "_Zifencei", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zfinx,    "_Zfinx", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zhinx,    "_Zhinx", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zihpm,    "_Zihpm", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zmmul,    "_Zmmul", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Zxcfu,    "_Zxcfu", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Sdext,    "_Sdext", ""),
                    cond_sel_string_f(CPU_EXTENSION_RISCV_Sdtrig,   "_Sdtrig", ""));

        // -------------------------------------------------------------------------------------------
        /* simulation notifier */
        assert (is_simulation_c != 1'b1)
        else $warning("CELLRV32 CPU WARNING! Assuming this is a simulation.");
        //
        assert (is_simulation_c != 1'b1)
        else $info("CELLRV32 CPU NOTE: Assuming this is real hardware.");

        // -------------------------------------------------------------------------------------------
        /* native data width check (work in progress!) */
        assert (XLEN == 32)
        else $error("CELLRV32 CPU CONFIG ERROR! <XLEN> native data path width has to be 32 (bit).");

        // -------------------------------------------------------------------------------------------
        /* CPU boot address */
        assert (CPU_BOOT_ADDR[1:0] == 2'b00)
        else $error("CELLRV32 CPU CONFIG ERROR! <CPU_BOOT_ADDR> has to be 32-bit aligned.");
        //
        assert (1'b0)
        else $info("CELLRV32 CPU CONFIG NOTE: Boot from address 0x%h.", CPU_BOOT_ADDR);
        // -------------------------------------------------------------------------------------------
        /* CSR system */
        assert (CPU_EXTENSION_RISCV_Zicsr != 0)
        else $warning("CELLRV32 CPU CONFIG WARNING! No exception/interrupt/trap/privileged features available when <CPU_EXTENSION_RISCV_Zicsr> = false.");

        // -------------------------------------------------------------------------------------------
        /* U-extension requires Zicsr extension */
        assert ((CPU_EXTENSION_RISCV_Zicsr != 0) || (CPU_EXTENSION_RISCV_U != 1))
        else $error("CELLRV32 CPU CONFIG ERROR! User mode requires <CPU_EXTENSION_RISCV_Zicsr> extension to be enabled.");

        // -------------------------------------------------------------------------------------------
        /* Instruction prefetch buffer */
        assert (is_power_of_two_f(CPU_IPB_ENTRIES) != 1'b0)
        else $error("CELLRV32 CPU CONFIG ERROR! Number of entries in instruction prefetch buffer <CPU_IPB_ENTRIES> has to be a power of two.");
        //
        assert (ipb_override_c != 1)
        else $warning("CELLRV32 CPU CONFIG WARNING! Overriding <CPU_IPB_ENTRIES> configuration (setting =2) because C ISA extension is enabled.");

        // -------------------------------------------------------------------------------------------
        /* PMP */
        assert (PMP_NUM_REGIONS <= 0)
        else $info("CELLRV32 CPU CONFIG NOTE: Implementing %0d PMP regions.", PMP_NUM_REGIONS);
        //
        assert (PMP_NUM_REGIONS <= 16)
        else $info("CELLRV32 CPU CONFIG ERROR! Number of PMP regions <PMP_NUM_REGIONS> out of valid range (0..16).");
        //
        assert ((is_power_of_two_f(PMP_MIN_GRANULARITY) != 0) || (PMP_NUM_REGIONS == 0))
        else $error("CELLRV32 CPU CONFIG ERROR! <PMP_MIN_GRANULARITY> has to be a power of two.");
        //
        assert (PMP_MIN_GRANULARITY >= 4)
        else $error("CELLRV32 CPU ERROR! <PMP_MIN_GRANULARITY> has to be >= 4 bytes.");
        //
        assert ((CPU_EXTENSION_RISCV_Zicsr != 0) || (PMP_NUM_REGIONS == 0))
        else $error("CELLRV32 CPU ERROR! Physical memory protection (PMP) requires <CPU_EXTENSION_RISCV_Zicsr> extension to be enabled.");

        // -------------------------------------------------------------------------------------------
        /* HPM counters */
        assert (!((CPU_EXTENSION_RISCV_Zihpm == 1) && (HPM_NUM_CNTS > 0)))
        else $info("CELLRV32 CPU CONFIG NOTE: Implementing %0d HPM counters.", HPM_NUM_CNTS);
        //
        assert (!((CPU_EXTENSION_RISCV_Zihpm == 1) && (HPM_NUM_CNTS > 29)))
        else $error("CELLRV32 CPU CONFIG ERROR! Number of HPM counters <HPM_NUM_CNTS> out of valid range (0..29).");
        //
        assert (!((CPU_EXTENSION_RISCV_Zihpm == 1) && ((HPM_CNT_WIDTH < 0) || (HPM_CNT_WIDTH > 64))))
        else $error("CELLRV32 CPU CONFIG ERROR! HPM counter width <HPM_CNT_WIDTH> has to be 0..64 bit.");
        //
        assert (!((CPU_EXTENSION_RISCV_Zicsr == 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)))
        else $error("CELLRV32 CPU CONFIG ERROR! Hardware performance monitors extension <CPU_EXTENSION_RISCV_Zihpm> requires <CPU_EXTENSION_RISCV_Zicsr> extension to be enabled.");


        // -------------------------------------------------------------------------------------------
        /* Mul-extension(s) */
        assert (!((CPU_EXTENSION_RISCV_Zmmul == 1) && (CPU_EXTENSION_RISCV_M == 1)))
        else $error("CELLRV32 CPU CONFIG ERROR! <M> and <Zmmul> extensions cannot co-exist!");

        // -------------------------------------------------------------------------------------------
        /* Debug mode */
        assert (!((CPU_EXTENSION_RISCV_Sdext == 1) && (CPU_EXTENSION_RISCV_Zicsr == 0)))
        else $error("CELLRV32 CPU CONFIG ERROR! Debug mode requires <CPU_EXTENSION_RISCV_Zicsr> extension to be enabled.");
        //
        assert (!((CPU_EXTENSION_RISCV_Sdext == 1) && (CPU_EXTENSION_RISCV_Zifencei == 0)))
        else $error("CELLRV32 CPU CONFIG ERROR! Debug mode requires <CPU_EXTENSION_RISCV_Zifencei> extension to be enabled.");

        // -------------------------------------------------------------------------------------------
        /* fast multiplication option */
        assert (!(FAST_MUL_EN == 1'b1))
        else $info("CELLRV32 CPU CONFIG NOTE: <FAST_MUL_EN> enabled. Trying to infer DSP blocks for multiplications.");

        // -------------------------------------------------------------------------------------------
        /* fast shift option */
        assert (!(FAST_SHIFT_EN == 1'b1))
        else $info("CELLRV32 CPU CONFIG NOTE: <FAST_SHIFT_EN> enabled. Implementing full-parallel logic / barrel shifters.");

        // -------------------------------------------------------------------------------------------
        /* Vector Extension */
        assert (!(CPU_EXTENSION_RISCV_V == 1'b1))
        else $info("CELLRV32 CPU CONFIG NOTE: Vector Extension <V> enabled with <VLEN> = %d and <ELEN> = %d.", VLEN, ELEN);
        //
        assert ((CPU_EXTENSION_RISCV_V != 1'b1) || (is_power_of_two_f(VLEN) != 1'b0)) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! VLEN should be a power of 2 to follow hardware design.");
        //
        assert ((CPU_EXTENSION_RISCV_V != 1'b1) || (is_power_of_two_f(ELEN) != 1'b0)) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! ELEN should be a power of 2 to follow hardware design.");
        //
        assert ((CPU_EXTENSION_RISCV_V != 1'b1) || (VLEN >= ELEN)) else
        $warning("CELLRV32 PROCESSOR CONFIG WARNING! VLEN should be greater or equal to ELEN to follow hardware design.");
    end

    // Control Unit ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_cpu_control #(
        /* General */
        .XLEN(XLEN),                                   // data path width
        .HW_THREAD_ID(HW_THREAD_ID),                   // hardware thread id
        .CPU_BOOT_ADDR(CPU_BOOT_ADDR),                 // cpu boot address
        .CPU_DEBUG_PARK_ADDR(CPU_DEBUG_PARK_ADDR),     // cpu debug mode parking loop entry address
        .CPU_DEBUG_EXC_ADDR( CPU_DEBUG_EXC_ADDR),      // cpu debug mode exception entry address
        /* RISC-V CPU Extensions */
        .CPU_EXTENSION_RISCV_B(CPU_EXTENSION_RISCV_B), // implement bit-manipulation extension?
        .CPU_EXTENSION_RISCV_C(CPU_EXTENSION_RISCV_C), // implement compressed extension?
        .CPU_EXTENSION_RISCV_E(CPU_EXTENSION_RISCV_E), // implement embedded RF extension?
        .CPU_EXTENSION_RISCV_M(CPU_EXTENSION_RISCV_M), // implement mul/div extension?
        .CPU_EXTENSION_RISCV_U(CPU_EXTENSION_RISCV_U), // implement user mode extension?
        .CPU_EXTENSION_RISCV_V(CPU_EXTENSION_RISCV_V), // implement vector extension?
        .CPU_EXTENSION_RISCV_Zfinx(CPU_EXTENSION_RISCV_Zfinx),       // implement 32-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zhinx(CPU_EXTENSION_RISCV_Zhinx),       // implement 16-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zicsr(CPU_EXTENSION_RISCV_Zicsr),       // implement CSR system?
        .CPU_EXTENSION_RISCV_Zicntr(CPU_EXTENSION_RISCV_Zicntr),    // implement base counters?
        .CPU_EXTENSION_RISCV_Zicond(CPU_EXTENSION_RISCV_Zicond),     // implement conditional operations extension?
        .CPU_EXTENSION_RISCV_Zihpm(CPU_EXTENSION_RISCV_Zihpm),       // implement hardware performance monitors?
        .CPU_EXTENSION_RISCV_Zifencei(CPU_EXTENSION_RISCV_Zifencei), // implement instruction stream sync.?
        .CPU_EXTENSION_RISCV_Zmmul(CPU_EXTENSION_RISCV_Zmmul),       // implement multiply-only M sub-extension?
        .CPU_EXTENSION_RISCV_Zxcfu(CPU_EXTENSION_RISCV_Zxcfu),       // implement custom (instr.) functions unit?
        .CPU_EXTENSION_RISCV_Sdext(CPU_EXTENSION_RISCV_Sdext),       // implement external debug mode extension?
        .CPU_EXTENSION_RISCV_Sdtrig(CPU_EXTENSION_RISCV_Sdtrig),     // implement trigger module extension?
        /* Tuning Options */
        .FAST_MUL_EN(    FAST_MUL_EN),                  // use DSPs for M extension's multiplier
        .FAST_SHIFT_EN ( FAST_SHIFT_EN),                // use barrel shifter for shift operations
        .CPU_IPB_ENTRIES(ipb_depth_c),                  // entries is instruction prefetch buffer, has to be a power of 2, min 1
        /* Physical memory protection (PMP) */
        .PMP_NUM_REGIONS(    PMP_NUM_REGIONS),          // number of regions (0..16)
        .PMP_MIN_GRANULARITY(PMP_MIN_GRANULARITY),      // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
        /* Hardware Performance Monitors (HPM) */
        .HPM_NUM_CNTS(HPM_NUM_CNTS),                    // number of implemented HPM counters (0..29)
        .HPM_CNT_WIDTH(HPM_CNT_WIDTH)                   // total size of HPM counters
    ) cellrv32_cpu_control_inst (
        /* global control */
        .clk_i(clk_i),          // global clock, rising edge
        .rstn_i(rstn_i),        // global reset, low-active, async
        .ctrl_o(ctrl),          // main control bus
        /* instruction fetch interface */
        .i_bus_addr_o(fetch_pc),       // bus access address
        .i_bus_rdata_i(i_bus_rdata_i), // bus read data
        .i_bus_re_o(i_bus_re_o),       // read enable
        .i_bus_ack_i(i_bus_ack_i),     // bus transfer acknowledge
        .i_bus_err_i(i_bus_err_i),     // bus transfer error
        .i_pmp_fault_i(i_pmp_fault),   // instruction fetch pmp fault
        /* status input */
        .alu_cp_done_i(cp_done),   // ALU iterative operation done
        .alu_exc_i(alu_exc),       // ALU exception
        .bus_d_wait_i(bus_d_wait), // wait for bus
        /* data input */
        .cmp_i(alu_cmp),      // comparator status
        .alu_add_i(alu_add),  // ALU address result
        .rs1_i(rs1),          // rf source 1
        .rs2_i(rs2),          // rf source 2
        /* data output */
        .imm_o(imm),          // immediate
        .curr_pc_o(curr_pc),         // current PC (corresponding to current instruction)
        .next_pc_o(next_pc),         // next PC (corresponding to next instruction)
        .csr_rdata_o(csr_rdata),     // CSR read data
        /* FPU interface */
        .fpu_flags_i(fpu_flags),     // exception flags
        /* debug mode (halt) request */
        .db_halt_req_i(db_halt_req_i),
        /* interrupts (risc-v compliant) */
        .msw_irq_i(msw_irq_i),      // machine software interrupt
        .mext_irq_i(mext_irq_i),    // machine external interrupt
        .mtime_irq_i(mtime_irq_i),  // machine timer interrupt
        /* fast interrupts (custom) */
        .firq_i(firq_i),        // fast interrupt trigger
        /* physical memory protection */
        .pmp_addr_o(pmp_addr),      // addresses
        .pmp_ctrl_o(pmp_ctrl),      // configs
        /* bus access exceptions */
        .mar_i(mar),           // memory address register
        .ma_load_i(ma_load),   // misaligned load data address
        .ma_store_i(ma_store), // misaligned store data address
        .be_load_i(be_load),   // bus error on load data access
        .be_store_i(be_store)  // bus error on store data access
    );

    /* CPU state */
    assign sleep_o = ctrl.cpu_sleep; // set when CPU is sleeping (after WFI)
    assign debug_o = ctrl.cpu_debug; // set when CPU is in debug mode

    /* instruction fetch interface */
    assign i_bus_addr_o  = fetch_pc;
    assign i_bus_fence_o = ctrl.bus_fencei;
    assign i_bus_priv_o  = ctrl.cpu_priv;

    // Register File -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_cpu_regfile #(
        .XLEN                  (XLEN),                  // data path width
        .CPU_EXTENSION_RISCV_E (CPU_EXTENSION_RISCV_E), // implement embedded RF extension?
        .RS3_EN                (regfile_rs3_en_c),      // enable 3rd read port
        .RS4_EN                (regfile_rs4_en_c)       // enable 4th read port
    ) cellrv32_cpu_regfile_inst (
        /* global control */
        .clk_i  (clk_i),    // global clock, rising edge
        .rstn_i (rstn_i),   // global reset, low-active, async
        .ctrl_i (ctrl),     // main control bus
        /* data input */
        .alu_i (alu_res),   // ALU result
        .mem_i (mem_rdata), // memory read data
        .csr_i (csr_rdata), // CSR read data
        .pc2_i (next_pc),   // next PC
        /* data output */
        .rs1_o (rs1),       // operand 1
        .rs2_o (rs2),       // operand 2
        .rs3_o (rs3),       // operand 3
        .rs4_o (rs4)        // operand 4
    );

    // ALU ---------------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_cpu_alu #(
        .XLEN                       (XLEN),                        // data path width
        /* RISC-V CPU Extensions */
        .CPU_EXTENSION_RISCV_B      (CPU_EXTENSION_RISCV_B),       // implement bit-manipulation extension?
        .CPU_EXTENSION_RISCV_M      (CPU_EXTENSION_RISCV_M),       // implement mul/div extension?
        .CPU_EXTENSION_RISCV_V      (CPU_EXTENSION_RISCV_V),       // implement vector extension?
        .CPU_EXTENSION_RISCV_Zmmul  (CPU_EXTENSION_RISCV_Zmmul),   // implement multiply-only M sub-extension?
        .CPU_EXTENSION_RISCV_Zfinx  (CPU_EXTENSION_RISCV_Zfinx),   // implement 32-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zhinx  (CPU_EXTENSION_RISCV_Zhinx),   // implement 16-bit floating-point extension (using INT reg!)
        .CPU_EXTENSION_RISCV_Zxcfu  (CPU_EXTENSION_RISCV_Zxcfu),   // implement custom (instr.) functions unit?
        .CPU_EXTENSION_RISCV_Zicond (CPU_EXTENSION_RISCV_Zicond),  // implement conditional operations extension?
        /* Extension Options */
        .FAST_MUL_EN                (FAST_MUL_EN),                 // use DSPs for M extension's multiplier
        .FAST_SHIFT_EN              (FAST_SHIFT_EN)                // use barrel shifter for shift operations
    ) cellrv32_cpu_alu_inst (
        /* global control */
        .clk_i       (clk_i),     // global clock, rising edge
        .rstn_i      (rstn_i),    // global reset, low-active, async
        .ctrl_i      (ctrl),      // main control bus
        /* data input */
        .rs1_i       (rs1),       // rf source 1
        .rs2_i       (rs2),       // rf source 2
        .rs3_i       (rs3),       // rf source 3
        .rs4_i       (rs4),       // rf source 4
        .pc_i        (curr_pc),   // current PC
        .imm_i       (imm),       // immediate
        /* data output */
        .cmp_o       (alu_cmp),   // comparator status
        .res_o       (alu_res),   // ALU result
        .add_o       (alu_add),   // address computation result
        .fpu_flags_o (fpu_flags), // FPU exception flags
        /* vector memory interface */
        .mem_req_o    (mem_req),
        .req_valid_o  (req_valid),
        .mem_resp_i   (mem_resp),
        .resp_valid_i (resp_valid),
        .multi_rsp_i  (d_bus_multi_rsp_i),
        /* status */
        .exc_o       (alu_exc),   // ALU exception
        .cp_done_o   (cp_done)    // iterative processing units done?
    );

    // Bus Interface (Load/Store Unit) -----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_cpu_bus #(
        .XLEN                (XLEN),               // data path width
        .PMP_NUM_REGIONS     (PMP_NUM_REGIONS),    // number of regions (0..16)
        .PMP_MIN_GRANULARITY (PMP_MIN_GRANULARITY) // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
    ) cellrv32_cpu_bus_inst (
        /* global control */
        .clk_i               (clk_i),         // global clock, rising edge
        .rstn_i              (rstn_i),        // global reset, low-active, async
        .ctrl_i              (ctrl  ),        // main control bus
        /* cpu instruction fetch interface */
        .fetch_pc_i          (fetch_pc),      // PC for instruction fetch
        .i_pmp_fault_o       (i_pmp_fault),   // instruction fetch pmp fault
        /* cpu data access interface */
        .addr_i              (alu_add),       // ALU.add result -> access address
        .wdata_i             (rs2),           // write data
        .rdata_o             (mem_rdata),     // read data
        .mar_o               (mar),           // current memory address register
        .d_wait_o            (bus_d_wait),    // wait for access to complete
        .ma_load_o           (ma_load),       // misaligned load data address
        .ma_store_o          (ma_store),      // misaligned store data address
        .be_load_o           (be_load),       // bus error on load data access
        .be_store_o          (be_store),      // bus error on store data access
        /* physical memory protection */
        .pmp_addr_i          (pmp_addr),      // addresses
        .pmp_ctrl_i          (pmp_ctrl),      // configurations
        /* vector data interface */
        .req_valid_i         (req_valid),
        .mem_req_i           (mem_req),
        .resp_valid_o        (resp_valid),
        .mem_resp_o          (mem_resp),
        .d_bus_multi_en_o    (d_bus_multi_en_o),
        .d_bus_req_ticket_o  (d_bus_req_ticket_o),
        .d_bus_resp_ticket_i (d_bus_resp_ticket_i),
        /* data bus */
        .d_bus_addr_o        (d_bus_addr_o),  // bus access address
        .d_bus_rdata_i       (d_bus_rdata_i), // bus read data
        .d_bus_wdata_o       (d_bus_wdata_o), // bus write data
        .d_bus_ben_o         (d_bus_ben_o),   // byte enable
        .d_bus_we_o          (d_bus_we_o),    // write enable
        .d_bus_re_o          (d_bus_re_o),    // read enable
        .d_bus_ack_i         (d_bus_ack_i),   // bus transfer acknowledge
        .d_bus_err_i         (d_bus_err_i),   // bus transfer error
        .d_bus_fence_o       (d_bus_fence_o), // fence operation
        .d_bus_priv_o        (d_bus_priv_o)   // current effective privilege level
    );

endmodule