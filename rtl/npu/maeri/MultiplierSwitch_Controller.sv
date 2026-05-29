`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module MultiplierSwitch_Controller (
    input  logic        clk_i                 ,
    input  logic        rstn_i                ,
    // putNewConfig
    input  logic        putNewConfig_en_i     ,
    output logic        putNewConfig_rdy_o    ,
    input  MS_Config    putNewConfig_val_i    ,
    // putPSumGenNotice
    input  logic        putPSumGenNotice_en_i ,
    output logic        putPSumGenNotice_rdy_o,
    // get Input Select
    output MS_IptSelect getIptSelect_val_o    ,
    // get Forward Select
    output MS_FwdSelect getFwdSelect_val_o    ,
    // get Argument Select
    output MS_ArgSelect getArgSelect_val_o    ,
    // get Do Compute
    output logic        getDoCompute_val_o
);
    MS_State     stateReg;
    MS_PSumCount pSumCounter;
    // ----------------------------------------------------------------
    // Buufers for incoming config
    // ----------------------------------------------------------------
    logic    ins_enq_en, ins_notFull, ins_deq_en, ins_notEmpty;
    MS_State ins_enq_val, ins_first;

    PipelineFifo #(
      .T     (MS_State       ),
      .DEPTH (2              )
    ) incomingNextState (
      .clk_i       (clk_i       ),
      .rstn_i      (rstn_i      ),
      .enq_en_i    (ins_enq_en  ),
      .notFull_o   (ins_notFull ),
      .enq_val_i   (ins_enq_val ),
      .deq_en_i    (ins_deq_en  ),
      .notEmpty_o  (ins_notEmpty),
      .first_val_o (ins_first   )
    );

    // ----------------------------------------------------------------
    // Buufers for incoming pSumCount
    // ----------------------------------------------------------------
    logic        inpc_enq_en, inpc_notFull, inpc_deq_en, inpc_notEmpty;
    MS_PSumCount inpc_enq_val, inpc_first;

    PipelineFifo #(
      .T     (MS_PSumCount       ),
      .DEPTH (2                  )
    ) incomingNextPSumCount (
      .clk_i       (clk_i        ),
      .rstn_i      (rstn_i       ),
      .enq_en_i    (inpc_enq_en  ),
      .notFull_o   (inpc_notFull ),
      .enq_val_i   (inpc_enq_val ),
      .deq_en_i    (inpc_deq_en  ),
      .notEmpty_o  (inpc_notEmpty),
      .first_val_o (inpc_first   )
    );

    // ================================================================
    // Combinational Logic
    // ================================================================

    // computeIptSelect
    always_comb begin : iptSelect
        case (stateReg)
            MS_IDLE             : getIptSelect_val_o = MS_IPT_NOTHING;
            MS_INIT_STEADY_VAL  : getIptSelect_val_o = MS_IPT_STATIONARY;
            MS_RUN_LEDGE_FIRST  : getIptSelect_val_o = MS_IPT_STREAM;
            MS_RUN_LEDGE        : getIptSelect_val_o = MS_IPT_STREAM;
            MS_RUN_MIDDLE_FIRST : getIptSelect_val_o = MS_IPT_STREAM;
            MS_RUN_MIDDLE       : getIptSelect_val_o = MS_IPT_NOTHING;
            MS_RUN_REDGE_FIRST  : getIptSelect_val_o = MS_IPT_STREAM;
            MS_RUN_REDGE        : getIptSelect_val_o = MS_IPT_NOTHING;
            default             : getIptSelect_val_o = MS_IPT_NOTHING;
        endcase
    end : iptSelect

    // computeFwdSelect
    always_comb begin : fwdSelect
        case (stateReg)
            MS_IDLE            : getFwdSelect_val_o = MS_FWD_NOTHING;
            MS_INIT_STEADY_VAL : getFwdSelect_val_o = MS_FWD_NOTHING;
            MS_RUN_LEDGE_FIRST : getFwdSelect_val_o = MS_FWD_INPUT;
            MS_RUN_LEDGE       : getFwdSelect_val_o = MS_FWD_INPUT;
            MS_RUN_MIDDLE_FIRST: getFwdSelect_val_o = MS_FWD_INPUT;
            MS_RUN_MIDDLE      : getFwdSelect_val_o = MS_FWD_FWD;
            MS_RUN_REDGE_FIRST : getFwdSelect_val_o = MS_FWD_NOTHING;
            MS_RUN_REDGE       : getFwdSelect_val_o = MS_FWD_NOTHING;
            default            : getFwdSelect_val_o = MS_FWD_NOTHING;
        endcase
    end : fwdSelect

    // computeArgSelect
    always_comb begin : argSelect
        case (stateReg)
            MS_IDLE            : getArgSelect_val_o = MS_ARG_NOTHING;
            MS_INIT_STEADY_VAL : getArgSelect_val_o = MS_ARG_NOTHING;
            MS_RUN_LEDGE_FIRST : getArgSelect_val_o = MS_ARG_INPUT;
            MS_RUN_LEDGE       : getArgSelect_val_o = MS_ARG_INPUT;
            MS_RUN_MIDDLE_FIRST: getArgSelect_val_o = MS_ARG_INPUT;
            MS_RUN_MIDDLE      : getArgSelect_val_o = MS_ARG_FWD;
            MS_RUN_REDGE_FIRST : getArgSelect_val_o = MS_ARG_INPUT;
            MS_RUN_REDGE       : getArgSelect_val_o = MS_ARG_FWD;
            default            : getArgSelect_val_o = MS_ARG_FWD;
        endcase
    end : argSelect

    // function Bool computeDoCompute
    always_comb begin : doCompute
        case (stateReg)
            MS_IDLE            : getDoCompute_val_o = 1'b0;
            MS_INIT_STEADY_VAL : getDoCompute_val_o = 1'b0;
            MS_RUN_LEDGE_FIRST : getDoCompute_val_o = 1'b1;
            MS_RUN_LEDGE       : getDoCompute_val_o = 1'b1;
            MS_RUN_MIDDLE_FIRST: getDoCompute_val_o = 1'b1;
            MS_RUN_MIDDLE      : getDoCompute_val_o = 1'b1;
            MS_RUN_REDGE_FIRST : getDoCompute_val_o = 1'b1;
            MS_RUN_REDGE       : getDoCompute_val_o = 1'b1;
            default            : getDoCompute_val_o = 1'b0;
        endcase
    end : doCompute

    // ================================================================
    // Sequential: stateReg, pSumCounter
    // ================================================================
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            stateReg    <= MS_IDLE;
            pSumCounter <= 16'b0;
        end else begin
            if (pSumCounter == '0) begin
                if (ins_notEmpty && inpc_notEmpty) begin
                    stateReg    <= ins_first;
                    pSumCounter <= inpc_first;
                end
            end else begin
                case (stateReg)
                    MS_RUN_LEDGE_FIRST : stateReg <= MS_RUN_LEDGE;
                    MS_RUN_MIDDLE_FIRST: stateReg <= MS_RUN_MIDDLE;
                    MS_RUN_REDGE_FIRST : stateReg <= MS_RUN_REDGE;
                    default:             stateReg <= stateReg;
                endcase
            end
            // --------------------------------------------------------
            if (putPSumGenNotice_en_i && putPSumGenNotice_rdy_o) begin
                pSumCounter <= pSumCounter - 16'b1;
            end
        end
    end

    // ================================================================
    // FIFO control signals
    // ================================================================
    // read data from FIFOs when pSumCounter == 0
    assign ins_deq_en  = (pSumCounter == '0) & ins_notEmpty & inpc_notEmpty;
    assign inpc_deq_en = (pSumCounter == '0) & ins_notEmpty & inpc_notEmpty;

    // write data to FIFOs when it is available
    assign putNewConfig_rdy_o = ins_notFull & inpc_notFull;
    assign ins_enq_en         = putNewConfig_en_i & putNewConfig_rdy_o;
    assign ins_enq_val        = putNewConfig_val_i.state;
    assign inpc_enq_en        = putNewConfig_en_i & putNewConfig_rdy_o;
    assign inpc_enq_val       = putNewConfig_val_i.psumCount;

    // putPSumGenNotice
    assign putPSumGenNotice_rdy_o = (pSumCounter != '0);

endmodule


// ================================================================
// Testbench
// ================================================================
module tb_MN_MultiplierSwitch_Controller;

    localparam int CW = 19;  // MS_CONFIG_W

    logic        clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    logic          putCfg_en,    putCfg_rdy;
    logic [CW-1:0] putCfg_val;
    logic          putPSum_en,   putPSum_rdy;
    logic [1:0]    ipt_val, fwd_val, arg_val;
    logic          doCompute_val;

    MultiplierSwitch_Controller dut (
        .clk_i                  (clk),
        .rstn_i                 (rst_n),
        .putNewConfig_en_i      (putCfg_en),
        .putNewConfig_rdy_o     (putCfg_rdy),
        .putNewConfig_val_i     (putCfg_val),
        .putPSumGenNotice_en_i  (putPSum_en),
        .putPSumGenNotice_rdy_o (putPSum_rdy),
        .getIptSelect_val_o     (ipt_val),
        .getFwdSelect_val_o     (fwd_val),
        .getArgSelect_val_o     (arg_val),
        .getDoCompute_val_o     (doCompute_val)
    );

    // Helper: build MS_Config
    function automatic logic [CW-1:0] make_config(
        input logic [2:0]  state,
        input logic [15:0] psum_count
    );
        return {state, psum_count};
    endfunction

    task automatic send_config(
        input logic [2:0]  state,
        input logic [15:0] psum_cnt
    );
        @(posedge clk);
        putCfg_en  = putCfg_rdy;
        putCfg_val = make_config(state, psum_cnt);
        if (putCfg_rdy)
            $display("[CFG ] state=%04b psumCnt=%0d  rdy=%b", state, psum_cnt, putCfg_rdy);
        else
            $display("[CFG ] BLOCKED");
        @(posedge clk); putCfg_en = 0;
    endtask

    task automatic send_psum_notice(input int count = 1);
        for (int i = 0; i < count; i++) begin
            @(posedge clk);
            putPSum_en = putPSum_rdy;
            if (putPSum_rdy)
                $display("[PSUM] notice sent  pSumCounter_rdy=%b", putPSum_rdy);
            else
                $display("[PSUM] BLOCKED (pSumCounter==0)");
            @(posedge clk); putPSum_en = 0;
        end
    endtask

    task automatic print_outputs(input string label);
        #1;
        $display("[OUT ] %s  ipt=%02b fwd=%02b arg=%02b doCompute=%b",
                 label, ipt_val, fwd_val, arg_val, doCompute_val);
    endtask

    initial begin
        rst_n = 0; putCfg_en = 0; putCfg_val = '0; putPSum_en = 0;
        repeat (3) @(posedge clk); rst_n = 1; @(posedge clk);

        // === TC1: state after reset = ms_idle ===
        $display("\n=== TC1: Reset -> ms_idle ===");
        print_outputs("idle");
        // ipt=00(nothing), fwd=00(nothing), arg=00(nothing), doCompute=0

        // === TC2: ms_initSteadyVal ===
        $display("\n=== TC2: ms_initSteadyVal ===");
        send_config(3'b001, 16'd0);  // psumCount=0 -> updateState can fire
        repeat (3) @(posedge clk);
        print_outputs("initSteadyVal");
        // ipt=01(stationary), fwd=00(nothing), arg=00(nothing), doCompute=0

        // === TC3: ms_runLEdgeFirst -> ms_runLEdge (transit) ===
        $display("\n=== TC3: ms_runLEdgeFirst -> transit -> ms_runLEdge ===");
        send_config(3'b010, 16'd3);  // LEdgeFirst, psumCount=3
        repeat (3) @(posedge clk);
        print_outputs("runLEdgeFirst");
        @(posedge clk); #1;
        print_outputs("runLEdge (after transit)");

        // === TC4: putPSumGenNotice giảm pSumCounter ===
        $display("\n=== TC4: putPSumGenNotice ===");
        send_psum_notice(3);
        repeat (3) @(posedge clk);
        print_outputs("after 3 psum notices");

        // === TC5: ms_runMiddleFirst -> ms_runMiddle ===
        $display("\n=== TC5: ms_runMiddleFirst ===");
        send_config(3'b100, 16'd2);
        repeat (2) @(posedge clk);
        print_outputs("runMiddleFirst");
        @(posedge clk); #1;
        print_outputs("runMiddle (after transit)");

        // === TC6: ms_runREdgeFirst -> ms_runREdge ===
        $display("\n=== TC6: ms_runREdgeFirst ===");
        send_psum_notice(2);  // drain psumCount trước
        send_config(3'b110, 16'd1);
        repeat (2) @(posedge clk);
        print_outputs("runREdgeFirst");
        @(posedge clk); #1;
        print_outputs("runREdge (after transit)");

        // === TC7: putPSumGenNotice khi pSumCounter==0 -> blocked ===
        $display("\n=== TC7: putPSumGenNotice blocked khi counter=0 ===");
        send_psum_notice(1);  // drain psumCount=1
        send_psum_notice(1);  // block (pSumCounter=0)

        // === TC8: putNewConfig khi busy (notFull test) ===
        $display("\n=== TC8: putNewConfig quadra send ===");
        send_config(3'b001, 16'd5);
        send_config(3'b010, 16'd3);
        send_config(3'b010, 16'd1);
        send_config(3'b010, 16'd1); // block (notFull=0)

        repeat (5) @(posedge clk);
        $display("\n=== Done ===");
        $finish;
    end

endmodule