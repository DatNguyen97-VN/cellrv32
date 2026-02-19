// ##################################################################################################
// # << CELLRV32 - Vector Execution Lane >>                                                         #
// # ********************************************************************************************** #
// # VECTOR_FP_ALU = false (default) : Enable floating-point lanes                                  #
// # VECTOR_FXP_ALU = false (default) : Enable fixed-point lanes                                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vex_pipe #(
    parameter int XLEN            = 32,
    parameter int VECTOR_LANES    = 8 ,
    parameter int VECTOR_LANE_NUM = 1 ,
    parameter     VECTOR_FP_ALU   = 1 ,
    parameter     VECTOR_FXP_ALU  = 0
) (
    input  logic            clk           ,
    input  logic            rst_n         ,
    //Issue Interface
    input  logic            valid_i       ,
    output logic            fp_valid_o    ,
    input  logic            done_i        ,
    output logic            ready_o       ,
    input  logic            mask_i        ,
    input  logic [XLEN-1:0] data_a_i      ,
    input  logic [XLEN-1:0] data_b_i      ,
    input  logic [     5:0] funct6_i      ,
    input  logic [     2:0] funct3_i      ,
    input  logic [     2:0] frm_i         ,
    input  logic [     4:0] vfunary_i     ,
    input  logic [     6:0] vl_i          ,
    input  logic            is_rdc_i      ,
    output logic [     3:0] valid_mul_div_o,
    //Writeback
    input  logic            head_uop_ex3_i,
    input  logic            end_uop_ex3_i ,
    output logic            wr_en_o       ,
    output logic [XLEN-1:0] wr_data_o     ,
    //EX1 Reduction Tree Intf
    input  logic [XLEN-1:0] rdc_data_ex1_i,
    output logic [XLEN-1:0] rdc_data_ex1_o,
    //EX2 Reduction Tree Intf
    input  logic [XLEN-1:0] rdc_data_ex2_i,
    output logic [XLEN-1:0] rdc_data_ex2_o,
    //EX3 Reduction Tree Intf
    input  logic [XLEN-1:0] rdc_data_ex3_i,
    output logic [XLEN-1:0] rdc_data_ex3_o,
    //EX4 Reduction Tree Intf
    output logic [     4:0] pipe_fflags_o
);
    //Reg Declaration
    logic            valid_int_ex1  ;
    logic            valid_int_ex2  ;
    logic            valid_int_ex3  ;
    logic [XLEN-1:0] data_ex1       ;
    logic [XLEN-1:0] data_ex2       ;
    logic [XLEN-1:0] data_ex3       ;
    logic [XLEN-1:0] data_ex4       ;
    logic [XLEN-1:0] temp_rdc_result_ex3;
    logic            use_temp_rdc_result;
    logic            ready_res_ex2  ;
    logic            ready_res_ex3  ;
    logic            valid_result_wr;

    //Wire Declaration
    logic            valid_int          ;
    logic            valid_int_done     ;
    logic            valid_fp_ex1       ;
    logic            ready_res_int_ex1  ;
    logic            ready_res_int_ex2  ;
    logic            ready_res_int_ex3  ;
    logic            ready_res_int_ex4  ;
    logic [XLEN-1:0] res_int_ex1        ;
    logic [XLEN-1:0] res_int_ex2        ;
    logic [XLEN-1:0] res_int_ex3        ;
    logic [XLEN-1:0] res_int_ex4        ;
    logic            ready_res_fp_ex4   ;
    logic [XLEN-1:0] res_fp_ex4         ;
    logic            mask_wr            ;
    logic            use_reduce_tree_ex1;
    logic            use_reduce_tree_ex2;
    logic            use_reduce_tree_ex3;

    // FP32 ALU ready / valid
    logic             vfp32_ready;
    logic             vint_ready;

    assign ready_o        = valid_fp_ex1 ? vfp32_ready : vint_ready;
    assign valid_int_ex1  =  is_rdc_i & valid_i; // rdc op
    assign valid_int_done = (funct3_i == funct3_opivv_c) || (funct3_i == funct3_opivi_c) || (funct3_i == funct3_opivx_c) ? valid_i : 1'b0; // integer op
    assign valid_int      = (funct3_i == funct3_opivv_c) || (funct3_i == funct3_opivi_c) || (funct3_i == funct3_opivx_c) ||
                           (funct3_i == funct3_opmvv_c) || (funct3_i == funct3_opmvx_c) ? valid_i : 1'b0; // integer op
    assign valid_fp_ex1   = (funct3_i == funct3_opfvv_c) || (funct3_i == funct3_opfvx_c) ? valid_i : 1'b0; // floating point op
    assign use_reduce_tree_ex1 = valid_int_ex1;
    
    //-----------------------------------------------
    // Integer ALU
    //-----------------------------------------------
    cellrv32_cpu_cp_vector_vex_pipe_vint #(
        .XLEN            (XLEN           ),
        .VECTOR_LANES    (VECTOR_LANES   ),
        .VECTOR_LANE_NUM (VECTOR_LANE_NUM)
    ) cellrv32_cpu_cp_vector_vex_pipe_vint_inst (
        .clk            (clk              ),
        .rst_n          (rst_n            ),
        .valid_i        (valid_int        ),
        .data_a_ex1_i   (data_a_i         ),
        .data_b_ex1_i   (data_b_i         ),
        .funct6_i       (funct6_i         ),
        .funct3_i       (funct3_i         ),
        .mask_i         (mask_i           ),
        .vl_i           (vl_i             ),
        .is_rdc_i       (is_rdc_i         ),
        .ready_o        (vint_ready       ),
        .valid_mul_div_o(valid_mul_div_o  ),
        //Reduction Tree Inputs
        .rdc_data_ex1_i (rdc_data_ex1_i   ),
        .rdc_data_ex2_i (rdc_data_ex2_i   ),
        .rdc_data_ex3_i (rdc_data_ex3_i   ),
        //Result Ex1 Out
        .ready_res_ex1_o(ready_res_int_ex1),
        .result_ex1_o   (res_int_ex1      ),
        //EX2 In
        .data_ex2_i     (data_ex1         ),
        //Result Ex2 Out
        .ready_res_ex2_o(ready_res_int_ex2),
        .result_ex2_o   (res_int_ex2      ),
        //EX3 In
        .data_ex3_i     (data_ex2         ),
        //Result Ex3 Out
        .ready_res_ex3_o(ready_res_int_ex3),
        .result_ex3_o   (res_int_ex3      ),
        //EX4 In
        .data_ex4_i     (data_ex3         ),
        //Result Ex4 Out
        .ready_res_ex4_o(ready_res_int_ex4),
        .result_ex4_o   (res_int_ex4      )
    );

    //-----------------------------------------------
    // Floating Point ALU
    //-----------------------------------------------
    generate if (VECTOR_FP_ALU) begin : cellrv32_cpu_cp_vector_vex_pipe_vfp32_ON
        cellrv32_cpu_cp_vector_vex_pipe_vfp32 #(
            .XLEN (XLEN)
        ) cellrv32_cpu_cp_vector_vex_pipe_vfp32_inst (
            .clk_i          (clk             ),
            .rstn_i         (rst_n           ),
            .valid_i        (valid_fp_ex1    ),
            .done_all_i     (done_i          ),
            .data_a_ex1_i   (data_a_i        ),
            .data_b_ex1_i   (data_b_i        ),
            .funct6_i       (funct6_i        ),
            .funct3_i       (funct3_i        ),
            .frm_i          (frm_i           ),
            .vfunary_i      (vfunary_i       ),
            .mask_i         (mask_i          ),
            .vl_i           (vl_i            ),
            .is_rdc_i       (is_rdc_i        ),
            .ready_o        (vfp32_ready     ),
            .fp32_valid_o   (fp_valid_o      ),
            //Reduction Tree Inputs
            .rdc_data_ex1_i (rdc_data_ex1_i  ),
            .rdc_data_ex2_i (rdc_data_ex2_i  ),
            .rdc_data_ex3_i (rdc_data_ex3_i  ),
            //Result Ex4 Out
            .ready_res_ex4_o(ready_res_fp_ex4),
            .result_ex4_o   (res_fp_ex4      ),
            .flags_ex4_o    (pipe_fflags_o   )
        );
    end else begin : cellrv32_cpu_cp_vector_vex_pipe_vfp32_OFF
        assign fp_valid_o       = 1'b0;
        assign ready_res_fp_ex4 = '0;
        assign res_fp_ex4       = '0;
        assign pipe_fflags_o    = '0;
    end endgenerate
   
    // The Data Flops are shared between the execution
    // units. The biggest data to be saved dictates
    // the size of the flop used
    //-----------------------------------------------
    // EX1/EX2 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
           data_ex1 <= '0;
        end else if (use_reduce_tree_ex1) begin
           data_ex1 <= res_int_ex1;
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_int_ex2       <= 1'b0;
            ready_res_ex2       <= 1'b0;
            use_reduce_tree_ex2 <= 1'b0;
        end else begin
            valid_int_ex2       <= valid_int_ex1;
            ready_res_ex2       <= ready_res_int_ex1;
            use_reduce_tree_ex2 <= use_reduce_tree_ex1;
        end
    end
    //-----------------------------------------------
    // EX2/EX3 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_ex2 <= '0;
        end else if (use_reduce_tree_ex2) begin
            if (ready_res_ex2) begin
                data_ex2 <= data_ex1;
            end else if (valid_int_ex2) begin
                data_ex2 <= res_int_ex2;
            end
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_int_ex3       <= 1'b0;
            ready_res_ex3       <= 1'b0;
            use_reduce_tree_ex3 <= 1'b0;
        end else begin
            valid_int_ex3       <= valid_int_ex2;
            ready_res_ex3       <= ready_res_ex2 | ready_res_int_ex2;
            use_reduce_tree_ex3 <= use_reduce_tree_ex2;
        end
    end
    //-----------------------------------------------
    // EX3/EX4 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_ex3 <= '0;
        end else if (use_reduce_tree_ex3) begin
            data_ex3 <= temp_rdc_result_ex3;
        end
    end
    //-----------------------------------------------
    // Temporary Reduction Result
    //-----------------------------------------------
    // Store the intermediate reduction results until we
    // execute all the uops
    generate if (VECTOR_LANE_NUM == 0) begin: g_rdc_tmp_rslt
        logic temp_rdc_result_en;
        logic [XLEN-1:0] selected_second_operand;
        logic [XLEN-1:0] nxt_temp_rdc_result_ex3;
        logic [XLEN-1:0] nxt_tmp_rslt;

        // select second operand
        assign selected_second_operand = res_int_ex3;
        // calculate new intermediate result
        always_comb begin
            case (funct6_i)
                funct6_vredsum_c : begin
                    // VRADD
                    nxt_tmp_rslt = temp_rdc_result_ex3 + selected_second_operand;
                end
                funct6_vredand_c : begin
                    // VRAND
                    nxt_tmp_rslt = temp_rdc_result_ex3 & selected_second_operand;
                end
                funct6_vredor_c : begin
                    // VROR
                    nxt_tmp_rslt = temp_rdc_result_ex3 | selected_second_operand;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    nxt_tmp_rslt = temp_rdc_result_ex3 ^ selected_second_operand;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    nxt_tmp_rslt = (temp_rdc_result_ex3 < selected_second_operand) ? temp_rdc_result_ex3 : selected_second_operand;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    nxt_tmp_rslt = ($signed(temp_rdc_result_ex3) < $signed(selected_second_operand)) ? temp_rdc_result_ex3 : selected_second_operand;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    nxt_tmp_rslt = (temp_rdc_result_ex3 > selected_second_operand) ? temp_rdc_result_ex3 : selected_second_operand;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    nxt_tmp_rslt = ($signed(temp_rdc_result_ex3) > $signed(selected_second_operand)) ? temp_rdc_result_ex3 : selected_second_operand;
                end
                default : begin
                    nxt_tmp_rslt = '0;
                end
            endcase
        end
        // mux data
        assign nxt_temp_rdc_result_ex3 = (head_uop_ex3_i & ready_res_ex3      ) ? data_ex3    :
                                         (head_uop_ex3_i & use_reduce_tree_ex3) ? res_int_ex3 : nxt_tmp_rslt;

        assign temp_rdc_result_en = valid_int_ex3 & use_reduce_tree_ex3;
        // store intermediate reduction result
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                temp_rdc_result_ex3 <= '0;
            end else if (temp_rdc_result_en) begin
                temp_rdc_result_ex3 <= nxt_temp_rdc_result_ex3;
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                use_temp_rdc_result <= 1'b0;
            else
                use_temp_rdc_result <= use_reduce_tree_ex3 & end_uop_ex3_i;
        end
    end else begin: g_rdc_tmp_rslt_stubs
        assign use_temp_rdc_result = 1'b0;
    end endgenerate
    //-----------------------------------------------
    // EX4/WR Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_ex4 <= '0;
        end else if (valid_int_done) begin
            data_ex4 <= res_int_ex1;
        end else if (ready_res_fp_ex4) begin
            data_ex4 <= res_fp_ex4;
        end else if (ready_res_int_ex4) begin
            data_ex4 <= res_int_ex4;
        end else if (use_reduce_tree_ex3) begin
            data_ex4 <= data_ex3;
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_result_wr <= 1'b0;
            mask_wr         <= 1'b1;
        end else begin
            // force writeback to happen on all elements
            valid_result_wr <= use_temp_rdc_result | ready_res_int_ex4 | ready_res_fp_ex4 | valid_int_done;
            mask_wr         <= use_temp_rdc_result | ready_res_int_ex4 | ready_res_fp_ex4 | valid_int_done;
        end
    end
    //------------------------------------------------------
    // Writeback Signals
    //------------------------------------------------------
    assign wr_en_o = valid_result_wr;
    
    generate
        if (VECTOR_LANE_NUM == 0) begin : wrb_rdc_nor_output
            always_comb begin
                if (is_rdc_i) begin
                    // vd[0] = vs1[0] + Σ vs2[i] with each i ∈ active elements, final result
                    case (funct6_i)
                        funct6_vredsum_c : begin
                            // VRADD
                            wr_data_o = temp_rdc_result_ex3 + data_a_i;
                        end
                        funct6_vredand_c : begin
                            // VRAND
                            wr_data_o = temp_rdc_result_ex3 & data_a_i;
                        end
                        funct6_vredor_c : begin
                            // VROR
                            wr_data_o = temp_rdc_result_ex3 | data_a_i;
                        end
                        funct6_vredxor_c : begin
                            // VRXOR
                            wr_data_o = temp_rdc_result_ex3 ^ data_a_i;
                        end
                        funct6_vredminu_c : begin
                            // VRMINU
                            wr_data_o = ( $unsigned(temp_rdc_result_ex3) < $unsigned(data_a_i) ) ?
                                         temp_rdc_result_ex3 : data_a_i;
                        end
                        funct6_vredmin_c : begin
                            // VRMIN
                            wr_data_o = ( $signed(temp_rdc_result_ex3) < $signed(data_a_i) ) ?
                                         temp_rdc_result_ex3 : data_a_i;
                        end
                        funct6_vredmaxu_c : begin
                            // VRMAXU
                            wr_data_o = ( $unsigned(temp_rdc_result_ex3) > $unsigned(data_a_i) ) ?
                                         temp_rdc_result_ex3 : data_a_i;
                        end
                        funct6_vredmax_c : begin
                            // VRMAX
                            wr_data_o = ( $signed(temp_rdc_result_ex3) > $signed(data_a_i) ) ?
                                         temp_rdc_result_ex3 : data_a_i;
                        end
                        default : begin
                            wr_data_o = '0;
                        end
                    endcase
                end else begin
                    wr_data_o = data_ex4 & {XLEN{mask_wr}};
                end
            end
        end : wrb_rdc_nor_output
    endgenerate

    generate
        if (VECTOR_LANE_NUM !=0) begin : wrb_nor_output
            assign wr_data_o = data_ex4 & {XLEN{mask_wr}};
        end : wrb_nor_output
    endgenerate

    // Reduction Signals
    assign rdc_data_ex1_o = data_b_i & {XLEN{use_reduce_tree_ex1}};
    assign rdc_data_ex2_o = data_ex1 & {XLEN{use_reduce_tree_ex2}};
    assign rdc_data_ex3_o = data_ex2 & {XLEN{use_reduce_tree_ex3}};

endmodule