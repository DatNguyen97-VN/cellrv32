// ##################################################################################################
// # << CELLRV32 - CPU Co-Processor: RISC-V Conditional Operations ('Zicond') ISA Extension >>      #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_cpu_cp_cond #(
    parameter XLEN = 32 // data path width
) (
    /* global control */
    input  logic             clk_i,   // global clock, rising edge
    input  ctrl_bus_t        ctrl_i,  // main control bus
    input  logic             start_i, // trigger operation
    /* data input */
    input  logic [XLEN-1:0]  rs1_i,   // rf source 1
    input  logic [XLEN-1:0]  rs2_i,   // rf source 2
    /* result and status */
    output logic [XLEN-1:0]  res_o,   // operation result
    output logic             valid_o  // data output valid
);
    
    const logic[XLEN-1:0] zero_c = '0;
    logic rs2_zero, condition;

    /* Compliance notifier */
    initial begin
        assert (1'b0) else $info("NEORV32 PROCESSOR CONFIG WARNING: The RISC-V 'Zicond' ISA extension is neither ratified nor frozen (yet).");
    end

    /* Conditional output */
    always_ff @( posedge clk_i ) begin : cond_out
        if ((start_i == 1'b1) && (condition == 1'b1)) begin
            res_o <= rs1_i;
        end else begin
            res_o <= zero_c;
        end
    end : cond_out

    /* condition check */
    assign rs2_zero = (rs2_i == zero_c) ? 1'b1 : 1'b0;
    assign condition = rs2_zero ~^ ctrl_i.ir_funct3[1]; // equal zero / non equal zero

    /* processing done */
    assign valid_o = start_i;
    
endmodule