// ######################################################################################################
// # << CELLRV32 - NPU Instruction FIFO >>                                                              #
// # ************************************************************************************************** #
// # This component includes a simple FIFO for the instruction type.                                    #
// # Instructions are splitted into 32 Bit words, except for the last word, which is 16 Bit.            #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_instruction_fifo #(
    parameter int FIFO_DEPTH = 32
)(
    input  logic         clk_i     ,
    input  logic         rstn_i    ,
    input  word_t        low_word_i, // The lower word of the instruction
    input  word_t        mid_word_i, // The middle word of the instruction  
    input  halfword_t    up_word_i , // The upper halfword (16 Bit) of the instruction
    input  logic [2:0]   wr_en_i   , // Write enable flags for each word
    output instruction_t inst_o    , // Read port of the FIFO
    input  logic         nxt_en_i  , // Read or 'next' enable of the FIFO (clears current value)
    output logic         empty_o   , // Determines if the FIFO is empty
    output logic         full_o      // Determines if the FIFO is full
);

    // Internal signals
    logic [2:0] empty_vector;
    logic [2:0] full_vector;
    
    word_t lower_output;
    word_t middle_output;
    halfword_t upper_output;
    
    // FIFO status logic
    assign empty_o = |empty_vector;
    assign full_o  = |full_vector;
    
    // Construct output instruction from three FIFO outputs
    assign inst_o = bits_to_instruction({upper_output, middle_output, lower_output});

    // FIFO for lower word (32 bits)
    cellrv32_npu_fifo #(
        .FIFO_WIDTH(4 * BYTE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) FIFO_0 (
        .clk_i   (clk_i          ),
        .rstn_i  (rstn_i         ),
        .in_i    (low_word_i     ),
        .wr_en_i (wr_en_i[0]     ),
        .out_o   (lower_output   ),
        .nxt_en_i(nxt_en_i       ),
        .empty_o (empty_vector[0]),
        .full_o  (full_vector[0] )
    );
    
    // FIFO for middle word (32 bits)
    cellrv32_npu_fifo #(
        .FIFO_WIDTH(4 * BYTE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) FIFO_1 (
        .clk_i   (clk_i          ),
        .rstn_i  (rstn_i         ),
        .in_i    (mid_word_i     ),
        .wr_en_i (wr_en_i[1]     ),
        .out_o   (middle_output  ),
        .nxt_en_i(nxt_en_i       ),
        .empty_o (empty_vector[1]),
        .full_o  (full_vector[1] )
    );
    
    // FIFO for upper halfword (16 bits)
    cellrv32_npu_fifo #(
        .FIFO_WIDTH(2 * BYTE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) FIFO_2 (
        .clk_i   (clk_i          ),
        .rstn_i  (rstn_i         ),
        .in_i    (up_word_i      ),
        .wr_en_i (wr_en_i[2]     ),  
        .out_o   (upper_output   ),
        .nxt_en_i(nxt_en_i       ),
        .empty_o (empty_vector[2]),
        .full_o  (full_vector[2] )
    );

endmodule