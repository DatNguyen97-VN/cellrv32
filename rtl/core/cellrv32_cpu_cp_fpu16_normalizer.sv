// ################################################################################################
// # << CELLRV32 - Half-Precision Floating-Point Unit: Normalizer and Rounding Unit >>            #
// # *********************************************************************************************#
// # This unit also performs int-to-half conversions.                                            #
// # ******************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_fpu16_normalizer (
    /* control */
    input logic        clk_i,      // global clock, rising edge
    input logic        rstn_i,     // global reset, low-active, async
    input logic        start_i,    // trigger operation
    input logic [02:0] rmode_i,    // rounding mode
    input logic        funct_i,    // operating mode (0=norm&round, 1=int-to-half)
    /* input */
    input logic        sign_i,     // sign
    input logic [05:0] exponent_i, // extended exponent
    input logic [21:0] mantissa_i, // extended mantissa
    input logic [31:0] integer_i,  // int input
    input logic [09:0] class_i,    // input number class
    input logic [04:0] flags_i,    // exception flags input
    /* output */
    output logic [15:0] result_o,  // half result
    output logic [04:0] flags_o,   // exception flags output
    output logic        done_o     // operation done
);
    
    /* controller */
    typedef enum logic[3:0] { S_IDLE, 
                              S_PREPARE_I2H, 
                              S_CHECK_I2H, 
                              S_PREPARE_NORM, 
                              S_PREPARE_SHIFT, 
                              S_NORMALIZE_BUSY, 
                              S_ROUND, 
                              S_CHECK, 
                              S_FINALIZE } ctrl_engine_state_t;
    
    typedef struct {
        ctrl_engine_state_t state; // current state
        logic norm_r; // normalization round 0 or 1
        logic [05:0] cnt; // interation counter/exponent (incl. overflow)
        logic [05:0] cnt_pre; 
        logic cnt_of;  // counter overflow
        logic cnt_uf;  // counter underflow
        logic rounded; // output is rounded
        logic res_sgn;
        logic [04:0] res_exp;
        logic [09:0] res_man;
        logic [09:0] class_data;
        logic [04:0] flags;
    } ctrl_t;
    ctrl_t ctrl;

    typedef struct {
        logic done;  
        logic dir; // shift direction: 0=right, 1=left
        logic zero;  
        logic [31:0] upper; 
        logic [09:0] lower; 
        logic ext_g; // guard bit
        logic ext_r; // round bit
        logic ext_s; // sticky bit
    } sreg_t;
    sreg_t sreg;

    /* rounding unit */
    typedef struct {
        logic en; // enable rounding
        logic [11:0] output_data; // mantissa size + hidden one + 1
    } round_t;
    round_t round;

    // Control Engine ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : ctrl_engine
        if (!rstn_i) begin
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
            if ((ctrl.cnt_pre[5:4] == 2'b01) && (ctrl.cnt[5:4] == 2'b10)) // overflow
               ctrl.cnt_of <= 1'b1;
            else if ((ctrl.cnt_pre[5:4] == 2'b00) && (ctrl.cnt[5:4] == 2'b11)) // underflow
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
                    if (start_i) begin
                        ctrl.cnt        <= exponent_i;
                        ctrl.res_sgn    <= sign_i;
                        ctrl.class_data <= class_i;
                        ctrl.flags      <= flags_i;
                        // int --> half
                        if (funct_i)
                            ctrl.state <= S_PREPARE_I2H;
                        else // half --> half
                            ctrl.state <= S_PREPARE_NORM;
                    end 
                end
                // --------------------------------------------------------------
                // prepare int-to-half conversion
                S_PREPARE_I2H : begin 
                    sreg.upper <= integer_i;
                    sreg.lower <= '0;
                    sreg.ext_g <= 1'b0;
                    sreg.ext_r <= 1'b0;
                    sreg.ext_s <= 1'b0;
                    sreg.dir   <= 1'b0; // shift right
                    ctrl.state <= S_CHECK_I2H;
                end
                // --------------------------------------------------------------
                // check if converting zero
                S_CHECK_I2H : begin 
                    if (sreg.zero) begin // all zero
                        ctrl.class_data[fp_class_pos_zero_c] <= 1'b1;
                        ctrl.state <= S_FINALIZE;
                    end else begin
                        ctrl.state <= S_NORMALIZE_BUSY;
                    end
                end
                // --------------------------------------------------------------
                // prepare "normal" normalization & rounding
                S_PREPARE_NORM : begin 
                    sreg.upper[31:3] <= '0;
                    // is Fused Multiply-Add/Subtract or Not-Multiply-Add/Subtract  operation?
                    sreg.upper[02:0] <= mantissa_i[21:19];
                    sreg.lower       <= mantissa_i[18:09];
                    //
                    sreg.ext_g       <= mantissa_i[08];
                    sreg.ext_r       <= mantissa_i[07];
                    sreg.ext_s       <= |mantissa_i[06:00]; // sticky bit
                    // check for special cases
                    if (ctrl.class_data[fp_class_snan_c]        || ctrl.class_data[fp_class_qnan_c]       || // NaN
                         ctrl.class_data[fp_class_neg_zero_c]   || ctrl.class_data[fp_class_pos_zero_c]   || // zero
                         ctrl.class_data[fp_class_neg_denorm_c] || ctrl.class_data[fp_class_pos_denorm_c] || // subnormal
                         ctrl.class_data[fp_class_neg_inf_c]    || ctrl.class_data[fp_class_pos_inf_c]    || // infinity
                         ctrl.flags[fp_exc_uf_c] || // underflow
                         ctrl.flags[fp_exc_of_c] || // overflow
                         ctrl.flags[fp_exc_nv_c]) begin // invalid
                        ctrl.state <= S_FINALIZE;
                    end else begin
                        ctrl.state <= S_PREPARE_SHIFT;
                    end
                end
                // --------------------------------------------------------------
                // prepare shift direction (for "normal" normalization only)
                S_PREPARE_SHIFT : begin
                    sreg.dir <= sreg.zero; // if number is less than 1.0 then shift left, else shift right
                    ctrl.state <= S_NORMALIZE_BUSY;
                end
                // --------------------------------------------------------------
                // running normalization cycle
                S_NORMALIZE_BUSY : begin 
                    /* shift until normalized or exception */
                    if (sreg.done || ctrl.cnt_uf || ctrl.cnt_of) begin
                        /* normalization control */
                        ctrl.norm_r <= 1'b1;
                        //
                        if (ctrl.norm_r) begin // second normalization cycle done       
                            ctrl.state <= S_CHECK;
                        end else begin // first normalization cycle done
                            ctrl.state <= S_ROUND;
                        end
                    end else begin
                        if (sreg.dir) begin // shift left
                            ctrl.cnt   <= ctrl.cnt - 1'b1;
                            sreg.upper <= {sreg.upper[$bits(sreg.upper)-2:0], sreg.lower[$bits(sreg.lower)-1]};
                            sreg.lower <= {sreg.lower[$bits(sreg.lower)-2:0], sreg.ext_g};
                            sreg.ext_g <= sreg.ext_r;
                            sreg.ext_r <= sreg.ext_s;
                            sreg.ext_s <= sreg.ext_s; // sticky bit
                        end else begin // shift right
                            ctrl.cnt   <= ctrl.cnt + 1'b1;
                            sreg.upper <= {1'b0, sreg.upper[$bits(sreg.upper)-1:1]};
                            sreg.lower <= {sreg.upper[0], sreg.lower[$bits(sreg.lower)-1:1]};
                            sreg.ext_g <= sreg.lower[0];
                            sreg.ext_r <= sreg.ext_g;
                            sreg.ext_s <= sreg.ext_r | sreg.ext_s; // sticky bit
                        end
                    end
                end
                // --------------------------------------------------------------
                // rounding cycle (after first normalization)
                S_ROUND : begin 
                    ctrl.rounded <= ctrl.rounded | round.en;
                    sreg.upper[31:02] <= '0;
                    sreg.upper[01:00] <= round.output_data[11:10];
                    sreg.lower <= round.output_data[09:0];
                    sreg.ext_g <= 1'b0;
                    sreg.ext_r <= 1'b0;
                    sreg.ext_s <= 1'b0;
                    ctrl.state <= S_PREPARE_SHIFT;
                end
                // --------------------------------------------------------------
                // check for overflow/underflow
                S_CHECK : begin 
                    if (ctrl.cnt_uf) begin // underflow
                        ctrl.flags[fp_exc_uf_c] <= 1'b1;
                    end else if (ctrl.cnt_of) begin // overflow
                        ctrl.flags[fp_exc_of_c] <= 1'b1;
                    end else if (ctrl.cnt[4:0] == 5'h00) begin // subnormal
                        ctrl.flags[fp_exc_uf_c] <= 1'b1;
                    end else if (ctrl.cnt[4:0] == 5'h1f) begin // infinity
                        ctrl.flags[fp_exc_of_c] <= 1'b1;
                    end
                    ctrl.state <= S_FINALIZE;
                end
                // --------------------------------------------------------------
                // result finalization
                S_FINALIZE : begin 
                    /* generate result word (the ORDER of checks is imporatant here!) */
                    // sNaN / qNaN
                    if (ctrl.class_data[fp_class_snan_c] || ctrl.class_data[fp_class_qnan_c] ||
                        ctrl.flags[fp_exc_nv_c]) begin
                        ctrl.res_sgn <= fp16_half_qnan_c[15];
                        ctrl.res_exp <= fp16_half_qnan_c[14:10];
                        ctrl.res_man <= fp16_half_qnan_c[09:00];
                    //
                    end else if (ctrl.class_data[fp_class_neg_inf_c] ||
                                 ctrl.class_data[fp_class_pos_inf_c] || // infinity
                                 ctrl.flags[fp_exc_of_c]) begin         // overflow
                        if (ctrl.class_data[fp_class_neg_inf_c]) begin
                            ctrl.res_sgn <= 1'b1;
                        end else if (ctrl.class_data[fp_class_pos_inf_c]) begin
                            ctrl.res_sgn <= 1'b0;
                        end
                        //
                        ctrl.res_exp <= fp16_half_pos_inf_c[14:10];
                        ctrl.res_man <= fp16_half_pos_inf_c[09:00];
                    //
                    end else if (ctrl.class_data[fp_class_neg_zero_c] || 
                                 ctrl.class_data[fp_class_pos_zero_c]) begin // zero
                        ctrl.res_sgn <= ctrl.class_data[fp_class_neg_zero_c];
                        ctrl.res_exp <= fp16_half_pos_zero_c[14:10];
                        ctrl.res_man <= fp16_half_pos_zero_c[09:00];
                    //    
                    end else if (ctrl.flags[fp_exc_uf_c] || // underflow
                                 sreg.zero               || 
                                 ctrl.class_data[fp_class_neg_denorm_c] || 
                                 ctrl.class_data[fp_class_pos_denorm_c]) begin // denormalized (flush-to-zero)
                        ctrl.res_exp <= fp16_half_pos_zero_c[14:10];
                        ctrl.res_man <= fp16_half_pos_zero_c[09:00];   
                    //      
                    end else begin // result is OK
                        ctrl.res_exp <= ctrl.cnt[4:0];
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
                        sreg.upper[0]) ? 1'b1 : 1'b0; // input is zero, hidden one is set

    // all-zero including hidden bit */
    assign sreg.zero = ((|sreg.upper) == 1'b0) ? 1'b1 : 1'b0;

    /* result */
    assign result_o[15]    = ctrl.res_sgn;
    assign result_o[14:10] = ctrl.res_exp;
    assign result_o[09:00] = ctrl.res_man;

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
        round.en  <= 1'b0;

        /* rounding mode */
        unique case (rmode_i[2:0])
            // round to nearest, ties to even
            3'b000 : begin
                if (sreg.ext_g)
                   if (sreg.ext_r || sreg.ext_s) // tie!
                      round.en <= 1'b1; // round up
                   else
                      round.en <= sreg.lower[0]; // round up if LSB of int is set
                   
            end
            // round towards zero
            3'b001 :
                     round.en <= 1'b0; // no rounding -> just truncate
            3'b010 : begin // round down (towards -infinity)
                     // if the number is negative then round up towards -inf else truncate
                     if (sign_i) begin
                        round.en  <= sreg.ext_g | sreg.ext_r | sreg.ext_s;
                     end
            end
            // round up (towards +infinity)
            3'b011 : begin
                     // if the number is positive then round up towards +inf else truncate
                     if (!sign_i) begin
                        round.en  <= sreg.ext_g | sreg.ext_r | sreg.ext_s;
                     end
            end
            // round to nearest, ties to max magnitude
            3'b100 : round.en <= sreg.ext_g; // if guard bit is 1 then round up else we can just truncate
            default: // undefined
                     round.en <= 1'b0;
        endcase
    end : rounding_unit_ctrl
    
    /* incrementer */
    logic [11:0] tmp_v;
    always_comb begin : rounding_unit_add
        tmp_v = {1'b0, sreg.upper[0], sreg.lower};
        if (round.en) begin
            round.output_data = tmp_v + 1'b1;
        end else begin // do nothing
            round.output_data = tmp_v;
        end
    end
endmodule