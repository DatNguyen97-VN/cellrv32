// ######################################################################################################
// # << CELLRV32 - NPU Runtime Counter >>                                                               #
// # ************************************************************************************************** #
// # This component includes the counter for runtime measurements.                                      #
// # The counter starts when a new Instruction is feeded to the NPU.                                    #
// # When the NPU signals a synchronization, the counter will stop and hold it's value.                 #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_runtime_counter (
    input  logic        clk_i      ,
    input  logic        rstn_i     ,
    input  logic        inst_en_i  , // Signals that a new Instruction was feeded and starts the counter
    input  logic        sync_i     , // Signals that the calculations are done, stops the counter and holds it's value
    output logic [31:0] count_val_o  // The current value of the counter
);

    logic [31:0] counter_q;
    logic [31:0] pipeline_q;
    logic        running_q;

    // Running state logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            running_q <= 1'b0;
        end else if (!running_q && inst_en_i) begin
            running_q <= 1'b1;
        end else if (running_q && sync_i) begin
            running_q <= 1'b0;
        end
    end

    // Counter
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            counter_q <= 32'd0;
        end else if (!running_q && inst_en_i) begin
            counter_q <= 32'd0;          // reset at start
        end else if (running_q) begin
            counter_q <= counter_q + 1;  // count
        end
    end

    // 1-stage pipeline (giữ nguyên chức năng)
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            pipeline_q <= 32'd0;
        end else begin
            pipeline_q <= counter_q;
        end
    end

    assign count_val_o = pipeline_q;

endmodule