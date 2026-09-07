`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_multiplierswitch (
    input  logic     clk_i             ,
    input  logic     rstn_i            ,
    // ---- dataPorts ----
    // putIptData
    input  logic     putIptData_en_i   ,
    output logic     putIptData_rdy_o  ,
    input  INT16     putIptData_val_i  ,
    // putFwdData
    input  logic     putFwdData_en_i   ,
    output logic     putFwdData_rdy_o  ,
    input  INT16     putFwdData_val_i  ,
    // getFwdData
    output logic     getFwdData_rdy_o  ,
    output INT16     getFwdData_val_o  ,
    // getPSum
    input  logic     getPSum_en_i      ,
    output logic     getPSum_rdy_o     ,
    output INT16     getPSum_val_o     ,
    // ---- controlPorts ----
    // putNewConfig
    input  logic     putNewConfig_en_i ,
    output logic     putNewConfig_rdy_o,
    input  MS_Config putNewConfig_val_i
);

    // ================================================================
    // MultiplierSwitch_Controller instance
    // ================================================================
    logic        ctrl_putNewConfig_en;
    logic        ctrl_putNewConfig_rdy;
    MS_Config    ctrl_putNewConfig_val;
    logic        ctrl_putAck_en;
    logic        ctrl_putAck_rdy;
    MS_IptSelect ctrl_iptSel_val;
    MS_FwdSelect ctrl_fwdSel_val;
    MS_ArgSelect ctrl_argSel_val;
    logic        ctrl_doCompute;

    cellrv32_npu_multiplierswitch_controller controller_inst (
        .clk_i                  (clk_i                ),
        .rstn_i                 (rstn_i               ),
        .putNewConfig_en_i      (ctrl_putNewConfig_en ),
        .putNewConfig_rdy_o     (ctrl_putNewConfig_rdy),
        .putNewConfig_val_i     (ctrl_putNewConfig_val),
        .putPSumGenNotice_en_i  (ctrl_putAck_en       ),
        .putPSumGenNotice_rdy_o (ctrl_putAck_rdy      ),
        .getIptSelect_val_o     (ctrl_iptSel_val      ),
        .getFwdSelect_val_o     (ctrl_fwdSel_val      ),
        .getArgSelect_val_o     (ctrl_argSel_val      ),
        .getDoCompute_val_o     (ctrl_doCompute       )
    );

    // ================================================================
    // MultiplierSwitch_NIC instance
    // ================================================================
    // dataPorts
    logic nic_putIptData_en;
    logic nic_putIptData_rdy;
    INT16 nic_putIptData_val;
    logic nic_putFwdData_en;
    logic nic_putFwdData_rdy;
    INT16 nic_putFwdData_val;
    logic nic_putPSum_en;
    logic nic_putPSum_rdy;
    INT16 nic_putPSum_val;
    INT16 nic_getStat_val;
    logic nic_getDynArg_en;
    logic nic_getDynArg_rdy;
    INT16 nic_getDynArg_val;
    logic nic_getPSum_en;
    logic nic_getPSum_rdy;
    INT16 nic_getPSum_val;
    logic nic_getFwdData_rdy;
    INT16 nic_getFwdData_val;

    cellrv32_npu_multiplierswitch_NIC nic_inst (
        .clk_i              (clk_i             ), 
        .rstn_i             (rstn_i            ),
        /* ---- controlPorts ---- */
        .putIptSelect_en_i  (1'b1              ),  
        .putIptSelect_val_i (ctrl_iptSel_val   ),
        .putFwdSelect_en_i  (1'b1              ),  
        .putFwdSelect_val_i (ctrl_fwdSel_val   ),
        .putArgSelect_en_i  (1'b1              ),  
        .putArgSelect_val_i (ctrl_argSel_val   ),
        /* ---- dataPorts ---- */
        // putIptData
        .putIptData_en_i    (nic_putIptData_en ), 
        .putIptData_rdy_o   (nic_putIptData_rdy),
        .putIptData_val_i   (nic_putIptData_val),
        // putFwdData
        .putFwdData_en_i    (nic_putFwdData_en ), 
        .putFwdData_rdy_o   (nic_putFwdData_rdy),
        .putFwdData_val_i   (nic_putFwdData_val),
        // putPSum
        .putPSum_en_i       (nic_putPSum_en    ),     
        .putPSum_rdy_o      (nic_putPSum_rdy   ),
        .putPSum_val_i      (nic_putPSum_val   ),
        /* ---- Output Ports ---- */
        // getStationaryArgument
        .getStat_val_o      (nic_getStat_val   ),
        // getDynamicArgument
        .getDynArg_en_i     (nic_getDynArg_en  ),  
        .getDynArg_rdy_o    (nic_getDynArg_rdy ),
        .getDynArg_val_o    (nic_getDynArg_val ),
        // getPSum
        .getPSum_en_i       (nic_getPSum_en    ),     
        .getPSum_rdy_o      (nic_getPSum_rdy   ),
        .getPSum_val_o      (nic_getPSum_val   ),
        // getFwdData 
        .getFwdData_rdy_o   (nic_getFwdData_rdy),
        .getFwdData_val_o   (nic_getFwdData_val)
    );

    // ================================================================
    // Multiplier instance
    // ================================================================
    INT16 alu_argA, alu_argB, alu_res;

    cellrv32_npu_multiplier #(.WIDTH($bits(INT16))
    ) alu_inst (
        .clk_i      (clk_i   ),
        .rstn_i     (rstn_i  ),
        .argA_i     (alu_argA),
        .argB_i     (alu_argB),
        .resValue_o (alu_res )
    );

    // ================================================================
    // rule doCompute
    // ================================================================
    wire rule_doCompute = ctrl_doCompute      // doCompute valid
                          & nic_getDynArg_rdy // argB valid
                          & nic_putPSum_rdy;  // pSumData notfull

    // getDynamicArgument fire
    assign nic_getDynArg_en = rule_doCompute;

    // ALU inputs
    assign alu_argA = nic_getStat_val;
    assign alu_argB = nic_getDynArg_val;

    // putPSum
    assign nic_putPSum_en  = rule_doCompute;
    assign nic_putPSum_val = alu_res;

    // ================================================================
    // dataPorts interface
    // ================================================================
    // putIptData
    assign nic_putIptData_en  = putIptData_en_i;
    assign putIptData_rdy_o   = nic_putIptData_rdy;
    assign nic_putIptData_val = putIptData_val_i;

    // putFwdData
    assign nic_putFwdData_en  = putFwdData_en_i;
    assign putFwdData_rdy_o   = nic_putFwdData_rdy;
    assign nic_putFwdData_val = putFwdData_val_i;

    // getFwdData
    assign getFwdData_rdy_o  = nic_getFwdData_rdy;
    assign getFwdData_val_o  = nic_getFwdData_val;

    // getPSum
    assign getPSum_rdy_o  = ctrl_putAck_rdy & nic_getPSum_rdy;
    assign ctrl_putAck_en = getPSum_en_i & getPSum_rdy_o;
    assign nic_getPSum_en = getPSum_en_i & getPSum_rdy_o;
    assign getPSum_val_o  = nic_getPSum_val;

    // ================================================================
    // controlPorts interface
    // ================================================================
    // putNewConfig(MS_Config) → controller.putNewConfig
    assign ctrl_putNewConfig_en  = putNewConfig_en_i;
    assign putNewConfig_rdy_o    = ctrl_putNewConfig_rdy;
    assign ctrl_putNewConfig_val = putNewConfig_val_i;

endmodule