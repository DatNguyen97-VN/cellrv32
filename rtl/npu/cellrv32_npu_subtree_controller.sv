`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_subtree_controller (
    input  logic             clk_i                  ,
    input  logic             rstn_i                 ,
    // put new data
    input  logic              putNewDests_en_i      ,
    output logic              putNewDests_rdy_o     ,
    input  DN_SubTreeDestBits putNewDests_val_i     ,
    // put ack signal
    input  logic              putAckSignal_en_i     ,
    output logic              putAckSignal_rdy_o    ,
    // get epoch signal
    output logic              getEpoch_val_o        ,
    // get configuration
    input  logic              getConfiguration_en_i ,
    output logic              getConfiguration_rdy_o,
    output DN_SubTreeConfig   getConfiguration_val_o
);
    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    logic epochReg;
    logic readyForNewData;
 
    // ----------------------------------------------------------------
    // incomingDestBits
    // ----------------------------------------------------------------
    logic              idb_enq_en,  idb_notFull;
    logic              idb_deq_en,  idb_notEmpty;
    DN_SubTreeDestBits idb_enq_val, idb_first;

    PipelineFifo #(
      .T     (DN_SubTreeDestBits               ),
      .DEPTH (DN_SubTreeIngressControlFifoDepth)
    ) incomingDestBits (
      .clk_i       (clk_i       ),        
      .rstn_i      (rstn_i      ),
      .enq_en_i    (idb_enq_en  ),  
      .notFull_o   (idb_notFull ),
      .enq_val_i   (idb_enq_val ),
      .deq_en_i    (idb_deq_en  ),  
      .notEmpty_o  (idb_notEmpty),
      .first_val_o (idb_first   )
    );
 
    // ----------------------------------------------------------------
    // outConfigSignals
    // ----------------------------------------------------------------
    logic            ocs_enq_en,  ocs_notFull;
    logic            ocs_deq_en,  ocs_notEmpty;
    DN_SubTreeConfig ocs_enq_val, ocs_first;

    PipelineFifo #(
      .T     (DN_SubTreeConfig                ),
      .DEPTH (DN_SubTreeEgressControlFifoDepth)
    ) outConfigSignals (
      .clk_i       (clk_i       ),        
      .rstn_i      (rstn_i      ),
      .enq_en_i    (ocs_enq_en  ),  
      .notFull_o   (ocs_notFull ),
      .enq_val_i   (ocs_enq_val ),
      .deq_en_i    (ocs_deq_en  ),  
      .notEmpty_o  (ocs_notEmpty),
      .first_val_o (ocs_first   )
    );

    // ================================================================
    // compute Config Signals
    // ================================================================
    DN_SubTreeConfig computed_config;

    localparam int lastlv = DN_NumSubTreeLvs - 1;
    localparam int lastLvFirstNodeID = 2 ** lastlv - 1;
    localparam int numNodesInLastLv = 2 ** lastlv;

    always_comb begin : compute_Config_Signals
      for (int node = 0; node < numNodesInLastLv; node++) begin : compute_lastlv
        // Compute configuration signals for each node in the last level
        // right and left leafs 
        // leftFwd  = idb_first[2*node];
        // rightFwd = idb_first[2*node + 1];

        if (idb_first[2*node] && idb_first[2*node + 1]) begin
          computed_config[lastLvFirstNodeID + node] = DS_BOTH;
        end else if (idb_first[2*node]) begin
          computed_config[lastLvFirstNodeID + node] = DS_LEFT;
        end else if (idb_first[2*node + 1]) begin
          computed_config[lastLvFirstNodeID + node] = DS_RIGHT;
        end else begin
          computed_config[lastLvFirstNodeID + node] = DS_IDLE;
        end
      end : compute_lastlv
      //
      for (int lv = DN_NumSubTreeLvs - 2; lv >= 0; lv--) begin : compute_upperlv
        automatic int lvFirstNodeID = 2 ** lv - 1;
        automatic int nextLvFirstNodeID = 2 ** (lv + 1) - 1;
        automatic int numNodesInLv = 2 ** lv;

        for (int node = 0; node < numNodesInLv; node++) begin
          automatic int nodeID       = lvFirstNodeID + node;
          automatic int leftChildID  = nextLvFirstNodeID + 2 * node;
          automatic int rightChildID = leftChildID + 1;

          // leftFwd  = computed_config[leftChildID];
          // rightFwd = computed_config[rightChildID];
          if (|computed_config[leftChildID] && |computed_config[rightChildID]) begin
            computed_config[nodeID] = DS_BOTH;
          end else if (|computed_config[leftChildID]) begin
            computed_config[nodeID] = DS_LEFT;
          end else if (|computed_config[rightChildID]) begin
            computed_config[nodeID] = DS_RIGHT;
          end else begin
            computed_config[nodeID] = DS_IDLE;
          end
        end
      end : compute_upperlv
    end : compute_Config_Signals

    // ================================================================
    // generate Config Signals
    // ================================================================
    assign idb_deq_en  = idb_notEmpty & ocs_notFull;
    assign ocs_enq_en  = idb_deq_en;
    assign ocs_enq_val = computed_config;

    // ================================================================
    // Sequential: epochReg, readyForNewData
    // ================================================================
    always_ff @(posedge clk_i or negedge rstn_i) begin   
      if (!rstn_i) begin
        epochReg        <= dn_initEpoch;
        readyForNewData <= 1'b1;
      end else begin
        // getConfiguration
        if (getConfiguration_en_i && getConfiguration_rdy_o) begin
          epochReg        <= ~epochReg;
          readyForNewData <= 1'b0;
        end else if (putAckSignal_en_i && putAckSignal_rdy_o) begin
          // putAckSignal
          readyForNewData <= 1'b1;
        end
      end
    end

    // ================================================================
    // putNewDests
    // ================================================================
    assign putNewDests_rdy_o = idb_notFull;
    assign idb_enq_en        = putNewDests_en_i & idb_notFull;
    assign idb_enq_val       = putNewDests_val_i;
 
    // ================================================================
    // ready for putAckSignal
    // ================================================================
    assign putAckSignal_rdy_o = ~readyForNewData;
 
    // ================================================================
    // getEpoch
    // ================================================================
    assign getEpoch_val_o = epochReg;
 
    // ================================================================
    // getConfiguration
    // ================================================================
    assign getConfiguration_rdy_o = readyForNewData & ocs_notEmpty;
    assign getConfiguration_val_o = ocs_first;
    assign ocs_deq_en             = getConfiguration_en_i & getConfiguration_rdy_o;

endmodule