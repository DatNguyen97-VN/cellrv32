`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_subtree_egress_NIC (
    input  logic                          clk_i            ,
    input  logic                          rstn_i           ,
    // put data
    input  logic [DN_SubTreeSz-1:0]       putNewDests_en_i ,
    output logic [DN_SubTreeSz-1:0]       putNewDests_rdy_o,
    input  logic [DN_SubTreeSz-1:0][15:0] putNewDests_val_i,
    // get data
    input  logic [DN_SubTreeSz-1:0]       getDests_en_i    ,
    output logic [DN_SubTreeSz-1:0]       getDests_rdy_o   ,
    output logic [DN_SubTreeSz-1:0][15:0] getDests_val_o
);
    // ------------------------------------------------
    // Internal signals
    // ------------------------------------------------
    logic [DN_SubTreeSz-1:0]       fifo_enq_en , fifo_notFull;
    logic [DN_SubTreeSz-1:0]       fifo_deq_en , fifo_notEmpty;
    logic [DN_SubTreeSz-1:0][15:0] fifo_enq_val, fifo_first;
 
    genvar idx;
    generate
        for (idx = 0; idx < DN_SubTreeSz; idx++) begin : gen_outData
            PipelineFifo #(
              .T     (INT16                     ),
              .DEPTH (DN_SubTreeEngressFifoDepth)
            ) outData_inst (
              .clk_i       (clk_i             ),      
              .rstn_i      (rstn_i            ),
              .enq_en_i    (fifo_enq_en[idx]  ), 
              .notFull_o   (fifo_notFull[idx] ),
              .enq_val_i   (fifo_enq_val[idx] ),
              .deq_en_i    (fifo_deq_en[idx]  ), 
              .notEmpty_o  (fifo_notEmpty[idx]),
              .first_val_o (fifo_first[idx]   )
            );
        end : gen_outData
    endgenerate

    // ------------------------------------------------
    // Connect put/get signals to FIFOs
    // ------------------------------------------------
    assign fifo_enq_en       = putNewDests_en_i & fifo_notFull;
    assign fifo_enq_val      = putNewDests_val_i;
    assign putNewDests_rdy_o = fifo_notFull;

    assign fifo_deq_en    = getDests_en_i & fifo_notEmpty;
    assign getDests_val_o = fifo_first;
    assign getDests_rdy_o = fifo_notEmpty;
    
endmodule