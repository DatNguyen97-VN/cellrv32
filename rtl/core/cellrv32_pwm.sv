// ##################################################################################################
// # << CELLRV32 - Pulse Width Modulation Controller (PWM) >>                                       #
// # ********************************************************************************************** #
// # Simple PWM controller with 8 bit resolution for the duty cycle and programmable base           #
// # frequency. The controller supports up to 60 PWM channels.                                      #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_pwm #(
    parameter int NUM_CHANNELS = 0 // number of PWM channels (0..12)
) (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o , // transfer acknowledge
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [07:0] clkgen_i,
    /* pwm output channels */
    output logic [11:0] pwm_o
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(pwm_size_c); // low address boundary bit

    /* Control register bits */
    localparam int ctrl_enable_c    = 0; // r/w: PWM enable
    localparam int ctrl_prsc0_bit_c = 1; // r/w: prescaler select bit 0
    localparam int ctrl_prsc1_bit_c = 2; // r/w: prescaler select bit 1
    localparam int ctrl_prsc2_bit_c = 3; // r/w: prescaler select bit 2

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // write enable
    logic        rden;   // read enable

    /* accessible regs */
    typedef logic [0:11][7:0] pwm_ch_t;
    pwm_ch_t    pwm_ch; // duty cycle (r/w)
    logic       enable; // enable unit (r/w)
    logic [2:0] prsc;   // clock prescaler (r/w)
    
    typedef logic [0:11][7:0] pwm_ch_rd_t;
    pwm_ch_rd_t pwm_ch_rd; // duty cycle read-back

    /* prescaler clock generator */
    logic prsc_tick;

    /* pwm core counter */
    logic [7:0] pwm_cnt;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
         assert (!(NUM_CHANNELS > 12)) else
         $error("CELLRV32 PROCESSOR CONFIG ERROR! <PWM controller> invalid number of channels (0..12)!");
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == pwm_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {pwm_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign rden   = acc_en & rden_i;
    assign wren   = acc_en & wren_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            enable <= 1'b0;
            prsc   <= '0;
            pwm_ch <= '0;
        end else begin
            if (wren == 1'b1) begin
                /* control register */
                if (addr == pwm_ctrl_addr_c) begin
                  enable <= data_i[ctrl_enable_c];
                  prsc   <= data_i[ctrl_prsc2_bit_c : ctrl_prsc0_bit_c];
                end
                /* duty cycle register 0 */
                if (addr == pwm_dc0_addr_c) begin
                  pwm_ch[00] <= data_i[07 : 00];
                  pwm_ch[01] <= data_i[15 : 08];
                  pwm_ch[02] <= data_i[23 : 16];
                  pwm_ch[03] <= data_i[31 : 24];
                end
                /* duty cycle register 1 */
                if (addr == pwm_dc1_addr_c) begin
                  pwm_ch[04] <= data_i[07 : 00];
                  pwm_ch[05] <= data_i[15 : 08];
                  pwm_ch[06] <= data_i[23 : 16];
                  pwm_ch[07] <= data_i[31 : 24];
                end
                /* duty cycle register 2 */
                if (addr == pwm_dc2_addr_c) begin
                  pwm_ch[08] <= data_i[07 : 00];
                  pwm_ch[09] <= data_i[15 : 08];
                  pwm_ch[10] <= data_i[23 : 16];
                  pwm_ch[11] <= data_i[31 : 24];
                end
            end
        end
    end : write_access

    /* PWM clock select */
    assign clkgen_en_o = enable; // enable clock generator
    assign prsc_tick   = clkgen_i[prsc];

    // Read access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus handshake
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            unique case (addr[3:2])
                2'b00 : begin
                        data_o[ctrl_enable_c] <= enable; 
                        data_o[ctrl_prsc2_bit_c : ctrl_prsc0_bit_c] <= prsc;
                end
                2'b01 : data_o <= {pwm_ch_rd[03], pwm_ch_rd[02], pwm_ch_rd[01], pwm_ch_rd[00]};                  
                2'b10 : data_o <= {pwm_ch_rd[07], pwm_ch_rd[06], pwm_ch_rd[05], pwm_ch_rd[04]};                  
                2'b11 : data_o <= {pwm_ch_rd[11], pwm_ch_rd[10], pwm_ch_rd[09], pwm_ch_rd[08]};                  
                default: begin
                    data_o <= '0;
                end
            endcase
        end
    end : read_access

    /* duty cycle read-back */
    always_comb begin : pwm_dc_rd_gen
        pwm_ch_rd = '0;
        // only implement the actually configured number of channel register
        for (int i = 0; i < NUM_CHANNELS; ++i) begin
            pwm_ch_rd[i] <= pwm_ch[i];
        end
    end : pwm_dc_rd_gen

    // PWM Core ----------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : pwm_core
        /* pwm base counter */
        if (enable == 1'b0) begin
            pwm_cnt <= '0;
        end else if (prsc_tick == 1'b1) begin
            pwm_cnt <= pwm_cnt + 1'b1;
        end
        /* channels */
        pwm_o <= '0;
        for (int i = 0; i < NUM_CHANNELS; ++i) begin
            if ((pwm_cnt >= pwm_ch[i]) || (enable == 1'b0)) begin
                pwm_o[i] <= 1'b0;
            end else begin
                pwm_o[i] <= 1'b1;
            end
        end
    end : pwm_core
endmodule 