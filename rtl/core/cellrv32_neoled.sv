// ##################################################################################################
// # << CELLRV32 - Smart LED (WS2811/WS2812) Interface (NEOLED) >>                                  #
// # ********************************************************************************************** #
// # Hardware interface for direct control of "smart LEDs" using an asynchronous serial data        #
// # line. Compatible with the WS2811 and WS2812 LEDs.                                              #
// #                                                                                                #
// # NeoPixel-compatible, RGB (24-bit) and RGBW (32-bit) modes supported (in "parallel")            #
// # (TM) "NeoPixel" is a trademark of Adafruit Industries.                                         #
// #                                                                                                #
// # The interface uses a programmable carrier frequency (800 KHz for the WS2812 LEDs)              #
// # configurable via the control register's clock prescaler bits (ctrl_clksel*_c) and the period   #
// # length configuration bits (ctrl_t_tot_*_c). "high-times" for sending a ZERO or a ONE bit are   #
// # configured using the ctrl_t_0h_*_c and ctrl_t_1h_*_c bits, respectively. 32-bit transfers      #
// # (for RGBW modules) and 24-bit transfers (for RGB modules) are supported via ctrl_mode__c.      #
// #                                                                                                #
// # The device features a TX buffer (FIFO) with <FIFO_DEPTH> entries with configurable interrupt.  #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_neoled #(
    parameter int FIFO_DEPTH = 1 // NEOLED FIFO depth, has to be a power of two, min 1
) (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [07:0] clkgen_i,
    /* interrupt */
    output logic        irq_o,  // interrupt request
    /* NEOLED output */
    output logic        neoled_o // serial async data line
);
    /* IO space: module base address */
    localparam int hi_abb_c = $clog2(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = $clog2(neoled_size_c); // low address boundary bit

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* Control register bits */
    localparam int ctrl_en_c       =  0; // r/w: module enable
    localparam int ctrl_mode_c     =  1; // r/w: 0 = 24-bit RGB mode, 1 = 32-bit RGBW mode
    localparam int ctrl_strobe_c   =  2; // r/w: 0 = send normal data, 1 = send LED strobe command (RESET) on data write
    //
    localparam int ctrl_clksel0_c  =  3; // r/w: prescaler select bit 0
    localparam int ctrl_clksel1_c  =  4; // r/w: prescaler select bit 1
    localparam int ctrl_clksel2_c  =  5; // r/w: prescaler select bit 2
    //
    localparam int ctrl_bufs_0_c   =  6; // r/-: log2(FIFO_DEPTH) bit 0
    localparam int ctrl_bufs_1_c   =  7; // r/-: log2(FIFO_DEPTH) bit 1
    localparam int ctrl_bufs_2_c   =  8; // r/-: log2(FIFO_DEPTH) bit 2
    localparam int ctrl_bufs_3_c   =  9; // r/-: log2(FIFO_DEPTH) bit 3
    //
    localparam int ctrl_t_tot_0_c  = 10; // r/w: pulse-clock ticks per total period bit 0
    localparam int ctrl_t_tot_1_c  = 11; // r/w: pulse-clock ticks per total period bit 1
    localparam int ctrl_t_tot_2_c  = 12; // r/w: pulse-clock ticks per total period bit 2
    localparam int ctrl_t_tot_3_c  = 13; // r/w: pulse-clock ticks per total period bit 3
    localparam int ctrl_t_tot_4_c  = 14; // r/w: pulse-clock ticks per total period bit 4
    //
    localparam int ctrl_t_0h_0_c   = 15; // r/w: pulse-clock ticks per ZERO high-time bit 0
    localparam int ctrl_t_0h_1_c   = 16; // r/w: pulse-clock ticks per ZERO high-time bit 1
    localparam int ctrl_t_0h_2_c   = 17; // r/w: pulse-clock ticks per ZERO high-time bit 2
    localparam int ctrl_t_0h_3_c   = 18; // r/w: pulse-clock ticks per ZERO high-time bit 3
    localparam int ctrl_t_0h_4_c   = 19; // r/w: pulse-clock ticks per ZERO high-time bit 4
    //
    localparam int ctrl_t_1h_0_c   = 20; // r/w: pulse-clock ticks per ONE high-time bit 0
    localparam int ctrl_t_1h_1_c   = 21; // r/w: pulse-clock ticks per ONE high-time bit 1
    localparam int ctrl_t_1h_2_c   = 22; // r/w: pulse-clock ticks per ONE high-time bit 2
    localparam int ctrl_t_1h_3_c   = 23; // r/w: pulse-clock ticks per ONE high-time bit 3
    localparam int ctrl_t_1h_4_c   = 24; // r/w: pulse-clock ticks per ONE high-time bit 4
    //
    localparam int ctrl_irq_conf_c = 27; // r/w: interrupt condition: 0=IRQ when buffer less than half full, 1=IRQ when buffer is empty
    localparam int ctrl_tx_empty_c = 28; // r/-: TX FIFO is empty
    localparam int ctrl_tx_half_c  = 29; // r/-: TX FIFO is at least half-full
    localparam int ctrl_tx_full_c  = 30; // r/-: TX FIFO is full
    localparam int ctrl_tx_busy_c  = 31; // r/-: serial TX engine busy when set

    /* control register */
    typedef struct {
        logic       enable;
        logic       mode;
        logic       strobe;
        logic [2:0] clk_prsc;
        logic       irq_conf;
        logic [4:0] t_total;
        logic [4:0] t0_high;
        logic [4:0] t1_high;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* transmission buffer */
    typedef struct {
        logic          we;    // write enable
        logic          re;    // read enable
        logic          clear; // sync reset, high-active
        logic [31+2:0] wdata; // write data (excluding mode)
        logic [31+2:0] rdata; // read data (including mode)
        logic          avail; // data available?
        logic          free;  // free entry available?
        logic          half;  // half full
    } tx_fifo_t;
    //
    tx_fifo_t tx_fifo;

    /* serial transmission engine */
    typedef enum { S_IDLE, S_INIT, S_GETBIT, S_PULSE, S_STROBE } serial_state_t;
    typedef struct {
        /* state control */
        serial_state_t state;
        logic mode;
        logic done;
        logic busy;
        logic [05:0] bit_cnt;
        /* shift register */
        logic [31:0] sreg;
        logic        next_bit; // next bit to send
        /* pulse generator */
        logic pulse_clk; // pulse cycle "clock"
        logic [04:0] pulse_cnt;
        logic [04:0] t_high;
        logic [06:0] strobe_cnt;
        logic        tx_out;
    } serial_t;
    //
    serial_t serial;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert  (!((is_power_of_two_f(FIFO_DEPTH) == 1'b0) || (FIFO_DEPTH < 1) || (FIFO_DEPTH > 32768)))
        else $error("CELLRV32 PROCESSOR CONFIG ERROR! Invalid NEOLED FIFO size configuration (1..32k).");
    end

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == neoled_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {neoled_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    /* write access */
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (rstn_i == 1'b0) begin
            ctrl.enable   <= 1'b0;
            ctrl.mode     <= 1'b0;
            ctrl.strobe   <= 1'b0;
            ctrl.clk_prsc <= '0;
            ctrl.irq_conf <= 1'b0;
            ctrl.t_total  <= '0;
            ctrl.t0_high  <= '0;
            ctrl.t1_high  <= '0;
        end else begin
            if ((wren == 1'b1) && (addr == neoled_ctrl_addr_c)) begin
                ctrl.enable   <= data_i[ctrl_en_c];
                ctrl.mode     <= data_i[ctrl_mode_c];
                ctrl.strobe   <= data_i[ctrl_strobe_c];
                ctrl.clk_prsc <= data_i[ctrl_clksel2_c : ctrl_clksel0_c];
                ctrl.irq_conf <= data_i[ctrl_irq_conf_c];
                ctrl.t_total  <= data_i[ctrl_t_tot_4_c : ctrl_t_tot_0_c];
                ctrl.t0_high  <= data_i[ctrl_t_0h_4_c  : ctrl_t_0h_0_c];
                ctrl.t1_high  <= data_i[ctrl_t_1h_4_c  : ctrl_t_1h_0_c];
            end
        end
    end

    /* read access */
    always_ff @(posedge clk_i) begin
        ack_o  <= wren | rden; // access acknowledge
        data_o <= '0;
        // and (addr = neoled_ctrl_addr_c) then
        if (rden == 1'b1) begin
            data_o[ctrl_en_c]                       <= ctrl.enable;
            data_o[ctrl_mode_c]                     <= ctrl.mode;
            data_o[ctrl_strobe_c]                   <= ctrl.strobe;
            data_o[ctrl_clksel2_c : ctrl_clksel0_c] <= ctrl.clk_prsc;
            data_o[ctrl_irq_conf_c]                 <= ctrl.irq_conf | (FIFO_DEPTH == 1); // tie to one if FIFO_DEPTH is 1
            data_o[ctrl_bufs_3_c  : ctrl_bufs_0_c]  <= 4'($clog2(FIFO_DEPTH));
            data_o[ctrl_t_tot_4_c : ctrl_t_tot_0_c] <= ctrl.t_total;
            data_o[ctrl_t_0h_4_c  : ctrl_t_0h_0_c]  <= ctrl.t0_high;
            data_o[ctrl_t_1h_4_c  : ctrl_t_1h_0_c]  <= ctrl.t1_high;
            //
            data_o[ctrl_tx_empty_c]                 <= ~tx_fifo.avail;
            data_o[ctrl_tx_half_c]                  <= tx_fifo.half;
            data_o[ctrl_tx_full_c]                  <= ~tx_fifo.free;
            data_o[ctrl_tx_busy_c]                  <= serial.busy;
        end
    end

    /* enable external clock generator */
    assign clkgen_en_o = ctrl.enable;

    // TX Buffer (FIFO) --------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(32+2),       // size of data elements in fifo
        .FIFO_RSYNC(1'b1),       // sync read
        .FIFO_SAFE (1'b1),       // safe access
        .FIFO_GATE (1'b0)        // no output gate required
    ) data_buffer (
        /* control */
        .clk_i(clk_i),           // clock, rising edge
        .rstn_i(rstn_i),         // async reset, low-active
        .clear_i(tx_fifo.clear), // sync reset, high-active
        .half_o(tx_fifo.half),   // FIFO is at least half full
        /* write port */
        .wdata_i(tx_fifo.wdata), // write data
        .we_i(tx_fifo.we),       // write enable
        .free_o(tx_fifo.free),   // at least one entry is free when set
        /* read port */
        .re_i(tx_fifo.re),       // read enable
        .rdata_o(tx_fifo.rdata), // read data
        .avail_o(tx_fifo.avail)  // data available when set
    );

    assign tx_fifo.re    = (serial.state == S_IDLE) ? 1'b1 : 1'b0;
    assign tx_fifo.we    = ((wren == 1'b1) && (addr == neoled_data_addr_c)) ? 1'b1 : 1'b0;
    assign tx_fifo.wdata = {ctrl.strobe, ctrl.mode, data_i};
    assign tx_fifo.clear = ~ctrl.enable;

    /* IRQ generator */
    always_ff @(posedge clk_i) begin
        irq_o <= ctrl.enable & (
                 ((~ ctrl.irq_conf) & (~ tx_fifo.avail)) | // fire IRQ if FIFO is empty
                 ((  ctrl.irq_conf) & (~ tx_fifo.half))    // fire IRQ if FIFO is less than half full
        );
    end

    // Serial TX Engine --------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : serial_engine
        /* clock generator */
        serial.pulse_clk <= clkgen_i[ctrl.clk_prsc];

        /* defaults */
        serial.done <= 1'b0;

        /* FSM */
        if (ctrl.enable == 1'b0) begin // disabled
            serial.tx_out <= 1'b0;
            serial.state  <= S_IDLE;
        end else begin
            unique case (serial.state)
                // --------------------------------------------------------------
                // waiting for new TX data
                S_IDLE : begin
                    serial.tx_out     <= 1'b0;
                    serial.pulse_cnt  <= '0;
                    serial.strobe_cnt <= '0;
                    if (tx_fifo.avail == 1'b1) begin
                      serial.state <= S_INIT;
                    end
                end
                // --------------------------------------------------------------
                // initialize TX shift engine
                S_INIT : begin
                    if (tx_fifo.rdata[32] == 1'b0) begin // mode = "RGB"
                        serial.mode    <= 1'b0;
                        serial.bit_cnt <= 6'b011000; // total number of bits to send: 3x8=24
                    end else begin // mode = "RGBW"
                        serial.mode    <= 1'b1;
                        serial.bit_cnt <= 6'b100000; // total number of bits to send: 4x8=32
                    end
                    //
                    if (tx_fifo.rdata[33] == 1'b0) begin // send data
                      serial.sreg  <= tx_fifo.rdata[31 : 00];
                      serial.state <= S_GETBIT;
                    end else // send RESET command
                      serial.state <= S_STROBE;
                end
                // --------------------------------------------------------------
                // get next TX bit
                S_GETBIT : begin
                    serial.sreg      <= {serial.sreg[$bits(serial.sreg)-2 : 0], 1'b0}; // shift left by one position (MSB-first)
                    serial.bit_cnt   <= serial.bit_cnt - 1'b1;
                    serial.pulse_cnt <= '0;
                    //
                    if (serial.next_bit == 1'b0) begin // send zero-bit
                        serial.t_high <= ctrl.t0_high;
                    end else begin // send one-bit
                        serial.t_high <= ctrl.t1_high;
                    end
                    //
                    if (serial.bit_cnt == 6'b000000) begin // all done?
                      serial.tx_out <= 1'b0;
                      serial.done   <= 1'b1; // done sending data
                      serial.state  <= S_IDLE;
                    end else begin // send current data MSB
                      serial.tx_out <= 1'b1;
                      serial.state  <= S_PULSE; // transmit single pulse
                    end
                end
                // --------------------------------------------------------------
                // send pulse with specific duty cycle
                S_PULSE : begin
                   // total pulse length = ctrl.t_total
                   // pulse high time    = serial.t_high
                   if (serial.pulse_clk == 1'b1) begin
                       serial.pulse_cnt <= serial.pulse_cnt + 1'b1;
                       /* T_high reached? */
                       if (serial.pulse_cnt == serial.t_high) begin
                           serial.tx_out <= 1'b0;
                       end
                       /* T_total reached? */
                       if (serial.pulse_cnt == ctrl.t_total) begin
                          serial.state <= S_GETBIT; // get next bit to send
                       end
                   end    
                end
                // --------------------------------------------------------------
                // strobe LED data ("RESET" command)
                S_STROBE : begin
                    // wait for 127 * ctrl.t_total to _ensure_ RESET
                    if (serial.pulse_clk == 1'b1) begin
                        /* T_total reached? */
                        if (serial.pulse_cnt == ctrl.t_total) begin
                            serial.pulse_cnt  <= '0;
                            serial.strobe_cnt <= serial.strobe_cnt + 1'b1;
                        end else begin
                            serial.pulse_cnt <= serial.pulse_cnt + 1'b1;
                        end
                    end
                    /* number of LOW periods reached for RESET? */
                    if (&serial.strobe_cnt == 1'b1) begin
                        serial.done  <= 1'b1;
                        serial.state <= S_IDLE;
                    end
                    
                end
                // --------------------------------------------------------------
                default: begin
                    serial.state <= S_IDLE;
                end
            endcase
            /* serial data tx_out */
            neoled_o <= serial.tx_out & ctrl.enable;
        end
    end : serial_engine

    /* SREG's TX data: bit 23 for RGB mode (24-bit), bit 31 for RGBW mode (32-bit) */
    assign serial.next_bit = (serial.mode == 1'b0) ? serial.sreg[23] : serial.sreg[31];

    /* TX engine status */
    assign serial.busy = (serial.state == S_IDLE) ? 1'b0 : 1'b1;
    
endmodule