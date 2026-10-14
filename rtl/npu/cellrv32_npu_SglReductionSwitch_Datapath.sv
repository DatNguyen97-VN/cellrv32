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
  // fifo_inputL
  // -------------------------------------------------------------------------
  INT16 fifoL_data;
  logic fifoL_notFull;
  logic fifoL_enq;
  logic fifoL_deq;
  INT16 fifoL_enq_data;
  logic fifoL_valid;

  assign inputL_ready_o = fifoL_notFull;
  assign fifoL_enq      = inputL_en_i & fifoL_notFull;
  assign fifoL_enq_data = inputL_data_i;

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) inputLBuffer_inst (
    .clk_i       (clk_i         ),
    .rstn_i      (rstn_i        ),
    .enq_en_i    (fifoL_enq     ),
    .notFull_o   (fifoL_notFull ),
    .enq_val_i   (fifoL_enq_data),
    .deq_en_i    (fifoL_deq     ),
    .notEmpty_o  (fifoL_valid   ),
    .first_val_o (fifoL_data    )
  );

  // -------------------------------------------------------------------------
  // fifo_inputR
  // -------------------------------------------------------------------------
  INT16 fifoR_data;
  logic fifoR_notFull;
  logic fifoR_enq;
  logic fifoR_deq;
  INT16 fifoR_enq_data;
  logic fifoR_valid;

  assign inputR_ready_o = fifoR_notFull;
  assign fifoR_enq      = inputR_en_i & fifoR_notFull;
  assign fifoR_enq_data = inputR_data_i;

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) inputRBuffer_inst (
    .clk_i       (clk_i         ),
    .rstn_i      (rstn_i        ),
    .enq_en_i    (fifoR_enq     ),
    .notFull_o   (fifoR_notFull ),
    .enq_val_i   (fifoR_enq_data),
    .deq_en_i    (fifoR_deq     ),
    .notEmpty_o  (fifoR_valid   ),
    .first_val_o (fifoR_data    )
  );

  // -------------------------------------------------------------------------
  // fifo_out
  // -------------------------------------------------------------------------
  INT16 fifoOut_data;
  logic fifoOut_notFull;
  logic fifoOut_enq;
  logic fifoOut_deq;
  INT16 fifoOut_enq_data;
  logic fifoOut_valid;

  assign fifoOut_deq    = fifoOut_valid & output_en_i;
  assign output_ready_o = fifoOut_valid;
  assign output_data_o  = fifoOut_data;

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) resultBuffers_inst (
    .clk_i       (clk_i         ),
    .rstn_i      (rstn_i        ),
    .enq_en_i    (fifoOut_enq     ),
    .notFull_o   (fifoOut_notFull ),
    .enq_val_i   (fifoOut_enq_data),
    .deq_en_i    (fifoOut_deq     ),
    .notEmpty_o  (fifoOut_valid   ),
    .first_val_o (fifoOut_data    )
  );

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

  assign rule_addTwo    = (mode == rn_sgrs_mode_addTwo) & fifoL_valid & fifoR_valid & fifoOut_notFull;
  assign rule_flowLeft  = (mode == rn_sgrs_mode_flowLeft) & fifoL_valid & fifoOut_notFull;
  assign rule_flowRight = (mode == rn_sgrs_mode_flowRight) & fifoR_valid & fifoOut_notFull;

  // fifoL / fifoR deq 
  assign fifoL_deq = rule_addTwo | rule_flowLeft;
  assign fifoR_deq = rule_addTwo | rule_flowRight;

  // fifoOut enq mux 
  always_comb begin
    fifoOut_enq      = 1'b0;
    fifoOut_enq_data = '0;
    if      (rule_addTwo)    begin fifoOut_enq = fifoOut_notFull; fifoOut_enq_data = adder_res;  end
    else if (rule_flowLeft)  begin fifoOut_enq = fifoOut_notFull; fifoOut_enq_data = fifoL_data; end
    else if (rule_flowRight) begin fifoOut_enq = fifoOut_notFull; fifoOut_enq_data = fifoR_data; end
  end

endmodule