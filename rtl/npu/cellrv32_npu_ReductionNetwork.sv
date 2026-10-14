`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_ReductionNetwork (
  input  logic                                 clk_i                      ,
  input  logic                                 rstn_i                     ,
  // controlPorts - putConfig
  input  logic                                 putConfig_en_i             ,
  input  RN_Config                             putConfig_val_i            ,
  // inputDataPorts
  input  logic [NumMultSwitches-1:0]           inputDataPorts_put_en_i    ,
  output logic [NumMultSwitches-1:0]           inputDataPorts_put_ready_o ,
  input  logic [NumMultSwitches-1:0][15:0]     inputDataPorts_put_data_i  ,
  // outputDataPorts
  input  logic [CollectionBandwidth-1:0]       outputDataPorts_get_en_i   ,
  output logic [CollectionBandwidth-1:0]       outputDataPorts_get_ready_o,
  output logic [CollectionBandwidth-1:0][15:0] outputDataPorts_get_data_o 
);

  // =========================================================================
  // Internal signals
  // =========================================================================
  // --- DblReductionSwitch ports ---
  // inputDataPorts[sw][prt]
  logic [3:0]       dbl_input_put_en   [RN_NumDblRSes-1:0];
  logic [3:0]       dbl_input_put_ready[RN_NumDblRSes-1:0];
  logic [3:0][15:0] dbl_input_put_data [RN_NumDblRSes-1:0];

  // outputDataPorts[sw][prt]
  logic [1:0]       dbl_output_get_ready[RN_NumDblRSes-1:0];
  logic [1:0]       dbl_output_get_en   [RN_NumDblRSes-1:0];
  logic [1:0][15:0] dbl_output_get_data [RN_NumDblRSes-1:0];

  // resultsDataPorts[sw][prt]
  logic [1:0]       dbl_results_get_en   [RN_NumDblRSes-1:0];
  logic [1:0]       dbl_results_get_ready[RN_NumDblRSes-1:0];
  logic [1:0][15:0] dbl_results_get_data [RN_NumDblRSes-1:0];

  // controlPorts
  logic          dbl_putConfig_en [RN_NumDblRSes-1:0];
  RN_DblRSConfig dbl_putConfig_val[RN_NumDblRSes-1:0];

  // --- SglReductionSwitch ports ---
  // inputDataPorts[sw][prt]
  logic [1:0]       sgl_input_put_en   [RN_NumSglRSes-1:0];
  logic [1:0]       sgl_input_put_ready[RN_NumSglRSes-1:0];
  logic [1:0][15:0] sgl_input_put_data [RN_NumSglRSes-1:0];

  // outputDataPorts[sw]
  logic sgl_output_get_ready[RN_NumSglRSes-1:0];
  logic sgl_output_get_en   [RN_NumSglRSes-1:0];
  INT16 sgl_output_get_data [RN_NumSglRSes-1:0];

  // resultsDataPorts[sw]
  logic sgl_results_get_en   [RN_NumSglRSes-1:0];
  logic sgl_results_get_ready[RN_NumSglRSes-1:0];
  INT16 sgl_results_get_data [RN_NumSglRSes-1:0];

  // controlPorts
  logic          sgl_putConfig_en [RN_NumSglRSes-1:0];
  RN_SglRSConfig sgl_putConfig_val[RN_NumSglRSes-1:0];

  // --- CollectionBus ports ---
  logic [RN_NumCollectionBusInputPorts-1:0]       col_input_put_en   [RN_NumColletionBuses-1:0];
  logic [RN_NumCollectionBusInputPorts-1:0]       col_input_put_ready[RN_NumColletionBuses-1:0];
  logic [RN_NumCollectionBusInputPorts-1:0][15:0] col_input_put_data [RN_NumColletionBuses-1:0];

  logic col_output_get_ready[RN_NumColletionBuses-1:0];
  logic col_output_get_en   [RN_NumColletionBuses-1:0];
  INT16 col_output_get_data [RN_NumColletionBuses-1:0]; 

  // =========================================================================
  // Instantiate DblReductionSwitches
  // =========================================================================
  genvar idx;
  generate
    for (idx = 0; idx < RN_NumDblRSes; idx++) begin : dbl_ReductionSwitches
      cellrv32_npu_DblReductionSwitch dblReductionSwitch_inst (
        .clk_i                       (clk_i                     ),
        .rstn_i                      (rstn_i                    ),
        // config
        .putConfig_en_i              (dbl_putConfig_en[idx]     ),
        .putConfig_val_i             (dbl_putConfig_val[idx]    ),
        // input data
        .inputDataPorts_put_en_i     (dbl_input_put_en[idx]     ),
        .inputDataPorts_put_ready_o  (dbl_input_put_ready[idx]  ),
        .inputDataPorts_put_data_i   (dbl_input_put_data[idx]   ),
        // output data
        .outputDataPorts_get_en_i    (dbl_output_get_en[idx]    ),
        .outputDataPorts_get_ready_o (dbl_output_get_ready[idx] ),
        .outputDataPorts_get_data_o  (dbl_output_get_data[idx]  ),
        // result data
        .resultsDataPorts_get_en_i   (dbl_results_get_en[idx]   ),
        .resultsDataPorts_get_ready_o(dbl_results_get_ready[idx]),
        .resultsDataPorts_get_data_o (dbl_results_get_data[idx] )
      );
    end : dbl_ReductionSwitches
  endgenerate

  // =========================================================================
  // Instantiate SglReductionSwitches
  // =========================================================================
  generate
    for (idx = 0; idx < RN_NumSglRSes; idx++) begin : sgl_ReductionSwitches
      cellrv32_npu_SglReductionSwitch sglReductionSwitch_inst (
        .clk_i                       (clk_i                     ),
        .rstn_i                      (rstn_i                    ),
        // config
        .putConfig_en_i              (sgl_putConfig_en[idx]     ),
        .putConfig_val_i             (sgl_putConfig_val[idx]    ),
        // input data
        .inputDataPorts_put_en_i     (sgl_input_put_en[idx]     ),
        .inputDataPorts_put_ready_o  (sgl_input_put_ready[idx]  ),
        .inputDataPorts_put_data_i   (sgl_input_put_data[idx]   ),
        // output data
        .outputDataPorts_get_en_i    (sgl_output_get_en[idx]    ),
        .outputDataPorts_get_ready_o (sgl_output_get_ready[idx] ),
        .outputDataPorts_get_data_o  (sgl_output_get_data[idx]  ),
        // result data
        .resultsDataPorts_get_en_i   (sgl_results_get_en[idx]   ),
        .resultsDataPorts_get_ready_o(sgl_results_get_ready[idx]),
        .resultsDataPorts_get_data_o (sgl_results_get_data[idx] )
      );
    end : sgl_ReductionSwitches
  endgenerate

  // =========================================================================
  // Instantiate CollectionBuses
  // =========================================================================
  generate
    for (idx = 0; idx < RN_NumColletionBuses; idx++) begin : collectionBuses
      cellrv32_npu_CollectionBus collectionBuse_inst (
        .clk_i                       (clk_i                    ),
        .rstn_i                      (rstn_i                   ),
        // input data
        .inputDataPorts_put_en_i     (col_input_put_en[idx]    ),
        .inputDataPorts_put_ready_o  (col_input_put_ready[idx] ),
        .inputDataPorts_put_data_i   (col_input_put_data[idx]  ),
        // output data
        .outputDataPorts_get_en_i    (col_output_get_en[idx]   ),
        .outputDataPorts_get_ready_o (col_output_get_ready[idx]),
        .outputDataPorts_get_data_o  (col_output_get_data[idx] )
      );
    end : collectionBuses
  endgenerate

  // =========================================================================
  // Interconnect: Double Reduction Switches
  // =========================================================================
  genvar lv;
  genvar ptr;
  generate
    for (lv = 2; lv < RN_NumLevels; lv++) begin : gen_dbl_interconnect
      localparam int lvFirstDblRSID     = 2 ** (lv - 1) - lv; // ID of the FIRST node at level lv
      localparam int nextLvFirstDblRSID = 2 ** lv - lv - 1;   // ID of the FIRST node at level lv+1
      localparam int numDblRSesInLV     = 2 ** (lv - 1) - 1;  // Number of double node at level lv

      // Connect to single reduction switches at edges of the level
      // left for first node
      // right for last node
      assign sgl_input_put_en[2*lv-3][1]          = dbl_output_get_ready[lvFirstDblRSID][0];
      assign dbl_output_get_en[lvFirstDblRSID][0] = sgl_input_put_ready[2*lv-3][1];
      assign sgl_input_put_data[2*lv-3][1]        = dbl_output_get_data[lvFirstDblRSID][0];

      assign sgl_input_put_en[2*lv-2][0]                = dbl_output_get_ready[nextLvFirstDblRSID-1][1];
      assign dbl_output_get_en[nextLvFirstDblRSID-1][1] = sgl_input_put_ready[2*lv-2][0];
      assign sgl_input_put_data[2*lv-2][0]              = dbl_output_get_data[nextLvFirstDblRSID-1][1];

      // except leaf level+1
      if (lv != RN_NumLevels-1) begin : gen_dbl_to_dbl
        for (ptr = 0; ptr < numDblRSesInLV; ptr++) begin 
          localparam int receiverRS_ID    = lvFirstDblRSID + ptr;
          localparam int firstSenderRS_ID = nextLvFirstDblRSID + 2 * ptr;

          // dblRS[firstSenderRS_ID].outputDataPorts[1] -> dblRS[receiverRS_ID].inputDataPorts[0]
          assign dbl_input_put_en[receiverRS_ID][0]     = dbl_output_get_ready[firstSenderRS_ID][1];
          assign dbl_output_get_en[firstSenderRS_ID][1] = dbl_input_put_ready[receiverRS_ID][0];
          assign dbl_input_put_data[receiverRS_ID][0]   = dbl_output_get_data[firstSenderRS_ID][1];

          // dblRS[firstSenderRS_ID+1].outputDataPorts[0] -> dblRS[receiverRS_ID].inputDataPorts[1]
          assign dbl_input_put_en[receiverRS_ID][1]         = dbl_output_get_ready[firstSenderRS_ID + 1][0];
          assign dbl_output_get_en[firstSenderRS_ID + 1][0] = dbl_input_put_ready[receiverRS_ID][1];
          assign dbl_input_put_data[receiverRS_ID][1]       = dbl_output_get_data[firstSenderRS_ID + 1][0];

          // dblRS[firstSenderRS_ID+1].outputDataPorts[1] -> dblRS[receiverRS_ID].inputDataPorts[2]
          assign dbl_input_put_en[receiverRS_ID][2]         = dbl_output_get_ready[firstSenderRS_ID + 1][1];
          assign dbl_output_get_en[firstSenderRS_ID + 1][1] = dbl_input_put_ready[receiverRS_ID][2];
          assign dbl_input_put_data[receiverRS_ID][2]       = dbl_output_get_data[firstSenderRS_ID + 1][1];

          // dblRS[firstSenderRS_ID+2].outputDataPorts[0] -> dblRS[receiverRS_ID].inputDataPorts[3]
          assign dbl_input_put_en[receiverRS_ID][3]         = dbl_output_get_ready[firstSenderRS_ID + 2][0];
          assign dbl_output_get_en[firstSenderRS_ID + 2][0] = dbl_input_put_ready[receiverRS_ID][3];
          assign dbl_input_put_data[receiverRS_ID][3]       = dbl_output_get_data[firstSenderRS_ID+2][0];
        end 
      end : gen_dbl_to_dbl
    end : gen_dbl_interconnect
  endgenerate

  // =========================================================================
  // Interconnect: Single Reduction Switches
  // =========================================================================

  // sglRS[1].outputDataPorts -> sglRS[0].inputDataPorts[0] (left data)
  assign sgl_input_put_en[0][0]   = sgl_output_get_ready[1];
  assign sgl_output_get_en[1]     = sgl_input_put_ready[0][0];
  assign sgl_input_put_data[0][0] = sgl_output_get_data[1];

  // sglRS[2].outputDataPorts -> sglRS[0].inputDataPorts[1] (right data)
  assign sgl_input_put_en[0][1]   = sgl_output_get_ready[2];
  assign sgl_output_get_en[2]     = sgl_input_put_ready[0][1];
  assign sgl_input_put_data[0][1] = sgl_output_get_data[2];

  generate
    for (lv = 1; lv < RN_NumLevels-1; lv++) begin : gen_sgl_interconnect
      localparam int First_edgeSglRS = 2 * lv - 1;
      localparam int next_edgeSglRS  = 2 * lv + 1;

      // sglRS[next_edgeSglRS].outputDataPorts -> sglRS[First_edgeSglRS].inputDataPorts[0]
      assign sgl_input_put_en[First_edgeSglRS][0]   = sgl_output_get_ready[next_edgeSglRS];
      assign sgl_output_get_en[next_edgeSglRS]      = sgl_input_put_ready[First_edgeSglRS][0];
      assign sgl_input_put_data[First_edgeSglRS][0] = sgl_output_get_data[next_edgeSglRS];

      // sglRS[next_edgeSglRS+1].outputDataPorts -> sglRS[First_edgeSglRS+1].inputDataPorts[1]
      assign sgl_input_put_en[First_edgeSglRS + 1][1]   = sgl_output_get_ready[next_edgeSglRS + 1];
      assign sgl_output_get_en[next_edgeSglRS + 1]      = sgl_input_put_ready[First_edgeSglRS + 1][1];
      assign sgl_input_put_data[First_edgeSglRS + 1][1] = sgl_output_get_data[next_edgeSglRS + 1];
    end : gen_sgl_interconnect
  endgenerate

  // =========================================================================
  // Interconnect double reduction switches to collection buses
  // =========================================================================
  generate
    for (ptr = 0; ptr < RN_NumDblRSes; ptr++) begin : gen_dbl_col
      localparam int prtID = 2 * (ptr / RN_NumColletionBuses);
      localparam int busID = ptr % RN_NumColletionBuses;

      // dblRS[sw].resultsDataPorts[0] -> collectionBus[busID].inputDataPorts[prtID]
      assign col_input_put_en[busID][prtID]   = dbl_results_get_ready[ptr][0];
      assign dbl_results_get_en[ptr][0]       = col_input_put_ready[busID][prtID];
      assign col_input_put_data[busID][prtID] = dbl_results_get_data[ptr][0];

      // dblRS[sw].resultsDataPorts[1] -> collectionBus[busID].inputDataPorts[prtID+1]
      assign col_input_put_en[busID][prtID + 1]   = dbl_results_get_ready[ptr][1];
      assign dbl_results_get_en[ptr][1]           = col_input_put_ready[busID][prtID + 1];
      assign col_input_put_data[busID][prtID + 1] = dbl_results_get_data[ptr][1];
    end : gen_dbl_col
  endgenerate

  // =========================================================================
  // Interconnect single reduction switches to collection buses
  // =========================================================================
  generate
    localparam int prtIDBase = 2 * RN_NumDblRSes / RN_NumColletionBuses;
    for (ptr = 0; ptr < RN_NumSglRSes; ptr++) begin : gen_sgl_col
      localparam int prtID = prtIDBase + ptr / RN_NumColletionBuses;
      localparam int busID = ptr % RN_NumColletionBuses;

      // sglRS[sw].resultsDataPorts -> collectionBus[busID].inputDataPorts[prtID]
      assign col_input_put_en[busID][prtID]   = sgl_results_get_ready[ptr];
      assign sgl_results_get_en[ptr]          = col_input_put_ready[busID][prtID];
      assign col_input_put_data[busID][prtID] = sgl_results_get_data[ptr];
    end : gen_sgl_col
  endgenerate

  // =========================================================================
  // inputDataPorts: putData routing
  // =========================================================================
  generate
    for (ptr = 0; ptr < NumMultSwitches; ptr++) begin : gen_input
      if ((ptr == 0) || (ptr == 1)) begin
        // left edge of tree : 0 is left, 1 is right data
        localparam int targSGRS_ID = 2 * (RN_NumLevels - 1) - 1;

        assign sgl_input_put_en[targSGRS_ID][ptr]   = inputDataPorts_put_en_i[ptr];
        assign inputDataPorts_put_ready_o[ptr]      = sgl_input_put_ready[targSGRS_ID][ptr];
        assign sgl_input_put_data[targSGRS_ID][ptr] = inputDataPorts_put_data_i[ptr];
      end else if (ptr == NumMultSwitches-2) begin
        // right edge of tree for left data
        localparam int targSGRS_ID = 2 * (RN_NumLevels - 1);

        assign sgl_input_put_en[targSGRS_ID][0]   = inputDataPorts_put_en_i[ptr];
        assign inputDataPorts_put_ready_o[ptr]    = sgl_input_put_ready[targSGRS_ID][0];
        assign sgl_input_put_data[targSGRS_ID][0] = inputDataPorts_put_data_i[ptr];
      end else if (ptr == NumMultSwitches-1) begin
        // right edge of tree for right data
        localparam int targSGRS_ID = 2 * (RN_NumLevels - 1);

        assign sgl_input_put_en[targSGRS_ID][1]   = inputDataPorts_put_en_i[ptr];
        assign inputDataPorts_put_ready_o[ptr]    = sgl_input_put_ready[targSGRS_ID][1];
        assign sgl_input_put_data[targSGRS_ID][1] = inputDataPorts_put_data_i[ptr];
      end else begin
        // middle-leafs
        localparam int targDBRS_ID_Base = 2 ** (RN_NumLevels - 2) - (RN_NumLevels - 1);
        localparam int targDBRS_ID_Ofs  = (ptr - 2) / 4;
        localparam int targDBRS_PortID  = (ptr - 2) % 4;
        localparam int targDBRS_ID      = targDBRS_ID_Base + targDBRS_ID_Ofs;

        assign dbl_input_put_en[targDBRS_ID][targDBRS_PortID]   = inputDataPorts_put_en_i[ptr];
        assign inputDataPorts_put_ready_o[ptr]                  = dbl_input_put_ready[targDBRS_ID][targDBRS_PortID];
        assign dbl_input_put_data[targDBRS_ID][targDBRS_PortID] = inputDataPorts_put_data_i[ptr];
      end
    end : gen_input
  endgenerate

  // =========================================================================
  // outputDataPorts: getData from collectionBuses
  // =========================================================================
  generate
    for (idx = 0; idx < RN_NumColletionBuses; idx++) begin : gen_output
      assign col_output_get_en[idx]           = outputDataPorts_get_en_i[idx];
      assign outputDataPorts_get_ready_o[idx] = col_output_get_ready[idx];
      assign outputDataPorts_get_data_o[idx]  = col_output_get_data[idx];
    end : gen_output
  endgenerate

  // =========================================================================
  // controlPorts: putConfig
  // =========================================================================
  generate
    for (idx = 0; idx < RN_NumDblRSes; idx++) begin : gen_dbl_putConfig
      assign dbl_putConfig_en[idx]  = putConfig_en_i;
      assign dbl_putConfig_val[idx] = putConfig_val_i.dblRSNetworkConfig[idx];
    end : gen_dbl_putConfig

    for (idx = 0; idx < RN_NumSglRSes; idx++) begin : gen_sgl_putConfig
      assign sgl_putConfig_en[idx]  = putConfig_en_i;
      assign sgl_putConfig_val[idx] = putConfig_val_i.sglRSNetworkConfig[idx];
    end : gen_sgl_putConfig
  endgenerate

endmodule


module tb_cellrv32_npu_ReductionNetwork ();

  localparam int TEST_CYCLES  = 500;
  localparam int NUM_IN       = NumMultSwitches;
  localparam int NUM_OUT      = CollectionBandwidth;

  // -------------------------------------------------------------------------
  // Clock & Reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // DUT ports
  // -------------------------------------------------------------------------
  logic      putConfig_en;
  RN_Config  putConfig_val;

  logic [NUM_IN-1:0]       inputDataPorts_put_en   ;
  logic [NUM_IN-1:0]       inputDataPorts_put_ready;
  logic [NUM_IN-1:0][15:0] inputDataPorts_put_data ;

  logic [NUM_OUT-1:0]       outputDataPorts_get_en   ;
  logic [NUM_OUT-1:0]       outputDataPorts_get_ready;
  logic [NUM_OUT-1:0][15:0] outputDataPorts_get_data ;

  // -------------------------------------------------------------------------
  // DUT instance
  // -------------------------------------------------------------------------
  cellrv32_npu_ReductionNetwork dut (
    .clk_i                       (clk                      ),
    .rstn_i                      (rst_n                    ),
    .putConfig_en_i              (putConfig_en             ),
    .putConfig_val_i             (putConfig_val            ),
    .inputDataPorts_put_en_i     (inputDataPorts_put_en    ),
    .inputDataPorts_put_ready_o  (inputDataPorts_put_ready ),
    .inputDataPorts_put_data_i   (inputDataPorts_put_data  ),
    .outputDataPorts_get_en_i    (outputDataPorts_get_en   ),
    .outputDataPorts_get_ready_o (outputDataPorts_get_ready),
    .outputDataPorts_get_data_o  (outputDataPorts_get_data )
  );

  // -------------------------------------------------------------------------
  // Cycle counter
  // -------------------------------------------------------------------------
  logic [31:0] cycleCount;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cycleCount <= '0;
    else        cycleCount <= cycleCount + 1;
  end

  // -------------------------------------------------------------------------
  // Scoreboards
  // -------------------------------------------------------------------------
  int pass_count;
  int fail_count;
  int send_count [0:NUM_IN-1];
  int recv_count [0:NUM_OUT-1];
  string current_tc;

  initial begin
    pass_count = 0;
    fail_count = 0;
    for (int i = 0; i < NUM_IN;  i++) send_count[i] = 0;
    for (int i = 0; i < NUM_OUT; i++) recv_count[i] = 0;
  end

  // -------------------------------------------------------------------------
  // Finish
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (cycleCount == 32'(TEST_CYCLES)) begin
      $display("==================================");
      $display("Test Summary @ cycle %0d", cycleCount);
      $display("  PASS : %0d", pass_count);
      $display("  FAIL : %0d", fail_count);
      $display("");
      for (int i = 0; i < NUM_IN;  i++)
        $display("  input[%0d]  send=%0d", i, send_count[i]);
      for (int i = 0; i < NUM_OUT; i++)
        $display("  output[%0d] recv=%0d", i, recv_count[i]);
      $display("==================================");
      $finish;
    end
  end

  // =========================================================================
  // Config builder helpers
  // =========================================================================

  // -------------------------------------------------------------------------
  // Create RN_Config with all SGRS and DBRS in idle state.
  // -------------------------------------------------------------------------
  function automatic RN_Config make_idle_config();
    RN_Config cfg;
    for (int i = 0; i < RN_NumSglRSes; i++) begin
      cfg.sglRSNetworkConfig[i].mode      = rn_sgrs_mode_idle;
      cfg.sglRSNetworkConfig[i].genOutput = 1'b0;
    end
    for (int i = 0; i < RN_NumDblRSes; i++) begin
      cfg.dblRSNetworkConfig[i].mode      = {rn_dbrs_submode_idle, rn_dbrs_submode_idle};
      cfg.dblRSNetworkConfig[i].genOutputL = 1'b0;
      cfg.dblRSNetworkConfig[i].genOutputR = 1'b0;
    end
    return cfg;
  endfunction

  // -------------------------------------------------------------------------
  // NumMultSwitches = 16, NumColletionBuses = 4, CollectionBandwidth = 4
  // -------------------------------------------------------------------------
  function automatic RN_Config make_test_config_A();
    RN_Config cfg = make_idle_config();

    // SGRS
    cfg.sglRSNetworkConfig[3].mode      = rn_sgrs_mode_addTwo;
    cfg.sglRSNetworkConfig[3].genOutput = 1'b1;
    cfg.sglRSNetworkConfig[5].mode      = rn_sgrs_mode_flowRight;
    cfg.sglRSNetworkConfig[5].genOutput = 1'b0;

    // DBRS
    cfg.dblRSNetworkConfig[0].mode       = {rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo};
    cfg.dblRSNetworkConfig[0].genOutputL = 1'b1;
    cfg.dblRSNetworkConfig[0].genOutputR = 1'b1;
    cfg.dblRSNetworkConfig[1].mode       = {rn_dbrs_submode_addThree, rn_dbrs_submode_addOne};
    cfg.dblRSNetworkConfig[1].genOutputL = 1'b0;
    cfg.dblRSNetworkConfig[1].genOutputR = 1'b0;
    cfg.dblRSNetworkConfig[2].mode       = {rn_dbrs_submode_addThree, rn_dbrs_submode_addOne};
    cfg.dblRSNetworkConfig[2].genOutputL = 1'b0;
    cfg.dblRSNetworkConfig[2].genOutputR = 1'b0;
    cfg.dblRSNetworkConfig[3].mode       = {rn_dbrs_submode_addThree, rn_sgrs_mode_idle};
    cfg.dblRSNetworkConfig[3].genOutputL = 1'b0;
    cfg.dblRSNetworkConfig[3].genOutputR = 1'b0;

    return cfg;
  endfunction

  // -------------------------------------------------------------------------
  // Config all-addTwo, genOutput all 1 — all switched generate output
  // -------------------------------------------------------------------------
  function automatic RN_Config make_all_output_config();
    RN_Config cfg;
    for (int i = 0; i < RN_NumSglRSes; i++) begin
      cfg.sglRSNetworkConfig[i].mode      = rn_sgrs_mode_addTwo;
      cfg.sglRSNetworkConfig[i].genOutput = 1'b1;
    end
    for (int i = 0; i < RN_NumDblRSes; i++) begin
      cfg.dblRSNetworkConfig[i].mode       = {rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo};
      cfg.dblRSNetworkConfig[i].genOutputL = 1'b1;
      cfg.dblRSNetworkConfig[i].genOutputR = 1'b1;
    end
    return cfg;
  endfunction

  // =========================================================================
  // Helper tasks
  // =========================================================================

  // -------------------------------------------------------------------------
  // do_putConfig
  // -------------------------------------------------------------------------
  task automatic do_putConfig(input RN_Config cfg);
    @(posedge clk);
    putConfig_en  <= 1'b1;
    putConfig_val <= cfg;
    @(posedge clk) #1;
    putConfig_en  <= 1'b0;
    repeat(2) @(posedge clk);
  endtask

  // -------------------------------------------------------------------------
  // do_putData: inject 1 input port
  // -------------------------------------------------------------------------
  task automatic do_putData(
    input int  port,
    input INT16 data
  );
    wait (inputDataPorts_put_ready[port]);
    @(posedge clk);
    inputDataPorts_put_en[port]   = 1'b1;
    inputDataPorts_put_data[port] = data;
    @(posedge clk) #1;
    inputDataPorts_put_en[port] = 1'b0;
    send_count[port]++;
  endtask

  // -------------------------------------------------------------------------
  // do_putDataRange: inject ports [lo..hi] within data = base + offset
  // -------------------------------------------------------------------------
  task automatic do_putDataRange(
    input int  lo,
    input int  hi,
    input INT16 base_val
  );
    for (int p = lo; p <= hi; p++) begin
      wait (inputDataPorts_put_ready[p]);
    end

    @(posedge clk);
    for (int p = lo; p <= hi; p++) begin
      inputDataPorts_put_en[p]   = 1'b1;
      inputDataPorts_put_data[p] = base_val + INT16'(p - lo);
    end

    @(posedge clk) #1;
    for (int p = lo; p <= hi; p++) begin
      inputDataPorts_put_en[p] = 1'b0;
      send_count[p]++;
    end
  endtask

  // -------------------------------------------------------------------------
  // do_putDataAll: inject all NUM_IN ports with data[i]
  // -------------------------------------------------------------------------
  task automatic do_putDataAll(input INT16 data [0:NUM_IN-1]);
    for (int p = 0; p < NUM_IN; p++) begin
      wait (inputDataPorts_put_ready[p]);
    end

    @(posedge clk);
    for (int p = 0; p < NUM_IN; p++) begin
      inputDataPorts_put_en[p]   = 1'b1;
      inputDataPorts_put_data[p] = data[p];
    end

    @(posedge clk) #1;
    for (int p = 0; p < NUM_IN; p++) begin
      inputDataPorts_put_en[p] = 1'b0;
      send_count[p]++;
    end
  endtask

  // -------------------------------------------------------------------------
  // check_output: check 1 output port
  // -------------------------------------------------------------------------
  task automatic check_output(
    input int    out_port,
    input INT16  expected,
    input string test_name
  );
    wait (outputDataPorts_get_ready[out_port]);
    outputDataPorts_get_en[out_port] = 1'b1;
    if (outputDataPorts_get_data[out_port] === expected) begin
      $display("[PASS] %s: out[%0d]=0x%04h (exp 0x%04h) @ cycle %0d",
                test_name, out_port,
                outputDataPorts_get_data[out_port], expected, cycleCount);
      pass_count++;
    end else begin
      $display("[FAIL] %s: out[%0d]=0x%04h (exp 0x%04h) @ cycle %0d",
                test_name, out_port,
                outputDataPorts_get_data[out_port], expected, cycleCount);
      fail_count++;
    end
    @(posedge clk);
    recv_count[out_port]++;
    outputDataPorts_get_en[out_port] = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // drain_output: Receive and count all available outputs within N cycles.  
  // -------------------------------------------------------------------------
  task automatic drain_output(
    input int    num_cycles,
    output int   total_recv
  );
    total_recv = 0;
    for (int p = 0; p < NUM_OUT; p++) begin
      outputDataPorts_get_en[p] = 1'b1;
    end
    repeat(num_cycles) begin
      @(posedge clk);
      for (int p = 0; p < NUM_OUT; p++) begin
        if (outputDataPorts_get_ready[p]) begin
          total_recv++;
          recv_count[p]++;
        end
      end
    end
    for (int p = 0; p < NUM_OUT; p++) begin
      outputDataPorts_get_en[p] = 1'b0;
    end
  endtask

  // -------------------------------------------------------------------------
  // check_no_output: Confirm no output for N cycles.
  // -------------------------------------------------------------------------
  task automatic check_no_output(
    input int    num_cycles,
    input string test_name
  );
    for (int p = 0; p < NUM_OUT; p++) begin
      outputDataPorts_get_en[p] = 1'b0;
    end
    repeat(num_cycles) @(posedge clk);
    begin
      logic any_valid = 1'b0;
      for (int p = 0; p < NUM_OUT; p++) begin
        if (outputDataPorts_get_ready[p]) any_valid = 1'b1;
      end
      if (!any_valid) begin
        $display("[PASS] %s: no output in %0d cycles @ cycle %0d",
                  test_name, num_cycles, cycleCount);
        pass_count++;
      end else begin
        $display("[FAIL] %s: unexpected output @ cycle %0d",
                  test_name, cycleCount);
        fail_count++;
      end
    end
  endtask

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    // Init
    putConfig_en  = 1'b0;
    putConfig_val = '{default: '0};
    for (int i = 0; i < NUM_IN;  i++) begin
      inputDataPorts_put_en[i]   = 1'b0;
      inputDataPorts_put_data[i] = '0;
    end
    for (int i = 0; i < NUM_OUT; i++) begin
      outputDataPorts_get_en[i] = 1'b0;
    end

    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    repeat(3) @(posedge clk);

    // =======================================================================
    // TEST 1: Idle config — no output
    // =======================================================================
    $display("--- TEST 1: idle config, no output ---");
    current_tc = "T1_idle";
    begin
      static RN_Config cfg = make_idle_config();
      do_putConfig(cfg);
      // Inject all ports
      do_putDataRange(0, NUM_IN-1, 16'h0001);
      check_no_output(100, "T1_idle");
    end

    // =======================================================================
    // TEST 2: Test pattern A
    // inject port 1..12 with data = idx
    // receive output at the collection buses
    // =======================================================================
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    repeat(3) @(posedge clk);

    $display("--- TEST 2: Test pattern A (12 inputs, reduce 3) ---");
    current_tc = "T2_pattern";
    begin
      automatic RN_Config cfg = make_test_config_A();
      automatic INT16 data_arr [0:NUM_IN-1]; 
      int got;
      
      do_putConfig(cfg);

      // Inject 16 inputs (port 0..15)
      for (int p = 0; p < NUM_IN; p++) begin
        data_arr[p] = INT16'(p);
      end

      // inject 0..15
      for (int p = 0; p < NUM_IN; p++) begin
        do_putData(p, data_arr[p]);
      end
        
      // receive output 
      drain_output(20, got);
      $display("T2_pattern : received %0d outputs", got);
        
      $display("[INFO] T2: test pattern complete");
      pass_count++;
    end

    repeat(10) @(posedge clk);
    $display("--- All planned tests done @ cycle %0d ---", cycleCount);

  end

endmodule