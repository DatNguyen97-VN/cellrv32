// ######################################################################################################
// # << CELLRV32 - NPU Activation >>                                                                    #
// # ************************************************************************************************** #
// # This component calculates the selected activation function for the input array.                    #
// # The input is rounded, has some checker logic for ReLU and look-up-tables for the sigmoid function. #
// # ************************************************************************************************** #
`ifndef  _INCL_ACTIVATION_DEFINITIONS
  `define _INCL_ACTIVATION_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_ACTIVATION_DEFINITIONS

module cellrv32_npu_activation #(
    parameter int MATRIX_WIDTH = 14
)(
    input  logic        clk_i                                 ,
    input  logic        rstn_i                                ,
    input  logic        enable_i                              ,
    
    input  logic [3:0]  activation_function_i                 ,
    input  logic        signed_not_unsigned_i                 ,
    
    input  logic [31:0] activation_input_i  [0:MATRIX_WIDTH-1], // WORD_TYPE equivalent
    output logic [7:0]  activation_output_o [0:MATRIX_WIDTH-1]  // BYTE_TYPE equivalent
);

    // Constants for sigmoid lookup tables
    localparam int SIGMOID_UNSIGNED[0:164] = '{
        128,130,132,134,136,138,140,142,144,146,148,150,152,154,156,157,159,161,163,165,167,169,170,172,174,176,177,179,181,182,184,186,187,189,190,192,193,195,196,198,199,200,202,203,204,206,207,208,209,210,212,213,214,215,216,217,218,219,220,221,222,223,224,225,225,226,227,228,229,229,230,231,232,232,233,234,234,235,235,236,237,237,
        238,238,239,239,240,240,241,241,241,242,242,243,243,243,244,244,245,245,245,246,246,246,246,247,247,247,248,248,248,248,248,249,249,249,249,250,250,250,250,250,250,251,251,251,251,251,251,252,252,252,252,252,252,252,252,253,253,253,253,253,253,253,253,253,253,253,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254,254
    };
    
    localparam int SIGMOID_SIGNED[-88:70] = '{
        // -88 to -1
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,6,6,6,7,7,8,8,9,9,10,10,11,12,12,13,14,14,15,16,17,18,19,20,21,22,23,25,26,27,29,30,31,33,34,36,38,39,41,43,45,46,48,50,52,54,56,58,60,62,
        // 0 to 70
        64,66,68,70,72,74,76,78,80,82,83,85,87,89,90,92,94,95,97,98,99,101,102,103,105,106,107,108,109,110,111,112,113,114,114,115,116,116,117,118,118,119,119,120,120,121,121,122,122,122,123,123,123,124,124,124,124,124,125,125,125,125,125,126,126,126,126,126,126,126,126
    };

    // Internal registers
    logic [31:0] input_reg [0:MATRIX_WIDTH-1];
    logic [7:0]  input_pipe0 [0:MATRIX_WIDTH-1];
    logic [23:0] relu_round_reg [0:MATRIX_WIDTH-1];     // 3*BYTE_WIDTH
    logic [20:0] sigmoid_round_reg [0:MATRIX_WIDTH-1];
    
    logic [7:0] relu_output [0:MATRIX_WIDTH-1];
    logic [7:0] sigmoid_output [0:MATRIX_WIDTH-1];
    logic [7:0] output_reg [0:MATRIX_WIDTH-1];
    
    logic [3:0] activation_function_reg0;
    logic [3:0] activation_function_reg1;
    logic [1:0] signed_not_unsigned_reg;
    logic signed [19:0] sigmoid_index;

    // Input register
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            input_reg <= '{default: '0};
        end else if (enable_i) begin
            input_reg <= activation_input_i;
        end
    end

    // Rounding logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            input_pipe0       <= '{default: '0};
            relu_round_reg    <= '{default: '0};
            sigmoid_round_reg <= '{default: '0};
        end else if (enable_i) begin
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                // Extract upper byte for pipe0
                input_pipe0[i] <= input_reg[i][31:24];
                
                // -----------------------------------------------------------
                // Input quantization adds highest non-mappable fractional bit for rounding,
                // round to nearest, ties to max magnitude
                //------------------------------------------------------------
                // ReLU Quantization - Q(u)16.8 input range
                relu_round_reg[i] <= input_reg[i][31:8] + input_reg[i][7];
                
                // Sigmoid Quantization
                if (!signed_not_unsigned_reg[0]) begin
                    // Unsinged - Qu16.5 input range
                    sigmoid_round_reg[i] <= input_reg[i][31:11] + input_reg[i][10];
                end else begin
                    // Singed - Q16.4 input range
                    sigmoid_round_reg[i] <= {input_reg[i][31:12] + input_reg[i][11], 1'b0};
                end
            end
        end
    end

    // Activation function registers
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            activation_function_reg0 <= '0;
            activation_function_reg1 <= '0;
        end else if (enable_i) begin
            activation_function_reg0 <= activation_function_i;
            activation_function_reg1 <= activation_function_reg0;
        end
    end

    // Signed/unsigned register
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            signed_not_unsigned_reg <= '0;
        end else if (enable_i) begin
            signed_not_unsigned_reg <= {signed_not_unsigned_reg[0], signed_not_unsigned_i};
        end
    end

    // ReLU activation logic
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            if (signed_not_unsigned_reg[1]) begin
                // Signed case
                if ($signed(relu_round_reg[i]) < 0) begin
                    relu_output[i] = 8'h00;
                end else if ($signed(relu_round_reg[i]) > 127) begin
                    relu_output[i] = 8'h7F;  // Bounded ReLU
                end else begin
                    relu_output[i] = relu_round_reg[i][7:0];
                end
            end else begin
                // Unsigned case
                if (relu_round_reg[i] > 255) begin
                    relu_output[i] = 8'hFF;  // Bounded ReLU
                end else begin
                    relu_output[i] = relu_round_reg[i][7:0];
                end
            end
        end
    end

    // Sigmoid activation logic
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            if (signed_not_unsigned_reg[1]) begin
                // Signed case
                // Signed - Qu4.4 table range
                sigmoid_index = $signed(sigmoid_round_reg[i][20:1]);
                
                if (sigmoid_index < -88) begin
                    sigmoid_output[i] = 8'h00;
                end else if (sigmoid_index > 70) begin
                    sigmoid_output[i] = 8'h7F;
                end else begin
                    sigmoid_output[i] = SIGMOID_SIGNED[sigmoid_index];
                end
            end else begin
                // Unsigned case
                // unsigned - Qu3.5 table range
                if (sigmoid_round_reg[i] > 164) begin
                    sigmoid_output[i] = 8'hFF;
                end else begin
                    sigmoid_output[i] = SIGMOID_UNSIGNED[sigmoid_round_reg[i]];
                end
            end
        end
    end

    // Choose activation function
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            output_reg <= '{default: '0};
        end else if (enable_i) begin
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                case (activation_type_t'(activation_function_reg1))
                    RELU: output_reg[i] <= relu_output[i];
                    SIGMOID: output_reg[i] <= sigmoid_output[i];
                    NO_ACTIVATION: output_reg[i] <= input_pipe0[i];
                    default: begin
                        $error("Unknown activation function!");
                        output_reg[i] <= input_pipe0[i];
                    end
                endcase
            end
        end
    end

    // Output assignment
    assign activation_output_o = output_reg;

endmodule