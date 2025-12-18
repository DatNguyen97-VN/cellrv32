// ##################################################################################################
// # << CELLRV32 - Arithmetical/Logical Unit >>                                                     #
// # ********************************************************************************************** #
// # Main data/address ALU and ALU co-processors (= multi-cycle function units).                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_alu #(
    parameter int XLEN             = 32,  // data path width
    parameter int VLEN             = 256, // vector length
    parameter int VECTOR_LANES     = 8,   // Number of SIMD lanes (width of vector datapath)
	parameter int VECTOR_REGISTERS = 32,  // Number of architectural vector registers
    /* RISC-V CPU Extensions */
    parameter int CPU_EXTENSION_RISCV_B      = 0, // implement bit-manipulation extension?
    parameter int CPU_EXTENSION_RISCV_M      = 0, // implement mul/div extension?
    parameter int CPU_EXTENSION_RISCV_V      = 0, // implement vector extension?
    parameter int CPU_EXTENSION_RISCV_Zmmul  = 0, // implement multiply-only M sub-extension?
    parameter int CPU_EXTENSION_RISCV_Zfinx  = 0, // implement 32-bit floating-point extension (using INT reg!)
    parameter int CPU_EXTENSION_RISCV_Zhinx  = 0, // implement 16-bit floating-point extension (using INT reg!)
    parameter int CPU_EXTENSION_RISCV_Zxcfu  = 0, // implement custom (instr.) functions unit?
    parameter int CPU_EXTENSION_RISCV_Zicond = 0, // implement conditional operations extension?
    /* Extension Options */
    parameter int FAST_MUL_EN                = 0,  // use DSPs for M extension's multiplier
    parameter int FAST_SHIFT_EN              = 0,  // use barrel shifter for shift operations
    parameter int VECTOR_FP_ALU              = 0   // Enable floating-point lanes
)(
    /* global control */
    input  logic            clk_i,       // global clock, rising edge
    input  logic            rstn_i,      // global reset, low-active, async
    input  ctrl_bus_t       ctrl_i,      // main control bus
    /* data input */
    input  logic [XLEN-1:0] rs1_i,       // rf source 1
    input  logic [XLEN-1:0] rs2_i,       // rf source 2
    input  logic [XLEN-1:0] rs3_i,       // rf source 3
    input  logic [XLEN-1:0] rs4_i,       // rf source 4
    input  logic [XLEN-1:0] pc_i,        // current PC
    input  logic [XLEN-1:0] imm_i,       // immediate
    /* data output */
    output logic [1:0]      cmp_o,       // comparator status
    output logic [XLEN-1:0] res_o,       // ALU result
    output logic [XLEN-1:0] add_o,       // address computation result
    output logic [4:0]      fpu_flags_o, // FPU exception flags
    /* vector memory interface */
    output vector_mem_req   mem_req_o,   // Address bus output (for load/store data)
    output logic            req_valid_o, // Indicates a valid memory request
    input  vector_mem_resp  mem_resp_i,  // Data bus
    input  logic            resp_valid_i,// Indicates a valid memory response
    input  logic            multi_rsp_i, // multi-cycle response valid
    /* status */
    output logic            exc_o,       // ALU exception
    output logic            cp_done_o    // co-processor operation done?
);

    /* comparator */
    logic [XLEN:0]   cmp_rs1;
    logic [XLEN:0]   cmp_rs2;
    logic [1:0]      cmp; // comparator status

    /* operands */
    logic [XLEN-1:0] opa;
    logic [XLEN-1:0] opb;

    /* intermediate results */
    logic [XLEN:0]   addsub_res;
    logic [XLEN-1:0] cp_res;

    /* co-processor monitor */
    typedef struct {
        logic run;
        logic fin;
        logic exc;
        logic [cp_timeout_c:0] cnt; // timeout counter
    } cp_monitor_t;
    cp_monitor_t cp_monitor;

    /* co-processor interface */
    typedef logic [XLEN-1:0] cp_data_if_t [6:0];
    cp_data_if_t cp_result; // co-processor result
    logic [7:0] cp_start;   // trigger co-processor
    logic [7:0] cp_valid;   // co-processor done
    logic [4:0] fpu32_flags; // fp32 flags
    logic [4:0] fpu16_flags; // fp16 flags
 
    // Comparator Unit (for conditional branches) ------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign cmp_rs1 = {(rs1_i[$bits(rs1_i)-1] & (~ctrl_i.alu_unsigned)), rs1_i}; // optional sign-extension
    assign cmp_rs2 = {(rs2_i[$bits(rs2_i)-1] & (~ctrl_i.alu_unsigned)), rs2_i}; // optional sign-extension

    assign cmp[cmp_equal_c] = (rs1_i == rs2_i) ? 1'b1 : 1'b0;
    assign cmp[cmp_less_c]  = (signed'(cmp_rs1) < signed'(cmp_rs2)) ? 1'b1 : 1'b0;  // signed or unsigned comparison
    assign cmp_o            = cmp;

    // ALU Input Operand Select ------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign opa = (ctrl_i.alu_opa_mux == 1'b1) ? pc_i  : rs1_i;
    assign opb = (ctrl_i.alu_opb_mux == 1'b1) ? imm_i : rs2_i;

    // Adder/Subtracter Core ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    logic [XLEN:0] opa_v, opb_v;
    logic carry; // only for subtract operation

    // Local propagate and generate signals
    logic [30:0] p, g;
    
    // Propagate/Generate at each prefix level (5-stage tree)
    logic [15:0] p1, p2, p3, p4, p5;
    logic [15:0] g1, g2, g3, g4, g5;
    logic g6;

    /* direct output of adder result */
    assign add_o = addsub_res[XLEN-1 : 0];

    always_comb begin : arithmetic_core
        // operand sign-extension
        opa_v = {(opa[$bits(opa)-1] & (~ctrl_i.alu_unsigned)), opa};
        carry     = 1'b0;
        // add/sub(slt) select
        if (ctrl_i.alu_op[0]) begin
           opb_v = ~{(opb[$bits(opb)-1] & (~ctrl_i.alu_unsigned)), opb};
           carry     = 1'b1;
        end else begin
           opb_v = {(opb[$bits(opb)-1] & (~ctrl_i.alu_unsigned)), opb};
        end
    end : arithmetic_core

    // ----------------------------------------------------------------------------
    // Initial propagate and generate terms
    // ----------------------------------------------------------------------------
    assign p = opa_v | opb_v; // propagate
    assign g = opa_v & opb_v; // generate

    // ----------------------------------------------------------------------------
    // Prefix tree
    // Each stage combines carries at increasing distance (1, 2, 4, 8, 16)
    // ----------------------------------------------------------------------------
    
    // Level 1: distance 1
    assign {p1, g1} = pro_and_gen_f ({p[30], p[28], p[26], p[24], p[22], p[20], p[18], p[16], p[14], p[12], p[10], p[08], p[06], p[04], p[02], p[0]},
                                     {p[29], p[27], p[25], p[23], p[21], p[19], p[17], p[15], p[13], p[11], p[09], p[07], p[05], p[03], p[01], 1'b0},
                                     {g[30], g[28], g[26], g[24], g[22], g[20], g[18], g[16], g[14], g[12], g[10], g[08], g[06], g[04], g[02], g[0]},
                                     {g[29], g[27], g[25], g[23], g[21], g[19], g[17], g[15], g[13], g[11], g[09], g[07], g[05], g[03], g[01], carry});
                   
    // Level 2: distance 2
    assign {p2, g2} = pro_and_gen_f ({p1[15],p[29], p1[13],p[25], p1[11],p[21], p1[09],p[17], p1[07],p[13], p1[05],p[09], p1[03],p[05], p1[01],p[01]},
                                     {{02{p1[14]}}, {02{p1[12]}}, {02{p1[10]}}, {02{p1[08]}}, {02{p1[06]}}, {02{p1[04]}}, {02{p1[02]}}, {02{p1[00]}}},
                                     {g1[15],g[29], g1[13],g[25], g1[11],g[21], g1[09],g[17], g1[07],g[13], g1[05],g[09], g1[03],g[05], g1[01],g[01]},
                                     {{02{g1[14]}}, {02{g1[12]}}, {02{g1[10]}}, {02{g1[08]}}, {02{g1[06]}}, {02{g1[04]}}, {02{g1[02]}}, {02{g1[00]}}});
    
    // Level 3: distance 4
    assign {p3, g3} = pro_and_gen_f ({p2[15],p2[14],p1[14],p[27], p2[11],p2[10],p1[10],p[19], p2[7],p2[6],p1[6],p[11], p2[3],p2[2],p1[2],p[3]},
                                     {{4{p2[13]}}               , {4{p2[9]}}                , {4{p2[5]}}             , {4{p2[1]}}}            ,
                                     {g2[15],g2[14],g1[14],g[27], g2[11],g2[10],g1[10],g[19], g2[7],g2[6],g1[6],g[11], g2[3],g2[2],g1[2],g[3]},
                                     {{4{g2[13]}}               , {4{g2[9]}}                , {4{g2[5]}}             , {4{g2[1]}}}            );
    
    // Level 4: distance 8
    assign {p4, g4} = pro_and_gen_f ({p3[15:12],p2[13:12],p1[12],p[23], p3[7:4],p2[5:4],p1[4],p[7]},
                                     {{8{p3[11]}}                     , {8{p3[3]}}}                ,
                                     {g3[15:12],g2[13:12],g1[12],g[23], g3[7:4],g2[5:4],g1[4],g[7]},
                                     {{8{g3[11]}}                     , {8{g3[3]}}}                );
    
    // Level 5: distance 16
    assign {p5, g5} = pro_and_gen_f ({p4[15:8],p3[11:8],p2[9:8],p1[8],p[15]},
                                     {{16{p4[7]}}},
                                     {g4[15:8],g3[11:8],g2[9:8],g1[8],g[15]},
                                     {{16{g4[7]}}}                          );
    
    // Level 6: distance 32 (final carry out)
    assign g6 = (opa_v[31] & opb_v[31]) | (g5[15] & (opa_v[31] | opb_v[31]));

    // ----------------------------------------------------------------------------
    // Final sum/carry computation
    // ----------------------------------------------------------------------------
    assign addsub_res = opa_v ^ opb_v ^ {g6, g5, g4[7:0], g3[3:0], g2[1:0], g1[0], carry};

    // ALU Operation Select ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : alu_core
        unique case (ctrl_i.alu_op)
            alu_op_add_c  : res_o =  addsub_res[XLEN-1 : 0];
            alu_op_sub_c  : res_o =  addsub_res[XLEN-1 : 0];
            alu_op_cp_c   : res_o =  cp_res;
            alu_op_slt_c  : res_o =  {'0, addsub_res[XLEN]};
            alu_op_movb_c : res_o =  opb;
            alu_op_xor_c  : res_o =  rs1_i ^ opb;
            alu_op_or_c   : res_o =  rs1_i | opb;
            alu_op_and_c  : res_o =  rs1_i & opb;
            default: begin
                res_o = addsub_res[XLEN-1 : 0];
            end
        endcase
    end : alu_core

    // **************************************************************************************************************************
    // ALU Co-Processors
    // **************************************************************************************************************************

    // Co-Processor Control ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : coprocessor_monitor
        // make sure that no co-processor iterates forever stalling the entire CPU;
        // an illegal instruction exception is raised if a co-processor operation
        // takes longer than 2^cp_timeout_c cycles
        if (rstn_i == 1'b0) begin
            cp_monitor.run <= 1'b0;
            cp_monitor.fin <= 1'b0;
            cp_monitor.exc <= 1'b0;
            cp_monitor.cnt <= '0;
        end else begin
            cp_monitor.exc <= cp_monitor.run & cp_monitor.cnt[$bits(cp_monitor.cnt)-1] & (~cp_monitor.fin);
            cp_monitor.fin <= |cp_valid;
            // co-processors are idle
            if (cp_monitor.run == 1'b0) begin
                cp_monitor.cnt <= '0;
                if ((|ctrl_i.alu_cp_trig) == 1'b1) begin // start
                    cp_monitor.run <= 1'b1;
                end
            end else begin // co-processor operation in progress
                cp_monitor.cnt <= cp_monitor.cnt + 1'b1;
                if ((cp_monitor.fin == 1'b1) || (ctrl_i.cpu_trap == 1'b1)) begin // done or abort
                    cp_monitor.run <= 1'b0;
                end
            end
        end
    end : coprocessor_monitor

    /* ALU processing exception */
    assign exc_o = cp_monitor.exc;

    /* co-processor select / start trigger */
    // -- > "cp_start" is high for one cycle to trigger operation of the according co-processor
    assign cp_start = ctrl_i.alu_cp_trig;

    /* (iterative) co-processor operation done? */
    // -- > "cp_valid" signal has to be set (for one cycle) one cycle before CP output data (cp_result) is valid
    assign cp_done_o = |cp_valid;

    /* exceoption flags */
    assign fpu_flags_o = fpu32_flags | fpu16_flags;

    /* co-processor result */
    // -- > "cp_result" data has to be always zero unless the specific co-processor has been actually triggered
    assign cp_res = cp_result[cp_sel_shifter_c]  | cp_result[cp_sel_muldiv_c] | 
                    cp_result[cp_sel_bitmanip_c] | cp_result[cp_sel_fpu32_c]  | 
                    cp_result[cp_sel_fpu16_c]    | cp_result[cp_sel_cfu_c]    | 
                    cp_result[cp_sel_cond_c];

    // -------------------------------------------------------------------------------------------
    // Co-Processor 0: Shifter Unit ('I'/'E' Base ISA) -------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_cpu_cp_shifter  #(
        .XLEN          (XLEN),
        .FAST_SHIFT_EN (FAST_SHIFT_EN)
    )
    cellrv32_cpu_cp_shifter_inst (
        /* global control */
        .clk_i   (clk_i),        // global clock, rising edge
        .rstn_i  (rstn_i),       // global reset, low-active, async
        .ctrl_i  (ctrl_i),       // main control bus
        .start_i (cp_start[cp_sel_shifter_c]),  // trigger operation
        /* data input */
        .rs1_i   (rs1_i),        // rf source 1
        .shamt_i (opb[$clog2(XLEN)-1:0]), // shift amount
        /* result and status */
        .res_o   (cp_result[cp_sel_shifter_c]), // operation result
        .valid_o (cp_valid[cp_sel_shifter_c])   // data output valid
    );

    // -------------------------------------------------------------------------------------------
    // Co-Processor 1: int Multiplication/Division Unit ('M' Extension) ----------------------
    // -------------------------------------------------------------------------------------------
    generate
        if ((CPU_EXTENSION_RISCV_M == 1'b1) || (CPU_EXTENSION_RISCV_Zmmul == 1'b1)) begin : cellrv32_cpu_cp_muldiv_inst_ON
            cellrv32_cpu_cp_muldiv #(
                .XLEN        (XLEN),
                .FAST_MUL_EN (FAST_MUL_EN),
                .DIVISION_EN (CPU_EXTENSION_RISCV_M)
            ) cellrv32_cpu_cp_muldiv_inst (
                /* global control */
                .clk_i   ( clk_i),       // global clock, rising edge
                .rstn_i  (rstn_i),       // global reset, low-active, async
                .ctrl_i  (ctrl_i),       // main control bus
                .start_i (cp_start[cp_sel_muldiv_c]),  // trigger operation
                /* data input */
                .rs1_i   (rs1_i),        // rf source 1
                .rs2_i   (rs2_i),        // rf source 2
                /* result and status */
                .res_o   (cp_result[cp_sel_muldiv_c]), // operation result
                .valid_o (cp_valid[cp_sel_muldiv_c])   // data output valid
            );
        end : cellrv32_cpu_cp_muldiv_inst_ON
    endgenerate

    generate
        if ((CPU_EXTENSION_RISCV_M == 1'b0) && (CPU_EXTENSION_RISCV_Zmmul == 1'b0)) begin : cellrv32_cpu_cp_muldiv_inst_OFF
            assign cp_result[cp_sel_muldiv_c] = '0;
            assign cp_valid[cp_sel_muldiv_c]  = 1'b0;
        end : cellrv32_cpu_cp_muldiv_inst_OFF
    endgenerate

    // -------------------------------------------------------------------------------------------
    // Co-Processor 2: Bit-Manipulation Unit ('B' Extension) -------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (CPU_EXTENSION_RISCV_B == 1'b1) begin : cellrv32_cpu_cp_bitmanip_inst_ON
            cellrv32_cpu_cp_bitmanip #(
                .XLEN          (XLEN),
                .FAST_SHIFT_EN (FAST_SHIFT_EN)
            ) cellrv32_cpu_cp_bitmanip_inst (
                /* global control */
                .clk_i   ( clk_i),       // global clock, rising edge
                .rstn_i  (rstn_i),       // global reset, low-active, async
                .ctrl_i  (ctrl_i),       // main control bus
                .start_i (cp_start[cp_sel_bitmanip_c]),  // trigger operation
                /* data input */
                .cmp_i   (cmp),          // comparator status
                .rs1_i   (rs1_i),        // rf source 1
                .rs2_i   (rs2_i),        // rf source 2
                .shamt_i (opb[$clog2(XLEN)-1:0]), // shift amount
                /* result and status */
                .res_o   (cp_result[cp_sel_bitmanip_c]), // operation result
                .valid_o (cp_valid[cp_sel_bitmanip_c])   // data output valid
            );
        end : cellrv32_cpu_cp_bitmanip_inst_ON
    endgenerate

    generate
        if (CPU_EXTENSION_RISCV_B == 1'b0) begin : cellrv32_cpu_cp_bitmanip_inst_OFF
            assign cp_result[cp_sel_bitmanip_c] = '0;
            assign cp_valid[cp_sel_bitmanip_c]  = 1'b0;
        end : cellrv32_cpu_cp_bitmanip_inst_OFF
    endgenerate

    // --------------------------------------------------------------------------------------------
    // Co-Processor 3: Single-Precision Floating-Point Unit ('Zfinx' Extension) ------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zfinx == 1'b1) begin : cellrv32_cpu_cp_fpu32_inst_ON
           cellrv32_cpu_cp_fpu32 #(
               .XLEN (XLEN)
           ) cellrv32_cpu_cp_fpu32_inst (
               /* global control */
               .clk_i    (clk_i),        // global clock, rising edge
               .rstn_i   (rstn_i),       // global reset, low-active, async
               .ctrl_i   (ctrl_i),       // main control bus
               .start_i  (cp_start[cp_sel_fpu32_c]),  // trigger operation
               /* data input */
               .cmp_i    (cmp),          // comparator status
               .rs1_i    (rs1_i),        // rf source 1
               .rs2_i    (rs2_i),        // rf source 2
               .rs3_i    (rs3_i),        // rf source 3
               /* result and status */
               .res_o    (cp_result[cp_sel_fpu32_c]), // operation result
               .fflags_o (fpu32_flags),  // exception flags
               .valid_o  (cp_valid[cp_sel_fpu32_c])   // data output valid
           );
       end : cellrv32_cpu_cp_fpu32_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zfinx == 1'b0) begin : cellrv32_cpu_cp_fpu32_inst_OFF
           assign cp_result[cp_sel_fpu32_c] = '0;
           assign fpu32_flags  = '0;
           assign cp_valid[cp_sel_fpu32_c]  = 1'b0;
       end : cellrv32_cpu_cp_fpu32_inst_OFF
    endgenerate

    // --------------------------------------------------------------------------------------------
    // Co-Processor 4: Half-Precision Floating-Point Unit ('Zhinx' Extension) ------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zhinx == 1'b1) begin : cellrv32_cpu_cp_fpu16_inst_ON
           cellrv32_cpu_cp_fpu16 #(
               .XLEN (XLEN)
           ) cellrv32_cpu_cp_fpu16_inst (
               /* global control */
               .clk_i    (clk_i),        // global clock, rising edge
               .rstn_i   (rstn_i),       // global reset, low-active, async
               .ctrl_i   (ctrl_i),       // main control bus
               .start_i  (cp_start[cp_sel_fpu16_c]),  // trigger operation
               /* data input */
               .cmp_i    (cmp),          // comparator status
               .rs1_i    (rs1_i),        // rf source 1
               .rs2_i    (rs2_i),        // rf source 2
               .rs3_i    (rs3_i),        // rf source 3
               /* result and status */
               .res_o    (cp_result[cp_sel_fpu16_c]), // operation result
               .fflags_o (fpu16_flags),  // exception flags
               .valid_o  (cp_valid[cp_sel_fpu16_c])   // data output valid
           );
       end : cellrv32_cpu_cp_fpu16_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zhinx == 1'b0) begin : cellrv32_cpu_cp_fpu16_inst_OFF
           assign cp_result[cp_sel_fpu16_c] = '0;
           assign fpu16_flags  = '0;
           assign cp_valid[cp_sel_fpu16_c]  = 1'b0;
       end : cellrv32_cpu_cp_fpu16_inst_OFF
    endgenerate

    // -------------------------------------------------------------------------------------------
    // Co-Processor 5: Custom (Instructions) Functions Unit ('Zxcfu' Extension) ------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zxcfu == 1'b1) begin : cellrv32_cpu_cp_cfu_inst_ON
           cellrv32_cpu_cp_cfu #(
               .XLEN(XLEN)
           ) cellrv32_cpu_cp_cfu_inst (
               /* global control */
               .clk_i   (clk_i),        // global clock, rising edge
               .rstn_i  (rstn_i),       // global reset, low-active, async
               .ctrl_i  (ctrl_i),       // main control bus
               .start_i (cp_start[cp_sel_cfu_c]),  // trigger operation
               /* data input */
               .rs1_i   (rs1_i),        // rf source 1
               .rs2_i   (rs2_i),        // rf source 2
               .rs3_i   (rs3_i),        // rf source 3
               .rs4_i   (rs4_i),        // rf source 4
               /* result and status */
               .res_o   (cp_result[cp_sel_cfu_c]), // operation result
               .valid_o (cp_valid[cp_sel_cfu_c])   // data output valid
           );
       end : cellrv32_cpu_cp_cfu_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zxcfu == 1'b0) begin : cellrv32_cpu_cp_cfu_inst_OFF
           assign cp_result[cp_sel_cfu_c] = '0;
           assign cp_valid[cp_sel_cfu_c]  = 1'b0;
       end : cellrv32_cpu_cp_cfu_inst_OFF
    endgenerate

    // -------------------------------------------------------------------------------------------
    // Co-Processor 6: Conditional Operations ('Zicond' Extension) -------------------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zicond == 1'b1) begin : cellrv32_cpu_cp_cond_inst_ON
           cellrv32_cpu_cp_cond #(.XLEN(XLEN))
           cellrv32_cpu_cp_cond_inst (
               /* global control */
               .clk_i   (clk_i),        // global clock, rising edge
               .ctrl_i  (ctrl_i),       // main control bus
               .start_i (cp_start[cp_sel_cond_c]),  // trigger operation
               /* data input */
               .rs1_i   (rs1_i),        // rf source 1
               .rs2_i   (rs2_i),        // rf source 2
               /* result and status */
               .res_o   (cp_result[cp_sel_cond_c]), // operation result
               .valid_o (cp_valid[cp_sel_cond_c])   // data output valid
           );
       end : cellrv32_cpu_cp_cond_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zicond == 1'b0) begin : cellrv32_cpu_cp_cond_inst_OFF
           assign cp_result[cp_sel_cond_c] = '0;
           assign cp_valid[cp_sel_cond_c]  = 1'b0;
       end : cellrv32_cpu_cp_cond_inst_OFF
    endgenerate

    // -------------------------------------------------------------------------------------------
    // Co-Processor 7: Vector Operations ('V' Extension) -----------------------------------------
    // -------------------------------------------------------------------------------------------
    generate  
        if (CPU_EXTENSION_RISCV_V == 1) begin : cellrv32_cpu_cp_vector_inst_ON
                cellrv32_cpu_cp_vector #(
                .VECTOR_REGISTERS  (VECTOR_REGISTERS),
                .VECTOR_LANES      (VECTOR_LANES),
                .DATA_WIDTH        (XLEN),
                .VECTOR_REQ_WIDTH  (VLEN)
            ) cellrv32_cpu_cp_vector_inst (
                // global control
                .clk_i            (clk_i),
                .rstn_i           (rstn_i),
                .vector_idle_o    ( ),
                .valid_in         (cp_start[cp_sel_vector_c]), // trigger operation
                .pop              (),
                .ctrl_i           (ctrl_i),
                /* data input */
                .rs1_i            (rs1_i), // rf source 1
                .rs2_i            (rs2_i), // rf source 2
                //Cache Request Interface
                .mem_req_valid_o  ( req_valid_o),
                .mem_req_o        (mem_req_o),
                .cache_ready_i    (multi_rsp_i),
                //Cache Response Interface
                .mem_resp_valid_i (resp_valid_i ),
                .mem_resp_i       (mem_resp_i),
                /* result and status */
                .valid_o(cp_valid[cp_sel_vector_c]) // data output valid
            );
        end : cellrv32_cpu_cp_vector_inst_ON
    endgenerate

    generate
        if (CPU_EXTENSION_RISCV_V == 0) begin : cellrv32_cpu_cp_vector_inst_OFF
            assign cp_valid[cp_sel_vector_c] = 1'b0;
        end : cellrv32_cpu_cp_vector_inst_OFF
    endgenerate

endmodule
