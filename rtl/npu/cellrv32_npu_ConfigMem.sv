`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_ConfigMem (
  input  logic     clk_i             ,
  input  logic     rstn_i            ,
  // get config from config memory
  input  logic     getRN_Config_en_i ,
  output logic     getRN_Config_rdy_o,
  output RN_Config getRN_Config_data_o
);

  localparam int CONFIG_MEM_DEPTH = 2 ** $bits(CR_ConfigIdx);

  // -------------------------------------------------------------------------
  // ROM initialized
  // -------------------------------------------------------------------------
  CR_ConfigData configMem [0:CONFIG_MEM_DEPTH-1];

  initial begin
    $readmemh("rn_config.hex", configMem);
  end

  logic         active;
  CR_ConfigIdx  pc;
  RN_Config     rn_ConfigBuffer;
  CR_ConfigData rawConfigData;

  RN_Config rn_ConfigFifo_data;
  logic     rn_ConfigFifo_notEmpty;
  logic     rn_ConfigFifo_notFull;
  logic     rn_ConfigFifo_enq;
  logic     rn_ConfigFifo_deq;

  always_ff @(posedge clk_i or negedge rstn_i) begin : getConfig
    if (!rstn_i) begin
      active          <= 1'b1;
      pc              <= '0;
      rn_ConfigBuffer <= '{default : '0};
    end else if (active) begin
      // ---------------------------------------------------------------------
      // Double Reduction Switches configuration
      // ---------------------------------------------------------------------
      if (pc < CR_ConfigIdx'(CR_DBRS_ConfigAddressBound)) begin
        automatic CR_ConfigIdx dbrs_base_idx = 4 * pc;

        for (CR_ConfigIdx idx = 0; idx < 4; idx++) begin
          if (dbrs_base_idx + idx < CR_ConfigIdx'(RN_NumDblRSes)) begin
            automatic CR_DBRS_ConfigData targetConfig = rawConfigData[8*idx +: 8];
            rn_ConfigBuffer.dblRSNetworkConfig[dbrs_base_idx + idx].mode       <= targetConfig[7:4];
            rn_ConfigBuffer.dblRSNetworkConfig[dbrs_base_idx + idx].genOutputL <= targetConfig[3];
            rn_ConfigBuffer.dblRSNetworkConfig[dbrs_base_idx + idx].genOutputR <= targetConfig[2];
          end
        end
      end
      // ---------------------------------------------------------------------
      // Single Reduction Switches configuration
      // ---------------------------------------------------------------------
      else if (pc < CR_ConfigIdx'(CR_SGRS_ConfigAddressBound)) begin
        automatic CR_ConfigIdx sgrs_base_idx = (pc - CR_ConfigIdx'(CR_DBRS_ConfigAddressBound)) * 8;

        for (CR_ConfigIdx idx = 0; idx < 8; idx++) begin
          if (sgrs_base_idx + idx < CR_ConfigIdx'(RN_NumSglRSes)) begin
            automatic CR_SGRS_ConfigData targetConfig = rawConfigData[4*idx +: 4];
            rn_ConfigBuffer.sglRSNetworkConfig[sgrs_base_idx + idx].mode      <= targetConfig[3:2];
            rn_ConfigBuffer.sglRSNetworkConfig[sgrs_base_idx + idx].genOutput <= targetConfig[1];
          end
        end
      end
      // ---------------------------------------------------------------------
      // write config data to buffer
      // ---------------------------------------------------------------------
      else begin
        rn_ConfigFifo_enq <= rn_ConfigFifo_notFull;  // enqueue when FIFO is not full
        active <= 1'b0;
      end
      // increment pc to next memory word
      pc <= pc + 1;
    end
  end : getConfig

  assign rawConfigData = configMem[pc];

  // -------------------------------------------------------------------------
  // rnConfig Fifo
  // -------------------------------------------------------------------------
  PipelineFifo #(
    .T     (RN_Config),
    .DEPTH (2        )
  ) rnConfigFifo_inst (
    .clk_i       (clk_i                 ),
    .rstn_i      (rstn_i                ),
    .enq_en_i    (rn_ConfigFifo_enq     ),
    .notFull_o   (rn_ConfigFifo_notFull ),
    .enq_val_i   (rn_ConfigBuffer       ),
    .deq_en_i    (rn_ConfigFifo_deq     ),
    .notEmpty_o  (rn_ConfigFifo_notEmpty),
    .first_val_o (rn_ConfigFifo_data    ) 
  );

  // -------------------------------------------------------------------------
  // Input/Output assignments
  // -------------------------------------------------------------------------
  assign getRN_Config_rdy_o  = rn_ConfigFifo_notEmpty;
  assign getRN_Config_data_o = rn_ConfigFifo_data;
  assign rn_ConfigFifo_deq   = rn_ConfigFifo_notEmpty & getRN_Config_en_i;

endmodule