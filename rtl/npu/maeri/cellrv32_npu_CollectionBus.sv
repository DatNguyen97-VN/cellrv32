`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_CollectionBus (
  input  logic                                           clk_i                      ,
  input  logic                                           rstn_i                     ,
  // putData
  input  logic [RN_NumCollectionBusInputPorts-1:0]       inputDataPorts_put_en_i    ,
  output logic [RN_NumCollectionBusInputPorts-1:0]       inputDataPorts_put_ready_o ,
  input  logic [RN_NumCollectionBusInputPorts-1:0][15:0] inputDataPorts_put_data_i  ,
  // getData
  input  logic                                           outputDataPorts_get_en_i   ,
  output logic                                           outputDataPorts_get_ready_o,
  output INT16                                           outputDataPorts_get_data_o
);
  // -------------------------------------------------------------------------
  // fifo inputData
  // -------------------------------------------------------------------------
  logic [RN_NumCollectionBusInputPorts-1:0]       notFull;
  logic [RN_NumCollectionBusInputPorts-1:0]       notEmpty;
  logic [RN_NumCollectionBusInputPorts-1:0][15:0] first;
  logic [RN_NumCollectionBusInputPorts-1:0]       enq_en;
  logic [RN_NumCollectionBusInputPorts-1:0]       deq_en;

  genvar idx;
  generate
    for (idx = 0; idx < RN_NumCollectionBusInputPorts; idx++) begin : input_buffer
      PipelineFifo #(
        .T     (INT16                           ),
        .DEPTH (RN_CollectionBusIngressFifoDepth)
      ) inputData_buffer_inst (
        .clk_i       (clk_i                        ),
        .rstn_i      (rstn_i                       ),
        .enq_en_i    (enq_en                   [idx]),
        .notFull_o   (notFull                  [idx]),
        .enq_val_i   (inputDataPorts_put_data_i[idx]),
        .deq_en_i    (deq_en                   [idx]),
        .notEmpty_o  (notEmpty                 [idx]),
        .first_val_o (first                    [idx])
      );
    end : input_buffer
  endgenerate

  assign inputDataPorts_put_ready_o = notFull;
  assign enq_en                     = inputDataPorts_put_en_i & notFull;

  // -------------------------------------------------------------------------
  // Fifo outputData
  // -------------------------------------------------------------------------
  logic outData_notFull;
  logic outData_notEmpty;
  INT16 outData_first;
  logic outData_enq;
  INT16 outData_enq_data;
  logic outData_deq;

  PipelineFifo #(
    .T     (INT16                           ),
    .DEPTH (RN_CollectionBusEngressFifoDepth)
  ) outputData_buffer_inst (
    .clk_i       (clk_i           ),
    .rstn_i      (rstn_i          ),
    .enq_en_i    (outData_enq     ),
    .notFull_o   (outData_notFull ),
    .enq_val_i   (outData_enq_data),
    .deq_en_i    (outData_deq     ),
    .notEmpty_o  (outData_notEmpty),
    .first_val_o (outData_first   )
  );

  assign outputDataPorts_get_ready_o = outData_notEmpty;
  assign outputDataPorts_get_data_o  = outData_first;
  assign outData_deq                 = outData_notEmpty & outputDataPorts_get_en_i;

  // -------------------------------------------------------------------------
  // Generic busArbiter
  // -------------------------------------------------------------------------
  logic [RN_NumCollectionBusInputPorts-1:0] arb_req;
  logic                                     arb_req_en;
  logic [RN_NumCollectionBusInputPorts-1:0] arb_grant;

  // Arbiter Request Bits
  assign arb_req = notEmpty;

  // getArbit_en when has req and outData buffer is not full
  assign arb_req_en = (arb_req != '0) & outData_notFull;

  cellrv32_npu_matrix_arbiter #(
    .NUM_REQ (RN_NumCollectionBusInputPorts)
  ) busArbiter_inst (
    .clk_i             (clk_i     ),
    .rstn_i            (rstn_i    ),
    // getArbit
    .getArbit_en_i     (arb_req_en),
    .getArbit_reqBit_i (arb_req   ),
    .getArbit_val_o    (arb_grant )
  );

  // -------------------------------------------------------------------------
  // fwdData
  // -------------------------------------------------------------------------
  always_comb begin
    outData_enq      = 1'b0;
    outData_enq_data = '0;
    deq_en           = '0;

    for (int idx = 0; idx < RN_NumCollectionBusInputPorts; idx++) begin
      if (arb_grant[idx]) begin
        outData_enq      = 1'b1;
        outData_enq_data = first[idx];
        deq_en[idx]      = 1'b1;
      end
    end
  end

endmodule


module tb_cellrv32_npu_CollectionBus ();

  localparam int TEST_CYCLES   = 50000;
  localparam int NUM_IN_PORTS  = RN_NumCollectionBusInputPorts;

  // -------------------------------------------------------------------------
  // Clock & Reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
  end

  // -------------------------------------------------------------------------
  // DUT ports
  // -------------------------------------------------------------------------
  logic [NUM_IN_PORTS-1:0]       inputDataPorts_put_en;
  logic [NUM_IN_PORTS-1:0]       inputDataPorts_put_ready;
  logic [NUM_IN_PORTS-1:0][15:0] inputDataPorts_put_data;

  logic outputDataPorts_get_en;
  logic outputDataPorts_get_ready;
  INT16 outputDataPorts_get_data;

  // -------------------------------------------------------------------------
  // DUT instance
  // -------------------------------------------------------------------------
  cellrv32_npu_CollectionBus dut (
    .clk_i                       (clk                      ),
    .rstn_i                      (rst_n                    ),
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
  int send_count [0:NUM_IN_PORTS-1];
  int recv_count;
  string current_tc;

  // Expected output queue (simple FIFO model)
  INT16 expected_queue [$];

  initial begin
    pass_count = 0;
    fail_count = 0;
    recv_count = 0;
    for (int i = 0; i < NUM_IN_PORTS; i++) send_count[i] = 0;
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
      $display("  Total recv : %0d", recv_count);
      $display("");
      for (int i = 0; i < NUM_IN_PORTS; i++)
        $display("  port[%0d] send=%0d", i, send_count[i]);
      $display("==================================");
      $finish;
    end
  end

  // =========================================================================
  // Helper tasks
  // =========================================================================

  // -------------------------------------------------------------------------
  // do_putData: inject data to port[prt]
  // -------------------------------------------------------------------------
  task automatic do_putData(
    input int   prt,
    input INT16 data
  );
    @(posedge clk);
    wait (inputDataPorts_put_ready[prt]);
    inputDataPorts_put_en[prt]   <= 1'b1;
    inputDataPorts_put_data[prt] <= data;
    @(posedge clk);
    inputDataPorts_put_en[prt] <= 1'b0;
    send_count[prt]++;
  endtask

  // -------------------------------------------------------------------------
  // do_putDataMulti: Inject into multiple ports simultaneously
  // ports[]: port list
  // data[] : data list
  // -------------------------------------------------------------------------
  task automatic do_putDataMulti(
    input int   ports[],
    input INT16 data []
  );
    @(posedge clk);
    // waiting for input is ready
    foreach (ports[i]) begin
      wait (inputDataPorts_put_ready[ports[i]]);
    end
    foreach (ports[i]) begin
      inputDataPorts_put_en[ports[i]]   <= 1'b1;
      inputDataPorts_put_data[ports[i]] <= data[i];
    end
    @(posedge clk);
    foreach (ports[i]) begin
      inputDataPorts_put_en[ports[i]] <= 1'b0;
      send_count[ports[i]]++;
    end
  endtask

  // -------------------------------------------------------------------------
  // do_getData: get 1 output, compare with expected
  // -------------------------------------------------------------------------
  task automatic do_getData(
    input INT16  expected,
    input string test_name
  );
    @(posedge clk);
    wait (outputDataPorts_get_ready);
    outputDataPorts_get_en <= 1'b1;
    #1;
    if (outputDataPorts_get_data === expected) begin
      $display("[PASS] %s: output=0x%04h (expected 0x%04h) @ cycle %0d",
                test_name, outputDataPorts_get_data, expected, cycleCount);
      pass_count++;
    end else begin
      $display("[FAIL] %s: output=0x%04h (expected 0x%04h) @ cycle %0d",
                test_name, outputDataPorts_get_data, expected, cycleCount);
      fail_count++;
    end
    recv_count++;
    @(posedge clk);
    outputDataPorts_get_en <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // do_getData_nocheck
  // -------------------------------------------------------------------------
  task automatic do_getData_nocheck(output INT16 recv_data);
    wait (outputDataPorts_get_ready);
    outputDataPorts_get_en <= 1'b1;
    #1;
    recv_data = outputDataPorts_get_data;
    recv_count++;
    @(posedge clk);
    outputDataPorts_get_en <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // check_no_output: Confirm no output for N cycles.
  // -------------------------------------------------------------------------
  task automatic check_no_output(
    input int    num_cycles,
    input string test_name
  );
    outputDataPorts_get_en <= 1'b0;
    repeat(num_cycles) @(posedge clk);
    if (!outputDataPorts_get_ready) begin
      $display("[PASS] %s: no output in %0d cycles (correct) @ cycle %0d",
                test_name, num_cycles, cycleCount);
      pass_count++;
    end else begin
      $display("[FAIL] %s: unexpected output=0x%04h @ cycle %0d",
                test_name, outputDataPorts_get_data, cycleCount);
      fail_count++;
    end
  endtask

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    // Init
    inputDataPorts_put_en = '0;
    inputDataPorts_put_data = '0;
    outputDataPorts_get_en = '0;

    wait (rst_n);
    repeat(3) @(posedge clk);

    // =======================================================================
    // TEST 1: No input — No output
    // =======================================================================
    $display("--- TEST 1: no input, expect no output ---");
    current_tc = "Test 1: No in/out";
    check_no_output(5, "T1_no_input");

    // =======================================================================
    // TEST 2: Single port inject — port 0
    // =======================================================================
    $display("--- TEST 2: single port[0] inject ---");
    current_tc = "Test 2: single port[0]";
    fork
      do_putData(0, 16'hAA01);
      do_getData(16'hAA01, "T2_port0");
    join

    // =======================================================================
    // TEST 3: Single port inject — port N/2 (mid)
    // =======================================================================
    $display("--- TEST 3: single port[%0d] inject ---", NUM_IN_PORTS/2);
    current_tc = "Test 3: single port[mid]";
    fork
      do_putData(NUM_IN_PORTS/2, 16'hBB02);
      do_getData(16'hBB02, $sformatf("T3_port%0d", NUM_IN_PORTS/2));
    join

    // =======================================================================
    // TEST 4: Single port inject — port N-1 (last)
    // =======================================================================
    $display("--- TEST 4: single port[%0d] inject (last) ---", NUM_IN_PORTS-1);
    current_tc = "Test 4: single port[last]";
    fork
      do_putData(NUM_IN_PORTS-1, 16'hCC03);
      do_getData(16'hCC03, $sformatf("T4_portLast"));
    join

    // =======================================================================
    // TEST 5: Sequentially inject data into each port and capture the sequential output.
    // Only one port has data at a time -> the arbiter selects that port.
    // =======================================================================
    $display("--- TEST 5: sequential single-port inject all ports ---");
    current_tc = "Test 5: sequential single-port";
    for (int prt = 0; prt < NUM_IN_PORTS; prt++) begin
      automatic INT16 test_data = INT16'(16'h1000 + prt);
      fork
        begin
          do_putData(prt, test_data);
          do_getData(test_data, $sformatf("T5_seq_port%0d", prt));
        end
      join
    end

    repeat(10) @(posedge clk);
    $display("--- All planned tests done ---");

  end

endmodule