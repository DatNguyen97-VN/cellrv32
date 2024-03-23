// ##################################################################################################
// # << CELLRV32 - 1-Wire Interface Host Controller (ONEWIRE) >>                                    #
// # ********************************************************************************************** #
// # Single-wire bus controller, compatible to the "Dallas 1-Wire Bus System".                      #
// # Provides three basic operations:                                                               #
// # * generate reset pulse and check for device presence                                           #
// # * transfer single bit (read-while-write)                                                       #
// # * transfer full byte (read-while-write)                                                        #
// # After completing any of the operations the interrupt signal is triggered.                      #
// # The base time for bus interactions is configured using a 2-bit clock prescaler and a 8-bit     #
// # clock divider. All bus operations are timed using (hardwired) multiples of this base time.     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_onewire (
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
    /* com lines (require external tri-state drivers) */
    input  logic        onewire_i, // 1-wire line state
    output logic        onewire_o, // 1-wire line pull-down
    /* interrupt */
    output logic        irq_o      // transfer done IRQ
);
    /* timing configuration (absolute time in multiples of the base tick time t_base) */
    localparam logic[6:0] t_write_one_c       = 1;  // t0
    localparam logic[6:0] t_read_sample_c     = 2;  // t1
    localparam logic[6:0] t_slot_end_c        = 7;  // t2
    localparam logic[6:0] t_pause_end_c       = 9;  // t3
    localparam logic[6:0] t_reset_end_c       = 48; // t4
    localparam logic[6:0] t_presence_sample_c = 55; // t5
    localparam logic[6:0] t_presence_end_c    = 96; // t6
    /* -> see data sheet for more information about the t* timing values */

    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(twi_size_c); // low address boundary bit

    /* control register */
    localparam int ctrl_en_c        =  0; // r/w: TWI enable
    localparam int ctrl_prsc0_c     =  1; // r/w: prescaler select bit 0
    localparam int ctrl_prsc1_c     =  2; // r/w: prescaler select bit 1
    localparam int ctrl_clkdiv0_c   =  3; // r/w: clock divider bit 0
    localparam int ctrl_clkdiv1_c   =  4; // r/w: clock divider bit 1
    localparam int ctrl_clkdiv2_c   =  5; // r/w: clock divider bit 2
    localparam int ctrl_clkdiv3_c   =  6; // r/w: clock divider bit 3
    localparam int ctrl_clkdiv4_c   =  7; // r/w: clock divider bit 4
    localparam int ctrl_clkdiv5_c   =  8; // r/w: clock divider bit 5
    localparam int ctrl_clkdiv6_c   =  9; // r/w: clock divider bit 6
    localparam int ctrl_clkdiv7_c   = 10; // r/w: clock divider bit 7
    localparam int ctrl_trig_rst_c  = 11; // -/w: trigger reset pulse, auto-clears
    localparam int ctrl_trig_bit_c  = 12; // -/w: trigger single-bit transmission, auto-clears
    localparam int ctrl_trig_byte_c = 13; // -/w: trigger full-byte transmission, auto-clears
    //
    localparam int ctrl_sense_c    = 29; // r/-: current state of the bus line
    localparam int ctrl_presence_c = 30; // r/-: bus presence detected
    localparam int ctrl_busy_c     = 31; // r/-: set while operation in progress

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* control register */
    typedef struct {
        logic       enable;
        logic [1:0] clk_prsc;
        logic [7:0] clk_div;
        logic       trig_rst;
        logic       trig_bit;
        logic       trig_byte;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* write data */
    logic [7:0] tx_data;

    /* clock generator */
    logic [3:0] clk_sel;
    logic       clk_tick;
    logic [7:0] clk_cnt;

    /* serial engine */
    typedef struct {
        logic [2:0] state;
        logic       busy;
        logic [2:0] bit_cnt;
        logic [6:0] tick_cnt;
        logic       tick;
        logic       tick_ff;
        logic [7:0] sreg;
        logic       done;
        logic [1:0] wire_in;
        logic       wire_lo;
        logic       wire_hi;
        logic       sample;
        logic       presence;
    } serial_t;
    //
    serial_t serial;

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == onewire_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {onewire_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            ctrl.enable    <= 1'b0;
            ctrl.clk_prsc  <= '0;
            ctrl.clk_div   <= '0;
            ctrl.trig_rst  <= 1'b0;
            ctrl.trig_bit  <= 1'b0;
            ctrl.trig_byte <= 1'b0;
            tx_data        <= '0;
        end else begin
            /* write access */
            if (wren == 1'b1) begin
              /* control register */
              if (addr == onewire_ctrl_addr_c) begin
                ctrl.enable   <= data_i[ctrl_en_c];
                ctrl.clk_prsc <= data_i[ctrl_prsc1_c : ctrl_prsc0_c];
                ctrl.clk_div  <= data_i[ctrl_clkdiv7_c : ctrl_clkdiv0_c];
              end
              /* data register */
              if (addr == onewire_data_addr_c) begin
                tx_data <= data_i[7:0];
              end
            end

            /* operation triggers */
            if ((wren == 1'b1) && (addr == onewire_ctrl_addr_c)) begin // set by host
              ctrl.trig_rst  <= data_i[ctrl_trig_rst_c];
              ctrl.trig_bit  <= data_i[ctrl_trig_bit_c];
              ctrl.trig_byte <= data_i[ctrl_trig_byte_c];
            end else if ((ctrl.enable == 1'b0) || (serial.state[1] == 1'b1)) begin // cleared when disabled or when in RTX/RESET state
              ctrl.trig_rst  <= 1'b0;
              ctrl.trig_bit  <= 1'b0;
              ctrl.trig_byte <= 1'b0;
            end
        end
    end : write_access

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus handshake
        data_o <= '0;
        if (rden == 1'b1) begin
          /* control register -*/
          if (addr == onewire_ctrl_addr_c) begin
            data_o[ctrl_en_c]                       <= ctrl.enable;
            data_o[ctrl_prsc1_c : ctrl_prsc0_c]     <= ctrl.clk_prsc;
            data_o[ctrl_clkdiv7_c : ctrl_clkdiv0_c] <= ctrl.clk_div;
            //
            data_o[ctrl_sense_c]                    <= serial.wire_in[1];
            data_o[ctrl_presence_c]                 <= serial.presence;
            data_o[ctrl_busy_c]                     <= serial.busy;
          /* data register -*/
          end else // if (addr = onewire_data_addr_c) then
            data_o[7:0] <= serial.sreg;
        end
    end : read_access

    // Tick Generator ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : tick_generator
        clk_tick    <= clk_sel[ctrl.clk_prsc];
        serial.tick <= 1'b0; // default
        if (ctrl.enable == 1'b0)
          clk_cnt <= '0;
        else if (clk_tick == 1'b1) begin
          if (clk_cnt == ctrl.clk_div) begin
             clk_cnt     <= '0;
             serial.tick <= 1'b1; // signal is high for 1 clk_i cycle every 't_base'
          end else
             clk_cnt <= clk_cnt + 1'b1;
        end
        serial.tick_ff <= serial.tick; // tick delayed by one clock cycle (for precise bus state sampling)
    end : tick_generator

    /* enable SoC clock generator */
    assign clkgen_en_o = ctrl.enable;

    /* only use the lowest 4 clocks of the system clock generator */
    assign clk_sel = clkgen_i[3:0];

    // Serial Engine -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : serial_engine
        /* input synchronizer */
        serial.wire_in <= {serial.wire_in[0], onewire_i}; // "to_bit" to avoid hardware-vs-simulation mismatch

        /* bus control */
        if ((serial.busy == 1'b0) || (serial.wire_hi == 1'b1)) // disabled/idle or active tristate request
           onewire_o <= 1'b1; // release bus (tristate), high (by pull-up resistor) or actively pulled low by device(s)
        else if (serial.wire_lo == 1'b1)
           onewire_o <= 1'b0; // pull bus actively low

        /* defaults */
        serial.done    <= 1'b0;
        serial.wire_lo <= 1'b0;
        serial.wire_hi <= 1'b0;

        /* FSM */
        serial.state[2] <= ctrl.enable; // module enabled? force reset state otherwise
        unique case (serial.state)
            // --------------------------------------------------------------
            // enabled, but IDLE: wait for new request
            3'b100 : begin
                serial.tick_cnt <= '0;
                /* transmission size */
                if (ctrl.trig_bit == 1'b1)
                   serial.bit_cnt <= 3'b000; // single bit
                else
                   serial.bit_cnt <= 3'b111; // full-byte
                /* any operation request? */
                if ((ctrl.trig_rst == 1'b1) || (ctrl.trig_bit == 1'b1) || (ctrl.trig_byte == 1'b1))
                   serial.state[1:0] <= 2'b01; // SYNC
            end
            // --------------------------------------------------------------
            // SYNC: start operation with next base tick
            3'b101 : begin
                serial.sreg <= tx_data;
                if (serial.tick == 1'b1) begin // synchronize
                   serial.wire_lo <= 1'b1; // force bus to low
                   if (ctrl.trig_rst == 1'b1)
                      serial.state[1:0] <= 2'b11; // RESET
                   else
                      serial.state[1:0] <= 2'b10; // RTX
                end
            end
            // --------------------------------------------------------------
            // RTX: read/write 'serial.bit_cnt-1' bits
            3'b110 : begin
                /* go high to write 1 or to read OR time slot completed */
                if (((serial.tick_cnt == t_write_one_c) && (serial.sreg[0] == 1'b1)) || (serial.tick_cnt == t_slot_end_c)) begin
                   serial.wire_hi <= 1'b1; // release bus
                end
                /* sample input (precisely / just once!) */
                if ((serial.tick_cnt == t_read_sample_c) && (serial.tick_ff == 1'b1)) begin
                   serial.sample <= serial.wire_in[1];
                end
                /* inter-slot pause (end of bit) & iteration control */
                if (serial.tick_cnt == t_pause_end_c) begin // bit done
                   serial.tick_cnt <= '0;
                   serial.sreg     <= {serial.sample, serial.sreg[7:1]}; // new bit; LSB first
                   serial.bit_cnt  <= serial.bit_cnt - 1'b1;
                   if (serial.bit_cnt == 3'b000) begin // all done
                     serial.done       <= 1'b1; // operation done
                     serial.state[1:0] <= 2'b00; // go back to IDLE
                   end else // next bit
                     serial.wire_lo <= 1'b1; // force bus to low again
                end else if (serial.tick == 1'b1)
                    serial.tick_cnt <= serial.tick_cnt + 1'b1;
            end
            // --------------------------------------------------------------
            // RESET: generate reset pulse and check for bus presence
            3'b111 : begin
                if (serial.tick == 1'b1) begin
                   serial.tick_cnt <= serial.tick_cnt + 1'b1;
                end
                /* end of reset pulse */
                if (serial.tick_cnt == t_reset_end_c) begin
                   serial.wire_hi <= 1'b1; // release bus
                end
                /* sample device presence (precisely / just once!) */
                if ((serial.tick_cnt == t_presence_sample_c) && (serial.tick_ff == 1'b1)) begin
                   serial.presence <= ~ serial.wire_in[1]; // set if bus is pulled low by any device
                end
                /* end of presence phase */
                if (serial.tick_cnt == t_presence_end_c) begin
                  serial.done       <= 1'b1; // operation done
                  serial.state[1:0] <= 2'b00; // go back to IDLE
                end
            end
            // --------------------------------------------------------------
            // "0--" OFFLINE: deactivated, reset externally-readable signals
            default: begin
                serial.sreg       <= '0;
                serial.presence   <= 1'b0;
                serial.state[1:0] <= 2'b00; // stay here, go to IDLE when module is enabled
            end
        endcase
    end : serial_engine

    /* serial engine busy? */
    assign serial.busy = (serial.state[1:0] == 2'b00) ? 1'b0 : 1'b1;

    /* operation done interrupt */
    assign irq_o = serial.done;
    
endmodule