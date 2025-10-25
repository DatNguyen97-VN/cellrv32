// ###############################################################################################
// # << CELLRV32 - Half-Precision Floating-Point Unit: Half-To-Int Converter >>                  #
// # ******************************************************************************************* #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_fpu16_h2i #(
    parameter XLEN = 32 // data path width
) (
    /* control */
    input  logic        clk_i,      // global clock, rising edge
    input  logic        rstn_i,     // global reset, low-active, async
    input  logic        start_i,    // trigger operation
    input  logic [02:0] rmode_i,    // rounding mode
    input  logic        funct_i,    // 0=signed, 1=unsigned
    /* input */
    input  logic        sign_i,     // sign
    input  logic [04:0] exponent_i, // exponent
    input  logic [09:0] mantissa_i, // mantissa
    input  logic [09:0] class_i,    // operand class
    /* output */
    output logic [31:0] result_o,   // int result
    output logic [04:0] flags_o,    // exception flags
    output logic        done_o      // operation done
);
    
    /* controller */
    typedef enum logic[2:0] { S_IDLE, 
                              S_PREPARE_H2I, 
                              S_NORMALIZE_BUSY, 
                              S_ROUND, 
                              S_FINALIZE } ctrl_engine_state_t;
    
    typedef struct {
        ctrl_engine_state_t state; // current state
        logic unsign;
        logic [04:0] cnt; // interation counter/exponent
        logic sign;
        logic [09:0] class_data;
        logic rounded; // output is rounded
        logic over;    // output is overflowing
        logic under;   // output in underflowing
        logic [31:0] result_tmp;
        logic [31:0] result;    
    } ctrl_t;
    ctrl_t ctrl;

    /* conversion shift register */
    typedef struct {
        logic [31:0] int_data; // including hidden-zero
        logic [09:0] mant;
        logic ext_g; // guard bit
        logic ext_r; // round bit
        logic ext_s; // sticky bit
    } sreg_t;
    sreg_t sreg;

    /* rounding unit */
    typedef struct {
        logic en;  // enable rounding
        logic sub; // 0=decrement, 1=increment
        logic [32:0] output_data; // result + overflow
    } round_t;
    round_t round;

    // Control Engine ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : ctrl_engine
        if (!rstn_i) begin
            ctrl.state       <= S_IDLE;
            ctrl.cnt         <= '0;
            ctrl.sign        <= 1'b0;
            ctrl.class_data  <= '0;
            ctrl.rounded     <= 1'b0;
            ctrl.over        <= 1'b0;
            ctrl.under       <= 1'b0;
            ctrl.unsign      <= 1'b0;
            ctrl.result      <= '0;
            ctrl.result_tmp  <= '0;
            sreg.int_data    <= '0;
            sreg.mant        <= '0;
            sreg.ext_s       <= 1'b0;
            done_o           <= 1'b0;
        end else begin
            /* default */
            done_o <= 1'b0;

            /* FSM */
            unique case (ctrl.state)
                // --------------------------------------------------------------
                S_IDLE : begin // wait for operation trigger
                    ctrl.rounded <= 1'b0; // not rounded yet
                    ctrl.over    <= 1'b0; // not overflowing yet
                    ctrl.under   <= 1'b0; // not underflowing yet
                    ctrl.unsign  <= funct_i;
                    sreg.ext_s   <= 1'b0; // init
                    if (start_i) begin
                        ctrl.cnt         <= exponent_i;
                        ctrl.sign        <= sign_i;
                        ctrl.class_data  <= class_i;
                        sreg.mant        <= mantissa_i;
                        ctrl.state       <= S_PREPARE_H2I;
                    end
                end
                // --------------------------------------------------------------
                S_PREPARE_H2I : begin // prepare half-to-int conversion
                    if (ctrl.cnt < 14) begin // less than 0.5
                        sreg.int_data    <= '0;
                        ctrl.under       <= 1'b1; // this is an underflow!
                        ctrl.cnt         <= '0;
                    end else if (ctrl.cnt == 14) begin // num < 1.0 but num >= 0.5
                        sreg.int_data    <= '0;
                        sreg.mant        <= {1'b1, sreg.mant[$bits(sreg.mant)-1:1]};
                        ctrl.cnt         <= '0;
                    end else begin
                        sreg.int_data    <= '0;
                        sreg.int_data[0] <= 1'b1; // hidden one
                        ctrl.cnt         <= ctrl.cnt - 5'd15; // remove bias to get raw number of left shifts
                    end

                    /* check terminal cases */
                    if (ctrl.class_data[fp_class_neg_inf_c]  || ctrl.class_data[fp_class_pos_inf_c]  ||
                        ctrl.class_data[fp_class_neg_zero_c] || ctrl.class_data[fp_class_pos_zero_c] ||
                        ctrl.class_data[fp_class_snan_c]     || ctrl.class_data[fp_class_qnan_c]) begin
                        ctrl.state <= S_FINALIZE;
                    end else begin
                        ctrl.state <= S_NORMALIZE_BUSY;
                    end
                    // sticky bit is set if any of the bits below the guard and round bit is set
                    sreg.ext_s <= |sreg.mant[$bits(sreg.mant)-3:0];
                end
                // --------------------------------------------------------------
                S_NORMALIZE_BUSY : begin // running normalization cycle
                    //
                    if ((|ctrl.cnt[$bits(ctrl.cnt)-2:0]) == 1'b0) begin
                        // sticky bit is set if any of the bits below the guard and round bit is set
                        sreg.ext_s <= sreg.ext_s | (|sreg.mant[$bits(sreg.mant)-3:0]);
                        //
                        if (!ctrl.unsign) // signed conversion
                            ctrl.over <= ctrl.over | sreg.int_data[$bits(sreg.int_data)-1]; // update overrun flag again to check for numerical overflow into sign bit
                        ctrl.state <= S_ROUND;
                    end else begin // shift left
                        ctrl.cnt      <= ctrl.cnt - 1'b1;
                        sreg.int_data <= {sreg.int_data[$bits(sreg.int_data)-2:0], sreg.mant[$bits(sreg.mant)-1]};
                        sreg.mant     <= {sreg.mant[$bits(sreg.mant)-2:0], 1'b0};
                        ctrl.over     <= ctrl.over | sreg.int_data[$bits(sreg.int_data)-1];
                    end
                end
                // --------------------------------------------------------------
                S_ROUND : begin // rounding cycle
                    ctrl.rounded    <= ctrl.rounded | round.en;
                    ctrl.over       <= ctrl.over | round.output_data[$bits(round.output_data)-1]; // overflow after rounding
                    ctrl.result_tmp <= round.output_data[$bits(round.output_data)-2:0];
                    ctrl.state      <= S_FINALIZE;
                end
                // --------------------------------------------------------------
                S_FINALIZE : begin // check for corner cases and finalize result
                    if (ctrl.unsign) begin // unsigned conversion
                        if (ctrl.class_data[fp_class_snan_c] || ctrl.class_data[fp_class_qnan_c] || // NaN
                            ctrl.class_data[fp_class_pos_inf_c] ||                                  // +inf
                            (!ctrl.sign && ctrl.over))                                              // positive out-of-range
                          ctrl.result <= 32'hffffffff;
                        else if (ctrl.class_data[fp_class_neg_zero_c] ||
                                 ctrl.class_data[fp_class_pos_zero_c] ||
                                 ctrl.class_data[fp_class_neg_inf_c]  || // subnormal zero or -inf
                                 ctrl.sign || ctrl.under)                // negative out-of-range or underflow
                          ctrl.result <= 32'h00000000;
                        else
                          ctrl.result <= ctrl.result_tmp;
                    end else begin // signed conversion
                        if (ctrl.class_data[fp_class_snan_c]    ||
                            ctrl.class_data[fp_class_qnan_c]    ||
                            ctrl.class_data[fp_class_pos_inf_c] || // NaN or +inf
                            (!ctrl.sign && ctrl.over))             // positive out-of-range
                          ctrl.result <= 32'h7fffffff;
                        else if (ctrl.class_data[fp_class_neg_zero_c] ||
                                 ctrl.class_data[fp_class_pos_zero_c] || // subnormal zero or -inf
                                 ctrl.under)                             // negative out-of-range or underflow
                          ctrl.result <= 32'h00000000;
                        else if (ctrl.class_data[fp_class_neg_inf_c] ||
                                 (ctrl.sign && ctrl.over)) // -inf or negative out-of-range
                          ctrl.result <= 32'h80000000;
                        else begin // result is ok, make sign adaption
                            if (ctrl.sign)
                                ctrl.result <= (0 - ctrl.result_tmp); // (0 - ctrl.result_tmp); is abs()
                            else
                                ctrl.result <= ctrl.result_tmp;
                        end
                    end
                    done_o     <= 1'b1;
                    ctrl.state <= S_IDLE;
                end
                // --------------------------------------------------------------
                default: begin // undefined
                    ctrl.state <= S_IDLE;
                end
            endcase
        end
    end : ctrl_engine

    /* result */
    assign result_o = ctrl.result;

    /* exception flags */
    assign flags_o[fp_exc_nv_c] = ctrl.class_data[fp_class_snan_c] | ctrl.class_data[fp_class_qnan_c]; // invalid operation
    assign flags_o[fp_exc_dz_c] = 1'b0; // divide by zero - not possible here
    assign flags_o[fp_exc_of_c] = ctrl.over | ctrl.class_data[fp_class_pos_inf_c] | ctrl.class_data[fp_class_neg_inf_c]; // overflow
    assign flags_o[fp_exc_uf_c] = ctrl.under; // underflow
    assign flags_o[fp_exc_nx_c] = ctrl.rounded; // inexact if result was rounded

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
                      round.en <= sreg.int_data[0]; // round up if LSB of int is set
                   
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

    // guard bit
    assign sreg.ext_g = sreg.mant[$bits(sreg.mant)-1];
    // round bit
    assign sreg.ext_r = sreg.mant[$bits(sreg.mant)-2];

    /* incrementer */
    logic [32:0] tmp_v; // including overflow
    always_comb begin : rounding_unit_add
        tmp_v = {1'b0, sreg.int_data};
        if (round.en)
            // increment
            round.output_data = tmp_v + 1;
        else // do nothing
            round.output_data = tmp_v;
    end : rounding_unit_add

endmodule