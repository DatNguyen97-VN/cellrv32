`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_ReductionSwitch_EgressNIC #(
  parameter int LANE = 1
)(
  input  logic                   clk_i               ,
  input  logic                   rstn_i              ,
  /* ----- controlPorts ----- */
  input  logic [LANE-1:0]       genOutput_en_i       ,
  /* ----- dataPorts ----- */
  // putData
  input  logic [LANE-1:0]       dataPorts_put_en_i   ,
  output logic [LANE-1:0]       dataPorts_put_ready_o,
  input  logic [LANE-1:0][15:0] dataPorts_put_data_i ,
  // dataPorts
  input  logic [LANE-1:0]       dataPorts_get_en_i   ,
  output logic [LANE-1:0]       dataPorts_get_ready_o,
  output logic [LANE-1:0][15:0] dataPorts_get_data_o ,
  // resultsDataPorts
  input  logic [LANE-1:0]       results_get_en_i     ,
  output logic [LANE-1:0]       results_get_ready_o  ,
  output logic [LANE-1:0][15:0] results_get_data_o
);

  // -------------------------------------------------------------------------
  // genOutput
  // -------------------------------------------------------------------------
  logic [LANE-1:0] genOutput_en;

  assign genOutput_en = genOutput_en_i;

  // -------------------------------------------------------------------------
  // outputBuffers
  // -------------------------------------------------------------------------
  logic [LANE-1:0]       outBuf_notFull;
  logic [LANE-1:0]       outBuf_notEmpty;
  logic [LANE-1:0][15:0] outBuf_first;
  logic [LANE-1:0]       outBuf_enq;
  logic [LANE-1:0]       outBuf_deq;
  logic [LANE-1:0][15:0] outBuf_enq_data;

  genvar idx;
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_outputBuffers
      PipelineFifo #(
        .T     (INT16),
        .DEPTH (2    )
      ) outputBuffers_inst (
        .clk_i       (clk_i               ),
        .rstn_i      (rstn_i              ),
        .enq_en_i    (outBuf_enq     [idx]),
        .notFull_o   (outBuf_notFull [idx]),
        .enq_val_i   (outBuf_enq_data[idx]),
        .deq_en_i    (outBuf_deq     [idx]),
        .notEmpty_o  (outBuf_notEmpty[idx]),
        .first_val_o (outBuf_first   [idx])
      );
    end : gen_outputBuffers
  endgenerate

  // -------------------------------------------------------------------------
  // resultBuffers
  // -------------------------------------------------------------------------
  logic [LANE-1:0]       resBuf_notFull;
  logic [LANE-1:0]       resBuf_notEmpty;
  logic [LANE-1:0][15:0] resBuf_first;
  logic [LANE-1:0]       resBuf_enq;
  logic [LANE-1:0]       resBuf_deq;
  logic [LANE-1:0][15:0] resBuf_enq_data;

  generate
    for (idx= 0; idx < LANE; idx++) begin : gen_resultBuffers
      PipelineFifo #(
        .T     (INT16),
        .DEPTH (2    )
      )resultBuffers_inst (
        .clk_i       (clk_i               ),
        .rstn_i      (rstn_i              ),
        .enq_en_i    (resBuf_enq     [idx]),
        .notFull_o   (resBuf_notFull [idx]),
        .enq_val_i   (resBuf_enq_data[idx]),
        .deq_en_i    (resBuf_deq     [idx]),
        .notEmpty_o  (resBuf_notEmpty[idx]),
        .first_val_o (resBuf_first   [idx])
      );
    end : gen_resultBuffers
  endgenerate

  // -------------------------------------------------------------------------
  // Write data to output/result buffers
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_putData
      assign dataPorts_put_ready_o[idx] = genOutput_en[idx] ? resBuf_notFull[idx] : outBuf_notFull[idx];
      
      assign resBuf_enq[idx]      = dataPorts_put_en_i[idx] & resBuf_notFull[idx] &  genOutput_en[idx];
      assign resBuf_enq_data[idx] = dataPorts_put_data_i[idx];

      assign outBuf_enq[idx]      = dataPorts_put_en_i[idx] & outBuf_notFull[idx] & ~genOutput_en[idx];
      assign outBuf_enq_data[idx] = dataPorts_put_data_i[idx];
    end : gen_putData
  endgenerate

  // -------------------------------------------------------------------------
  // Read data from output buffers
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_getData
      assign outBuf_deq[idx]            = outBuf_notEmpty[idx] & dataPorts_get_en_i[idx];
      assign dataPorts_get_ready_o[idx] = outBuf_notEmpty[idx];
      assign dataPorts_get_data_o[idx]  = outBuf_first[idx];
    end : gen_getData
  endgenerate

  // -------------------------------------------------------------------------
  // Read data from result buffers
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < LANE; idx++) begin : gen_results
      assign resBuf_deq[idx]          = resBuf_notEmpty[idx] & results_get_en_i[idx];
      assign results_get_ready_o[idx] = resBuf_notEmpty[idx];
      assign results_get_data_o[idx]  = resBuf_first[idx];
    end : gen_results
  endgenerate

endmodule