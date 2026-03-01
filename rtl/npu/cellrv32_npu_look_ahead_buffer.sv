// ########################################################################################################
// # << CELLRV32 - NPU Look Ahead Buffer >>                                                               #
// # **************************************************************************************************** #
// # This component includes a small look ahead buffer for instructions.                                  #
// # Weight instructions should be executed with matrix multiply instructions in parallel.                #
// # The look ahead buffer waits for a matrix multiply instruction, when a weight instruction was feeded. #
// # **************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_look_ahead_buffer (
    input  logic         clk_i      ,
    input  logic         rstn_i     ,
    input  logic         enable_i   ,
    input  logic         inst_busy_i, // Busy feedback from control coordinator to stop pipelining
    input  instruction_t inst_i     , // The input for instructions
    input  logic         inst_wr_i  , // Write flag for instructions
    output instruction_t inst_o     , // The output for pipelined instructions
    output logic         inst_rd_o    // Read flag for instructions
);
    // Internal registers - current state
    instruction_t input_reg_cs;
    instruction_t pipe_reg_cs;
    instruction_t output_reg_cs;
    
    logic input_write_cs;
    logic pipe_write_cs;
    logic output_write_cs;
    
    // Internal registers - next state
    instruction_t input_reg_ns;
    instruction_t pipe_reg_ns;
    instruction_t output_reg_ns;
    
    logic input_write_ns;
    logic pipe_write_ns;
    logic output_write_ns;
    
    // Combinational logic assignments
    assign input_reg_ns = inst_i;
    assign input_write_ns = inst_wr_i;
    
    assign inst_o = (inst_busy_i == 1'b0) ? output_reg_cs : '0;
    assign inst_rd_o = (inst_busy_i == 1'b0) ? output_write_cs : 1'b0;
    
    // Look ahead combinational logic
    always_comb begin
        if (pipe_write_cs) begin
            // Check if weight instruction is in pipe
            if (pipe_reg_cs.opcode[OP_CODE_WIDTH-1:3] == 5'b00001) begin
                if (input_write_cs) begin
                    // Weight in pipe, new instruction available - advance pipeline
                    pipe_reg_ns     = input_reg_cs;
                    output_reg_ns   = pipe_reg_cs;
                    pipe_write_ns   = input_write_cs;
                    output_write_ns = pipe_write_cs;
                end else begin
                    // Weight in pipe, wait until next instruction is fed
                    pipe_reg_ns     = pipe_reg_cs;
                    output_reg_ns   = '0;
                    pipe_write_ns   = pipe_write_cs;
                    output_write_ns = 1'b0;
                end
            end else begin
                // Non-weight instruction in pipe - normal advance
                pipe_reg_ns     = input_reg_cs;
                output_reg_ns   = pipe_reg_cs;
                pipe_write_ns   = input_write_cs;
                output_write_ns = pipe_write_cs;
            end
        end else begin
            // No valid instruction in pipe - normal advance
            pipe_reg_ns     = input_reg_cs;
            output_reg_ns   = pipe_reg_cs;
            pipe_write_ns   = input_write_cs;
            output_write_ns = pipe_write_cs;
        end
    end
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            input_reg_cs <= '0;
            pipe_reg_cs <= '0;
            output_reg_cs <= '0;
            
            input_write_cs <= 1'b0;
            pipe_write_cs <= 1'b0;
            output_write_cs <= 1'b0;
        end else if (enable_i && !inst_busy_i) begin
            input_reg_cs <= input_reg_ns;
            pipe_reg_cs <= pipe_reg_ns;
            output_reg_cs <= output_reg_ns;
            
            input_write_cs <= input_write_ns;
            pipe_write_cs <= pipe_write_ns;
            output_write_cs <= output_write_ns;
        end
    end

endmodule