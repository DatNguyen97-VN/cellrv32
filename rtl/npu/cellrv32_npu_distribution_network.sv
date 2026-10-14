`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_distribution_network (
    input  logic                                        clk_i          ,
    input  logic                                        rstn_i         ,
    // isEmpty
    output logic                                        isEmpty_val_o  ,
    // controlPorts
    input  logic [DN_NumSubTrees-1:0]                   ctrl_en_i      ,
    output logic [DN_NumSubTrees-1:0]                   ctrl_rdy_o     ,
    input  logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0] ctrl_val_i     ,
    // putData
    input  logic [DN_NumSubTrees-1:0]                   inputPut_en_i  ,
    output logic [DN_NumSubTrees-1:0]                   inputPut_rdy_o ,
    input  logic [DN_NumSubTrees-1:0][15:0]             inputPut_val_i ,
    // getData
    input  logic [NumMultSwitches-1:0]                  outputGet_en_i ,
    output logic [NumMultSwitches-1:0]                  outputGet_rdy_o,
    output logic [NumMultSwitches-1:0][15:0]            outputGet_val_o
);

    // ----------------------------------------------------------------
    // InputBuffers instance
    // ----------------------------------------------------------------
    logic [DistributionBandwidth-1:0]       put_fifo_enq_en,  put_fifo_notFull;
    logic [DistributionBandwidth-1:0]       put_fifo_deq_en,  put_fifo_notEmpty;
    logic [DistributionBandwidth-1:0][15:0] put_fifo_enq_val, put_fifo_first;

    genvar idx;
    generate
        for (idx = 0; idx < DistributionBandwidth; idx++) begin : input_buffer
            PipelineFifo #(
              .T     (INT16              ),
              .DEPTH (DN_IngressFifoDepth)
            ) inputBuffers (
              .clk_i       (clk_i                 ),        
              .rstn_i      (rstn_i                ),
              .enq_en_i    (put_fifo_enq_en[idx]  ),  
              .notFull_o   (put_fifo_notFull[idx] ),
              .enq_val_i   (put_fifo_enq_val[idx] ),
              .deq_en_i    (put_fifo_deq_en[idx]  ),  
              .notEmpty_o  (put_fifo_notEmpty[idx]),
              .first_val_o (put_fifo_first[idx]   )
            );
        end : input_buffer
    endgenerate

    assign put_fifo_enq_en  = inputPut_en_i & put_fifo_notFull;
    assign put_fifo_enq_val = inputPut_val_i;

    // ----------------------------------------------------------------
    // OutputBuffers instance
    // ----------------------------------------------------------------
    logic [NumMultSwitches-1:0]       get_fifo_enq_en,  get_fifo_notFull;
    logic [NumMultSwitches-1:0]       get_fifo_deq_en,  get_fifo_notEmpty;
    logic [NumMultSwitches-1:0][15:0] get_fifo_enq_val, get_fifo_first;

    generate
        for (idx = 0; idx < NumMultSwitches; idx++) begin : output_buffer
            PipelineFifo #(
              .T     (INT16             ),
              .DEPTH (DN_EgressFifoDepth)
            ) outputBuffers (
              .clk_i       (clk_i                 ),       
              .rstn_i      (rstn_i                ),
              .enq_en_i    (get_fifo_enq_en[idx]  ), 
              .notFull_o   (get_fifo_notFull[idx] ),
              .enq_val_i   (get_fifo_enq_val[idx] ),
              .deq_en_i    (get_fifo_deq_en[idx]  ), 
              .notEmpty_o  (get_fifo_notEmpty[idx]),
              .first_val_o (get_fifo_first[idx]   )
            );
        end : output_buffer
    endgenerate

    // ----------------------------------------------------------------
    // SubTree instances
    // ----------------------------------------------------------------
    logic [DN_NumSubTrees-1:0]                         st_isEmpty;
    logic [DN_NumSubTrees-1:0]                         st_putDest_en;
    logic [DN_NumSubTrees-1:0]                         st_putDest_rdy;
    logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0]       st_putDest_val;
    logic [DN_NumSubTrees-1:0]                         st_inputPut_en;
    logic [DN_NumSubTrees-1:0]                         st_inputPut_rdy;
    logic [DN_NumSubTrees-1:0][15:0]                   st_inputPut_val;
    logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0]       st_outputGet_en;
    logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0]       st_outputGet_rdy;
    logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0][15:0] st_outputGet_val;

    generate
        for (idx = 0; idx < DN_NumSubTrees; idx++) begin : gen_subtrees
            cellrv32_npu_subtree subTrees_inst (
              .clk_i                          (clk_i                ),
              .rstn_i                         (rstn_i               ),
              .controlPorts_isEmpty_o         (st_isEmpty[idx]      ),
              .controlPorts_putNewDests_en_i  (st_putDest_en[idx]   ),
              .controlPorts_putNewDests_rdy_o (st_putDest_rdy[idx]  ),
              .controlPorts_putNewDests_val_i (st_putDest_val[idx]  ),
              .inputDataPorts_putData_en_i    (st_inputPut_en[idx]  ),
              .inputDataPorts_putData_rdy_o   (st_inputPut_rdy[idx] ),
              .inputDataPorts_putData_val_i   (st_inputPut_val[idx] ),
              .outputDataPorts_getData_en_i   (st_outputGet_en[idx] ),
              .outputDataPorts_getData_rdy_o  (st_outputGet_rdy[idx]),
              .outputDataPorts_getData_val_o  (st_outputGet_val[idx])
        );
        end : gen_subtrees
    endgenerate

    // ================================================================
    // Interconnect: InputBuffer.getData[i] -> subTrees[i].inputPut
    // ================================================================
    always_comb begin : connect_inputbuffer_to_subtree
        for (int i = 0; i < DN_NumSubTrees; i++) begin
            put_fifo_deq_en[i] = put_fifo_notEmpty[i] & st_inputPut_rdy[i];
            st_inputPut_en [i] = put_fifo_deq_en[i];
            st_inputPut_val[i] = put_fifo_first[i];
        end
    end : connect_inputbuffer_to_subtree

    // ================================================================
    // Interconnect: subTrees[i].outputGet[j] -> OutputBuffer.putData[i*SZ+j]
    // ================================================================
    always_comb begin : connect_subtree_to_outputbuffer
        for (int i = 0; i < DN_NumSubTrees; i++) begin
            st_outputGet_en[i]                               = st_outputGet_rdy[i] & get_fifo_notFull[i*DN_SubTreeSz +: DN_SubTreeSz];
            get_fifo_enq_en[i*DN_SubTreeSz +: DN_SubTreeSz]  = st_outputGet_en[i];
            get_fifo_enq_val[i*DN_SubTreeSz +: DN_SubTreeSz] = st_outputGet_val[i];
            
        end
    end : connect_subtree_to_outputbuffer

    // ================================================================
    // putNewDest Interface
    // ================================================================
    assign ctrl_rdy_o     = st_putDest_rdy;
    assign st_putDest_en  = ctrl_en_i & st_putDest_rdy;
    assign st_putDest_val = ctrl_val_i;

    // ================================================================
    // putData Interface
    // ================================================================
    assign inputPut_rdy_o = put_fifo_notFull;

    // ================================================================
    // getData Interface
    // ================================================================
    assign outputGet_rdy_o = get_fifo_notEmpty;
    assign get_fifo_deq_en = outputGet_en_i & get_fifo_notEmpty;
    assign outputGet_val_o = get_fifo_first;

    // ================================================================
    // compute isEmpty
    // ================================================================
    assign isEmpty_val_o = (&st_isEmpty) & (~|put_fifo_notEmpty);

endmodule


// Test cases
//   TC1  – Reset behaviour
//   TC2  – isEmpty flag: all-empty after reset, clears on ingress, reasserts
//   TC3  – Single-lane unicast: one SubTree, one leaf destination
//   TC4  – all-lane unicast: every SubTree sends to its leaf[0]
//   TC5  – Single-lane multicast: one SubTree, multiple leaf destinations
//   TC6  – Broadcast: one SubTree, all leaves set
// ============================================================================
module tb_cellrv32_npu_distribution_network;
    // -----------------------------------------------------------------------
    // DUT port signals
    // -----------------------------------------------------------------------
    logic clk_i;
    logic rstn_i;

    logic                                        isEmpty_val_o;

    logic [DN_NumSubTrees-1:0]                   ctrl_en_i;
    logic [DN_NumSubTrees-1:0]                   ctrl_rdy_o;
    logic [DN_NumSubTrees-1:0][DN_SubTreeSz-1:0] ctrl_val_i;

    logic [DN_NumSubTrees-1:0]                   inputPut_en_i;
    logic [DN_NumSubTrees-1:0]                   inputPut_rdy_o;
    logic [DN_NumSubTrees-1:0][15:0]             inputPut_val_i;

    logic [NumMultSwitches-1:0]                  outputGet_en_i;
    logic [NumMultSwitches-1:0]                  outputGet_rdy_o;
    logic [NumMultSwitches-1:0][15:0]            outputGet_val_o;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    cellrv32_npu_distribution_network dut (
        .clk_i           (clk_i          ),
        .rstn_i          (rstn_i         ),
        .isEmpty_val_o   (isEmpty_val_o  ),
        .ctrl_en_i       (ctrl_en_i      ),
        .ctrl_rdy_o      (ctrl_rdy_o     ),
        .ctrl_val_i      (ctrl_val_i     ),
        .inputPut_en_i   (inputPut_en_i  ),
        .inputPut_rdy_o  (inputPut_rdy_o ),
        .inputPut_val_i  (inputPut_val_i ),
        .outputGet_en_i  (outputGet_en_i ),
        .outputGet_rdy_o (outputGet_rdy_o),
        .outputGet_val_o (outputGet_val_o)
    );

    // -----------------------------------------------------------------------
    // Clock  (10 ns period)
    // -----------------------------------------------------------------------
    initial clk_i = 0;
    always  #5 clk_i = ~clk_i;

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int tests_run  = 0;
    int tests_pass = 0;
    int tests_fail = 0;
    string current_tc;

    // -----------------------------------------------------------------------
    // Utility macros & tasks
    // -----------------------------------------------------------------------
    `define CHECK(label, expr) \
        begin \
            tests_run++; \
            if (expr) begin \
                tests_pass++; \
                $display("  [PASS]  %s", label); \
            end else begin \
                tests_fail++; \
                $display("  [FAIL]  %s  (at t=%0t)", label, $time); \
            end \
        end

    // Advance N clock cycles; settle 1 ns after edge
    task automatic clk_cycle(input int n = 1);
        repeat (n) @(posedge clk_i);
        #1;
    endtask

    // Set all driven inputs to idle
    task automatic idle_inputs();
        ctrl_en_i      = '0;
        ctrl_val_i     = '0;
        inputPut_en_i  = '0;
        inputPut_val_i = '0;
        outputGet_en_i = '0;
    endtask

    // Apply synchronous reset
    task automatic apply_reset(input int cycles = 6);
        rstn_i = 0;
        idle_inputs();
        clk_cycle(cycles);
        rstn_i = 1;
        clk_cycle(2);
    endtask

    // -----------------------------------------------------------------------
    // push_dest – push destination bitmask into one SubTree
    //   lane    : SubTree index 0..DN_NumSubTrees-1
    //   dest    : destination mask
    //   timeout : max wait cycles
    // -----------------------------------------------------------------------
    task automatic push_dest(input int lane,
                             input DN_SubTreeDestBits dest,
                             input int timeout = 200);
        int cnt = 0;
        ctrl_en_i [lane] = 1'b1;
        ctrl_val_i[lane] = dest;
        while (!ctrl_rdy_o[lane] && cnt < timeout) begin
            @(posedge clk_i); #1;
            cnt++;
        end
        @(posedge clk_i); #1;
        ctrl_en_i [lane] = 1'b0;
        ctrl_val_i[lane] = '0;
    endtask

    // -----------------------------------------------------------------------
    // push_data – push one 16-bit word into one buffer lane
    // lane : SubTree index 0..DN_NumSubTrees-1
    // data : 16-bit payload
    // -----------------------------------------------------------------------
    task automatic push_data(input int lane,
                             input logic [15:0] data,
                             input int timeout = 200);
        int cnt = 0;
        inputPut_en_i [lane] = 1'b1;
        inputPut_val_i[lane] = data;
        while (!inputPut_rdy_o[lane] && cnt < timeout) begin
            @(posedge clk_i); #1;
            cnt++;
        end
        @(posedge clk_i); #1;
        inputPut_en_i [lane] = 1'b0;
        inputPut_val_i[lane] = 16'd0;
    endtask

    // -----------------------------------------------------------------------
    // consume_outputs – wait for & drain output ports indicated by port_mask
    //   port_mask : NMS-bit mask of ports to watch
    //   out_vals  : captured data per port
    //   timeout   : max cycles to wait for every port in mask
    // -----------------------------------------------------------------------
    task automatic consume_outputs(
            input  logic [NumMultSwitches-1:0]       port_mask,
            output logic [NumMultSwitches-1:0][15:0] out_vals,
            input  int timeout = 400);
        logic [NumMultSwitches-1:0] done;
        int cnt;
        done     = '0;
        out_vals = 'x;
        cnt      = 0;
        while ((done & port_mask) != port_mask && cnt < timeout) begin
            // enable read on ready-and-not-yet-done ports within mask
            outputGet_en_i = outputGet_rdy_o & port_mask & ~done;
            #1;
            for (int p = 0; p < NumMultSwitches; p++) begin
                if (outputGet_en_i[p] && outputGet_rdy_o[p]) begin
                    out_vals[p] = outputGet_val_o[p];
                    done[p]     = 1;
                end
            end
            cnt++;
        end
        outputGet_en_i = '0;
    endtask

    // -----------------------------------------------------------------------
    // Helper: output port index  = lane * DN_SubTreeSz + leaf
    // -----------------------------------------------------------------------
    function automatic int port_idx(input int lane, input int leaf);
        return lane * DN_SubTreeSz + leaf;
    endfunction

    // -----------------------------------------------------------------------
    // Helper: build NumMultSwitches-bit port_mask from lane + DN_SubTreeSz-bit dest bitmask
    // -----------------------------------------------------------------------
    function automatic logic [NumMultSwitches-1:0] build_port_mask(
            input int          lane,
            input DN_SubTreeDestBits dest);
        logic [NumMultSwitches-1:0] m;
        m = '0;
        for (int leaf = 0; leaf < DN_SubTreeSz; leaf++)
            if (dest[leaf]) m[lane * DN_SubTreeSz + leaf] = 1;
        return m;
    endfunction

    // -----------------------------------------------------------------------
    // send_and_receive – combined helper for single-lane transactions
    //   lane   : SubTree index
    //   dest   : DN_SubTreeSz-bit leaf mask
    //   data   : 16-bit payload
    //   out_vals: captured NumMultSwitches-wide output array
    // -----------------------------------------------------------------------
    task automatic send_and_receive(
            input  int           lane,
            input  DN_SubTreeDestBits dest,
            input  logic [15:0]  data,
            output logic [NumMultSwitches-1:0][15:0] out_vals,
            input  int timeout = 400);
        logic [NumMultSwitches-1:0] pmask;
        pmask = build_port_mask(lane, dest);
        push_dest(lane, dest,  timeout);
        push_data(lane, data,  timeout);
        consume_outputs(pmask, out_vals, timeout);
    endtask

    // -----------------------------------------------------------------------
    // TC1: Reset behaviour
    // -----------------------------------------------------------------------
    task automatic tc1_reset();
        current_tc = "TC1: Reset behaviour";
        $display("\n=== %s ===", current_tc);
        apply_reset(8);

        `CHECK("TC1: isEmpty HIGH immediately after reset", isEmpty_val_o === 1'b1)
        `CHECK("TC1: ctrl_rdy_o all-ones after reset", ctrl_rdy_o === '1)
        `CHECK("TC1: inputPut_rdy_o all-ones after reset", inputPut_rdy_o === '1)
        `CHECK("TC1: outputGet_rdy_o all-zero after reset", outputGet_rdy_o === '0)
    endtask

    // -----------------------------------------------------------------------
    // TC2: isEmpty flag
    // -----------------------------------------------------------------------
    task automatic tc2_isEmpty();
        logic [NumMultSwitches-1:0][15:0] dummy;
        current_tc = "TC2: isEmpty flag";
        $display("\n=== %s ===", current_tc);
        apply_reset();

        `CHECK("TC2: isEmpty HIGH before any transaction", isEmpty_val_o === 1'b1)

        // Inject one packet – isEmpty must de-assert
        push_dest(0, {{(DN_SubTreeSz-1){1'b0}}, 1'b1});
        inputPut_en_i [0] = 1;
        inputPut_val_i[0] = 16'hABCD;
        @(posedge clk_i); #1;
        inputPut_en_i[0] = 0;
        clk_cycle(1);

        `CHECK("TC2: isEmpty LOW while data in-flight", isEmpty_val_o === 1'b0)

        // Drain output and give pipeline time to flush
        outputGet_en_i = '1;
        clk_cycle(60);
        outputGet_en_i = '0;
        clk_cycle(5);

        `CHECK("TC2: isEmpty HIGH after pipeline drained", isEmpty_val_o === 1'b1)
    endtask

    // -----------------------------------------------------------------------
    // TC3: Single-lane unicast (lane 0, leaf 0)
    // -----------------------------------------------------------------------
    task automatic tc3_unicast();
        logic [NumMultSwitches-1:0][15:0] out_vals;
        logic [DN_SubTreeSz-1:0]  dest;
        logic [15:0]    expected;
        int             prt;
        current_tc = "TC3: Single-lane unicast";

        $display("\n=== TC3: Single-lane unicast (lane 0 -> leaf 0) ===");
        apply_reset();

        dest     = {{(DN_SubTreeSz-1){1'b0}}, 1'b1}; // leaf 0 only
        expected = 16'hCAFE;
        prt      = port_idx(0, 0);

        send_and_receive(0, dest, expected, out_vals);

        `CHECK("TC3: correct data at output port [0]", out_vals[prt] === expected)
        
        // Spot-check that no other port received data
        `CHECK("TC3: port [1] empty (no leak)", outputGet_rdy_o[port_idx(0,1)] === 1'b0)
    endtask

    // -----------------------------------------------------------------------
    // TC4: All-lanes unicast – every SubTree sends to its leaf[0]
    // -----------------------------------------------------------------------
    task automatic tc4_all_lanes_unicast();
        logic [NumMultSwitches-1:0][15:0] out_vals;
        logic [NumMultSwitches-1:0] pmask;
        logic [DN_SubTreeSz-1:0] dest;
        logic all_ok;
        current_tc = "TC4: All-lanes unicast";

        $display("\n=== TC4: All-lanes unicast (%0d lanes -> each leaf 0) ===", DN_NumSubTrees);
        apply_reset();

        dest  = {{(DN_SubTreeSz-1){1'b0}}, 1'b1};
        pmask = '0;
        for (int l = 0; l < NumMultSwitches; l++) pmask[port_idx(l, 0)] = 1;

        // Push dests on all lanes simultaneously
        ctrl_val_i = '0;
        ctrl_en_i  = '0;
        for (int l = 0; l < DN_NumSubTrees; l++) begin
            ctrl_en_i [l] = 1;
            ctrl_val_i[l] = dest;
        end
        @(posedge clk_i); #1;
        ctrl_en_i = '0;

        // Push data on all lanes simultaneously
        for (int l = 0; l < DN_NumSubTrees; l++) begin
            inputPut_en_i [l] = 1;
            inputPut_val_i[l] = 16'(l + 1);
        end
        @(posedge clk_i); #1;
        inputPut_en_i = '0;

        consume_outputs(pmask, out_vals);

        all_ok = 1;
        for (int l = 0; l < DN_NumSubTrees; l++) begin
            int p = port_idx(l, 0);
            if (out_vals[p] !== 16'(l + 1)) all_ok = 0;
            $display(" TC4: lane %0d -> port %0d: expected %0h, got %0h", l, p, 16'(l + 1), out_vals[p]);
        end
        `CHECK("TC4: all NT output ports have correct unique values", all_ok)
    endtask

    // -----------------------------------------------------------------------
    // TC5: Multicast on one lane (lane 1, leaves 0,2,4)
    // -----------------------------------------------------------------------
    task automatic tc5_multicast();
        logic [NumMultSwitches-1:0][15:0] out_vals;
        logic [DN_SubTreeSz-1:0]  dest;
        logic [15:0]    expected;
        current_tc = "TC5: Multicast";

        $display("\n=== TC5: Multicast (lane 1, leaves 0,2,4) ===");
        apply_reset();

        dest     = 8'b0001_0101;   // leaves 0, 2, 4
        expected = 16'hBEEF;

        send_and_receive(1, dest, expected, out_vals);

        `CHECK("TC5: data on leaf 0 of lane 1",
                out_vals[port_idx(1,0)] === expected)
        `CHECK("TC5: data on leaf 2 of lane 1",
                out_vals[port_idx(1,2)] === expected)
        `CHECK("TC5: data on leaf 4 of lane 1",
                out_vals[port_idx(1,4)] === expected)
        `CHECK("TC5: leaf 1 of lane 1 empty",
                outputGet_rdy_o[port_idx(1,1)] === 1'b0)
        `CHECK("TC5: leaf 3 of lane 1 empty",
                outputGet_rdy_o[port_idx(1,3)] === 1'b0)
    endtask

    // -----------------------------------------------------------------------
    // TC6: Broadcast on one lane (lane 2, all leaves)
    // -----------------------------------------------------------------------
    task automatic tc6_broadcast();
        logic [NumMultSwitches-1:0][15:0] out_vals;
        logic [DN_SubTreeSz-1:0]  dest;
        logic [15:0]    expected;
        logic           all_ok;
        current_tc = "TC6: Broadcast";

        $display("\n=== TC6: Broadcast (lane 2, all leaves) ===");
        apply_reset();

        dest     = '1;
        expected = 16'hDEAD;

        send_and_receive(2, dest, expected, out_vals);

        all_ok = 1;
        for (int leaf = 0; leaf < DN_SubTreeSz; leaf++) begin
            if (out_vals[port_idx(2, leaf)] !== expected) all_ok = 0;
        end
        `CHECK("TC6: all leaves of lane 2 received broadcast correctly", all_ok)
    endtask

    // -----------------------------------------------------------------------
    // MAIN – run all test cases
    // -----------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display(" DistributionNetwork Testbench");
        $display(" NumSubTrees = %0d", DN_NumSubTrees);
        $display(" SubTreeSz   = %0d", DN_SubTreeSz);
        $display(" NumMulSw    = %0d", NumMultSwitches);
        $display("============================================================");

        // Safe initial state
        rstn_i         = 0;
        ctrl_en_i      = '0;
        ctrl_val_i     = '0;
        inputPut_en_i  = '0;
        inputPut_val_i = '0;
        outputGet_en_i = '0;

        // Run tests
        tc1_reset();
        tc2_isEmpty();
        tc3_unicast();
        tc4_all_lanes_unicast();
        tc5_multicast();
        tc6_broadcast();

        // Summary
        $display("\n============================================================");
        $display("  RESULTS: %0d / %0d passed  (%0d failed)",
                  tests_pass, tests_run, tests_fail);
        $display("============================================================");
        if (tests_fail == 0)
            $display("  *** ALL TESTS PASSED ***\n");
        else
            $display("  *** %0d TEST(S) FAILED - see [FAIL] lines above ***\n",
                      tests_fail);
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    initial begin
        #2_000_000;
        $display("[WATCHDOG] Simulation exceeded 2 ms - aborting");
        $finish;
    end

endmodule