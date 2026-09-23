`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_SglReductionSwitch_Datapath (
  input  logic        clk_i         ,
  input  logic        rstn_i        ,
  // inputDataPorts[0] - Left
  input  logic        inputL_en_i,
  output logic        inputL_ready_o,
  input  INT16        inputL_data_i ,
  // inputDataPorts[1] - Right
  input  logic        inputR_en_i,
  output logic        inputR_ready_o,
  input  INT16        inputR_data_i ,
  // outputDataPorts
  input  logic        output_en_i   ,
  output logic        output_ready_o,
  output INT16        output_data_o ,
  // controlPorts
  input  RN_SGRS_Mode mode_val_i
);

  // -------------------------------------------------------------------------
  // control signals
  // -------------------------------------------------------------------------
  RN_SGRS_Mode mode;

  assign mode = mode_val_i;

  // -------------------------------------------------------------------------
  // BypassFifo: fifo_inputL
  // -------------------------------------------------------------------------
  INT16 fifoL_data;
  logic fifoL_valid;
  logic fifoL_enq;
  logic fifoL_deq;
  INT16 fifoL_enq_data;

  assign inputL_ready_o = ~fifoL_valid;
  assign fifoL_enq      = inputL_en_i & inputL_ready_o;
  assign fifoL_enq_data = inputL_data_i;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      fifoL_valid <= 1'b0;
      fifoL_data  <= '0;
    end else begin
      case ({fifoL_enq, fifoL_deq})
        2'b10: begin fifoL_valid <= 1'b1; fifoL_data <= fifoL_enq_data; end
        2'b01: begin fifoL_valid <= 1'b0;                               end
        2'b11: begin fifoL_valid <= 1'b1; fifoL_data <= fifoL_enq_data; end
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // BypassFifo: fifo_inputR
  // -------------------------------------------------------------------------
  INT16 fifoR_data;
  logic fifoR_valid;
  logic fifoR_enq;
  logic fifoR_deq;
  INT16 fifoR_enq_data;

  assign inputR_ready_o = ~fifoR_valid;
  assign fifoR_enq      = inputR_en_i & inputR_ready_o;
  assign fifoR_enq_data = inputR_data_i;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      fifoR_valid <= 1'b0;
      fifoR_data  <= '0;
    end else begin
      case ({fifoR_enq, fifoR_deq})
        2'b10: begin fifoR_valid <= 1'b1; fifoR_data <= fifoR_enq_data; end
        2'b01: begin fifoR_valid <= 1'b0;                               end
        2'b11: begin fifoR_valid <= 1'b1; fifoR_data <= fifoR_enq_data; end
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // BypassFifo: fifo_out
  // -------------------------------------------------------------------------
  INT16 fifoOut_data;
  logic fifoOut_valid;
  logic fifoOut_enq;
  logic fifoOut_deq;
  INT16 fifoOut_enq_data;

  assign output_data_o  = fifoOut_data;
  assign output_ready_o = fifoOut_valid;
  assign fifoOut_deq    = fifoOut_valid & output_en_i;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      fifoOut_valid <= 1'b0;
      fifoOut_data  <= '0;
    end else begin
      case ({fifoOut_enq, fifoOut_deq})
        2'b10: begin fifoOut_valid <= 1'b1; fifoOut_data <= fifoOut_enq_data; end
        2'b01: begin fifoOut_valid <= 1'b0;                                   end
        2'b11: begin fifoOut_valid <= 1'b1; fifoOut_data <= fifoOut_enq_data; end
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // Submodule: 16-bits Adder
  // -------------------------------------------------------------------------
  INT16 adder_res;

  cellrv32_npu_adder #(
    .WIDTH ($bits(INT16))
  ) adder_inst (
    .clk_i      (clk_i     ),
    .rstn_i     (rstn_i    ),
    .argA_i     (fifoL_data),
    .argB_i     (fifoR_data),
    .resValue_o (adder_res )
  );

  // -------------------------------------------------------------------------
  // compute data and read / write fifo[input/output]
  // -------------------------------------------------------------------------
  logic rule_addTwo;
  logic rule_flowLeft;
  logic rule_flowRight;

  assign rule_addTwo    = (mode == rn_sgrs_mode_addTwo) & fifoL_valid & fifoR_valid & ~fifoOut_valid;
  assign rule_flowLeft  = (mode == rn_sgrs_mode_flowLeft) & fifoL_valid & ~fifoOut_valid;
  assign rule_flowRight = (mode == rn_sgrs_mode_flowRight) & fifoR_valid & ~fifoOut_valid;

  // fifoL / fifoR deq 
  assign fifoL_deq = rule_addTwo | rule_flowLeft;
  assign fifoR_deq = rule_addTwo | rule_flowRight;

  // fifoOut enq mux 
  always_comb begin
    fifoOut_enq      = 1'b0;
    fifoOut_enq_data = '0;
    if      (rule_addTwo)    begin fifoOut_enq = 1'b1; fifoOut_enq_data = adder_res;  end
    else if (rule_flowLeft)  begin fifoOut_enq = 1'b1; fifoOut_enq_data = fifoL_data; end
    else if (rule_flowRight) begin fifoOut_enq = 1'b1; fifoOut_enq_data = fifoR_data; end
  end

endmodule