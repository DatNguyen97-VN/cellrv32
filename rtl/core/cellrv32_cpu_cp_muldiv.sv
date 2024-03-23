// #################################################################################################
// # << CELLRV32 - CPU Co-Processor: int Multiplier/Divider Unit (RISC-V "M" Extension) >>      #
// # ********************************************************************************************* #
// # Multiplier core (signed/unsigned) uses serial add-and-shift algorithm. Multiplications can be #
// # mapped to DSP blocks (faster!) when FAST_MUL_EN = true. Divider core (unsigned-only; pre and  #
// # post sign-compensation logic) uses serial restoring serial algorithm.                         #
// # ********************************************************************************************* #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_cpu_cp_muldiv #(
    parameter XLEN        = 32, // data path width
    parameter FAST_MUL_EN = 1,  // use DSPs for faster multiplication
    parameter DIVISION_EN = 1   // implement divider hardware
) (
    /* global control */
    input  logic            clk_i,   // global clock, rising edge
    input  logic            rstn_i,  // global reset, low-active, async
    input  ctrl_bus_t       ctrl_i,  // main control bus
    input  logic             start_i,              // trigger operation
    /* data input */
    input  logic [XLEN-1:0]  rs1_i,                // rf source 1
    input  logic [XLEN-1:0]  rs2_i,                // rf source 2
    /* result and status */
    output logic [XLEN-1:0]  res_o,                // operation result
    output logic             valid_o               // data output valid
);
    
    /* operations */
    const logic[2:0] cp_op_mul_c    = 3'b000; // mul
    const logic[2:0] cp_op_mulh_c   = 3'b001; // mulh
    const logic[2:0] cp_op_mulhsu_c = 3'b010; // mulhsu
    const logic[2:0] cp_op_mulhu_c  = 3'b011; // mulhu
    const logic[2:0] cp_op_div_c    = 3'b100; // div
    const logic[2:0] cp_op_divu_c   = 3'b101; // divu
    const logic[2:0] cp_op_rem_c    = 3'b110; // rem
    //const logic[2:0] cp_op_remu_c   = 3'b111; // remu

    /* controller */
    typedef enum logic[1:0] { S_IDLE, S_BUSY, S_DONE } state_t;
    typedef struct {
        state_t state;         
        logic [index_size_f(XLEN)-1:0] cnt; // iteration counter          
        logic [2:0] cp_op; // operation to execute         
        logic [2:0] cp_op_ff;      
        logic op; // 0 = mul, 1 = div            
        logic rs1_is_signed; 
        logic rs2_is_signed; 
        logic out_en;        
        logic [XLEN-1:0] rs2_abs;       
    } ctrl_t;
    ctrl_t ctrl;

    /* divider core */
    typedef struct {
        logic start; // start new division     
        logic sign_mod; // result sign correction  
        logic [XLEN-1:0] remainder; 
        logic [XLEN-1:0] quotient;  
        logic [XLEN:0]   sub; // try subtraction (and restore if underflow)      
        logic [XLEN-1:0] res_u; // unsigned result   
        logic signed [XLEN-1:0] res;       
    } div_t;
    div_t div;

    /* multiplier core */
    typedef struct {
        logic                     start;  // start new multiplication  
        logic [2*XLEN-1:0]        prod;   // product   
        logic [XLEN:0]            add;    // addition step    
        logic                     p_sext; // product sign-extension
        logic signed [XLEN:0]     dsp_x;  // input for using DSPs
        logic signed [XLEN:0]     dsp_y;  // input for using DSPs
        logic signed [2*XLEN+1:0] dsp_z;  
    } mul_t;
    mul_t mul;

    // Co-Processor Controller -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : coprocessor_ctrl
        if (rstn_i == 1'b0) begin
            ctrl.state    <= S_IDLE;
            ctrl.rs2_abs  <= '0;
            ctrl.cnt      <= '0;
            ctrl.cp_op_ff <= '0;
            ctrl.out_en   <=  1'b0;
            div.sign_mod  <=  1'b0;
        end else begin
            /* defaults */
            ctrl.out_en <= 1'b0;
            /* FSM */
            unique case (ctrl.state)
                S_IDLE : begin // wait for start signal
                    ctrl.cp_op_ff <= ctrl.cp_op;
                    ctrl.cnt      <= index_size_f(XLEN)'(XLEN-2); // iterative cycle counter
                    //  trigger new operation
                    if (start_i == 1'b1) begin
                        if (DIVISION_EN == 1'b1) begin
                            /* DIV: check relevant input signs for result sign compensation */
                            if (ctrl.cp_op[1:0] == cp_op_div_c[1:0]) // signed div operation
                                div.sign_mod <= (rs1_i[$bits(rs1_i)-1] ^ rs2_i[$bits(rs2_i)-1]) & (|rs2_i); // different signs AND divisor not zero
                            else if (ctrl.cp_op[1:0] == cp_op_rem_c[1:0]) // signed rem operation
                                div.sign_mod <= rs1_i[$bits(rs1_i)-1];
                            else
                                div.sign_mod <= 1'b0;
                            /* DIV: abs(rs2) */
                            if ((rs2_i[$bits(rs2_i)-1] & ctrl.rs2_is_signed) == 1'b1) // signed division?
                                ctrl.rs2_abs <= ~rs2_i + 1; // make positive
                            else
                                ctrl.rs2_abs <= rs2_i;
                        end
                    /* is fast multiplication? */
                        if ((ctrl.op == 1'b0) && (FAST_MUL_EN == 1'b1))
                            ctrl.state <= S_DONE;
                        else 
                            ctrl.state <= S_BUSY;
                    end
                end
                S_BUSY : begin // processing
                    ctrl.cnt <= ctrl.cnt - 1'b1;
                    if (((|ctrl.cnt) == 1'b0) || (ctrl_i.cpu_trap == 1'b1)) // abort on trap
                        ctrl.state <= S_DONE;
                end
                S_DONE : begin // final step / enable output for one cycle
                    ctrl.out_en <= 1'b1;
                    ctrl.state  <= S_IDLE;
                end
                default: begin // undefined
                    ctrl.state <= S_IDLE;
                end
            endcase
        end
    end : coprocessor_ctrl

    /* done? assert one cycle before actual data output */
    assign valid_o = (ctrl.state == S_DONE) ? 1'b1 : 1'b0;

    /* co-processor operation */
    assign ctrl.cp_op = ctrl_i.ir_funct3;
    assign ctrl.op    = (ctrl_i.ir_funct3[2] == 1'b1) ? 1'b1 : 1'b0;
    
    /* input operands treated as signed? */
    assign ctrl.rs1_is_signed = ((ctrl.cp_op == cp_op_mulh_c) || (ctrl.cp_op == cp_op_mulhsu_c) ||
                                (ctrl.cp_op == cp_op_div_c) || (ctrl.cp_op == cp_op_rem_c)) ? 1'b1 : 1'b0;
    assign ctrl.rs2_is_signed = ((ctrl.cp_op == cp_op_mulh_c) || (ctrl.cp_op == cp_op_div_c) 
                                || (ctrl.cp_op == cp_op_rem_c)) ? 1'b1 : 1'b0;
    
    /* start operation (do it fast!) */
    assign mul.start = ((start_i == 1'b1) && (ctrl.op == 1'b0)) ? 1'b1 : 1'b0;
    assign div.start = ((start_i == 1'b1) && (ctrl.op == 1'b1)) ? 1'b1 : 1'b0;
    
    // Multiplier Core (signed/unsigned) - Full Parallel -----------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (FAST_MUL_EN == 1'b1) begin : multiplier_core_parallel
            /* direct approach */
            always_ff @( posedge clk_i ) begin : multiplier_core
                if (mul.start == 1'b1) begin
                    mul.dsp_x <= signed'({(rs1_i[$bits(rs1_i)-1] & ctrl.rs1_is_signed), rs1_i});
                    mul.dsp_y <= signed'({(rs2_i[$bits(rs2_i)-1] & ctrl.rs2_is_signed), rs2_i});
                end
                mul.prod <= mul.dsp_z[63:0];
            end : multiplier_core

            /* actual multiplication */
            assign mul.dsp_z = mul.dsp_x * mul.dsp_y;
        end : multiplier_core_parallel
    endgenerate

    /* no parallel multiplier */
    generate
        if (FAST_MUL_EN == 1'b0) begin
            assign mul.dsp_x = '0;
            assign mul.dsp_y = '0;
            assign mul.dsp_z = '0;
        end
    endgenerate

    // Multiplier Core (signed/unsigned) - Iterative ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (FAST_MUL_EN == 1'b0) begin : multiplier_core_serial
            /* shift-and-add algorithm */
            always_ff @( posedge clk_i ) begin : multiplier_core
                 if (mul.start == 1'b1) begin // start new multiplication
                     mul.prod[63:32] <= '0;
                     mul.prod[31:0]  <= rs1_i;
                 end else if ((ctrl.state == S_BUSY) || (ctrl.state == S_DONE)) begin // processing step or sign-finalization step
                     mul.prod[63:31] <= mul.add[32:0];
                     mul.prod[30:0]  <= mul.prod[31:1];
                 end
            end : multiplier_core

            /* multiply with 0/1 via addition */
            always_comb begin : mul_update
                if (mul.prod[0] == 1'b1) // multiply with 1
                    if ((ctrl.state == S_DONE) && (ctrl.rs1_is_signed == 1'b1)) // for signed operations only: take care of negative weighted MSB -> multiply with -1
                        mul.add = unsigned'({mul.p_sext, mul.prod[63:32]}) - unsigned'({(rs2_i[$bits(rs2_i)-1] & ctrl.rs2_is_signed), rs2_i});
                    else // multiply with +1
                        mul.add = unsigned'({mul.p_sext, mul.prod[63:32]}) + unsigned'({(rs2_i[$bits(rs2_i)-1] & ctrl.rs2_is_signed), rs2_i});
                else // multiply with 0
                    mul.add = {mul.p_sext, mul.prod[63:32]};
            end : mul_update

            /* product sign extension bit */
            assign mul.p_sext = mul.prod[$bits(mul.prod)-1] & ctrl.rs2_is_signed;
        end : multiplier_core_serial
    endgenerate

    /* no serial multiplier */
    generate
        if (FAST_MUL_EN == 1'b1) begin : multiplier_core_serial_none
             assign mul.add    = '0;
             assign mul.p_sext = 1'b0;
        end : multiplier_core_serial_none
    endgenerate

    // Divider Core (unsigned) - Iterative -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (DIVISION_EN == 1'b1) begin : divider_core_serial
            /* restoring division algorithm */
            always_ff @( posedge clk_i ) begin : divider_core
                if (div.start == 1'b1) begin // start new division
                    if ((rs1_i[$bits(rs1_i)-1] & ctrl.rs1_is_signed) == 1'b1) // signed division ?
                       div.quotient <= ~rs1_i + 1; // make positive
                    else
                       div.quotient <= rs1_i;
                    div.remainder <= '0;
                end else if ((ctrl.state == S_BUSY) || (ctrl.state == S_DONE)) begin // running ?
                    div.quotient <= {div.quotient[30:0], ~div.sub[32]};
                    if (div.sub[32] == 1'b0) // implicit shift
                        div.remainder <= div.sub[31:0];
                    else // underflow: restore and explicit shift
                        div.remainder <= {div.remainder[30:0], div.quotient[31]};
                end
            end : divider_core

            /* try another subtraction (and shift) */
            assign div.sub = {1'b0, div.remainder[30:0], div.quotient[31]} - {1'b0, ctrl.rs2_abs};

            /* result and sign compensation */
            assign div.res_u = ((ctrl.cp_op == cp_op_div_c) || (ctrl.cp_op == cp_op_divu_c)) ? div.quotient : div.remainder;
            assign div.res   = (div.sign_mod == 1'b1) ? (~div.res_u + 1) : div.res_u;
        end : divider_core_serial
    endgenerate

    /* no divider */
    generate
        if (DIVISION_EN == 1'b0) begin : divider_core_serial_none
            assign div.remainder = '0;
            assign div.quotient  = '0;
            assign div.sub       = '0;
            assign div.res_u     = '0;
            assign div.res       = '0;
        end : divider_core_serial_none
    endgenerate

    // Data Output -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : operation_result
        res_o = '0; // default
        if (ctrl.out_en == 1'b1) begin
            unique case (ctrl.cp_op_ff)
                cp_op_mul_c   : res_o = mul.prod[31:0];
                cp_op_mulh_c,
                cp_op_mulhsu_c,
                cp_op_mulhu_c : res_o = mul.prod[63:32];
                default: begin // cp_op_div_c | cp_op_rem_c | cp_op_divu_c | cp_op_remu_c
                                res_o = div.res;
                end
            endcase
        end
    end : operation_result

endmodule