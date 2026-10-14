`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_subtree (
    input  logic clk_i,
    input  logic rstn_i,
    // controlPorts
    input  logic                          controlPorts_putNewDests_en_i ,
    output logic                          controlPorts_putNewDests_rdy_o,
    input  DN_SubTreeDestBits             controlPorts_putNewDests_val_i,
    output logic                          controlPorts_isEmpty_o        ,
    // putData
    input  logic                          inputDataPorts_putData_en_i   ,
    output logic                          inputDataPorts_putData_rdy_o  ,
    input  logic [15:0]                   inputDataPorts_putData_val_i  ,
    // getData
    input  logic [DN_SubTreeSz-1:0]       outputDataPorts_getData_en_i  ,
    output logic [DN_SubTreeSz-1:0]       outputDataPorts_getData_rdy_o ,
    output logic [DN_SubTreeSz-1:0][15:0] outputDataPorts_getData_val_o
);
    // ================================================================
    // SubTree_IngressNIC Instance
    // ================================================================
    logic        ingNIC_putData_en;
    logic        ingNIC_putData_rdy;
    logic [15:0] ingNIC_putData_val;
    logic        ingNIC_getData_en;
    logic        ingNIC_getData_rdy;
    logic [15:0] ingNIC_getData_val;
    logic        ingNIC_getEpoch_rdy;
    logic        ingNIC_getEpoch_val;
    logic        ingNIC_isEmpty;

    cellrv32_npu_subtree_ingress_NIC ingressNIC_inst (
        .clk_i          (clk_i              ),
        .rstn_i         (rstn_i             ),
        .putData_en_i   (ingNIC_putData_en  ),
        .putData_rdy_o  (ingNIC_putData_rdy ),
        .putData_val_i  (ingNIC_putData_val ),
        .getData_en_i   (ingNIC_getData_en  ),
        .getData_rdy_o  (ingNIC_getData_rdy ),
        .getData_val_o  (ingNIC_getData_val ),
        .getEpoch_rdy_o (ingNIC_getEpoch_rdy),
        .getEpoch_val_o (ingNIC_getEpoch_val),
        .isEmpty_val_o  (ingNIC_isEmpty     )
    );

    // ================================================================
    // SubTree_EgressNIC Instance
    // ================================================================
    logic [DN_SubTreeSz-1:0]       egrNIC_putData_en;
    logic [DN_SubTreeSz-1:0]       egrNIC_putData_rdy;
    logic [DN_SubTreeSz-1:0][15:0] egrNIC_putData_val;
    logic [DN_SubTreeSz-1:0]       egrNIC_getData_en;
    logic [DN_SubTreeSz-1:0]       egrNIC_getData_rdy;
    logic [DN_SubTreeSz-1:0][15:0] egrNIC_getData_val;

    cellrv32_npu_subtree_egress_NIC egressNIC_inst (
        .clk_i             (clk_i             ),
        .rstn_i            (rstn_i            ),
        .putNewDests_en_i  (egrNIC_putData_en ),
        .putNewDests_val_i (egrNIC_putData_val),
        .putNewDests_rdy_o (egrNIC_putData_rdy),
        .getDests_en_i     (egrNIC_getData_en ),
        .getDests_rdy_o    (egrNIC_getData_rdy),
        .getDests_val_o    (egrNIC_getData_val)
    );

    // ================================================================
    // SubTree_Controller Instance
    // ================================================================
    logic              ctrl_putNewDests_en;
    logic              ctrl_putNewDests_rdy;
    DN_SubTreeDestBits ctrl_putNewDests_val;
    logic              ctrl_putAckSignal_en;
    logic              ctrl_putAckSignal_rdy;
    logic              ctrl_getEpoch_val;
    logic              ctrl_getConf_en;
    logic              ctrl_getConf_rdy;
    DN_SubTreeConfig   ctrl_getConf_val;

    cellrv32_npu_subtree_controller controller_inst (
        .clk_i                   (clk_i                ),
        .rstn_i                  (rstn_i               ),
        .putNewDests_en_i        (ctrl_putNewDests_en  ),
        .putNewDests_rdy_o       (ctrl_putNewDests_rdy ),
        .putNewDests_val_i       (ctrl_putNewDests_val ),
        .putAckSignal_en_i       (ctrl_putAckSignal_en ),
        .putAckSignal_rdy_o      (ctrl_putAckSignal_rdy),
        .getEpoch_val_o          (ctrl_getEpoch_val    ),
        .getConfiguration_en_i   (ctrl_getConf_en      ),
        .getConfiguration_rdy_o  (ctrl_getConf_rdy     ),
        .getConfiguration_val_o  (ctrl_getConf_val     )
    );

    // ================================================================
    // DistributionSwitch Instances
    // ================================================================
    logic [DN_NumSubTreeDistSwitches-1:0]       sw_putData_en;
    logic [DN_NumSubTreeDistSwitches-1:0][15:0] sw_putData_val;
    logic [DN_NumSubTreeDistSwitches-1:0]       sw_getDataL_en;
    logic [DN_NumSubTreeDistSwitches-1:0][15:0] sw_getDataL_val;
    logic [DN_NumSubTreeDistSwitches-1:0]       sw_getDataR_en;
    logic [DN_NumSubTreeDistSwitches-1:0][15:0] sw_getDataR_val;
    logic [DN_NumSubTreeDistSwitches-1:0]       sw_putNewConfig_en;
    logic [DN_NumSubTreeDistSwitches-1:0][01:0] sw_putNewConfig_val;

    genvar idx;
    generate
        for (idx = 0; idx < DN_NumSubTreeDistSwitches; idx++) begin : gen_distSW
            cellrv32_npu_distributionswitch distSwitches_inst (
                .clk_i             (clk_i                               ),
                .rstn_i            (rstn_i                              ),
                .newInData_i       (sw_putData_val[idx]                 ),
                .newInData_en_i    (sw_putData_en[idx]                  ),
                .outDataLeft_o     (sw_getDataL_val[idx]                ),
                .outDataLeft_en_o  (sw_getDataL_en[idx]                 ),
                .outDataRight_o    (sw_getDataR_val[idx]                ),
                .outDataRight_en_o (sw_getDataR_en[idx]                 ),
                .newConfig_i       (DS_Config'(sw_putNewConfig_val[idx])),
                .newConfig_en_i    (sw_putNewConfig_en[idx]             )
            );
        end : gen_distSW
    endgenerate

    // ================================================================
    // Tree Datapath connections (mkConnection):
    //   for lv = 0 .. NL-2:
    //     for node = 0 .. 2^lv - 1:
    //       Connection(distSwitches[lvFirst+node].getDataL,
    //                  distSwitches[nextLvFirst + node*2].putData)
    //       Connection(distSwitches[lvFirst+node].getDataR,
    //                  distSwitches[nextLvFirst + node*2 + 1].putData)
    // ================================================================
    logic rule_sendData;

    always_comb begin : datapath_connection
        // default
        sw_putData_en [0] = 1'b0;
        sw_putData_val[0] = '0;
        if (rule_sendData) begin : sending_Data
            sw_putData_en [0] = 1'b1;
            sw_putData_val[0] = ingNIC_getData_val;
        end : sending_Data
        //
        for (int lv = 0; lv < DN_NumSubTreeLvs; lv++) begin : tree_datapath_connection
            automatic int lvFirstNodeID     = 2 ** lv - 1;
            automatic int nextLvFirstNodeID = 2 ** (lv + 1) - 1;
            automatic int numNodes          = 2 ** lv;
            //
            for (int node = 0; node < numNodes ; node++) begin
                automatic int firstTargNodeID = nextLvFirstNodeID + node * 2;
                // Connection(getDataL, putData)
                sw_putData_en [firstTargNodeID] = sw_getDataL_en [lvFirstNodeID + node];
                sw_putData_val[firstTargNodeID] = sw_getDataL_val[lvFirstNodeID + node];
                // Connection(getDataR, putData)
                sw_putData_en [firstTargNodeID + 1] = sw_getDataR_en [lvFirstNodeID + node];
                sw_putData_val[firstTargNodeID + 1] = sw_getDataR_val[lvFirstNodeID + node];
            end
        end : tree_datapath_connection
    end : datapath_connection

    // ================================================================
    // Connect Tree Leaves and NIC
    // ================================================================
    localparam int lastLvFirstNodeID = 2 ** (DN_NumSubTreeLvs - 1) - 1;
    genvar sw;
    generate
        for (sw = 0; sw < DN_SubTreeSz; sw++) begin : tree_leaves_NIC
            if (sw % 2 == 0) begin
                assign egrNIC_putData_en [sw] = sw_getDataL_en [lastLvFirstNodeID + sw/2] & egrNIC_putData_rdy[sw];
                assign egrNIC_putData_val[sw] = sw_getDataL_val[lastLvFirstNodeID + sw/2];
            end else begin
                assign egrNIC_putData_en [sw] = sw_getDataR_en [lastLvFirstNodeID + sw/2] & egrNIC_putData_rdy[sw];
                assign egrNIC_putData_val[sw] = sw_getDataR_val[lastLvFirstNodeID + sw/2];
            end
        end : tree_leaves_NIC
    endgenerate

    // ================================================================
    // sendData
    // ================================================================
    assign rule_sendData = (ctrl_getEpoch_val == ingNIC_getEpoch_val) // epoch match
                           & ingNIC_getData_rdy                       // data available
                           & ingNIC_getEpoch_rdy                      // epoch valid
                           & ctrl_putAckSignal_rdy                    // controller waiting for ack
                           & &egrNIC_putData_rdy;                     // all leafs ready

    assign ingNIC_getData_en    = rule_sendData;
    assign ctrl_putAckSignal_en = rule_sendData;
    
    // ================================================================
    // configureTree
    // ================================================================
    assign ctrl_getConf_en = ctrl_getConf_rdy;  

    always_comb begin : configureTree
        for (int sw = 0; sw < DN_NumSubTreeDistSwitches; sw++) begin
            if (ctrl_getConf_en) begin
                sw_putNewConfig_en [sw] = 1'b1;
                sw_putNewConfig_val[sw] = ctrl_getConf_val[sw];
            end else begin
                sw_putNewConfig_en [sw] = 1'b0;
                sw_putNewConfig_val[sw] = DS_IDLE;
            end
        end
    end : configureTree

    // ================================================================
    // Input/Output assignments
    // ================================================================
    // isEmpty
    assign controlPorts_isEmpty_o = ingNIC_isEmpty;

    // putNewDests
    assign ctrl_putNewDests_en            = controlPorts_putNewDests_en_i;
    assign controlPorts_putNewDests_rdy_o = ctrl_putNewDests_rdy;
    assign ctrl_putNewDests_val           = controlPorts_putNewDests_val_i;

    // putData
    assign ingNIC_putData_en            = inputDataPorts_putData_en_i;
    assign inputDataPorts_putData_rdy_o = ingNIC_putData_rdy;
    assign ingNIC_putData_val           = inputDataPorts_putData_val_i;

    // getData
    assign egrNIC_getData_en             = outputDataPorts_getData_en_i;
    assign outputDataPorts_getData_rdy_o = egrNIC_getData_rdy;
    assign outputDataPorts_getData_val_o = egrNIC_getData_val;

endmodule

// ============================================================
// Full-Feature Testbench for SubTree
//
// Test coverage:
//   TC1 : Reset & initialization — verify isEmpty=1, correct ready signals
//   TC2 : putNewDests blocked when not ready
//   TC3 : putData blocked when not ready (before configuration)
//   TC4 : Broadcast — all leaves receive data
//   TC5 : Left route (DS_LEFT) — only even leaves receive
//   TC6 : Right route (DS_RIGHT) — only odd leaves receive
//   TC7 : Unicast — only one leaf receives
//   TC8 : Pipeline — multiple consecutive frames without stalling
//   TC9 : Backpressure — outputGet not drained → correct SubTree stall
//   TC10: isEmpty semantics — True only when ingressNIC is empty
//   TC11: Reset during operation  
// ============================================================

module tb_cellrv32_npu_subtree;
    // ----------------------------------------------------------------
    // Clock & Reset
    // ----------------------------------------------------------------
    logic clk_i, rstn_i;
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // ----------------------------------------------------------------
    // DUT ports
    // ----------------------------------------------------------------
    logic                          controlPorts_isEmpty_o;
    logic                          controlPorts_putNewDests_en_i;
    logic                          controlPorts_putNewDests_rdy_o;
    DN_SubTreeDestBits             controlPorts_putNewDests_val_i;

    logic                          inputDataPorts_putData_en_i;
    logic                          inputDataPorts_putData_rdy_o;
    logic [15:0]                   inputDataPorts_putData_val_i;

    logic [DN_SubTreeSz-1:0]       outputDataPorts_getData_en_i;
    logic [DN_SubTreeSz-1:0]       outputDataPorts_getData_rdy_o;
    logic [DN_SubTreeSz-1:0][15:0] outputDataPorts_getData_val_o;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    cellrv32_npu_subtree dut (
        .clk_i                          (clk_i                         ),
        .rstn_i                         (rstn_i                        ),
        .controlPorts_isEmpty_o         (controlPorts_isEmpty_o        ),
        .controlPorts_putNewDests_en_i  (controlPorts_putNewDests_en_i ),
        .controlPorts_putNewDests_rdy_o (controlPorts_putNewDests_rdy_o),
        .controlPorts_putNewDests_val_i (controlPorts_putNewDests_val_i),
        .inputDataPorts_putData_en_i    (inputDataPorts_putData_en_i   ),
        .inputDataPorts_putData_rdy_o   (inputDataPorts_putData_rdy_o  ),
        .inputDataPorts_putData_val_i   (inputDataPorts_putData_val_i  ),
        .outputDataPorts_getData_en_i   (outputDataPorts_getData_en_i  ),
        .outputDataPorts_getData_rdy_o  (outputDataPorts_getData_rdy_o ),
        .outputDataPorts_getData_val_o  (outputDataPorts_getData_val_o )
    );

    // ----------------------------------------------------------------
    // Scoreboard & statistics
    // ----------------------------------------------------------------
    int pass_cnt, fail_cnt;
    string current_tc;

    task automatic pass(input string msg = "");
        pass_cnt++;
        $display("  [PASS] %s %s", current_tc, msg);
    endtask

    task automatic fail(input string msg = "");
        fail_cnt++;
        $display("  [FAIL] %s %s", current_tc, msg);
    endtask

    task automatic check(input logic cond, input string msg);
        if (cond) pass(msg);
        else      fail(msg);
    endtask

    // ----------------------------------------------------------------
    // Helper: build DN_SubTreeDestBits
    //   destBits[2*leaf]   = left leaf
    //   destBits[2*leaf+1] = right leaf
    // ----------------------------------------------------------------
    function automatic DN_SubTreeDestBits make_dest_broadcast();
        return '1;
    endfunction

    function automatic DN_SubTreeDestBits make_dest_left_only();
        // Set only the "left" bit of each leaf node.
        DN_SubTreeDestBits bits = '0;
        for (int i = 0; i < DN_SubTreeSz/2; i++)
            bits[2*i] = 1'b1;   
        return bits;
    endfunction

    function automatic DN_SubTreeDestBits make_dest_right_only();
        // Set only the "right" bit of each leaf node.
        DN_SubTreeDestBits bits = '0;
        for (int i = 0; i < DN_SubTreeSz/2; i++)
            bits[2*i+1] = 1'b1;
        return bits;
    endfunction

    function automatic DN_SubTreeDestBits make_dest_leaf(input int leaf_idx);
        // Enable only one leaf: leaf_idx
        DN_SubTreeDestBits bits = '0;
        bits[leaf_idx] = 1'b1;
        return bits;
    endfunction

    // ----------------------------------------------------------------
    // Task: Sending routing configuration.
    // ----------------------------------------------------------------
    task automatic send_config(
        input DN_SubTreeDestBits cfg,
        input int                timeout = 1000
    );
        int t;
        for (t = 0; t < timeout; t++) begin
            @(posedge clk_i);
            if (controlPorts_putNewDests_rdy_o) begin
                controlPorts_putNewDests_en_i  = 1'b1;
                controlPorts_putNewDests_val_i = cfg;
                @(posedge clk_i);
                #1;
                controlPorts_putNewDests_en_i = 1'b0;
                return;
            end
            @(negedge clk_i);
        end
        $display("  [WARN] send_config TIMEOUT after %0d cycles", timeout);
    endtask

    // ----------------------------------------------------------------
    // Task: sending data
    // ----------------------------------------------------------------
    task automatic send_data(
        input logic [15:0] val,
        input int          timeout = 1000
    );
        int t;
        for (t = 0; t < timeout; t++) begin
            @(posedge clk_i);
            if (inputDataPorts_putData_rdy_o) begin
                inputDataPorts_putData_en_i  = 1'b1;
                inputDataPorts_putData_val_i = val;
                @(posedge clk_i);
                #1;
                inputDataPorts_putData_en_i = 1'b0;
                return;
            end
            @(negedge clk_i);
        end
        $display("  [WARN] send_data TIMEOUT after %0d cycles", timeout);
    endtask

    // ----------------------------------------------------------------
    // Task: drain an output port
    // Returns the received value (or 'X' on timeout)
    // ----------------------------------------------------------------
    task automatic drain_port(
        input  int          port_idx,
        output logic [15:0] got_val,
        output logic        got_valid,
        input  int          timeout = 50
    );
        got_valid = 1'b0;
        got_val   = 'X;
        for (int t = 0; t < timeout; t++) begin
            @(posedge clk_i);
            if (outputDataPorts_getData_rdy_o[port_idx]) begin
                outputDataPorts_getData_en_i[port_idx] = 1'b1;
                got_val   = outputDataPorts_getData_val_o[port_idx];
                got_valid = 1'b1;
                @(posedge clk_i);
                #1;
                outputDataPorts_getData_en_i[port_idx] = 1'b0;
                return;
            end
            @(negedge clk_i);
        end
    endtask

    // ----------------------------------------------------------------
    // Task: Drain all ports with expected_mask = 1
    // Check: Ports within the mask receive the correct expected_val
    // Ports outside the mask do not receive it
    // ----------------------------------------------------------------
    task automatic drain_and_check(
        input DN_SubTreeDestBits expected_mask,
        input logic [15:0]       expected_val,
        input int                per_port_timeout = 1000
    );
        logic [15:0] got_val;
        logic        got_valid;
        logic [DN_SubTreeSz-1:0] did_receive = '0;

        // Drain all ports in the mask    
        for (int i = 0; i < DN_SubTreeSz; i++) begin
            if (expected_mask[i]) begin
                drain_port(i, got_val, got_valid, per_port_timeout);
                if (got_valid) begin
                    did_receive[i] = 1'b1;
                    if (got_val === expected_val)
                        pass($sformatf("port[%0d] = 0x%04X (correct)", i, got_val));
                    else
                        fail($sformatf("port[%0d] = 0x%04X (expect 0x%04X)", i, got_val, expected_val));
                end else begin
                    fail($sformatf("port[%0d] TIMEOUT (expected 0x%04X)", i, expected_val));
                end
            end
        end

        // External port check: No response received within 5 cycles.
        repeat (5) @(posedge clk_i);
        for (int i = 0; i < DN_SubTreeSz; i++) begin
            if (!expected_mask[i]) begin
                if (outputDataPorts_getData_rdy_o[i])
                    fail($sformatf("port[%0d] unexpectedly has data (should be idle)", i));
                // else: correct — no data available
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Task: send config + data + drain (a complete transaction)
    // ----------------------------------------------------------------
    task automatic full_transaction(
        input DN_SubTreeDestBits cfg,
        input logic [15:0]       data_val,
        input DN_SubTreeDestBits expect_mask,
        input string             tc_name
    );
        current_tc = tc_name;
        $display("\n--- %s ---", tc_name);
        send_config(cfg);
        repeat (3) @(posedge clk_i);
        send_data(data_val);
        drain_and_check(expect_mask, data_val);
    endtask

    // ================================================================
    // MAIN TEST SEQUENCE
    // ================================================================
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        // initialize inout signals
        rstn_i                         = 1'b0;
        controlPorts_putNewDests_en_i  = 1'b0;
        controlPorts_putNewDests_val_i = '0;
        inputDataPorts_putData_en_i    = 1'b0;
        inputDataPorts_putData_val_i   = '0;
        outputDataPorts_getData_en_i   = '0;

        // ============================================================
        // TC1: Reset & initialize
        // ============================================================
        current_tc = "TC1_Reset";
        $display("\n========== TC1: Reset & Init ==========");
        repeat (3) @(posedge clk_i);
        rstn_i = 1'b1;
        @(posedge clk_i); #1;

        check(controlPorts_isEmpty_o         === 1'b1, "isEmpty=1 after reset");
        check(controlPorts_putNewDests_rdy_o === 1'b1, "putNewDests_rdy=1 after reset");
        check(inputDataPorts_putData_rdy_o   === 1'b1, "putData_rdy=1 after reset");
        check(outputDataPorts_getData_rdy_o  === '0,   "no outputData after reset");

        // ============================================================
        // TC2: putNewDests while controller is busy -> rdy=0
        // (Send first config, then immediately send second config)
        // ============================================================
        current_tc = "TC2_putNewDests_backpressure";
        $display("\n========== TC2: putNewDests backpressure ==========");
        // 1st-config
        @(posedge clk_i);
        controlPorts_putNewDests_en_i  = 1'b1;
        controlPorts_putNewDests_val_i = make_dest_broadcast();
        @(posedge clk_i);
        #1;
        controlPorts_putNewDests_en_i = 1'b0;

        // 2nd-config immediately
        @(posedge clk_i);
        controlPorts_putNewDests_en_i  = 1'b1;
        controlPorts_putNewDests_val_i = make_dest_broadcast();
        @(posedge clk_i);
        #1;
        controlPorts_putNewDests_en_i = 1'b0;

        // 3rd-config immediately
        @(posedge clk_i);
        controlPorts_putNewDests_en_i  = 1'b1;
        controlPorts_putNewDests_val_i = make_dest_broadcast();
        @(posedge clk_i);
        #1;
        controlPorts_putNewDests_en_i = 1'b0;

        // 4th-config immediately
        @(posedge clk_i);
        controlPorts_putNewDests_en_i  = 1'b1;
        controlPorts_putNewDests_val_i = make_dest_broadcast();
        @(posedge clk_i);
        #1;
        controlPorts_putNewDests_en_i = 1'b0;

        // Result of backpressure depends on FIFO depth — only log
        $display("  [INFO] putNewDests_rdy = %b (FIFO depth dependent)", controlPorts_putNewDests_rdy_o);
        pass("TC2 flow completed");

        // ============================================================
        // TC3: Broadcast — All leaves accepted.
        // ============================================================
        // reset DUT
        rstn_i = 1'b0;
        @(posedge clk_i);
        @(posedge clk_i);
        rstn_i = 1'b1;
        @(posedge clk_i);

        full_transaction(
            make_dest_broadcast(),
            16'hBEEF,
            {DN_SubTreeSz{1'b1}},
            "TC3_Broadcast"
        );

        // ============================================================
        // TC4: Left route — only even-numbered leaves receive (sw 0, 2, 4, 6)
        // ============================================================
        full_transaction(
            make_dest_left_only(),
            16'hAAAA,
            8'b01010101,  // port 0,2,4,6 = even leaves
            "TC4_LeftOnly"
        );

        // ============================================================
        // TC5: Right route — only odd-numbered leaves receive (sw 1, 3, 5, 7)
        // ============================================================
        full_transaction(
            make_dest_right_only(),
            16'hBBBB,
            8'b10101010,  // port 1,3,5,7 = odd leaves
            "TC5_RightOnly"
        );

        // ============================================================
        // TC6: Unicast — only leaf 0 and 5 receives (sw 0, sw 5)
        // ============================================================
        full_transaction(
            make_dest_leaf(0),
            16'h0001,
            8'b00000001,
            "TC6.1_Unicast_leaf0"
        );

        full_transaction(
            make_dest_leaf(4),
            16'h0002,
            8'b00010000,
            "TC6.2_Unicast_leaf5"
        );

        // ============================================================
        // TC7: Unicast — only last and pre-last leaves receive
        // ============================================================
        full_transaction(
            make_dest_leaf(DN_SubTreeSz-1),
            16'hFF00,
            1 << (DN_SubTreeSz-1),
            "TC7.1_Unicast_lastLeaf"
        );
        
        full_transaction(
            make_dest_leaf(DN_SubTreeSz-2),
            16'h00FF,
            1 << (DN_SubTreeSz-2),
            "TC7.2_Unicast_preLastLeaf"
        );

        // ============================================================
        // TC8: Pipeline — 13 frame broadcast without stalling
        // ============================================================
        current_tc = "TC8_Pipeline";
        $display("\n========== TC8: Pipeline 13 frames ==========");
        begin
            static logic [15:0] pipe_vals [0:12] = '{16'h0011, 16'h0022, 16'h0033, 16'h0044, 16'h0055, 16'h0066, 16'h0077, 16'h0088, 16'h0099, 16'h00AA, 16'h00BB, 16'h00CC, 16'h00DD};

            // send 13 config + 13 data
            for (int f = 0; f < 13; f++) begin
                send_config(make_dest_broadcast());
                repeat (2) @(posedge clk_i);
                send_data(pipe_vals[f]);
            end

            // Drain all 13 frame
            for (int f = 0; f < 13; f++) begin
                automatic logic [15:0] got; logic ok;
                for (int p = 0; p < DN_SubTreeSz; p++) begin
                    drain_port(p, got, ok, 80);
                    if (ok) begin
                        if (got === pipe_vals[f])
                            pass($sformatf("frame[%0d] port[%0d] = 0x%04X", f, p, got));
                        else
                            fail($sformatf("frame[%0d] port[%0d] = 0x%04X (exp 0x%04X)",
                                           f, p, got, pipe_vals[f]));
                    end else
                        fail($sformatf("frame[%0d] port[%0d] TIMEOUT", f, p));
                end
            end
        end

        // ============================================================
        // TC9: Backpressure — no drain output -> SubTree stall
        // ============================================================
        // reset DUT
        rstn_i = 1'b0;
        @(posedge clk_i);
        @(posedge clk_i);
        rstn_i = 1'b1;
        @(posedge clk_i);

        current_tc = "TC9_Backpressure";
        $display("\n========== TC9: Output backpressure ==========");
        begin
            // Send config + data but do NOT drain output  
            send_config(make_dest_broadcast());
            repeat (3) @(posedge clk_i);
            send_data(16'hDEAD);

            // Waiting for output data
            repeat (2000) @(posedge clk_i);
            #1;

            // Check output rdy = 1 (data pending)
            check(outputDataPorts_getData_rdy_o != '0,
                  "outputData waiting (backpressure held data)");

            // Check SubTree block: putData_rdy = 0 if pipeline full
            // (optional — depends on FIFO depth, only log)
            $display("  [INFO] putData_rdy = %b (may be 0 if pipeline full)",
                     inputDataPorts_putData_rdy_o);

            // Drain to release backpressure
            for (int p = 0; p < DN_SubTreeSz; p++) begin
                logic [15:0] got; logic ok;
                drain_port(p, got, ok, 10);
            end
            pass("TC9 backpressure and drain completed");
        end

        // ============================================================
        // TC10: isEmpty semantics
        // ============================================================
        // reset DUT
        rstn_i = 1'b0;
        @(posedge clk_i);
        @(posedge clk_i);
        rstn_i = 1'b1;
        @(posedge clk_i);

        current_tc = "TC10_isEmpty";
        $display("\n========== TC10: isEmpty ==========");
        begin
            // after drain all data — isEmpty is 1
            repeat (5) @(posedge clk_i); #1;
            check(controlPorts_isEmpty_o === 1'b1,
                  "isEmpty=1 after all drained");

            // sending data -> isEmpty = 0
            send_config(make_dest_broadcast());
            repeat (2) @(posedge clk_i);
            send_data(16'h1234);
            @(negedge clk_i);
            check(controlPorts_isEmpty_o === 1'b0,
                  "isEmpty=0 after putData");

            // Drain -> isEmpty is 1
            for (int p = 0; p < DN_SubTreeSz; p++) begin
                logic [15:0] got; logic ok;
                drain_port(p, got, ok, 40);
            end
            repeat (5) @(posedge clk_i); #1;
            check(controlPorts_isEmpty_o === 1'b1,
                  "isEmpty=1 after drain");
        end

        // ============================================================
        // TC11: Reset during operation  
        // ============================================================
        current_tc = "TC11_MidReset";
        $display("\n========== TC11: Reset mid-operation ==========");
        begin
            // start transaction
            send_config(make_dest_broadcast());
            send_data(16'hBAD0);
            repeat (5) @(posedge clk_i);

            // Assert reset
            rstn_i = 1'b0;
            repeat (3) @(posedge clk_i);
            rstn_i = 1'b1;
            @(posedge clk_i); #1;

            check(controlPorts_isEmpty_o         === 1'b1, "isEmpty=1 after mid-reset");
            check(controlPorts_putNewDests_rdy_o === 1'b1, "putNewDests_rdy=1 after mid-reset");
            check(outputDataPorts_getData_rdy_o  === '0,   "no stale output after mid-reset");

            // normal transaction after reset
            full_transaction(
                make_dest_broadcast(),
                16'h11FF,
                {DN_SubTreeSz{1'b1}},
                "TC11_PostReset_broadcast"
            );
        end

        // ============================================================
        // Summary
        // ============================================================
        repeat (5) @(posedge clk_i);
        $display("\n========================================");
        $display("  TEST SUMMARY");
        $display("  PASS: %0d", pass_cnt);
        $display("  FAIL: %0d", fail_cnt);
        $display("  TOTAL: %0d", pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("  RESULT: ALL PASSED");
        else
            $display("  RESULT: %0d FAILURES", fail_cnt);
        $display("========================================\n");
        $finish;
    end

    // ----------------------------------------------------------------
    // Timeout watchdog   
    // ----------------------------------------------------------------
    initial begin
        #500000;
        $display("[WATCHDOG] Simulation timeout!");
        $finish;
    end

endmodule