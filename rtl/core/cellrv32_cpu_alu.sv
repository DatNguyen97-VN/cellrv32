// ##################################################################################################
// # << CELLRV32 - Arithmetical/Logical Unit >>                                                     #
// # ********************************************************************************************** #
// # Main data/address ALU and ALU co-processors (= multi-cycle function units).                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_alu #(
    parameter XLEN = 32, // data path width
    /* RISC-V CPU Extensions */
    parameter CPU_EXTENSION_RISCV_B      = 0, // implement bit-manipulation extension?
    parameter CPU_EXTENSION_RISCV_M      = 0, // implement mul/div extension?
    parameter CPU_EXTENSION_RISCV_Zmmul  = 0, // implement multiply-only M sub-extension?
    parameter CPU_EXTENSION_RISCV_Zfinx  = 0, // implement 32-bit floating-point extension (using INT reg!)
    parameter CPU_EXTENSION_RISCV_Zxcfu  = 0, // implement custom (instr.) functions unit?
    parameter CPU_EXTENSION_RISCV_Zicond = 0, // implement conditional operations extension?
    /* Extension Options */
    parameter FAST_MUL_EN                = 0,  // use DSPs for M extension's multiplier
    parameter FAST_SHIFT_EN              = 0   // use barrel shifter for shift operations
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
    typedef logic [XLEN-1:0] cp_data_if_t [5:0];
    cp_data_if_t cp_result; // co-processor result
    logic [5:0]  cp_start ; // trigger co-processor
    logic [5:0]  cp_valid ; // co-processor done

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

    always_comb begin : arithmetic_core
        // operand sign-extension
        opa_v = {(opa[$bits(opa)-1] & (~ctrl_i.alu_unsigned)), opa};
        opb_v = {(opb[$bits(opb)-1] & (~ctrl_i.alu_unsigned)), opb};
        // add/sub(slt) select
        if (ctrl_i.alu_op[0] == 1'b1) 
           addsub_res = opa_v - opb_v;
        else 
           addsub_res = opa_v + opb_v;
    end : arithmetic_core
    
    /* direct output of adder result */
    assign add_o = addsub_res[XLEN-1 : 0];

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

    /* co-processor result */
    // -- > "cp_result" data has to be always zero unless the specific co-processor has been actually triggered
    assign cp_res = cp_result[0] | cp_result[1] | cp_result[2] | cp_result[3] | cp_result[4] | cp_result[5];
    
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
        .start_i (cp_start[0]),  // trigger operation
        /* data input */
        .rs1_i   (rs1_i),        // rf source 1
        .shamt_i (opb[index_size_f(XLEN)-1:0]), // shift amount
        /* result and status */
        .res_o   (cp_result[0]), // operation result
        .valid_o (cp_valid[0])   // data output valid
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
                .start_i (cp_start[1]),  // trigger operation
                /* data input */
                .rs1_i   (rs1_i),        // rf source 1
                .rs2_i   (rs2_i),        // rf source 2
                /* result and status */
                .res_o   (cp_result[1]), // operation result
                .valid_o (cp_valid[1])   // data output valid
            );
        end : cellrv32_cpu_cp_muldiv_inst_ON
    endgenerate

    generate
        if ((CPU_EXTENSION_RISCV_M == 1'b0) && (CPU_EXTENSION_RISCV_Zmmul == 1'b0)) begin : cellrv32_cpu_cp_muldiv_inst_OFF
            assign cp_result[1] = '0;
            assign cp_valid[1]  = 1'b0;
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
                .start_i (cp_start[2]),  // trigger operation
                /* data input */
                .cmp_i   (cmp),          // comparator status
                .rs1_i   (rs1_i),        // rf source 1
                .rs2_i   (rs2_i),        // rf source 2
                .shamt_i (opb[index_size_f(XLEN)-1:0]), // shift amount
                /* result and status */
                .res_o   (cp_result[2]), // operation result
                .valid_o (cp_valid[2])   // data output valid
            );
        end : cellrv32_cpu_cp_bitmanip_inst_ON
    endgenerate

    generate
        if (CPU_EXTENSION_RISCV_B == 1'b0) begin : cellrv32_cpu_cp_bitmanip_inst_OFF
            assign cp_result[2] = '0;
            assign cp_valid[2]  = 1'b0;
        end : cellrv32_cpu_cp_bitmanip_inst_OFF
    endgenerate
    
    // --------------------------------------------------------------------------------------------
    // Co-Processor 3: Single-Precision Floating-Point Unit ('Zfinx' Extension) ------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zfinx == 1'b1) begin : cellrv32_cpu_cp_fpu_inst_ON
           cellrv32_cpu_cp_fpu #(
               .XLEN (XLEN)
           ) cellrv32_cpu_cp_fpu_inst (
               /* global control */
               .clk_i    (clk_i),        // global clock, rising edge
               .rstn_i   (rstn_i),       // global reset, low-active, async
               .ctrl_i   (ctrl_i),       // main control bus
               .start_i  (cp_start[3]),  // trigger operation
               /* data input */
               .cmp_i    (cmp),          // comparator status
               .rs1_i    (rs1_i),        // rf source 1
               .rs2_i    (rs2_i),        // rf source 2
               .rs3_i    (rs3_i),        // rf source 3
               /* result and status */
               .res_o    (cp_result[3]), // operation result
               .fflags_o (fpu_flags_o),  // exception flags
               .valid_o  (cp_valid[3])   // data output valid
           );
       end : cellrv32_cpu_cp_fpu_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zfinx == 1'b0) begin : cellrv32_cpu_cp_fpu_inst_OFF
           assign cp_result[3] = '0;
           assign fpu_flags_o  = '0;
           assign cp_valid[3]  = 1'b0;
       end : cellrv32_cpu_cp_fpu_inst_OFF
    endgenerate
     
    // -------------------------------------------------------------------------------------------
    // Co-Processor 4: Custom (Instructions) Functions Unit ('Zxcfu' Extension) ------------------
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
               .start_i (cp_start[4]),  // trigger operation
               /* data input */
               .rs1_i   (rs1_i),        // rf source 1
               .rs2_i   (rs2_i),        // rf source 2
               .rs3_i   (rs3_i),        // rf source 3
               .rs4_i   (rs4_i),        // rf source 4
               /* result and status */
               .res_o   (cp_result[4]), // operation result
               .valid_o (cp_valid[4])   // data output valid
           );
       end : cellrv32_cpu_cp_cfu_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zxcfu == 1'b0) begin : cellrv32_cpu_cp_cfu_inst_OFF
           assign cp_result[4] = '0;
           assign cp_valid[4]  = 1'b0;
       end : cellrv32_cpu_cp_cfu_inst_OFF
    endgenerate

    // -------------------------------------------------------------------------------------------
    // Co-Processor 5: Conditional Operations ('Zicond' Extension) -------------------------------
    // -------------------------------------------------------------------------------------------
    generate
       if (CPU_EXTENSION_RISCV_Zicond == 1'b1) begin : cellrv32_cpu_cp_cond_inst_ON
           cellrv32_cpu_cp_cond #(.XLEN(XLEN))
           cellrv32_cpu_cp_cond_inst (
               /* global control */
               .clk_i   (clk_i),        // global clock, rising edge
               .ctrl_i  (ctrl_i),       // main control bus
               .start_i (cp_start[5]),  // trigger operation
               /* data input */
               .rs1_i   (rs1_i),        // rf source 1
               .rs2_i   (rs2_i),        // rf source 2
               /* result and status */
               .res_o   (cp_result[5]), // operation result
               .valid_o (cp_valid[5])   // data output valid
           );
       end : cellrv32_cpu_cp_cond_inst_ON
    endgenerate

    generate
       if (CPU_EXTENSION_RISCV_Zicond == 1'b0) begin : cellrv32_cpu_cp_cond_inst_OFF
           assign cp_result[5] = '0;
           assign cp_valid[5]  = 1'b0;
       end : cellrv32_cpu_cp_cond_inst_OFF
    endgenerate
    
endmodule