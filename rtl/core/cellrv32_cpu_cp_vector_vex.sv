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
    parameter int VECTOR_REGISTERS   = 32,
    parameter int VECTOR_LANES       = 8 ,
    parameter int ADDR_WIDTH         = 32,
    parameter int DATA_WIDTH         = 32,
    parameter int MICROOP_WIDTH      = 7 ,
    parameter int VECTOR_TICKET_BITS = 5 ,
    parameter int FWD_POINT_A        = 1 ,
    parameter int FWD_POINT_B        = 3 ,
    parameter     VECTOR_FP_ALU      = 1 ,
    parameter     VECTOR_FXP_ALU     = 0
) (
    input  logic                                                         clk         ,
    input  logic                                                         rst_n       ,
    output logic                                                         vex_idle_o  ,
    //Issue Interface
    input  logic                                                         valid_i     ,
    input  to_vector_exec [            VECTOR_LANES-1:0]                 exec_data_i ,
    input  to_vector_exec_info                                           exec_info_i ,
    output logic                                                         ready_o     ,
    //Forward Point #1 (EX1)
    output logic          [            VECTOR_LANES-1:0]                 frw_a_en    ,
    output logic          [$clog2(VECTOR_REGISTERS)-1:0]                 frw_a_addr  ,
    output logic          [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] frw_a_data  ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                 frw_a_ticket,
    //Forward Point #2 (EX*)
    output logic          [            VECTOR_LANES-1:0]                 frw_b_en    ,
    output logic          [$clog2(VECTOR_REGISTERS)-1:0]                 frw_b_addr  ,
    output logic          [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] frw_b_data  ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                 frw_b_ticket,
    //Writeback
    output logic          [            VECTOR_LANES-1:0]                 wr_en       ,
    output logic          [$clog2(VECTOR_REGISTERS)-1:0]                 wr_addr     ,
    output logic          [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] wr_data     ,
    output logic          [            VECTOR_LANES-1:0]                 rdc_done_o  ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                 wr_ticket
);


    logic [$clog2(VECTOR_REGISTERS)-1:0]                 dst_ex2, dst_ex3, dst_ex4, dst_wr;
    logic [      VECTOR_TICKET_BITS-1:0]                 ticket_ex2, ticket_ex3, ticket_ex4, ticket_wr;
    logic                                                valid_ex2, valid_ex3, valid_ex4;
    logic                                                head_ex2, head_ex3, head_ex4, head_wr;
    logic                                                end_ex2, end_ex3, end_ex4, end_wr;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex1_i;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex1_o;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex2_i;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex2_o;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex3_i;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex3_o;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex4_i;
    logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] rdc_data_ex4_o;


    logic [VECTOR_LANES-1:0] ready;
    logic [VECTOR_LANES-1:0] vex_pipe_valid;
    logic [VECTOR_LANES-1:0] vex_fp_valid;
    logic is_fp32;
    logic all_thread_done;

    assign ready_o = |ready;
    assign is_fp32 = (exec_info_i.ir_funct3 == funct3_opfvv_c) || (exec_info_i.ir_funct3 == funct3_opfvx_c);

    genvar k;
    generate
        for (k = 0; k < VECTOR_LANES; k++) begin : g_vex_pipe
            assign vex_pipe_valid[k] = valid_i & exec_data_i[k].valid;
            vex_pipe #(
                .VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
                .DATA_WIDTH        (DATA_WIDTH        ),
                .MICROOP_WIDTH     (MICROOP_WIDTH     ),
                .VECTOR_LANES      (VECTOR_LANES      ),
                .VECTOR_LANE_NUM   (k                 ),
                .FWD_POINT_A       (FWD_POINT_A       ),
                .FWD_POINT_B       (FWD_POINT_B       ),
                .VECTOR_FP_ALU     (VECTOR_FP_ALU     ),
                .VECTOR_FXP_ALU    (VECTOR_FXP_ALU    )
            ) vex_pipe (
                .clk           (clk                     ),
                .rst_n         (rst_n                   ),
                //Input
                .valid_i       (vex_pipe_valid[k]       ),
                .fp_valid_o    (vex_fp_valid[k]         ),
                .ready_o       (ready[k]                ),
                .done_i        (all_thread_done         ),
                .mask_i        (exec_data_i[k].mask     ),
                .data_a_i      (exec_data_i[k].data1    ),
                .data_b_i      (exec_data_i[k].data2    ),
                .funct6_i      (exec_info_i.ir_funct6   ),
                .funct3_i      (exec_info_i.ir_funct3   ),
                .frm_i         (exec_info_i.frm         ),
                .vs1_i         (exec_info_i.src1        ),
                .vl_i          (exec_info_i.vl          ),
                .is_rdc_i      (exec_info_i.is_rdc      ),
                //Forward Point #1 (EX1)
                .frw_a_en_o    (frw_a_en[k]             ),
                .frw_a_data_o  (frw_a_data[k]           ),
                //Forward Point #2 (EX*)
                .frw_b_en_o    (frw_b_en[k]             ),
                .frw_b_data_o  (frw_b_data[k]           ),
                //Writeback (EX*)
                .head_uop_ex4_i(head_ex4                ),
                .end_uop_ex4_i (end_ex4                 ),
                .wr_en_o       (wr_en[k]                ),
                .wr_data_o     (wr_data[k]              ),
                .rdc_done_o    (rdc_done_o[k]           ),
                //EX1 Reduction Tree Intf
                .rdc_data_ex1_i(rdc_data_ex1_i[k]       ),
                .rdc_data_ex1_o(rdc_data_ex1_o[k]       ),
                //EX2 Reduction Tree Intf
                .rdc_data_ex2_i(rdc_data_ex2_i[k]       ),
                .rdc_data_ex2_o(rdc_data_ex2_o[k]       ),
                //EX3 Reduction Tree Intf
                .rdc_data_ex3_i(rdc_data_ex3_i[k]       ),
                .rdc_data_ex3_o(rdc_data_ex3_o[k]       ),
                //EX2 Reduction Tree Intf
                .rdc_data_ex4_i(rdc_data_ex4_i[k]       ),
                .rdc_data_ex4_o(rdc_data_ex4_o[k]       )
            );
        end
    endgenerate
    //Connect the Reduction Tree
    //---------------------------
    // EX1
    //---------------------------
    generate
        for (k = 0; k < VECTOR_LANES; k = k + 2) begin: g_rdc_ex1
            assign rdc_data_ex1_i[k] = rdc_data_ex1_o[k+1];
        end
    endgenerate
    //---------------------------
    // EX2
    //---------------------------
    generate if (VECTOR_LANES > 2) begin: g_rdc_ex2
        for (k = 0; k <= VECTOR_LANES/2; k = k + 4) begin: g_rdc_ex2
            assign rdc_data_ex2_i[k] = rdc_data_ex2_o[k+2];
        end
    end endgenerate
    //---------------------------
    // EX3
    //---------------------------
    generate if (VECTOR_LANES > 4) begin: g_rdc_ex3
        for (k = 0; k <= VECTOR_LANES/4; k = k + 8) begin
            assign rdc_data_ex3_i[k] = rdc_data_ex3_o[k+4];
        end
    end endgenerate
    //---------------------------
    // EX4
    //---------------------------
    generate if (VECTOR_LANES > 8) begin: g_rdc_ex4
        for (k = 0; k <= VECTOR_LANES/8; k = k + 16) begin
            assign rdc_data_ex4_i[k] = rdc_data_ex4_o[k+8];
        end
    end endgenerate

    //-----------------------------------------------
    // EX1/EX2 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if(valid_i) begin
            dst_ex2    <= exec_info_i.dst;
            ticket_ex2 <= exec_info_i.ticket;
            head_ex2   <= exec_info_i.head_uop;
            end_ex2    <= exec_info_i.end_uop;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_ex2 <= 1'b0;
        end else begin
            valid_ex2 <= valid_i;
        end
    end
    //-----------------------------------------------
    // EX2/EX3 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if(valid_ex2) begin
            dst_ex3     <= dst_ex2;
            ticket_ex3  <= ticket_ex2;
            head_ex3    <= head_ex2;
            end_ex3     <= end_ex2;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_ex3 <= 1'b0;
        end else begin
            valid_ex3 <= valid_ex2;
        end
    end
    //-----------------------------------------------
    // EX3/EX4 Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if(valid_ex3) begin
            dst_ex4     <= dst_ex3;
            ticket_ex4  <= ticket_ex3;
            head_ex4    <= head_ex3;
            end_ex4     <= end_ex3;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_ex4 <= 1'b0;
        end else begin
            valid_ex4 <= valid_ex3;
        end
    end
    //-----------------------------------------------
    // EX4/WR Flops
    //-----------------------------------------------
    always_ff @(posedge clk) begin
        if(valid_ex4) begin
            dst_wr     <= dst_ex4;
            ticket_wr  <= ticket_ex4;
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
    // Forwarding Points
    //------------------------------------------------------
    // Forward Point #1
    assign frw_a_addr   = exec_info_i.dst;
    assign frw_a_ticket = exec_info_i.ticket;

    // Forward Point #2
    assign frw_b_addr   = dst_ex4;
    assign frw_b_ticket = ticket_ex4;

    // Writeback Signals
    assign wr_addr      = is_fp32 ? fp_dst : dst_wr;
    assign wr_ticket    = ticket_wr;

    assign vex_idle_o   = ~valid_i & ~valid_ex2 & ~valid_ex3 & ~valid_ex4;

endmodule