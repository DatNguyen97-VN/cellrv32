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
    parameter int VECTOR_REGISTERS   = 32,
    parameter int DATA_WIDTH         = 32,
    parameter int MICROOP_WIDTH      = 7 ,
    parameter int VECTOR_TICKET_BITS = 5 ,
    parameter int VECTOR_LANES       = 8 ,
    parameter int VECTOR_LANE_NUM    = 1 ,
    parameter int FWD_POINT_A        = 1 ,
    parameter int FWD_POINT_B        = 3 ,
    parameter     VECTOR_FP_ALU      = 1 ,
    parameter     VECTOR_FXP_ALU     = 0
) (
    input  logic                                           clk           ,
    input  logic                                           rst_n         ,
    //Issue Interface
    input  logic                                           valid_i       ,
    output logic                                           ready_o       ,
    input  logic                                           mask_i        ,
    input  logic [                         DATA_WIDTH-1:0] data_a_i      ,
    input  logic [                         DATA_WIDTH-1:0] data_b_i      ,
    input  logic [                                    5:0] funct6_i      ,
    input  logic [                                    2:0] funct3_i      ,
    input  logic [                                    6:0] vl_i          ,
    //Forward Point #1
    output logic                                           frw_a_en_o    ,
    output logic [                         DATA_WIDTH-1:0] frw_a_data_o  ,
    //Forward Point #2
    output logic                                           frw_b_en_o    ,
    output logic [                         DATA_WIDTH-1:0] frw_b_data_o  ,
    //Writeback
    input  logic                                           head_uop_ex4_i,
    input  logic                                           end_uop_ex4_i ,
    output logic                                           wr_en_o       ,
    output logic [                         DATA_WIDTH-1:0] wr_data_o     ,
    //EX1 Reduction Tree Intf
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex1_i,
    output logic [                         DATA_WIDTH-1:0] rdc_data_ex1_o,
    //EX2 Reduction Tree Intf
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex2_i,
    output logic [                         DATA_WIDTH-1:0] rdc_data_ex2_o,
    //EX3 Reduction Tree Intf
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex3_i,
    output logic [                         DATA_WIDTH-1:0] rdc_data_ex3_o,
    //EX4 Reduction Tree Intf
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex4_i,
    output logic [                         DATA_WIDTH-1:0] rdc_data_ex4_o
);
    localparam int EX1_W = 4*(DATA_WIDTH+8);
    localparam int EX2_W = 3*DATA_WIDTH    ;
    localparam int EX3_W = 3*DATA_WIDTH    ;
    localparam int EX4_W = DATA_WIDTH      ;

    //Reg Declaration
    logic             valid_int_ex2  ;
    logic             valid_int_ex3  ;
    logic             valid_int_ex4  ;
    logic             valid_fp_ex2   ;
    logic             valid_fp_ex3   ;
    logic             valid_fp_ex4   ;
    logic [EX1_W-1:0] data_ex1       ;
    logic [EX2_W-1:0] data_ex2       ;
    logic [EX3_W-1:0] data_ex3       ;
    logic [EX4_W-1:0] data_ex4       ;
    logic [EX4_W-1:0] temp_rdc_result_ex4;
    logic             use_temp_rdc_result;
    logic             ready_res_ex2  ;
    logic             ready_res_ex3  ;
    logic             ready_res_ex4  ;
    logic             valid_result_wr;

    //Wire Declaration
    logic             valid_int_ex1      ;
    logic             valid_fp_ex1       ;
    logic             valid_fxp_ex1      ;
    logic             ready_res_int_ex1  ;
    logic             ready_res_int_ex2  ;
    logic             ready_res_int_ex3  ;
    logic             ready_res_int_ex4  ;
    logic [EX1_W-1:0] res_int_ex1        ;
    logic [EX2_W-1:0] res_int_ex2        ;
    logic [EX3_W-1:0] res_int_ex3        ;
    logic [EX4_W-1:0] res_int_ex4        ;
    logic             ready_res_fp_ex1   ;
    logic             ready_res_fp_ex2   ;
    logic             ready_res_fp_ex3   ;
    logic             ready_res_fp_ex4   ;
    logic [EX1_W-1:0] res_fp_ex1         ;
    logic [EX2_W-1:0] res_fp_ex2         ;
    logic [EX3_W-1:0] res_fp_ex3         ;
    logic [EX4_W-1:0] res_fp_ex4         ;
    logic             mask_ex2           ;
    logic             mask_ex3           ;
    logic             mask_ex4           ;
    logic             mask_wr            ;
    logic             use_reduce_tree_ex1;
    logic             use_reduce_tree_ex2;
    logic             use_reduce_tree_ex3;
    logic             use_reduce_tree_ex4;
    logic [      5:0] rdc_op_ex4;

    assign ready_o        = valid_i; // so far no multi-cycle blocking ops exist
    assign valid_int_ex1  = (funct3_i == funct3_opivv_c) | (funct3_i == funct3_opivi_c) | (funct3_i == funct3_opivx_c) ? valid_i : 1'b0; // integer op
    //assign valid_fp_ex1   = valid_i ? (fu_i === `FP_FU)  : 1'b0; // floating point op
    //assign valid_fxp_ex1  = valid_i ? (fu_i === `FXP_FU) : 1'b0; // fixed point op
    assign use_reduce_tree_ex1 = (funct3_i == funct3_opmvv_c) || (funct3_i == funct3_opmvx_c) ? 1'b1 : 1'b0;
    
    //-----------------------------------------------
    // Integer ALU
    //-----------------------------------------------
    v_int_alu #(
        .DATA_WIDTH        (DATA_WIDTH        ),
        .MICROOP_WIDTH     (MICROOP_WIDTH     ),
        .VECTOR_TICKET_BITS(VECTOR_TICKET_BITS),
        .VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
        .VECTOR_LANES      (VECTOR_LANES      ),
        .VECTOR_LANE_NUM   (VECTOR_LANE_NUM   ),
        .EX1_W             (EX1_W             ),
        .EX2_W             (EX2_W             ),
        .EX3_W             (EX3_W             ),
        .EX4_W             (EX4_W             )
    ) v_int_alu (
        .clk            (clk              ),
        .rst_n          (rst_n            ),
        .valid_i        (valid_int_ex1    ),
        .data_a_ex1_i   (data_a_i         ),
        .data_b_ex1_i   (data_b_i         ),
        .funct6_i       (funct6_i         ),
        .funct3_i       (funct3_i         ),
        .mask_i         (mask_i           ),
        .vl_i           (vl_i             ),
        //Reduction Tree Inputs
        .rdc_data_ex1_i (rdc_data_ex1_i   ),
        .rdc_data_ex2_i (rdc_data_ex2_i   ),
        .rdc_data_ex3_i (rdc_data_ex3_i   ),
        .rdc_data_ex4_i (rdc_data_ex4_i   ),
        //Result Ex1 Out
        .ready_res_ex1_o(ready_res_int_ex1),
        .result_ex1_o   (res_int_ex1      ),
        //EX2 In
        .data_ex2_i     (data_ex1         ),
        .mask_ex2_i     (mask_ex2         ),
        //Result Ex2 Out
        .ready_res_ex2_o(ready_res_int_ex2),
        .result_ex2_o   (res_int_ex2      ),
        //EX3 In
        .data_ex3_i     (data_ex2         ),
        .mask_ex3_i     (mask_ex3         ),
        //Result Ex3 Out
        .ready_res_ex3_o(ready_res_int_ex3),
        .result_ex3_o   (res_int_ex3      ),
        //EX4 In
        .data_ex4_i     (data_ex3         ),
        .mask_ex4_i     (mask_ex4         ),
        //Result Ex4 Out
        .rdc_op_ex4_o   (rdc_op_ex4       ),
        .ready_res_ex4_o(ready_res_int_ex4),
        .result_ex4_o   (res_int_ex4      )
    );

    //-----------------------------------------------
    // Floating Point ALU
    //-----------------------------------------------
    //generate if (VECTOR_FP_ALU) begin:g_fp_alu
    //    v_fp_alu #(
    //        .DATA_WIDTH        (DATA_WIDTH        ),
    //        .MICROOP_WIDTH     (MICROOP_WIDTH     ),
    //        .VECTOR_TICKET_BITS(VECTOR_TICKET_BITS),
    //        .VECTOR_LANE_NUM   (VECTOR_LANE_NUM   ),
    //        .EX1_W             (EX1_W             ),
    //        .EX2_W             (EX2_W             ),
    //        .EX3_W             (EX3_W             ),
    //        .EX4_W             (EX4_W             )
    //    ) v_fp_alu (
    //        .clk            (clk             ),
    //        .rst_n          (rst_n           ),
    //        .valid_i        (valid_fp_ex1    ),
    //        .data_a_ex1_i   (data_a_i        ),
    //        .data_b_ex1_i   (data_b_i        ),
    //        .imm_ex1_i      (immediate_i     ),
    //        .microop_i      (microop_i       ),
    //        .mask_i         (mask_i          ),
    //        //Result Ex1 Out
    //        .ready_res_ex1_o(ready_res_fp_ex1),
    //        .result_ex1_o   (res_fp_ex1      ),
    //        //EX2 In
    //        .data_ex2_i     (data_ex1        ),
    //        .mask_ex2_i     (mask_ex2        ),
    //        //Result Ex2 Out
    //        .ready_res_ex2_o(ready_res_fp_ex2),
    //        .result_ex2_o   (res_fp_ex2      ),
    //        //EX3 In
    //        .data_ex3_i     (data_ex2        ),
    //        .mask_ex3_i     (mask_ex3        ),
    //        //Result Ex3 Out
    //        .ready_res_ex3_o(ready_res_fp_ex3),
    //        .result_ex3_o   (res_fp_ex3      ),
    //        //EX4 In
    //        .data_ex4_i     (data_ex3        ),
    //        .mask_ex4_i     (mask_ex4        ),
    //        //Result Ex4 Out
    //        .ready_res_ex4_o(ready_res_fp_ex4),
    //        .result_ex4_o   (res_fp_ex4      )
    //    );
    //end else begin: g_fp_alu_stubs
    //    assign ready_res_fp_ex1 = 1'b0;
    //    assign ready_res_fp_ex2 = 1'b0;
    //    assign ready_res_fp_ex3 = 1'b0;
    //    assign ready_res_fp_ex4 = 1'b0;
    //end endgenerate
   
    // The Data Flops are shared between the execution
    // units. The biggest data to be saved dictates
    // the size of the flop used
    //-----------------------------------------------
    // EX1/EX2 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk) begin
        if(mask_i | use_reduce_tree_ex1) begin
            if(valid_int_ex1) begin
                data_ex1 <= res_int_ex1;
            end else if(valid_fp_ex1) begin
                data_ex1 <= res_fp_ex1;
            end
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_int_ex2       <= 1'b0;
            valid_fp_ex2        <= 1'b0;
            ready_res_ex2       <= 1'b0;
            mask_ex2            <= 1'b1;
            use_reduce_tree_ex2 <= 1'b0;
        end else begin
            valid_int_ex2       <= valid_int_ex1;
            valid_fp_ex2        <= valid_fp_ex1;
            ready_res_ex2       <= ready_res_int_ex1 | ready_res_fp_ex1;
            mask_ex2            <= mask_i & valid_i;
            // force writeback to happen on all elements
            // write 0s everywhere except el#0 that holds the reduced result
            use_reduce_tree_ex2 <= use_reduce_tree_ex1;
        end
    end
    //-----------------------------------------------
    // EX2/EX3 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk) begin
        if(mask_ex2 | use_reduce_tree_ex2) begin
            if(ready_res_ex2) begin
                data_ex2 <= data_ex1;
            end else if(valid_int_ex2) begin
                data_ex2 <= res_int_ex2;
            end else if (valid_fp_ex2) begin
                data_ex2 <= res_fp_ex2;
            end
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_int_ex3       <= 1'b0;
            valid_fp_ex3        <= 1'b0;
            ready_res_ex3       <= 1'b0;
            mask_ex3            <= 1'b1;
            use_reduce_tree_ex3 <= 1'b0;
        end else begin
            valid_int_ex3       <= valid_int_ex2;
            valid_fp_ex3        <= valid_fp_ex2;
            ready_res_ex3       <= ready_res_ex2 | ready_res_int_ex2 | ready_res_fp_ex2;
            mask_ex3            <= mask_ex2;
            use_reduce_tree_ex3 <= use_reduce_tree_ex2;
        end
    end
    //-----------------------------------------------
    // EX3/EX4 Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk) begin
        if(mask_ex3 | use_reduce_tree_ex3) begin
            if(ready_res_ex3) begin
                data_ex3 <= data_ex2;
            end else if(valid_int_ex3) begin
                data_ex3 <= res_int_ex3;
            end else if (valid_fp_ex3) begin
                data_ex3 <= res_fp_ex3;
            end
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_int_ex4       <= 1'b0;
            valid_fp_ex4        <= 1'b0;
            ready_res_ex4       <= 1'b0;
            mask_ex4            <= 1'b1;
            use_reduce_tree_ex4 <= 1'b0;
        end else begin
            valid_int_ex4       <= valid_int_ex3;
            valid_fp_ex4        <= valid_fp_ex3;
            ready_res_ex4       <= ready_res_ex3 | ready_res_int_ex3 | ready_res_fp_ex3;
            mask_ex4            <= mask_ex3;
            use_reduce_tree_ex4 <= use_reduce_tree_ex3;
        end
    end
    //-----------------------------------------------
    // Temporary Reduction Result
    //-----------------------------------------------
    // Store the intermediate reduction results until we
    // execute all the uops
    generate if (VECTOR_LANE_NUM == 0) begin: g_rdc_tmp_rslt
        logic temp_rdc_result_en;
        logic [EX4_W-1:0] selected_second_operand;
        logic [EX4_W-1:0] nxt_temp_rdc_result_ex4;
        logic [EX4_W-1:0] nxt_tmp_rslt;

        // select second operand
        assign selected_second_operand = ready_res_ex4 ? data_ex3 : res_int_ex4;
        // calculate new intermediate result
        always_comb begin
            case (rdc_op_ex4)
                funct6_vredsum_c : begin
                    // VRADD
                    nxt_tmp_rslt = temp_rdc_result_ex4 + selected_second_operand;
                end
                funct6_vredand_c : begin
                    // VRAND
                    nxt_tmp_rslt = temp_rdc_result_ex4 & selected_second_operand;
                end
                funct6_vredor_c : begin
                    // VROR
                    nxt_tmp_rslt = temp_rdc_result_ex4 | selected_second_operand;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    nxt_tmp_rslt = temp_rdc_result_ex4 ^ selected_second_operand;
                end
                default : begin
                    nxt_tmp_rslt = 'x;
                end
            endcase
        end
        // mux data
        assign nxt_temp_rdc_result_ex4 = (head_uop_ex4_i & ready_res_ex4      ) ? data_ex3    :
                                         (head_uop_ex4_i & use_reduce_tree_ex4) ? res_int_ex4 : nxt_tmp_rslt;

        assign temp_rdc_result_en = valid_int_ex4 & use_reduce_tree_ex4;
        // store intermediate reduction result
        always_ff @(posedge clk) begin
            if (temp_rdc_result_en)
                temp_rdc_result_ex4 <= nxt_temp_rdc_result_ex4;
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n)
                use_temp_rdc_result <= 1'b0;
            else
                use_temp_rdc_result <= use_reduce_tree_ex4 & end_uop_ex4_i & ~head_uop_ex4_i;
        end
    end else begin: g_rdc_tmp_rslt_stubs
        assign use_temp_rdc_result = 1'b0;
    end endgenerate
    //-----------------------------------------------
    // EX4/WR Data Flops
    //-----------------------------------------------
    // Data storage
    always_ff @(posedge clk) begin
        if(mask_ex4 | use_reduce_tree_ex4) begin
            if(ready_res_ex4) begin
                data_ex4 <= data_ex3;
            end else if(valid_int_ex4) begin
                data_ex4 <= res_int_ex4;
            end else if (valid_fp_ex4) begin
                data_ex4 <= res_fp_ex4;
            end
        end
    end
    // Control Info storage
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_result_wr <= 1'b0;
            mask_wr         <= 1'b1;
        end else begin
            // force writeback to happen on all elements
            // write 0s everywhere except el#0 that holds the reduced result only for reduction tree
            valid_result_wr <= valid_int_ex4 | valid_fp_ex4 | use_reduce_tree_ex4;
            mask_wr         <= mask_ex4 | (use_reduce_tree_ex4 & VECTOR_LANE_NUM != 0);
        end
    end
    //------------------------------------------------------
    // Forwarding Points
    //------------------------------------------------------
    // Forward Point #1
    //------------------------------------------------------
    assign frw_a_en_o   = ready_res_int_ex1;
    assign frw_a_data_o = res_int_ex1[0 +: DATA_WIDTH];
    //------------------------------------------------------
    // Forward Point #2
    //------------------------------------------------------
    assign frw_b_en_o   = ready_res_ex4;
    assign frw_b_data_o = mask_ex4 ? data_ex3[0 +: DATA_WIDTH] : '0;

    // Writeback Signals
    assign wr_en_o      = valid_result_wr;
    assign wr_data_o    = use_temp_rdc_result ? temp_rdc_result_ex4[0 +: DATA_WIDTH] & {DATA_WIDTH{mask_wr}} :
                                                data_ex4[0 +: DATA_WIDTH] & {DATA_WIDTH{mask_wr}};

    // Reduction Signals
    assign rdc_data_ex1_o = data_a_i[0 +: DATA_WIDTH];
    assign rdc_data_ex2_o = data_ex1[0 +: DATA_WIDTH];
    assign rdc_data_ex3_o = data_ex2[0 +: DATA_WIDTH];
    assign rdc_data_ex4_o = data_ex3[0 +: DATA_WIDTH];

endmodule