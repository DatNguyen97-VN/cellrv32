// ################################################################################################################################################
// # << CELLRV32 - NPU Multiplier Switch NIC >>                                                                                                   #
// # ******************************************************************************************************************************************** #
// # This module functions as a Network Interface Controller (NIC) for the core switch, managing input, forwarding, and partial-sum data via      #
// # dedicated FIFO queues. It stores static data directly while buffering streaming, forwarding, and partial-sum data for subsequent processing. #
// # Control signals determine whether dynamic parameters are selected from the input data stream or the forwarding FIFO. The module supplies the #
// # selected data to the core switch's computation logic while maintaining a FIFO flow control mechanism using a "ready/enable" handshake.       #
// # ******************************************************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_multiplierswitch_NIC (
    input  logic        clk_i             ,
    input  logic        rstn_i            ,
    /* ---- controlPorts ---- */
    // putIptSelect
    input  logic        putIptSelect_en_i ,
    input  MS_IptSelect putIptSelect_val_i,  
    // putFwdSelect
    input  logic        putFwdSelect_en_i ,
    input  MS_FwdSelect putFwdSelect_val_i, 
    // putArgSelect
    input  logic        putArgSelect_en_i ,
    input  MS_ArgSelect putArgSelect_val_i,
    /* ---- dataPorts ---- */
    // putIptData
    input  logic        putIptData_en_i   ,
    output logic        putIptData_rdy_o  ,
    input  INT16        putIptData_val_i  ,
    // putFwdData
    input  logic        putFwdData_en_i   ,
    output logic        putFwdData_rdy_o  ,
    input  INT16        putFwdData_val_i  ,
    // putPSum
    input  logic        putPSum_en_i      ,
    output logic        putPSum_rdy_o     ,
    input  INT16        putPSum_val_i     ,
    /* ---- Output Ports ---- */
    // getStationaryArgument
    output INT16        getStat_val_o     ,
    // getDynamicArgument
    input  logic        getDynArg_en_i    ,
    output logic        getDynArg_rdy_o   ,
    output INT16        getDynArg_val_o   ,
    // getPSum
    input  logic        getPSum_en_i      ,
    output logic        getPSum_rdy_o     ,
    output INT16        getPSum_val_o     ,
    // getFwdData
    output logic        getFwdData_rdy_o  ,
    output INT16        getFwdData_val_o
);

    /* Control singal wires */
    logic        iptSel_en;
    MS_IptSelect iptSel_val;

    assign iptSel_en  = putIptSelect_en_i;
    assign iptSel_val = putIptSelect_val_i;

    logic        fwdSel_en;
    MS_FwdSelect fwdSel_val;

    assign fwdSel_en  = putFwdSelect_en_i;
    assign fwdSel_val = putFwdSelect_val_i;

    logic        argSel_en;
    MS_ArgSelect argSel_val;

    assign argSel_en  = putArgSelect_en_i;
    assign argSel_val = putArgSelect_val_i;

    // ----------------------------------------------------------------
    // stationaryData
    // ----------------------------------------------------------------
    INT16 stationaryData;

    // ----------------------------------------------------------------
    // streamData buffer
    // ----------------------------------------------------------------
    logic stream_enq_en, stream_notFull;
    INT16 stream_enq_val;
    logic stream_deq_en, stream_notEmpty;
    INT16 stream_first;

    PipelineFifo #(
      .T     (INT16              ),
      .DEPTH (MS_IngressFifoDepth)
    ) streamData (
      .clk_i       (clk_i          ),        
      .rstn_i      (rstn_i         ),
      .enq_en_i    (stream_enq_en  ),  
      .notFull_o   (stream_notFull ),
      .enq_val_i   (stream_enq_val ),
      .deq_en_i    (stream_deq_en  ),  
      .notEmpty_o  (stream_notEmpty),
      .first_val_o (stream_first   )
    );

    // ----------------------------------------------------------------
    // fwdData buffer
    // ----------------------------------------------------------------
    logic fwd_enq_en, fwd_notFull;
    INT16 fwd_enq_val;
    logic fwd_deq_en, fwd_notEmpty;
    INT16 fwd_first;

    PipelineFifo #(
      .T     (INT16          ),
      .DEPTH (MS_FwdFifoDepth)
    ) fwdData (
      .clk_i       (clk_i       ),        
      .rstn_i      (rstn_i      ),
      .enq_en_i    (fwd_enq_en  ),  
      .notFull_o   (fwd_notFull ),
      .enq_val_i   (fwd_enq_val ),
      .deq_en_i    (fwd_deq_en  ),  
      .notEmpty_o  (fwd_notEmpty),
      .first_val_o (fwd_first   )
    );

    // ----------------------------------------------------------------
    // pSumData buffer
    // ----------------------------------------------------------------
    logic psum_enq_en, psum_notFull;
    INT16 psum_enq_val;
    logic psum_deq_en, psum_notEmpty;
    INT16 psum_first;

    PipelineFifo #(
      .T     (INT16           ),
      .DEPTH (MS_PSumFifoDepth)
    ) pSumData (
      .clk_i       (clk_i        ),        
      .rstn_i      (rstn_i       ),
      .enq_en_i    (psum_enq_en  ),  
      .notFull_o   (psum_notFull ),
      .enq_val_i   (psum_enq_val ),
      .deq_en_i    (psum_deq_en  ),  
      .notEmpty_o  (psum_notEmpty),
      .first_val_o (psum_first   )
    );

    // ================================================================
    // dataPorts
    // ================================================================
    // ----------------------------------------------------------------
    // putIptData
    // ----------------------------------------------------------------
    assign putIptData_rdy_o = (iptSel_val == MS_IPT_STATIONARY) || ((iptSel_val == MS_IPT_STREAM) & stream_notFull);
    assign stream_enq_en = putIptData_en_i & iptSel_en & (iptSel_val == MS_IPT_STREAM) & stream_notFull;
    assign stream_enq_val = putIptData_val_i;

    // stationaryData update (sequential)
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            stationaryData <= '0;
        end else if (iptSel_en && (iptSel_val == MS_IPT_STATIONARY) && putIptData_en_i) begin
            stationaryData <= putIptData_val_i;
        end
    end

    // ----------------------------------------------------------------
    // putFwdData
    // ----------------------------------------------------------------
    assign putFwdData_rdy_o = fwd_notFull;
    assign fwd_enq_en       = putFwdData_en_i & fwd_notFull;
    assign fwd_enq_val      = putFwdData_val_i;

    // ----------------------------------------------------------------
    // putPSum
    // ----------------------------------------------------------------
    assign putPSum_rdy_o = psum_notFull;
    assign psum_enq_en   = putPSum_en_i & psum_notFull;
    assign psum_enq_val  = putPSum_val_i;

    // ----------------------------------------------------------------
    // getStationaryArgument
    // ----------------------------------------------------------------
    assign getStat_val_o = stationaryData;

    // ----------------------------------------------------------------
    // getDynamicArgument
    // ----------------------------------------------------------------
    always_comb begin
        case (argSel_val)
            MS_ARG_INPUT : begin
                getDynArg_rdy_o = stream_notEmpty;
                getDynArg_val_o = stream_first;
                stream_deq_en   = stream_notEmpty & getDynArg_en_i;
                fwd_deq_en      = 1'b0;
            end
            MS_ARG_FWD : begin
                getDynArg_rdy_o = fwd_notEmpty;
                getDynArg_val_o = fwd_first;
                stream_deq_en   = 1'b0;
                fwd_deq_en      = fwd_notEmpty & getDynArg_en_i;
            end
            default : begin
                getDynArg_rdy_o = 1'b0;
                getDynArg_val_o = '0;
                stream_deq_en   = 1'b0;
                fwd_deq_en      = 1'b0;
            end
        endcase
    end

    // ----------------------------------------------------------------
    // getPSum
    // ----------------------------------------------------------------
    assign getPSum_rdy_o = psum_notEmpty;
    assign getPSum_val_o = psum_first;
    assign psum_deq_en   = getPSum_en_i & psum_notEmpty;

    // ----------------------------------------------------------------
    // getFwdData
    // ----------------------------------------------------------------
    assign getFwdData_rdy_o = getDynArg_rdy_o;

    always_comb begin
        case (fwdSel_val)
            MS_FWD_INPUT : begin
                getFwdData_val_o = stream_first;
            end
            MS_FWD_FWD : begin
                getFwdData_val_o = fwd_first;
            end
            default: begin
                getFwdData_val_o = '0;
            end
        endcase
    end

endmodule


// ================================================================
// Testbench
// ================================================================
module tb_cellrv32_npu_multiplierswitch_NIC;

    localparam int DW = 16;

    logic clk_i, rstn_i;
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // controlPorts
    logic       putIptSel_en;  MS_IptSelect putIptSel_val;
    logic       putFwdSel_en;  MS_FwdSelect putFwdSel_val;
    logic       putArgSel_en;  MS_ArgSelect putArgSel_val;

    // dataPorts
    logic          putIptData_en_i,  putIptData_rdy_o; logic [DW-1:0] putIptData_val_i;
    logic          putFwdData_en_i,  putFwdData_rdy_o;
                                                       logic [DW-1:0] putFwdData_val_i;
    logic          putPSum_en_i,     putPSum_rdy_o;    logic [DW-1:0] putPSum_val_i;
                                                       logic [DW-1:0] getStat_val_o;
    logic          getDynArg_en_i,   getDynArg_rdy_o;
                                                       logic [DW-1:0] getDynArg_val_o;
    logic          getPSum_en_i,     getPSum_rdy_o;    logic [DW-1:0] getPSum_val_o;
    logic          getFwdData_rdy_o;
                                                       logic [DW-1:0] getFwdData_val_o;

    cellrv32_npu_multiplierswitch_NIC dut (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .putIptSelect_en_i(putIptSel_en),     .putIptSelect_val_i(putIptSel_val),
        .putFwdSelect_en_i(putFwdSel_en),     .putFwdSelect_val_i(putFwdSel_val),
        .putArgSelect_en_i(putArgSel_en),     .putArgSelect_val_i(putArgSel_val),
        .putIptData_en_i(putIptData_en_i),    .putIptData_rdy_o(putIptData_rdy_o),
        .putIptData_val_i(putIptData_val_i),
        .putFwdData_en_i(putFwdData_en_i),    .putFwdData_rdy_o(putFwdData_rdy_o),
        .putFwdData_val_i(putFwdData_val_i),
        .putPSum_en_i(putPSum_en_i),          .putPSum_rdy_o(putPSum_rdy_o),
        .putPSum_val_i(putPSum_val_i),
        .getStat_val_o(getStat_val_o),
        .getDynArg_en_i(getDynArg_en_i),      .getDynArg_rdy_o(getDynArg_rdy_o),
        .getDynArg_val_o(getDynArg_val_o),
        .getPSum_en_i(getPSum_en_i),          .getPSum_rdy_o(getPSum_rdy_o),
        .getPSum_val_o(getPSum_val_o),
        .getFwdData_rdy_o(getFwdData_rdy_o),
        .getFwdData_val_o(getFwdData_val_o)
    );

    // Helper: set control signals
    task automatic set_sel(input logic [1:0] ipt, input logic [1:0] fwd, input logic [1:0] arg);
        putIptSel_en = (ipt !== 2'bXX); putIptSel_val = MS_IptSelect'(ipt);
        putFwdSel_en = (fwd !== 2'bXX); putFwdSel_val = MS_FwdSelect'(fwd);
        putArgSel_en = (arg !== 2'bXX); putArgSel_val = MS_ArgSelect'(arg);
    endtask

    initial begin
        rstn_i = 0;
        {putIptSel_en, putFwdSel_en, putArgSel_en} = '0;
        putIptSel_val = MS_IPT_NOTHING;
        putFwdSel_val = MS_FWD_NOTHING;
        putArgSel_val = MS_ARG_NOTHING;
        putIptData_en_i = 0; putFwdData_en_i = 0; putPSum_en_i = 0;
        getDynArg_en_i = 0; getPSum_en_i = 0;

        repeat (3) @(posedge clk_i); 
        rstn_i = 1; 
        @(posedge clk_i);

        // === TC1: putIptData stationary ===
        $display("\n=== TC1: putIptData -> stationary ===");
        @(posedge clk_i);
        set_sel(2'b01, 2'bXX, 2'bXX);  // iptSel=stationary
        putIptData_en_i  = 1; putIptData_val_i = 16'hAAAA;
        @(posedge clk_i);
        @(negedge clk_i);
        putIptData_en_i = 0; {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;
        @(posedge clk_i); #1;
        $display(" getStat_val_o= 0x%04X (expect 0xAAAA)", getStat_val_o);

        // === TC2: putIptData stream, getDynamicArgument argInput ===
        $display("\n=== TC2: putIptData -> stream, getDynArg=argInput ===");
        @(posedge clk_i);
        set_sel(2'b10, 2'bXX, 2'bXX);  // iptSel=stream
        putIptData_en_i  = 1; putIptData_val_i = 16'hBBBB;
        @(posedge clk_i);
        @(negedge clk_i); putIptData_en_i = 0; {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;

        @(posedge clk_i);
        set_sel(2'bXX, 2'bXX, 2'b01);  // argSel=argInput
        getDynArg_en_i = 1;
        #1;
        $display(" getDynArg_rdy_o=%b val=0x%04X (expect 1, 0xBBBB)", getDynArg_rdy_o, getDynArg_val_o);
        @(posedge clk_i);
        @(negedge clk_i); getDynArg_en_i = 0; {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;

        // === TC3: putFwdData, getFwdData (peek), getDynArg=argFwd ===
        $display("\n=== TC3: putFwdData -> peek getFwdData -> getDynArg=argFwd ===");
        @(posedge clk_i);
        set_sel(2'bXX, 2'b01, 2'bXX);  // fwdSel=fwdInput
        putFwdData_en_i = 1; putFwdData_val_i = 16'hCCCC;
        @(posedge clk_i);
        @(negedge clk_i); putFwdData_en_i = 0; {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;

        // Enqueue fwdData via stream path (fwdSel=fwdFwd enq from fwd FIFO)
        // putFwdData enq into fwd FIFO within fwdSel valid
        @(posedge clk_i);
        set_sel(2'bXX, 2'b10, 2'bXX);  // fwdSel=fwdFwd: getFwdData peek fwdData
        #1;
        $display("  getFwdData_rdy_o=%b val=0x%04X", getFwdData_rdy_o, getFwdData_val_o);
        @(negedge clk_i); {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;

        // getDynArg = argFwd for deq
        @(posedge clk_i);
        set_sel(2'bXX, 2'bXX, 2'b10);  // argSel=argFwd
        getDynArg_en_i = 1;
        #1;
        $display("  getDynArg argFwd: val=0x%04X (expect 1,0xCCCC)", getDynArg_val_o);
        @(posedge clk_i);
        @(negedge clk_i); getDynArg_en_i = 0; {putIptSel_en,putFwdSel_en,putArgSel_en} = '0;

        // === TC4: putPSum / getPSum ===
        $display("\n=== TC4: putPSum / getPSum ===");
        @(posedge clk_i);
        putPSum_en_i = 1; putPSum_val_i = 16'hDDDD;
        @(posedge clk_i);
        @(negedge clk_i); putPSum_en_i = 0;

        @(posedge clk_i);
        getPSum_en_i = 1;
        #1;
        $display("  getPSum_rdy_o=%b val=0x%04X (expect 1,0xDDDD)", getPSum_rdy_o, getPSum_val_o);
        @(negedge clk_i); getPSum_en_i = 0;

        // === TC5: getDynArg when argSel not valid → rdy=0 ===
        $display("\n=== TC5: getDynArg blocked when argSel is not available ===");
        @(posedge clk_i);
        getDynArg_en_i = 1;  // argSel_en=0 → rdy=0
        #1;
        $display("  getDynArg_rdy_o=%b (expect 0, no argSel)", getDynArg_rdy_o);
        @(posedge clk_i);
        @(negedge clk_i); getDynArg_en_i = 0;

        repeat (3) @(posedge clk_i);
        $display("\n=== Done ===");
        $finish;
    end

endmodule