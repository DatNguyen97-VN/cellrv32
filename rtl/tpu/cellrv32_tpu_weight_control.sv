// ######################################################################################################
// # << CELLRV32 - NPU Weight Control >>                                                                #
// # ************************************************************************************************** #
// # This component includes the control unit for weight loading.                                       #
// # Weights are read from the weight buffer and get stored sequentially in the matrix multiply unit.   #
// # If the control unit gets to the end of the preweight registers of the matrix multiply unit,        #
// # it restarts loading the next batch of values.                                                      #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_weight_control #(
    parameter MATRIX_WIDTH = 14
)(
    input  logic                            clk_i           ,
    input  logic                            rstn_i          ,
    input  logic                            enable_i        ,
    input  weight_instruction_t             instruction_i   , // The weight instruction to be executed
    input  logic                            instruction_en_i, // Enable for instruction
    output logic                            wei_read_en_o   , // Read enable flag for weight buffer
    output logic [WEIGHT_ADDRESS_WIDTH-1:0] wei_buff_addr_o , // Address for weight buffer read
    output logic                            load_wei_o      , // Load weight flag for matrix multiply unit
    output logic [7:0]                      wei_addr_o      , // Address of the weight for matrix multiply unit
    output logic                            wei_signed_o    , // Determines if the weights are signed or unsigned
    output logic                            busy_o          , // If the control unit is busy, a new instruction shouldn't be fed
    output logic                            resource_busy_o   // The resources are in use and the instruction is not fully finished yet
);

    // Local parameters
    localparam int WEIGHT_COUNTER_WIDTH = $clog2(MATRIX_WIDTH);

    // Internal signals and registers
    logic                            running;
    logic [31:0]                     length_counter; // Counter for the length of the current weight loading operation
    logic                            weight_read_en;
    logic [WEIGHT_COUNTER_WIDTH-1:0] weight_buffer_address;
    logic                            load_weight_reg;

    // Pipeline registers for weight address and control signals
    logic                            weight_signed;
    logic [WEIGHT_COUNTER_WIDTH-1:0] weight_address;

    // -----------------------------------
    // Main control logic
    // -----------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : read_weight_buffer
        if (!rstn_i) begin
            running               <= 1'b0;
            length_counter        <= '0;
            weight_read_en        <= 1'b0;
            weight_buffer_address <= '0;
            weight_signed         <= 1'b0;
        end else if (enable_i) begin
            if (!running && instruction_en_i) begin
                running               <= 1'b1;
                length_counter        <= instruction_i.calc_len;
                weight_read_en        <= 1'b1;
                weight_buffer_address <= instruction_i.wei_addr;
                weight_signed         <= instruction_i.opcode[0];
            end else if (running) begin
                if (weight_buffer_address < length_counter - 1) begin
                    running               <= 1'b1;
                    weight_read_en        <= 1'b1;
                    weight_buffer_address <= weight_buffer_address + 1'b1;
                end else begin
                    running               <= 1'b0;
                    weight_read_en        <= 1'b0;
                    weight_buffer_address <= '0;
                end
            end
        end
    end : read_weight_buffer

    always_ff @(posedge clk_i or negedge rstn_i) begin : load_weights_into_matrix_multiply
        if (!clk_i) begin
            load_weight_reg <= 1'b0;
            weight_address  <= '0;
        end else if (enable_i) begin
            load_weight_reg <= weight_read_en;
            weight_address  <= weight_buffer_address;
        end
    end : load_weights_into_matrix_multiply
    
    // Output assignments
    assign wei_read_en_o   = weight_read_en;
    assign wei_buff_addr_o = weight_buffer_address;
    assign load_wei_o      = load_weight_reg;
    assign wei_addr_o      = weight_address;
    assign wei_signed_o    = weight_signed & load_weight_reg;
    assign busy_o          = running;
    assign resource_busy_o = running | load_weight_reg;

endmodule