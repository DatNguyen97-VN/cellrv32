// ##################################################################################################
// # << CELLRV32 - Vector Register Remmaping >>                                                     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vrat #(
    parameter int TOTAL_ENTRIES = 32,
    parameter int DATA_WIDTH    = 5
) (
    input  logic                             clk_i      ,
    input  logic                             rstn_i     ,
    input  logic                             reconfigure,
    //Write Port
    input  logic [$clog2(TOTAL_ENTRIES)-1:0] write_addr ,
    input  logic [           DATA_WIDTH-1:0] write_data ,
    input  logic                             write_en   ,
    //Read Port #1
    input  logic [$clog2(TOTAL_ENTRIES)-1:0] read_addr_1,
    output logic [           DATA_WIDTH-1:0] read_data_1,
    output logic                             remapped_1 ,
    //Read Port #2
    input  logic [$clog2(TOTAL_ENTRIES)-1:0] read_addr_2,
    output logic [           DATA_WIDTH-1:0] read_data_2,
    //Read Port #3
    input  logic [$clog2(TOTAL_ENTRIES)-1:0] read_addr_3,
    output logic [           DATA_WIDTH-1:0] read_data_3
);
    localparam ADDR_WIDTH = $clog2(TOTAL_ENTRIES);

    logic [TOTAL_ENTRIES-1:0][DATA_WIDTH-1 : 0] ratMem;
    logic [TOTAL_ENTRIES-1:0] remapped;

    //RAT memory storage
    always_ff @(posedge clk_i or negedge rstn_i) begin : mem
        if(!rstn_i) begin
            for (int i = 0; i < TOTAL_ENTRIES; i++) begin
                ratMem[i] <= i;
            end
        end else begin
            if (reconfigure) begin
                ratMem <= '0;
            end else if(write_en) begin
                ratMem[write_addr] <= write_data;
            end
        end
    end

    //Register Status Storage (remapped y/n)
    always_ff @(posedge clk_i or negedge rstn_i) begin : remap
        if(!rstn_i) begin
            remapped <= '1;
        end else begin
            if (reconfigure) begin
                remapped <= '0;
            end else if(write_en) begin
                remapped[write_addr] <= 1'b1;
            end
        end
    end
    
    //Push Data Out
    assign read_data_1 = ratMem[read_addr_1];
    assign remapped_1  = remapped[read_addr_1];
    assign read_data_2 = ratMem[read_addr_2];
    assign read_data_3 = ratMem[read_addr_3];

endmodule