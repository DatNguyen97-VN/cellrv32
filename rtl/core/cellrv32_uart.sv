// #################################################################################################Ê
// # << CELLRV32 - Universal Asynchronous Receiver and Transmitter (UART0/1) >>                     #
// # ********************************************************************************************** #
// # Frame configuration: 1 start bit, 8 bit data, parity bit (none/even/odd), 1 stop bit,          #
// # programmable BAUD rate via clock pre-scaler and 12-bit BAUD value configuration register,      #
// # optional configurable RX and TX FIFOs.                                                         #
// #                                                                                                #
// # Interrupts: Configurable RX and TX interrupt (both triggered by specific FIFO fill-levels)     #
// #                                                                                                #
// # Support for RTS("RTR")/CTS hardware flow control:                                              #
// # * uart_rts_o = 0: RX is ready to receive a new char, enabled via CTRL.ctrl_rts_en_c            #
// # * uart_cts_i = 0: TX is allowed to send a new char, enabled via CTRL.ctrl_cts_en_c             #
// #                                                                                                #
// # UART0 / UART1:                                                                                 #
// # This module is used for implementing UART0 and UART1. The UART_PRIMARY generic configures the  #
// # interface register addresses and simulation outputs for UART0 (UART_PRIMARY = true) or UART1   #
// # (UART_PRIMARY = false).                                                                        #
// #                                                                                                #
// # SIMULATION MODE:                                                                               #
// # When the simulation mode is enabled (setting the ctrl.ctrl_sim_en_c bit) any write             #
// # access to the TX register will not trigger any UART activity. Instead, the written data is     #
// # output to the simulation environment. The lowest 8 bits of the written data are printed as     #
// # ASCII char to the simulator console.                                                           #
// # This char is also stored to the file "neorv32.uartX.sim_mode.text.out" (where X = 0 for UART0  #
// # and X = 1 for UART1). The full 32-bit write data is also stored as 8-digit hexadecimal value   #
// # to the file "neorv32.uartX.sim_mode.data.out" (where X = 0 for UART0 and X = 1 for UART1).     #
// # No interrupts are triggered when in SIMULATION MODE.                                           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_uart #(
    parameter logic   UART_PRIMARY = 0, // true = primary UART (UART0), false = secondary UART (UART1)
    parameter int UART_RX_FIFO = 1, // RX fifo depth, has to be a power of two, min 1
    parameter int UART_TX_FIFO = 1 // TX fifo depth, has to be a power of two, min 1
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
    /* com lines */
    output logic        uart_txd_o,
    input  logic        uart_rxd_i,
    /* hardware flow control */
    output logic        uart_rts_o, // UART.RX ready to receive ("RTR"), low-active, optional
    input  logic        uart_cts_i, // UART.TX allowed to transmit, low-active, optional
    /* interrupts */
    output logic        irq_rx_o,   // rx interrupt
    output logic        irq_tx_o    // tx interrupt
);
    /* interface configuration for UART0 / UART1 */
    localparam logic[31:0] uart_id_base_c      = UART_PRIMARY ? uart0_base_c : uart1_base_c;
    localparam int     uart_id_size_c      = UART_PRIMARY ? uart0_size_c : uart1_size_c;
    localparam logic[31:0] uart_id_ctrl_addr_c = UART_PRIMARY ? uart0_ctrl_addr_c : uart1_ctrl_addr_c;
    localparam logic[31:0] uart_id_rtx_addr_c  = UART_PRIMARY ? uart0_rtx_addr_c  : uart1_rtx_addr_c;

    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(uart_id_size_c); // low address boundary bit

    /* control register bits */
    localparam int ctrl_en_c            =  0; // r/w: UART enable
    localparam int ctrl_sim_en_c        =  1; // r/w: simulation-mode enable
    localparam int ctrl_hwfc_en_c       =  2; // r/w: enable RTS/CTS hardware flow-control
    localparam int ctrl_prsc0_c         =  3; // r/w: baud prescaler bit 0
    localparam int ctrl_prsc1_c         =  4; // r/w: baud prescaler bit 1
    localparam int ctrl_prsc2_c         =  5; // r/w: baud prescaler bit 2
    localparam int ctrl_baud0_c         =  6; // r/w: baud divisor bit 0
    localparam int ctrl_baud1_c         =  7; // r/w: baud divisor bit 1
    localparam int ctrl_baud2_c         =  8; // r/w: baud divisor bit 2
    localparam int ctrl_baud3_c         =  9; // r/w: baud divisor bit 3
    localparam int ctrl_baud4_c         = 10; // r/w: baud divisor bit 4
    localparam int ctrl_baud5_c         = 11; // r/w: baud divisor bit 5
    localparam int ctrl_baud6_c         = 12; // r/w: baud divisor bit 6
    localparam int ctrl_baud7_c         = 13; // r/w: baud divisor bit 7
    localparam int ctrl_baud8_c         = 14; // r/w: baud divisor bit 8
    localparam int ctrl_baud9_c         = 15; // r/w: baud divisor bit 9
    //
    localparam int ctrl_rx_nempty_c     = 16; // r/-: RX FIFO not empty
    localparam int ctrl_rx_half_c       = 17; // r/-: RX FIFO at least half-full
    localparam int ctrl_rx_full_c       = 18; // r/-: RX FIFO full
    localparam int ctrl_tx_empty_c      = 19; // r/-: TX FIFO empty
    localparam int ctrl_tx_nhalf_c      = 20; // r/-: TX FIFO not at least half-full
    localparam int ctrl_tx_full_c       = 21; // r/-: TX FIFO full
    localparam int ctrl_irq_rx_nempty_c = 22; // r/w: RX FIFO not empty
    localparam int ctrl_irq_rx_half_c   = 23; // r/w: RX FIFO at least half-full
    localparam int ctrl_irq_rx_full_c   = 24; // r/w: RX FIFO full
    localparam int ctrl_irq_tx_empty_c  = 25; // r/w: TX FIFO empty
    localparam int ctrl_irq_tx_nhalf_c  = 26; // r/w: TX FIFO not at least half-full
    //
    localparam int ctrl_rx_over_c       = 30; // r/-: RX FIFO overflow
    localparam int ctrl_tx_busy_c       = 31; // r/-: UART transmitter is busy and TX FIFO not empty

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable
    logic        rden_ff;

    /* clock generator */
    logic uart_clk;

    /* control register */
    typedef struct {
        logic       enable;
        logic       sim_mode;
        logic       hwfc_en;
        logic [2:0] prsc;
        logic [9:0] baud;
        logic       irq_rx_nempty;
        logic       irq_rx_half;
        logic       irq_rx_full;
        logic       irq_tx_empty;
        logic       irq_tx_nhalf;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* UART transmitter */
    typedef struct {
        logic [2:0] state;
        logic [8:0] sreg;
        logic [3:0] bitcnt;
        logic [9:0] baudcnt;
        logic       done;
        logic       busy;
        logic [1:0] cts_sync;
    } tx_engine_t;
    //
    tx_engine_t tx_engine;

    /* UART receiver */
    typedef struct {
        logic [1:0] state;
        logic [9:0] sreg;
        logic [3:0] bitcnt;
        logic [9:0] baudcnt;
        logic       done;
        logic [2:0] sync;
        logic       over;
    } rx_engine_t;
    //
    rx_engine_t rx_engine;

    /* FIFO interface */
    typedef struct {
        logic       clear; // sync reset, high-active
        logic       we;    // write enable
        logic       re;    // read enable
        logic [7:0] wdata; // write data
        logic [7:0] rdata; // read data
        logic       free;  // free entry available?
        logic       avail; // data available?
        logic       half;  // at least half full
    } fifo_t;
    //
    fifo_t rx_fifo, tx_fifo;
    
    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (is_power_of_two_f(UART_RX_FIFO) != 1'b0) else $error("NEORV32 PROCESSOR CONFIG ERROR: UART %s FIFO depth has to be a power of two.", cond_sel_string_f(UART_PRIMARY, "0", "1"));
        assert (is_power_of_two_f(UART_TX_FIFO) != 1'b0) else $error("NEORV32 PROCESSOR CONFIG ERROR: UART %s FIFO depth has to be a power of two.", cond_sel_string_f(UART_PRIMARY, "0", "1"));
    end

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------

    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == uart_id_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {uart_id_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    /* write access */
    always_ff @(posedge clk_i or negedge rstn_i) begin : write_access
        if (rstn_i == 1'b0) begin
            ctrl.enable        <= 1'b0;
            ctrl.sim_mode      <= 1'b0;
            ctrl.hwfc_en       <= 1'b0;
            ctrl.prsc          <= '0;
            ctrl.baud          <= '0;
            ctrl.irq_rx_nempty <= 1'b0;
            ctrl.irq_rx_half   <= 1'b0;
            ctrl.irq_rx_full   <= 1'b0;
            ctrl.irq_tx_empty  <= 1'b0;
            ctrl.irq_tx_nhalf  <= 1'b0;
        end else begin
            if (wren == 1'b1) begin
                if (addr == uart_id_ctrl_addr_c) begin // control register
                    ctrl.enable        <= data_i[ctrl_en_c];
                    ctrl.sim_mode      <= data_i[ctrl_sim_en_c];
                    ctrl.hwfc_en       <= data_i[ctrl_hwfc_en_c];
                    ctrl.prsc          <= data_i[ctrl_prsc2_c : ctrl_prsc0_c];
                    ctrl.baud          <= data_i[ctrl_baud9_c : ctrl_baud0_c];
                    //
                    ctrl.irq_rx_nempty <= data_i[ctrl_irq_rx_nempty_c];
                    ctrl.irq_rx_half   <= data_i[ctrl_irq_rx_half_c];
                    ctrl.irq_rx_full   <= data_i[ctrl_irq_rx_full_c];
                    ctrl.irq_tx_empty  <= data_i[ctrl_irq_tx_empty_c];
                    ctrl.irq_tx_nhalf  <= data_i[ctrl_irq_tx_nhalf_c];
                end
            end
        end
    end : write_access

    /* read access */
    always_ff @( posedge clk_i ) begin : read_access
        rden_ff <= rden; // delay read access by one cycle due to synchronous FIFO read access
        ack_o   <= wren | rden_ff; // bus access acknowledge
        data_o  <= '0;
        //
        if (rden_ff == 1'b1) begin
            if (addr == uart_id_ctrl_addr_c) begin // control register
                data_o[ctrl_en_c]                   <= ctrl.enable;
                data_o[ctrl_sim_en_c]               <= ctrl.sim_mode;
                data_o[ctrl_hwfc_en_c]              <= ctrl.hwfc_en;
                data_o[ctrl_prsc2_c : ctrl_prsc0_c] <= ctrl.prsc;
                data_o[ctrl_baud9_c : ctrl_baud0_c] <= ctrl.baud;
                //
                data_o[ctrl_rx_nempty_c]            <= rx_fifo.avail;
                data_o[ctrl_rx_half_c]              <= rx_fifo.half;
                data_o[ctrl_rx_full_c]              <= ~ rx_fifo.free;
                data_o[ctrl_tx_empty_c]             <= ~ tx_fifo.avail;
                data_o[ctrl_tx_nhalf_c]             <= ~ tx_fifo.half;
                data_o[ctrl_tx_full_c]              <= ~ tx_fifo.free;
                //
                data_o[ctrl_irq_rx_nempty_c]        <= ctrl.irq_rx_nempty;
                data_o[ctrl_irq_rx_half_c]          <= ctrl.irq_rx_half;
                data_o[ctrl_irq_rx_full_c]          <= ctrl.irq_rx_full;
                data_o[ctrl_irq_tx_empty_c]         <= ctrl.irq_tx_empty;
                data_o[ctrl_irq_tx_nhalf_c]         <= ctrl.irq_tx_nhalf;
                //
                data_o[ctrl_rx_over_c]              <= rx_engine.over;
                data_o[ctrl_tx_busy_c]              <= tx_engine.busy | tx_fifo.avail;
            end else begin // data register
                data_o[7:0] <= rx_fifo.rdata;
            end
        end
    end : read_access

    /* UART clock enable */
    assign clkgen_en_o = ctrl.enable;
    assign uart_clk    = clkgen_i[ctrl.prsc];

    // Data Buffers ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------

    /* TX FIFO */
    neorv32_fifo #(
        .FIFO_DEPTH (UART_TX_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH (8),            // size of data elements in fifo (32-bit only for simulation)
        .FIFO_RSYNC (1'b1),         // sync read
        .FIFO_SAFE  (1'b1),         // safe access
        .FIFO_GATE  (1'b0)          // no output gate required
    ) tx_engine_fifo_inst (
        /* control */
        .clk_i   (clk_i),           // clock, rising edge
        .rstn_i  (rstn_i),          // async reset, low-active
        .clear_i (tx_fifo.clear),   // sync reset, high-active
        .half_o  (tx_fifo.half),    // FIFO at least half-full
        /* write port */
        .wdata_i (tx_fifo.wdata),   // write data
        .we_i    (tx_fifo.we),      // write enable
        .free_o  (tx_fifo.free),    // at least one entry is free when set
        /* read port */
        .re_i    (tx_fifo.re),      // read enable
        .rdata_o (tx_fifo.rdata),   // read data
        .avail_o (tx_fifo.avail)    // data available when set
    );

    assign tx_fifo.clear = ((ctrl.enable == 1'b0) || (ctrl.sim_mode == 1'b1)) ? 1'b1 : 1'b0;
    assign tx_fifo.wdata = data_i[7:0];
    assign tx_fifo.we    = ((wren == 1'b1) && (addr == uart_id_rtx_addr_c)) ? 1'b1 : 1'b0;
    assign tx_fifo.re    = ((tx_engine.state == 3'b100) && (tx_fifo.avail == 1'b1)) ? 1'b1 : 1'b0;

    /* TX interrupt generator */
    always_ff @( posedge clk_i ) begin : tx_interrupt
        irq_tx_o <= ctrl.enable & (
                    (ctrl.irq_tx_empty & (~ tx_fifo.avail)) | // fire IRQ if TX FIFO empty
                    (ctrl.irq_tx_nhalf & (~ tx_fifo.half)));  // fire IRQ if TX FIFO not at least half full
    end : tx_interrupt

    /* RX FIFO */
    neorv32_fifo #(
        .FIFO_DEPTH (UART_RX_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH (8),            // size of data elements in fifo
        .FIFO_RSYNC (1'b1),         // sync read
        .FIFO_SAFE  (1'b1),         // safe access
        .FIFO_GATE  (1'b0)          // no output gate required
    ) rx_engine_fifo_inst (
        /* control */
        .clk_i   (clk_i),         // clock, rising edge
        .rstn_i  (rstn_i),        // async reset, low-active
        .clear_i (rx_fifo.clear), // sync reset, high-active
        .half_o  (rx_fifo.half),  // FIFO at least half-full
        /* write port */
        .wdata_i (rx_fifo.wdata), // write data
        .we_i    (rx_fifo.we),    // write enable
        .free_o  (rx_fifo.free),  // at least one entry is free when set
        /* read port */
        .re_i    (rx_fifo.re),    // read enable
        .rdata_o (rx_fifo.rdata), // read data
        .avail_o (rx_fifo.avail)  // data available when set
    );

    assign rx_fifo.clear = ((ctrl.enable == 1'b0) || (ctrl.sim_mode == 1'b1)) ? 1'b1 : 1'b0;
    assign rx_fifo.wdata = rx_engine.sreg[8:1];
    assign rx_fifo.we    = rx_engine.done;
    assign rx_fifo.re    = ((rden == 1'b1) && (addr == uart_id_rtx_addr_c)) ? 1'b1 : 1'b0;

    /* RX interrupt generator */
    always_ff @( posedge clk_i ) begin : rx_interrupt
        irq_rx_o <= ctrl.enable & (
                    (ctrl.irq_rx_nempty & rx_fifo.avail) |     // fire IRQ if RX FIFO not empty
                    (ctrl.irq_rx_half   & rx_fifo.half)  |     // fire IRQ if RX FIFO at least half full
                    (ctrl.irq_rx_full   & (~ rx_fifo.free)));  // fire IRQ if RX FIFO full
    end : rx_interrupt

    // Transmit Engine ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : trans_engine
        /* synchronize clear-to-send */
        tx_engine.cts_sync <= {tx_engine.cts_sync[0], uart_cts_i};

        /* defaults */
        tx_engine.done <= 1'b0;

        /* FSM */
        tx_engine.state[2] <= ctrl.enable;
        unique case (tx_engine.state)
            // --------------------------------------------------------------
            // IDLE: wait for new data to send
            // --------------------------------------------------------------
            3'b100 : begin
                tx_engine.baudcnt <= ctrl.baud;
                tx_engine.bitcnt  <= 4'b1011; // 1 start-bit + 8 data-bits + 1 stop-bit + 1 pause-bit
                if (tx_fifo.avail == 1'b1) begin
                  tx_engine.state[1:0] <= 2'b01;
                end
            end
            // --------------------------------------------------------------
            // PREPARE: get data from buffer, check if we are allowed to start sending
            // --------------------------------------------------------------
            3'b101 : begin
                tx_engine.sreg <= {tx_fifo.rdata, 1'b0}; // data & start-bit
                if ((tx_engine.cts_sync[1] == 1'b0) || (ctrl.hwfc_en == 1'b0)) begin // allowed to send OR flow-control disabled
                  tx_engine.state[1:0] <= 2'b11;
                end
            end
            // --------------------------------------------------------------
            // SEND: transmit data
            // --------------------------------------------------------------
            3'b111 : begin
                if (uart_clk == 1'b1) begin
                  if ((|tx_engine.baudcnt) == 1'b0) begin // bit done?
                    tx_engine.baudcnt <= ctrl.baud;
                    tx_engine.bitcnt  <= tx_engine.bitcnt - 1'b1;
                    tx_engine.sreg    <= {1'b1, tx_engine.sreg[$bits(tx_engine.sreg)-1 : 1]};
                  end else
                    tx_engine.baudcnt <= tx_engine.baudcnt - 1'b1;
                end
                //
                // all bits send?
                if ((|tx_engine.bitcnt) == 1'b0) begin 
                  tx_engine.done       <= 1'b1;
                  tx_engine.state[1:0] <= 2'b00;
                end
            end
            // --------------------------------------------------------------
            // "0--": disabled
            // --------------------------------------------------------------
            default: begin
                tx_engine.state[1:0] <= 2'b00;
            end
        endcase
    end : trans_engine

    /* transmitter busy */
    assign tx_engine.busy = ((tx_engine.state[1:0] == 2'b00)) ? 1'b0 : 1'b1;

    /* serial data output */
    assign uart_txd_o = (tx_engine.state == 3'b111) ? tx_engine.sreg[0] : 1'b1; // data is sent LSB-first
    
    // Receive Engine ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : receive_engine
        /* input synchronizer */
        rx_engine.sync[2] <= uart_rxd_i;
        if (uart_clk == 1'b1) begin
          rx_engine.sync[1] <= rx_engine.sync[2];
          rx_engine.sync[0] <= rx_engine.sync[1];
        end

        /* defaults */
        rx_engine.done <= 1'b0;

        /* FSM */
        rx_engine.state[1] <= ctrl.enable;
        unique case (rx_engine.state)
            // --------------------------------------------------------------
            // IDLE: wait for incoming transmission
            2'b10 : begin
                rx_engine.baudcnt <= {1'b0, ctrl.baud[9:1]}; // half baud delay at the beginning to sample in the middle of each bit
                rx_engine.bitcnt  <= 4'b1010; // 1 start-bit + 8 data-bits + 1 stop-bit
                if (rx_engine.sync[1:0] == 2'b01) begin // start bit detected (falling edge)?
                  rx_engine.state[0] <= 1'b1;
                end
            end
            // --------------------------------------------------------------
            // RECEIVE: sample receive data
            2'b11 : begin
                if (uart_clk == 1'b1) begin
                  if (|rx_engine.baudcnt == 1'b0) begin // bit done
                     rx_engine.baudcnt <= ctrl.baud;
                     rx_engine.bitcnt  <= rx_engine.bitcnt - 1'b1;
                     rx_engine.sreg    <= {rx_engine.sync[2], rx_engine.sreg[$bits(rx_engine.sreg)-1 : 1]};
                  end else
                     rx_engine.baudcnt <= rx_engine.baudcnt - 1'b1;
                end
                //
                // all bits received?
                if (|rx_engine.bitcnt == 1'b0) begin 
                  rx_engine.done     <= 1'b1; // receiving done
                  rx_engine.state[0] <= 1'b0;
                end
            end
            // --------------------------------------------------------------
            // "0--": disabled
            default: begin
                rx_engine.state[0] <= 1'b0;
            end
        endcase
    end

    /* RX overrun flag */
    always_ff @( posedge clk_i ) begin
        // clear when reading data register
        if (((rden == 1'b1) && (addr == uart_id_rtx_addr_c)) || (ctrl.enable == 1'b0)) 
          rx_engine.over <= 1'b0;
        else if ((rx_fifo.we == 1'b1) && (rx_fifo.free == 1'b0)) // writing to full FIFO
          rx_engine.over <= 1'b1;     
    end

    /* HW flow-control: ready to receive? */
    always_ff @( posedge clk_i ) begin
        if (ctrl.hwfc_en == 1'b1) begin
          if ((ctrl.enable == 1'b0) | // UART disabled
             (rx_fifo.half == 1'b1))  // RX FIFO at least half-full: no "safe space" left in RX FIFO
            uart_rts_o <= 1'b1; // NOT allowed to send
          else
            uart_rts_o <= 1'b0; // ready to receive
        end else
          uart_rts_o <= 1'b0;   // always ready to receive when HW flow-control is disabled
    end

    // SIMULATION Transmitter --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        /*---------------------------------*/
        /* WARNING: for SIMULATION ONLY!   */
        /*---------------------------------*/

        if (is_simulation_c == 1'b1) begin : simulation_transmitter
            /* simulation output configuration */
            localparam logic  sim_screen_output_en_c = 1'b1; // output lowest byte as char to simulator console when enabled
            localparam logic  sim_text_output_en_c   = 1'b1; // output lowest byte as char to text file when enabled
            localparam logic  sim_data_output_en_c   = 1'b1; // dump 32-bit TX word to file when enabled
            localparam string sim_uart_text_file_c   = cond_sel_string_f(UART_PRIMARY, "cellrv32.uart0.sim_mode.text.out", "cellrv32.uart1.sim_mode.text.out");
            localparam string sim_uart_data_file_c   = cond_sel_string_f(UART_PRIMARY, "cellrv32.uart0.sim_mode.data.out", "cellrv32.uart1.sim_mode.data.out");
            
            int file_uart_text_out = $fopen(sim_uart_text_file_c, "w+");
            int file_uart_data_out = $fopen(sim_uart_data_file_c, "w+");
            int char_v;
            string line_screen_v =""; // we need several line variables here since "writeline" seems to flush the source variable
            string line_text_v = "";
            logic [3:0] line_data_v;

            // statements
            always_comb begin
                if ((ctrl.enable == 1'b1) && (ctrl.sim_mode == 1'b1) && 
                    (wren == 1'b1) && (addr == uart_id_rtx_addr_c)) begin // UART simulation mode
                    /* print lowest byte as ASCII char */
                    char_v = int'(data_i);
                    // check out of range
                    if (char_v >= 128) begin
                        char_v = 0;
                    end

                    /* ASCII output */
                    if ((char_v != 10) && (char_v != 13)) begin // skip line breaks - they are issued via "write line"
                        // data on screen
                        if (sim_screen_output_en_c == 1'b1) begin
                            line_screen_v = {line_screen_v, string'(char_v)};
                        end
                        // generate output text
                        if (sim_text_output_en_c == 1'b1) begin
                            line_text_v = {line_text_v, string'(char_v)};
                        end
                    end else if (char_v == 10) begin // line break: write to screen and text file
                        // display on screen
                        if (sim_screen_output_en_c == 1'b1) begin
                            $display("%s", line_screen_v);
                            // clear all char
                            line_screen_v = "";
                        end
                        // write text to output file
                        if (sim_text_output_en_c == 1'b1) begin
                            $fwrite(file_uart_text_out, "%s", line_text_v);
                            // next line
                            $fdisplay(file_uart_text_out);
                            // clear all char
                            line_text_v = "";
                        end
                    end

                    /* dump raw data as 8 hex chars to file */
                    if (sim_data_output_en_c) begin
                        $fwrite(file_uart_data_out, "%h", data_i);
                        // next line
                        $fdisplay(file_uart_data_out);
                    end
                end
            end
        end : simulation_transmitter
    endgenerate
endmodule