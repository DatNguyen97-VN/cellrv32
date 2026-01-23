// ##################################################################################################
// # << CELLRV32 - Vector Execution Stage >>                                                        #
// # ********************************************************************************************** #
// # VECTOR_FP_ALU = false (default) : Enable floating-point lanes                                  #
// # VECTOR_FXP_ALU = false (default) : Enable fixed-point lanes                                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vex #(
    parameter int VECTOR_REGISTERS = 32,
    parameter int VECTOR_LANES     = 8 ,
    parameter int XLEN             = 32,
    parameter     VECTOR_FP_ALU    = 1 ,
    parameter     VECTOR_FXP_ALU   = 0
) (
    input  logic                                                         clk        ,
    input  logic                                                         rst_n      ,
    output logic                                                         vex_idle_o ,
    // Issue Interface
    input  logic                                                         valid_i    ,
    input  to_vector_exec [            VECTOR_LANES-1:0]                 exec_data_i,
    input  to_vector_exec_info                                           exec_info_i,
    output logic                                                         ready_o    ,
    // Writeback
    output logic          [            VECTOR_LANES-1:0]                 wr_en      ,
    output logic          [$clog2(VECTOR_REGISTERS)-1:0]                 wr_addr    ,
    output logic          [            VECTOR_LANES-1:0][XLEN-1:0] wr_data    ,
    output logic          [            VECTOR_LANES-1:0]                 rdc_done_o ,
    output logic          [                         4:0]                 fflags_o    
); 


    logic [$clog2(VECTOR_REGISTERS)-1:0] dst_ex2, dst_ex3, dst_ex4, dst_wr;
    logic                                valid_ex2, valid_ex3, valid_ex4;
    logic                                head_ex2, head_ex3, head_ex4;
    logic                                end_ex2, end_ex3, end_ex4;
    logic [XLEN-1:0] rdc_data_ex1_i [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex1_o [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex2_i [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex2_o [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex3_i [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex3_o [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex4_i [VECTOR_LANES-1:0];
    logic [XLEN-1:0] rdc_data_ex4_o [VECTOR_LANES-1:0];
    logic [$clog2(VECTOR_REGISTERS)-1:0] mul_div_dst_ex1;
    logic [$clog2(VECTOR_REGISTERS)-1:0] mul_div_dst_ex2;
    logic [$clog2(VECTOR_REGISTERS)-1:0] mul_div_dst_ex3;
    logic [$clog2(VECTOR_REGISTERS)-1:0] mul_div_dst_ex4;
    logic [$clog2(VECTOR_REGISTERS)-1:0] mul_div_dst    ;

    logic [VECTOR_LANES-1:0] ready;
    logic [VECTOR_LANES-1:0] vex_pipe_valid;
    logic [VECTOR_LANES-1:0] vex_fp_valid;
    logic is_fp32;
    logic is_mul_div;
    logic all_thread_done;
    logic [4:0] vex_pipe_fflag [VECTOR_LANES-1:0];
    logic [3:0] valid_mul_div [VECTOR_LANES-1:0];

    assign ready_o = |ready;
    assign is_fp32 = (exec_info_i.ir_funct3 == funct3_opfvv_c) || (exec_info_i.ir_funct3 == funct3_opfvx_c);
    assign is_mul_div = ((exec_info_i.ir_funct3 == funct3_opmvv_c) || (exec_info_i.ir_funct3 == funct3_opmvx_c)) & ~exec_info_i.is_rdc;

    always_comb begin
      fflags_o = '0;
      for (int i = 0; i < VECTOR_LANES; i++) begin
        fflags_o |= vex_pipe_fflag[i];
      end
    end

    genvar k;
    generate
        for (k = 0; k < VECTOR_LANES; k++) begin : g_vex_pipe
            assign vex_pipe_valid[k] = valid_i & exec_data_i[k].valid;
            vex_pipe #(
                .XLEN            (XLEN          ),
                .VECTOR_LANES    (VECTOR_LANES  ),
                .VECTOR_LANE_NUM (k             ),
                .VECTOR_FP_ALU   (VECTOR_FP_ALU ),
                .VECTOR_FXP_ALU  (VECTOR_FXP_ALU)
            ) vex_pipe (
                .clk            (clk                  ),
                .rst_n          (rst_n                ),
                //Input
                .valid_i        (vex_pipe_valid[k]    ),
                .fp_valid_o     (vex_fp_valid[k]      ),
                .ready_o        (ready[k]             ),
                .done_i         (all_thread_done      ),
                .mask_i         (exec_data_i[k].mask  ),
                .data_a_i       (exec_data_i[k].data1 ),
                .data_b_i       (exec_data_i[k].data2 ),
                .funct6_i       (exec_info_i.ir_funct6),
                .funct3_i       (exec_info_i.ir_funct3),
                .frm_i          (exec_info_i.frm      ),
                .vfunary_i      (exec_info_i.vfunary  ),
                .vl_i           (exec_info_i.vl       ),
                .is_rdc_i       (exec_info_i.is_rdc   ),
                .valid_mul_div_o(valid_mul_div[k]     ),
                //Writeback (EX*)
                .head_uop_ex4_i (head_ex4             ),
                .end_uop_ex4_i  (end_ex4              ),
                .wr_en_o        (wr_en[k]             ),
                .wr_data_o      (wr_data[k]           ),
                .rdc_done_o     (rdc_done_o[k]        ),
                //EX1 Reduction Tree Intf
                .rdc_data_ex1_i (rdc_data_ex1_i[k]    ),
                .rdc_data_ex1_o (rdc_data_ex1_o[k]    ),
                //EX2 Reduction Tree Intf
                .rdc_data_ex2_i (rdc_data_ex2_i[k]    ),
                .rdc_data_ex2_o (rdc_data_ex2_o[k]    ),
                //EX3 Reduction Tree Intf
                .rdc_data_ex3_i (rdc_data_ex3_i[k]    ),
                .rdc_data_ex3_o (rdc_data_ex3_o[k]    ),
                //EX2 Reduction Tree Intf
                .rdc_data_ex4_i (rdc_data_ex4_i[k]    ),
                .rdc_data_ex4_o (rdc_data_ex4_o[k]    ),
                .pipe_fflags_o  (vex_pipe_fflag[k]    )
            );
        end
    endgenerate
    //Connect the Reduction Tree
    //-----------------------------------------------
    // EX1
    //-----------------------------------------------
    genvar i;
    generate
        for (i = 0; i < VECTOR_LANES; i = i+2) begin: g_rdc_ex1
            assign rdc_data_ex1_i[i] = rdc_data_ex1_o[i+1];
        end : g_rdc_ex1
    endgenerate
    //-----------------------------------------------
    // EX2
    //-----------------------------------------------
    generate
        if (VECTOR_LANES > 2) begin : g_rdc_ex2
            for (i = 0; i <= VECTOR_LANES/2; i = i+4) begin : g_input_rdc_ex2
                assign rdc_data_ex2_i[i] = rdc_data_ex2_o[i+2];
            end : g_input_rdc_ex2
        end : g_rdc_ex2
    endgenerate
    //-----------------------------------------------
    // EX3
    //-----------------------------------------------
    generate
        if (VECTOR_LANES > 4) begin : g_rdc_ex3
            for (i = 0; i <= VECTOR_LANES/4; i = i+8) begin : g_input_rdc_ex3
                assign rdc_data_ex3_i[i] = rdc_data_ex3_o[i+4];
            end : g_input_rdc_ex3
        end : g_rdc_ex3
    endgenerate
    //-----------------------------------------------
    // EX4
    //-----------------------------------------------
    generate
        if (VECTOR_LANES > 8) begin : g_rdc_ex4
            for (i = 0; i <= VECTOR_LANES/8; i = i+16) begin : g_input_rdc_ex4
                assign rdc_data_ex4_i[i] = rdc_data_ex4_o[i+8];
            end : g_input_rdc_ex4
        end : g_rdc_ex4
    endgenerate
    //-----------------------------------------------
    // EX1 Mul/Div Flop
    //-----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_div_dst_ex1 <= '0;
        end else if (ready_o && is_mul_div) begin
            mul_div_dst_ex1 <= exec_info_i.dst;
        end
    end
    //-----------------------------------------------
    // EX2 Mul/Div Flop
    //-----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_div_dst_ex2 <= '0;
        end else if (valid_mul_div[0][0]) begin
            mul_div_dst_ex2 <= mul_div_dst_ex1;
        end
    end
    //-----------------------------------------------
    // EX3 Mul/Div Flop
    //-----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_div_dst_ex3 <= '0;
        end else if (valid_mul_div[0][1]) begin
            mul_div_dst_ex3 <= mul_div_dst_ex2;
        end
    end
    //-----------------------------------------------
    // EX4 Mul/Div Flop
    //-----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_div_dst_ex4 <= '0;
        end else if (valid_mul_div[0][2]) begin
            mul_div_dst_ex4 <= mul_div_dst_ex3;
        end
    end
    //-----------------------------------------------
    // Mul/Div Write Flop
    //-----------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_div_dst <= '0;
        end else if (valid_mul_div[0][3]) begin
            mul_div_dst <= mul_div_dst_ex4;
        end
    end
    //-----------------------------------------------
    // EX1/EX2 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_i) begin
            dst_ex2  <= exec_info_i.dst;
            head_ex2 <= exec_info_i.head_uop;
            end_ex2  <= exec_info_i.end_uop;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_ex2 <= 1'b0;
        end else begin
            valid_ex2 <= valid_i;
        end
    end
    //-----------------------------------------------
    // EX2/EX3 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_ex2) begin
            dst_ex3  <= dst_ex2;
            head_ex3 <= head_ex2;
            end_ex3  <= end_ex2;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_ex3 <= 1'b0;
        end else begin
            valid_ex3 <= valid_ex2;
        end
    end
    //-----------------------------------------------
    // EX3/EX4 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_ex3) begin
            dst_ex4  <= dst_ex3;
            head_ex4 <= head_ex3;
            end_ex4  <= end_ex3;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_ex4 <= 1'b0;
        end else begin
            valid_ex4 <= valid_ex3;
        end
    end
    //-----------------------------------------------
    // EX4/WR Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if (valid_ex4) begin
            dst_wr <= dst_ex4;
        end
    end
    //
    logic [$clog2(VECTOR_REGISTERS)-1:0] fp_dst;
    logic [VECTOR_LANES-1:0] status_thread;
    logic [VECTOR_LANES-1:0] prev_vex_pipe_valid;
    logic prev_ready;

    always_ff @(posedge clk or negedge rst_n) begin : Fall_Edge_Detect
        if (!rst_n) begin
            prev_ready <= 1'b0;
            prev_vex_pipe_valid <= '0;
        end else begin
            prev_ready <= ready_o;
            prev_vex_pipe_valid <= vex_pipe_valid;
        end
    end : Fall_Edge_Detect

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_dst <= '0;
            status_thread <= '0;
        end else if (!ready_o && prev_ready) begin
            fp_dst <= exec_info_i.dst;
            status_thread <= prev_vex_pipe_valid;
        end
    end

    assign all_thread_done = status_thread == vex_fp_valid;
    //------------------------------------------------------
    // Writeback Signals
    //------------------------------------------------------
    assign wr_addr    = is_fp32    ? fp_dst      : 
                        is_mul_div ? mul_div_dst : dst_wr;
    assign vex_idle_o = ~valid_i & ~valid_ex2 & ~valid_ex3 & ~valid_ex4;

endmodule