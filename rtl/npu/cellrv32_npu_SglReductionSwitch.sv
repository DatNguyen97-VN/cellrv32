`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_SglReductionSwitch (
  input  logic             clk_i                       ,
  input  logic             rstn_i                      ,
  // controlPorts
  input  logic             putConfig_en_i              ,
  input  RN_SglRSConfig    putConfig_val_i             ,
  // inputDataPorts[0:1]
  input  logic [1:0]       inputDataPorts_put_en_i     ,
  output logic [1:0]       inputDataPorts_put_ready_o  ,
  input  logic [1:0][15:0] inputDataPorts_put_data_i   ,
  // outputDataPorts
  input  logic             outputDataPorts_get_en_i    ,
  output logic             outputDataPorts_get_ready_o ,
  output INT16             outputDataPorts_get_data_o  ,
  // resultsDataPorts 
  input  logic             resultsDataPorts_get_en_i   ,
  output logic             resultsDataPorts_get_ready_o,
  output INT16             resultsDataPorts_get_data_o
);

  // -------------------------------------------------------------------------
  // SglReductionSwitch_Controller
  // -------------------------------------------------------------------------
  RN_SGRS_Mode ctrl_getMode_val;
  logic        ctrl_getGenOutput_val;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ctrl_getMode_val      <= rn_sgrs_mode_idle;
      ctrl_getGenOutput_val <= 1'b0;
    end else if (putConfig_en_i) begin
      ctrl_getMode_val      <= putConfig_val_i.mode;
      ctrl_getGenOutput_val <= putConfig_val_i.genOutput;
    end
  end

  // -------------------------------------------------------------------------
  // SglReductionSwitch_IngressNIC
  // -------------------------------------------------------------------------
  // ingressNIC.putData  <-- inputDataPorts
  // ingressNIC.getData  --> datapath.inputDataPorts
  logic [1:0]       ingress_put_en;
  logic [1:0]       ingress_put_ready;
  logic [1:0][15:0] ingress_put_data;

  logic [1:0]       ingress_get_ready;
  logic [1:0]       ingress_get_en;
  logic [1:0][15:0] ingress_get_data;

  cellrv32_npu_ReductionSwitch_IngressNIC #(
    .LANE(2)
  ) ingressNIC_inst (
    .clk_i                 (clk_i            ),
    .rstn_i                (rstn_i           ),
    // putData <- inputDataPorts
    .dataPorts_put_en_i    (ingress_put_en   ),
    .dataPorts_put_ready_o (ingress_put_ready),
    .dataPorts_put_data_i  (ingress_put_data ),
    // getData --> datapath.inputDataPorts
    .dataPorts_get_en_i    (ingress_get_en   ),
    .dataPorts_get_ready_o (ingress_get_ready),
    .dataPorts_get_data_o  (ingress_get_data )
  );

  // inputDataPorts --> ingressNIC.putData
  always_comb begin
    for (int prt = 0; prt < 2; prt++) begin
      ingress_put_en            [prt] = inputDataPorts_put_en_i  [prt];
      inputDataPorts_put_ready_o[prt] = ingress_put_ready        [prt];
      ingress_put_data          [prt] = inputDataPorts_put_data_i[prt];
    end
  end

  // -------------------------------------------------------------------------
  // SglReductionSwitch_Datapath
  // -------------------------------------------------------------------------
  // ingressNIC.getData --> datapath.putData --> egressNIC.putData
  logic dp_inputL_en;
  logic dp_inputL_ready;
  INT16 dp_inputL_data;
  logic dp_inputR_en;
  logic dp_inputR_ready;
  INT16 dp_inputR_data;

  logic dp_output_en;
  logic dp_output_ready;
  INT16 dp_output_data;

  cellrv32_npu_SglReductionSwitch_Datapath datapath_inst (
    .clk_i          (clk_i           ),
    .rstn_i         (rstn_i          ),
    // inputData - Left <-- ingressNIC.dataPorts[0].getData
    .inputL_en_i    (dp_inputL_en    ),
    .inputL_ready_o (dp_inputL_ready ),
    .inputL_data_i  (dp_inputL_data  ),
    // inputData - Right <-- ingressNIC.dataPorts[1].getData
    .inputR_en_i    (dp_inputR_en    ),
    .inputR_ready_o (dp_inputR_ready ),
    .inputR_data_i  (dp_inputR_data  ),
    // outputDataPorts --> egressNIC.dataPorts.putData
    .output_en_i    (dp_output_en    ),
    .output_ready_o (dp_output_ready ),
    .output_data_o  (dp_output_data  ),
    // controlPorts <-- controller
    .mode_val_i     (ctrl_getMode_val)
  );

  // ingressNIC.dataPorts[0].getData <-> datapath.inputDataPorts[0].putData
  assign dp_inputL_en      = ingress_get_ready[0];
  assign ingress_get_en[0] = dp_inputL_ready;
  assign dp_inputL_data    = ingress_get_data[0];

  // ingressNIC.dataPorts[1].getData <-> datapath.inputDataPorts[1].putData
  assign dp_inputR_en      = ingress_get_ready[1];
  assign ingress_get_en[1] = dp_inputR_ready;
  assign dp_inputR_data    = ingress_get_data[1];

  // -------------------------------------------------------------------------
  // SglReductionSwitch_EgressNIC
  // -------------------------------------------------------------------------
  logic egress_put_en;
  logic egress_put_ready;
  INT16 egress_put_data;

  logic egress_get_en;
  logic egress_get_ready;
  INT16 egress_get_data;

  logic egress_res_en;
  logic egress_res_ready;
  INT16 egress_res_data;

  cellrv32_npu_ReductionSwitch_EgressNIC #(
    .LANE(1)
  ) egressNIC_inst (
    .clk_i                 (clk_i                ),
    .rstn_i                (rstn_i               ),
    // controlPorts <- controller.getGenOutput
    .genOutput_en_i        (ctrl_getGenOutput_val),
    // dataPorts.putData <- datapath.outputDataPorts
    .dataPorts_put_en_i    (egress_put_en        ),
    .dataPorts_put_ready_o (egress_put_ready     ),
    .dataPorts_put_data_i  (egress_put_data      ),
    // dataPorts.getData --> outputDataPorts
    .dataPorts_get_en_i    (egress_get_en        ),
    .dataPorts_get_ready_o (egress_get_ready     ),
    .dataPorts_get_data_o  (egress_get_data      ),
    // resultsDataPorts --> resultsDataPorts
    .results_get_en_i      (egress_res_en        ),
    .results_get_ready_o   (egress_res_ready     ),
    .results_get_data_o    (egress_res_data      )
  );

  // datapath.outputDataPorts.getData <-> egressNIC.dataPorts.putData
  assign egress_put_en   = dp_output_ready;
  assign dp_output_en    = egress_put_ready;
  assign egress_put_data = dp_output_data;

  // -------------------------------------------------------------------------
  // outputDataPorts  <-- egressNIC.dataPorts.getData
  // -------------------------------------------------------------------------
  assign outputDataPorts_get_ready_o = egress_get_ready;
  assign egress_get_en               = outputDataPorts_get_en_i;
  assign outputDataPorts_get_data_o  = egress_get_data;

  // -------------------------------------------------------------------------
  // resultsDataPorts <-- egressNIC.resultsDataPorts.getData
  // -------------------------------------------------------------------------
  assign resultsDataPorts_get_ready_o = egress_res_ready;
  assign egress_res_en                = resultsDataPorts_get_en_i;
  assign resultsDataPorts_get_data_o  = egress_res_data;

endmodule


module tb_cellrv32_npu_SglReductionSwitch ();

  localparam int TEST_CYCLES = 10000;

  // -------------------------------------------------------------------------
  // Clock & Reset
  // -------------------------------------------------------------------------
  logic clk_i;
  logic rstn_i;

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  initial begin
    rstn_i = 0;
    repeat(2) @(posedge clk_i);
    rstn_i = 1;
  end

  // -------------------------------------------------------------------------
  // DUT ports
  // -------------------------------------------------------------------------
  // controlPorts
  logic          putConfig_en_i;
  RN_SglRSConfig putConfig_val_i;

  // inputDataPorts[0:1]
  logic [1:0]       inputDataPorts_put_en_i   ;
  logic [1:0]       inputDataPorts_put_ready_o;
  logic [1:0][15:0] inputDataPorts_put_data_i ;

  // outputDataPorts
  logic outputDataPorts_get_en_i;
  logic outputDataPorts_get_ready_o;
  INT16 outputDataPorts_get_data_o;

  // resultsDataPorts
  logic resultsDataPorts_get_en_i;
  logic resultsDataPorts_get_ready_o;
  INT16 resultsDataPorts_get_data_o;

  // -------------------------------------------------------------------------
  // DUT instance
  // -------------------------------------------------------------------------
  cellrv32_npu_SglReductionSwitch dut (
    .clk_i                        (clk_i                       ),
    .rstn_i                       (rstn_i                      ),
    // config
    .putConfig_en_i               (putConfig_en_i              ),
    .putConfig_val_i              (putConfig_val_i             ),
    // input
    .inputDataPorts_put_en_i      (inputDataPorts_put_en_i     ),
    .inputDataPorts_put_ready_o   (inputDataPorts_put_ready_o  ),
    .inputDataPorts_put_data_i    (inputDataPorts_put_data_i   ),
    // output
    .outputDataPorts_get_en_i     (outputDataPorts_get_en_i    ),
    .outputDataPorts_get_ready_o  (outputDataPorts_get_ready_o ),
    .outputDataPorts_get_data_o   (outputDataPorts_get_data_o  ),
    // result
    .resultsDataPorts_get_en_i    (resultsDataPorts_get_en_i   ),
    .resultsDataPorts_get_ready_o (resultsDataPorts_get_ready_o),
    .resultsDataPorts_get_data_o  (resultsDataPorts_get_data_o )
  );

  // -------------------------------------------------------------------------
  // Cycle counter
  // -------------------------------------------------------------------------
  logic [31:0] cycleCount;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) cycleCount <= '0;
    else        cycleCount <= cycleCount + 1;
  end

  // -------------------------------------------------------------------------
  // Scoreboards
  // -------------------------------------------------------------------------
  int pass_count;
  int fail_count;
  int output_recv_count;
  int result_recv_count;
  string current_test_name;

  initial begin
    pass_count        = 0;
    fail_count        = 0;
    output_recv_count = 0;
    result_recv_count = 0;
  end

  // -------------------------------------------------------------------------
  // Finish
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (cycleCount == 32'(TEST_CYCLES)) begin
      $display("==================================");
      $display("Test Summary:");
      $display("  PASS : %0d", pass_count);
      $display("  FAIL : %0d", fail_count);
      $display("  output_recv  : %0d", output_recv_count);
      $display("  result_recv  : %0d", result_recv_count);
      $display("==================================");
      $finish;
    end
  end

  // -------------------------------------------------------------------------
  // Helper task: putConfig
  // -------------------------------------------------------------------------
  task automatic do_putConfig(
    input RN_SGRS_Mode mode,
    input logic        genOutput
  );
    @(posedge clk_i);
    putConfig_en_i            = 1'b1;
    putConfig_val_i.mode      = mode;
    putConfig_val_i.genOutput = genOutput;
    @(posedge clk_i);
    #1;
    putConfig_en_i            = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Helper task: inject data to one port
  // -------------------------------------------------------------------------
  task automatic do_putData(
    input int  port,
    input INT16 data
  );
    @(posedge clk_i);
    inputDataPorts_put_en_i[port] = 1'b1;
    inputDataPorts_put_data_i[port] = data;
    // wait until ready
    wait (inputDataPorts_put_ready_o[port]);
    @(posedge clk_i);
    #1;
    inputDataPorts_put_en_i[port] = 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Helper task: inject both ports simultaneously
  // -------------------------------------------------------------------------
  task automatic do_putDataBoth(
    input INT16 dataL,
    input INT16 dataR
  );
    @(posedge clk_i);
    inputDataPorts_put_en_i[0]   <= 1'b1;
    inputDataPorts_put_data_i[0] <= dataL;
    inputDataPorts_put_en_i[1]   <= 1'b1;
    inputDataPorts_put_data_i[1] <= dataR;
    wait (inputDataPorts_put_ready_o[0] && inputDataPorts_put_ready_o[1]);
    @(posedge clk_i);
    #1;
    inputDataPorts_put_en_i[0] <= 1'b0;
    inputDataPorts_put_en_i[1] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Helper task: check output port
  // -------------------------------------------------------------------------
  task automatic check_output(
    input INT16  expected,
    input string test_name
  );
    wait (outputDataPorts_get_ready_o);
    outputDataPorts_get_en_i <= 1'b1;
    if (outputDataPorts_get_data_o === expected) begin
      $display("[PASS] %s: output = %0d (expected %0d)", 
                test_name, outputDataPorts_get_data_o, expected);
      pass_count++;
    end else begin
      $display("[FAIL] %s: output = %0d (expected %0d)",
                test_name, outputDataPorts_get_data_o, expected);
      fail_count++;
    end
    output_recv_count++;
    @(posedge clk_i) #1;
    outputDataPorts_get_en_i <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Helper task: check result port
  // -------------------------------------------------------------------------
  task automatic check_result(
    input INT16  expected,
    input string test_name
  );
    resultsDataPorts_get_en_i <= 1'b1;
    wait (resultsDataPorts_get_ready_o);
    if (resultsDataPorts_get_data_o === expected) begin
      $display("[PASS] %s: result = %0d (expected %0d)",
                test_name, resultsDataPorts_get_data_o, expected);
      pass_count++;
    end else begin
      $display("[FAIL] %s: result = %0d (expected %0d)",
                test_name, resultsDataPorts_get_data_o, expected);
      fail_count++;
    end
    result_recv_count++;
    @(posedge clk_i) #1;
    resultsDataPorts_get_en_i <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------------------
  initial begin
    // initialize all input signals
    putConfig_en_i               = 1'b0;
    putConfig_val_i              = '0;
    inputDataPorts_put_en_i[0]   = 1'b0;
    inputDataPorts_put_en_i[1]   = 1'b0;
    inputDataPorts_put_data_i[0] = '0;
    inputDataPorts_put_data_i[1] = '0;
    outputDataPorts_get_en_i     = 1'b0;
    resultsDataPorts_get_en_i    = 1'b0;

    // Wait reset
    wait (rstn_i);
    repeat(2) @(posedge clk_i);

    // =======================================================================
    // TEST 1: mode = idle
    // =======================================================================
    $display("--- TEST 1: mode=idle ---");
    current_test_name = "TC1: idle";
    do_putConfig(rn_sgrs_mode_idle, 1'b0);
    repeat(3) @(posedge clk_i);
    // check output valid
    if (!outputDataPorts_get_ready_o && !resultsDataPorts_get_ready_o) begin
      $display("[PASS] idle mode: no output generated");
      pass_count++;
    end else begin
      $display("[FAIL] idle mode: unexpected output");
      fail_count++;
    end

    // =======================================================================
    // TEST 2: mode = addTwo, genOutput = 0 (output to outputDataPorts)
    // addTwo: L + R -> outputDataPorts
    // =======================================================================
    $display("--- TEST 2: mode=addTwo, genOutput=0 ---");
    current_test_name = "TC2: addTwo, genOutput=0";
    do_putConfig(rn_sgrs_mode_addTwo, 1'b0);

    fork
      do_putDataBoth(16'd10, 16'd20);
      check_output(16'd30, "addTwo_noGen");
    join

    // =======================================================================
    // TEST 3: mode = addTwo, genOutput = 1 (output to resultsDataPorts)
    // =======================================================================
    $display("--- TEST 3: mode=addTwo, genOutput=1 ---");
    current_test_name = "TC3: addTwo, genOutput=1";
    do_putConfig(rn_sgrs_mode_addTwo, 1'b1);

    fork
      do_putDataBoth(16'd15, 16'd25);
      check_result(16'd40, "addTwo_genOutput");
    join

    // =======================================================================
    // TEST 4: mode = flowLeft, genOutput = 0
    // flowLeft: inputL, pass through -> outputDataPorts
    // =======================================================================
    $display("--- TEST 4: mode=flowLeft, genOutput=0 ---");
    current_test_name = "TC4: flowLeft, genOutput=0";
    do_putConfig(rn_sgrs_mode_flowLeft, 1'b0);

    fork
      do_putData(0, 16'd77);
      check_output(16'd77, "flowLeft_noGen");
    join

    // =======================================================================
    // TEST 5: mode = flowLeft, genOutput = 1
    // flowLeft: inputL -> resultsDataPorts
    // =======================================================================
    $display("--- TEST 5: mode=flowLeft, genOutput=1 ---");
    current_test_name = "TC5: flowLeft, genOutput=1";
    do_putConfig(rn_sgrs_mode_flowLeft, 1'b1);

    fork
      do_putData(0, 16'd55);
      check_result(16'd55, "flowLeft_genOutput");
    join

    // =======================================================================
    // TEST 6: mode = flowRight, genOutput = 0
    // flowRight: inputR, pass through -> outputDataPorts
    // =======================================================================
    $display("--- TEST 6: mode=flowRight, genOutput=0 ---");
    current_test_name = "TC6: flowRight, genOutput=0";
    do_putConfig(rn_sgrs_mode_flowRight, 1'b0);

    fork
      do_putData(1, 16'd99);
      check_output(16'd99, "flowRight_noGen");
    join

    // =======================================================================
    // TEST 7: mode = flowRight, genOutput = 1
    // flowRight: inputR -> resultsDataPorts
    // =======================================================================
    $display("--- TEST 7: mode=flowRight, genOutput=1 ---");
    current_test_name = "TC7: flowRight, genOutput=1";
    do_putConfig(rn_sgrs_mode_flowRight, 1'b1);

    fork
      do_putData(1, 16'd123);
      check_result(16'd123, "flowRight_genOutput");
    join

    // =======================================================================
    // TEST 8: Stress test - addTwo
    // Given N pairs of consecutive data points, check the sum of each pair.
    // =======================================================================
    $display("--- TEST 8: stress addTwo x8 ---");
    current_test_name = "TC8: addTwo, stress test";
    do_putConfig(rn_sgrs_mode_addTwo, 1'b0);

    begin
      static INT16 testL [0:7] = '{16'd1,  16'd2,  16'd3,  16'd4,
                           16'd5,  16'd6,  16'd7,  16'd8};
      static INT16 testR [0:7] = '{16'd10, 16'd20, 16'd30, 16'd40,
                           16'd50, 16'd60, 16'd70, 16'd80};

      for (int i = 0; i < 8; i++) begin
        fork
          do_putDataBoth(testL[i], testR[i]);
          check_output(testL[i] + testR[i], $sformatf("stress_addTwo_%0d", i));
        join
      end
    end

    // =======================================================================
    // TEST 9: Config change mid-stream
    // addTwo -> flowLeft -> addTwo
    // =======================================================================
    $display("--- TEST 9: config change mid-stream ---");
    current_test_name = "TC9: config change mid-stream";

    do_putConfig(rn_sgrs_mode_addTwo, 1'b0);
    fork
      do_putDataBoth(16'd100, 16'd200);
      check_output(16'd300, "mid_addTwo");
    join

    do_putConfig(rn_sgrs_mode_flowLeft, 1'b0);
    fork
      do_putData(0, 16'd42);
      check_output(16'd42, "mid_flowLeft");
    join

    do_putConfig(rn_sgrs_mode_addTwo, 1'b0);
    fork
      do_putDataBoth(16'd50, 16'd50);
      check_output(16'd100, "mid_addTwo_again");
    join

    // =======================================================================
    // TEST 10: backpressure - getoutput is not enabled, 
    // DUT should hold data until getoutput is asserted
    // =======================================================================
    $display("--- TEST 10: backpressure on outputDataPorts ---");
    current_test_name = "TC10: backpressure on outputDataPorts";
    do_putConfig(rn_sgrs_mode_addTwo, 1'b0);
    outputDataPorts_get_en_i <= 1'b0;

    fork
      do_putDataBoth(16'd11, 16'd22);
      begin
        // wait for a few cycles
        repeat(500) @(posedge clk_i);
        // check data is still available 
        if (outputDataPorts_get_ready_o) begin
          $display("[PASS] backpressure: output held valid during backpressure");
          pass_count++;
        end else begin
          $display("[FAIL] backpressure: output not valid");
          fail_count++;
        end
        check_output(16'd33, "backpressure_addTwo");
      end
    join

  end

endmodule