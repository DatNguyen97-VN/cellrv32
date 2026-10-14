// ######################################################################################################
// # << CELLRV32 - NPU Systolic Data Setup >>                                                           #
// # ************************************************************************************************** #
// # This component takes a byte array and diagonalizes it for the matrix multiply unit.                #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_systolic_data_setup #(
    parameter int MATRIX_WIDTH = 14
)(
    input  logic                  clk_i                        ,
    input  logic                  rstn_i                       ,
    input  logic                  enable_i                     ,
    input  logic [BYTE_WIDTH-1:0] data_i     [MATRIX_WIDTH-1:0], // The byte array input to be diagonalized
    output logic [BYTE_WIDTH-1:0] systolic_o [MATRIX_WIDTH-1:0]  // The diagonalized output
);

    // Buffer register for creating diagonal pattern
    // Only need registers for indices 1 to MATRIX_WIDTH-1
    logic [BYTE_WIDTH-1:0] buffer_reg      [MATRIX_WIDTH-1:1][MATRIX_WIDTH-1:1];
    logic [BYTE_WIDTH-1:0] buffer_reg_next [MATRIX_WIDTH-1:1][MATRIX_WIDTH-1:1];
    
    // Combinational logic for shift register next state
    always_comb begin
        // Initialize next state
        for (int i = 1; i < MATRIX_WIDTH; i++) begin
            for (int j = 1; j < MATRIX_WIDTH; j++) begin
                if (i == 1) begin
                    // First row gets data from input (excluding index 0)
                    buffer_reg_next[i][j] = data_i[j];
                end else begin
                    // Other rows shift from previous row
                    buffer_reg_next[i][j] = buffer_reg[i-1][j];
                end
            end
        end
    end
    
    // Output assignment
    // Diagonal extraction for systolic output
    always_comb begin
        // First output is directly from input
        systolic_o[0] = data_i[0];
        
        for (int i = 1; i < MATRIX_WIDTH; i++) begin
            systolic_o[i] = buffer_reg[i][i];
        end
    end
    
    // Sequential logic for buffer register
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            // Reset all buffer registers to zero
            for (int i = 1; i < MATRIX_WIDTH; i++) begin
                for (int j = 1; j < MATRIX_WIDTH; j++) begin
                    buffer_reg[i][j] <= '0;
                end
            end
        end else if (enable_i) begin
            // Update buffer registers when enabled
            buffer_reg <= buffer_reg_next;
        end
    end

endmodule