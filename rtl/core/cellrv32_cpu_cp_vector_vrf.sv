// ##################################################################################################
// # << CELLRV32 - Vector Register File >>                                                          #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS 
 
module vrf #(
    parameter int VREGS      = 32,
    parameter int ELEMENTS   = 4 ,
    parameter int DATA_WIDTH = 32
) (
    input  logic                                           clk_i     ,
    input  logic                                           reset     ,
    //Element Read Ports
    input  logic [      $clog2(VREGS)-1:0]                 rd_addr_1 ,
    output logic [           ELEMENTS-1:0][DATA_WIDTH-1:0] data_out_1,
    input  logic [      $clog2(VREGS)-1:0]                 rd_addr_2 ,
    output logic [           ELEMENTS-1:0][DATA_WIDTH-1:0] data_out_2,
    //Element Write Ports
    input  logic [           ELEMENTS-1:0]                 el_wr_en  ,
    input  logic [      $clog2(VREGS)-1:0]                 el_wr_addr,
    input  logic [           ELEMENTS-1:0][DATA_WIDTH-1:0] el_wr_data,
    //Register Write Port
    input  logic [           ELEMENTS-1:0]                 v_wr_en   ,
    input  logic [      $clog2(VREGS)-1:0]                 v_wr_addr ,
    input  logic [ELEMENTS*DATA_WIDTH-1:0]                 v_wr_data
);

    // Internal Signals
    logic [ELEMENTS*DATA_WIDTH-1:0] memory [VREGS-1:0];
    logic [$clog2(VREGS)-1:0]       wr_addr;

    // Store new Data
    always_ff @(posedge clk_i) begin : memManage
        for (int k = 0; k < ELEMENTS; k++) begin
            if (v_wr_en[k] || el_wr_en[k]) begin
                memory[wr_addr][k*DATA_WIDTH +: DATA_WIDTH] <= v_wr_en[k] ? v_wr_data[k*DATA_WIDTH +: DATA_WIDTH] : el_wr_data[k];
            end
        end
    end : memManage

    // Pick the address to write data
    assign wr_addr = |v_wr_en ? v_wr_addr : el_wr_addr;

    // Pick the Data and push them to the Output
    assign data_out_1 = memory[rd_addr_1];
    assign data_out_2 = memory[rd_addr_2];

endmodule