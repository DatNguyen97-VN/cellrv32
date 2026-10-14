`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_npu_distributionswitch (
    input  logic        clk_i            ,
    input  logic        rstn_i           ,
    // data
    input  logic [15:0] newInData_i      ,
    input  logic        newInData_en_i   ,
    output logic [15:0] outDataLeft_o    ,
    output logic        outDataLeft_en_o ,
    output logic [15:0] outDataRight_o   ,
    output logic        outDataRight_en_o,
    // config
    input  DS_Config    newConfig_i      ,
    input  logic        newConfig_en_i
);
    // internal signals
    logic getRoutLeft, getRoutRight;

    // -------------------------------------------
    // controller
    // -------------------------------------------
    DS_Config stateReg;

    // put new config
    always_ff @( posedge clk_i or negedge rstn_i ) begin : put_new_config
      if (!rstn_i) begin
        stateReg <= DS_IDLE;
      end else if (newConfig_en_i) begin
        stateReg <= newConfig_i; 
      end
    end : put_new_config

    // get route left
    always_comb begin : get_route_left
      case (stateReg)
        DS_LEFT : getRoutLeft = 1'b1;
        DS_RIGHT: getRoutLeft = 1'b0;  
        DS_BOTH : getRoutLeft = 1'b1;
        default : getRoutLeft = 1'b0; 
      endcase 
    end : get_route_left

    // get route right
    always_comb begin : get_route_right
      case (stateReg)
        DS_LEFT : getRoutRight = 1'b0;   
        DS_RIGHT: getRoutRight = 1'b1; 
        DS_BOTH : getRoutRight = 1'b1;
        default : getRoutRight = 1'b0;  
      endcase 
    end : get_route_right

    // -------------------------------------------
    // nic
    // -------------------------------------------
    assign outDataLeft_o     = newInData_i;
    assign outDataLeft_en_o  = newInData_en_i & getRoutLeft;
    assign outDataRight_o    = newInData_i;
    assign outDataRight_en_o = newInData_en_i & getRoutRight;
    
endmodule