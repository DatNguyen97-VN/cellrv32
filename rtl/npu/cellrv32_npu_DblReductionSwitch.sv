`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_DblReductionSwitch (
  input  logic             clk_i                       ,
  input  logic             rstn_i                      ,
  // putConfig
  input  logic             putConfig_en_i              ,
  input  RN_DblRSConfig    putConfig_val_i             ,
  // putData
  input  logic [3:0]       inputDataPorts_put_en_i     ,
  output logic [3:0]       inputDataPorts_put_ready_o  ,
  input  logic [3:0][15:0] inputDataPorts_put_data_i   ,
  // outputDataPorts
  input  logic [1:0]       outputDataPorts_get_en_i    ,
  output logic [1:0]       outputDataPorts_get_ready_o ,
  output logic [1:0][15:0] outputDataPorts_get_data_o  ,
  // resultsDataPorts
  input  logic [1:0]       resultsDataPorts_get_en_i   ,
  output logic [1:0]       resultsDataPorts_get_ready_o,
  output logic [1:0][15:0] resultsDataPorts_get_data_o
);

  // -------------------------------------------------------------------------
  // DblReductionSwitch_Controller
  // -------------------------------------------------------------------------
  RN_DBRS_SubMode leftMode;
  RN_DBRS_SubMode rightMode;
  logic           leftGenOutput;
  logic           rightGenOutput;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      leftMode       <= rn_dbrs_submode_idle;
      rightMode      <= rn_dbrs_submode_idle;
      leftGenOutput  <= 1'b0;
      rightGenOutput <= 1'b0;
    end else if (putConfig_en_i) begin
      leftMode       <= putConfig_val_i.mode[3:2];
      rightMode      <= putConfig_val_i.mode[1:0];
      leftGenOutput  <= putConfig_val_i.genOutputL;
      rightGenOutput <= putConfig_val_i.genOutputR;
    end
  end

  // -------------------------------------------------------------------------
  // DblReductionSwitch_IngressNIC
  // -------------------------------------------------------------------------
  logic [3:0]       ingress_put_en;
  logic [3:0]       ingress_put_ready;
  logic [3:0][15:0] ingress_put_data;

  logic [3:0]       ingress_get_en;
  logic [3:0]       ingress_get_ready;
  logic [3:0][15:0] ingress_get_data;

  cellrv32_npu_ReductionSwitch_IngressNIC #( 
    .LANE(4)
    ) ingressNIC_inst (
    .clk_i                 (clk_i            ),
    .rstn_i                (rstn_i           ),
    .dataPorts_put_en_i    (ingress_put_en   ),
    .dataPorts_put_ready_o (ingress_put_ready),
    .dataPorts_put_data_i  (ingress_put_data ),
    .dataPorts_get_ready_o (ingress_get_en   ),
    .dataPorts_get_en_i    (ingress_get_ready),
    .dataPorts_get_data_o  (ingress_get_data )
  );

  // inputDataPorts --> ingressNIC.putData
  genvar idx;
  generate
    for (idx = 0; idx < 4; idx++) begin : gen_input
      assign ingress_put_en[idx]             = inputDataPorts_put_en_i[idx];
      assign inputDataPorts_put_ready_o[idx] = ingress_put_ready[idx];
      assign ingress_put_data[idx]           = inputDataPorts_put_data_i[idx];
    end : gen_input
  endgenerate

  // -------------------------------------------------------------------------
  // DblReductionSwitch_Datapath
  // -------------------------------------------------------------------------
  logic [3:0]       dp_input_put_en;
  logic [3:0]       dp_input_put_ready;
  logic [3:0][15:0] dp_input_put_data;

  logic [1:0]       dp_output_get_en;
  logic [1:0]       dp_output_get_ready;
  logic [1:0][15:0] dp_output_get_data;

  cellrv32_npu_DblReductionSwitch_Datapath datapath_inst (
    .clk_i              (clk_i              ),
    .rstn_i             (rstn_i             ),
    // inputDataPorts : LL, LR, RL, RR <- ingressNIC.getData
    .input_put_en_i     (dp_input_put_en    ),
    .input_put_ready_o  (dp_input_put_ready ),
    .input_put_data_i   (dp_input_put_data  ),
    // outputDataPorts : L, R -> egressNIC.putData
    .output_get_ready_o (dp_output_get_en   ),
    .output_get_en_i    (dp_output_get_ready),
    .output_get_data_o  (dp_output_get_data ),
    // controlPorts <- controller
    .modeL_val_i        (leftMode           ),
    .modeR_val_i        (rightMode          )
  );

  // ingressNIC.getData <-> datapath.putData
  generate
    for (idx = 0; idx < 4; idx++) begin : gen_ingress_dp
      assign dp_input_put_en[idx]   = ingress_get_en[idx];
      assign ingress_get_ready[idx] = dp_input_put_ready[idx];
      assign dp_input_put_data[idx] = ingress_get_data[idx];
    end : gen_ingress_dp
  endgenerate

  // -------------------------------------------------------------------------
  // DblReductionSwitch_EgressNIC
  // -------------------------------------------------------------------------
  logic [1:0]       egress_put_en;
  logic [1:0]       egress_put_ready;
  logic [1:0][15:0] egress_put_data;

  logic [1:0]       egress_get_ready;
  logic [1:0]       egress_get_en;
  logic [1:0][15:0] egress_get_data;

  logic [1:0]       egress_res_ready;
  logic [1:0]       egress_res_en;
  logic [1:0][15:0] egress_res_data;

  logic [1:0]       genOutput_en;

  cellrv32_npu_ReductionSwitch_EgressNIC #( 
    .LANE(2)
    ) egressNIC_inst (
    .clk_i                 (clk_i           ),
    .rstn_i                (rstn_i          ),
    // controlPorts <- controller
    .genOutput_en_i        (genOutput_en    ),
    // inputDataPorts : R, L
    .dataPorts_put_en_i    (egress_put_en   ),
    .dataPorts_put_ready_o (egress_put_ready),
    .dataPorts_put_data_i  (egress_put_data ),
    // outputDataPorts
    .dataPorts_get_en_i    (egress_get_en   ),
    .dataPorts_get_ready_o (egress_get_ready),
    .dataPorts_get_data_o  (egress_get_data ),
    // resultsDataPorts
    .results_get_en_i      (egress_res_en   ),
    .results_get_ready_o   (egress_res_ready),
    .results_get_data_o    (egress_res_data )
  );

  assign genOutput_en = {rightGenOutput, leftGenOutput};

  // datapath.getData -> egressNIC.putData
  generate
    for (idx = 0; idx < 2; idx++) begin : gen_dp_egress
      assign egress_put_en[idx]       = dp_output_get_en[idx];
      assign dp_output_get_ready[idx] = egress_put_ready[idx];
      assign egress_put_data[idx]     = dp_output_get_data[idx];
    end : gen_dp_egress
  endgenerate

  // -------------------------------------------------------------------------
  // outputDataPorts <- egressNIC.outputDataPorts.getData
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < 2; idx++) begin : gen_output
      assign outputDataPorts_get_ready_o[idx] = egress_get_ready[idx];
      assign egress_get_en[idx]               = outputDataPorts_get_en_i[idx];
      assign outputDataPorts_get_data_o[idx]  = egress_get_data[idx];
    end : gen_output
  endgenerate

  // -------------------------------------------------------------------------
  // resultsDataPorts <- egressNIC.resultsDataPorts.getData
  // -------------------------------------------------------------------------
  generate
    for (idx = 0; idx < 2; idx++) begin : gen_results
      assign resultsDataPorts_get_ready_o[idx] = egress_res_ready[idx];
      assign egress_res_en[idx]                = resultsDataPorts_get_en_i[idx];
      assign resultsDataPorts_get_data_o[idx]  = egress_res_data[idx];
    end : gen_results
  endgenerate

endmodule


module tb_cellrv32_npu_DblReductionSwitch ();

  localparam int TEST_CYCLES = 50000;

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
  // controlPorts
  logic           putConfig_en;
  RN_DblRSConfig  putConfig_val;

  // inputDataPorts: RR, RL, LR, LL
  logic [3:0]       inputDataPorts_put_en   ;
  logic [3:0]       inputDataPorts_put_ready;
  logic [3:0][15:0] inputDataPorts_put_data ;

  // outputDataPorts: R, L
  logic [1:0]       outputDataPorts_get_en   ;
  logic [1:0]       outputDataPorts_get_ready;
  logic [1:0][15:0] outputDataPorts_get_data ;

  // resultsDataPorts: R, L
  logic [1:0]       resultsDataPorts_get_en   ;
  logic [1:0]       resultsDataPorts_get_ready;
  logic [1:0][15:0] resultsDataPorts_get_data ;

  // -------------------------------------------------------------------------
  // DUT instance
  // -------------------------------------------------------------------------
  cellrv32_npu_DblReductionSwitch dut (
    .clk_i                        (clk                       ),
    .rstn_i                       (rst_n                     ),
    .putConfig_en_i               (putConfig_en              ),
    .putConfig_val_i              (putConfig_val             ),
    .inputDataPorts_put_en_i      (inputDataPorts_put_en     ),
    .inputDataPorts_put_ready_o   (inputDataPorts_put_ready  ),
    .inputDataPorts_put_data_i    (inputDataPorts_put_data   ),
    .outputDataPorts_get_en_i     (outputDataPorts_get_en    ),
    .outputDataPorts_get_ready_o  (outputDataPorts_get_ready ),
    .outputDataPorts_get_data_o   (outputDataPorts_get_data  ),
    .resultsDataPorts_get_en_i    (resultsDataPorts_get_en   ),
    .resultsDataPorts_get_ready_o (resultsDataPorts_get_ready),
    .resultsDataPorts_get_data_o  (resultsDataPorts_get_data )
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
  int output_recv_count [0:1];
  int result_recv_count [0:1];
  string current_tc;

  initial begin
    pass_count           = 0;
    fail_count           = 0;
    output_recv_count[0] = 0;
    output_recv_count[1] = 0;
    result_recv_count[0] = 0;
    result_recv_count[1] = 0;
  end

  // -------------------------------------------------------------------------
  // Finish
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (cycleCount == 32'(TEST_CYCLES)) begin
      $display("==================================");
      $display("Test Summary:");
      $display("  PASS            : %0d", pass_count);
      $display("  FAIL            : %0d", fail_count);
      $display("  outputL recv    : %0d", output_recv_count[0]);
      $display("  outputR recv    : %0d", output_recv_count[1]);
      $display("  resultL recv    : %0d", result_recv_count[0]);
      $display("  resultR recv    : %0d", result_recv_count[1]);
      $display("==================================");
      $finish;
    end
  end

  // =========================================================================
  // Helper tasks
  // =========================================================================

  // -------------------------------------------------------------------------
  // putConfig
  // -------------------------------------------------------------------------
  task automatic do_putConfig(
    input RN_DBRS_SubMode modeL,
    input RN_DBRS_SubMode modeR,
    input logic           genOutputL,
    input logic           genOutputR
  );
    @(posedge clk);
    putConfig_en               <= 1'b1;
    putConfig_val.mode         <= {modeL, modeR};
    putConfig_val.genOutputL   <= genOutputL;
    putConfig_val.genOutputR   <= genOutputR;
    @(posedge clk);
    putConfig_en               <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // inject single port (port: 0=LL,1=LR,2=RL,3=RR)
  // -------------------------------------------------------------------------
  task automatic do_putData(
    input int   port,
    input INT16 data
  );
    wait (inputDataPorts_put_ready[port]);
    inputDataPorts_put_en[port]   = 1'b1;
    inputDataPorts_put_data[port] = data;
    @(posedge clk) #1;
    inputDataPorts_put_en[port] = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // inject 4 ports at once (LL, LR, RL, RR)
  // -------------------------------------------------------------------------
  task automatic do_putData4(
    input INT16 dataLL,
    input INT16 dataLR,
    input INT16 dataRL,
    input INT16 dataRR
  );
    wait (&inputDataPorts_put_ready);
    inputDataPorts_put_en[0] <= 1'b1; inputDataPorts_put_data[0] <= dataLL;
    inputDataPorts_put_en[1] <= 1'b1; inputDataPorts_put_data[1] <= dataLR;
    inputDataPorts_put_en[2] <= 1'b1; inputDataPorts_put_data[2] <= dataRL;
    inputDataPorts_put_en[3] <= 1'b1; inputDataPorts_put_data[3] <= dataRR;
    
    @(posedge clk) #1;
    inputDataPorts_put_en[0] <= 1'b0;
    inputDataPorts_put_en[1] <= 1'b0;
    inputDataPorts_put_en[2] <= 1'b0;
    inputDataPorts_put_en[3] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // inject 3 ports: LL, LR, RL (for leftThreeSum)
  // -------------------------------------------------------------------------
  task automatic do_putData_LL_LR_RL(
    input INT16 dataLL,
    input INT16 dataLR,
    input INT16 dataRL
  );
    wait (inputDataPorts_put_ready[0] && inputDataPorts_put_ready[1] &&
          inputDataPorts_put_ready[2]);

    inputDataPorts_put_en[0] <= 1'b1; inputDataPorts_put_data[0] <= dataLL;
    inputDataPorts_put_en[1] <= 1'b1; inputDataPorts_put_data[1] <= dataLR;
    inputDataPorts_put_en[2] <= 1'b1; inputDataPorts_put_data[2] <= dataRL;
    inputDataPorts_put_en[3] <= 1'b0;
    
    @(posedge clk) #1;
    inputDataPorts_put_en[0] <= 1'b0;
    inputDataPorts_put_en[1] <= 1'b0;
    inputDataPorts_put_en[2] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // inject 3 ports: LR, RL, RR (for rightThreeSum)
  // -------------------------------------------------------------------------
  task automatic do_putData_LR_RL_RR(
    input INT16 dataLR,
    input INT16 dataRL,
    input INT16 dataRR
  );
    @(posedge clk);
    inputDataPorts_put_en[0] <= 1'b0;
    inputDataPorts_put_en[1] <= 1'b1;  inputDataPorts_put_data[1] <= dataLR;
    inputDataPorts_put_en[2] <= 1'b1;  inputDataPorts_put_data[2] <= dataRL;
    inputDataPorts_put_en[3] <= 1'b1;  inputDataPorts_put_data[3] <= dataRR;
    wait (inputDataPorts_put_ready[1] && inputDataPorts_put_ready[2] &&
          inputDataPorts_put_ready[3]);
    @(posedge clk);
    inputDataPorts_put_en[1] <= 1'b0;
    inputDataPorts_put_en[2] <= 1'b0;
    inputDataPorts_put_en[3] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // check outputDataPorts[side] (side: 0=L, 1=R)
  // -------------------------------------------------------------------------
  task automatic check_output(
    input int    side,
    input INT16  expected,
    input string test_name
  );
    wait (outputDataPorts_get_ready[side]);
    outputDataPorts_get_en[side] <= 1'b1;
    if (outputDataPorts_get_data[side] === expected) begin
      $display("[PASS] %s: output[%0d] = %0d (expected %0d)",
                test_name, side, outputDataPorts_get_data[side], expected);
      pass_count++;
    end else begin
      $display("[FAIL] %s: output[%0d] = %0d (expected %0d)",
                test_name, side, outputDataPorts_get_data[side], expected);
      fail_count++;
    end
    output_recv_count[side]++;
    @(posedge clk) #1;
    outputDataPorts_get_en[side] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // check resultsDataPorts[side]
  // -------------------------------------------------------------------------
  task automatic check_result(
    input int    side,
    input INT16  expected,
    input string test_name
  );
    wait (resultsDataPorts_get_ready[side]);
    resultsDataPorts_get_en[side] <= 1'b1;
    if (resultsDataPorts_get_data[side] === expected) begin
      $display("[PASS] %s: result[%0d] = %0d (expected %0d)",
                test_name, side, resultsDataPorts_get_data[side], expected);
      pass_count++;
    end else begin
      $display("[FAIL] %s: result[%0d] = %0d (expected %0d)",
                test_name, side, resultsDataPorts_get_data[side], expected);
      fail_count++;
    end
    result_recv_count[side]++;
    @(posedge clk) #1;
    resultsDataPorts_get_en[side] <= 1'b0;
  endtask

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    // initialize inputs
    putConfig_en  = 1'b0;
    putConfig_val = 16'd0;
    inputDataPorts_put_en = '{default: 1'b0};
    inputDataPorts_put_data = '{default: 16'd0};  
    outputDataPorts_get_en = 2'b00;
    resultsDataPorts_get_en = 2'b00;

    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // =======================================================================
    // TEST 1: idle/idle
    // modeL=idle, modeR=idle
    // =======================================================================
    $display("--- TEST 1: modeL=idle, modeR=idle ---");
    current_tc = "TEST 1: mode=idle";
    do_putConfig(rn_dbrs_submode_idle, rn_dbrs_submode_idle, 1'b0, 1'b0);
    repeat(5) @(posedge clk);
    if (~|outputDataPorts_get_ready && ~|resultsDataPorts_get_ready) begin
      $display("[PASS] idle/idle: no output generated");
      pass_count++;
    end else begin
      $display("[FAIL] idle/idle: unexpected output");
      fail_count++;
    end

    // =======================================================================
    // TEST 2: modeL=addTwo, modeR=addTwo, genOutputL=0, genOutputR=0
    // Left : LL + LR -> outputL
    // Right: RL + RR -> outputR
    // =======================================================================
    $display("--- TEST 2: modeL=addTwo, modeR=addTwo, genL=0, genR=0 ---");
    current_tc = "TEST 2: mode=addTwo, genOut=0";
    do_putConfig(rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo, 1'b0, 1'b0);

    fork
      do_putData4(16'd10, 16'd20, 16'd30, 16'd40);
      begin
        check_output(0, 16'd30, "T2_outputL"); // 10+20=30
        check_output(1, 16'd70, "T2_outputR"); // 30+40=70
      end
    join

    // =======================================================================
    // TEST 3: modeL=addTwo, modeR=addTwo, genOutputL=1, genOutputR=1
    // Left : LL + LR -> resultL
    // Right: RL + RR -> resultR
    // =======================================================================
    $display("--- TEST 3: modeL=addTwo, modeR=addTwo, genL=1, genR=1 ---");
    current_tc = "TEST 3: mode=addTwo, genOut=1";
    do_putConfig(rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo, 1'b1, 1'b1);

    fork
      do_putData4(16'd5, 16'd15, 16'd25, 16'd35);
      begin
        check_result(0, 16'd20, "T3_resultL"); // 5+15=20
        check_result(1, 16'd60, "T3_resultR"); // 25+35=60
      end
    join

    // =======================================================================
    // TEST 4: modeL=addTwo, modeR=addTwo, genOutputL=1, genOutputR=0
    // Left : LL + LR -> resultL
    // Right: RL + RR -> outputR
    // =======================================================================
    $display("--- TEST 4: modeL=addTwo, modeR=addTwo, genL=1, genR=0 ---");
    current_tc = "TEST 4: mode=addTwo, genOut=1-0";
    do_putConfig(rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo, 1'b1, 1'b0);

    fork
      do_putData4(16'd100, 16'd200, 16'd50, 16'd50);
      begin
        check_result(0, 16'd300, "T4_resultL"); // 100+200=300
        check_output(1, 16'd100, "T4_outputR"); // 50+50=100
      end
    join

    // =======================================================================
    // TEST 5: modeL=addOne, modeR=addOne, genOutputL=0, genOutputR=0
    // Left : LL -> outputL (pass-through)
    // Right: RR -> outputR (pass-through)
    // =======================================================================
    $display("--- TEST 5: modeL=addOne, modeR=addOne, genL=0, genR=0 ---");
    current_tc = "TEST 5: mode=addOne, genOut=0";
    do_putConfig(rn_dbrs_submode_addOne, rn_dbrs_submode_addOne, 1'b0, 1'b0);

    fork
      begin
        do_putData(0, 16'd77); // LL
        do_putData(3, 16'd88); // RR
      end
      begin
        check_output(0, 16'd77, "T5_outputL");  // pass-through LL
        check_output(1, 16'd88, "T5_outputR");  // pass-through RR
      end
    join

    // =======================================================================
    // TEST 6: modeL=addOne, modeR=addOne, genOutputL=1, genOutputR=1
    // Left : LL -> resultL
    // Right: RR -> resultR
    // =======================================================================
    $display("--- TEST 6: modeL=addOne, modeR=addOne, genL=1, genR=1 ---");
    current_tc = "TEST 6: mode=addOne, genOut=1";
    do_putConfig(rn_dbrs_submode_addOne, rn_dbrs_submode_addOne, 1'b1, 1'b1);

    fork
      begin
        do_putData(0, 16'd42); // LL
        do_putData(3, 16'd84); // RR
      end
      begin
        check_result(0, 16'd42, "T6_resultL");
        check_result(1, 16'd84, "T6_resultR");
      end
    join

    // =======================================================================
    // TEST 7: modeL=addThree, modeR=addOne
    // Left : LL + LR + RL -> outputL (3-input sum)
    // Right: RR -> outputR (pass-through)
    // genL=0, genR=0
    // =======================================================================
    $display("--- TEST 7: modeL=addThree, modeR=addOne, genL=0, genR=0 ---");
    current_tc = "TEST 7: mode=addThree-addOne, genOut=0";
    do_putConfig(rn_dbrs_submode_addThree, rn_dbrs_submode_addOne, 1'b0, 1'b0);

    fork
      begin
        do_putData_LL_LR_RL(16'd10, 16'd20, 16'd30); // LL=10,LR=20,RL=30
        do_putData(3, 16'd99);                        // RR=99
      end
      begin
        check_output(0, 16'd60,  "T7_outputL"); // 10+20+30=60
        check_output(1, 16'd99,  "T7_outputR"); // pass-through RR
      end
    join

    // =======================================================================
    // TEST 8: modeL=addThree, modeR=addOne
    // genL=1, genR=1 -> results
    // =======================================================================
    $display("--- TEST 8: modeL=addThree, modeR=addOne, genL=1, genR=1 ---");
    current_tc = "TEST 8: mode=addThree-addOne, genOut=1";
    do_putConfig(rn_dbrs_submode_addThree, rn_dbrs_submode_addOne, 1'b1, 1'b1);

    fork
      begin
        do_putData_LL_LR_RL(16'd5, 16'd10, 16'd15);
        do_putData(3, 16'd55);
      end
      begin
        check_result(0, 16'd30, "T8_resultL"); // 5+10+15=30
        check_result(1, 16'd55, "T8_resultR"); // pass-through RR
      end
    join

    // =======================================================================
    // TEST 9: modeL=addOne, modeR=addThree
    // Left : LL -> outputL
    // Right: LR + RL + RR -> outputR (3-input sum)
    // genL=0, genR=0
    // =======================================================================
    $display("--- TEST 9: modeL=addOne, modeR=addThree, genL=0, genR=0 ---");
    current_tc = "TEST 9: mode=addOne-addThree, genOut=0";
    do_putConfig(rn_dbrs_submode_addOne, rn_dbrs_submode_addThree, 1'b0, 1'b0);

    fork
      begin
        do_putData(0, 16'd11);                       // LL=11
        do_putData_LR_RL_RR(16'd20, 16'd30, 16'd40); // LR=20,RL=30,RR=40
      end
      begin
        check_output(0, 16'd11, "T9_outputL"); // pass-through LL
        check_output(1, 16'd90, "T9_outputR"); // 20+30+40=90
      end
    join

    // =======================================================================
    // TEST 10: Stress — addTwo/addTwo8 consecutive times
    // =======================================================================
    $display("--- TEST 10: stress addTwo/addTwo x8 ---");
    current_tc = "TEST 10: stress addTwo/addTwo";
    do_putConfig(rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo, 1'b0, 1'b0);

    begin
      static INT16 ll[0:7] = '{16'd1,  16'd2,  16'd3,  16'd4,  16'd5,  16'd6,  16'd7,  16'd8};
      static INT16 lr[0:7] = '{16'd10, 16'd20, 16'd30, 16'd40, 16'd50, 16'd60, 16'd70, 16'd80};
      static INT16 rl[0:7] = '{16'd2,  16'd4,  16'd6,  16'd8,  16'd10, 16'd12, 16'd14, 16'd16};
      static INT16 rr[0:7] = '{16'd20, 16'd40, 16'd60, 16'd80, 16'd100,16'd120,16'd140,16'd160};

      for (int i = 0; i < 8; i++) begin
        fork
          do_putData4(ll[i], lr[i], rl[i], rr[i]);
          begin
            check_output(0, ll[i]+lr[i], $sformatf("stress_L_%0d", i));
            check_output(1, rl[i]+rr[i], $sformatf("stress_R_%0d", i));
          end
        join
      end
    end

    // =======================================================================
    // TEST 11: Config change mid-stream
    // addTwo/addTwo -> addThree/addOne -> addOne/addTwo
    // =======================================================================
    $display("--- TEST 11: config change mid-stream ---");
    current_tc = "TEST 11: config change mid-stream";

    // addTwo/addTwo
    do_putConfig(rn_dbrs_submode_addTwo, rn_dbrs_submode_addTwo, 1'b0, 1'b0);
    fork
      do_putData4(16'd10, 16'd10, 16'd20, 16'd20);
      begin
        check_output(0, 16'd20, "T14.1_L");
        check_output(1, 16'd40, "T14.1_R");
      end
    join

    // addThree/addOne
    do_putConfig(rn_dbrs_submode_addThree, rn_dbrs_submode_addOne, 1'b0, 1'b0);
    fork
      begin
        do_putData_LL_LR_RL(16'd1, 16'd2, 16'd3);
        do_putData(3, 16'd99);
      end
      begin
        check_output(0, 16'd6,  "T14.2_L"); // 1+2+3=6
        check_output(1, 16'd99, "T14.2_R");
      end
    join

    // addOne/addTwo
    do_putConfig(rn_dbrs_submode_addOne, rn_dbrs_submode_addTwo, 1'b0, 1'b0);
    fork
      begin
        do_putData(0, 16'd7);
        do_putData(2, 16'd8);
        do_putData(3, 16'd9);
      end
      begin
        check_output(0, 16'd7,  "T14.3_L");
        check_output(1, 16'd17, "T14.3_R"); // 8+9=17
      end
    join

    // finish
    repeat(10) @(posedge clk);
    $display("--- All planned tests done ---");

  end

endmodule