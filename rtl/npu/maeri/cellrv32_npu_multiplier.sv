//
module cellrv32_npu_multiplier #(
  parameter int WIDTH = 16
  ) (
    input              clk_i     ,
    input              rstn_i    ,
    input  [WIDTH-1:0] argA_i    ,
    input  [WIDTH-1:0] argB_i    ,
    output [WIDTH-1:0] resValue_o
  );
  // remaining internal signals
  logic [4*WIDTH-1:0] extendedRes;
  logic [2*WIDTH-1:0] extendedA, extendedB;

  // internal signals
  assign extendedRes = extendedA * extendedB;
  assign extendedA = {{WIDTH{argA_i[WIDTH-1]}}, argA_i};
  assign extendedB = {{WIDTH{argB_i[WIDTH-1]}}, argB_i};

  // output assignment
  assign resValue_o = {extendedRes[31], extendedRes[26:12]};
endmodule

