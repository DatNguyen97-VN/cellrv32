// ######################################################################################################
// # << CELLRV32 - NPU Fifo >>                                                                          #
// # ************************************************************************************************** #
// # TThis component includes a simple FIFO.                                                            #
// # The FIFO uses distributed RAM.                                                                     #
// # ************************************************************************************************** #

module cellrv32_npu_fifo #(
    parameter int FIFO_WIDTH   = 8,
    parameter int FIFO_DEPTH   = 32,
    parameter int USE_DIST_RAM = 0  // 1 for distributed RAM, 0 for FF implementation
) (
    input  logic                  clk_i   ,
    input  logic                  rstn_i  ,
    input  logic [FIFO_WIDTH-1:0] in_i    , // Write port of the FIFO.
    input  logic                  wr_en_i , // Write enable flag for the FIFO.
    
    output logic [FIFO_WIDTH-1:0] out_o   , // Read port of the FIFO.
    input  logic                  nxt_en_i, // Read or 'next' enable of the FIFO (clears the current value).
    
    output logic                  empty_o , // Determines if the FIFO is empty.
    output logic                  full_o    // Determines if the FIFO is full.
);

    generate
        if (USE_DIST_RAM) begin : DIST_RAM_FIFO
            // Do nothing here.
        end else begin : FF_FIFO
            // Flip-flop based FIFO implementation
            logic [FIFO_WIDTH-1:0] fifo_data [0:FIFO_DEPTH-1];
            logic [$clog2(FIFO_DEPTH+1)-1:0] size;
            
            assign out_o = fifo_data[0];
            
            always_ff @(posedge clk_i or negedge rstn_i) begin
                if (!rstn_i) begin
                    size <= '0;
                    for (int i = 0; i < FIFO_DEPTH; i++) begin
                        fifo_data[i] <= '0;
                    end
                    empty_o <= 1'b1;
                    full_o <= 1'b0;
                end else begin
                    // Handle read (shift down)
                    if (nxt_en_i && size > 0) begin
                        for (int i = 1; i < FIFO_DEPTH; i++) begin
                            fifo_data[i-1] <= fifo_data[i];
                        end
                        size <= size - 1;
                        full_o <= 1'b0;
                    end
                    
                    // Handle write
                    if (wr_en_i && size < FIFO_DEPTH) begin
                        fifo_data[size] <= in_i;
                        size <= size + 1;
                        empty_o <= 1'b0;
                    end
                    
                    // Update flags based on size
                    case (size)
                        FIFO_DEPTH: begin
                            empty_o <= 1'b0;
                            full_o <= 1'b1;
                        end
                        0: begin
                            empty_o <= 1'b1;
                            full_o <= 1'b0;
                        end
                        default: begin
                            // Maintain current state for intermediate values
                        end
                    endcase
                end
            end
        end
    endgenerate

endmodule