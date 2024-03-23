// ##################################################################################################
// # << CELLRV32 - CPU Operations Control Unit >>                                                   #
// # ********************************************************************************************** #
// # CPU operations are controlled by several "engines" (modules). These engines operate in         #
// # parallel to implement a simple pipeline:                                                       #
// #  + Fetch engine:    Fetches 32-bit chunks of instruction words                                 #
// #  + Issue engine:    Decodes compressed instructions, aligns and queues instruction words       #
// #  + Execute engine:  Multi-cycle execution of instructions (generate control signals)           #
// #  + Trap controller: Handles interrupts and exceptions                                          #
// #  + CSR module:      Read/write access to control and status registers                          #
// #  + Debug module:    CPU debug mode handling (on-chip debugger)                                 #
// #  + Trigger module:  Hardware-assisted breakpoints (on-chip debugger)                           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_control #(
    /* General */
    parameter XLEN                         = 32, // data path width
    parameter HW_THREAD_ID                 = 0,  // hardware thread id (32-bit)
    parameter logic[31:0] CPU_BOOT_ADDR       = 0, // cpu boot address
    parameter logic[31:0] CPU_DEBUG_PARK_ADDR = 0, // cpu debug mode parking loop entry address
    parameter logic[31:0] CPU_DEBUG_EXC_ADDR  = 0, // cpu debug mode exception entry address
    /* RISC-V CPU Extensions */
    parameter CPU_EXTENSION_RISCV_B        = 0, // implement bit-manipulation extension?
    parameter CPU_EXTENSION_RISCV_C        = 0, // implement compressed extension?
    parameter CPU_EXTENSION_RISCV_E        = 0, // implement embedded RF extension?
    parameter CPU_EXTENSION_RISCV_M        = 0, // implement mul/div extension?
    parameter CPU_EXTENSION_RISCV_U        = 0, // implement user mode extension?
    parameter CPU_EXTENSION_RISCV_Zfinx    = 0, // implement 32-bit floating-point extension (using INT reg!)
    parameter CPU_EXTENSION_RISCV_Zicsr    = 0, // implement CSR system?
    parameter CPU_EXTENSION_RISCV_Zicntr   = 0, // implement base counters?
    parameter CPU_EXTENSION_RISCV_Zihpm    = 0, // implement hardware performance monitors?
    parameter CPU_EXTENSION_RISCV_Zifencei = 0, // implement instruction stream sync.?
    parameter CPU_EXTENSION_RISCV_Zmmul    = 0, // implement multiply-only M sub-extension?
    parameter CPU_EXTENSION_RISCV_Zxcfu    = 0, // implement custom (instr.) functions unit?
    parameter CPU_EXTENSION_RISCV_Zicond   = 0, // implement conditional operations extension?
    parameter CPU_EXTENSION_RISCV_Sdext    = 0, // implement external debug mode extension?
    parameter CPU_EXTENSION_RISCV_Sdtrig   = 0, // implement trigger module extension?
    /* Tuning Options */
    parameter FAST_MUL_EN                  = 0, // use DSPs for M extension's multiplier
    parameter FAST_SHIFT_EN                = 0, // use barrel shifter for shift operations
    parameter CPU_IPB_ENTRIES              = 1, // entries in instruction prefetch buffer, has to be a power of 2, min 1
    /* Physical memory protection (PMP) */
    parameter PMP_NUM_REGIONS              = 0, // number of regions (0..16)
    parameter PMP_MIN_GRANULARITY          = 0, // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
    /* Hardware Performance Monitors (HPM) */
    parameter HPM_NUM_CNTS                 = 0,  // number of implemented HPM counters (0..29)
    parameter HPM_CNT_WIDTH                = 40  // total size of HPM counters (0..64)
) (
    /* global control */
    input logic clk_i,         // global clock, rising edge
    input logic rstn_i,        // global reset, low-active, async
    output ctrl_bus_t ctrl_o,  // main control bus
    /* instruction fetch interface */
    output logic [XLEN-1:0] i_bus_addr_o,  // bus access address
    input  logic [31:0]     i_bus_rdata_i, // bus read data
    output logic            i_bus_re_o,    // read enable
    input  logic            i_bus_ack_i,   // bus transfer acknowledge
    input  logic            i_bus_err_i,   // bus transfer error
    input  logic            i_pmp_fault_i, // instruction fetch pmp fault
    /* status input */
    input logic alu_cp_done_i, // ALU iterative operation done
    input logic alu_exc_i,     // ALU exception
    input logic bus_d_wait_i,  // wait for bus
    /* data input */
    input logic [1:0]      cmp_i,     // comparator status
    input logic [XLEN-1:0] alu_add_i, // ALU address result
    input logic [XLEN-1:0] rs1_i,     // rf source 1
    /* data output */
    output logic [XLEN-1:0] imm_o,       // immediate
    output logic [XLEN-1:0] curr_pc_o,   // current PC (corresponding to current instruction)
    output logic [XLEN-1:0] next_pc_o,   // next PC (corresponding to next instruction)
    output logic [XLEN-1:0] csr_rdata_o, // CSR read data
    /* FPU interface */
    input logic [4:0] fpu_flags_i, // exception flags
    /* debug mode (halt) request */
    input logic db_halt_req_i,
    /* interrupts (risc-v compliant) */
    input logic msw_irq_i,     // machine software interrupt
    input logic mext_irq_i,    // machine external interrupt
    input logic mtime_irq_i,   // machine timer interrupt
    /* fast interrupts (custom) */
    input logic [15:0] firq_i,
    /* physical memory protection */
    output logic [33:0] pmp_addr_o [15:0], // addresses
    output logic [07:0] pmp_ctrl_o [15:0], // configs
    /* bus access exceptions */
    input logic [XLEN-1:0] mar_i,      // memory address register
    input logic            ma_load_i,  // misaligned load data address
    input logic            ma_store_i, // misaligned store data address
    input logic            be_load_i,  // bus error on load data access
    input logic            be_store_i  // bus error on store data access
);
    /* HPM counter width - high/low parts */
    localparam int hpm_cnt_lo_width_c = cond_sel_int_f((HPM_CNT_WIDTH < 32), HPM_CNT_WIDTH, 32);
    localparam int hpm_cnt_hi_width_c = cond_sel_int_f((HPM_CNT_WIDTH > 32), HPM_CNT_WIDTH-32, 0);

    /* instruction fetch engine */
    typedef enum logic[1:0] { IF_RESTART, 
                              IF_REQUEST, 
                              IF_PENDING, 
                              IF_WAIT } fetch_engine_state_t; //  better use one-hot encoding
    
    /* instruction fetch engine */
    typedef struct {
        fetch_engine_state_t state;
        fetch_engine_state_t state_prev;
        logic restart;
        logic unaligned;
        logic [XLEN-1:0] pc;
        logic reset;
        logic resp;    // bus response
        logic a_err;   // alignment error
        logic pmp_err; // PMP error
    } fetch_engine_t;
    //
    fetch_engine_t fetch_engine;

    /* instruction prefetch buffer (FIFO) interface */
    typedef logic [0:1][(2+16)-1:0] ipb_data_t;
    //
    typedef struct packed {
        ipb_data_t  wdata;
        logic [1:0] we;    // trigger write
        logic [1:0] free;  // free entry available?
        ipb_data_t  rdata;
        logic [1:0] re;    // read enable
        logic [1:0] avail; // data available?
    } ipb_t;
    //
    ipb_t ipb;

    /* instruction issue engine */
    typedef struct {
        logic align;
        logic align_set;
        logic align_clr;
        logic [15:0] ci_i16;
        logic [31:0] ci_i32;
        logic ci_ill;
        logic [(4+32)-1:0] data; // 4-bit status + 32-bit instruction
        logic [1:0]        valid; // data word is valid when != 0
    } issue_engine_t;
    //
    issue_engine_t issue_engine;

    /* instruction decoding helper logic */
    typedef struct {
        logic is_f_op;   
        logic is_m_mul;  
        logic is_m_div;  
        logic is_b_imm;  
        logic is_b_reg;  
        logic is_zicond; 
        logic rs1_zero; 
        logic rd_zero;   
    } decode_aux_t;
    //
    decode_aux_t decode_aux;

    /* instruction execution engine */
    // make sure reset state is the first item in the list (discussion #415)
    typedef enum logic[3:0] { BRANCHED, DISPATCH, TRAP_ENTER, 
                             TRAP_EXIT, TRAP_EXECUTE, EXECUTE, 
                             ALU_WAIT, BRANCH, SYSTEM, MEM_REQ,
                             MEM_WAIT } execute_engine_state_t;
    //
    typedef struct packed {
        execute_engine_state_t state;
        execute_engine_state_t state_nxt;
        execute_engine_state_t state_prev;
        execute_engine_state_t state_prev2;
        //
        logic [31:0] i_reg;
        logic [31:0] i_reg_nxt;
        //
        logic is_ci;     // current instruction is de-compressed instruction
        logic is_ci_nxt;
        logic is_ici;    // current instruction is illegal de-compressed instruction
        logic is_ici_nxt;
        //
        logic            branch_taken; // branch condition fulfilled
        logic [XLEN-1:0] pc;           // actual PC, corresponding to current executed instruction
        logic            pc_mux_sel;   // source select for PC update
        logic            pc_we;        // PC update enabled
        logic [XLEN-1:0] next_pc;      // next PC, corresponding to next instruction to be executed
        logic [XLEN-1:0] next_pc_inc;  // increment to get next PC
        logic [XLEN-1:0] pc_last;      // PC of last executed instruction
        //
        logic sleep;    // CPU in sleep mode
        logic sleep_nxt;
        logic branched; // instruction fetch was reset
        logic branched_nxt;
    } execute_engine_t;
    //
    execute_engine_t execute_engine;

    /* trap_ctrl_t */
    typedef struct packed {
        logic [exc_width_c-1:0] exc_buf;       // synchronous exception buffer (one bit per exception)
        logic                   exc_fire;      // set if there is a valid source in the exception buffer
        logic [irq_width_c-1:0] irq_pnd;       // pending interrupt
        logic [irq_width_c-1:0] irq_buf;       // asynchronous exception/interrupt buffer (one bit per interrupt source)
        logic                   irq_fire;      // set if there is a valid source in the interrupt buffer
        logic [6:0]             cause;         // trap ID for mcause CSR + debug-mode entry identifier
        logic [XLEN-1:0]        epc;           // exception program counter
        //
        logic env_start;     // start trap handler env
        logic env_start_ack; // start of trap handler acknowledged
        logic env_end;       // end trap handler env
        //
        logic instr_be;      // instruction fetch bus error
        logic instr_ma;      // instruction fetch misaligned address
        logic instr_il;      // illegal instruction
        logic env_call;      // ecall instruction
        logic break_point;   // ebreak instruction
    } trap_ctrl_t;
    //
    trap_ctrl_t trap_ctrl;

    /* CPU main control bus */
    ctrl_bus_t ctrl_nxt, ctrl;

    /* RISC-V control and status registers (CSRs) */
    typedef logic [0:PMP_NUM_REGIONS-1][7:0]                  pmpcfg_t;
    typedef logic [0:3][XLEN-1:0]                             pmpcfg_rd_t;
    typedef logic [0 : PMP_NUM_REGIONS-1][XLEN-3:index_size_f(PMP_MIN_GRANULARITY)-2] pmpaddr_t;
    typedef logic [0:15][XLEN-1:0]                            pmpaddr_rd_t;
    typedef logic [0:HPM_NUM_CNTS-1][hpmcnt_event_size_c-1:0] mhpmevent_t;
    typedef logic [0:28][XLEN-1:0]                            mhpmevent_rd_t;
    typedef logic [0:HPM_NUM_CNTS-1][XLEN-1:0]                mhpmcnt_t;
    typedef logic [0:28][XLEN:0]                              mhpmcnt_nxt_t;
    typedef logic [0:HPM_NUM_CNTS-1][00:00]                   mhpmcnt_ovfl_t;
    typedef logic [0:28][XLEN-1:0]                            mhpmcnt_rd_t;
    //
    typedef struct packed {
        logic [11:0]     addr;              // csr address
        logic            we;                // csr write enable
        logic            we_nxt;           
        logic            re;                // csr read enable
        logic            re_nxt;           
        logic [XLEN-1:0] wdata;             // csr write data
        logic [XLEN-1:0] rdata;             // csr read data
        //
        logic mstatus_mie;       // mstatus.MIE: global IRQ enable (R/W)
        logic mstatus_mpie;      // mstatus.MPIE: previous global IRQ enable (R/W)
        logic mstatus_mpp;       // mstatus.MPP: machine previous privilege mode
        logic mstatus_mprv;      // mstatus.MPRV: effective privilege level for machine-mode load/stores
        logic mstatus_tw;        // mstatus.TW: do not allow user mode to execute WFI instruction when set
        //
        logic        mie_msi;    // mie.MSIE: machine software interrupt enable (R/W)
        logic        mie_mei;    // mie.MEIE: machine external interrupt enable (R/W)
        logic        mie_mti;    // mie.MEIE: machine timer interrupt enable (R/W)
        logic [15:0] mie_firq;  // mie.firq*e: fast interrupt enabled (R/W)
        //
        logic [15:0] mip_firq_nclr;     // clear pending FIRQ (active-low)
        //
        logic mcountinhibit_cy;         // mcounterinhibit.cy: inhibit auto-increment for [m]cycle[h]
        logic mcountinhibit_ir;         // mcounterinhibit.ir: inhibit auto-increment for [m]instret[h]
        logic [28:0] mcountinhibit_hpm; // mcounterinhibit.hpm: inhibit auto-increment for mhpmcounterx[h]
        //
        logic privilege;     // current privilege mode
        logic privilege_eff; // current *effective* privilege mode
        //
        logic [XLEN-1:0] mepc;   // mepc: machine exception pc (R/W)
        logic [5:0]      mcause; // mcause: machine trap cause (R/W)
        logic [XLEN-1:0] mtvec;  // mtvec: machine trap-handler base address (R/W), bit 1:0 == 00
        logic [XLEN-1:0] mtval;  // mtval: machine bad address or instruction (R/W)
        //
        mhpmevent_t    mhpmevent;    // mhpmevent*: machine performance-monitoring event selector (R/W)
        mhpmevent_rd_t mhpmevent_rd; // read data
        //
        logic [XLEN-1:0] mscratch; // mscratch: scratch register (R/W)
        //
        logic [XLEN-1:0] mcycle;        // mcycle (R/W)
        logic [XLEN:0]   mcycle_nxt;
        logic [00:00]    mcycle_ovfl;   // counter low-to-high-word overflow
        logic [XLEN-1:0] mcycleh;       // mcycleh (R/W)
        logic [XLEN-1:0] minstret;      // minstret (R/W)
        logic [XLEN:0]   minstret_nxt;
        logic [00:00]    minstret_ovfl; // counter low-to-high-word overflow
        logic [XLEN-1:0] minstreth;     // minstreth (R/W)
        //
        mhpmcnt_t      mhpmcounter;      // mhpmcounter* (R/W), plus carry bit
        mhpmcnt_nxt_t  mhpmcounter_nxt;  // low-word to high-word counter overflow
        mhpmcnt_ovfl_t mhpmcounter_ovfl; // counter low-to-high-word overflow
        mhpmcnt_t      mhpmcounterh;     // mhpmcounter*h (R/W)
        mhpmcnt_rd_t   mhpmcounter_rd;   // counter low read-back
        mhpmcnt_rd_t   mhpmcounterh_rd;  // counter high read-back
        //
        pmpcfg_t     pmpcfg;             // PMP configuration registers
        pmpcfg_rd_t  pmpcfg_rd;          // PMP configuration read-back
        pmpaddr_t    pmpaddr;            // PMP address registers (bits 33:2 of PHYSICAL address)
        pmpaddr_rd_t pmpaddr_rd;         // PMP address read-back
        //
        logic [2:0] frm;                 // frm (R/W): FPU rounding mode
        logic [4:0] fflags;              // fflags (R/W): FPU exception flags
        //
        logic            dcsr_ebreakm;  // dcsr.ebreakm (R/W): behavior of ebreak instruction in m-mode
        logic            dcsr_ebreaku;  // dcsr.ebreaku (R/W): behavior of ebreak instruction in u-mode
        logic            dcsr_step;     // dcsr.step (R/W): single-step mode
        logic            dcsr_prv;      // dcsr.prv (R/W): current privilege level when entering debug mode
        logic [2:0]      dcsr_cause;    // dcsr.cause (R/-): why was debug mode entered
        logic [XLEN-1:0] dcsr_rd;       // dcsr (R/(W)): debug mode control and status register
        logic [XLEN-1:0] dpc;           // dpc (R/W): debug mode program counter
        logic [XLEN-1:0] dscratch0;     // dscratch0 (R/W): debug mode scratch register 0
        //
        logic            tdata1_exe;     // enable (match) trigger
        logic            tdata1_action;  // enter debug mode / ebreak exception when trigger fires
        logic            tdata1_dmode;   // set to ignore tdata* CSR access from machine-mode
        logic [XLEN-1:0] tdata1_rd;      // tdata1 (R/(W)): trigger register read-back
        logic [XLEN-1:0] tdata2;         // tdata2 (R/W): address-match register
    } csr_t;
    //
    csr_t csr;

    /* counter CSRs write access */
    typedef struct {
        logic [XLEN-1:0] wdata; 
        logic [1:0]      cycle; 
        logic [1:0]      instret;
        logic [28:0]     hpm_lo; 
        logic [28:0]     hpm_hi;
    } cnt_csr_we_t;
    //
    cnt_csr_we_t cnt_csr_we;

    /* debug mode controller */
    typedef enum logic[1:0] { DEBUG_OFFLINE, DEBUG_ONLINE, DEBUG_LEAVING } debug_ctrl_state_t;
    //
    typedef struct {
        debug_ctrl_state_t state;
        logic              running;      // CPU is in debug mode
        logic              trig_hw;      // hardware trigger
        logic              trig_break;   // ebreak instruction trigger
        logic              trig_halt;    // external request trigger
        logic              trig_step;    // single-stepping mode trigger
        logic              dret;         // executed DRET instruction
        logic              ext_halt_req; // external halt request buffer
    } debug_ctrl_t;
    //
    debug_ctrl_t debug_ctrl;

    /* (hpm) counter events */
    logic [hpmcnt_event_size_c-1:0] cnt_event;
    logic [HPM_NUM_CNTS-1:0]        hpmcnt_trigger;

    /* illegal instruction check */
    logic illegal_cmd;
    logic illegal_reg; // illegal register (>x15) - E-extension

    /* CSR access/privilege and r/w check */
    logic csr_reg_valid;  // valid CSR access (implemented at all)
    logic csr_rw_valid;   // valid CSR access (valid r/w access rights)
    logic csr_priv_valid; // valid CSR access (valid access privilege)

    /* hardware trigger module */
    logic hw_trigger_fire;

    /* misc */
    logic [06:0] imm_opcode; // simplified opcode for immediate generator
    logic [11:0] csr_raddr;  // CSR read address (AND-gated)
    
    // ****************************************************************************************************************************
    // Instruction Fetch (always fetch 32-bit-aligned 32-bit chunks of data)
    // ****************************************************************************************************************************
    // Fetch Engine FSM --------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : fetch_engine_fsm
      if (rstn_i == 1'b0) begin
          fetch_engine.state      <= IF_RESTART;
          fetch_engine.state_prev <= IF_RESTART;
          fetch_engine.restart    <= 1'b1; // set to reset IPB
          fetch_engine.unaligned  <= 1'b0; // always start at aligned address after reset
          fetch_engine.pc         <= '0;
          fetch_engine.pmp_err    <= 1'b0;
      end else begin
          /* previous state (for HPM) */
          fetch_engine.state_prev <= fetch_engine.state;
          //
          /* restart request buffer */
          if (fetch_engine.state == IF_RESTART) begin // restart done
              fetch_engine.restart <= 1'b0;
          end else begin // buffer request
              fetch_engine.restart <= fetch_engine.restart | fetch_engine.reset;
          end
          //
          /* FSM */
          unique case (fetch_engine.state)
              // --------------------------------------------------------------
              /* set new fetch start address */
              IF_RESTART : begin
                  fetch_engine.pc        <= {execute_engine.pc[XLEN-1:2], 2'b00}; // initialize with "real" PC, 32-bit aligned
                  fetch_engine.unaligned <= execute_engine.pc[1];
                  fetch_engine.state     <= IF_REQUEST;
              end
              // --------------------------------------------------------------
              /* request new 32-bit-aligned instruction word */
              IF_REQUEST : begin
                  fetch_engine.pmp_err <= i_pmp_fault_i;
                  if (ipb.free == 2'b11) begin // wait for free IPB space
                      fetch_engine.state <= IF_PENDING;
                  end
              end
              // --------------------------------------------------------------
              // wait for bus response and write instruction data to prefetch buffer
              IF_PENDING : begin
                  // wait for bus response
                  if (fetch_engine.resp == 1'b1) begin
                      fetch_engine.pc        <= fetch_engine.pc + 4;
                      fetch_engine.unaligned <= 1'b0;
                      fetch_engine.pmp_err   <= 1'b0;
                      //
                      // restart request (fast)
                      if ((fetch_engine.restart == 1'b1) || (fetch_engine.reset == 1'b1)) begin
                          fetch_engine.state <= IF_RESTART;
                          // do not trigger new instruction fetch when a branch instruction is being executed (wait for branch destination)
                      end else if (((execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c+2] == opcode_branch_c[6:2]) &&
                                    (execute_engine.i_reg[31] == 1'b1)) || // predict: taken if branching backwards
                                    (execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c+2] == opcode_jal_c[6:2]) ||      // always taken
                                    (execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c+2] == opcode_jalr_c[6:2])) begin // always taken
                          fetch_engine.state <= IF_WAIT;
                      end else begin // request next instruction word
                          fetch_engine.state <= IF_REQUEST;
                      end
                  end
              end
              // --------------------------------------------------------------
              // wait for branch instruction
              IF_WAIT : begin
                  // restart request (fast) if taken branch
                  if ((fetch_engine.restart == 1'b1) || (fetch_engine.reset == 1'b1)) begin
                      fetch_engine.state <= IF_RESTART;
                  end else begin
                      fetch_engine.state <= IF_REQUEST;
                  end
              end
              // --------------------------------------------------------------
              // undefined
              default: begin
                  fetch_engine.state <= IF_RESTART;
              end
          endcase
      end
    end : fetch_engine_fsm

    /* PC output for instruction fetch */
    assign i_bus_addr_o = {fetch_engine.pc[XLEN-1 : 2], 2'b00}; // 32-bit aligned

    /* instruction fetch (read) request if IPB not full */
    assign i_bus_re_o = ((fetch_engine.state == IF_REQUEST) && (ipb.free == 2'b11)) ? 1'b1 : 1'b0;

    /* unaligned access error (no alignment exceptions possible when using C-extension) */
    assign fetch_engine.a_err = ((fetch_engine.unaligned == 1'b1) && (CPU_EXTENSION_RISCV_C == 0)) ? 1'b1 : 1'b0;

    /* instruction bus response */
    // [NOTE] PMP and alignment-error will keep pending until the actually triggered bus access completes (or fails)
    assign fetch_engine.resp = ((i_bus_ack_i == 1'b1) || (i_bus_err_i == 1'b1)) ? 1'b1 : 1'b0;

    /* IPB instruction data and status */
    assign ipb.wdata[0] = {(i_bus_err_i | fetch_engine.pmp_err), fetch_engine.a_err, i_bus_rdata_i[15:00]};
    assign ipb.wdata[1] = {(i_bus_err_i | fetch_engine.pmp_err), fetch_engine.a_err, i_bus_rdata_i[31:16]};

    /* IPB write enable */
    assign ipb.we[0] = ((fetch_engine.state == IF_PENDING) && (fetch_engine.resp == 1'b1) &&
                       ((fetch_engine.unaligned == 1'b0) || (CPU_EXTENSION_RISCV_C == 0))) ? 1'b1 : 1'b0;
    assign ipb.we[1] = ((fetch_engine.state == IF_PENDING) && (fetch_engine.resp == 1'b1)) ? 1'b1 : 1'b0;

    // Instruction Prefetch Buffer (FIFO) --------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    genvar i;
    generate
     // low half-word and high half-word (+status)
     for (i = 0; i < 2; ++i) begin : prefetch_buffer
         cellrv32_fifo #(
             .FIFO_DEPTH (CPU_IPB_ENTRIES),     // number of fifo entries; has to be a power of two; min 1
             .FIFO_WIDTH ($bits(ipb.wdata[i])), // size of data elements in fifo
             .FIFO_RSYNC (0),                   // we NEED to read data asynchronously
             .FIFO_SAFE  (0),                   // no safe access required (ensured by FIFO-external control)
             .FIFO_GATE  (0)                    // no output gate required
         ) prefetch_buffer_inst (
             /* control */
             .clk_i   (clk_i),                // clock, rising edge
             .rstn_i  (rstn_i),               // async reset, low-active
             .clear_i (fetch_engine.restart), // sync reset, high-active
             .half_o  (    ),                 // at least half full
             /* write port */
             .wdata_i (ipb.wdata[i]),         // write data
             .we_i    (ipb.we[i]),            // write enable
             .free_o  (ipb.free[i]),          // at least one entry is free when set
             /* read port */
             .re_i    (ipb.re[i]),            // read enable
             .rdata_o (ipb.rdata[i]),         // read data
             .avail_o (ipb.avail[i])          // data available when set
         );
     end : prefetch_buffer
    endgenerate

    // ****************************************************************************************************************************
    // Instruction Issue (decompress 16-bit instructions and assemble a 32-bit instruction word)
    // ****************************************************************************************************************************

    // Issue Engine FSM (required only if C extension is enabled) --------------------------------
    // -------------------------------------------------------------------------------------------
    generate
     if (CPU_EXTENSION_RISCV_C == 1) begin : issue_engine_enabled
         always_ff @( posedge clk_i ) begin : issue_engine_fsm_sync
             if (fetch_engine.restart == 1'b1) begin
                  issue_engine.align <= execute_engine.pc[1]; // branch to unaligned address?
             end else if (execute_engine.state == DISPATCH) begin
                 issue_engine.align <= (issue_engine.align & (~issue_engine.align_clr)) | issue_engine.align_set; // "RS" flip-flop
             end
         end : issue_engine_fsm_sync
         //
         always_comb begin : issue_engine_fsm_comb
             /* defaults */
             issue_engine.align_set = 1'b0;
             issue_engine.align_clr = 1'b0;
             issue_engine.valid     = 2'b00;
             //
             /* start with LOW half-word */
             if (issue_engine.align == 1'b0) begin
                 if (ipb.rdata[0][1:0] != 2'b11) begin // compressed
                      issue_engine.align_set = ipb.avail[0]; // start of next instruction word is NOT 32-bit-aligned
                      issue_engine.valid[0]  = ipb.avail[0];
                      issue_engine.data      = {issue_engine.ci_ill, ipb.rdata[0][17:16], 1'b1, issue_engine.ci_i32};
                 end else begin // aligned uncompressed
                     issue_engine.valid = (ipb.avail[0] && ipb.avail[1]) ? '1 : '0;
                     issue_engine.data  = {1'b0, (ipb.rdata[1][17:16] | ipb.rdata[0][17:16]),
                                           1'b0,  ipb.rdata[1][15:00],  ipb.rdata[0][15:00]};
                 end
             /* start with HIGH half-word */
             end else begin
                 if (ipb.rdata[1][1:0] != 2'b11) begin // compressed
                     issue_engine.align_clr = ipb.avail[1]; // start of next instruction word IS 32-bit-aligned again
                     issue_engine.valid[1]  = ipb.avail[1];
                     issue_engine.data      = {issue_engine.ci_ill, ipb.rdata[1][17:16], 1'b1, issue_engine.ci_i32};
                 end else begin // unaligned uncompressed
                     issue_engine.valid = (ipb.avail[0] && ipb.avail[1]) ? '1 : '0;
                     issue_engine.data  = {1'b0, (ipb.rdata[0][17:16] | ipb.rdata[1][17:16]),
                                           1'b0,  ipb.rdata[0][15:00],  ipb.rdata[1][15:00]};
                 end
             end
         end : issue_engine_fsm_comb
     end : issue_engine_enabled
    endgenerate

    generate
     if (CPU_EXTENSION_RISCV_C == 0) begin : issue_engine_disabled
         assign issue_engine.valid = (ipb.avail[0] == 1'b1) ? '1 : '0; // only use status flags from IPB[0]
         assign issue_engine.data  = {1'b0, ipb.rdata[0][17:16], 1'b0, ipb.rdata[1][15:0], ipb.rdata[0][15:0]};
     end : issue_engine_disabled
    endgenerate
    
    /* update IPB FIFOs (ready-for-next)? */
    assign ipb.re[0] = ((issue_engine.valid[0] == 1'b1) && (execute_engine.state == DISPATCH)) ? 1'b1 : 1'b0;
    assign ipb.re[1] = ((issue_engine.valid[1] == 1'b1) && (execute_engine.state == DISPATCH)) ? 1'b1 : 1'b0;

    // Compressed Instructions Decoding ----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
     if (CPU_EXTENSION_RISCV_C == 1) begin : cellrv32_cpu_decompressor_inst_true
         cellrv32_cpu_decompressor #(
             .FPU_ENABLE (CPU_EXTENSION_RISCV_Zfinx) //  floating-point instructions enabled
         ) cellrv32_cpu_decompressor_inst (
             .ci_instr16_i (issue_engine.ci_i16), // compressed instruction input
             .ci_illegal_o (issue_engine.ci_ill), // illegal compressed instruction
             .ci_instr32_o (issue_engine.ci_i32)  // 32-bit decompressed instruction
         );
     end else begin : cellrv32_cpu_decompressor_inst_false
         assign issue_engine.ci_i32 = '0;
         assign issue_engine.ci_ill = 1'b0;
     end
    endgenerate
    
    /* 16-bit instructions: half-word select */
    assign issue_engine.ci_i16 = (issue_engine.align == 1'b0) ? ipb.rdata[0][15:0] : ipb.rdata[1][15:0];

    // ****************************************************************************************************************************
    // Instruction Execution
    // ****************************************************************************************************************************
    // Immediate Generator -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : imm_gen
     unique case (imm_opcode)
         // S-immediate: store
         opcode_store_c : begin
             imm_o[XLEN-1:11] <= (execute_engine.i_reg[31] == 1'b1) ? '1 : '0; // sign extension
             imm_o[10:05]     <= execute_engine.i_reg[30:25];
             imm_o[04:00]     <= execute_engine.i_reg[11:07];
         end
         // B-immediate: conditional branches
         opcode_branch_c : begin
             imm_o[XLEN-1:12] <= (execute_engine.i_reg[31] == 1'b1) ? '1 : '0; // sign extension
             imm_o[11]        <= execute_engine.i_reg[07];
             imm_o[10:05]     <= execute_engine.i_reg[30:25];
             imm_o[04:01]     <= execute_engine.i_reg[11:08];
             imm_o[00]        <= 1'b0;
         end
         // U-immediate: lui, auipc
         opcode_lui_c, opcode_auipc_c : begin
             imm_o[XLEN-1:12] <= execute_engine.i_reg[31:12];
             imm_o[11:00]     <= '0;
         end
         // J-immediate: unconditional jumps
         opcode_jal_c : begin
             imm_o[XLEN-1:20] <= (execute_engine.i_reg[31] == 1'b1) ? '1 : '0; // sign extension
             imm_o[19:12]     <= execute_engine.i_reg[19:12];
             imm_o[11]        <= execute_engine.i_reg[20];
             imm_o[10:01]     <= execute_engine.i_reg[30:21];
             imm_o[00]        <= 1'b0;
         end
         // I-immediate: ALU-immediate, loads, jump-and-link with register
         default: begin
             imm_o[XLEN-1:11] <= (execute_engine.i_reg[31] == 1'b1) ? '1 : '0; // sign extension
             imm_o[10:01]     <= execute_engine.i_reg[30:21];
             imm_o[00]        <= execute_engine.i_reg[20];
         end
     endcase
    end : imm_gen

    /* save some bits here - the two LSBs are always "11" for 32-bit instructions */
    assign imm_opcode = {execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c+2], 2'b11};

    // Branch Condition Check --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : branch_check
     if (execute_engine.i_reg[instr_funct3_msb_c] == 1'b0) begin // beq / bne
         execute_engine.branch_taken = cmp_i[cmp_equal_c] ^ execute_engine.i_reg[instr_funct3_lsb_c];
     end else begin // blt(u) / bge(u)
         execute_engine.branch_taken = cmp_i[cmp_less_c]  ^ execute_engine.i_reg[instr_funct3_lsb_c];
     end
    end : branch_check

    // Execute Engine FSM Sync ----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : execute_engine_fsm_sync
     if (rstn_i == 1'b0) begin
         execute_engine.state       <= BRANCHED; // reset is a branch from "somewhere"
         execute_engine.state_prev  <= BRANCHED;
         execute_engine.state_prev2 <= BRANCHED;
         execute_engine.branched    <= 1'b1; // reset is a branch from "somewhere"
         execute_engine.i_reg       <= '0;
         execute_engine.is_ci       <= 1'b0;
         execute_engine.is_ici      <= 1'b0;
         ctrl                       <= ctrl_bus_zero_c;
         execute_engine.sleep       <= 1'b0;
         execute_engine.pc_last     <= '0;
         execute_engine.pc          <= {CPU_BOOT_ADDR[XLEN-1:2], 2'b00}; // 32-bit aligned boot address
         execute_engine.next_pc     <= '0;
     end else begin
         /* execute engine arbiter */
         execute_engine.state       <= execute_engine.state_nxt;
         execute_engine.state_prev  <= execute_engine.state; // for HPMs only
         execute_engine.state_prev2 <= execute_engine.state_prev; // for HPMs only
         execute_engine.branched    <= execute_engine.branched_nxt;
         execute_engine.i_reg       <= execute_engine.i_reg_nxt;
         execute_engine.is_ci       <= execute_engine.is_ci_nxt;
         execute_engine.is_ici      <= execute_engine.is_ici_nxt;

         /* main control bus buffer */
         ctrl <= ctrl_nxt;

         /* sleep mode */
         if ((CPU_EXTENSION_RISCV_Sdext == 1) && ((debug_ctrl.running == 1'b1) || (csr.dcsr_step == 1'b1))) begin
             execute_engine.sleep <= 1'b0; // no sleep when in debug mode
         end else begin
             execute_engine.sleep <= execute_engine.sleep_nxt;
         end

         /* PC of "last executed" instruction for trap handling */
         if (execute_engine.state == EXECUTE) begin
             execute_engine.pc_last <= execute_engine.pc;
         end

         /* PC update */
         if (execute_engine.pc_we == 1'b1) begin
             if (execute_engine.pc_mux_sel == 1'b0) begin
                 execute_engine.pc <= {execute_engine.next_pc[XLEN-1:1], 1'b0}; // normal (linear) increment OR trap enter/exit
             end else begin
                 execute_engine.pc <= {alu_add_i[XLEN-1:1], 1'b0}; // jump/taken_branch
             end
         end

         /* next PC logic */
         unique case (execute_engine.state)
             // starting trap environment
             TRAP_ENTER : begin
                 if ((trap_ctrl.cause[5] == 1'b1) && (CPU_EXTENSION_RISCV_Sdext == 1)) begin // trap cause: debug mode (re-)entry
                     execute_engine.next_pc <= CPU_DEBUG_PARK_ADDR; // debug mode enter; start at "parking loop" <normal_entry>
                 end else if ((debug_ctrl.running == 1'b1) && (CPU_EXTENSION_RISCV_Sdext == 1)) begin
                     execute_engine.next_pc <= CPU_DEBUG_EXC_ADDR; // debug mode enter: start at "parking loop" <exception_entry>
                 end else begin // normal start of trap
                     execute_engine.next_pc <= {csr.mtvec[XLEN-1:2], 2'b00}; // trap enter
                 end
             end
             // leaving trap environment
             TRAP_EXIT : begin
                 if ((debug_ctrl.running == 1'b1) && (CPU_EXTENSION_RISCV_Sdext == 1)) begin // debug mode exit
                     execute_engine.next_pc <= {csr.dpc[XLEN-1:1], 1'b0}; // debug mode exit
                 end else begin // normal end of trap
                     execute_engine.next_pc <= {csr.mepc[XLEN-1:1], 1'b0}; // trap exit
                 end
             end
             // normal increment
             EXECUTE : execute_engine.next_pc <= execute_engine.pc + execute_engine.next_pc_inc; // next linear PC
             default: begin
                 // do nothing
             end
         endcase
     end
    end : execute_engine_fsm_sync

    /* PC increment for next linear instruction (+2 for compressed instr., +4 otherwise) */
    assign execute_engine.next_pc_inc[XLEN-1:4] = '0;
    assign execute_engine.next_pc_inc[3:0] = ((execute_engine.is_ci == 1'b0) || (CPU_EXTENSION_RISCV_C == 0)) ? 4'h4 : 4'h2;

    /* PC output */
    assign curr_pc_o = {execute_engine.pc[XLEN-1:1], 1'b0}; // current PC
    assign next_pc_o = {execute_engine.next_pc[XLEN-1:1], 1'b0}; // next PC
    
    // CPU Control Bus Output --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : ctrl_output
     /* register file */
     ctrl_o.rf_wb_en   = ctrl.rf_wb_en & (~trap_ctrl.exc_buf[exc_iillegal_c]); // no write if illegal instruction
     ctrl_o.rf_rs1     = execute_engine.i_reg[instr_rs1_msb_c : instr_rs1_lsb_c];
     ctrl_o.rf_rs2     = execute_engine.i_reg[instr_rs2_msb_c : instr_rs2_lsb_c];
     ctrl_o.rf_rs3     = execute_engine.i_reg[instr_rs3_msb_c : instr_rs3_lsb_c];
     ctrl_o.rf_rd      = execute_engine.i_reg[instr_rd_msb_c  : instr_rd_lsb_c ];
     ctrl_o.rf_mux     = ctrl.rf_mux;
     ctrl_o.rf_zero_we = ctrl.rf_zero_we;
     /* alu */
     ctrl_o.alu_op       = ctrl.alu_op;
     ctrl_o.alu_opa_mux  = ctrl.alu_opa_mux;
     ctrl_o.alu_opb_mux  = ctrl.alu_opb_mux;
     ctrl_o.alu_unsigned = ctrl.alu_unsigned;
     ctrl_o.alu_frm      = csr.frm;
     ctrl_o.alu_cp_trig  = ctrl.alu_cp_trig;
     /* bus interface */
     ctrl_o.bus_req    = ctrl.bus_req;
     ctrl_o.bus_mo_we  = ctrl.bus_mo_we;
     ctrl_o.bus_fence  = ctrl.bus_fence;
     ctrl_o.bus_fencei = ctrl.bus_fencei;
     //
     // effective privilege level for loads and stores in M-mode
     if (csr.mstatus_mprv == 1'b1) begin
         ctrl_o.bus_priv = csr.mstatus_mpp;
     end else begin
         ctrl_o.bus_priv = csr.privilege_eff;
     end
     //
     /* instruction word bit fields */
     ctrl_o.ir_funct3  = execute_engine.i_reg[instr_funct3_msb_c  : instr_funct3_lsb_c ];
     ctrl_o.ir_funct12 = execute_engine.i_reg[instr_funct12_msb_c : instr_funct12_lsb_c];
     ctrl_o.ir_opcode  = execute_engine.i_reg[instr_opcode_msb_c  : instr_opcode_lsb_c ];
     /* cpu status */
     ctrl_o.cpu_priv  = csr.privilege_eff; // effective privilege mode
     ctrl_o.cpu_sleep = execute_engine.sleep; // cpu is in sleep mode
     ctrl_o.cpu_trap  = trap_ctrl.env_start_ack; // cpu is starting a trap handler
     ctrl_o.cpu_debug = debug_ctrl.running; // cpu is currently in debug mode
    end : ctrl_output

    // Decoding Helper Logic ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : decode_helper
     /* defaults */
     decode_aux.is_f_op   = 1'b0;
     decode_aux.is_m_mul  = 1'b0;
     decode_aux.is_m_div  = 1'b0;
     decode_aux.is_b_imm  = 1'b0;
     decode_aux.is_b_reg  = 1'b0;
     decode_aux.is_zicond = 1'b0;
     decode_aux.rs1_zero  = 1'b0;
     decode_aux.rd_zero   = 1'b0;

     /* is BITMANIP instruction? */
     /* pretty complex as we have to check the already-crowded ALU/ALUI instruction space */
     if (CPU_EXTENSION_RISCV_B == 1) begin // BITMANIP implemented at all?
         /* register-immediate operation */
         if (((execute_engine.i_reg[instr_funct7_msb_c    : instr_funct7_lsb_c ] == 7'b0110000) && (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b001) &&
             ((execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00000)   || // CLZ
              (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00001)   || // CTZ
              (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00010)   || // CPOP
              (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00100)   || // SEXT.B
              (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00101))) || // SEXT.H
             ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0110000) && (execute_engine.i_reg[instr_funct3_msb_c    : instr_funct3_lsb_c]  == 3'b101))   ||    // RORI
             ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0010100) && (execute_engine.i_reg[instr_funct3_msb_c    : instr_funct3_lsb_c]  == 3'b101)    &&
                                                                                               (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c] == 5'b00111)) ||    // ORCB
             ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0100100) && (execute_engine.i_reg[instr_funct3_msb_c-1  : instr_funct3_lsb_c]  == 2'b01))    ||    // BCLRI / BEXTI
             ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0110100) && (execute_engine.i_reg[instr_funct3_msb_c-1  : instr_funct3_lsb_c]  == 2'b01))    ||    // REV8 / BINVI
             ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0010100) && (execute_engine.i_reg[instr_funct3_msb_c    : instr_funct3_lsb_c]  == 3'b001)))  begin // BSETI
             decode_aux.is_b_imm = 1'b1;
         end
         //
         /* register-register operation */
         if (((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0110000) && (execute_engine.i_reg[instr_funct3_msb_c-1 : instr_funct3_lsb_c] == 2'b01))  || // ROR / ROL
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000101) && (execute_engine.i_reg[instr_funct3_msb_c   : instr_funct3_lsb_c] != 3'b000)) || // MIN[U] / MAX[U] / CMUL[H/R]
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000100) && (execute_engine.i_reg[instr_funct3_msb_c   : instr_funct3_lsb_c] == 3'b100)) || // ZEXTH
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0100100) && (execute_engine.i_reg[instr_funct3_msb_c-1 : instr_funct3_lsb_c] == 2'b01))  || // BCLR / BEXT
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0110100) && (execute_engine.i_reg[instr_funct3_msb_c   : instr_funct3_lsb_c] == 3'b001)) || // BINV
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0010100) && (execute_engine.i_reg[instr_funct3_msb_c   : instr_funct3_lsb_c] == 3'b001)) || // BSET
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0100000) &&
              ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b111) ||       // ANDN
               (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b110) ||       // ORN
               (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b100))) ||    // XORN
              ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0010000) &&
              ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b010) ||       // SH1ADD
               (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b100) ||       // SH2ADD
               (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == 3'b110)))) begin // SH3ADD
             decode_aux.is_b_reg = 1'b1;
         end
     end
     
     /* floating-point operations (Zfinx) */
     if (CPU_EXTENSION_RISCV_Zfinx == 1) begin //  FPU implemented at all?
        if (((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+3] == 4'b0000))   || // FADD.S / FSUB.S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b00010)) || // FMUL.S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b11100)  && (execute_engine.i_reg[instr_funct3_msb_c    : instr_funct3_lsb_c] == 3'b001))     ||     // FCLASS.S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b00100)  && (execute_engine.i_reg[instr_funct3_msb_c] == 1'b0))                               ||     // FSGNJ[N/X].S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b00101)  && (execute_engine.i_reg[instr_funct3_msb_c    : instr_funct3_msb_c-1] == 2'b00))    ||     // FMIN.S / FMAX.S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b10100)  && (execute_engine.i_reg[instr_funct3_msb_c] == 1'b0))                               ||     // FEQ.S / FLT.S / FLE.S
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b11010)  && (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c+1] == 4'b0000)) ||     // FCVT.S.W*
            ((execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c+2] == 5'b11000)  && (execute_engine.i_reg[instr_funct12_lsb_c+4 : instr_funct12_lsb_c+1] == 4'b0000))) begin // FCVT.W*.S
            // single-precision operations only
            if ((execute_engine.i_reg[instr_funct7_lsb_c+1 : instr_funct7_lsb_c] == float_single_c)) begin
                decode_aux.is_f_op = 1'b1;
            end
        end
     end

     /* int MUL (M/Zmmul) / DIV (M) operation */
     if (execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000001) begin
         if (((CPU_EXTENSION_RISCV_M == 1) || (CPU_EXTENSION_RISCV_Zmmul == 1)) && (execute_engine.i_reg[instr_funct3_msb_c] == 1'b0)) begin
             decode_aux.is_m_mul = 1'b1;
         end
         //
         if ((CPU_EXTENSION_RISCV_M == 1) && (execute_engine.i_reg[instr_funct3_msb_c] == 1'b1)) begin
             decode_aux.is_m_div = 1'b1;
         end
     end

     /* conditional operations (Zicond) */
     if ((CPU_EXTENSION_RISCV_Zicond == 1) && 
         (execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000111) &&
         (execute_engine.i_reg[instr_funct3_msb_c] == 1'b1) && (execute_engine.i_reg[instr_funct3_lsb_c] == 1'b1)) begin
         decode_aux.is_zicond = 1'b1;
     end

     /* register/uimm5 checks */
     if (execute_engine.i_reg[instr_rs1_msb_c : instr_rs1_lsb_c] == 5'b00000) begin
         decode_aux.rs1_zero = 1'b1;
     end
     if (execute_engine.i_reg[instr_rd_msb_c : instr_rd_lsb_c] == 5'b00000) begin
         decode_aux.rd_zero = 1'b1;
     end
    end : decode_helper
    
    /* CSR access address */
    assign csr.addr = execute_engine.i_reg[instr_imm12_msb_c : instr_imm12_lsb_c];

    // Execute Engine FSM Comb -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : execute_engine_fsm_comb
     /* arbiter defaults */
     execute_engine.state_nxt    = execute_engine.state;
     execute_engine.i_reg_nxt    = execute_engine.i_reg;
     execute_engine.is_ci_nxt    = execute_engine.is_ci;
     execute_engine.is_ici_nxt   = 1'b0;
     execute_engine.sleep_nxt    = execute_engine.sleep;
     execute_engine.branched_nxt = execute_engine.branched;
     execute_engine.pc_mux_sel   = 1'b0;
     execute_engine.pc_we        = 1'b0;

     /* instruction dispatch defaults */
     fetch_engine.reset = 1'b0;

     /* trap environment control defaults */
     trap_ctrl.env_start_ack = 1'b0;
     trap_ctrl.env_end       = 1'b0;
     trap_ctrl.instr_be      = 1'b0;
     trap_ctrl.instr_ma      = 1'b0;
     trap_ctrl.env_call      = 1'b0;
     trap_ctrl.break_point   = 1'b0;
     debug_ctrl.dret         = 1'b0;

     /* CSR access defaults */
     csr.we_nxt = 1'b0;
     csr.re_nxt = 1'b0;

     /* Control defaults */
     ctrl_nxt        = ctrl_bus_zero_c; // all off by default
     ctrl_nxt.alu_op = alu_op_add_c;    // default ALU operation: ADD
     ctrl_nxt.rf_mux = rf_mux_alu_c;    // default RF input: ALU

     /* ALU sign control */
     if (execute_engine.i_reg[instr_opcode_lsb_c+4] == 1'b1) begin // ALU ops
         ctrl_nxt.alu_unsigned = execute_engine.i_reg[instr_funct3_lsb_c+0]; // unsigned ALU operation? (SLTIU, SLTU)
     end else begin // branches
         ctrl_nxt.alu_unsigned = execute_engine.i_reg[instr_funct3_lsb_c+1]; // unsigned branches? (BLTU, BGEU)
     end

     /* state machine */
     unique case (execute_engine.state)
         // --------------------------------------------------------------
         // Get new command from instruction issue engine
         DISPATCH : begin
             /* update PC and compressed instruction status flags */
             execute_engine.pc_mux_sel = 1'b0; // next PC
             execute_engine.pc_we      = ~execute_engine.branched; // update PC with next_pc if there was no actual branch
             execute_engine.is_ci_nxt  = issue_engine.data[32];    // this is a de-compressed instruction
             execute_engine.is_ici_nxt = issue_engine.data[35];    // this is an illegal compressed instruction
             //
             if ((issue_engine.valid[0] == 1'b1) || (issue_engine.valid[1] == 1'b1)) begin // instruction available?
                  /* update IR *only* if we have a new instruction word available as this register must not contain non-defined values */
                  execute_engine.i_reg_nxt = issue_engine.data[31:0]; // <has to stay here>
                  /* clear branch flipflop */
                  execute_engine.branched_nxt = 1'b0;
                  /* instruction fetch exceptions */
                  trap_ctrl.instr_ma = issue_engine.data[33] & (~CPU_EXTENSION_RISCV_C); // misaligned instruction fetch (if C disabled)
                  trap_ctrl.instr_be = issue_engine.data[34]; // bus access fault during instruction fetch
                  /* any reason to go to trap state? */
                  if ((execute_engine.sleep  == 1'b1) ||     // enter sleep state
                      (trap_ctrl.exc_fire    == 1'b1) ||     // exception during LAST instruction (e.g. illegal instruction)
                      (trap_ctrl.env_start   == 1'b1) ||     // pending trap (IRQ or late exception)
                     ((issue_engine.data[33] == 1'b1) && 
                      (CPU_EXTENSION_RISCV_C == 0))   ||     // misaligned instruction fetch address (if C disabled) during instruction fetch
                      (issue_engine.data[34] == 1'b1)) begin // bus access fault during instruction fetch
                     execute_engine.state_nxt = TRAP_ENTER;
                  end else begin
                     execute_engine.state_nxt = EXECUTE;
                  end
             end
         end
         // --------------------------------------------------------------
         // Start trap environment and get trap vector; stay here for sleep mode
         TRAP_ENTER : begin
             if (trap_ctrl.env_start == 1'b1) begin
                 trap_ctrl.env_start_ack  = 1'b1;
                 execute_engine.state_nxt = TRAP_EXECUTE;
             end
         end
         // --------------------------------------------------------------
         // Return from trap environment and get xEPC
         TRAP_EXIT : begin
             trap_ctrl.env_end        = 1'b1;
             execute_engine.state_nxt = TRAP_EXECUTE;
         end
         // --------------------------------------------------------------
         // Process trap environment
         TRAP_EXECUTE : begin
             execute_engine.pc_mux_sel = 1'b0; // next_PC (xEPC or trap vector)
             fetch_engine.reset        = 1'b1;
             execute_engine.pc_we      = 1'b1;
             execute_engine.sleep_nxt  = 1'b0; // disable sleep mode
             execute_engine.state_nxt  = BRANCHED;
         end
         // --------------------------------------------------------------
         //  Decode and execute instruction (control has to be here for exactly 1 cycle in any case!)
         EXECUTE : begin
             // [NOTE] register file is read in this stage; due to the sync read, data will be available in the _next_ state
             // ------------------------------------------------------------
             unique case (execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c])
                 // --------------------------------------------------------------
                 // register/immediate ALU operation
                 opcode_alu_c, opcode_alui_c : begin
                     /* register-immediate ALU operation */
                     if (execute_engine.i_reg[instr_opcode_msb_c-1] == 1'b0) begin
                         ctrl_nxt.alu_opb_mux = 1'b1; // use IMM as ALU.OPB
                     end
                     //
                     /*ALU core operation */
                     unique case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                         // ADD(I), SUB
                         funct3_subadd_c : begin
                             if ((execute_engine.i_reg[instr_opcode_msb_c-1] == 1'b1) && (execute_engine.i_reg[instr_funct7_msb_c-1] == 1'b1)) begin
                                 ctrl_nxt.alu_op = alu_op_sub_c; // SUB if not an immediate op and funct7.6 set
                             end else begin
                                 ctrl_nxt.alu_op = alu_op_add_c;
                             end
                         end
                         // SLT(I), SLTU(I)
                         funct3_slt_c, funct3_sltu_c : begin
                             ctrl_nxt.alu_op = alu_op_slt_c;
                         end
                         // XOR(i)
                         funct3_xor_c : begin
                             ctrl_nxt.alu_op = alu_op_xor_c;
                         end
                         // OR(i)
                         funct3_or_c : begin
                             ctrl_nxt.alu_op = alu_op_or_c;
                         end
                         // AND(I) or multi-cycle / co-processor operation
                         default: begin
                             ctrl_nxt.alu_op = alu_op_and_c;
                         end
                     endcase
                     //
                     /* EXT: co-processor MULDIV operation (multi-cycle) */
                     if (((CPU_EXTENSION_RISCV_M == 1) && (execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_alu_c[5]) &&
                         ((decode_aux.is_m_mul == 1'b1) || (decode_aux.is_m_div == 1'b1))) || // MUL/DIV
                         ((CPU_EXTENSION_RISCV_Zmmul == 1) && (execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_alu_c[5]) &&
                          (decode_aux.is_m_mul == 1'b1))) begin // MUL

                         ctrl_nxt.alu_cp_trig[cp_sel_muldiv_c] = 1'b1; // trigger MULDIV CP
                         execute_engine.state_nxt              = ALU_WAIT;
                     //
                     /* EXT: co-processor BIT-MANIPULATION operation (multi-cycle) */
                     end else if ((CPU_EXTENSION_RISCV_B == 1) &&
                                (((execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_alu_c[5])  && (decode_aux.is_b_reg == 1'b1)) || // register operation
                                 ((execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_alui_c[5]) && (decode_aux.is_b_imm == 1'b1)))) begin
                         
                         ctrl_nxt.alu_cp_trig[cp_sel_bitmanip_c] = 1'b1; // trigger BITMANIP CP
                         execute_engine.state_nxt                = ALU_WAIT;
                     //
                     /* EXT: co-processor CONDITIONAL operations (multi-cycle) */
                     end else if ((CPU_EXTENSION_RISCV_Zicond == 1) && (decode_aux.is_zicond == 1'b1) &&
                                  (execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_alu_c[5])) begin
                         
                         ctrl_nxt.alu_cp_trig[cp_sel_cond_c] = 1'b1; // trigger COND CP
                         execute_engine.state_nxt            = ALU_WAIT;
                     //
                     /* BASE: co-processor SHIFT operation (multi-cycle) */
                     end else if ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sll_c) ||
                                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sr_c)) begin
                         
                         ctrl_nxt.alu_cp_trig[cp_sel_shifter_c] = 1'b1; // trigger SHIFTER CP
                         execute_engine.state_nxt               = ALU_WAIT;
                     //
                     /* BASE: ALU CORE operation (single-cycle) */
                     end else begin
                         ctrl_nxt.rf_wb_en        = 1'b1; // valid RF write-back
                         execute_engine.state_nxt = DISPATCH;
                     end
                 end
                 // --------------------------------------------------------------
                 // load upper immediate / add upper immediate to PC
                 opcode_lui_c, opcode_auipc_c : begin
                     ctrl_nxt.alu_opa_mux = 1'b1; // ALU.OPA = PC (for AUIPC only)
                     ctrl_nxt.alu_opb_mux = 1'b1; // use IMM as ALU.OPB
                     //
                     if (execute_engine.i_reg[instr_opcode_lsb_c+5] == opcode_lui_c[5]) begin
                         ctrl_nxt.alu_op = alu_op_movb_c; // actual ALU operation = MOVB
                     end else begin // AUIPC
                         ctrl_nxt.alu_op = alu_op_add_c; // actual ALU operation = ADD
                     end
                     // 
                     ctrl_nxt.rf_wb_en        = 1'b1; // valid RF write-back
                     execute_engine.state_nxt = DISPATCH;
                 end
                 // --------------------------------------------------------------
                 // load/store
                 opcode_load_c, opcode_store_c : begin
                     ctrl_nxt.alu_opb_mux     = 1'b1; // use IMM as ALU.OPB
                     ctrl_nxt.bus_mo_we       = 1'b1; // write memory output registers (data & address)
                     execute_engine.state_nxt = MEM_REQ;
                 end
                 // --------------------------------------------------------------
                 // branch / jump and link (with register)
                 opcode_branch_c, opcode_jal_c, opcode_jalr_c : begin
                     ctrl_nxt.alu_opb_mux = 1'b1; // use IMM as ALU.OPB (branch target address offset)
                     //
                     if (execute_engine.i_reg[instr_opcode_lsb_c+3 : instr_opcode_lsb_c+2] == opcode_jalr_c[3:2]) begin // JALR
                         ctrl_nxt.alu_opa_mux = 1'b0; // use RS1 as ALU.OPA (branch target address base)
                     end else begin // JAL
                         ctrl_nxt.alu_opa_mux = 1'b1; // use PC as ALU.OPA (branch target address base)
                     end
                     // 
                     execute_engine.state_nxt = BRANCH;
                 end
                 // --------------------------------------------------------------
                 // fence operations
                 opcode_fence_c : begin
                     if (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_fence_c) begin
                         ctrl_nxt.bus_fence = 1'b1; // FENCE
                     end
                     //
                     if ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_fencei_c) && (CPU_EXTENSION_RISCV_Zifencei == 1)) begin
                         ctrl_nxt.bus_fencei = 1'b1; // FENCE.I
                     end
                     //
                     execute_engine.state_nxt = TRAP_EXECUTE; // use TRAP_EXECUTE to "modify" PC (PC <= PC)
                 end
                 // --------------------------------------------------------------
                 // floating-point operations
                 opcode_fop_c : begin
                     if (CPU_EXTENSION_RISCV_Zfinx == 1) begin
                         ctrl_nxt.alu_cp_trig[cp_sel_fpu_c] = 1'b1; // trigger FPU CP
                         execute_engine.state_nxt = ALU_WAIT;
                     end else begin
                         execute_engine.state_nxt = DISPATCH;
                     end
                 end
                 // --------------------------------------------------------------
                 // CFU: custom RISC-V instructions
                 opcode_cust0_c, opcode_cust1_c, opcode_cust2_c, opcode_cust3_c : begin
                     if (CPU_EXTENSION_RISCV_Zxcfu == 1) begin
                         ctrl_nxt.alu_cp_trig[cp_sel_cfu_c] = 1'b1; // trigger CFU CP
                         execute_engine.state_nxt = ALU_WAIT;
                     end else begin
                         execute_engine.state_nxt = DISPATCH;
                     end
                 end
                 // --------------------------------------------------------------
                 // environment operation / CSR access
                 opcode_system_c : begin
                     csr.re_nxt = 1'b1; // always read CSR, only relevant for CSR access
                     //
                     if (CPU_EXTENSION_RISCV_Zicsr == 1) begin
                         execute_engine.state_nxt = SYSTEM;
                     end else begin
                         execute_engine.state_nxt = DISPATCH;
                     end
                 end
                 // --------------------------------------------------------------
                 // illegal opcode
                 default: begin
                     execute_engine.state_nxt = DISPATCH;
                 end
             endcase
         end
         // --------------------------------------------------------------
         // wait for multi-cycle ALU operation (ALU co-processor) to finish
         ALU_WAIT : begin
             ctrl_nxt.alu_op = alu_op_cp_c;
             // wait for completion or abort on illegal instruction exception (the co-processor will also terminate operations)
             if ((alu_cp_done_i == 1'b1) || (trap_ctrl.exc_buf[exc_iillegal_c] == 1'b1)) begin
                 ctrl_nxt.rf_wb_en        = 1'b1; // valid RF write-back (won't happen in case of an illegal instruction)
                 execute_engine.state_nxt = DISPATCH;
             end
         end
         // --------------------------------------------------------------
         // update PC on taken branches and jumps
         BRANCH : begin
             /* get and store return address (only relevant for jump-and-link operations) */
             ctrl_nxt.rf_mux = rf_mux_npc_c; // next PC
             /* destination address */
             execute_engine.pc_mux_sel = 1'b1; // PC <= alu.add = branch/jump destination
             execute_engine.pc_we      = 1'b1; // update PC with destination; will be overridden again in DISPATCH if branch not taken
             //
             if ((execute_engine.i_reg[instr_opcode_lsb_c+2] == 1'b1) || (execute_engine.branch_taken == 1'b1)) begin // JAL/JALR or taken branch
                 fetch_engine.reset       = 1'b1; // reset instruction fetch starting at modified PC
                 execute_engine.state_nxt = BRANCHED;
             end else begin
                 execute_engine.state_nxt = DISPATCH;
             end
             //
             /* valid RF write-back? */
             if (execute_engine.i_reg[instr_opcode_lsb_c+2] == 1'b1) begin // is jump-and-link?
                 ctrl_nxt.rf_wb_en = 1'b1;
             end 
         end
         // --------------------------------------------------------------
         // delay cycle to wait for reset of pipeline front-end (instruction fetch)
         BRANCHED : begin
             execute_engine.branched_nxt = 1'b1; // this is an actual branch
             execute_engine.state_nxt    = DISPATCH;
             /* use this state also to (re-)initialize the register file's x0/zero register */
             if (reset_x0_c == 1) begin // if x0 is a "real" register that has to be initialized to zero
                 ctrl_nxt.rf_mux     = rf_mux_csr_c; // this will return 0 since csr.re_nxt has not been set
                 ctrl_nxt.rf_zero_we = 1'b1; // allow/force write access to x0
             end
         end
         // --------------------------------------------------------------
         // trigger memory request
         MEM_REQ : begin
             // not an illegal instruction
             if (trap_ctrl.exc_buf[exc_iillegal_c] == 1'b0) begin
                 ctrl_nxt.bus_req = 1'b1; // trigger memory request
             end
             //
             execute_engine.state_nxt = MEM_WAIT;
         end
         // --------------------------------------------------------------
         //  wait for bus transaction to finish
         MEM_WAIT : begin
             ctrl_nxt.rf_mux = rf_mux_mem_c; // memory read data
             /* wait for memory response */
             if ((trap_ctrl.exc_buf[exc_laccess_c ]  || trap_ctrl.exc_buf[exc_saccess_c] || // bus access error
                  trap_ctrl.exc_buf[exc_lalign_c  ]  || trap_ctrl.exc_buf[exc_salign_c ] || // alignment error
                  trap_ctrl.exc_buf[exc_iillegal_c]) == 1'b1) begin // illegal instruction
                 execute_engine.state_nxt = DISPATCH; // abort!
             end else if (bus_d_wait_i == 1'b0) begin // wait for bus to finish transaction
                 if (execute_engine.i_reg[instr_opcode_msb_c-1] == 1'b0) begin // load
                     ctrl_nxt.rf_wb_en = 1'b1; // data write-back
                 end 
                 //
                 execute_engine.state_nxt = DISPATCH;
             end
         end
         // --------------------------------------------------------------
         // system environment operation
         SYSTEM : begin
             ctrl_nxt.rf_mux = rf_mux_csr_c; // only relevant for CSR access
             //
             if ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_env_c) && // ENVIRONMENT
                 (trap_ctrl.exc_buf[exc_iillegal_c] == 1'b0)) begin // and NOT already identified as illegal instruction
                 execute_engine.state_nxt = DISPATCH; // default
                 //
                 unique case (execute_engine.i_reg[instr_funct12_msb_c : instr_funct12_lsb_c])
                     funct12_ecall_c  : trap_ctrl.env_call       = 1'b1; // ecall
                     funct12_ebreak_c : trap_ctrl.break_point    = 1'b1; // ebreak
                     funct12_mret_c   : execute_engine.state_nxt = TRAP_EXIT; // mret
                     funct12_dret_c   : begin
                                        execute_engine.state_nxt = TRAP_EXIT; 
                                        debug_ctrl.dret = 1'b1; // dret
                     end
                     default: begin
                                        execute_engine.sleep_nxt = 1'b1; // "funct12_wfi_c" - wfi/sleep
                     end
                 endcase
             end else begin // CSR ACCESS - no CSR will be altered if illegal instruction
                 execute_engine.state_nxt <= DISPATCH;
                 //
                 if ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_csrrw_c ) || // CSRRW:  always write CSR
                     (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_csrrwi_c) || // CSRRWI: always write CSR
                     (decode_aux.rs1_zero == 1'b0)) begin // CSRR(S/C)(I): write CSR if rs1/imm5 is NOT zero
                     csr.we_nxt = 1'b1;
                 end
                 //
                 ctrl_nxt.rf_wb_en = 1'b1; // valid RF write-back
             end
         end
         // --------------------------------------------------------------
         // undefined
         default: begin
             execute_engine.state_nxt = DISPATCH;
         end
     endcase
    end : execute_engine_fsm_comb

    // ****************************************************************************************************************************
    // Illegal Instruction and CSR Access Check
    // ****************************************************************************************************************************

    // CSR Access Check: Available at All --------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : csr_avail_check
     csr_reg_valid = 1'b0; // default: invalid access
     //
     unique case (csr.addr)
         // --------------------------------------------------------------
         /* floating-point CSRs */
         csr_fflags_c, csr_frm_c, csr_fcsr_c : begin
             csr_reg_valid = logic'(CPU_EXTENSION_RISCV_Zfinx); // valid if FPU implemented
         end
         // --------------------------------------------------------------
         // machine trap setup/handling, counters, environment & information registers
         csr_mstatus_c, csr_mstatush_c, csr_misa_c, csr_mie_c, csr_mtvec_c, 
         csr_mscratch_c, csr_mepc_c, csr_mcause_c, csr_mip_c, csr_mtval_c,
         csr_mcycle_c, csr_mcycleh_c, csr_minstret_c, csr_minstreth_c,
         csr_mcountinhibit_c, csr_mcounteren_c, csr_menvcfg_c, csr_menvcfgh_c,
         csr_mvendorid_c, csr_marchid_c, csr_mimpid_c, csr_mhartid_c, 
         csr_mconfigptr_c, csr_mxisa_c : begin
             csr_reg_valid = 1'b1;
         end
         // --------------------------------------------------------------
         // physical memory protection (PMP)
         csr_pmpaddr0_c , csr_pmpaddr1_c , csr_pmpaddr2_c , // address
         csr_pmpaddr3_c , csr_pmpaddr4_c , csr_pmpaddr5_c , // address
         csr_pmpaddr6_c , csr_pmpaddr7_c , csr_pmpaddr8_c , // address
         csr_pmpaddr9_c , csr_pmpaddr10_c, csr_pmpaddr11_c, // address
         csr_pmpaddr12_c, csr_pmpaddr13_c, csr_pmpaddr14_c, csr_pmpaddr15_c,      // configuration
         csr_pmpcfg0_c  , csr_pmpcfg1_c  , csr_pmpcfg2_c  , csr_pmpcfg3_c : begin // configuration
             csr_reg_valid = (PMP_NUM_REGIONS > 0); // valid if PMP implemented
         end
         // --------------------------------------------------------------
         // HPM counters
         csr_hpmcounter3_c   , csr_hpmcounter4_c   , csr_hpmcounter5_c   , csr_hpmcounter6_c   , csr_hpmcounter7_c   , csr_hpmcounter8_c    , // user counters LOW
         csr_hpmcounter9_c   , csr_hpmcounter10_c  , csr_hpmcounter11_c  , csr_hpmcounter12_c  , csr_hpmcounter13_c  , csr_hpmcounter14_c   ,
         csr_hpmcounter15_c  , csr_hpmcounter16_c  , csr_hpmcounter17_c  , csr_hpmcounter18_c  , csr_hpmcounter19_c  , csr_hpmcounter20_c   ,
         csr_hpmcounter21_c  , csr_hpmcounter22_c  , csr_hpmcounter23_c  , csr_hpmcounter24_c  , csr_hpmcounter25_c  , csr_hpmcounter26_c   ,
         csr_hpmcounter27_c  , csr_hpmcounter28_c  , csr_hpmcounter29_c  , csr_hpmcounter30_c  , csr_hpmcounter31_c  ,
         csr_hpmcounter3h_c  , csr_hpmcounter4h_c  , csr_hpmcounter5h_c  , csr_hpmcounter6h_c  , csr_hpmcounter7h_c  , csr_hpmcounter8h_c   , // user counters HIGH
         csr_hpmcounter9h_c  , csr_hpmcounter10h_c , csr_hpmcounter11h_c , csr_hpmcounter12h_c , csr_hpmcounter13h_c , csr_hpmcounter14h_c  ,
         csr_hpmcounter15h_c , csr_hpmcounter16h_c , csr_hpmcounter17h_c , csr_hpmcounter18h_c , csr_hpmcounter19h_c , csr_hpmcounter20h_c  ,
         csr_hpmcounter21h_c , csr_hpmcounter22h_c , csr_hpmcounter23h_c , csr_hpmcounter24h_c , csr_hpmcounter25h_c , csr_hpmcounter26h_c  ,
         csr_hpmcounter27h_c , csr_hpmcounter28h_c , csr_hpmcounter29h_c , csr_hpmcounter30h_c , csr_hpmcounter31h_c ,
         csr_mhpmcounter3_c  , csr_mhpmcounter4_c  , csr_mhpmcounter5_c  , csr_mhpmcounter6_c  , csr_mhpmcounter7_c  , csr_mhpmcounter8_c   , // machine counters LOW
         csr_mhpmcounter9_c  , csr_mhpmcounter10_c , csr_mhpmcounter11_c , csr_mhpmcounter12_c , csr_mhpmcounter13_c , csr_mhpmcounter14_c  ,
         csr_mhpmcounter15_c , csr_mhpmcounter16_c , csr_mhpmcounter17_c , csr_mhpmcounter18_c , csr_mhpmcounter19_c , csr_mhpmcounter20_c  ,
         csr_mhpmcounter21_c , csr_mhpmcounter22_c , csr_mhpmcounter23_c , csr_mhpmcounter24_c , csr_mhpmcounter25_c , csr_mhpmcounter26_c  ,
         csr_mhpmcounter27_c , csr_mhpmcounter28_c , csr_mhpmcounter29_c , csr_mhpmcounter30_c , csr_mhpmcounter31_c ,
         csr_mhpmcounter3h_c , csr_mhpmcounter4h_c , csr_mhpmcounter5h_c , csr_mhpmcounter6h_c , csr_mhpmcounter7h_c , csr_mhpmcounter8h_c  , // machine counters HIGH
         csr_mhpmcounter9h_c , csr_mhpmcounter10h_c, csr_mhpmcounter11h_c, csr_mhpmcounter12h_c, csr_mhpmcounter13h_c, csr_mhpmcounter14h_c ,
         csr_mhpmcounter15h_c, csr_mhpmcounter16h_c, csr_mhpmcounter17h_c, csr_mhpmcounter18h_c, csr_mhpmcounter19h_c, csr_mhpmcounter20h_c ,
         csr_mhpmcounter21h_c, csr_mhpmcounter22h_c, csr_mhpmcounter23h_c, csr_mhpmcounter24h_c, csr_mhpmcounter25h_c, csr_mhpmcounter26h_c ,
         csr_mhpmcounter27h_c, csr_mhpmcounter28h_c, csr_mhpmcounter29h_c, csr_mhpmcounter30h_c, csr_mhpmcounter31h_c,
         csr_mhpmevent3_c    , csr_mhpmevent4_c    , csr_mhpmevent5_c    , csr_mhpmevent6_c    , csr_mhpmevent7_c    , csr_mhpmevent8_c     , // event configuration
         csr_mhpmevent9_c    , csr_mhpmevent10_c   , csr_mhpmevent11_c   , csr_mhpmevent12_c   , csr_mhpmevent13_c   , csr_mhpmevent14_c    ,
         csr_mhpmevent15_c   , csr_mhpmevent16_c   , csr_mhpmevent17_c   , csr_mhpmevent18_c   , csr_mhpmevent19_c   , csr_mhpmevent20_c    ,
         csr_mhpmevent21_c   , csr_mhpmevent22_c   , csr_mhpmevent23_c   , csr_mhpmevent24_c   , csr_mhpmevent25_c   , csr_mhpmevent26_c    ,
         csr_mhpmevent27_c   , csr_mhpmevent28_c   , csr_mhpmevent29_c   , csr_mhpmevent30_c   , csr_mhpmevent31_c : begin
             csr_reg_valid = logic'(CPU_EXTENSION_RISCV_Zihpm); // valid if Zihpm implemented
         end
         // --------------------------------------------------------------
         // counter and timer CSRs
         csr_cycle_c, csr_cycleh_c, csr_instret_c, csr_instreth_c : begin
             csr_reg_valid = logic'(CPU_EXTENSION_RISCV_Zicntr); // valid if Zicntr implemented
         end
         // --------------------------------------------------------------
         // debug-mode CSRs
         csr_dcsr_c, csr_dpc_c, csr_dscratch0_c : begin
             csr_reg_valid = logic'(CPU_EXTENSION_RISCV_Sdext); // valid if debug-mode implemented
         end
         // --------------------------------------------------------------
         // trigger module CSRs
         csr_tselect_c  , csr_tdata1_c , csr_tdata2_c   , 
         csr_tdata3_c   , csr_tinfo_c  , csr_tcontrol_c , 
         csr_mcontext_c , csr_scontext_c : begin
             csr_reg_valid = logic'(CPU_EXTENSION_RISCV_Sdtrig); // valid if trigger module implemented
         end
         // --------------------------------------------------------------
         // undefined / not implemented
         default: begin
             csr_reg_valid = 1'b0; // invalid access
         end
     endcase
    end : csr_avail_check

    // CSR Access Check: R/W Capabilities --------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : csr_rw_check
     if ((csr.addr[11:10] == 2'b11) && // CSR is read-only
        /* is this CSR instruction really going to write to the CSR? */
        ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_csrrw_c ) || // always write CSR
         (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_csrrwi_c) || // always write CSR
         (decode_aux.rs1_zero == 1'b0))) begin // clear/set: write CSR if rs1/imm5 is NOT zero
         csr_rw_valid = 1'b0; // invalid access
     end else begin
         csr_rw_valid = 1'b1; // access granted
     end
    end : csr_rw_check

    // CSR Access Check: Privilege Level ---------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : csr_priv_check
     if ((CPU_EXTENSION_RISCV_Sdext == 1) && (debug_ctrl.running == 1'b0) && // debug-mode implemented but not running?
        ((csr.addr == csr_dcsr_c) || (csr.addr == csr_dpc_c) || (csr.addr == csr_dscratch0_c))) begin // debug-mode-only CSR?
         csr_priv_valid = 1'b0; // invalid access
     end else if ((csr.addr[9:8] != 2'b00) && (csr.privilege_eff == 1'b0)) begin
         csr_priv_valid = 1'b0; // invalid access
     end else begin
         csr_priv_valid = 1'b1; // access granted
     end
    end : csr_priv_check

    // Illegal Instruction Check -----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : illegal_instruction_check
     /* defaults */
     illegal_cmd = 1'b0;
     illegal_reg = 1'b0;

     /* check instruction word encoding and side effects */
     unique case (execute_engine.i_reg[instr_opcode_msb_c : instr_opcode_lsb_c])
         // --------------------------------------------------------------
         // LUI, UIPC, JAL (only check actual OPCODE)
         opcode_lui_c, opcode_auipc_c, opcode_jal_c : begin
             illegal_cmd = 1'b0;
             illegal_reg = execute_engine.i_reg[instr_rd_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check JALR.funct3
         opcode_jalr_c : begin
             case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                 3'b000 : illegal_cmd = 1'b0;
                 default: begin
                          illegal_cmd = 1'b1;
                 end
             endcase
             //
             illegal_reg = execute_engine.i_reg[instr_rs1_msb_c] | execute_engine.i_reg[instr_rd_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check BRANCH.funct3
         opcode_branch_c : begin
             case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                 funct3_beq_c, funct3_bne_c , funct3_blt_c,
                 funct3_bge_c, funct3_bltu_c, funct3_bgeu_c : illegal_cmd = 1'b0;
                 default: begin
                     illegal_cmd = 1'b1;
                 end
             endcase
             //  
             illegal_reg = execute_engine.i_reg[instr_rs2_msb_c] | execute_engine.i_reg[instr_rs1_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check LOAD.funct3
         opcode_load_c : begin
             case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                 funct3_lb_c , funct3_lh_c, funct3_lw_c, 
                 funct3_lbu_c, funct3_lhu_c : illegal_cmd = 1'b0;
                 default: begin
                     illegal_cmd = 1'b1;
                 end
             endcase
             //
             illegal_reg = execute_engine.i_reg[instr_rs1_msb_c] | execute_engine.i_reg[instr_rd_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check STORE.funct3
         opcode_store_c : begin
             case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                 funct3_sb_c, funct3_sh_c, funct3_sw_c : illegal_cmd = 1'b0;
                 default: begin
                     illegal_cmd = 1'b1;
                 end
             endcase
             //
             illegal_reg = execute_engine.i_reg[instr_rs2_msb_c] | execute_engine.i_reg[instr_rs1_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check ALU.funct3 & ALU.funct7
         opcode_alu_c : begin
             if (((((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_subadd_c) || (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sr_c)) &&
                    (execute_engine.i_reg[instr_funct7_msb_c-2 : instr_funct7_lsb_c] == 5'b00000) && (execute_engine.i_reg[instr_funct7_msb_c] == 1'b0)) ||
                  (((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sll_c) ||
                    (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_slt_c) ||
                    (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sltu_c) ||
                    (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_xor_c) ||
                    (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_or_c) ||
                    (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_and_c)) &&
                    (execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000000))) || // valid base ALU instruction?
            (((CPU_EXTENSION_RISCV_M == 1) || (CPU_EXTENSION_RISCV_Zmmul == 1)) && (decode_aux.is_m_mul == 1'b1)) || // valid MUL instruction?
            ((CPU_EXTENSION_RISCV_M == 1) && (decode_aux.is_m_div == 1'b1)) || // valid DIV instruction?
            ((CPU_EXTENSION_RISCV_B == 1) && (decode_aux.is_b_reg == 1'b1)) || // valid BITMANIP register instruction?
            ((CPU_EXTENSION_RISCV_Zicond == 1) && (decode_aux.is_zicond == 1'b1))) begin // valid CONDITIONAL instruction?
                 illegal_cmd = 1'b0;
             end else begin
                 illegal_cmd = 1'b1;
             end
             //
             illegal_reg = execute_engine.i_reg[instr_rd_msb_c] | execute_engine.i_reg[instr_rs1_msb_c] | execute_engine.i_reg[instr_rs2_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check ALU.funct3 & ALU.funct7
         opcode_alui_c : begin
             if (((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_subadd_c) ||
                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_slt_c) ||
                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sltu_c) ||
                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_xor_c) ||
                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_or_c) ||
                  (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_and_c) ||
                  ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sll_c) &&
                   (execute_engine.i_reg[instr_funct7_msb_c : instr_funct7_lsb_c] == 7'b0000000)) ||
                  ((execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_sr_c) &&
                   ((execute_engine.i_reg[instr_funct7_msb_c-2 : instr_funct7_lsb_c] == 5'b00000) && (execute_engine.i_reg[instr_funct7_msb_c] == 1'b0)))) || // valid base ALUI instruction?
                 ((CPU_EXTENSION_RISCV_B == 1) && (decode_aux.is_b_imm == 1'b1))) begin
                 illegal_cmd = 1'b0;
             end else begin
                 illegal_cmd = 1'b1;
             end
             //
             illegal_reg = execute_engine.i_reg[instr_rs1_msb_c] | execute_engine.i_reg[instr_rd_msb_c]; // illegal 'E' register?
         end
         // --------------------------------------------------------------
         // check FENCE.funct3, ignore all remaining bit-fields
         opcode_fence_c : begin
             case (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c])
                 funct3_fence_c  : illegal_cmd = 1'b0; // FENCE
                 funct3_fencei_c : illegal_cmd = ~(logic'(CPU_EXTENSION_RISCV_Zifencei)); // FENCE.I
                 default: begin
                                   illegal_cmd = 1'b1;
                 end
             endcase
         end
         // --------------------------------------------------------------
         // check system instructions
         opcode_system_c : begin
             if (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_env_c) begin // system environment
                 if ((decode_aux.rs1_zero == 1'b1) && (decode_aux.rd_zero == 1'b1)) begin
                     case (execute_engine.i_reg[instr_funct12_msb_c : instr_funct12_lsb_c])
                         funct12_ecall_c, funct12_ebreak_c : illegal_cmd = 1'b0; // ECALL, EBREAK
                         funct12_mret_c                    : illegal_cmd = ~csr.privilege; // MRET (only allowed in ACTUAL M-mode)
                         funct12_wfi_c                     : illegal_cmd = (~csr.privilege) & csr.mstatus_tw; // WFI (only allowed in ACTUAL M-mode or if mstatus.TW = 0)
                         funct12_dret_c                    : illegal_cmd = ~debug_ctrl.running; // DRET (only allowed in D-mode)
                         default: begin
                                                             illegal_cmd = 1'b1;
                         end
                     endcase
                 end else begin
                     illegal_cmd = 1'b1;
                 end
             end else if ((csr_reg_valid == 1'b0) || (csr_rw_valid == 1'b0) || (csr_priv_valid == 1'b0) || // invalid CSR access?
                          (execute_engine.i_reg[instr_funct3_msb_c : instr_funct3_lsb_c] == funct3_csril_c)) begin
                 illegal_cmd = 1'b1;
             end else begin
                 illegal_cmd = 1'b0;
             end
             //
             /* illegal E-CPU register? */
             if (execute_engine.i_reg[instr_funct3_msb_c] == 1'b0) begin // reg-reg CSR (or ENV where rd=rs1=zero)
                 illegal_reg = execute_engine.i_reg[instr_rd_msb_c] | execute_engine.i_reg[instr_rs1_msb_c];
             end else begin // reg-imm CSR
                 illegal_reg = execute_engine.i_reg[instr_rd_msb_c];
             end
         end
         // --------------------------------------------------------------
         // floating point operations - single/dual operands
         opcode_fop_c : begin
             if ((CPU_EXTENSION_RISCV_Zfinx == 1) && (decode_aux.is_f_op == 1'b1)) begin // is supported floating-point instruction
                 illegal_cmd = 1'b0;
                 illegal_reg = execute_engine.i_reg[instr_rs2_msb_c] | execute_engine.i_reg[instr_rs1_msb_c] | execute_engine.i_reg[instr_rd_msb_c]; // illegal 'E' register?
             end else begin
                 illegal_cmd = 1'b1;
                 illegal_reg = 1'b0;
             end
         end
         // --------------------------------------------------------------
         // custom instructions (CFU)
         opcode_cust0_c, opcode_cust1_c, opcode_cust2_c, opcode_cust3_c : begin
             illegal_cmd = ~(logic'(CPU_EXTENSION_RISCV_Zxcfu)); // CFU extension implemented?
             illegal_reg = 1'b0; // custom instruction do not trap if a register above x15 is used when E ISA extension is enabled
         end
         // --------------------------------------------------------------
         // undefined/illegal opcode
         default: begin
             illegal_cmd = 1'b1;
         end
     endcase
    end : illegal_instruction_check

    // Illegal Operation Check -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // check in EXECUTE state: any illegal instruction processing condition? --
    assign trap_ctrl.instr_il = ((execute_engine.state == EXECUTE) || (execute_engine.state == ALU_WAIT)) ? // evaluate in execution stages only
                                 (illegal_cmd | alu_exc_i | // illegal instruction or ALU processing exception
                                 (CPU_EXTENSION_RISCV_E & illegal_reg) | // illegal register access in E extension
                                 (CPU_EXTENSION_RISCV_C & execute_engine.is_ici)) // illegal compressed instruction
                                 : 1'b0;

    // ****************************************************************************************************************************
    // Trap Controller for Interrupts and Exceptions
    // ****************************************************************************************************************************

    // Trap Buffer -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : trap_buffer
      if (rstn_i == 1'b0) begin
          trap_ctrl.exc_buf = '0;
          trap_ctrl.irq_pnd = '0;
          trap_ctrl.irq_buf = '0;
      end else begin
          // Exception Buffer -----------------------------------------------------
          // If several exception sources trigger at once, all the requests will
          // stay active until the trap environment is started. Only the exception
          // with highest priority will be used to update the MCAUSE CSR.
          // ----------------------------------------------------------------------
 
           /* misaligned load/store/instruction address */
          trap_ctrl.exc_buf[exc_lalign_c] <= (trap_ctrl.exc_buf[exc_lalign_c] | ma_load_i)          & (~trap_ctrl.env_start_ack);
          trap_ctrl.exc_buf[exc_salign_c] <= (trap_ctrl.exc_buf[exc_salign_c] | ma_store_i)         & (~trap_ctrl.env_start_ack);
          trap_ctrl.exc_buf[exc_ialign_c] <= (trap_ctrl.exc_buf[exc_ialign_c] | trap_ctrl.instr_ma) & (~trap_ctrl.env_start_ack);
 
           /* load/store/instruction bus access error */
          trap_ctrl.exc_buf[exc_laccess_c] <= (trap_ctrl.exc_buf[exc_laccess_c] | be_load_i)          & (~trap_ctrl.env_start_ack);
          trap_ctrl.exc_buf[exc_saccess_c] <= (trap_ctrl.exc_buf[exc_saccess_c] | be_store_i)         & (~trap_ctrl.env_start_ack);
          trap_ctrl.exc_buf[exc_iaccess_c] <= (trap_ctrl.exc_buf[exc_iaccess_c] | trap_ctrl.instr_be) & (~trap_ctrl.env_start_ack);
 
           /* illegal instruction & environment call */
          trap_ctrl.exc_buf[exc_envcall_c]  <= (trap_ctrl.exc_buf[exc_envcall_c ] | trap_ctrl.env_call) & (~trap_ctrl.env_start_ack);
          trap_ctrl.exc_buf[exc_iillegal_c] <= (trap_ctrl.exc_buf[exc_iillegal_c] | trap_ctrl.instr_il) & (~trap_ctrl.env_start_ack);
 
           /* break point */
          if (CPU_EXTENSION_RISCV_Sdext == 1) begin
              trap_ctrl.exc_buf[exc_break_c] <= (~trap_ctrl.env_start_ack) & (trap_ctrl.exc_buf[exc_break_c] |
                                                (hw_trigger_fire & (~csr.tdata1_action)) | // trigger module fires and enter-debug is disabled
                                                (trap_ctrl.break_point & ( csr.privilege) & (~csr.dcsr_ebreakm) & (~debug_ctrl.running)) | // enter M-mode handler on ebreak in M-mode
                                                (trap_ctrl.break_point & (~csr.privilege) & (~csr.dcsr_ebreaku) & (~debug_ctrl.running))); // enter M-mode handler on ebreak in U-mode
          end else begin
              trap_ctrl.exc_buf[exc_break_c] <= (trap_ctrl.exc_buf[exc_break_c] | trap_ctrl.break_point | hw_trigger_fire) & (~trap_ctrl.env_start_ack);
          end
 
           /* debug-mode entry */
          if (CPU_EXTENSION_RISCV_Sdext == 1) begin
              trap_ctrl.exc_buf[exc_db_break_c] <= (trap_ctrl.exc_buf[exc_db_break_c] | debug_ctrl.trig_break) & (~trap_ctrl.env_start_ack);
              trap_ctrl.exc_buf[exc_db_hw_c]    <= (trap_ctrl.exc_buf[exc_db_hw_c]    | debug_ctrl.trig_hw)    & (~trap_ctrl.env_start_ack);
          end else begin
              trap_ctrl.exc_buf[exc_db_break_c] <= 1'b0;
              trap_ctrl.exc_buf[exc_db_hw_c]    <= 1'b0;
          end
          //
          // Interrupt Pending Buffer ---------------------------------------------
          // Once triggered, the fast interrupt requests stay active until
          // explicitly cleared via the MIP CSR.
          // ----------------------------------------------------------------------
 
           /* RISC-V machine interrupts */
          trap_ctrl.irq_pnd[irq_msi_irq_c] <= msw_irq_i;
          trap_ctrl.irq_pnd[irq_mei_irq_c] <= mext_irq_i;
          trap_ctrl.irq_pnd[irq_mti_irq_c] <= mtime_irq_i;
          
          /* CELLRV32-specific fast interrupts */
          for (int i = 0; i <= 15; ++i) begin
             trap_ctrl.irq_pnd[irq_firq_0_c+i] <= (trap_ctrl.irq_pnd[irq_firq_0_c+i] & csr.mip_firq_nclr[i]) | firq_i[i];
          end // i
          
         /* debug-mode entry */
         trap_ctrl.irq_pnd[irq_db_halt_c] <= 1'b0; // unused
         trap_ctrl.irq_pnd[irq_db_step_c] <= 1'b0; // unused

         // Interrupt Masking Buffer ---------------------------------------------
         // Masking of interrupt request lines. Furthermore, this buffer ensures
         // that an *active* interrupt request line *stays* active (even if
         // disabled via MIE) if the trap environment is *currently* starting.
         // ----------------------------------------------------------------------

         /* RISC-V machine interrupts */
         trap_ctrl.irq_buf[irq_msi_irq_c] <= (trap_ctrl.irq_pnd[irq_msi_irq_c] & csr.mie_msi) | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_msi_irq_c]);
         trap_ctrl.irq_buf[irq_mei_irq_c] <= (trap_ctrl.irq_pnd[irq_mei_irq_c] & csr.mie_mei) | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_mei_irq_c]);
         trap_ctrl.irq_buf[irq_mti_irq_c] <= (trap_ctrl.irq_pnd[irq_mti_irq_c] & csr.mie_mti) | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_mti_irq_c]);

         /* CELLRV32-specific fast interrupts */
         for (int i = 0; i <= 15; ++i) begin
             trap_ctrl.irq_buf[irq_firq_0_c+i] <= (trap_ctrl.irq_pnd[irq_firq_0_c+i] & csr.mie_firq[i]) | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_firq_0_c+i]);
         end // i

         /* debug-mode entry */
         if (CPU_EXTENSION_RISCV_Sdext == 1) begin
             trap_ctrl.irq_buf[irq_db_halt_c] <= debug_ctrl.trig_halt | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_db_halt_c]);
             trap_ctrl.irq_buf[irq_db_step_c] <= debug_ctrl.trig_step | (trap_ctrl.env_start & trap_ctrl.irq_buf[irq_db_step_c]);
         end else begin
             trap_ctrl.irq_buf[irq_db_halt_c] <= 1'b0;
             trap_ctrl.irq_buf[irq_db_step_c] <= 1'b0;
         end
      end
    end : trap_buffer

    // Trap Controller ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : trap_controller
      if (rstn_i == 1'b0) begin
         trap_ctrl.env_start <= 1'b0;
      end else begin
         if (trap_ctrl.env_start == 1'b0) begin // no started trap handler yet
             if (((trap_ctrl.exc_fire == 1'b1)) || // exception firing
                  // trigger IRQ only in EXECUTE or TRAP_ENTER (e.g. during sleep) state to continue execution even on permanent interrupt request
                 ((trap_ctrl.irq_fire == 1'b1) && ((execute_engine.state == EXECUTE) || (execute_engine.state == TRAP_ENTER)))) begin
                 trap_ctrl.env_start <= 1'b1; // now execute engine can start trap handler
             end
         end else begin // trap environment ready to start
             if (trap_ctrl.env_start_ack == 1'b1) begin // start of trap handler acknowledged by execute engine
                 trap_ctrl.env_start <= 1'b0;
             end
         end
      end
    end : trap_controller
    
    // Trap Trigger ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* any exception? */
    assign trap_ctrl.exc_fire = ((|trap_ctrl.exc_buf) == 1'b1) ? 1'b1 : 1'b0; // sync. exceptions CANNOT be masked

    /* any interrupt? */
    assign trap_ctrl.irq_fire = ((
                                 ((|trap_ctrl.irq_buf[irq_firq_15_c : irq_msi_irq_c]) == 1'b1) && // pending IRQ
                                 ((csr.mstatus_mie == 1'b1) || (csr.privilege == priv_mode_u_c)) && // take IRQ when in M-mode and MIE=1 OR when in U-mode
                                 (debug_ctrl.running == 1'b0) && // no machine IRQs when in debug-mode
                                 (csr.dcsr_step == 1'b0) // no machine IRQs when in single-stepping mode
                                ) ||
                                (trap_ctrl.irq_buf[irq_db_step_c] == 1'b1) || // debug-mode single-step IRQ
                                (trap_ctrl.irq_buf[irq_db_halt_c] == 1'b1)) ? 1'b1 : 1'b0;

    /* exception program counter (for updating xCAUSE CSRs) */
    assign trap_ctrl.epc = (((trap_ctrl.cause[$bits(trap_ctrl.cause)-1]) == 1'b1) || (trap_ctrl.cause == trap_iba_c)) ?
                             {execute_engine.pc[XLEN-1 : 1], 1'b0} : {execute_engine.pc_last[XLEN-1 : 1], 1'b0};

    //  Trap Priority Encoder ---------------------------------------------------------------------
    //  -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : trap_encoder
                         /* standard RISC-V exceptions */
      trap_ctrl.cause <= (trap_ctrl.exc_buf[exc_ialign_c ]   == 1'b1) ? trap_ima_c : // instruction address misaligned
                         (trap_ctrl.exc_buf[exc_iaccess_c]   == 1'b1) ? trap_iba_c : // instruction access fault
                         (trap_ctrl.exc_buf[exc_iillegal_c]  == 1'b1) ? trap_iil_c : // illegal instruction
                         (trap_ctrl.exc_buf[exc_envcall_c]   == 1'b1) ? {trap_env_c[06:02], csr.privilege, csr.privilege} : // environment call (U/M)
                         (trap_ctrl.exc_buf[exc_break_c]     == 1'b1) ? trap_brk_c : // breakpoint
                         (trap_ctrl.exc_buf[exc_salign_c]    == 1'b1) ? trap_sma_c : // store address misaligned
                         (trap_ctrl.exc_buf[exc_lalign_c]    == 1'b1) ? trap_lma_c : // load address misaligned
                         (trap_ctrl.exc_buf[exc_saccess_c]   == 1'b1) ? trap_sbe_c : // store access fault
                         (trap_ctrl.exc_buf[exc_laccess_c]   == 1'b1) ? trap_lbe_c : // load access fault
                         /* debug mode exceptions and interrupts */
                         (trap_ctrl.irq_buf[irq_db_halt_c]   == 1'b1) ? trap_db_halt_c  : // external halt request (async)
                         (trap_ctrl.exc_buf[exc_db_hw_c]     == 1'b1) ? trap_db_trig_c  : // hardware trigger (sync)
                         (trap_ctrl.exc_buf[exc_db_break_c]  == 1'b1) ? trap_db_break_c : // break instruction (sync)
                         (trap_ctrl.irq_buf[irq_db_step_c]   == 1'b1) ? trap_db_step_c  : // single stepping (async)
                         /* CELLRV32-specific fast interrupts */
                         (trap_ctrl.irq_buf[irq_firq_0_c]    == 1'b1) ? trap_firq0_c  : // fast interrupt channel 0
                         (trap_ctrl.irq_buf[irq_firq_1_c]    == 1'b1) ? trap_firq1_c  : // fast interrupt channel 1
                         (trap_ctrl.irq_buf[irq_firq_2_c]    == 1'b1) ? trap_firq2_c  : // fast interrupt channel 2
                         (trap_ctrl.irq_buf[irq_firq_3_c]    == 1'b1) ? trap_firq3_c  : // fast interrupt channel 3
                         (trap_ctrl.irq_buf[irq_firq_4_c]    == 1'b1) ? trap_firq4_c  : // fast interrupt channel 4
                         (trap_ctrl.irq_buf[irq_firq_5_c]    == 1'b1) ? trap_firq5_c  : // fast interrupt channel 5
                         (trap_ctrl.irq_buf[irq_firq_6_c]    == 1'b1) ? trap_firq6_c  : // fast interrupt channel 6
                         (trap_ctrl.irq_buf[irq_firq_7_c]    == 1'b1) ? trap_firq7_c  : // fast interrupt channel 7
                         (trap_ctrl.irq_buf[irq_firq_8_c]    == 1'b1) ? trap_firq8_c  : // fast interrupt channel 8
                         (trap_ctrl.irq_buf[irq_firq_9_c]    == 1'b1) ? trap_firq9_c  : // fast interrupt channel 9
                         (trap_ctrl.irq_buf[irq_firq_10_c]   == 1'b1) ? trap_firq10_c : // fast interrupt channel 10
                         (trap_ctrl.irq_buf[irq_firq_11_c]   == 1'b1) ? trap_firq11_c : // fast interrupt channel 11
                         (trap_ctrl.irq_buf[irq_firq_12_c]   == 1'b1) ? trap_firq12_c : // fast interrupt channel 12
                         (trap_ctrl.irq_buf[irq_firq_13_c]   == 1'b1) ? trap_firq13_c : // fast interrupt channel 13
                         (trap_ctrl.irq_buf[irq_firq_14_c]   == 1'b1) ? trap_firq14_c : // fast interrupt channel 14
                         (trap_ctrl.irq_buf[irq_firq_15_c]   == 1'b1) ? trap_firq15_c : // fast interrupt channel 15
                         /* standard RISC-V interrupts */
                         (trap_ctrl.irq_buf[irq_mei_irq_c]   == 1'b1) ? trap_mei_c : // machine external interrupt (MEI)
                         (trap_ctrl.irq_buf[irq_msi_irq_c]   == 1'b1) ? trap_msi_c : // machine SW interrupt (MSI)
                         (trap_ctrl.irq_buf[irq_mti_irq_c]   == 1'b1) ? trap_mti_c : // machine timer interrupt (MTI)
                         trap_mti_c; // don't care
    end : trap_encoder

    // ****************************************************************************************************************************
    // Control and Status Registers (CSRs)
    // ****************************************************************************************************************************

    // Control and Status Registers - Write Data -------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : csr_write_data
      logic [XLEN-1:00] tmp_v;
      // body
      /* immediate/register operand */
      if (execute_engine.i_reg[instr_funct3_msb_c] == 1'b1) begin
         tmp_v = '0;
         tmp_v[04:00] = execute_engine.i_reg[19:15]; // uimm5
      end else begin
         tmp_v = rs1_i;
      end
      
      /* tiny ALU to compute CSR write data */
      unique case (execute_engine.i_reg[instr_funct3_msb_c-1 : instr_funct3_lsb_c])
         2'b10 : csr.wdata = csr.rdata | tmp_v;     // set
         2'b11 : csr.wdata = csr.rdata & (~tmp_v); // clear
         default: begin
                 csr.wdata = tmp_v; // write
         end
      endcase
    end : csr_write_data

    // Control and Status Registers - Write Access -----------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : csr_write_access
      if (rstn_i == 1'b0) begin
         csr.we                <= 1'b0;
         //
         csr.privilege         <= priv_mode_m_c; // start in MACHINE mode
         csr.mstatus_mie       <= 1'b0;
         csr.mstatus_mpie      <= 1'b0;
         csr.mstatus_mpp       <= 1'b0;
         csr.mstatus_mprv      <= 1'b0;
         csr.mstatus_tw        <= 1'b0;
         csr.mie_msi           <= 1'b0;
         csr.mie_mei           <= 1'b0;
         csr.mie_mti           <= 1'b0;
         csr.mie_firq          <= '0;
         csr.mtvec             <= '0;
         csr.mscratch          <= 32'h19880704;
         csr.mepc              <= '0;
         csr.mcause            <= '0;
         csr.mtval             <= '0;
         //
         csr.mip_firq_nclr     <= '0;
         //
         csr.pmpcfg            <= '0;
         csr.pmpaddr           <= '0;
         //
         csr.mhpmevent         <= '0;
         //
         csr.mcountinhibit_cy  <= 1'b0;
         csr.mcountinhibit_ir  <= 1'b0;
         csr.mcountinhibit_hpm <= '0;
         //
         csr.fflags            <= '0;
         csr.frm               <= '0;
         //
         csr.dcsr_ebreakm      <= 1'b0;
         csr.dcsr_ebreaku      <= 1'b0;
         csr.dcsr_step         <= 1'b0;
         csr.dcsr_prv          <= priv_mode_m_c;
         csr.dcsr_cause        <= '0;
         csr.dpc               <= '0;
         csr.dscratch0         <= '0;
         //
         csr.tdata1_exe        <= 1'b0;
         csr.tdata1_action     <= 1'b0;
         csr.tdata1_dmode      <= 1'b0;
         csr.tdata2            <= '0;
      end else begin
         /* write access? */
         csr.we <= csr.we_nxt & (~trap_ctrl.exc_buf[exc_iillegal_c]); // write if not illegal instruction

         /* defaults */
         csr.mip_firq_nclr <= '1; // active low

         if (CPU_EXTENSION_RISCV_Zicsr == 1) begin
             // ********************************************************************************
             // Manual CSR access by application software
             // ********************************************************************************
             if (csr.we == 1'b1) begin // manual write access and not illegal instruction
                 // ----------------------------------------------------------------------
                 /* user floating-point CSRs */
                 if (CPU_EXTENSION_RISCV_Zfinx == 1) begin // floating point CSR class
                     if (csr.addr[11:02] == csr_class_float_c) begin
                         if (csr.addr[1:0] == 2'b01) begin // R/W: fflags - floating-point (FPU) exception flags
                             csr.fflags <= csr.wdata[4:0];
                         end else if (csr.addr[1:0] == 2'b10) begin // R/W: frm - floating-point (FPU) rounding mode
                             csr.frm  <= csr.wdata[2:0];
                         end else if (csr.addr[1:0] == 2'b11) begin // R/W: fcsr - floating-point (FPU) control/status (frm + fflags)
                             csr.frm    <= csr.wdata[7:5];
                             csr.fflags <= csr.wdata[4:0];
                         end
                     end
                 end
                 // ----------------------------------------------------------------------
                 // machine trap setup
                 if (csr.addr[11:3] == csr_class_setup_c) begin // trap setup CSR class
                     /* R/W: mstatus - machine status register */
                     if (csr.addr[2:0] == csr_mstatus_c[2:0]) begin
                         csr.mstatus_mie  <= csr.wdata[03];
                         csr.mstatus_mpie <= csr.wdata[07];
                         // user mode implemented
                         if (CPU_EXTENSION_RISCV_U == 1) begin
                             csr.mstatus_mpp  <= csr.wdata[11] | csr.wdata[12]; // everything /= U will fall back to M
                             csr.mstatus_mprv <= csr.wdata[17];
                             csr.mstatus_tw   <= csr.wdata[21];
                         end
                     end
                     /* R/W: mie - machine interrupt enable register */
                     if (csr.addr[2:0] == csr_mie_c[2:0]) begin
                         csr.mie_msi  <= csr.wdata[03]; // machine SW IRQ enable
                         csr.mie_mti  <= csr.wdata[07]; // machine TIMER IRQ enable
                         csr.mie_mei  <= csr.wdata[11]; // machine EXT IRQ enable
                         csr.mie_firq <= csr.wdata[31:16]; // fast interrupt channels 0..15
                     end
                     /* R/W: mtvec - machine trap-handler base address (for ALL exceptions) */
                     if (csr.addr[2:0] == csr_mtvec_c[2:0]) begin
                         csr.mtvec <= {csr.wdata[XLEN-1 : 2], 2'b00}; // mtvec.MODE=0
                     end
                 end 
                 // ----------------------------------------------------------------------
                 // machine trap handling
                 if (csr.addr[11:4] == csr_class_trap_c) begin // machine trap handling CSR class
                     /* R/W: mscratch - machine scratch register */
                     if (csr.addr[3:0] == csr_mscratch_c[3:0]) begin
                         csr.mscratch <= csr.wdata;
                     end
                     /* R/W: mepc - machine exception program counter */
                     if (csr.addr[3:0] == csr_mepc_c[3:0]) begin
                         csr.mepc <= csr.wdata;
                     end
                     /* R/W: mcause - machine trap cause */
                     if (csr.addr[3:0] == csr_mcause_c[3:0]) begin
                         csr.mcause <= {csr.wdata[31], csr.wdata[4:0]}; // type (async/sync) & identifier
                     end
                     /* R/W: mtval - machine trap value */
                     if (csr.addr[3:0] == csr_mtval_c[3:0]) begin
                         csr.mtval <= csr.wdata;
                     end
                     /* R/C: mip - machine interrupt pending */
                     if (csr.addr[3:0] == csr_mip_c[3:0]) begin
                         csr.mip_firq_nclr <= csr.wdata[31:16]; // set low to clear according bit (FIRQs only)
                     end
                 end
                 // ----------------------------------------------------------------------
                 // machine physical memory protection
                 if (PMP_NUM_REGIONS > 0) begin
                     /* R/W: pmpcfg* - PMP configuration registers */
                     if (csr.addr[11:2] == csr_class_pmpcfg_c) begin // pmp configuration CSR class
                         for (int i = 0; i < PMP_NUM_REGIONS; ++i) begin
                             if (csr.addr[1:0] == (i/4)) begin
                                 if (csr.pmpcfg[i][7] == 1'b0) begin // unlocked pmpcfg entry
                                     csr.pmpcfg[i][0] <= csr.wdata[(i % 4)*8+0]; // R - read
                                     csr.pmpcfg[i][1] <= csr.wdata[(i % 4)*8+1]; // W - write
                                     csr.pmpcfg[i][2] <= csr.wdata[(i % 4)*8+2]; // X - execute
                                     csr.pmpcfg[i][3] <= csr.wdata[(i % 4)*8+3]; // A_L - mode low [TOR-mode only!]
                                     csr.pmpcfg[i][4] <= 1'b0; // A_H - mode high [TOR-mode only!]
                                     csr.pmpcfg[i][5] <= 1'b0; // reserved
                                     csr.pmpcfg[i][6] <= 1'b0; // reserved
                                     csr.pmpcfg[i][7] <= csr.wdata[(i % 4)*8+7]; // L (locked / also enforce in machine-mode)
                                 end
                             end
                         end
                     end
                     /* R/W: pmpaddr* - PMP address registers */
                     if (csr.addr[11:4] == csr_class_pmpaddr_c) begin
                         for (int i = 0; i < PMP_NUM_REGIONS; ++i) begin
                             if (i < PMP_NUM_REGIONS-1) begin
                                 if ((csr.addr[3:0] == i) && (csr.pmpcfg[i][7] == 1'b0) && // unlocked access
                                    ((csr.pmpcfg[i+1][7] == 1'b0) || (csr.pmpcfg[i+1][3] == 1'b0))) begin // pmpcfg(i+1) not "LOCKED TOR" [TOR-mode only!]
                                     csr.pmpaddr[i] <= csr.wdata[XLEN-3 : index_size_f(PMP_MIN_GRANULARITY)-2];
                                 end
                             end else begin // very last entry
                                 if ((csr.addr[3:0] == i) && (csr.pmpcfg[i][7] == 1'b0)) begin // unlocked access
                                     csr.pmpaddr[i] <= csr.wdata[XLEN-3 : index_size_f(PMP_MIN_GRANULARITY)-2];
                                 end
                             end
                         end
                     end
                 end
                 // ----------------------------------------------------------------------
                 // machine counter setup
                 if (csr.addr[11:5] == csr_cnt_setup_c) begin // counter configuration CSR class
                     /* R/W: mcountinhibit - machine counter-inhibit register */
                     if (csr.addr[4:0] == csr_mcountinhibit_c[4:0]) begin
                         if (CPU_EXTENSION_RISCV_Zicntr == 1) begin
                             csr.mcountinhibit_cy <= csr.wdata[0]; // inhibit auto-increment of [m]cycle[h] counter
                             csr.mcountinhibit_ir <= csr.wdata[2]; // inhibit auto-increment of [m]instret[h] counter
                         end
                         //
                         if ((HPM_NUM_CNTS > 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin // any HPMs available?
                             csr.mcountinhibit_hpm <= csr.wdata[$bits(csr.mcountinhibit_hpm)+2 : 3]; // inhibit auto-increment of [m]hpmcounter*[h] counter
                         end
                     end
                     /* R/W: mhpmevent - machine performance-monitors event selector */
                     if ((HPM_NUM_CNTS > 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin
                         for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
                             if (csr.addr[4:0] == (i+3)) begin
                                 csr.mhpmevent[i] <= csr.wdata[$bits(csr.mhpmevent[i])-1 : 0];
                             end
                             //
                             csr.mhpmevent[i][hpmcnt_event_never_c] <= 1'b0; // would be used for "TIME"
                         end
                     end
                 end
                 // ----------------------------------------------------------------------
                 // debug mode CSRs
                 if (CPU_EXTENSION_RISCV_Sdext == 1) begin
                     if (csr.addr[11:2] == csr_class_debug_c) begin // debug CSR class
                         /* R/W: dcsr - debug mode control and status register */
                         if (csr.addr[1:0] == csr_dcsr_c[1:0]) begin
                             csr.dcsr_ebreakm <= csr.wdata[15];
                             csr.dcsr_step    <= csr.wdata[2];
                             //
                             if (CPU_EXTENSION_RISCV_U == 1) begin // user mode implemented
                                  csr.dcsr_ebreaku <= csr.wdata[12];
                                  csr.dcsr_prv     <= csr.wdata[1] | csr.wdata[0]; // everything /= U will fall back to M
                             end
                         end
                         /* R/W: dpc - debug mode program counter */
                         if (csr.addr[1:0] == csr_dpc_c[1:0]) begin
                             csr.dpc <= {csr.wdata[XLEN-1 : 1], 1'b0};
                         end
                         /* R/W: dscratch0 - debug mode scratch register 0 */
                         if (csr.addr[1:0] == csr_dscratch0_c[1:0]) begin
                             csr.dscratch0 <= csr.wdata;
                         end
                     end
                 end
                 // ----------------------------------------------------------------------
                 // trigger module CSRs
                 if (CPU_EXTENSION_RISCV_Sdtrig == 1) begin
                     if (csr.addr[11:4] == csr_class_trigger_c) begin // trigger CSR class
                         if ((debug_ctrl.running == 1'b1) || (csr.tdata1_dmode == 1'b0)) begin // exclusive access from debug-mode?
                             /* R/W: tdata1 - match control */
                             if (csr.addr[3:0] == csr_tdata1_c[3:0]) begin
                                 csr.tdata1_exe    <= csr.wdata[2];
                                 csr.tdata1_action <= csr.wdata[12];
                                 csr.tdata1_dmode  <= csr.wdata[27];
                             end
                             /* R/W: tdata2 - address compare */
                             if (csr.addr[3:0] == csr_tdata2_c[3:0]) begin
                                 csr.tdata2 <= {csr.wdata[XLEN-1 : 1], 1'b0};
                             end
                         end
                     end
                 end
                 // ----------------------------------------------------------------------

            // ********************************************************************************
            // Automatic CSR access by hardware
            // ********************************************************************************
            end else begin
                 // ----------------------------------------------------------------------
                 // -- floating-point (FPU) exception flags
                 // ----------------------------------------------------------------------
                 if ((CPU_EXTENSION_RISCV_Zfinx == 1) && (trap_ctrl.exc_buf[exc_iillegal_c] == 1'b0)) begin // no illegal instruction
                     csr.fflags <= csr.fflags | fpu_flags_i; // accumulate flags ("accrued exception flags")
                 end

                 // -- --------------------------------------------------------------------
                 // -- TRAP ENTER
                 // -- --------------------------------------------------------------------
                 if (trap_ctrl.env_start_ack == 1'b1) begin // trap handler starting?
                     // -- NORMAL trap entry: write mcause, mepc and mtval - no update when in debug-mode! --
                     // -- --------------------------------------------------------------------
                     if ((CPU_EXTENSION_RISCV_Sdext == 0) ||
                         ((trap_ctrl.cause[5] == 1'b0) && (debug_ctrl.running == 1'b0))) begin
                         /* trap cause ID */
                         csr.mcause <= {trap_ctrl.cause[$bits(trap_ctrl.cause)-1], trap_ctrl.cause[4:0]}; // type + identifier
                         /* trap PC */
                         csr.mepc <= trap_ctrl.epc;
                         /* trap value */
                         unique case (trap_ctrl.cause)
                             // misaligned instruction address OR instruction access error
                             trap_ima_c, trap_iba_c : begin
                                 csr.mtval <= {execute_engine.pc[XLEN-1 : 1], 1'b0}; // address of faulting instruction access
                             end
                             // misaligned load/store address OR load/store access error
                             trap_lma_c, trap_lbe_c, trap_sma_c, trap_sbe_c : begin
                                 csr.mtval <= mar_i; // faulting data access address
                             end
                             // everything else including all interrupts
                             default: begin
                                  csr.mtval <= '0;
                             end
                         endcase
                         /* update privilege level and interrupt enable stack */
                         csr.privilege    <= priv_mode_m_c; // execute trap in machine mode
                         csr.mstatus_mie  <= 1'b0; // disable interrupts
                         csr.mstatus_mpie <= csr.mstatus_mie; // backup previous mie state
                         csr.mstatus_mpp  <= csr.privilege; // backup previous privilege mode
                     end

                    // -- DEBUG MODE entry: write dpc and dcsr - no update when already in debug-mode! --
                    // -- --------------------------------------------------------------------
                    if ((CPU_EXTENSION_RISCV_Sdext == 1) && 
                        (trap_ctrl.cause[5] == 1'b1) && 
                        (debug_ctrl.running == 1'b0)) begin
                        /* trap cause ID */
                        csr.dcsr_cause <= trap_ctrl.cause[2:0]; // why did we enter debug mode?
                        /* current privilege mode when debug mode was entered */
                        csr.dcsr_prv <= csr.privilege;
                        /* trap PC */
                        csr.dpc <= trap_ctrl.epc;
                    end
                 // -- --------------------------------------------------------------------
                 // -- TRAP EXIT
                 // -- --------------------------------------------------------------------
                end else if (trap_ctrl.env_end == 1'b1) begin
                     /* return from debug mode */
                     if ((CPU_EXTENSION_RISCV_Sdext == 1) && (debug_ctrl.running == 1'b1)) begin
                         if (CPU_EXTENSION_RISCV_U == 1) begin
                             csr.privilege <= csr.dcsr_prv;
                             //
                             if (csr.dcsr_prv != priv_mode_m_c) begin
                                 csr.mstatus_mprv <= 1'b0; // clear if return priv. mode is less than M
                             end
                         end
                     /* return from "normal trap" */
                     end else begin
                         if (CPU_EXTENSION_RISCV_U == 1) begin
                             csr.privilege   <= csr.mstatus_mpp; // restore previous privilege mode
                             csr.mstatus_mpp <= priv_mode_u_c; // set to least-privileged mode that is supported
                             //
                             if (csr.mstatus_mpp != priv_mode_m_c) begin
                                  csr.mstatus_mprv <= 1'b0; // clear if return priv. mode is less than M
                             end
                         end else begin
                             csr.privilege   <= priv_mode_m_c;
                             csr.mstatus_mpp <= priv_mode_m_c;
                         end
                         //
                          csr.mstatus_mie  <= csr.mstatus_mpie; // restore global IRQ enable flag
                          csr.mstatus_mpie <= 1'b1;
                     end
                 end // trap exit
             end // hardware csr access

             // ********************************************************************************
             // Override - tie unimplemented registers to all-zero
             // ********************************************************************************
             
             /* no FPU */
             if (CPU_EXTENSION_RISCV_Zfinx == 0) begin
               csr.frm    <= '0;
               csr.fflags <= '0;
             end
     
             /* no user mode */
             if (CPU_EXTENSION_RISCV_U == 0) begin
               csr.mstatus_mprv  <= 1'b0;
               csr.mstatus_tw    <= 1'b0;
               //
               csr.dcsr_ebreaku  <= 1'b0;
               csr.dcsr_prv      <= 1'b0;
             end
     
             /* no PMP */
             if (PMP_NUM_REGIONS == 0) begin
               csr.pmpcfg  <= '0;
               csr.pmpaddr <= '0;
             end
     
             /* no HPMs */
             if ((HPM_NUM_CNTS == 0) || (CPU_EXTENSION_RISCV_Zihpm == 0)) begin
               csr.mcountinhibit_hpm <= '0;
               csr.mhpmevent         <= '0;
             end
     
             /* no base counters */
             if (CPU_EXTENSION_RISCV_Zicntr == 0) begin
               csr.mcountinhibit_cy <= 1'b0;
               csr.mcountinhibit_ir <= 1'b0;
             end
     
             /* no debug mode */
             if (CPU_EXTENSION_RISCV_Sdext == 0) begin
               csr.dcsr_ebreakm <= 1'b0;
               csr.dcsr_step    <= 1'b0;
               csr.dcsr_ebreaku <= 1'b0;
               csr.dcsr_prv     <= priv_mode_m_c;
               csr.dcsr_cause   <= '0;
               csr.dpc          <= '0;
               csr.dscratch0    <= '0;
             end
     
             /* no trigger module */
             if (CPU_EXTENSION_RISCV_Sdtrig == 0) begin
               csr.tdata1_exe    <= 1'b0;
               csr.tdata1_action <= 1'b0;
               csr.tdata1_dmode  <= 1'b0;
               csr.tdata2        <= '0;
             end
         end // Zicsr implemented
      end
    end : csr_write_access

    /* effective privilege mode is MACHINE when in debug mode */
    assign csr.privilege_eff = ((CPU_EXTENSION_RISCV_Sdext == 1) && (debug_ctrl.running == 1'b1)) ? priv_mode_m_c : csr.privilege;

    /* PMP output to bus unit and configuration read-back */
    always_comb begin : pmp_connect
      csr.pmpaddr_rd = '0;
      csr.pmpcfg_rd  = '0;
      //
      for (int j = 0; j < 16; ++j) begin
        pmp_addr_o[j] = '0;
        pmp_ctrl_o[j] = '0;
      end
      // loop
      for (int i = 0; i < 16; ++i) begin
         if (i < PMP_NUM_REGIONS) begin
            pmp_addr_o[i][XLEN-1 : index_size_f(PMP_MIN_GRANULARITY)] = csr.pmpaddr[i];
            pmp_ctrl_o[i] = csr.pmpcfg[i];
            csr.pmpaddr_rd[i][XLEN-3 : index_size_f(PMP_MIN_GRANULARITY)-2] = csr.pmpaddr[i];
            csr.pmpcfg_rd[i/4][8*(i % 4) +: 8] = csr.pmpcfg[i];
         end
      end
    end : pmp_connect

    // Control and Status Registers - Read Access ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : csr_read_access
       csr.re    <= csr.re_nxt; // read access?
       csr.rdata <= '0; // default output, unimplemented CSRs/CSR bits read as zero
       //
       if (CPU_EXTENSION_RISCV_Zicsr == 1) begin
         unique case (csr_raddr)
             // -- --------------------------------------------------------------------
             /* floating-point CSRs */
             // -- --------------------------------------------------------------------
             // fflags (r/w): floating-point (FPU) exception flags
             csr_fflags_c : begin 
                 if (CPU_EXTENSION_RISCV_Zfinx) begin
                     csr.rdata[4:0] <= csr.fflags;
                 end
             end
              // frm (r/w): floating-point (FPU) rounding mode
             csr_frm_c : begin
                 if (CPU_EXTENSION_RISCV_Zfinx) begin
                     csr.rdata[2:0] <= csr.frm;
                 end
             end
             // fcsr (r/w): floating-point (FPU) control/status (frm + fflags)
             csr_fcsr_c : begin 
                 if (CPU_EXTENSION_RISCV_Zfinx) begin
                     csr.rdata[7:0] <= {csr.frm, csr.fflags};
                 end
             end
             // -- --------------------------------------------------------------------
             /* machine trap setup */
             // -- --------------------------------------------------------------------
             // mstatus (r/w): machine status register - low word
             csr_mstatus_c : begin
                 csr.rdata[03] <= csr.mstatus_mie; // MIE
                 csr.rdata[07] <= csr.mstatus_mpie; // MPIE
                 csr.rdata[12:11] <= (csr.mstatus_mpp == 1'b1) ? '1 : '0; // MPP: machine previous privilege mode
                 csr.rdata[17] <= csr.mstatus_mprv;
                 csr.rdata[21] <= csr.mstatus_tw & logic'(CPU_EXTENSION_RISCV_U); // TW
             end
             //  misa (r/-): ISA and extensions
             csr_misa_c : begin
                 csr.rdata[01] <=   CPU_EXTENSION_RISCV_B;   // B CPU extension
                 csr.rdata[02] <=   CPU_EXTENSION_RISCV_C;   // C CPU extension
                 csr.rdata[04] <=   CPU_EXTENSION_RISCV_E;   // E CPU extension
                 csr.rdata[08] <= ~ CPU_EXTENSION_RISCV_E;   // I CPU extension (if not E)
                 csr.rdata[12] <=   CPU_EXTENSION_RISCV_M;   // M CPU extension
                 csr.rdata[20] <=   CPU_EXTENSION_RISCV_U;   // U CPU extension
                 csr.rdata[23] <=   1'b1;                            // X CPU extension (non-standard extensions / CELLRV32-specific)
                 csr.rdata[30] <=   1'b1; // 32-bit architecture (MXL lo)
                 csr.rdata[31] <=   1'b0; // 32-bit architecture (MXL hi)
             end
             // mie (r/w): machine interrupt-enable register
             csr_mie_c : begin
                 csr.rdata[03]    <= csr.mie_msi; // machine software IRQ enable
                 csr.rdata[07]    <= csr.mie_mti; // machine timer IRQ enable
                 csr.rdata[11]    <= csr.mie_mei; // machine external IRQ enable
                 csr.rdata[31:16] <= csr.mie_firq;
             end
             // mtvec (r/w): machine trap-handler base address (for ALL exceptions)
             csr_mtvec_c : begin
                 csr.rdata <= {csr.mtvec[XLEN-1:2], 2'b00}; // mtvec.MODE=0
             end
             // mcounteren (r/-): machine counter enable register
             csr_mcounteren_c : begin
                 if (CPU_EXTENSION_RISCV_U == 1) begin
                     csr.rdata[0] <= 1'b1; // allow user-level access to cycle[h]
                     csr.rdata[2] <= 1'b1; // allow user-level access to instret[h]
                     //
                     for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
                         csr.rdata[3+i] <= 1'b1; // allow user-level access to all available hpmcounter*[h] CSRs
                     end
                 end
             end
             // -- --------------------------------------------------------------------
             /* machine trap handling */
             // -- --------------------------------------------------------------------
             // mscratch (r/w): machine scratch register
             csr_mscratch_c : begin
                 csr.rdata <= csr.mscratch;
             end
             // mepc (r/w): machine exception program counter
             csr_mepc_c : begin
                 csr.rdata <= {csr.mepc[XLEN-1:1], 1'b0};
             end
             // mcause (r/w): machine trap cause
             csr_mcause_c : begin
                 csr.rdata[31]  <= csr.mcause[5];
                 csr.rdata[4:0] <= csr.mcause[4:0];
             end
             // mtval (r/w): machine bad address or instruction
             csr_mtval_c : begin
                 csr.rdata <= csr.mtval;
             end
             // mip (r/c): machine interrupt pending
             csr_mip_c : begin
                 csr.rdata[03]    <= trap_ctrl.irq_pnd[irq_msi_irq_c];
                 csr.rdata[07]    <= trap_ctrl.irq_pnd[irq_mti_irq_c];
                 csr.rdata[11]    <= trap_ctrl.irq_pnd[irq_mei_irq_c];
                 csr.rdata[31:16] <= trap_ctrl.irq_pnd[irq_firq_15_c : irq_firq_0_c];
             end
             // -- --------------------------------------------------------------------
             /* physical memory protection - configuration (r/w) */
             // -- --------------------------------------------------------------------
             csr_pmpcfg0_c, csr_pmpcfg1_c, csr_pmpcfg2_c, csr_pmpcfg3_c : begin
                 if (PMP_NUM_REGIONS > 0) begin
                     csr.rdata <= csr.pmpcfg_rd[csr_raddr[1:0]];
                 end
             end
             // -- --------------------------------------------------------------------
             /* physical memory protection - addresses (r/w) */
             // -- --------------------------------------------------------------------
             csr_pmpaddr0_c  : if (PMP_NUM_REGIONS > 00) begin csr.rdata <= csr.pmpaddr_rd[00]; end
             csr_pmpaddr1_c  : if (PMP_NUM_REGIONS > 01) begin csr.rdata <= csr.pmpaddr_rd[01]; end
             csr_pmpaddr2_c  : if (PMP_NUM_REGIONS > 02) begin csr.rdata <= csr.pmpaddr_rd[02]; end
             csr_pmpaddr3_c  : if (PMP_NUM_REGIONS > 03) begin csr.rdata <= csr.pmpaddr_rd[03]; end
             csr_pmpaddr4_c  : if (PMP_NUM_REGIONS > 04) begin csr.rdata <= csr.pmpaddr_rd[04]; end
             csr_pmpaddr5_c  : if (PMP_NUM_REGIONS > 05) begin csr.rdata <= csr.pmpaddr_rd[05]; end
             csr_pmpaddr6_c  : if (PMP_NUM_REGIONS > 06) begin csr.rdata <= csr.pmpaddr_rd[06]; end
             csr_pmpaddr7_c  : if (PMP_NUM_REGIONS > 07) begin csr.rdata <= csr.pmpaddr_rd[07]; end
             csr_pmpaddr8_c  : if (PMP_NUM_REGIONS > 08) begin csr.rdata <= csr.pmpaddr_rd[08]; end
             csr_pmpaddr9_c  : if (PMP_NUM_REGIONS > 09) begin csr.rdata <= csr.pmpaddr_rd[09]; end
             csr_pmpaddr10_c : if (PMP_NUM_REGIONS > 10) begin csr.rdata <= csr.pmpaddr_rd[10]; end
             csr_pmpaddr11_c : if (PMP_NUM_REGIONS > 11) begin csr.rdata <= csr.pmpaddr_rd[11]; end
             csr_pmpaddr12_c : if (PMP_NUM_REGIONS > 12) begin csr.rdata <= csr.pmpaddr_rd[12]; end
             csr_pmpaddr13_c : if (PMP_NUM_REGIONS > 13) begin csr.rdata <= csr.pmpaddr_rd[13]; end
             csr_pmpaddr14_c : if (PMP_NUM_REGIONS > 14) begin csr.rdata <= csr.pmpaddr_rd[14]; end
             csr_pmpaddr15_c : if (PMP_NUM_REGIONS > 15) begin csr.rdata <= csr.pmpaddr_rd[15]; end
             // -- --------------------------------------------------------------------
             /* machine counter setup */
             // -- --------------------------------------------------------------------
             // mcountinhibit (r/w): machine counter-inhibit register
             csr_mcountinhibit_c : begin
                 if (CPU_EXTENSION_RISCV_Zicntr == 1) begin
                     csr.rdata[0] <= csr.mcountinhibit_cy; // inhibit auto-increment of [m]cycle[h] counter
                     csr.rdata[2] <= csr.mcountinhibit_ir; // inhibit auto-increment of [m]instret[h] counter
                 end
                 // any HPMs implemented?
                 if ((HPM_NUM_CNTS > 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin
                     csr.rdata[(HPM_NUM_CNTS+3)-1 : 3] <= csr.mcountinhibit_hpm[HPM_NUM_CNTS-1 : 0]; // inhibit auto-increment of [m]hpmcounter*[h] counter
                 end
             end
             // -- --------------------------------------------------------------------
             /* HPM event selector (r/w) */
             csr_mhpmevent3_c  : if ((HPM_NUM_CNTS > 00) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[00]; end
             csr_mhpmevent4_c  : if ((HPM_NUM_CNTS > 01) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[01]; end
             csr_mhpmevent5_c  : if ((HPM_NUM_CNTS > 02) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[02]; end
             csr_mhpmevent6_c  : if ((HPM_NUM_CNTS > 03) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[03]; end
             csr_mhpmevent7_c  : if ((HPM_NUM_CNTS > 04) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[04]; end
             csr_mhpmevent8_c  : if ((HPM_NUM_CNTS > 05) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[05]; end
             csr_mhpmevent9_c  : if ((HPM_NUM_CNTS > 06) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[06]; end
             csr_mhpmevent10_c : if ((HPM_NUM_CNTS > 07) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[07]; end
             csr_mhpmevent11_c : if ((HPM_NUM_CNTS > 08) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[08]; end
             csr_mhpmevent12_c : if ((HPM_NUM_CNTS > 09) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[09]; end
             csr_mhpmevent13_c : if ((HPM_NUM_CNTS > 10) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[10]; end
             csr_mhpmevent14_c : if ((HPM_NUM_CNTS > 11) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[11]; end
             csr_mhpmevent15_c : if ((HPM_NUM_CNTS > 12) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[12]; end
             csr_mhpmevent16_c : if ((HPM_NUM_CNTS > 13) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[13]; end
             csr_mhpmevent17_c : if ((HPM_NUM_CNTS > 14) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[14]; end
             csr_mhpmevent18_c : if ((HPM_NUM_CNTS > 15) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[15]; end
             csr_mhpmevent19_c : if ((HPM_NUM_CNTS > 16) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[16]; end
             csr_mhpmevent20_c : if ((HPM_NUM_CNTS > 17) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[17]; end
             csr_mhpmevent21_c : if ((HPM_NUM_CNTS > 18) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[18]; end
             csr_mhpmevent22_c : if ((HPM_NUM_CNTS > 19) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[19]; end
             csr_mhpmevent23_c : if ((HPM_NUM_CNTS > 20) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[20]; end
             csr_mhpmevent24_c : if ((HPM_NUM_CNTS > 21) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[21]; end
             csr_mhpmevent25_c : if ((HPM_NUM_CNTS > 22) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[22]; end
             csr_mhpmevent26_c : if ((HPM_NUM_CNTS > 23) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[23]; end
             csr_mhpmevent27_c : if ((HPM_NUM_CNTS > 24) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[24]; end
             csr_mhpmevent28_c : if ((HPM_NUM_CNTS > 25) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[25]; end
             csr_mhpmevent29_c : if ((HPM_NUM_CNTS > 26) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[26]; end
             csr_mhpmevent30_c : if ((HPM_NUM_CNTS > 27) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[27]; end
             csr_mhpmevent31_c : if ((HPM_NUM_CNTS > 28) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmevent_rd[28]; end
             // -- --------------------------------------------------------------------
             /* counters and timers */
             csr_cycle_c   , csr_mcycle_c    : if (CPU_EXTENSION_RISCV_Zicntr) begin csr.rdata <= csr.mcycle;    end
             csr_cycleh_c  , csr_mcycleh_c   : if (CPU_EXTENSION_RISCV_Zicntr) begin csr.rdata <= csr.mcycleh;   end
             csr_instret_c , csr_minstret_c  : if (CPU_EXTENSION_RISCV_Zicntr) begin csr.rdata <= csr.minstret;  end
             csr_instreth_c, csr_minstreth_c : if (CPU_EXTENSION_RISCV_Zicntr) begin csr.rdata <= csr.minstreth; end
             // -- --------------------------------------------------------------------
             /* HPM low word (r/w) */
             csr_mhpmcounter3_c , csr_hpmcounter3_c  : if ((HPM_NUM_CNTS > 00) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[00]; end
             csr_mhpmcounter4_c , csr_hpmcounter4_c  : if ((HPM_NUM_CNTS > 01) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[01]; end
             csr_mhpmcounter5_c , csr_hpmcounter5_c  : if ((HPM_NUM_CNTS > 02) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[02]; end
             csr_mhpmcounter6_c , csr_hpmcounter6_c  : if ((HPM_NUM_CNTS > 03) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[03]; end
             csr_mhpmcounter7_c , csr_hpmcounter7_c  : if ((HPM_NUM_CNTS > 04) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[04]; end
             csr_mhpmcounter8_c , csr_hpmcounter8_c  : if ((HPM_NUM_CNTS > 05) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[05]; end
             csr_mhpmcounter9_c , csr_hpmcounter9_c  : if ((HPM_NUM_CNTS > 06) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[06]; end
             csr_mhpmcounter10_c, csr_hpmcounter10_c : if ((HPM_NUM_CNTS > 07) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[07]; end
             csr_mhpmcounter11_c, csr_hpmcounter11_c : if ((HPM_NUM_CNTS > 08) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[08]; end
             csr_mhpmcounter12_c, csr_hpmcounter12_c : if ((HPM_NUM_CNTS > 09) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[09]; end
             csr_mhpmcounter13_c, csr_hpmcounter13_c : if ((HPM_NUM_CNTS > 10) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[10]; end
             csr_mhpmcounter14_c, csr_hpmcounter14_c : if ((HPM_NUM_CNTS > 11) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[11]; end
             csr_mhpmcounter15_c, csr_hpmcounter15_c : if ((HPM_NUM_CNTS > 12) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[12]; end
             csr_mhpmcounter16_c, csr_hpmcounter16_c : if ((HPM_NUM_CNTS > 13) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[13]; end
             csr_mhpmcounter17_c, csr_hpmcounter17_c : if ((HPM_NUM_CNTS > 14) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[14]; end
             csr_mhpmcounter18_c, csr_hpmcounter18_c : if ((HPM_NUM_CNTS > 15) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[15]; end
             csr_mhpmcounter19_c, csr_hpmcounter19_c : if ((HPM_NUM_CNTS > 16) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[16]; end
             csr_mhpmcounter20_c, csr_hpmcounter20_c : if ((HPM_NUM_CNTS > 17) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[17]; end
             csr_mhpmcounter21_c, csr_hpmcounter21_c : if ((HPM_NUM_CNTS > 18) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[18]; end
             csr_mhpmcounter22_c, csr_hpmcounter22_c : if ((HPM_NUM_CNTS > 19) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[19]; end
             csr_mhpmcounter23_c, csr_hpmcounter23_c : if ((HPM_NUM_CNTS > 20) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[20]; end
             csr_mhpmcounter24_c, csr_hpmcounter24_c : if ((HPM_NUM_CNTS > 21) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[21]; end
             csr_mhpmcounter25_c, csr_hpmcounter25_c : if ((HPM_NUM_CNTS > 22) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[22]; end
             csr_mhpmcounter26_c, csr_hpmcounter26_c : if ((HPM_NUM_CNTS > 23) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[23]; end
             csr_mhpmcounter27_c, csr_hpmcounter27_c : if ((HPM_NUM_CNTS > 24) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[24]; end
             csr_mhpmcounter28_c, csr_hpmcounter28_c : if ((HPM_NUM_CNTS > 25) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[25]; end
             csr_mhpmcounter29_c, csr_hpmcounter29_c : if ((HPM_NUM_CNTS > 26) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[26]; end
             csr_mhpmcounter30_c, csr_hpmcounter30_c : if ((HPM_NUM_CNTS > 27) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[27]; end
             csr_mhpmcounter31_c, csr_hpmcounter31_c : if ((HPM_NUM_CNTS > 28) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounter_rd[28]; end
             // -- --------------------------------------------------------------------
             /* HPM high word (r/w) */
             csr_mhpmcounter3h_c , csr_hpmcounter3h_c  : if ((HPM_NUM_CNTS > 00) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[00]; end
             csr_mhpmcounter4h_c , csr_hpmcounter4h_c  : if ((HPM_NUM_CNTS > 01) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[01]; end
             csr_mhpmcounter5h_c , csr_hpmcounter5h_c  : if ((HPM_NUM_CNTS > 02) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[02]; end
             csr_mhpmcounter6h_c , csr_hpmcounter6h_c  : if ((HPM_NUM_CNTS > 03) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[03]; end
             csr_mhpmcounter7h_c , csr_hpmcounter7h_c  : if ((HPM_NUM_CNTS > 04) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[04]; end
             csr_mhpmcounter8h_c , csr_hpmcounter8h_c  : if ((HPM_NUM_CNTS > 05) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[05]; end
             csr_mhpmcounter9h_c , csr_hpmcounter9h_c  : if ((HPM_NUM_CNTS > 06) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[06]; end
             csr_mhpmcounter10h_c, csr_hpmcounter10h_c : if ((HPM_NUM_CNTS > 07) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[07]; end
             csr_mhpmcounter11h_c, csr_hpmcounter11h_c : if ((HPM_NUM_CNTS > 08) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[08]; end
             csr_mhpmcounter12h_c, csr_hpmcounter12h_c : if ((HPM_NUM_CNTS > 09) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[09]; end
             csr_mhpmcounter13h_c, csr_hpmcounter13h_c : if ((HPM_NUM_CNTS > 10) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[10]; end
             csr_mhpmcounter14h_c, csr_hpmcounter14h_c : if ((HPM_NUM_CNTS > 11) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[11]; end
             csr_mhpmcounter15h_c, csr_hpmcounter15h_c : if ((HPM_NUM_CNTS > 12) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[12]; end
             csr_mhpmcounter16h_c, csr_hpmcounter16h_c : if ((HPM_NUM_CNTS > 13) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[13]; end
             csr_mhpmcounter17h_c, csr_hpmcounter17h_c : if ((HPM_NUM_CNTS > 14) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[14]; end
             csr_mhpmcounter18h_c, csr_hpmcounter18h_c : if ((HPM_NUM_CNTS > 15) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[15]; end
             csr_mhpmcounter19h_c, csr_hpmcounter19h_c : if ((HPM_NUM_CNTS > 16) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[16]; end
             csr_mhpmcounter20h_c, csr_hpmcounter20h_c : if ((HPM_NUM_CNTS > 17) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[17]; end
             csr_mhpmcounter21h_c, csr_hpmcounter21h_c : if ((HPM_NUM_CNTS > 18) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[18]; end
             csr_mhpmcounter22h_c, csr_hpmcounter22h_c : if ((HPM_NUM_CNTS > 19) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[19]; end
             csr_mhpmcounter23h_c, csr_hpmcounter23h_c : if ((HPM_NUM_CNTS > 20) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[20]; end
             csr_mhpmcounter24h_c, csr_hpmcounter24h_c : if ((HPM_NUM_CNTS > 21) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[21]; end
             csr_mhpmcounter25h_c, csr_hpmcounter25h_c : if ((HPM_NUM_CNTS > 22) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[22]; end
             csr_mhpmcounter26h_c, csr_hpmcounter26h_c : if ((HPM_NUM_CNTS > 23) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[23]; end
             csr_mhpmcounter27h_c, csr_hpmcounter27h_c : if ((HPM_NUM_CNTS > 24) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[24]; end
             csr_mhpmcounter28h_c, csr_hpmcounter28h_c : if ((HPM_NUM_CNTS > 25) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[25]; end
             csr_mhpmcounter29h_c, csr_hpmcounter29h_c : if ((HPM_NUM_CNTS > 26) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[26]; end
             csr_mhpmcounter30h_c, csr_hpmcounter30h_c : if ((HPM_NUM_CNTS > 27) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[27]; end
             csr_mhpmcounter31h_c, csr_hpmcounter31h_c : if ((HPM_NUM_CNTS > 28) && (CPU_EXTENSION_RISCV_Zihpm)) begin csr.rdata <= csr.mhpmcounterh_rd[28]; end
             // -- --------------------------------------------------------------------
             /* machine information registers */
             // -- --------------------------------------------------------------------
             csr_marchid_c : csr.rdata[4:0] <= 5'b10011; // marchid (r/-): arch ID - official RISC-V open-source arch ID
             csr_mimpid_c  : csr.rdata <= hw_version_c; // mimpid (r/-): implementation ID -- CELLRV32 hardware version
             csr_mhartid_c : csr.rdata <= HW_THREAD_ID; // mhartid (r/-): hardware thread ID
             // -- --------------------------------------------------------------------
             /* debug mode CSRs */
             csr_dcsr_c      : if (CPU_EXTENSION_RISCV_Sdext) begin csr.rdata <= csr.dcsr_rd;   end // dcsr (r/w): debug mode control and status
             csr_dpc_c       : if (CPU_EXTENSION_RISCV_Sdext) begin csr.rdata <= csr.dpc;       end // dpc (r/w): debug mode program counter
             csr_dscratch0_c : if (CPU_EXTENSION_RISCV_Sdext) begin csr.rdata <= csr.dscratch0; end // dscratch0 (r/w): debug mode scratch register 0
             // -- --------------------------------------------------------------------
             /* trigger module CSRs */
             csr_tdata1_c : if (CPU_EXTENSION_RISCV_Sdtrig) begin csr.rdata <= csr.tdata1_rd;   end // tdata1 (r/w): match control
             csr_tdata2_c : if (CPU_EXTENSION_RISCV_Sdtrig) begin csr.rdata <= csr.tdata2;      end // tdata2 (r/w): address-compare
             csr_tinfo_c  : if (CPU_EXTENSION_RISCV_Sdtrig) begin csr.rdata <= 32'h00000004;    end // tinfo (r/w): address-match trigger only
             
             // -- --------------------------------------------------------------------
             /* CELLRV32-specific (RISC-V "custom") read-only CSRs */
             // -- --------------------------------------------------------------------
             
             // -- --------------------------------------------------------------------
             /* machine extended ISA extensions information */
             csr_mxisa_c : begin
                 // extended ISA (sub-)extensions
                 csr.rdata[00] <= logic'(CPU_EXTENSION_RISCV_Zicsr);    // Zicsr: privileged architecture (!!!)
                 csr.rdata[01] <= logic'(CPU_EXTENSION_RISCV_Zifencei); // Zifencei: instruction stream sync.
                 csr.rdata[02] <= logic'(CPU_EXTENSION_RISCV_Zmmul);    // Zmmul: mul/div
                 csr.rdata[03] <= logic'(CPU_EXTENSION_RISCV_Zxcfu);    // Zxcfu: custom RISC-V instructions
                 csr.rdata[04] <= logic'(CPU_EXTENSION_RISCV_Zicond);   // Zicond: conditional operations
                 csr.rdata[05] <= logic'(CPU_EXTENSION_RISCV_Zfinx);    // Zfinx: FPU using x registers, "F-alternative"

                 csr.rdata[07] <= logic'(CPU_EXTENSION_RISCV_Zicntr);   // Zicntr: base instructions, cycle and time CSRs
                 csr.rdata[08] <= logic'(PMP_NUM_REGIONS > 0);          // PMP: physical memory protection (Zspmp)
                 csr.rdata[09] <= logic'(CPU_EXTENSION_RISCV_Zihpm);    // Zihpm: hardware performance monitors
                 csr.rdata[10] <= logic'(CPU_EXTENSION_RISCV_Sdext);    // Sdext: RISC-V (external) debug mode
                 csr.rdata[11] <= logic'(CPU_EXTENSION_RISCV_Sdtrig);   // Sdtrig: trigger module
                 // misc 
                 csr.rdata[20] <= logic'(is_simulation_c);              // is this a simulation?
                 // tuning options 
                 csr.rdata[30] <= logic'(FAST_MUL_EN);                  // DSP-based multiplication (M extensions only)
                 csr.rdata[31] <= logic'(FAST_SHIFT_EN);                // parallel logic for shifts (barrel shifters)
             end
             // -- --------------------------------------------------------------------
             /* undefined/unavailable */
             default: begin
                 csr.rdata <= '0; // not implemented, read as zero
             end
         endcase
       end
    end : csr_read_access

    /* AND-gate CSR read address: csr.rdata is zero if csr.re is not set */
    // -- > [WARNING] MACHINE (9:8 = 11) and USER (9:8 = 00) CSRs only!
    assign csr_raddr = (csr.re == 1'b1) ? {csr.addr[11:10], csr.addr[8], csr.addr[8], csr.addr[7:0]} : '0;

    /* CSR read data output */
    assign csr_rdata_o = csr.rdata;

    // ****************************************************************************************************************************
    // CPU Counters / HPMs
    // ****************************************************************************************************************************

    // Control and Status Registers - Counters ---------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : csr_counters
       if (rstn_i == 1'b0) begin
         /* write access */
         cnt_csr_we.cycle     <= '0;
         cnt_csr_we.instret   <= '0;
         cnt_csr_we.hpm_lo    <= '0;
         cnt_csr_we.hpm_hi    <= '0;
         cnt_csr_we.wdata     <= '0;
         /* counters */
         csr.mcycle           <= '0;
         csr.mcycle_ovfl      <= '0;
         csr.mcycleh          <= '0;
         csr.minstret         <= '0;
         csr.minstret_ovfl    <= '0;
         csr.minstreth        <= '0;
         csr.mhpmcounter_ovfl <= '0;
         csr.mhpmcounter      <= '0;
         csr.mhpmcounterh     <= '0;
       end else begin
         /* write enable - defaults */
         cnt_csr_we.cycle   <= '0;
         cnt_csr_we.instret <= '0;
         cnt_csr_we.hpm_lo  <= '0;
         cnt_csr_we.hpm_hi  <= '0;

         /* write enable - access decoder */
         if (csr.we == 1'b1) begin
             cnt_csr_we.wdata <= csr.wdata; // buffer actual write data
             if (csr.addr[11:8] == csr_class_mcnt_c) begin // machine-mode counter access only
                 // NOTE: no need to check bits 6:5 of the CSR address here as they're always zero - an
                 // exception is raised if they're not all-zero
                 /* csr_mcycleh_c */
                 if (csr.addr[4:0] == csr_mcycle_c[4:0]) begin 
                     cnt_csr_we.cycle[0] <= ~ csr.addr[7]; // low word
                     cnt_csr_we.cycle[1] <=   csr.addr[7]; // high word
                 end
                 //
                 /* csr_minstreth_c */
                 if (csr.addr[4:0] == csr_minstret_c[4:0]) begin
                     cnt_csr_we.instret[0] <= ~ csr.addr[7]; // low word
                     cnt_csr_we.instret[1] <=   csr.addr[7]; // high word
                 end
                 //
                 /* csr_mhpmcounter3h_c */
                 for (int i = 0; i <= 28; ++i) begin
                     if (csr.addr[4:0] == (csr_mhpmcounter3_c[4:0] + i)) begin
                         cnt_csr_we.hpm_lo[i] <= ~ csr.addr[7]; // low word
                         cnt_csr_we.hpm_hi[i] <=   csr.addr[7]; // high word
                     end
                 end
             end
         end
         // ----------------------------------------------------------------------
         /* [machine] standard CPU counters (cycle & instret) */
         // ----------------------------------------------------------------------
         if (CPU_EXTENSION_RISCV_Zicntr == 1) begin // implemented at all?
             /* mcycle */
             if (cnt_csr_we.cycle[0] == 1'b1) begin // write access
                 csr.mcycle <= cnt_csr_we.wdata;
             // non-inhibited automatic update and not in debug mode
             end else if ((csr.mcountinhibit_cy == 1'b0) && 
                          (cnt_event[hpmcnt_event_cy_c] == 1'b1) && 
                          (debug_ctrl.running == 1'b0)) begin
                 csr.mcycle <= csr.mcycle_nxt[$bits(csr.mcycle_nxt)-2 : 0];
             end
             //
             csr.mcycle_ovfl[0] <= csr.mcycle_nxt[$bits(csr.mcycle_nxt)-1] & (~csr.mcountinhibit_cy) &
                                   cnt_event[hpmcnt_event_cy_c] & (~debug_ctrl.running);
             
             /* mcycleh */
             if (cnt_csr_we.cycle[1] == 1'b1) begin // write access
                 csr.mcycleh <= cnt_csr_we.wdata;
             end else begin // automatic update
                 csr.mcycleh <= csr.mcycleh + csr.mcycle_ovfl;
             end

             /* minstret */
             if (cnt_csr_we.instret[0] == 1'b1) begin // write access
                 csr.minstret <= cnt_csr_we.wdata;
             // non-inhibited automatic update and not in debug mode
             end else if ((csr.mcountinhibit_ir == 1'b0) && 
                          (cnt_event[hpmcnt_event_ir_c] == 1'b1) && 
                          (debug_ctrl.running == 1'b0)) begin
                 csr.minstret <= csr.minstret_nxt[$bits(csr.minstret_nxt)-2 : 0];
             end
             // 
             csr.minstret_ovfl[0] <= csr.minstret_nxt[$bits(csr.minstret_nxt)-1] & (~csr.mcountinhibit_ir) & cnt_event[hpmcnt_event_ir_c] & (~debug_ctrl.running);

             /* minstreth */
             if (cnt_csr_we.instret[1] == 1'b1) begin // write access
               csr.minstreth <= cnt_csr_we.wdata;
             end else begin // automatic update
               csr.minstreth <= csr.minstreth + csr.minstret_ovfl;
             end
         end else begin
             csr.mcycle        <= '0;
             csr.mcycle_ovfl   <= '0;
             csr.mcycleh       <= '0;
             csr.minstret      <= '0;
             csr.minstret_ovfl <= '0;
             csr.minstreth     <= '0;
         end
         // ----------------------------------------------------------------------
         /* [machine] hardware performance monitors (counters) */
         // ----------------------------------------------------------------------
         for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
             /* [m]hpmcounter* */
             if ((hpm_cnt_lo_width_c > 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin
                 csr.mhpmcounter_ovfl[i][0] <= csr.mhpmcounter_nxt[i][$bits(csr.mhpmcounter_nxt[i])-1] & (~csr.mcountinhibit_hpm[i]) & hpmcnt_trigger[i];
                 // write access
                 if (cnt_csr_we.hpm_lo[i] == 1'b1) begin
                     csr.mhpmcounter[i][hpm_cnt_lo_width_c-1 : 0] <= cnt_csr_we.wdata[hpm_cnt_lo_width_c-1 : 0];
                 // non-inhibited automatic update (and not in debug mode)
                 end else if ((csr.mcountinhibit_hpm[i] == 1'b0) && (hpmcnt_trigger[i] == 1'b1)) begin
                     csr.mhpmcounter[i][hpm_cnt_lo_width_c-1 : 0] <= csr.mhpmcounter_nxt[i][hpm_cnt_lo_width_c-1 : 0];
                 end
             end else begin
                 csr.mhpmcounter_ovfl[i] <= '0;
                 csr.mhpmcounter[i]      <= '0;
             end
             /* [m]hpmcounter*h */
             if ((hpm_cnt_hi_width_c > 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin
                 // write access
                 if (cnt_csr_we.hpm_hi[i] == 1'b1) begin
                     csr.mhpmcounterh[i][hpm_cnt_hi_width_c-1 : 0] <= cnt_csr_we.wdata[hpm_cnt_hi_width_c-1 : 0];
                 end else begin //  automatic update
                     csr.mhpmcounterh[i][hpm_cnt_hi_width_c-1 : 0] <= csr.mhpmcounterh[i][hpm_cnt_hi_width_c-1 : 0] + csr.mhpmcounter_ovfl[i];
                 end
             end else begin
                 csr.mhpmcounterh[i] <= '0;
             end
         end // loop
       end
    end : csr_counters

    /* counter increment */
    always_comb begin : cnt_increment
       csr.mcycle_nxt      = ({1'b0, csr.mcycle}   + 1);
       csr.minstret_nxt    = ({1'b0, csr.minstret} + 1);
       csr.mhpmcounter_nxt = '0;
       //
       for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
           csr.mhpmcounter_nxt[i] = ({1'b0, csr.mhpmcounter[i]} + 1);
       end
    end : cnt_increment

    /* hpm counter read */
    always_comb begin : hpm_connect
       csr.mhpmevent_rd    = '0;
       csr.mhpmcounter_rd  = '0;
       csr.mhpmcounterh_rd = '0;
       //
       if ((HPM_NUM_CNTS != 0) && (CPU_EXTENSION_RISCV_Zihpm == 1)) begin
          for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
             csr.mhpmevent_rd[i][hpmcnt_event_size_c-1 : 0] = csr.mhpmevent[i];
             csr.mhpmevent_rd[i][hpmcnt_event_never_c] = 1'b0; // "TIME" is always zero
             //
             if (hpm_cnt_lo_width_c > 0) begin
                 csr.mhpmcounter_rd[i][hpm_cnt_lo_width_c-1 : 0] = csr.mhpmcounter[i][hpm_cnt_lo_width_c-1 : 0];
             end
             //
             if (hpm_cnt_hi_width_c > 0) begin
                 csr.mhpmcounterh_rd[i][hpm_cnt_hi_width_c-1 : 0] = csr.mhpmcounterh[i][hpm_cnt_hi_width_c-1 : 0];
             end
          end
       end
    end : hpm_connect

    // Hardware Performance Monitor - Counter Event Control (Triggers) ---------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : hpmcnt_ctrl
       /* enable selected triggers by ANDing actual events and according CSR configuration bits */
       /* OR everything to see if counter should increment */
       hpmcnt_trigger <= '0; // default
       //
       if (HPM_NUM_CNTS != 0) begin
           for (int i = 0; i < HPM_NUM_CNTS; ++i) begin
               /* do not increment if CPU is in debug mode */
               if ((|(cnt_event & csr.mhpmevent[i][$bits(cnt_event)-1 : 0]) == 1'b1) && 
                   (debug_ctrl.running == 1'b0)) begin
                 hpmcnt_trigger[i] <= 1'b1;
               end else begin
                 hpmcnt_trigger[i] <= 1'b0;
               end
           end
       end
    end : hpmcnt_ctrl

    /* RISC-V-specific counter event triggers */
    assign cnt_event[hpmcnt_event_cy_c]      = (execute_engine.sleep == 1'b0) ? 1'b1 : 1'b0; // active cycle
    assign cnt_event[hpmcnt_event_never_c]   = 1'b0; // "never" (position would be TIME)
    assign cnt_event[hpmcnt_event_ir_c]      = (execute_engine.state == EXECUTE) ? 1'b1: 1'b0; // any executed instruction

    /* CELLRV32-specific counter event triggers */
    assign cnt_event[hpmcnt_event_cir_c]     = ((execute_engine.state == EXECUTE)    && (execute_engine.is_ci      == 1'b1)      ) ? 1'b1 : 1'b0; // executed compressed instruction
    assign cnt_event[hpmcnt_event_wait_if_c] = ((fetch_engine.state   == IF_PENDING) && (fetch_engine.state_prev   == IF_PENDING)) ? 1'b1 : 1'b0; // instruction fetch memory wait cycle
    assign cnt_event[hpmcnt_event_wait_ii_c] = ((execute_engine.state == DISPATCH)   && (execute_engine.state_prev == DISPATCH)  ) ? 1'b1 : 1'b0; // instruction issue wait cycle
    assign cnt_event[hpmcnt_event_wait_mc_c] = ((execute_engine.state == ALU_WAIT)                                               ) ? 1'b1 : 1'b0; // multi-cycle alu-operation wait cycle

    assign cnt_event[hpmcnt_event_load_c]    = ((ctrl.bus_req == 1'b1)             && (execute_engine.i_reg[instr_opcode_msb_c-1] == 1'b0)) ? 1'b1 : 1'b0; // load operation
    assign cnt_event[hpmcnt_event_store_c]   = ((ctrl.bus_req == 1'b1)             && (execute_engine.i_reg[instr_opcode_msb_c-1] == 1'b1)) ? 1'b1 : 1'b0; // store operation
    assign cnt_event[hpmcnt_event_wait_ls_c] = ((execute_engine.state == MEM_WAIT) && (execute_engine.state_prev2 == MEM_WAIT)            ) ? 1'b1 : 1'b0; // load/store memory wait cycle

    assign cnt_event[hpmcnt_event_jump_c]    = ((execute_engine.state == BRANCH)   && (execute_engine.i_reg[instr_opcode_lsb_c+2] == 1'b1)) ? 1'b1 : 1'b0; // jump (unconditional)
    assign cnt_event[hpmcnt_event_branch_c]  = ((execute_engine.state == BRANCH)   && (execute_engine.i_reg[instr_opcode_lsb_c+2] == 1'b0)) ? 1'b1 : 1'b0; // branch (conditional, taken or not taken)
    assign cnt_event[hpmcnt_event_tbranch_c] = ((execute_engine.state == BRANCHED) && (execute_engine.state_prev == BRANCH) &&
                                                (execute_engine.i_reg[instr_opcode_lsb_c+2] == 1'b0)) ? 1'b1 : 1'b0; // taken branch (conditional)

    assign cnt_event[hpmcnt_event_trap_c]    = (trap_ctrl.env_start_ack == 1'b1) ? 1'b1 : 1'b0; // entered trap
    assign cnt_event[hpmcnt_event_illegal_c] = ((trap_ctrl.env_start_ack == 1'b1) && (trap_ctrl.cause == trap_iil_c)) ? 1'b1 : 1'b0; // illegal operation

    // ****************************************************************************************************************************
    // CPU Debug Mode (Part of the On-Chip Debugger)
    // ****************************************************************************************************************************

    // Debug Control -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : debug_control
       if (rstn_i == 1'b0) begin
          debug_ctrl.ext_halt_req <= 1'b0;
          debug_ctrl.state        <= DEBUG_OFFLINE;
       end else begin
         if (CPU_EXTENSION_RISCV_Sdext == 1) begin
             debug_ctrl.ext_halt_req <= db_halt_req_i; // external halt request (from Debug Module)
             // state machine
             unique case (debug_ctrl.state)
                 /* waiting to start debug mode */
                 DEBUG_OFFLINE : begin
                     // processing trap entry into debug mode
                     if ((trap_ctrl.env_start_ack == 1'b1) && (trap_ctrl.cause[5] == 1'b1)) begin
                         debug_ctrl.state <= DEBUG_ONLINE;
                     end
                 end

                 /* we are in debug mode */
                 DEBUG_ONLINE : begin
                     // DRET instruction
                     if (debug_ctrl.dret == 1'b1) begin
                         debug_ctrl.state <= DEBUG_LEAVING;
                     end
                 end

                 /* leaving debug mode */
                 DEBUG_LEAVING : begin
                     // processing trap exit (updating PC and status registers)
                     if (execute_engine.state == TRAP_EXECUTE) begin
                         debug_ctrl.state <= DEBUG_OFFLINE;
                     end
                 end

                 /* undefined */
                 default: begin
                     debug_ctrl.state <= DEBUG_OFFLINE;
                 end
             endcase
         end else begin
             debug_ctrl.ext_halt_req <= 1'b0;
             debug_ctrl.state        <= DEBUG_OFFLINE;
         end
       end
    end : debug_control

    /* CPU is in debug mode */
    assign debug_ctrl.running = ((CPU_EXTENSION_RISCV_Sdext == 0) || (debug_ctrl.state == DEBUG_OFFLINE)) ? 1'b0 : 1'b1;

    /* entry debug mode triggers */
    assign debug_ctrl.trig_hw    = hw_trigger_fire & (~debug_ctrl.running) & csr.tdata1_action & csr.tdata1_dmode; // enter debug mode by HW trigger module request (only valid if dmode = 1)
    assign debug_ctrl.trig_break = trap_ctrl.break_point & (debug_ctrl.running | // re-enter debug mode
                                   (( csr.privilege) & csr.dcsr_ebreakm) |       // enabled goto-debug-mode in machine mode on "ebreak"
                                   ((~csr.privilege) & csr.dcsr_ebreaku));       // enabled goto-debug-mode in user mode on "ebreak"
    assign debug_ctrl.trig_halt  = debug_ctrl.ext_halt_req & (~debug_ctrl.running); // external halt request (if not halted already)
    assign debug_ctrl.trig_step  = csr.dcsr_step & (~debug_ctrl.running); // single-step mode (trigger when NOT CURRENTLY in debug mode)

    // Debug Control and Status Register (dcsr) - Read-Back -----------------------------------
    // -------------------------------------------------------------------------------------------
    assign csr.dcsr_rd[31 : 28] = 4'b0100;          // xdebugver: external debug support compatible to spec. version 1.0
    assign csr.dcsr_rd[27 : 16] = '0;              // reserved
    assign csr.dcsr_rd[15]      = csr.dcsr_ebreakm; // ebreakm: what happens on ebreak in m-mode? (normal trap OR debug-enter)
    assign csr.dcsr_rd[14]      = 1'b0;             // ebreakh: hypervisor mode not implemented
    assign csr.dcsr_rd[13]      = 1'b0;             // ebreaks: supervisor mode not implemented
    assign csr.dcsr_rd[12]      = (CPU_EXTENSION_RISCV_U == 1) ? csr.dcsr_ebreaku : 1'b0; // ebreaku: what happens on ebreak in u-mode? (normal trap OR debug-enter)
    assign csr.dcsr_rd[11]      = 1'b0; // stepie: interrupts are disabled during single-stepping
    assign csr.dcsr_rd[10]      = 1'b1; // stopcount: standard counters and HPMs are stopped when in debug mode
    assign csr.dcsr_rd[09]      = 1'b0; // stoptime: timers increment as usual
    assign csr.dcsr_rd[08 : 06] = csr.dcsr_cause; // debug mode entry cause
    assign csr.dcsr_rd[05]      = 1'b0; // reserved
    assign csr.dcsr_rd[04]      = 1'b1; // mprven: mstatus.mprv is also evaluated in debug mode
    assign csr.dcsr_rd[03]      = 1'b0; // nmip: no pending non-maskable interrupt
    assign csr.dcsr_rd[02]      = csr.dcsr_step; // step: single-step mode
    assign csr.dcsr_rd[01 : 00] = csr.dcsr_prv ? '1 : '0; // prv: privilege mode when debug mode was entered

    // ****************************************************************************************************************************
    // Hardware Trigger Module (Part of the On-Chip Debugger)
    // ****************************************************************************************************************************

    /* trigger to enter debug-mode: instruction address match (fire AFTER execution) */
    assign hw_trigger_fire = ((CPU_EXTENSION_RISCV_Sdtrig == 1) && (csr.tdata1_exe == 1'b1) &&
                              (csr.tdata2[XLEN-1 : 1] == execute_engine.pc[XLEN-1 : 1]) &&
                              (execute_engine.state == EXECUTE)) ? 1'b1 : 1'b0;

    // Match Control CSR (mcontrol @ tdata1) - Read-Back -----------------------------------------
    // -------------------------------------------------------------------------------------------
    assign csr.tdata1_rd[31 : 28] = 4'b0010; // type: address(/data) match trigger
    assign csr.tdata1_rd[27]      = csr.tdata1_dmode; // dmode: set to ignore machine-mode access to tdata* CSRs
    assign csr.tdata1_rd[26 : 21] = 6'b000000; // maskmax: only exact values
    assign csr.tdata1_rd[20]      = 1'b0; // hit: feature not implemented
    assign csr.tdata1_rd[19]      = 1'b0; // select: fire on address match
    assign csr.tdata1_rd[18]      = 1'b1; // timing: trigger **after** executing the triggering instruction
    assign csr.tdata1_rd[17 : 16] = 2'b00; // sizelo: match against an access of any size
    assign csr.tdata1_rd[15 : 12] = {3'b000, csr.tdata1_action}; // action: 1: enter debug mode on trigger, 0: ebreak exception on trigger
    assign csr.tdata1_rd[11]      = 1'b0; // chain: chaining not supported - there is only one trigger
    assign csr.tdata1_rd[10 : 07] = 4'b0000; // match: only full-address-match
    assign csr.tdata1_rd[6]       = 1'b1; // m: trigger enabled when in machine mode
    assign csr.tdata1_rd[5]       = 1'b0; // h: hypervisor mode not supported
    assign csr.tdata1_rd[4]       = 1'b0; // s: supervisor mode not supported
    assign csr.tdata1_rd[3]       = (CPU_EXTENSION_RISCV_U == 1) ? 1'b1 : 1'b0; // u: trigger enabled when in user mode
    assign csr.tdata1_rd[2]       = csr.tdata1_exe; // execute: enable trigger
    assign csr.tdata1_rd[1]       = 1'b0; // store: store address or data matching not supported
    assign csr.tdata1_rd[0]       = 1'b0; // load: load address or data matching not supported
    
endmodule