// ##################################################################################################
// # << CELLRV32 - CPU Co-Processor: Shifter (CPU Base ISA) >>                                      #
// # ********************************************************************************************** #
// # FAST_SHIFT_EN = false (default) : Use bit-serial shifter architecture (small but slow)         #
// # FAST_SHIFT_EN = true            : Use barrel shifter architecture (large but fast)             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS


module cellrv32_cpu_cp_shifter #(
    parameter XLEN          = 32, // data path width
    parameter FAST_SHIFT_EN = 1   // implement fast but large barrel shifter
) (
    /* global control */
    input  logic clk_i,                            // global clock, rising edge
    input  logic rstn_i,                           // global reset, low-active, async
    input  ctrl_bus_t ctrl_i,                      // main control bus
    input  logic start_i,                          // trigger operation
    /* data input */
    input  logic [XLEN-1:0] rs1_i,                 // rf source 1
    input  logic [$clog2(XLEN)-1:0] shamt_i,                  // shift amount
    /* result and status */
    output logic [XLEN-1:0] res_o,                 // operation result
    output logic valid_o                           // data output valid
);
    
    /* serial shifter */
    typedef struct {
        logic busy;    
        logic busy_ff; 
        logic done;    
        logic [$clog2(XLEN)-1:0] cnt;     
        logic [XLEN-1:0] sreg;    
    } shifter_t;
    shifter_t shifter;

    /* barrel shifter */
    typedef logic[XLEN-1:0] bs_level_t [5:0];
    bs_level_t bs_level;
    logic bs_start;
    logic [XLEN-1:0] bs_result;

    // Serial Shifter (small but slow) -----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
            if (FAST_SHIFT_EN == 1'b0) begin : serial_shifter
                always_ff @( posedge clk_i or negedge rstn_i ) begin : serial_shifter_core
                    if (rstn_i == 1'b0) begin
                        shifter.busy_ff <= 1'b0;
                        shifter.busy    <= 1'b0;
                        shifter.cnt     <= '0;
                        shifter.sreg    <= '0;
                    end else begin
                        /* arbitration */
                        shifter.busy_ff <= shifter.busy;
                        if (start_i == 1'b1) begin
                            shifter.busy <= 1'b1;
                        end else if ((shifter.done == 1'b1) || (ctrl_i.cpu_trap == 1'b1)) begin // abort on trap
                            shifter.busy <= 1'b0;
                        end
                        /* shift register */
                        if (start_i == 1'b1) begin // trigger new shift
                            shifter.cnt  <= shamt_i;
                            shifter.sreg <= rs1_i;
                        end else if ((|shifter.cnt) == 1'b1) begin // running shift (cnt != 0)
                            shifter.cnt <= shifter.cnt - 1'b1;
                            if (ctrl_i.ir_funct3[2] == 1'b0) begin // SLL: shift left logical
                                shifter.sreg <= {shifter.sreg[$bits(shifter.sreg)-2:0], 1'b0};
                            end else begin // SRL: shift right logical / SRA: shift right arithmetical
                                shifter.sreg <= {(shifter.sreg[$bits(shifter.sreg)-1] & ctrl_i.ir_funct12[10]), shifter.sreg[$bits(shifter.sreg)-1:1]};
                            end
                        end
                    end
                end : serial_shifter_core
                
                /* shift control/output */
                assign shifter.done = ((|shifter.cnt[$bits(shifter.cnt)-1:1]) == 1'b0) ? 1'b1 : 1'b0; 
                assign valid_o      = shifter.busy & shifter.done;
                assign res_o        = ((shifter.busy == 1'b0) & (shifter.busy_ff == 1'b1)) ? shifter.sreg : '0;

            end : serial_shifter
    endgenerate

    // Barrel Shifter (fast but large) -----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    genvar i;
    generate
        if (FAST_SHIFT_EN == 1'b1) begin : barrel_shifter
            /* shifter core */
               // input layer: convert left shifts to right shifts by reversing
               assign bs_level[$clog2(XLEN)] = (ctrl_i.ir_funct3[2] == 1'b0) ? // is left shift?
                                                     bit_rev_f(rs1_i) // reverse bit order of input operand
                                                     : rs1_i;
               // shifter array (right-shifts only)
               for (i = $clog2(XLEN)-1; i >= 0; i--) begin : shifter_array
                assign bs_level[i][XLEN-1 : XLEN-(2**i)] = (shamt_i[i] == 1'b1) ? {(2**i){(bs_level[i+1][XLEN-1] & ctrl_i.ir_funct12[10])}} : bs_level[i+1][XLEN-1 : XLEN-(2**i)];
                assign bs_level[i][(XLEN-(2**i))-1 : 0]  = (shamt_i[i] == 1'b1) ?  bs_level[i+1][XLEN-1 : 2**i] : bs_level[i+1][(XLEN-(2**i))-1 : 0];
               end : shifter_array

            /* pipeline register */
            always_ff @( posedge clk_i ) begin : barrel_shifter_buf
                bs_start  <= start_i;
                bs_result <= bs_level[0]; // this register can be moved by the register balancing
            end : barrel_shifter_buf

            /* output layer: output gate and re-convert original left shifts */
            assign res_o = (bs_start == 1'b0) ? '0 :
                           (ctrl_i.ir_funct3[2] == 1'b0) ? bit_rev_f(bs_result)
                           : bs_result;

            /* processing done */
            assign valid_o = start_i;
        end : barrel_shifter
    endgenerate
endmodule