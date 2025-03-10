// ##################################################################################################
// # << CELLRV32 - Single-Precision Floating-Point Unit: Normalizer and Rounding Unit >>            #
// # ***********************************************************************************************#
// # This unit also performs int-to-float conversions.                                          #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_fpu_normalizer (
    /* control */
    input logic       clk_i,      // global clock, rising edge
    input logic       rstn_i,     // global reset, low-active, async
    input logic       start_i,    // trigger operation
    input logic [2:0] rmode_i,    // rounding mode
    input logic       funct_i,    // operating mode (0=norm&round, 1=int-to-float)
    /* input */
    input logic        sign_i,     // sign
    input logic [8:0]  exponent_i, // extended exponent
    input logic [47:0] mantissa_i, // extended mantissa
    input logic [31:0] integer_i,  // int input
    input logic [9:0]  class_i,    // input number class
    input logic [4:0]  flags_i,    // exception flags input
    /* output */
    output logic [31:0] result_o,   // float result
    output logic [4:0]  flags_o,    // exception flags output
    output logic        done_o      // operation done
);
    
    /* controller */
    typedef enum logic[3:0] { S_IDLE, 
                              S_PREPARE_I2F, 
                              S_CHECK_I2F, 
                              S_PREPARE_NORM, 
                              S_PREPARE_SHIFT, 
                              S_NORMALIZE_BUSY, 
                              S_ROUND, 
                              S_CHECK, 
                              S_FINALIZE } ctrl_engine_state_t;
    
    typedef struct {
        ctrl_engine_state_t state; // current state
        logic norm_r; // normalization round 0 or 1
        logic [8:0] cnt; // interation counter/exponent (incl. overflow)
        logic [8:0] cnt_pre; 
        logic cnt_of;  // counter overflow
        logic cnt_uf;  // counter underflow
        logic rounded; // output is rounded
        logic res_sgn;
        logic [7:0]  res_exp;
        logic [22:0] res_man;
        logic [9:0]  class_data;
        logic [4:0]  flags;
    } ctrl_t;
    ctrl_t ctrl;

    typedef struct {
        logic done;  
        logic dir; // shift direction: 0=right, 1=left
        logic zero;  
        logic [31:0] upper; 
        logic [22:0] lower; 
        logic ext_g; // guard bit
        logic ext_r; // round bit
        logic ext_s; // sticky bit
    } sreg_t;
    sreg_t sreg;

    /* rounding unit */
    typedef struct {
        logic en; // enable rounding
        logic sub; // 0=decrement, 1=increment
        logic [24:0] output_data; // mantissa size + hidden one + 1
    } round_t;
    round_t round;

    // Control Engine ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : ctrl_engine
        if (rstn_i == 1'b0) begin
           ctrl.state      <= S_IDLE;
           ctrl.norm_r     <= 1'b0;
           ctrl.cnt        <= '0;
           ctrl.cnt_pre    <= '0;
           ctrl.cnt_of     <= 1'b0;
           ctrl.cnt_uf     <= 1'b0;
           ctrl.rounded    <= 1'b0;
           ctrl.res_exp    <= '0;
           ctrl.res_man    <= '0;
           ctrl.res_sgn    <= 1'b0;
           ctrl.class_data <= '0;
           ctrl.flags      <= '0;
           //
           sreg.upper   <= '0;
           sreg.lower   <= '0;
           sreg.dir     <= 1'b0;
           sreg.ext_g   <= 1'b0;
           sreg.ext_r   <= 1'b0;
           sreg.ext_s   <= 1'b0;
           //
           done_o       <= 1'b0;
        end else begin
            /* defaults */
            ctrl.cnt_pre <= ctrl.cnt;
            done_o       <= 1'b0;

            /* exponent counter underflow/overflow */
            if ((ctrl.cnt_pre[8:7] == 2'b01) && (ctrl.cnt[8:7] == 2'b10)) // overflow
               ctrl.cnt_of <= 1'b1;
            else if ((ctrl.cnt_pre[8:7] == 2'b00) && (ctrl.cnt[8:7] == 2'b11)) // underflow
               ctrl.cnt_uf <= 1'b1;

            /* FSM */
            unique case (ctrl.state)
                // --------------------------------------------------------------
                // wait for operation trigger
                S_IDLE : begin 
                    ctrl.norm_r  <= 1'b0; // start with first normalization
                    ctrl.rounded <= 1'b0; // not rounded yet
                    ctrl.cnt_of  <= 1'b0;
                    ctrl.cnt_uf  <= 1'b0;
                    //
                    if (start_i == 1'b1) begin
                        ctrl.cnt        <= exponent_i;
                        ctrl.res_sgn    <= sign_i;
                        ctrl.class_data <= class_i;
                        ctrl.flags      <= flags_i;
                        // float --> float
                        if (funct_i == 1'b0)
                            ctrl.state <= S_PREPARE_NORM;
                        else // int --> float
                            ctrl.state <= S_PREPARE_I2F;
                    end 
                end
                // --------------------------------------------------------------
                // prepare int-to-float conversion
                S_PREPARE_I2F : begin 
                    sreg.upper <= integer_i;
                    sreg.lower <= '0;
                    sreg.ext_g <= 1'b0;
                    sreg.ext_r <= 1'b0;
                    sreg.ext_s <= 1'b0;
                    sreg.dir   <= 1'b0; // shift right
                    ctrl.state <= S_CHECK_I2F;
                end
                // --------------------------------------------------------------
                // check if converting zero
                S_CHECK_I2F : begin 
                    if (sreg.zero == 1'b1) begin // all zero
                        ctrl.class_data[fp_class_pos_zero_c] <= 1'b1;
                        ctrl.state <= S_FINALIZE;
                    end else begin
                        ctrl.state <= S_NORMALIZE_BUSY;
                    end
                end
                // --------------------------------------------------------------
                // prepare "normal" normalization & rounding
                S_PREPARE_NORM : begin 
                    sreg.upper[31:2] <= '0;
                    sreg.upper[1:0]  <= mantissa_i[47:46];
                    sreg.lower <= mantissa_i[45:23];
                    sreg.ext_g <= mantissa_i[22];
                    sreg.ext_r <= mantissa_i[21];
                    //
                    if ((|mantissa_i[20:0]) == 1'b1) begin
                         sreg.ext_s <= 1'b1;
                    end else begin
                         sreg.ext_s <= 1'b0;
                    end
                    // check for special cases
                    if ((ctrl.class_data[fp_class_snan_c]       || ctrl.class_data[fp_class_qnan_c]       || // NaN
                         ctrl.class_data[fp_class_neg_zero_c]   || ctrl.class_data[fp_class_pos_zero_c]   || // zero
                         ctrl.class_data[fp_class_neg_denorm_c] || ctrl.class_data[fp_class_pos_denorm_c] || // subnormal
                         ctrl.class_data[fp_class_neg_inf_c]    || ctrl.class_data[fp_class_pos_inf_c]    || // infinity
                         ctrl.flags[fp_exc_uf_c] || // underflow
                         ctrl.flags[fp_exc_of_c] || // overflow
                         ctrl.flags[fp_exc_nv_c]) == 1'b1) begin // invalid
                        ctrl.state <= S_FINALIZE;
                    end else begin
                        ctrl.state <= S_PREPARE_SHIFT;
                    end
                end
                // --------------------------------------------------------------
                // prepare shift direction (for "normal" normalization only)
                S_PREPARE_SHIFT : begin 
                    if (sreg.zero == 1'b0) begin // number < 1.0
                        sreg.dir <= 1'b0; // shift right
                    end else begin
                        sreg.dir <= 1'b1; // shift left
                    end
                    ctrl.state <= S_NORMALIZE_BUSY;
                end
                // --------------------------------------------------------------
                // running normalization cycle
                S_NORMALIZE_BUSY : begin 
                    /* shift until normalized or exception */
                    if ((sreg.done == 1'b1) || (ctrl.cnt_uf == 1'b1) || (ctrl.cnt_of == 1'b1)) begin
                        /* normalization control */
                        ctrl.norm_r <= 1'b1;
                        //
                        if (ctrl.norm_r == 1'b0) begin // first normalization cycle done
                            ctrl.state <= S_ROUND;
                        end else begin // second normalization cycle done
                            ctrl.state <= S_CHECK;
                        end
                    end else begin
                        if (sreg.dir == 1'b0) begin // shift right
                            ctrl.cnt   <= ctrl.cnt + 1'b1;
                            sreg.upper <= {1'b0, sreg.upper[$bits(sreg.upper)-1:1]};
                            sreg.lower <= {sreg.upper[0], sreg.lower[$bits(sreg.lower)-1:1]};
                            sreg.ext_g <= sreg.lower[0];
                            sreg.ext_r <= sreg.ext_g;
                            sreg.ext_s <= sreg.ext_r | sreg.ext_s; // sticky bit
                        end else begin // shift left
                            ctrl.cnt   <= ctrl.cnt - 1'b1;
                            sreg.upper <= {sreg.upper[$bits(sreg.upper)-2:0], sreg.lower[$bits(sreg.lower)-1]};
                            sreg.lower <= {sreg.lower[$bits(sreg.lower)-2:0], sreg.ext_g};
                            sreg.ext_g <= sreg.ext_r;
                            sreg.ext_r <= sreg.ext_s;
                            sreg.ext_s <= sreg.ext_s; // sticky bit
                        end
                    end
                end
                // --------------------------------------------------------------
                // rounding cycle (after first normalization)
                S_ROUND : begin 
                    ctrl.rounded <= ctrl.rounded | round.en;
                    sreg.upper[31:02] <= '0;
                    sreg.upper[01:00] <= round.output_data[24:23];
                    sreg.lower <= round.output_data[22:0];
                    sreg.ext_g <= 1'b0;
                    sreg.ext_r <= 1'b0;
                    sreg.ext_s <= 1'b0;
                    ctrl.state <= S_PREPARE_SHIFT;
                end
                // --------------------------------------------------------------
                // check for overflow/underflow
                S_CHECK : begin 
                    if (ctrl.cnt_uf == 1'b1) begin // underflow
                        ctrl.flags[fp_exc_uf_c] <= 1'b1;
                    end else if (ctrl.cnt_of == 1'b1) begin // overflow
                        ctrl.flags[fp_exc_of_c] <= 1'b1;
                    end else if (ctrl.cnt[7:0] == 8'h00) begin // subnormal
                        ctrl.flags[fp_exc_uf_c] <= 1'b1;
                    end else if (ctrl.cnt[7:0] == 8'hff) begin // infinity
                        ctrl.flags[fp_exc_of_c] <= 1'b1;
                    end
                    ctrl.state <= S_FINALIZE;
                end
                // --------------------------------------------------------------
                // result finalization
                S_FINALIZE : begin 
                    /* generate result word (the ORDER of checks is imporatant here!) */
                    // sNaN / qNaN
                    if ((ctrl.class_data[fp_class_snan_c] == 1'b1) || (ctrl.class_data[fp_class_qnan_c] == 1'b1)) begin
                        ctrl.res_sgn <= fp_single_qnan_c[31];
                        ctrl.res_exp <= fp_single_qnan_c[30:23];
                        ctrl.res_man <= fp_single_qnan_c[22:00];
                    //
                    end else if ((ctrl.class_data[fp_class_neg_inf_c] == 1'b1) ||
                                 (ctrl.class_data[fp_class_pos_inf_c] == 1'b1) ||  // infinity
                                 (ctrl.flags[fp_exc_of_c] == 1'b1)) begin // overflow
                        ctrl.res_exp <= fp_single_pos_inf_c[30:23]; // keep original sign
                        ctrl.res_man <= fp_single_pos_inf_c[22:00];
                    //
                    end else if ((ctrl.class_data[fp_class_neg_zero_c] == 1'b1) || 
                                (ctrl.class_data[fp_class_pos_zero_c] == 1'b1)) begin // zero
                        ctrl.res_sgn <= ctrl.class_data[fp_class_neg_zero_c];
                        ctrl.res_exp <= fp_single_pos_zero_c[30:23];
                        ctrl.res_man <= fp_single_pos_zero_c[22:00];  
                    //    
                    end else if ((ctrl.flags[fp_exc_uf_c] == 1'b1) || // underflow
                                 (sreg.zero == 1'b1) || 
                                (ctrl.class_data[fp_class_neg_denorm_c] == 1'b1) || 
                                (ctrl.class_data[fp_class_pos_denorm_c] == 1'b1)) begin // denormalized (flush-to-zero)
                        ctrl.res_exp <= fp_single_pos_zero_c[30:23]; // keep original sign
                        ctrl.res_man <= fp_single_pos_zero_c[22:00];     
                    //      
                    end else begin // result is OK
                        ctrl.res_exp <= ctrl.cnt[7:0];
                        ctrl.res_man <= sreg.lower;
                    end
                    /* generate exception flags */
                    ctrl.flags[fp_exc_nv_c] <= ctrl.flags[fp_exc_nv_c] | ctrl.class_data[fp_class_snan_c]; // invalid if input is SIGNALING NaN
                    ctrl.flags[fp_exc_nx_c] <= ctrl.flags[fp_exc_nx_c] | ctrl.rounded; // inexcat if result is rounded
                    //
                    done_o     <= 1'b1;
                    ctrl.state <= S_IDLE;
                end
                // --------------------------------------------------------------
                // --------------------------------------------------------------
                default: begin // undefined
                    ctrl.state <= S_IDLE;
                end
            endcase
        end
    end : ctrl_engine

    /* stop shifting when normalized */
    assign sreg.done = (((|sreg.upper[$bits(sreg.upper)-1:1]) == 1'b0) &&
                        (sreg.upper[0] == 1'b1)) ? 1'b1 : 1'b0; // input is zero, hidden one is set

    // all-zero including hidden bit */
    assign sreg.zero = ((|sreg.upper) == 1'b0) ? 1'b1 : 1'b0;

    /* result */
    assign result_o[31]    = ctrl.res_sgn;
    assign result_o[30:23] = ctrl.res_exp;
    assign result_o[22:00] = ctrl.res_man;

    /* exception flags */
    assign flags_o[fp_exc_nv_c] = ctrl.flags[fp_exc_nv_c]; // invalid operation
    assign flags_o[fp_exc_dz_c] = ctrl.flags[fp_exc_dz_c]; // divide by zero
    assign flags_o[fp_exc_of_c] = ctrl.flags[fp_exc_of_c]; // overflow
    assign flags_o[fp_exc_uf_c] = ctrl.flags[fp_exc_uf_c]; // underflow
    assign flags_o[fp_exc_nx_c] = ctrl.flags[fp_exc_nx_c]; // inexact

    // Rounding ----------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : rounding_unit_ctrl
       /* defaults */
       round.en  = 1'b0;
       round.sub = 1'b0;
       /* rounding mode */ 
       unique case (rmode_i[2:0])
        // round to nearest, ties to even
        3'b000 : begin
            if (sreg.ext_g == 1'b0) begin
                round.en = 1'b0; // round down (do nothing)
            end else begin
                if ((sreg.ext_r == 1'b0) && (sreg.ext_s == 1'b0)) begin // tie!
                    round.en = sreg.lower[0]; // round up if LSB of mantissa is set
                end else begin
                    round.en = 1'b1; // round up
                end
            end
            round.sub = 1'b0; // increment
        end
        // round towards zero
        3'b001 : round.en = 1'b0; // no rounding -> just truncate
        // round down (towards -infinity)
        3'b010 : begin
            round.en  = sreg.ext_g | sreg.ext_r | sreg.ext_s;
            round.sub = 1'b1; // decrement
        end
        // round up (towards +infinity)
        3'b011 : begin
            round.en  = sreg.ext_g | sreg.ext_r | sreg.ext_s;
            round.sub = 1'b0; // increment
        end
        // round to nearest, ties to max magnitude
        3'b100 : round.en = 1'b0; // FIXME / TODO
        default: begin // undefined
            round.en = 1'b0;
        end
       endcase
    end : rounding_unit_ctrl
    
    /* incrementer/decrementer */
    logic [24:0] tmp_v;
    always_comb begin : rounding_unit_add
        tmp_v = {1'b0, sreg.upper[0], sreg.lower};
        //
        if (round.en == 1'b1) begin
            if (round.sub == 1'b0) begin // increment
                round.output_data = tmp_v + 1'b1;
            end else begin // decrement
                round.output_data = tmp_v - 1'b1;
            end
        end else begin // do nothing
            round.output_data = tmp_v;
        end
    end
endmodule