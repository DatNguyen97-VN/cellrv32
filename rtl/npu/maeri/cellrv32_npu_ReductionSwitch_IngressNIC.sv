`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_ReductionSwitch_IngressNIC #(
  parameter LANE = 2
)(
  input  logic                  clk_i                ,
  input  logic                  rstn_i               ,
  // putData
  input  logic [LANE-1:0]       dataPorts_put_en_i   ,
  output logic [LANE-1:0]       dataPorts_put_ready_o,
  input  logic [LANE-1:0][15:0] dataPorts_put_data_i ,
  // getData
  output logic [LANE-1:0]       dataPorts_get_ready_o,
  input  logic [LANE-1:0]       dataPorts_get_en_i   ,
  output logic [LANE-1:0][15:0] dataPorts_get_data_o 
);

  // -------------------------------------------------------------------------
  // inputBuffers instance
  // -------------------------------------------------------------------------
  logic [LANE-1:0]       notFull;
  logic [LANE-1:0]       notEmpty;
  logic [LANE-1:0][15:0] first;
  logic [LANE-1:0]       enq_en;
  logic [LANE-1:0]       deq_en;

  genvar idx;
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_inputBuffers
      PipelineFifo #(
        .T     (INT16),
        .DEPTH (2    )
      ) inputBuffers_inst (
        .clk_i       (clk_i                   ),
        .rstn_i      (rstn_i                  ),
        .enq_en_i    (enq_en              [idx]),
        .notFull_o   (notFull             [idx]),
        .enq_val_i   (dataPorts_put_data_i[idx]),
        .deq_en_i    (deq_en              [idx]),
        .notEmpty_o  (notEmpty            [idx]),
        .first_val_o (first               [idx])
      );
    end : gen_inputBuffers
  endgenerate

  // -------------------------------------------------------------------------
  // input/output interface
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_ports
      // putData
      assign enq_en[idx]                = dataPorts_put_en_i[idx] & notFull[idx];
      assign dataPorts_put_ready_o[idx] = notFull[idx];

      // getData
      assign deq_en[idx]                = notEmpty[idx] & dataPorts_get_en_i[idx];
      assign dataPorts_get_ready_o[idx] = notEmpty[idx];
      assign dataPorts_get_data_o[idx]  = first[idx];
    end : gen_ports
  endgenerate

endmodule