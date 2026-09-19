`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_multiplier_network (
  input  logic                             clk_i          ,
  input  logic                             rstn_i         ,
  // putData
  input  logic [NumMultSwitches-1:0]       putData_en_i   ,
  output logic [NumMultSwitches-1:0]       putData_rdy_o  ,
  input  logic [NumMultSwitches-1:0][15:0] putData_val_i  ,
  // getData
  input  logic [NumMultSwitches-1:0]       getData_en_i   ,
  output logic [NumMultSwitches-1:0]       getData_rdy_o  ,
  output logic [NumMultSwitches-1:0][15:0] getData_val_o  ,
  // putConfig
  input  logic                             putConfig_en_i ,
  output logic                             putConfig_rdy_o,
  input  MN_Config                         putConfig_val_i,
  input  logic [31:0]                      putConfig_numActualActiveMultSwitches_i
);

  // =========================================================================
  // Vector#(NumMultSwitches, MultiplierSwitch)
  // =========================================================================
  // putIptData 
  logic [NumMultSwitches-1:0]       sw_putIpt_en; 
  logic [NumMultSwitches-1:0]       sw_putIpt_rdy; 
  logic [NumMultSwitches-1:0][15:0] sw_putIpt_val; 
  // getFwdData 
  logic [NumMultSwitches-1:0]       sw_getFwd_rdy;
  logic [NumMultSwitches-1:0][15:0] sw_getFwd_val; 
  // putFwdData 
  logic [NumMultSwitches-1:0]       sw_putFwd_en;
  logic [NumMultSwitches-1:0]       sw_putFwd_rdy;
  logic [NumMultSwitches-1:0][15:0] sw_putFwd_val;  
  // getPSum 
  logic [NumMultSwitches-1:0]       sw_getPSum_en; 
  logic [NumMultSwitches-1:0]       sw_getPSum_rdy;
  logic [NumMultSwitches-1:0][15:0] sw_getPSum_val; 
  // putNewConfig 
  logic [NumMultSwitches-1:0]       sw_putConfig_en;
  logic [NumMultSwitches-1:0]       sw_putConfig_rdy; 
  MN_Config                         sw_putConfig_val;   

  // =========================================================================
  // Instantiate NumMultSwitches x MultiplierSwitch
  // =========================================================================
  genvar sw;
  generate
    for (sw = 0; sw < NumMultSwitches; sw++) begin : gen_multSwitches
      cellrv32_npu_multiplierswitch MultSW_inst (
        .clk_i              (clk_i               ),
        .rstn_i             (rstn_i              ),
        // dataPorts.putIptData
        .putIptData_en_i    (sw_putIpt_en[sw]    ),
        .putIptData_rdy_o   (sw_putIpt_rdy[sw]   ),
        .putIptData_val_i   (sw_putIpt_val[sw]   ),
        // dataPorts.putFwdData
        .putFwdData_en_i    (sw_putFwd_en[sw]    ),
        .putFwdData_rdy_o   (sw_putFwd_rdy[sw]   ),
        .putFwdData_val_i   (sw_putFwd_val[sw]   ),
        // dataPorts.getFwdData
        .getFwdData_rdy_o   (sw_getFwd_rdy[sw]   ),
        .getFwdData_val_o   (sw_getFwd_val[sw]   ),
        // dataPorts.getPSum
        .getPSum_rdy_o      (sw_getPSum_rdy[sw]  ),
        .getPSum_en_i       (sw_getPSum_en[sw]   ),
        .getPSum_val_o      (sw_getPSum_val[sw]  ),
        // controlPorts.putNewConfig
        .putNewConfig_en_i  (sw_putConfig_en[sw] ),
        .putNewConfig_rdy_o (sw_putConfig_rdy[sw]),
        .putNewConfig_val_i (sw_putConfig_val[sw])
      );
    end : gen_multSwitches
  endgenerate

  // =========================================================================
  // Forward links
  // =========================================================================
  generate
    for (sw = 0; sw < NumMultSwitches-1; sw++) begin : gen_fwd_link
      // getFwdData[sw] -> putFwdData[sw+1]
      assign sw_putFwd_en[sw+1]  = sw_getFwd_rdy[sw] & sw_putFwd_rdy[sw+1];
      assign sw_putFwd_val[sw+1] = sw_getFwd_val[sw];
    end : gen_fwd_link
  endgenerate

  // First switch: no forward producer
  assign sw_putFwd_en[0]  = 1'b0;
  assign sw_putFwd_val[0] = '0;

  // =========================================================================
  // multSwitches.putIptData
  // =========================================================================
  generate
    for (sw = 0; sw < NumMultSwitches; sw++) begin : gen_putData
      assign sw_putIpt_en[sw]  = putData_en_i[sw];
      assign putData_rdy_o[sw] = sw_putIpt_rdy[sw];
      assign sw_putIpt_val[sw] = putData_val_i[sw];
    end : gen_putData
  endgenerate

  // =========================================================================
  // multSwitches.getPSum
  // =========================================================================
  generate
    for (sw = 0; sw < NumMultSwitches; sw++) begin : gen_getData
      assign sw_getPSum_en[sw] = getData_en_i[sw];
      assign getData_rdy_o[sw] = sw_getPSum_rdy[sw];
      assign getData_val_o[sw] = sw_getPSum_val[sw];
    end : gen_getData
  endgenerate

  // =========================================================================
  // putConfig
  // =========================================================================
  always_comb begin : gen_putConfig
    // default:
    putConfig_rdy_o = 1'b1;

    for (int idx = 0; idx < NumMultSwitches; idx++) begin
      if (idx < putConfig_numActualActiveMultSwitches_i) begin
        sw_putConfig_en[idx]  = putConfig_en_i;
        putConfig_rdy_o      &= sw_putConfig_rdy[idx]; // ready if all active switches are ready
        sw_putConfig_val[idx] = putConfig_val_i[idx];
      end else begin
        sw_putConfig_en[idx]  = 1'b0;
        putConfig_rdy_o      &= 1'b1; // unactive switch does not block
        sw_putConfig_val[idx] = '0;
      end
    end
  end : gen_putConfig

endmodule

// ================================================================
// Testbench
// ================================================================
module tb_cellrv32_npu_multiplier_network();

  localparam int TEST_CYCLES = 1000;

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
  logic [NumMultSwitches-1:0]        putData_en;
  logic [NumMultSwitches-1:0]        putData_rdy;
  logic [NumMultSwitches-1:0][15:0]  putData_val;

  logic [NumMultSwitches-1:0]        getData_rdy;
  logic [NumMultSwitches-1:0]        getData_en;
  logic [NumMultSwitches-1:0][15:0]  getData_val;

  logic          putConfig_en;
  MN_Config      putConfig_val;
  logic          putConfig_rdy;  
  logic [31:0]   putConfig_numActualActiveMultSwitches;
  
  MN_Config    cfg;
  MS_State     state     [NumMultSwitches-1:0];
  MS_PSumCount psumCount [NumMultSwitches-1:0];
  logic [15:0] inputData;
  logic [15:0] data      [NumMultSwitches-1:0];

  // -------------------------------------------------------------------------
  // DUT instance
  // -------------------------------------------------------------------------
  cellrv32_npu_multiplier_network dut (
    .clk_i                                   (clk                                  ),
    .rstn_i                                  (rst_n                                ),
    .putData_en_i                            (putData_en                           ),
    .putData_rdy_o                           (putData_rdy                          ),
    .putData_val_i                           (putData_val                          ),
    .getData_rdy_o                           (getData_rdy                          ),
    .getData_en_i                            (getData_en                           ),
    .getData_val_o                           (getData_val                          ),
    .putConfig_en_i                          (putConfig_en                         ),
    .putConfig_val_i                         (putConfig_val                        ),
    .putConfig_rdy_o                         (putConfig_rdy                        ),
    .putConfig_numActualActiveMultSwitches_i (putConfig_numActualActiveMultSwitches)
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
  int send_count [NumMultSwitches-1:0];
  int recv_count [NumMultSwitches-1:0];

  initial begin
    pass_count = 0;
    fail_count = 0;
    for (int i = 0; i < NumMultSwitches; i++) begin
      send_count[i] = 0;
      recv_count[i] = 0;
    end
  end

  // -------------------------------------------------------------------------
  // Finish
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (cycleCount == 32'(TEST_CYCLES)) begin
      $display("==================================");
      $display("Test Summary:");
      $display("  PASS : %0d", pass_count);
      $display("  FAIL : %0d", fail_count);
      $display("");
      for (int i = 0; i < NumMultSwitches; i++) begin
        $display("  sw[%0d] send=%0d recv=%0d", i, send_count[i], recv_count[i]);
      end
      $display("==================================");
      $finish;
    end
  end

  // =========================================================================
  // Helper tasks
  // =========================================================================
  // -------------------------------------------------------------------------
  // push a config to DUT when putConfig_rdy is high
  // -------------------------------------------------------------------------
  task automatic do_putConfig(
    input MN_Config  cfg,
    input logic [31:0] numActive
  );
    wait (putConfig_rdy);
    @(posedge clk);
    putConfig_en                          = 1'b1;
    putConfig_val                         = cfg;
    putConfig_numActualActiveMultSwitches = numActive;
    @(posedge clk);
    putConfig_en = 1'b0;
    @(posedge clk);
  endtask

  // -------------------------------------------------------------------------
  // push a data to DUT when putData_rdy is high
  // -------------------------------------------------------------------------
  task automatic do_putData(
    input int          sw,
    input logic [15:0] data
  );
    wait (putData_rdy[sw]);
    @(posedge clk);
    putData_en[sw]  = 1'b1;
    putData_val[sw] = data;
    @(posedge clk);
    putData_en[sw] = 1'b0;
    send_count[sw]++;
  endtask

  // -------------------------------------------------------------------------
  // do_putDataAll: inject data to all swithches
  // -------------------------------------------------------------------------
  task automatic do_putDataAll(
    input logic [15:0] data [NumMultSwitches-1:0]
  );
    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      wait (putData_rdy[sw]);
    end
    @(posedge clk);
    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      putData_en[sw]  = 1'b1;
      putData_val[sw] = data[sw];
    end
    @(posedge clk);
    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      putData_en[sw] = 1'b0;
      send_count[sw]++;
    end
  endtask

  // -------------------------------------------------------------------------
  // check_getPSum: check the pSum from DUT when getData_rdy is high
  // -------------------------------------------------------------------------
  task automatic check_getPSum(
    input int          sw,
    input logic [15:0] argA,
    input logic [15:0] argB,
    input string       test_name
  );
    logic [63:0] expected;
    logic [15:0] result;
    wait (getData_rdy[sw]);
    getData_en[sw] <= 1'b1;
    @(posedge clk);
    expected = {{16{argA[15]}}, argA} * {{16{argB[15]}}, argB};
    result = {expected[31], expected[26:12]};
    if (getData_val[sw] === result) begin
      $display("[PASS] %s: sw[%0d] pSum=%0d (expected %0d) @ cycle %0d",
                test_name, sw, getData_val[sw], result, cycleCount);
      pass_count++;
    end else begin
      $display("[FAIL] %s: sw[%0d] pSum=%0d (expected %0d) @ cycle %0d",
                test_name, sw, getData_val[sw], result, cycleCount);
      fail_count++;
    end
    recv_count[sw]++;
    #1;
    getData_en[sw] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // make_config_weights: create MN_Config within state and psumCount
  // -------------------------------------------------------------------------
  function automatic MN_Config make_config_weights (
    input MS_PSumCount psumCount [NumMultSwitches-1:0],
    input MS_State     state     [NumMultSwitches-1:0]
  );
    MN_Config cfg;
    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      cfg[sw] = '{state: state[sw], psumCount: psumCount[sw]};
    end
    return cfg;
  endfunction

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    // Init
    putData_en   = '0;
    putData_val  = '0;
    getData_en   = '0;
    putConfig_en = 1'b0;
    putConfig_val = '{default: '{state: 3'b000, psumCount: 16'd0}};
    putConfig_numActualActiveMultSwitches = 0;

    // Reset
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;

    repeat(2) @(posedge clk);

    // =======================================================================
    // TEST 1: single switch active, weight (identity)
    // sw[0]: weight x input -> pSum
    // =======================================================================
    $display("--- TEST 1: single switch, weight (identity) ---");
    // load weight
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'd0;
      state[i]     = MS_INIT_STEADY_VAL;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd1);
    do_putData(0, 16'd42);

    // data stream
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'd13;
      state[i]     = MS_RUN_LEDGE;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd1);

    while (psumCount[0]) begin
      inputData = $random();
      fork
        do_putData(0, inputData);
        check_getPSum(0, 16'd42, inputData, "T1_identity");
      join
      psumCount[0]--;
    end

    // =======================================================================
    // TEST 2: all switches active
    // pSum[i] = w[i] * input[i]
    // =======================================================================
    $display("\n--- TEST 2: all switches ---");
    // load weight
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'd0;
      state[i]     = MS_INIT_STEADY_VAL;
      data[i]      = 16'd42;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);
    do_putDataAll(data);

    // data stream
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'(i + 1);
      state[i]     = MS_RUN_LEDGE;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);

    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      while (psumCount[sw]) begin
        inputData = $random();
        fork
          do_putData(sw, inputData);
          check_getPSum(sw, 16'd42, inputData, "T2_allSw");
        join
        psumCount[sw]--;
      end
    end

    // =======================================================================
    // TEST 3: forward link chain
    // mode=forward, inject sw[0], expect sw[N-1] receives data forwarded
    // =======================================================================
    // Reset
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;

    $display("\n--- TEST 3: forward link chain ---");
     // load weight
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'd0;
      state[i]     = MS_INIT_STEADY_VAL;
      data[i]      = 16'd100;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);
    do_putDataAll(data);

    // initiate first switch to forward mode
    state[0] = MS_RUN_LEDGE;
    psumCount[0] = 16'd1;
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd1);
    do_putData(0, 16'd99);

    // forward chain: sw[0] -> sw[1] -> ... -> sw[N-1]
    for (int i = 1; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'd1;
      state[i]     = MS_RUN_MIDDLE;
      data[i]      = 16'd77;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);

    check_getPSum(NumMultSwitches-1, 16'd100, 16'd99, "T3_fwd_chain");

    // =======================================================================
    // TEST 4: backpressure on getData (getData_en=0 for 13 cycles)
    // =======================================================================
    // Reset
    rst_n = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    
    $display("--- TEST 4: backpressure on getData ---");
     // load weight
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 0;
      state[i]     = MS_INIT_STEADY_VAL;
      data[i]      = $random();
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);
    do_putDataAll(data);

    // data stream
    for (int i = 0; i < NumMultSwitches; i++) begin
      psumCount[i] = 16'(i + 1);
      state[i]     = MS_RUN_LEDGE;
    end
    cfg = make_config_weights(psumCount, state);
    do_putConfig(cfg, 32'd16);

    for (int sw = 0; sw < NumMultSwitches; sw++) begin
      while (psumCount[sw]) begin
        inputData = $random();
        do_putData(sw, inputData);
        // pSum is valid after 13 cycles
        repeat(13) @(posedge clk);
        if (getData_rdy[sw]) begin
          $display("[PASS] T4: pSum held valid during backpressure @ cycle");
        end else begin
          $display("[FAIL] T4: pSum not valid after inject @ cycle");
          fail_count++;
        end
        check_getPSum(sw, data[sw], inputData, "T4_backpressure");
        psumCount[sw]--;
      end
    end
    $display("--- All planned tests done ---");
  end
endmodule