// ##################################################################################################
// # << CELLRV32 - Two-Wire Interface Controller (TWI) >>                                           #
// # ********************************************************************************************** #
// # Supports START and STOP conditions, 8 bit data + ACK/NACK transfers and clock stretching.      #
// # Supports ACKs by the controller. 8 clock pre-scalers + 4-bit clock divider for bus clock       #
// # configuration. No multi-controller support and no peripheral mode support yet.                 #
// # Interrupt: "transmission done"                                                                 #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_twi (
    /* host access */
    input  logic        clk_i ,  // global clock line
    input  logic        rstn_i,  // global reset line, low-active, async
    input  logic [31:0] addr_i,  // address
    input  logic        rden_i,  // read enable
    input  logic        wren_i,  // write enable
    input  logic [31:0] data_i,  // data in
    output logic [31:0] data_o,  // data out
    output logic        ack_o ,  // transfer acknowledge
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [7:0]  clkgen_i,
    /* com lines (require external tri-state drivers) */
    input  logic        twi_sda_i, // serial data line input
    output logic        twi_sda_o, // serial data line output
    input  logic        twi_scl_i, // serial clock line input
    output logic        twi_scl_o, // serial clock line output
    /* interrupt */
    output logic        irq_o      // transfer done IRQ
);
    /* IO space: module base address */
    localparam int hi_abb_c = $clog2(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = $clog2(twi_size_c); // low address boundary bit

    /* control register */
    localparam int ctrl_en_c     =  0; // r/w: TWI enable
    localparam int ctrl_start_c  =  1; // -/w: Generate START condition
    localparam int ctrl_stop_c   =  2; // -/w: Generate STOP condition
    localparam int ctrl_mack_c   =  3; // r/w: generate ACK by controller for transmission
    localparam int ctrl_csen_c   =  4; // r/w: allow clock stretching when set
    localparam int ctrl_prsc0_c  =  5; // r/w: CLK prsc bit 0
    localparam int ctrl_prsc1_c  =  6; // r/w: CLK prsc bit 1
    localparam int ctrl_prsc2_c  =  7; // r/w: CLK prsc bit 2
    localparam int ctrl_cdiv0_c  =  8; // r/w: clock divider bit 0
    localparam int ctrl_cdiv1_c  =  9; // r/w: clock divider bit 1
    localparam int ctrl_cdiv2_c  = 10; // r/w: clock divider bit 2
    localparam int ctrl_cdiv3_c  = 11; // r/w: clock divider bit 3
    //
    localparam int ctrl_claimed_c = 29; // r/-: Set if bus is still claimed
    localparam int ctrl_ack_c     = 30; // r/-: Set if ACK received
    localparam int ctrl_busy_c    = 31; // r/-: Set if TWI unit is busy

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* control register */
    typedef struct {
        logic       enable;
        logic       mack;
        logic       csen;
        logic [2:0] prsc;
        logic [3:0] cdiv;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* clock generator */
    typedef struct {
        logic [3:0] cnt; // clock divider
        logic       tick; // actual TWI "clock"
        logic [3:0] phase_gen; // clock phase generator
        logic [3:0] phase_gen_ff;
        logic [3:0] phase;
        logic       halt; // active clock stretching
    } clk_gen_t;
    //
    clk_gen_t clk_gen;

    /* arbiter */
    typedef struct {
        logic [2:0] state;
        logic [1:0] state_nxt;
        logic [3:0] bitcnt;
        logic [8:0] rtx_sreg; // main rx/tx shift reg
        logic       rtx_done; // transmission done
        logic       busy;
        logic       claimed ; // bus is currently claimed by _this_ controller
    } arbiter_t;
    //
    arbiter_t arbiter;

    /* tri-state I/O control */
    typedef struct {
        logic [1:0] sda_in_ff; // SDA input sync
        logic [1:0] scl_in_ff; // SCL input sync
        logic       sda_in;
        logic       scl_in;
        logic       sda_out;
        logic       scl_out;
    } io_con_t;
    //
    io_con_t io_con;

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == twi_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {twi_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : write_access
        if (rstn_i == 1'b0) begin
            ctrl.enable <= 1'b0;
            ctrl.mack   <= 1'b0;
            ctrl.csen   <= 1'b0;
            ctrl.prsc   <= '0;
            ctrl.cdiv   <= '0;
        end else begin
            if (wren == 1'b1) begin
                if (addr == twi_ctrl_addr_c) begin
                    ctrl.enable <= data_i[ctrl_en_c];
                    ctrl.mack   <= data_i[ctrl_mack_c];
                    ctrl.csen   <= data_i[ctrl_csen_c];
                    ctrl.prsc   <= data_i[ctrl_prsc2_c : ctrl_prsc0_c];
                    ctrl.cdiv   <= data_i[ctrl_cdiv3_c : ctrl_cdiv0_c];
                end
            end
        end
    end : write_access

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus handshake
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            if (addr == twi_ctrl_addr_c) begin
                data_o[ctrl_en_c]                   <= ctrl.enable;
                data_o[ctrl_mack_c]                 <= ctrl.mack;
                data_o[ctrl_csen_c]                 <= ctrl.csen;
                data_o[ctrl_prsc2_c : ctrl_prsc0_c] <= ctrl.prsc;
                data_o[ctrl_cdiv3_c : ctrl_cdiv0_c] <= ctrl.cdiv;
                //
                data_o[ctrl_claimed_c] <= arbiter.claimed;
                data_o[ctrl_ack_c]     <= ~ arbiter.rtx_sreg[0];
                data_o[ctrl_busy_c]    <= arbiter.busy;
            end else begin // twi_rtx_addr_c =>
                data_o[7:0] <= arbiter.rtx_sreg[8:1];
            end
        end
    end : read_access

    // Clock Generation --------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : clock_generator
        if (ctrl.enable == 1'b0) begin // reset/disabled
            clk_gen.tick <= 1'b0;
            clk_gen.cnt  <= '0;
        end else begin
            clk_gen.tick <= 1'b0; // default
            if (clkgen_i[ctrl.prsc] == 1'b1) begin // pre-scaled clock
               if (clk_gen.cnt == ctrl.cdiv) begin // clock divider for fine-tuning
                 clk_gen.tick <= 1'b1;
                 clk_gen.cnt  <= '0;
               end else
                 clk_gen.cnt <= clk_gen.cnt + 1'b1;
            end
        end
    end : clock_generator

    /* clock generator enable */
    assign clkgen_en_o = ctrl.enable;

    /* generate four non-overlapping clock phases */
    always_ff @( posedge clk_i ) begin : phase_generator
        clk_gen.phase_gen_ff <= clk_gen.phase_gen;
        // offline or idle
        if ((arbiter.state[2] == 1'b0) || (arbiter.state[1:0] == 2'b00)) begin
            clk_gen.phase_gen <= 4'b0001; // make sure to start with a new phase, bit stepping: 0-1-2-3
        end else begin
            // clock tick and no clock stretching detected
            if ((clk_gen.tick == 1'b1) && (clk_gen.halt == 1'b0)) begin
                clk_gen.phase_gen <= {clk_gen.phase_gen[2:0], clk_gen.phase_gen[3]}; // rotate left
            end
        end
    end : phase_generator

    /* TWI bus signals are set/sampled using 4 clock phases */
    assign clk_gen.phase[0] = clk_gen.phase_gen_ff[0] & (~ clk_gen.phase_gen[0]); // first step
    assign clk_gen.phase[1] = clk_gen.phase_gen_ff[1] & (~ clk_gen.phase_gen[1]);
    assign clk_gen.phase[2] = clk_gen.phase_gen_ff[2] & (~ clk_gen.phase_gen[2]);
    assign clk_gen.phase[3] = clk_gen.phase_gen_ff[3] & (~ clk_gen.phase_gen[3]); // last step

    /* Clock Stretching Detector */
    /* controller wants to pull SCL high, but SCL is pulled low by peripheral */
    assign clk_gen.halt = ((io_con.scl_out == 1'b1) && (io_con.scl_in_ff[1] == 1'b0) && (ctrl.csen == 1'b1)) ? 1'b1 : 1'b0;

    // TWI Transceiver ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : twi_engine
        /* input synchronizer */
        io_con.sda_in_ff <= {io_con.sda_in_ff[0], io_con.sda_in};
        io_con.scl_in_ff <= {io_con.scl_in_ff[0], io_con.scl_in};

        /* interrupt */
        if ((arbiter.state == 3'b111) && (arbiter.rtx_done == 1'b1)) // transmission done
          irq_o <= 1'b1;
        else
          irq_o <= 1'b0;

        /* serial engine */
        arbiter.state[2] <= ctrl.enable; // module enabled?
        unique case (arbiter.state)
            // --------------------------------------------------------------
            // IDLE: waiting for operation requests
            3'b100 : begin
                arbiter.bitcnt <= '0;
                if (wren == 1'b1) begin
                    if (addr == twi_ctrl_addr_c) begin
                        if (data_i[ctrl_start_c] == 1'b1) // issue START condition
                          arbiter.state_nxt <= 2'b01;
                        else if (data_i[ctrl_stop_c] == 1'b1)  // issue STOP condition
                          arbiter.state_nxt <= 2'b10;
                    end else if (addr == twi_rtx_addr_c) begin // start a data transmission
                        // one bit extra for ACK: issued by controller if ctrl_mack_c is set,
                        // sampled from peripheral if ctrl_mack_c is cleared
                        arbiter.rtx_sreg  <= {data_i[7:0], (~ ctrl.mack)};
                        arbiter.state_nxt <= 2'b11;
                    end
                end

                /* start operation on next TWI clock pulse */
                if ((arbiter.state_nxt != 2'b00) && (clk_gen.tick == 1'b1)) begin
                  arbiter.state[1:0] <= arbiter.state_nxt;
                end
            end
            // --------------------------------------------------------------
            // START: generate (repeated) START condition
            3'b101 : begin
                arbiter.state_nxt <= 2'b00; // no operation pending anymore
                if (clk_gen.phase[0] == 1'b1)
                  io_con.sda_out <= 1'b1;
                else if (clk_gen.phase[1] == 1'b1)
                  io_con.sda_out <= 1'b0;
                //
                if (clk_gen.phase[0] == 1'b1)
                  io_con.scl_out <= 1'b1;
                else if (clk_gen.phase[3] == 1'b1) begin
                  io_con.scl_out <= 1'b0;
                  arbiter.state[1:0] <= 2'b00; // go back to IDLE
                end
            end
            // --------------------------------------------------------------
            // STOP: generate STOP condition
            3'b110 : begin
                arbiter.state_nxt <= 2'b00; // no operation pending anymore
                if (clk_gen.phase[0] == 1'b1)
                  io_con.sda_out <= 1'b0;
                else if (clk_gen.phase[3] == 1'b1) begin
                  io_con.sda_out <= 1'b1;
                  arbiter.state[1:0] <= 2'b00; // go back to IDLE
                end
                //
                if (clk_gen.phase[0] == 1'b1)
                  io_con.scl_out <= 1'b0;
                else if (clk_gen.phase[1] == 1'b1)
                  io_con.scl_out <= 1'b1;
            end
            // --------------------------------------------------------------
            // TRANSMISSION: send/receive byte + ACK/NACK/MACK
            3'b111 : begin
                arbiter.state_nxt <= 2'b00; // no operation pending anymore
                /* SCL clocking */
                if ((clk_gen.phase[0] == 1'b1) || (clk_gen.phase[3] == 1'b1))
                  io_con.scl_out <= 1'b0; // set SCL low after transmission to keep bus claimed
                else if (clk_gen.phase[1] == 1'b1) // first half + second half of valid data strobe
                  io_con.scl_out <= 1'b1;
                /* SDA output */
                if (arbiter.rtx_done == 1'b1)
                  io_con.sda_out <= 1'b0; // set SDA low after transmission to keep bus claimed
                else if (clk_gen.phase[0] == 1'b1)
                  io_con.sda_out <= arbiter.rtx_sreg[8]; // MSB first
                /* SDA input */
                if (clk_gen.phase[2] == 1'b1)
                  arbiter.rtx_sreg <= {arbiter.rtx_sreg[7:0], io_con.sda_in_ff[1]}; // sample SDA input and shift left
                /* bit counter */
                if (clk_gen.phase[3] == 1'b1) begin
                  arbiter.bitcnt <= arbiter.bitcnt + 1'b1;
                end
                /* transmission done */
                if (arbiter.rtx_done == 1'b1) begin
                  arbiter.state[1:0] <= 2'b00; // go back to IDLE
                end
            end
            // --------------------------------------------------------------
            // "0--" OFFLINE: TWI deactivated, bus unclaimed
            default: begin
                io_con.scl_out     <= 1'b1;  // SCL driven by pull-up resistor
                io_con.sda_out     <= 1'b1;  // SDA driven by pull-up resistor
                arbiter.rtx_sreg   <= '0;   // make DATA and ACK _defined_ after reset
                arbiter.state_nxt  <= 2'b00; // no operation pending anymore
                arbiter.state[1:0] <= 2'b00; // stay here, go to IDLE when activated
            end
        endcase
    end : twi_engine

    /* transmit 8 data bits + 1 ACK bit and wait for another clock phase */
    assign arbiter.rtx_done = ((arbiter.bitcnt == 4'b1001) && (clk_gen.phase[0] == 1'b1)) ? 1'b1 : 1'b0;

    /* arbiter busy? */
    assign arbiter.busy = arbiter.state[1] | arbiter.state[0] |       // operation in progress
                          arbiter.state_nxt[1] | arbiter.state_nxt[0]; // pending operation

    /* check if the TWI bus is currently claimed (by this module or any other controller) */
    assign arbiter.claimed = ((arbiter.busy == 1'b1) || ((io_con.sda_in_ff[1] == 1'b0) && (io_con.scl_in_ff[1] == 1'b0))) ? 1'b1 : 1'b0;

    // Tri-State Driver Interface ----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign twi_sda_o     = io_con.sda_out; // NOTE: signal lines can only be actively driven low
    assign twi_scl_o     = io_con.scl_out;
    assign io_con.sda_in = twi_sda_i; // "to_bit" to avoid hardware-vs-simulation mismatch
    assign io_con.scl_in = twi_scl_i; // "to_bit" to avoid hardware-vs-simulation mismatch

endmodule