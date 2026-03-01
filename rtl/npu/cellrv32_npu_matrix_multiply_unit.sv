// ######################################################################################################################
// # << CELLRV32 - NPU Matrix Multiply Unit >>                                                                          #
// # ****************************************************************************************************************** #
// # This is the matrix multiply unit. It has inputs to load weights to it's MACC components and inputs for             #
// # the matrix multiply operation.                                                                                     #
// # The matrix multiply unit is a systolic array consisting of identical MACC components.                              #
// # The MACCs are laid to a 2 dimensional grid.                                                                        #
// # The input has to be fed diagonally, because of the delays caused by the MACC registers.                            #
// # The partial sums are 'flowing down' the array and the input has to be delayed.                                     #
// # ****************************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_matrix_multiply_unit #(
    parameter int MATRIX_WIDTH = 14
)(
    input  logic        clk_i                              ,
    input  logic        rstn_i                             ,
    input  logic        enable_i                           ,
    input  logic [7:0]  wei_data_i       [0:MATRIX_WIDTH-1], // Input for the weights, connected to the MACC's weight input
    input  logic        wei_signed_i                       , // Determines if the weight input is signed or unsigned
    input  logic [7:0]  systolic_data_i  [0:MATRIX_WIDTH-1], // The diagonally fed input data
    input  logic        systolic_signed_i                  , // Determines if the systolic input is signed or unsigned
    input  logic        act_wei_i                          , // Activates the loaded weights sequentially
    input  logic        load_wei_i                         , // Preloads one column of weights with WEIGHT_DATA
    input  logic [7:0]  wei_addr_i                         , // Addresses up to 256 columns of pre-weights
    output logic [31:0] result_o         [0:MATRIX_WIDTH-1]  // The result of the matrix multiply
);
    // Internal signals
    logic [31:0] interim_result [0:MATRIX_WIDTH-1][0:MATRIX_WIDTH-1];
    
    // For address conversion
    logic load_weight_map [0:MATRIX_WIDTH-1];
    
    logic [MATRIX_WIDTH-2:0] activate_control_cs, activate_control_ns;
    logic [MATRIX_WIDTH-1:0] activate_map;
    
    // For sign extension
    logic [8:0] extended_weight_data [0:MATRIX_WIDTH-1];
    logic [8:0] extended_systolic_data [0:MATRIX_WIDTH-1];
    
    // For result sign extension
    logic [2+MATRIX_WIDTH-1:0] sign_control_cs, sign_control_ns;

    // Linear shift register logic
    always_comb begin
        activate_control_ns[MATRIX_WIDTH-2:1] = activate_control_cs[MATRIX_WIDTH-3:0];
        activate_control_ns[0] = act_wei_i;
        
        sign_control_ns[2+MATRIX_WIDTH-1:1] = sign_control_cs[2+MATRIX_WIDTH-2:0];
        sign_control_ns[0] = systolic_signed_i;
        
        activate_map = {activate_control_cs, act_wei_i};
    end

    // Address conversion
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            load_weight_map[i] = 1'b0;
        end
        
        if (load_wei_i) begin
            load_weight_map[wei_addr_i] = 1'b1;
        end
    end
    
    // Sign extension
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            if (wei_signed_i) begin
                extended_weight_data[i] = {wei_data_i[i][BYTE_WIDTH-1], wei_data_i[i]};
            end else begin
                extended_weight_data[i] = {1'b0, wei_data_i[i]};
            end
            
            if (sign_control_ns[i]) begin
                extended_systolic_data[i] = {systolic_data_i[i][BYTE_WIDTH-1], systolic_data_i[i]};
            end else begin
                extended_systolic_data[i] = {1'b0, systolic_data_i[i]};
            end
        end
    end

    // MACC array generation
    generate
        for (genvar i = 0; i < MATRIX_WIDTH; i++) begin : MACC_ROW
            for (genvar j = 0; j < MATRIX_WIDTH; j++) begin : MACC_COL
                // ====================================================== 
                // Upper left element (i=0, j=0)
                // ====================================================== 
                if (i == 0 && j == 0) begin : UPPER_LEFT_ELEMENT
                    MACC #(
                        .LAST_SUM_WIDTH   (1), // Just to avoid zero width, will not be used          ),
                        .PARTIAL_SUM_WIDTH(2*EXTENDED_BYTE_WIDTH)
                    ) macc_inst (
                        .clk_i     (clk_i                                          ),
                        .rstn_i    (rstn_i                                         ),
                        .enable_i  (enable_i                                       ),
                        .wei_i     (extended_weight_data[j]                        ),
                        .pre_wei_i (load_weight_map[i]                             ),
                        .load_wei_i(activate_map[i]                                ),
                        .in_i      (extended_systolic_data[i]                      ),
                        .last_sum_i(1'b0                                           ),
                        .part_sum_o(interim_result[i][j][2*EXTENDED_BYTE_WIDTH-1:0])
                    );
                end
                // ====================================================== 
                // First column (i=0, j>0)
                // ====================================================== 
                else if (i == 0 && j > 0) begin : FIRST_COLUMN
                    MACC #(
                        .LAST_SUM_WIDTH   (1), // Just to avoid zero width, will not be used          ),
                        .PARTIAL_SUM_WIDTH(2*EXTENDED_BYTE_WIDTH)
                    ) macc_inst (
                        .clk_i     (clk_i                                          ),
                        .rstn_i    (rstn_i                                         ),
                        .enable_i  (enable_i                                       ),
                        .wei_i     (extended_weight_data[j]                        ),
                        .pre_wei_i (load_weight_map[i]                             ),
                        .load_wei_i(activate_map[i]                                ),
                        .in_i      (extended_systolic_data[i]                      ),
                        .last_sum_i(1'b0                                           ),
                        .part_sum_o(interim_result[i][j][2*EXTENDED_BYTE_WIDTH-1:0])
                    );
                end
                // ====================================================== 
                // Left full elements (i>0 && i<=2*(BYTE_WIDTH-1) && j=0)
                // ====================================================== 
                else if (i > 0 && i <= 2*(BYTE_WIDTH-1) && j == 0) begin : LEFT_FULL_ELEMENTS
                    MACC #(
                        .LAST_SUM_WIDTH   (2*EXTENDED_BYTE_WIDTH + i - 1),
                        .PARTIAL_SUM_WIDTH(2*EXTENDED_BYTE_WIDTH + i    )
                    ) macc_inst (
                        .clk_i     (clk_i                                                  ),
                        .rstn_i    (rstn_i                                                 ),
                        .enable_i  (enable_i                                               ),
                        .wei_i     (extended_weight_data[j]                                ),
                        .pre_wei_i (load_weight_map[i]                                     ),
                        .load_wei_i(activate_map[i]                                        ),
                        .in_i      (extended_systolic_data[i]                              ),
                        .last_sum_i(interim_result[i-1][j][2*EXTENDED_BYTE_WIDTH + i - 2:0]),
                        .part_sum_o(interim_result[i][j][2*EXTENDED_BYTE_WIDTH + i - 1:0]  )
                    );
                end
                // ====================================================== 
                // Full columns (i>0 && i<=2*(BYTE_WIDTH-1) && j>0)
                // ====================================================== 
                else if (i > 0 && i <= 2*(BYTE_WIDTH-1) && j > 0) begin : FULL_COLUMNS
                    MACC #(
                        .LAST_SUM_WIDTH   (2*EXTENDED_BYTE_WIDTH + i - 1),
                        .PARTIAL_SUM_WIDTH(2*EXTENDED_BYTE_WIDTH + i    )
                    ) macc_inst (
                        .clk_i    (clk_i                                                   ),
                        .rstn_i   (rstn_i                                                  ),
                        .enable_i (enable_i                                                ),
                        .wei_i    (extended_weight_data[j]                                 ),
                        .pre_wei_i(load_weight_map[i]                                      ),
                        .load_wei_i(activate_map[i]                                        ),
                        .in_i      (extended_systolic_data[i]                              ),
                        .last_sum_i(interim_result[i-1][j][2*EXTENDED_BYTE_WIDTH + i - 2:0]),
                        .part_sum_o(interim_result[i][j][2*EXTENDED_BYTE_WIDTH + i - 1:0]  )
                    );
                end
                // ====================================================== 
                // Left cut elements (i>2*BYTE_WIDTH && j=0)
                // ====================================================== 
                else if (i > 2*BYTE_WIDTH && j == 0) begin : LEFT_CUTTED_ELEMENT
                    MACC #(
                        .LAST_SUM_WIDTH   (4*BYTE_WIDTH),
                        .PARTIAL_SUM_WIDTH(4*BYTE_WIDTH)
                    ) macc_inst (
                        .clk_i     (clk_i                    ),
                        .rstn_i    (rstn_i                   ),
                        .enable_i  (enable_i                 ),
                        .wei_i     (extended_weight_data[j]  ),
                        .pre_wei_i (load_weight_map[i]       ),
                        .load_wei_i(activate_map[i]          ),
                        .in_i      (extended_systolic_data[i]),
                        .last_sum_i(interim_result[i-1][j]   ),
                        .part_sum_o(interim_result[i][j]     )
                    );
                end
                // ====================================================== 
                // Cut columns (i>2*BYTE_WIDTH && j>0)
                // ====================================================== 
                else if (i > 2*BYTE_WIDTH && j > 0) begin : CUTTED_COLUMNS
                    MACC #(
                        .LAST_SUM_WIDTH   (4*BYTE_WIDTH),
                        .PARTIAL_SUM_WIDTH(4*BYTE_WIDTH)
                    ) macc_inst (
                        .clk_i     (clk_i                    ),
                        .rstn_i    (rstn_i                   ),
                        .enable_i  (enable_i                 ),
                        .wei_i     (extended_weight_data[j]  ),
                        .pre_wei_i (load_weight_map[i]       ),
                        .load_wei_i(activate_map[i]          ),
                        .in_i      (extended_systolic_data[i]),
                        .last_sum_i(interim_result[i-1][j]   ),
                        .part_sum_o(interim_result[i][j]     )
                    );
                end
            end
        end
    endgenerate

    // Result assignment
    logic [2*EXTENDED_BYTE_WIDTH+MATRIX_WIDTH-2:0] result_data_v;
    logic [4*BYTE_WIDTH-1:2*EXTENDED_BYTE_WIDTH+MATRIX_WIDTH-1] extend_v;

    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            
            result_data_v = interim_result[MATRIX_WIDTH-1][i][2*EXTENDED_BYTE_WIDTH+MATRIX_WIDTH-2:0];
            
            if (sign_control_cs[2+MATRIX_WIDTH-1]) begin
                extend_v = {(4*BYTE_WIDTH-(2*EXTENDED_BYTE_WIDTH+MATRIX_WIDTH-1)){interim_result[MATRIX_WIDTH-1][i][2*EXTENDED_BYTE_WIDTH+MATRIX_WIDTH-2]}};
            end else begin
                extend_v = '0;
            end
            
            result_o[i] = {extend_v, result_data_v};
        end
    end
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            activate_control_cs <= '0;
            sign_control_cs <= '0;
        end else begin
            activate_control_cs <= activate_control_ns;
            sign_control_cs <= sign_control_ns;
        end
    end

endmodule