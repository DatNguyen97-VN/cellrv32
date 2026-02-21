// ##################################################################################################
// # << CELLRV32 - Vector Integer Unit >>                                                           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_vector_vex_pipe_vint #(
    parameter int XLEN             = 32,
    parameter int VECTOR_LANES     = 8 ,
    parameter int VECTOR_LANE_NUM  = 1 
) (
    input  logic            clk            ,
    input  logic            rst_n          ,
    input  logic            valid_i        ,
    input  logic [XLEN-1:0] data_a_ex1_i   ,
    input  logic [XLEN-1:0] data_b_ex1_i   ,
    input  logic [     5:0] funct6_i       ,
    input  logic [     2:0] funct3_i       ,
    input  logic            mask_i         ,
    input  logic [     6:0] vl_i           ,
    input  logic            is_rdc_i       ,
    output logic            ready_o        ,
    output logic [     3:0] valid_mul_div_o,
    // Reduction Tree Inputs
    input  logic [XLEN-1:0] rdc_data_ex1_i ,
    input  logic [XLEN-1:0] rdc_data_ex2_i ,
    input  logic [XLEN-1:0] rdc_data_ex3_i ,
    // Result Ex1 Out
    output logic            ready_res_ex1_o,
    output logic [XLEN-1:0] result_ex1_o   ,
    // EX2 Data In
    input  logic [XLEN-1:0] data_ex2_i     ,
    // Result EX2 Out
    output logic [XLEN-1:0] result_ex2_o   ,
    // EX3 Data In
    input  logic [XLEN-1:0] data_ex3_i     ,
    // Result EX3 Ou
    output logic            ready_res_ex3_o,
    output logic [XLEN-1:0] result_ex3_o   ,
    // Result EX4 Out
    output logic            ready_res_ex4_o,
    output logic [XLEN-1:0] result_ex4_o
);

    logic [XLEN-1:0] data_a_u_ex1 ;
    logic [XLEN-1:0] data_b_u_ex1 ;

    logic valid_int_ex1;
    logic valid_mul_ex1;
    logic valid_mul_ex2;
    logic valid_mul_ex3;
    logic valid_mul_ex4;
    logic valid_div_ex1;
    logic valid_div_ex2;
    logic valid_div_ex3;
    logic valid_div_ex4;
    logic is_multi_cycle;
    logic is_single_cycle;

    logic mul_div_ready;

    logic [XLEN-1:0] result_int_ex1;
    logic [XLEN-1:0] result_mul_ex4;
    logic [XLEN-1:0] result_div_ex4;

    logic [XLEN-1:0] result_rdc_ex1;
    logic [XLEN-1:0] result_rdc_ex2;
    logic [XLEN-1:0] result_rdc_ex3;

    assign data_a_u_ex1 = $unsigned(data_a_ex1_i);
    assign data_b_u_ex1 = $unsigned(data_b_ex1_i);

    assign is_multi_cycle = (funct3_i == funct3_opmvv_c) || (funct3_i == funct3_opmvx_c) ? 1'b1 : 1'b0;
    assign is_single_cycle = ~is_multi_cycle & valid_i;
    assign ready_o = is_multi_cycle ? mul_div_ready & valid_i : valid_i;

    // ========================================================================
    // ========================================================================
    // INT Section (no mul/div)
    // ========================================================================
    // ========================================================================
    logic [XLEN-1:0] result_int;
    always_comb begin
        case (funct6_i)
            // vadd.vv, vadd.vx, vadd.vi
            funct6_vadd_c : begin
                result_int    = data_a_u_ex1 + data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vsub.vv, vsub.vx
            funct6_vsub_c : begin
                result_int    = data_b_u_ex1 - data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vrsub.vx, vrsub.vi
            funct6_vrsub_c : begin
                result_int    = data_a_u_ex1 - data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vand.vv, vand.vx, vand.vi
            funct6_vand_c : begin
                result_int    = data_a_u_ex1 & data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vor.vv, vor.vx, vor.vi
            funct6_vor_c : begin
                result_int    = data_a_u_ex1 | data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vxor.vv, vxor.vx, vxor.vi
            funct6_vxor_c : begin
                result_int    = data_a_u_ex1 ^ data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vsll.vv, vsll.vx, vsll.vi
            funct6_vsll_c : begin
                result_int    = data_b_u_ex1 << data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vsrl.vv, vsrl.vx, vsrl.vi
            funct6_vsrl_c : begin
                result_int    = data_b_u_ex1 >> data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vsra.vv, vsra.vx, vsra.vi
            funct6_vsra_c : begin
                result_int    = $signed(data_b_ex1_i) >>> data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vminu.vv, vminu.vx
            funct6_vminu_c : begin
                result_int    = (data_b_u_ex1 < data_a_u_ex1) ? data_b_u_ex1 : data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vmin.vv, vmin.vx
            funct6_vmin_c : begin
                result_int    = ($signed(data_b_ex1_i) < $signed(data_a_ex1_i)) ? data_b_ex1_i : data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // vmaxu.vv, vmaxu.vx
            funct6_vmaxu_c : begin
                result_int    = (data_b_u_ex1 > data_a_u_ex1) ? data_b_u_ex1 : data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vmax.vv, vmax.vx
            funct6_vmax_c : begin
                result_int    = ($signed(data_b_ex1_i) > $signed(data_a_ex1_i)) ? data_b_ex1_i : data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // vmv.v.v, vmv.v.x, vmv.v.i
            funct6_vmv_c : begin
                result_int    = data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // unknown funct6
            default : begin
                result_int    = '0;
                valid_int_ex1 = 1'b0;
            end
        endcase
    end
    assign result_int_ex1 = result_int;

    // ========================================================================
    // ========================================================================
    // Multiplier/Division Section
    // ========================================================================
    // ========================================================================
    /* controller */
    typedef enum logic[1:0] { S_IDLE, S_BUSY, S_DONE } state_t;
    typedef struct {
        state_t      state;         
        logic  [2:0] cnt;   // iteration counter 
        logic        rs1_is_signed; 
        logic        rs2_is_signed;
        logic        valid_mul;      
        logic        valid_div;    
    } ctrl_t;

    /* multiplier core */
    typedef struct {
        // State registers
        logic   [XLEN+1:0] M_ext;   // sign-extended multiplicand
        logic   [XLEN+1:0] base;    // base partial product, shifted pp
        logic              running; // is running?
        logic [2*XLEN+2:0] prod;    // final product
    } mul_t;

    /* divider core */
    typedef struct { 
        logic [XLEN-1:0] rs2_abs; 
        logic [XLEN-1:0] remainder; 
        logic [XLEN-1:0] quotient;  
        logic            sign_mod; // result sign correction
        logic [XLEN:0]   sub; // try subtraction (and restore if underflow)
    } div_t;

    logic valid;
    logic valid_mul_div;

    assign valid_mul_div = is_multi_cycle & valid_i & ~is_rdc_i;
    assign valid_mul_div_o = {valid_mul_ex4, valid_mul_ex3, valid_mul_ex2, valid_mul_ex1} |
                             {valid_div_ex4, valid_div_ex3, valid_div_ex2, valid_div_ex1};

    // ===============================================
    // MUL, DIV: EX1 BOOTH AND RESTORING ALGRITHM
    // ===============================================
    ctrl_t ctrl_ex1;
    mul_t  mul_ex1;
    div_t  div_ex1;

    // Co-Processor Controller ----------------------------------------------------
    // ----------------------------------------------------------------------------
    always_ff @( posedge clk or negedge rst_n ) begin : coprocessor_ctrl_ex1
        if (!rst_n) begin
            ctrl_ex1.state   <= S_IDLE;
            ctrl_ex1.cnt     <= '0;
            div_ex1.sign_mod <= 1'b0;
            div_ex1.rs2_abs  <= '0;
        end else begin
            /* FSM */
            unique case (ctrl_ex1.state)
                S_IDLE : begin // wait for start signal
                    ctrl_ex1.cnt <= ctrl_ex1.valid_mul ? 3'd3 : 3'd7; // iterative cycle counter
                    //  trigger new operation
                        if (valid) begin
                            if (ctrl_ex1.valid_div) begin
                            /* DIV: check relevant input signs for result sign compensation */
                            if (funct6_i[1:0] == 2'b01) // signed div operation
                                div_ex1.sign_mod <= (data_b_ex1_i[$bits(data_b_ex1_i)-1] ^ data_a_ex1_i[$bits(data_a_ex1_i)-1]) & (|data_a_ex1_i); // different signs AND divisor not zero
                            else if (funct6_i[1:0] == 2'b11) // signed rem operation
                                div_ex1.sign_mod <= data_b_ex1_i[$bits(data_b_ex1_i)-1];
                            else
                                div_ex1.sign_mod <= 1'b0;
                            /* DIV: abs(rs2) */
                            if (data_a_ex1_i[$bits(data_a_ex1_i)-1] && ctrl_ex1.rs2_is_signed) // signed division?
                                div_ex1.rs2_abs <= ~data_a_ex1_i + 1; // make positive
                            else
                                div_ex1.rs2_abs <= data_a_ex1_i;
                        end
                        // next state
                        ctrl_ex1.state <= S_BUSY;
                    end
                end
                S_BUSY : begin // processing
                    ctrl_ex1.cnt <= ctrl_ex1.cnt - 3'b1;
                    if (!(|ctrl_ex1.cnt)) // abort on trap
                        ctrl_ex1.state <= S_DONE;
                end
                S_DONE : begin // final step / enable output for one cycle
                    ctrl_ex1.state <= S_IDLE;
                end
                default: begin // undefined
                    ctrl_ex1.state <= S_IDLE;
                end
            endcase
        end
    end : coprocessor_ctrl_ex1

    /* done? assert one cycle before actual data output */
    assign valid_mul_ex1 = (ctrl_ex1.state == S_DONE) & ctrl_ex1.valid_mul;
    assign valid_div_ex1 = (ctrl_ex1.state == S_DONE) & ctrl_ex1.valid_div;
    assign mul_div_ready = (ctrl_ex1.state == S_IDLE);

    /* co-processor operation */
    /* input operands treated as signed? */
    always_comb begin
        unique case (funct6_i)
            funct6_vmul_c : begin
                // VMUL
                ctrl_ex1.rs1_is_signed = 1'b1;
                ctrl_ex1.rs2_is_signed = 1'b1;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b1;
                ctrl_ex1.valid_div     = 1'b0;
            end
            funct6_vmulh_c : begin
                // VMULH
                ctrl_ex1.rs1_is_signed = 1'b1;
                ctrl_ex1.rs2_is_signed = 1'b1;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b1;
                ctrl_ex1.valid_div     = 1'b0;
            end
            funct6_vmulhsu_c : begin
                // VMULHSU
                ctrl_ex1.rs1_is_signed = 1'b1;
                ctrl_ex1.rs2_is_signed = 1'b0;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b1;
                ctrl_ex1.valid_div     = 1'b0;
            end
            funct6_vmulhu_c : begin
                // VMULHU
                ctrl_ex1.rs1_is_signed = 1'b0;
                ctrl_ex1.rs2_is_signed = 1'b0;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b1;
                ctrl_ex1.valid_div     = 1'b0;
            end
            funct6_vdiv_c, funct6_vrem_c : begin
                // VDIV, VREM
                ctrl_ex1.rs1_is_signed = 1'b1;
                ctrl_ex1.rs2_is_signed = 1'b1;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b0;
                ctrl_ex1.valid_div     = 1'b1;
            end
            funct6_vdivu_c, funct6_vremu_c : begin
                // VDIVU, VREMU
                ctrl_ex1.rs1_is_signed = 1'b0;
                ctrl_ex1.rs2_is_signed = 1'b0;
                valid                  = valid_mul_div;
                ctrl_ex1.valid_mul     = 1'b0;
                ctrl_ex1.valid_div     = 1'b1;
            end
            default : begin
                ctrl_ex1.rs1_is_signed = 1'b0;
                ctrl_ex1.rs2_is_signed = 1'b0;
                valid                  = 1'b0;
                ctrl_ex1.valid_mul     = 1'b0;
                ctrl_ex1.valid_div     = 1'b0;
            end
        endcase
    end

    // Multiplier Core (signed/unsigned) - Iterative ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* serial booth's radix-4 algorithm */
    always_ff @(posedge clk or negedge rst_n) begin : multiplier_core_serial_booth_ex1
        if (!rst_n) begin
            // Reset all registers
            mul_ex1.prod    <= '0;
            mul_ex1.M_ext   <= '0;
            mul_ex1.running <= 1'b0;
        end else begin
            if (valid && ctrl_ex1.valid_mul && !mul_ex1.running) begin
                // Initialize new multiplication
                mul_ex1.M_ext   <= {{2{data_b_ex1_i[XLEN-1] & ctrl_ex1.rs1_is_signed}}, data_b_ex1_i};
                mul_ex1.prod    <= {32'h00000000, {2{data_a_ex1_i[XLEN-1] & ctrl_ex1.rs2_is_signed}}, data_a_ex1_i, 1'b0};
                mul_ex1.running <= 1'b1;
            end else if (mul_ex1.running) begin   
                // Last step?
                if (ctrl_ex1.state == S_DONE) begin
                    mul_ex1.running <= 1'b0;
                end
                // Shift the partial product and accumulate
                mul_ex1.prod[2*XLEN+2:33] <= {{2{mul_ex1.prod[2*XLEN+2]}}, mul_ex1.prod[2*XLEN+2:35]} + mul_ex1.base;
                mul_ex1.prod[32:00]       <= mul_ex1.prod[34:02];
            end
        end
    end : multiplier_core_serial_booth_ex1

    // Booth recoding: look at 3 bits of multiplier
    always_comb begin : booth_recoding_ex1
        unique case (mul_ex1.prod[2:0]) 
            3'b000, 3'b111: mul_ex1.base =  '0;                   //  0
            3'b001, 3'b010: mul_ex1.base =   mul_ex1.M_ext;       // +M
            3'b011:         mul_ex1.base =   mul_ex1.M_ext << 1;  // +2M
            3'b100:         mul_ex1.base = -(mul_ex1.M_ext << 1); // -2M
            3'b101, 3'b110: mul_ex1.base =  -mul_ex1.M_ext;       // -M
            default:        mul_ex1.base =   '0;                  //  0
        endcase           
    end : booth_recoding_ex1

    // Divider Core (unsigned) - Iterative -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* restoring division algorithm */
    always_ff @( posedge clk or negedge rst_n ) begin : divider_core_ex1
        if (!rst_n) begin
            div_ex1.quotient  <= '0;
            div_ex1.remainder <= '0;
        end else if (valid && mul_div_ready && ctrl_ex1.valid_div) begin // start new division
            if (data_b_ex1_i[$bits(data_b_ex1_i)-1] & ctrl_ex1.rs1_is_signed) // signed division ?
               div_ex1.quotient <= ~data_b_ex1_i + 1; // make positive
            else
               div_ex1.quotient <= data_b_ex1_i;
            div_ex1.remainder <= '0;
        end else if ((ctrl_ex1.state == S_BUSY) || (ctrl_ex1.state == S_DONE)) begin // running ?
            div_ex1.quotient <= {div_ex1.quotient[30:0], ~div_ex1.sub[32]};
            if (!div_ex1.sub[32]) // implicit shift
                div_ex1.remainder <= div_ex1.sub[31:0];
            else // underflow: restore and explicit shift
                div_ex1.remainder <= {div_ex1.remainder[30:0], div_ex1.quotient[31]};
        end
    end : divider_core_ex1

    /* try another subtraction (and shift) */
    assign div_ex1.sub = {1'b0, div_ex1.remainder[30:0], div_ex1.quotient[31]} - {1'b0, div_ex1.rs2_abs};

    // ===============================================
    // MUL, DIV: EX2 BOOTH AND RESTORING ALGRITHM
    // ===============================================
    
    ctrl_t ctrl_ex2;
    mul_t  mul_ex2;
    div_t  div_ex2;

    // Co-Processor Controller ----------------------------------------------------
    // ----------------------------------------------------------------------------
    always_ff @( posedge clk or negedge rst_n ) begin : coprocessor_ctrl_ex2
        if (!rst_n) begin
            ctrl_ex2.state   <= S_IDLE;
            div_ex2.sign_mod <= 1'b0;
            ctrl_ex2.cnt     <= '0;
            div_ex2.rs2_abs  <= '0;
        end else begin
            /* FSM */
            unique case (ctrl_ex2.state)
                S_IDLE : begin // wait for start signal
                    ctrl_ex2.cnt <= ctrl_ex2.valid_mul ? 3'd3 : 3'd7; // iterative cycle counter
                    if (valid_div_ex1) begin
                        /* DIV: abs(rs2) */
                        div_ex2.rs2_abs <= div_ex1.rs2_abs;
                        // sign mode
                        div_ex2.sign_mod <= div_ex1.sign_mod;
                    end
                    //  trigger new operation
                    if (valid_mul_ex1 || valid_div_ex1) begin
                        ctrl_ex2.state <= S_BUSY;  
                    end
                end
                S_BUSY : begin // processing
                    ctrl_ex2.cnt <= ctrl_ex2.cnt - 3'b1;
                    if (!(|ctrl_ex2.cnt)) // abort on trap
                        ctrl_ex2.state <= S_DONE;
                end
                S_DONE : begin // final step / enable output for one cycle
                    ctrl_ex2.state  <= S_IDLE;
                end
                default: begin // undefined
                    ctrl_ex2.state <= S_IDLE;
                end
            endcase
        end
    end : coprocessor_ctrl_ex2

    /* done? assert one cycle before actual data output */
    assign valid_mul_ex2 = (ctrl_ex2.state == S_DONE) & ctrl_ex2.valid_mul;
    assign valid_div_ex2 = (ctrl_ex2.state == S_DONE) & ctrl_ex2.valid_div;

    /* co-processor operation */
    assign ctrl_ex2.rs1_is_signed = 1'b0;
    assign ctrl_ex2.rs2_is_signed = 1'b0;
    assign ctrl_ex2.valid_mul     = ctrl_ex1.valid_mul;
    assign ctrl_ex2.valid_div     = ctrl_ex1.valid_div;

    // Multiplier Core (signed/unsigned) - Iterative ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* serial booth's radix-4 algorithm */
    always_ff @(posedge clk or negedge rst_n) begin : multiplier_core_serial_boot_ex2
        if (!rst_n) begin
            // Reset all registers
            mul_ex2.prod    <= '0;
            mul_ex2.M_ext   <= '0;
            mul_ex2.running <= 1'b0;
        end else begin
            if (valid_mul_ex1 && ctrl_ex2.valid_mul && !mul_ex2.running) begin
                // Initialize new multiplication
                mul_ex2.M_ext   <= mul_ex1.M_ext;
                mul_ex2.prod    <= mul_ex1.prod;
                mul_ex2.running <= 1'b1;
            end else if (mul_ex2.running) begin   
                // Last step?
                if (ctrl_ex2.state == S_DONE) begin
                    mul_ex2.running <= 1'b0;
                end
                // Shift the partial product and accumulate
                mul_ex2.prod[2*XLEN+2:33] <= {{2{mul_ex2.prod[2*XLEN+2]}}, mul_ex2.prod[2*XLEN+2:35]} + mul_ex2.base;
                mul_ex2.prod[32:00]       <= mul_ex2.prod[34:02];
            end
        end
    end : multiplier_core_serial_boot_ex2

    // Booth recoding: look at 3 bits of multiplier
    always_comb begin : booth_recoding_ex2
        unique case (mul_ex2.prod[2:0]) 
            3'b000, 3'b111: mul_ex2.base =  '0;                   //  0
            3'b001, 3'b010: mul_ex2.base =   mul_ex2.M_ext;       // +M
            3'b011:         mul_ex2.base =   mul_ex2.M_ext << 1;  // +2M
            3'b100:         mul_ex2.base = -(mul_ex2.M_ext << 1); // -2M
            3'b101, 3'b110: mul_ex2.base =  -mul_ex2.M_ext;       // -M
            default:        mul_ex2.base =   '0;                  //  0
        endcase           
    end : booth_recoding_ex2

    // Divider Core (unsigned) - Iterative -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* restoring division algorithm */
    always_ff @( posedge clk or negedge rst_n ) begin : divider_core_ex2
        if (!rst_n) begin
            div_ex2.quotient  <= '0;
            div_ex2.remainder <= '0;
        end else if (valid_div_ex1 && ctrl_ex2.valid_div) begin // start new division
            div_ex2.quotient <= div_ex1.quotient;
            div_ex2.remainder <= div_ex1.remainder;
        end else if ((ctrl_ex2.state == S_BUSY) || (ctrl_ex2.state == S_DONE)) begin // running ?
            div_ex2.quotient <= {div_ex2.quotient[30:0], ~div_ex2.sub[32]};
            if (!div_ex2.sub[32]) // implicit shift
                div_ex2.remainder <= div_ex2.sub[31:0];
            else // underflow: restore and explicit shift
                div_ex2.remainder <= {div_ex2.remainder[30:0], div_ex2.quotient[31]};
        end
    end : divider_core_ex2

    /* try another subtraction (and shift) */
    assign div_ex2.sub = {1'b0, div_ex2.remainder[30:0], div_ex2.quotient[31]} - {1'b0, div_ex2.rs2_abs};

    // ===============================================
    // MUL, DIV: EX3 BOOTH AND RESTORING ALGRITHM
    // ===============================================
    ctrl_t ctrl_ex3;
    mul_t  mul_ex3;
    div_t  div_ex3;

    // Co-Processor Controller ----------------------------------------------------
    // ----------------------------------------------------------------------------
    always_ff @( posedge clk or negedge rst_n ) begin : coprocessor_ctrl_ex3
        if (!rst_n) begin
            ctrl_ex3.state   <= S_IDLE;
            div_ex3.sign_mod <= 1'b0;
            div_ex3.rs2_abs  <= '0;
            ctrl_ex3.cnt     <= '0;
        end else begin
            /* FSM */
            unique case (ctrl_ex3.state)
                S_IDLE : begin // wait for start signal
                    ctrl_ex3.cnt <= ctrl_ex3.valid_mul ? 3'd3 : 3'd7; // iterative cycle counter
                    if (valid_div_ex2) begin
                        /* DIV: abs(rs2) */
                        div_ex3.rs2_abs <= div_ex2.rs2_abs;
                        // sign mode
                        div_ex3.sign_mod <= div_ex2.sign_mod;
                    end
                    //  trigger new operation
                    if (valid_mul_ex2 || valid_div_ex2) begin
                        ctrl_ex3.state <= S_BUSY;  
                    end
                end
                S_BUSY : begin // processing
                    ctrl_ex3.cnt <= ctrl_ex3.cnt - 3'b1;
                    if (!(|ctrl_ex3.cnt)) // abort on trap
                        ctrl_ex3.state <= S_DONE;
                end
                S_DONE : begin // final step / enable output for one cycle
                    ctrl_ex3.state  <= S_IDLE;
                end
                default: begin // undefined
                    ctrl_ex3.state <= S_IDLE;
                end
            endcase
        end
    end : coprocessor_ctrl_ex3

    /* done? assert one cycle before actual data output */
    assign valid_mul_ex3 = (ctrl_ex3.state == S_DONE) & ctrl_ex3.valid_mul;
    assign valid_div_ex3 = (ctrl_ex3.state == S_DONE) & ctrl_ex3.valid_div;

    /* co-processor operation */
    assign ctrl_ex3.rs1_is_signed = 1'b0;
    assign ctrl_ex3.rs2_is_signed = 1'b0;
    assign ctrl_ex3.valid_mul     = ctrl_ex2.valid_mul;
    assign ctrl_ex3.valid_div     = ctrl_ex2.valid_div;

    // Multiplier Core (signed/unsigned) - Iterative ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* serial booth's radix-4 algorithm */
    always_ff @(posedge clk or negedge rst_n) begin : multiplier_core_serial_booth_ex3
        if (!rst_n) begin
            // Reset all registers
            mul_ex3.prod    <= '0;
            mul_ex3.M_ext   <= '0;
            mul_ex3.running <= 1'b0;
        end else begin
            if (valid_mul_ex2 && ctrl_ex3.valid_mul && !mul_ex3.running) begin
                // Initialize new multiplication
                mul_ex3.M_ext   <= mul_ex2.M_ext;
                mul_ex3.prod    <= mul_ex2.prod;
                mul_ex3.running <= 1'b1;
            end else if (mul_ex3.running) begin   
                // Last step?
                if (ctrl_ex3.state == S_DONE) begin
                    mul_ex3.running <= 1'b0;
                end
                // Shift the partial product and accumulate
                mul_ex3.prod[2*XLEN+2:33] <= {{2{mul_ex3.prod[2*XLEN+2]}}, mul_ex3.prod[2*XLEN+2:35]} + mul_ex3.base;
                mul_ex3.prod[32:00]       <= mul_ex3.prod[34:02];
            end
        end
    end : multiplier_core_serial_booth_ex3

    // Booth recoding: look at 3 bits of multiplier
    always_comb begin : booth_recoding_ex3
        unique case (mul_ex3.prod[2:0]) 
            3'b000, 3'b111: mul_ex3.base =  '0;                   //  0
            3'b001, 3'b010: mul_ex3.base =   mul_ex3.M_ext;       // +M
            3'b011:         mul_ex3.base =   mul_ex3.M_ext << 1;  // +2M
            3'b100:         mul_ex3.base = -(mul_ex3.M_ext << 1); // -2M
            3'b101, 3'b110: mul_ex3.base =  -mul_ex3.M_ext;       // -M
            default:        mul_ex3.base =   '0;                  //  0
        endcase           
    end : booth_recoding_ex3

    // Divider Core (unsigned) - Iterative -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* restoring division algorithm */
    always_ff @( posedge clk or negedge rst_n ) begin : divider_core_ex3
        if (!rst_n) begin
            div_ex3.quotient  <= '0;
            div_ex3.remainder <= '0;
        end else if (valid_div_ex2 && ctrl_ex3.valid_div) begin // start new division
            div_ex3.quotient <= div_ex2.quotient;
            div_ex3.remainder <= div_ex2.remainder;
        end else if ((ctrl_ex3.state == S_BUSY) || (ctrl_ex3.state == S_DONE)) begin // running ?
            div_ex3.quotient <= {div_ex3.quotient[30:0], ~div_ex3.sub[32]};
            if (!div_ex3.sub[32]) // implicit shift
                div_ex3.remainder <= div_ex3.sub[31:0];
            else // underflow: restore and explicit shift
                div_ex3.remainder <= {div_ex3.remainder[30:0], div_ex3.quotient[31]};
        end
    end : divider_core_ex3

    /* try another subtraction (and shift) */
    assign div_ex3.sub = {1'b0, div_ex3.remainder[30:0], div_ex3.quotient[31]} - {1'b0, div_ex3.rs2_abs};

    // ===============================================
    // MUL, DIV: EX4 BOOTH AND RESTORING ALGRITHM
    // ===============================================
    ctrl_t ctrl_ex4;
    mul_t  mul_ex4;
    div_t  div_ex4;
    logic valid_mul_div_ex4;

    // Co-Processor Controller ----------------------------------------------------
    // ----------------------------------------------------------------------------
    always_ff @( posedge clk or negedge rst_n ) begin : coprocessor_ctrl_ex4
        if (!rst_n) begin
            ctrl_ex4.state    <= S_IDLE;
            div_ex4.sign_mod  <= 1'b0;
            div_ex4.rs2_abs   <= '0;
            ctrl_ex4.cnt      <= '0;
            valid_mul_div_ex4 <= 1'b0;
        end else begin
            // default value
            valid_mul_div_ex4 <= 1'b0;
            /* FSM */
            unique case (ctrl_ex4.state)
                S_IDLE : begin // wait for start signal
                    ctrl_ex4.cnt <= ctrl_ex4.valid_mul ? 3'd3 : 3'd6; // iterative cycle counter
                    if (valid_div_ex3) begin
                        /* DIV: abs(rs2) */
                        div_ex4.rs2_abs <= div_ex3.rs2_abs;
                        // sign mode
                        div_ex4.sign_mod <= div_ex3.sign_mod;
                    end
                    // trigger new operation
                    if (valid_mul_ex3 || valid_div_ex3) begin
                        ctrl_ex4.state <= S_BUSY;
                    end
                end
                S_BUSY : begin // processing
                    ctrl_ex4.cnt <= ctrl_ex4.cnt - 3'b1;
                    if (!(|ctrl_ex4.cnt)) // abort on trap
                        ctrl_ex4.state <= S_DONE;
                end
                S_DONE : begin // final step / enable output for one cycle
                    ctrl_ex4.state    <= S_IDLE;
                    valid_mul_div_ex4 <= 1'b1;
                end
                default: begin // undefined
                    ctrl_ex4.state <= S_IDLE;
                end
            endcase
        end
    end : coprocessor_ctrl_ex4

    /* co-processor operation */
    assign ctrl_ex4.rs1_is_signed = 1'b0;
    assign ctrl_ex4.rs2_is_signed = 1'b0;
    assign ctrl_ex4.valid_mul     = ctrl_ex3.valid_mul;
    assign ctrl_ex4.valid_div     = ctrl_ex3.valid_div;

    assign valid_mul_ex4 = valid_mul_div_ex4 & ctrl_ex4.valid_mul;
    assign valid_div_ex4 = valid_mul_div_ex4 & ctrl_ex4.valid_div;

    // Multiplier Core (signed/unsigned) - Iterative ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* serial booth's radix-4 algorithm */
    always_ff @(posedge clk or negedge rst_n) begin : multiplier_core_serial_booth_ex4
        if (!rst_n) begin
            // Reset all registers
            mul_ex4.prod    <= '0;
            mul_ex4.M_ext   <= '0;
            mul_ex4.running <= 1'b0;
        end else begin
            if (valid_mul_ex3 && ctrl_ex4.valid_mul && !mul_ex4.running) begin
                // Initialize new multiplication
                mul_ex4.M_ext   <= mul_ex3.M_ext;
                mul_ex4.prod    <= mul_ex3.prod;
                mul_ex4.running <= 1'b1;
            end else if (mul_ex4.running) begin   
                // Last step?
                if (ctrl_ex4.state == S_DONE) begin
                    mul_ex4.running <= 1'b0;
                end
                // Shift the partial product and accumulate
                mul_ex4.prod[2*XLEN+2:33] <= {{2{mul_ex4.prod[2*XLEN+2]}}, mul_ex4.prod[2*XLEN+2:35]} + mul_ex4.base;
                mul_ex4.prod[32:00]       <= mul_ex4.prod[34:02];
            end
        end
    end : multiplier_core_serial_booth_ex4

    // Booth recoding: look at 3 bits of multiplier
    always_comb begin : booth_recoding_ex4
        unique case (mul_ex4.prod[2:0]) 
            3'b000, 3'b111: mul_ex4.base =  '0;                   //  0
            3'b001, 3'b010: mul_ex4.base =   mul_ex4.M_ext;       // +M
            3'b011:         mul_ex4.base =   mul_ex4.M_ext << 1;  // +2M
            3'b100:         mul_ex4.base = -(mul_ex4.M_ext << 1); // -2M
            3'b101, 3'b110: mul_ex4.base =  -mul_ex4.M_ext;       // -M
            default:        mul_ex4.base =   '0;                  //  0
        endcase           
    end : booth_recoding_ex4

    // Divider Core (unsigned) - Iterative -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* restoring division algorithm */
    always_ff @( posedge clk or negedge rst_n ) begin : divider_core_ex4
        if (!rst_n) begin
            div_ex4.quotient <= '0;
            div_ex4.remainder <= '0;
        end else if (valid_div_ex3 && ctrl_ex4.valid_div) begin // start new division
            div_ex4.quotient <= div_ex3.quotient;
            div_ex4.remainder <= div_ex3.remainder;
        end else if ((ctrl_ex4.state == S_BUSY) || (ctrl_ex4.state == S_DONE)) begin // running ?
            div_ex4.quotient <= {div_ex4.quotient[30:0], ~div_ex4.sub[32]};
            if (!div_ex4.sub[32]) // implicit shift
                div_ex4.remainder <= div_ex4.sub[31:0];
            else // underflow: restore and explicit shift
                div_ex4.remainder <= {div_ex4.remainder[30:0], div_ex4.quotient[31]};
        end
    end : divider_core_ex4

    /* try another subtraction (and shift) */
    assign div_ex4.sub = {1'b0, div_ex4.remainder[30:0], div_ex4.quotient[31]} - {1'b0, div_ex4.rs2_abs};

    // ---------------------------------------------------------
    // Multiplier/Division Outputs
    // ---------------------------------------------------------
    assign result_mul_ex4 = (funct6_i == funct6_vmul_c) ? mul_ex4.prod[1      +: XLEN] : 
                                                          mul_ex4.prod[XLEN+1 +: XLEN];
    /* division result and sign compensation */
    logic [XLEN-1:0] div_res_u; // unsigned result

    assign div_res_u      = ((funct6_i == funct6_vdiv_c) || (funct6_i == funct6_vdivu_c)) ? div_ex4.quotient : div_ex4.remainder;
    assign result_div_ex4 = div_ex4.sign_mod ? (~div_res_u + 1) : div_res_u;

    //================================================
    // Reduction Tree Section
    //================================================
    // Lane 0 ─┐
    //      ├─ EX1 ─┐
    // Lane 1 ─┘    │
    //              ├─ EX2 ─┐
    // Lane 2 ─┐    │       │
    //      ├─ EX1 ─┘       │
    // Lane 3 ─┘            ├─ EX3 ─────┬──── EX4 ===> Final Result
    //                      │           │ 
    // Lane 4 ─┐            │           │ 
    //      ├─ EX1 ─┐       │           │ 
    // Lane 5 ─┘    │       │           │ 
    //              ├─ EX2 ─┘           │ 
    // Lane 6 ─┐    │                   │ 
    //      ├─ EX1 ─┘                   │ 
    // Lane 7 ─┘                        │ 
    // .....   ─────────────────────────┘

    // ===============================================
    // RDC:EX1
    // ===============================================
    logic [      6:0] vl_ex2, vl_ex3;
    logic [ XLEN-1:0] tree_result_ex1, tree_result_ex2;
    logic [ XLEN-1:0] tree_result_ex3;

    logic active_rdc_ex1, active_rdc_ex2, active_rdc_ex3;
    logic valid_rdc_ex1, valid_rdc_ex2, valid_rdc_ex3;

    generate if (!VECTOR_LANE_NUM[0]) begin: g_rdc_ex1
        logic odd_rdc_override;
        // If the vector has an odd number of elements,
        // the last lane has no pairs to merge.
        assign odd_rdc_override = ((vl_i - 1) == VECTOR_LANE_NUM);
        always_comb begin
            case (funct6_i)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i + rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredand_c : begin
                    // VRAND
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i & rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredor_c : begin
                    // VROR
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i | rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i ^ rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      (data_b_u_ex1 < rdc_data_ex1_i) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      ($signed(data_b_ex1_i) < $signed(rdc_data_ex1_i)) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      (data_b_u_ex1 > rdc_data_ex1_i) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      ($signed(data_b_ex1_i) > $signed(rdc_data_ex1_i)) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i & valid_i;
                    valid_rdc_ex1   = valid_i & (vl_i <= 'd2);
                end
                default : begin
                    tree_result_ex1 = '0;
                    active_rdc_ex1  = 1'b0;
                    valid_rdc_ex1   = 1'b0;
                end
            endcase
        end

        assign result_rdc_ex1 = tree_result_ex1;

    end else begin: g_rdc_ex1_stubs
        assign result_rdc_ex1 = data_b_ex1_i;
        assign active_rdc_ex1 = is_rdc_i;
        assign valid_rdc_ex1  = 1'b0;
    end endgenerate
    // ===============================================
    // RDC:EX2
    // ===============================================
    generate if (VECTOR_LANES > 2 & VECTOR_LANE_NUM[1:0] == 2'b00) begin: g_rdc_ex2
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                active_rdc_ex2 <= 1'b0;
            end else begin
                active_rdc_ex2 <= active_rdc_ex1;
                vl_ex2         <= vl_i;
            end
        end

        assign valid_rdc_ex2  = active_rdc_ex2 & (vl_ex2 <= 'd4);
        // EX2 outputs
        always_comb begin
            case (funct6_i)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex2 = data_ex2_i + rdc_data_ex2_i;
                end
                funct6_vredand_c : begin
                    // VRAND
                    tree_result_ex2 = data_ex2_i & rdc_data_ex2_i;
                end
                funct6_vredor_c : begin
                    // VROR
                    tree_result_ex2 = data_ex2_i | rdc_data_ex2_i;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    tree_result_ex2 = data_ex2_i ^ rdc_data_ex2_i;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex2 = (data_ex2_i < rdc_data_ex2_i) ? data_ex2_i : rdc_data_ex2_i;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex2 = ($signed(data_ex2_i) < $signed(rdc_data_ex2_i)) ? data_ex2_i : rdc_data_ex2_i;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex2 = (data_ex2_i > rdc_data_ex2_i) ? data_ex2_i : rdc_data_ex2_i;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex2 = ($signed(data_ex2_i) > $signed(rdc_data_ex2_i)) ? data_ex2_i : rdc_data_ex2_i;
                end
                default : begin
                    tree_result_ex2 = '0;
                end
            endcase
        end

        assign result_rdc_ex2 = tree_result_ex2;

    end else begin: g_rdc_ex2_stubs
        assign result_rdc_ex2 = data_ex2_i;
        assign active_rdc_ex2 = active_rdc_ex1;
        assign valid_rdc_ex2  = valid_rdc_ex1;
    end endgenerate
    // ===============================================
    // RDC:EX3
    // ===============================================
    generate if (VECTOR_LANES > 4 & VECTOR_LANE_NUM[2:0] == 3'b000) begin: g_rdc_ex3
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                active_rdc_ex3 <= 0;
            end else begin
                active_rdc_ex3 <= active_rdc_ex2;
                vl_ex3         <= vl_ex2;
            end
        end

        assign valid_rdc_ex3  = active_rdc_ex3 & (vl_ex3 <= 'd8);
        // EX3 outputs
        always_comb begin
            case (funct6_i)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex3 = data_ex3_i + rdc_data_ex3_i;
                end
                funct6_vredand_c: begin
                    // VRAND
                    tree_result_ex3 = data_ex3_i & rdc_data_ex3_i;
                end
                funct6_vredor_c: begin
                    // VROR
                    tree_result_ex3 = data_ex3_i | rdc_data_ex3_i;
                end
                funct6_vredxor_c: begin
                    // VRXOR
                    tree_result_ex3 = data_ex3_i ^ rdc_data_ex3_i;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex3 = (data_ex3_i < rdc_data_ex3_i) ? data_ex3_i : rdc_data_ex3_i;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex3 = ($signed(data_ex3_i) < $signed(rdc_data_ex3_i)) ? data_ex3_i : rdc_data_ex3_i;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex3 = (data_ex3_i > rdc_data_ex3_i) ? data_ex3_i : rdc_data_ex3_i;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex3 = ($signed(data_ex3_i) > $signed(rdc_data_ex3_i)) ? data_ex3_i : rdc_data_ex3_i;
                end
                default : begin
                    tree_result_ex3 = '0;
                end
            endcase
        end

        assign result_rdc_ex3 = tree_result_ex3;

    end else begin: g_rdc_ex3_stubs
        assign result_rdc_ex3 = data_ex3_i;
        assign active_rdc_ex3 = active_rdc_ex2;
        assign valid_rdc_ex3  = valid_rdc_ex2;
    end endgenerate

    // ================================================
    // Outputs
    // ================================================
    // EX1 Out
    assign ready_res_ex1_o = valid_int_ex1  | valid_rdc_ex1;   //indicate ready result
    assign result_ex1_o    = active_rdc_ex1 ? result_rdc_ex1 :
                             ~mask_i        ? '0             :
                             valid_int_ex1  ? result_int_ex1 : '0;
    // EX2 Out
    assign result_ex2_o    = active_rdc_ex2 ? result_rdc_ex2 : '0;
    // EX3 Out
    assign ready_res_ex3_o = valid_rdc_ex3;   //indicate ready result
    assign result_ex3_o    = active_rdc_ex3 ? result_rdc_ex3 : '0;
    // EX4 Out
    assign ready_res_ex4_o = valid_mul_ex4  | valid_div_ex4; //indicate ready result
    assign result_ex4_o    = valid_mul_ex4  ? result_mul_ex4 :
                             valid_div_ex4  ? result_div_ex4 : '0;

endmodule