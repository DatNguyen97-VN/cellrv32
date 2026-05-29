// ================================================================
// Pipeline FIFO depth-2
// ================================================================
module PipelineFifo #(
    parameter type T = logic,
    parameter int DEPTH = 2
) (
    input  logic clk_i      ,
    input  logic rstn_i     ,
    input  logic enq_en_i   ,
    output logic notFull_o  ,
    input  T     enq_val_i  ,
    input  logic deq_en_i   ,
    output logic notEmpty_o ,
    output T     first_val_o
);
    T mem [DEPTH-1:0];
    logic [$clog2(DEPTH):0] count;
    logic [$clog2(DEPTH)-1:0] rd_ptr, wr_ptr;
 
    assign notFull_o  = (count < DEPTH);
    assign notEmpty_o = (count > 0);
    assign first_val_o = mem[rd_ptr];
 
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            count  <= '0; 
            rd_ptr <= '0; 
            wr_ptr <= '0;
        end else begin
            case ({enq_en_i & notFull_o, deq_en_i & notEmpty_o})
                // write-only
                2'b10 : begin
                    mem[wr_ptr] <= enq_val_i; 
                    wr_ptr      <= wr_ptr + 1; 
                    count       <= count + 1; 
                end
                // read-only
                2'b01: begin 
                    rd_ptr <= rd_ptr + 1; 
                    count  <= count - 1; 
                end
                // both read-write
                2'b11: begin 
                    mem[wr_ptr] <= enq_val_i; 
                    wr_ptr      <= wr_ptr + 1; 
                    rd_ptr      <= rd_ptr + 1; 
                end
                default:;
            endcase
        end
    end
endmodule
 
// ================================================================
// Bypass FIFO depth-1 (mkBypassFifo)
// ================================================================
module BypassFifo #(
    parameter type T = logic
) (
    input  logic clk_i     ,
    input  logic rstn_i    ,
    input  logic enq_en_i  ,
    output logic notFull_o ,
    input  T     enq_val_i ,
    input  logic deq_en_i  ,
    output logic notEmpty_o,
    output T     first_val_o
);
    T mem;
    logic             valid;
 
    assign notEmpty_o  = valid | enq_en_i;
    assign notFull_o   = ~valid | deq_en_i;
    assign first_val_o = valid ? mem : enq_val_i;
 
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin 
            valid <= 1'b0; 
            mem   <= '0; 
        end else case ({enq_en_i & notFull_o, deq_en_i & notEmpty_o})
            2'b10: begin
                mem   <= enq_val_i; 
                valid <= 1'b1; 
            end
            2'b01: begin 
                valid <= 1'b0;
            end
            2'b11: begin 
                mem   <= enq_val_i; 
                valid <= 1'b1; 
            end
            default:;
        endcase
    end
endmodule : BypassFifo
