`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_subtree_ingress_NIC (
    input  logic        clk_i         ,
    input  logic        rstn_i        ,
    // putData
    input  logic        putData_en_i  ,
    output logic        putData_rdy_o ,
    input  logic [15:0] putData_val_i ,
    // getData
    input  logic        getData_en_i  ,
    output logic        getData_rdy_o ,
    output logic [15:0] getData_val_o ,
    // getEpoch
    output logic        getEpoch_rdy_o,
    output logic        getEpoch_val_o,
    // isEmpty
    output logic        isEmpty_val_o
);
    logic epochReg;
    // ----------------------------------------------------------------
    // Fifo for incoming data
    // ----------------------------------------------------------------
    logic        idata_enq_en , idata_notFull;
    logic        idata_deq_en , idata_notEmpty;
    logic [15:0] idata_enq_val, idata_first;
 
    PipelineFifo #(
      .T     (INT16                     ),
      .DEPTH (DN_SubTreeIngressFifoDepth)
    ) incomingData (
      .clk       (clk_i         ),        
      .rst_n     (rstn_i        ),
      .enq_en    (idata_enq_en  ),  
      .notFull   (idata_notFull ),
      .enq_val   (idata_enq_val ),
      .deq_en    (idata_deq_en  ),  
      .notEmpty  (idata_notEmpty),
      .first_val (idata_first   )
    );
 
    // ----------------------------------------------------------------
    // Fifo for epoch
    // ----------------------------------------------------------------
    logic epoch_enq_en , epoch_notFull;
    logic epoch_deq_en , epoch_notEmpty;
    logic epoch_enq_val, epoch_first;
 
    PipelineFifo #(
      .T     (DN_Epoch                  ),
      .DEPTH (DN_SubTreeIngressFifoDepth)
    ) epochStore (
      .clk       (clk_i         ),        
      .rst_n     (rstn_i        ),
      .enq_en    (epoch_enq_en  ),  
      .notFull   (epoch_notFull ),
      .enq_val   (epoch_enq_val ),
      .deq_en    (epoch_deq_en  ),  
      .notEmpty  (epoch_notEmpty),
      .first_val (epoch_first   )
    );
 
    // ================================================================
    // putData
    // ================================================================
    wire putData_fire = putData_en_i & putData_rdy_o;
 
    assign putData_rdy_o = idata_notFull & epoch_notFull;
    assign idata_enq_en  = putData_fire;
    assign idata_enq_val = putData_val_i;
    assign epoch_enq_en  = putData_fire;
    assign epoch_enq_val = ~epochReg;
 
    // epochReg
    always_ff @(posedge clk_i or negedge rstn_i) begin
      if (!rstn_i) begin
        epochReg <= dn_initEpoch;
      end else if (putData_fire) begin
        epochReg <= epoch_enq_val;
      end
    end
 
    // ================================================================
    // getData
    // ================================================================
    assign getData_rdy_o = idata_notEmpty & epoch_notEmpty;
    assign getData_val_o = idata_first;
    assign idata_deq_en  = getData_en_i & getData_rdy_o;
    assign epoch_deq_en  = getData_en_i & getData_rdy_o;
 
    // ================================================================
    // getEpoch
    // ================================================================
    assign getEpoch_rdy_o = epoch_notEmpty;
    assign getEpoch_val_o = epoch_first;
 
    // ================================================================
    // isEmpty
    // ================================================================
    assign isEmpty_val_o = ~idata_notEmpty;
endmodule