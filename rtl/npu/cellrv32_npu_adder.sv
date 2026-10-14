`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_adder #(
    parameter int WIDTH = 16
) (
    input              clk_i ,
    input              rstn_i,
    // inputs
    input  [WIDTH-1:0] argA_i,
    input  [WIDTH-1:0] argB_i,
    // output
    output [WIDTH-1:0] resValue_o
);
  assign resValue_o = argA_i + argB_i;
endmodule

