`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_DblReductionSwitch_Datapath (
  input  logic             clk_i             ,
  input  logic             rstn_i            ,
  // inputDataPorts[0..3] : LL, LR, RL, RR
  input  logic [3:0]       input_put_en_i    ,
  output logic [3:0]       input_put_ready_o ,
  input  logic [3:0][15:0] input_put_data_i  ,
  // outputDataPorts[0..1] : L, R
  input  logic [1:0]       output_get_en_i   ,
  output logic [1:0]       output_get_ready_o,
  output logic [1:0][15:0] output_get_data_o ,
  // controlPorts
  input  RN_DBRS_SubMode   modeL_val_i       ,
  input  RN_DBRS_SubMode   modeR_val_i
);

  // -------------------------------------------------------------------------
  // fifo_inputLL, fifo_inputLR, fifo_inputRL, fifo_inputRR instances
  // -------------------------------------------------------------------------
  logic notFull_LL, notEmpty_LL;
  INT16 first_LL;

  logic notFull_LR, notEmpty_LR;
  INT16 first_LR;

  logic notFull_RL, notEmpty_RL;
  INT16 first_RL;

  logic notFull_RR, notEmpty_RR;
  INT16 first_RR;

  logic enq_LL, deq_LL;
  logic enq_LR, deq_LR;
  logic enq_RL, deq_RL;
  logic enq_RR, deq_RR;

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_inputLL_inst (
    .clk_i       (clk_i              ),
    .rstn_i      (rstn_i             ),
    .enq_en_i    (enq_LL             ),
    .notFull_o   (notFull_LL         ),
    .enq_val_i   (input_put_data_i[0]),
    .deq_en_i    (deq_LL             ),
    .notEmpty_o  (notEmpty_LL        ),
    .first_val_o (first_LL           )
  );

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_inputLR_inst (
    .clk_i       (clk_i              ),
    .rstn_i      (rstn_i             ),
    .enq_en_i    (enq_LR             ),
    .notFull_o   (notFull_LR         ),
    .enq_val_i   (input_put_data_i[1]),
    .deq_en_i    (deq_LR             ),
    .notEmpty_o  (notEmpty_LR        ),
    .first_val_o (first_LR           )
  );

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_inputRL_inst (
    .clk_i       (clk_i              ),
    .rstn_i      (rstn_i             ),
    .enq_en_i    (enq_RL             ),
    .notFull_o   (notFull_RL         ),
    .enq_val_i   (input_put_data_i[2]),
    .deq_en_i    (deq_RL             ),
    .notEmpty_o  (notEmpty_RL        ),
    .first_val_o (first_RL           )
  );

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_inputRR_inst (
    .clk_i       (clk_i              ),
    .rstn_i      (rstn_i             ),
    .enq_en_i    (enq_RR             ),
    .notFull_o   (notFull_RR         ),
    .enq_val_i   (input_put_data_i[3]),
    .deq_en_i    (deq_RR             ),
    .notEmpty_o  (notEmpty_RR        ),
    .first_val_o (first_RR           )
  );

  // write data: enq when valid and notFull
  assign input_put_ready_o = {notFull_RR, notFull_RL, notFull_LR, notFull_LL};

  assign enq_LL = input_put_en_i[0] & notFull_LL;
  assign enq_LR = input_put_en_i[1] & notFull_LR;
  assign enq_RL = input_put_en_i[2] & notFull_RL;
  assign enq_RR = input_put_en_i[3] & notFull_RR;

  // -------------------------------------------------------------------------
  // fifo_outL, fifo_outR instances
  // -------------------------------------------------------------------------
  logic notFull_outL;
  logic notEmpty_outL;  
  logic enq_outL; 
  logic deq_outL;
  INT16 first_outL;
  INT16 enq_outL_data;

  logic notFull_outR;
  logic notEmpty_outR;  
  logic deq_outR;
  INT16 first_outR;
  logic enq_outR;  
  INT16 enq_outR_data;

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_outL_inst (
    .clk_i       (clk_i        ),
    .rstn_i      (rstn_i       ),
    .enq_en_i    (enq_outL     ),
    .notFull_o   (notFull_outL ),
    .enq_val_i   (enq_outL_data),
    .deq_en_i    (deq_outL     ),
    .notEmpty_o  (notEmpty_outL),
    .first_val_o (first_outL   )
  );

  PipelineFifo #(
    .T     (INT16),
    .DEPTH (2    )
  ) fifo_outR_inst (
    .clk_i       (clk_i        ),
    .rstn_i      (rstn_i       ),
    .enq_en_i    (enq_outR     ),
    .notFull_o   (notFull_outR ),
    .enq_val_i   (enq_outR_data),
    .deq_en_i    (deq_outR     ),
    .notEmpty_o  (notEmpty_outR),
    .first_val_o (first_outR   )
  );

  assign deq_outL = output_get_en_i[0] & notEmpty_outL;
  assign deq_outR = output_get_en_i[1] & notEmpty_outR;

  assign output_get_ready_o[0] = notEmpty_outL;
  assign output_get_ready_o[1] = notEmpty_outR;

  assign output_get_data_o[0]  = first_outL;
  assign output_get_data_o[1]  = first_outR;

  // ==========================================================================
  // Adders
  // adders[0],[1] for Left; adders[2],[3] for Right
  // ==========================================================================
  INT16 adder_res [3:0];

  // adder[0]: val_LL   + val_LR (step 1: leftThreeSum, leftTwoSum)
  // adder[1]: adder[0] + val_RL (step 2: leftThreeSum)
  // adder[2]: val_RL   + val_RR (step 1: rightThreeSum, rightTwoSum)
  // adder[3]: adder[2] + val_LR (step 2: rightThreeSum)
  cellrv32_npu_adder adder0_inst (.clk_i(clk_i), .rstn_i(rstn_i), .argA_i(first_LL),     .argB_i(first_LR), .resValue_o(adder_res[0]));
  cellrv32_npu_adder adder1_inst (.clk_i(clk_i), .rstn_i(rstn_i), .argA_i(adder_res[0]), .argB_i(first_RL), .resValue_o(adder_res[1]));
  cellrv32_npu_adder adder2_inst (.clk_i(clk_i), .rstn_i(rstn_i), .argA_i(first_RL),     .argB_i(first_RR), .resValue_o(adder_res[2]));
  cellrv32_npu_adder adder3_inst (.clk_i(clk_i), .rstn_i(rstn_i), .argA_i(adder_res[2]), .argB_i(first_LR), .resValue_o(adder_res[3]));

  // ==========================================================================
  // Rules of read fifo inputData, compute and write fifo outputData
  // ==========================================================================
  // do Left Three Sum 
  logic rule_leftThreeSum;
  assign rule_leftThreeSum = (modeL_val_i == rn_dbrs_submode_addThree)
                           & ((modeR_val_i == rn_dbrs_submode_addOne) | (modeR_val_i == rn_dbrs_submode_idle))
                           & notEmpty_LL & notEmpty_LR & notEmpty_RL
                           & notFull_outL;

  // do Left Two Sum 
  logic rule_leftTwoSum;
  assign rule_leftTwoSum = (modeL_val_i == rn_dbrs_submode_addTwo)
                         & (modeR_val_i != rn_dbrs_submode_addThree)
                         & notEmpty_LL & notEmpty_LR
                         & notFull_outL;

  // do Left One Sum
  logic rule_leftOneSum;
  assign rule_leftOneSum = (modeL_val_i == rn_dbrs_submode_addOne)
                         & notEmpty_LL
                         & notFull_outL;

  // do Right Three Sum
  logic rule_rightThreeSum;
  assign rule_rightThreeSum = (modeR_val_i == rn_dbrs_submode_addThree)
                            & (modeL_val_i != rn_dbrs_submode_addThree | modeL_val_i != rn_dbrs_submode_addTwo)
                            & notEmpty_RL & notEmpty_RR & notEmpty_LR
                            & notFull_outR;

  // do Right Two Sum
  logic rule_rightTwoSum;
  assign rule_rightTwoSum = (modeR_val_i == rn_dbrs_submode_addTwo)
                          & (modeL_val_i != rn_dbrs_submode_addThree)
                          & notEmpty_RL & notEmpty_RR
                          & notFull_outR;

  // do Right One Sum
  logic rule_rightOneSum;
  assign rule_rightOneSum = (modeR_val_i == rn_dbrs_submode_addOne)
                          & notEmpty_RR
                          & notFull_outR;

  // -------------------------------------------------------------------------
  // read data from fifo
  // -------------------------------------------------------------------------
  assign deq_LL = rule_leftThreeSum  | rule_leftTwoSum    | rule_leftOneSum;
  assign deq_LR = rule_leftThreeSum  | rule_leftTwoSum    | rule_rightThreeSum;
  assign deq_RL = rule_leftThreeSum  | rule_rightThreeSum | rule_rightTwoSum;
  assign deq_RR = rule_rightThreeSum | rule_rightTwoSum   | rule_rightOneSum;

  // -------------------------------------------------------------------------
  // write data to fifo_outL / fifo_outR
  // -------------------------------------------------------------------------
  always_comb begin
    enq_outL      = 1'b0;
    enq_outL_data = '0;
    if      (rule_leftThreeSum) begin enq_outL = 1'b1; enq_outL_data = adder_res[1]; end
    else if (rule_leftTwoSum)   begin enq_outL = 1'b1; enq_outL_data = adder_res[0]; end
    else if (rule_leftOneSum)   begin enq_outL = 1'b1; enq_outL_data = first_LL;     end
  end

  always_comb begin
    enq_outR      = 1'b0;
    enq_outR_data = '0;
    if      (rule_rightThreeSum) begin enq_outR = 1'b1; enq_outR_data = adder_res[3]; end
    else if (rule_rightTwoSum)   begin enq_outR = 1'b1; enq_outR_data = adder_res[2]; end
    else if (rule_rightOneSum)   begin enq_outR = 1'b1; enq_outR_data = first_RR;     end
  end

endmodule