// ######################################################################################################
// # << CELLRV32 - NPU Activation Control >>                                                            #
// # ************************************************************************************************** #
// # This component includes the control unit for the activation operation.                             #
// # This unit controls the data flow from the accumulators, pipes it through the activation component  #
// # and stores the results back in the unified buffer.                                                 #
// # Instructions will be executed delayed, so a previous matrix multiply can be finished just in time. #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_activation_control #(
    parameter int MATRIX_WIDTH = 14
) (
    input  logic                                 clk_i            ,
    input  logic                                 rstn_i           ,
    input  logic                                 enable_i         ,
    input  instruction_t                         inst_i           , // The activation instruction to be executed.
    input  logic                                 inst_en_i        , // enable for instruction.
    output logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_act_addr_o   , // Address for the accumulators
    output logic [ACTIVATION_BIT_WIDTH-1:0]      activation_func_o, // The type of activation function to be calculated.
    output logic                                 signed_unsigned_o, // Determines if the input and output is signed or unsigned.
    output logic [BUFFER_ADDRESS_WIDTH-1:0]      act_buff_addr_o  , // Address for the unified buffer.
    output logic                                 buff_wr_en_o     , // Write enable flag for the unified buffer.
    output logic                                 busy_o           , // If the control unit is busy, a new instruction shouldn't be fed.
    output logic                                 resource_busy_o    // The resources are in use and the instruction is not fully finished yet.
);

    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_act_addr;
    logic [ACTIVATION_BIT_WIDTH-1:0]      activation_func;
    logic                                 signed_unsigned;
    logic [BUFFER_ADDRESS_WIDTH-1:0]      act_buff_addr [3:0];
    logic [3:0]                           buf_write_en;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] length_event2;
    logic                                 running;

    // -----------------------------------
    // Main control logic
    // -----------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : read_accumulator_and_control
        if (!rstn_i) begin
            acc_act_addr     <= '0;
            activation_func  <= '0;
            signed_unsigned  <= 1'b0;
            length_event2     <= '0;
            running          <= 1'b0;
        end else if (enable_i) begin
            if (inst_en_i && !running) begin
                acc_act_addr    <= inst_i.acc_addr;
                activation_func <= inst_i.opcode[3:0];
                signed_unsigned <= inst_i.opcode[4];
                length_event2    <= inst_i.calc_len;
                running         <= 1'b1;
            end else if (running) begin
                if (acc_act_addr < length_event2 - 1) begin
                    acc_act_addr <= acc_act_addr + 1'b1;
                    running      <= 1'b1;
                end else begin
                    acc_act_addr <= '0;
                    running      <= 1'b0;
                end
            end
        end  
    end : read_accumulator_and_control

    always_ff @(posedge clk_i or negedge rstn_i) begin : write_activation_to_buffer
        if (!rstn_i) begin
            act_buff_addr <= '{default : '0};
            buf_write_en  <= '0;
        end else if (enable_i) begin
            act_buff_addr[3] <= act_buff_addr[2];
            act_buff_addr[2] <= act_buff_addr[1];
            act_buff_addr[1] <= act_buff_addr[0];
            act_buff_addr[0] <= acc_act_addr;
            buf_write_en     <= {buf_write_en[3:0], running};
        end  
    end : write_activation_to_buffer

    // Output assignments
    assign acc_act_addr_o    = acc_act_addr;
    assign activation_func_o = activation_func;
    assign signed_unsigned_o = signed_unsigned;
    assign act_buff_addr_o   = act_buff_addr[3];
    assign buff_wr_en_o      = buf_write_en[3];
    assign busy_o            = running;
    assign resource_busy_o   = running | (buf_write_en != 4'h0);
endmodule