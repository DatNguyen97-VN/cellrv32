// ######################################################################################################################
// # << CELLRV32 - NPU Macc >>                                                                                          #
// # ****************************************************************************************************************** #
// # Component which does a multiply-add operation with double buffered weights.                                        #
// # This component has two weight registers, which are configured as gated clock registers with seperate enable flags. #
// # The second register is used for multiplication with the input register. The product is added to the LAST_SUM input,#
// # which defines the PARTIAL_SUM output register.                                                                     #
// # ****************************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_macc #(
    parameter int LAST_SUM_WIDTH    = 0,
    parameter int PARTIAL_SUM_WIDTH = 18
)(
    input  logic                         clk_i     ,
    input  logic                         rstn_i    ,
    input  logic                         enable_i  ,
    input  logic [8:0]                   wei_i     , // Input of the first weight register
    input  logic                         pre_wei_i , // First weight register enable or 'preload'
    input  logic                         load_wei_i, // Second weight register enable or 'load'
    input  logic [8:0]                   in_i      , // Input for the multiply-add operation
    input  logic [LAST_SUM_WIDTH-1:0]    last_sum_i, // Input for accumulation
    output logic [PARTIAL_SUM_WIDTH-1:0] part_sum_o  // Output of partial sum register
);

    // Constants
    localparam int MUL_HALFWORD_WIDTH = 18;  // 2 * EXTENDED_BYTE_WIDTH

    // Alternating weight registers
    logic [8:0] preweight_cs, preweight_ns;
    logic [8:0] weight_cs, weight_ns;
    
    // Input register
    logic [8:0] input_cs, input_ns;
    
    // Pipeline register for multiplication result
    logic [MUL_HALFWORD_WIDTH-1:0] pipeline_cs, pipeline_ns;
    
    // Result register
    logic [PARTIAL_SUM_WIDTH-1:0] partial_sum_cs, partial_sum_ns;

    // Combinational logic
    always_comb begin
        input_ns = in_i;
        preweight_ns = wei_i;
        weight_ns = preweight_cs;
        
        // Multiplication
        pipeline_ns = $signed(input_cs) * $signed(weight_cs);
        
        // Addition - only ONE case will get synthesized based on parameters
        if (LAST_SUM_WIDTH > 0 && LAST_SUM_WIDTH < PARTIAL_SUM_WIDTH) begin
            // Sign extend both operands to PARTIAL_SUM_WIDTH
            partial_sum_ns = $signed({pipeline_cs[$bits(pipeline_cs)-1], pipeline_cs}) + $signed({last_sum_i[$bits(last_sum_i)-1], last_sum_i});
        end else if (LAST_SUM_WIDTH > 0 && LAST_SUM_WIDTH == PARTIAL_SUM_WIDTH) begin
            // Same width, direct addition
            partial_sum_ns = $signed(pipeline_cs) + $signed(last_sum_i);
        end else begin
            // LAST_SUM_WIDTH = 0, just pass through multiplication result
            partial_sum_ns = pipeline_cs;
        end
    end
    
    // Output assignment
    assign part_sum_o = partial_sum_cs;

    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            preweight_cs <= '0;
            weight_cs <= '0;
            input_cs <= '0;
            pipeline_cs <= '0;
            partial_sum_cs <= '0;
        end else begin
            if (pre_wei_i) begin
                preweight_cs <= preweight_ns;
            end
            
            if (load_wei_i) begin
                weight_cs <= weight_ns;
            end
            
            if (enable_i) begin
                input_cs <= input_ns;
                pipeline_cs <= pipeline_ns;
                partial_sum_cs <= partial_sum_ns;
            end
        end
    end

endmodule