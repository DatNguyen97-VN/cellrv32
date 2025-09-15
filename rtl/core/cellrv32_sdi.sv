// ##################################################################################################
// # << CELLRV32 - Serial Data Interface (SDI) >>                                                   #
// # ********************************************************************************************** #
// # Byte-oriented serial data interface using the SPI protocol. This device acts as *device* (not  #
// # as a host). Hence, all data transfers are driven/clocked by an external SPI host controller.   # 
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_sdi #(
    parameter int RTX_FIFO = 1 // RTX fifo depth, has to be a power of two, min 1
) (
    /* host access */
    input  logic        clk_i,     // global clock line
    input  logic        rstn_i,    // global reset line, low-active, async
    input  logic [31:0] addr_i,    // address
    input  logic        rden_i,    // read enable
    input  logic        wren_i,    // write enable
    input  logic [31:0] data_i,    // data in
    output logic [31:0] data_o,    // data out
    output logic        ack_o,     // transfer acknowledge
    /* SDI receiver input */
    input  logic        sdi_csn_i, // low-active chip-select
    input  logic        sdi_clk_i, // serial clock
    input  logic        sdi_dat_i, // serial data input
    output logic        sdi_dat_o, // serial data output
    /* interrupts */
    output logic        irq_o
);
    /* IO space: module base address */
    localparam int hi_abb_c = $clog2(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = $clog2(sdi_size_c); // low address boundary bit

    /* control register */
    localparam int ctrl_en_c           =  0; // r/w: SDI enable
    localparam int ctrl_clr_rx_c       =  1; // -/w: clear RX FIFO, auto-clears
    //constant ctrl_cpha_c         : natural :=  2; // r/w: clock phase [TODO]
    //
    localparam int ctrl_fifo_size0_c   =  4; // r/-: log2(FIFO size), bit 0 (lsb)
    localparam int ctrl_fifo_size1_c   =  5; // r/-: log2(FIFO size), bit 1
    localparam int ctrl_fifo_size2_c   =  6; // r/-: log2(FIFO size), bit 2
    localparam int ctrl_fifo_size3_c   =  7; // r/-: log2(FIFO size), bit 3 (msb)
    //
    localparam int ctrl_irq_rx_avail_c = 15; // r/-: RX FIFO not empty
    localparam int ctrl_irq_rx_half_c  = 16; // r/-: RX FIFO at least half full
    localparam int ctrl_irq_rx_full_c  = 17; // r/-: RX FIFO full
    localparam int ctrl_irq_tx_empty_c = 18; // r/-: TX FIFO empty
    //
    localparam int ctrl_rx_avail_c     = 23; // r/-: RX FIFO not empty
    localparam int ctrl_rx_half_c      = 24; // r/-: RX FIFO at least half full
    localparam int ctrl_rx_full_c      = 25; // r/-: RX FIFO full
    localparam int ctrl_tx_empty_c     = 26; // r/-: TX FIFO empty
    localparam int ctrl_tx_full_c      = 27; // r/-: TX FIFO full

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* control register (see bit definitions above) */
    typedef struct {
        logic enable;
        logic clr_rx;
        logic irq_rx_avail;
        logic irq_rx_half;
        logic irq_rx_full;
        logic irq_tx_empty;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* input synchronizer */
    typedef struct {
        logic [2:0] sck_ff;
        logic [1:0] csn_ff;
        logic [1:0] sdi_ff;
        logic       sck;
        logic       csn;
        logic       sdi;
    } sync_t;
    //
    sync_t sync;

    /* serial engine */
    typedef struct packed {
        logic [2:0] state;
        logic [3:0] cnt;
        logic [7:0] sreg;
        logic sdi_ff;
        logic start;
        logic done;
    } serial_t;
    //
    serial_t serial;

    /* RX/TX FIFO interface */
    typedef struct {
        logic       we;    // write enable
        logic       re;    // read enable
        logic       clear; // sync reset, high-active
        logic [7:0] wdata; // write data
        logic [7:0] rdata; // read data
        logic       avail; // data available?
        logic       free;  // free entry available?
        logic       half;  // half full
    } fifo_t;
    //
    fifo_t tx_fifo, rx_fifo;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (!(is_power_of_two_f(RTX_FIFO) == 1'b0)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR: SDI FIFO size has to be a power of two.");
        //
        assert (!(RTX_FIFO > 2**15)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR: SDI FIFO size out of valid range (1..32768).");
    end

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == sdi_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {sdi_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    /* write */
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            ctrl.enable       <= 1'b0;
            ctrl.clr_rx       <= 1'b0;
            ctrl.irq_rx_avail <= 1'b0;
            ctrl.irq_rx_half  <= 1'b0;
            ctrl.irq_rx_full  <= 1'b0;
            ctrl.irq_tx_empty <= 1'b0;
        end else begin
            ctrl.clr_rx <= 1'b0;
            //
            if (wren == 1'b1) begin
                if (addr == sdi_ctrl_addr_c) begin // control register
                    ctrl.enable <= data_i[ctrl_en_c];
                    ctrl.clr_rx <= data_i[ctrl_clr_rx_c];
                    //
                    ctrl.irq_rx_avail <= data_i[ctrl_irq_rx_avail_c];
                    ctrl.irq_rx_half  <= data_i[ctrl_irq_rx_half_c];
                    ctrl.irq_rx_full  <= data_i[ctrl_irq_rx_full_c];
                    ctrl.irq_tx_empty <= data_i[ctrl_irq_tx_empty_c];
                end
            end
        end
    end : write_access

    /* read */
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus access acknowledge
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            if (addr == sdi_ctrl_addr_c) begin // control register
                data_o[ctrl_en_c] <= ctrl.enable;
                //
                data_o[ctrl_fifo_size3_c : ctrl_fifo_size0_c] <= (ctrl_fifo_size3_c - ctrl_fifo_size0_c + 1)'($clog2(RTX_FIFO));
                //
                data_o[ctrl_irq_rx_avail_c] <= ctrl.irq_rx_avail;
                data_o[ctrl_irq_rx_half_c]  <= ctrl.irq_rx_half;
                data_o[ctrl_irq_rx_full_c]  <= ctrl.irq_rx_full;
                data_o[ctrl_irq_tx_empty_c] <= ctrl.irq_tx_empty;
                //
                data_o[ctrl_rx_avail_c] <= rx_fifo.avail;
                data_o[ctrl_rx_half_c]  <= rx_fifo.half;
                data_o[ctrl_rx_full_c]  <= ~ rx_fifo.free;
                data_o[ctrl_tx_empty_c] <= ~ tx_fifo.avail;
                data_o[ctrl_tx_full_c]  <= ~ tx_fifo.free;
            end else begin
                data_o[7:0] <= rx_fifo.rdata;
            end
        end
    end : read_access

    // Data FIFO ("Ring Buffer") -----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* TX */
    cellrv32_fifo #(
        .FIFO_DEPTH(RTX_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(8),        // size of data elements in fifo (32-bit only for simulation)
        .FIFO_RSYNC(1'b1),    // async read
        .FIFO_SAFE(1'b1),     // safe access
        .FIFO_GATE(1'b1)      // output zero if no data available
    ) tx_fifo_inst (
        /* control */
        .clk_i(clk_i),           // clock, rising edge
        .rstn_i(rstn_i),         // async reset, low-active
        .clear_i(tx_fifo.clear), // sync reset, high-active
        .half_o(tx_fifo.half),   // FIFO at least half-full
        /* write port */
        .wdata_i(tx_fifo.wdata), // write data
        .we_i(tx_fifo.we),       // write enable
        .free_o(tx_fifo.free),   // at least one entry is free when set
        /* read port */
        .re_i(tx_fifo.re),       // read enable
        .rdata_o(tx_fifo.rdata), // read data
        .avail_o(tx_fifo.avail)  // data available when set
    );

    /* write access (CPU) */
    assign tx_fifo.clear = ~ ctrl.enable;
    assign tx_fifo.wdata = data_i[7:0];
    assign tx_fifo.we    = ((wren == 1'b1) && (addr == sdi_rtx_addr_c)) ? 1'b1 : 1'b0;

    /* read access (SDI) */
    assign tx_fifo.re = serial.start;

    /* RX */
    cellrv32_fifo #(
        .FIFO_DEPTH(RTX_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(8),        // size of data elements in fifo (32-bit only for simulation)
        .FIFO_RSYNC(1'b1),    // async read
        .FIFO_SAFE(1'b1),     // safe access
        .FIFO_GATE(1'b0)      // no output gate required
    ) rx_fifo_inst (
        /* control */
        .clk_i(clk_i),           // clock, rising edge
        .rstn_i(rstn_i),         // async reset, low-active
        .clear_i(rx_fifo.clear), // sync reset, high-active
        .half_o(rx_fifo.half),   // FIFO at least half-full
        /* write port */
        .wdata_i(rx_fifo.wdata), // write data
        .we_i(rx_fifo.we),       // write enable
        .free_o(rx_fifo.free),   // at least one entry is free when set
        /* read port */
        .re_i(rx_fifo.re),       // read enable
        .rdata_o(rx_fifo.rdata), // read data
        .avail_o(rx_fifo.avail)  // data available when set
    );

    /* write access (SDI) */
    assign rx_fifo.wdata = serial.sreg;
    assign rx_fifo.we    = serial.done;

    /* read access (CPU) */
    assign rx_fifo.clear = (~ ctrl.enable) | ctrl.clr_rx;
    assign rx_fifo.re    = ((rden == 1'b1) && (addr == sdi_rtx_addr_c)) ? 1'b1 : 1'b0;
    
    // Input Synchronizer ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        sync.sck_ff <= {sync.sck_ff[1:0], sdi_clk_i};
        sync.csn_ff <= {sync.csn_ff[0], sdi_csn_i};
        sync.sdi_ff <= {sync.sdi_ff[0], sdi_dat_i};
    end

    assign sync.sck = sync.sck_ff[1] ^ sync.sck_ff[2]; // edge detect
    assign sync.csn = sync.csn_ff[1];
    assign sync.sdi = sync.sdi_ff[1];

    // Serial Engine -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        /* defaults */
        serial.start <= 1'b0;
        serial.done  <= 1'b0;

        /* FSM */
        serial.state[2] <= ctrl.enable;
        //
        unique case (serial.state)
            // --------------------------------------------------------------
            // enabled but idle, waiting for new transmission trigger
            3'b100 : begin
                if (sync.csn == 1'b0) begin // start new transmission on falling edge of chip-select
                  serial.state[1:0] <= 2'b10;
                  serial.start      <= 1'b1;
                end
                serial.cnt  <= 4'h0;
                serial.sreg <= tx_fifo.rdata;
            end
            // --------------------------------------------------------------
            // bit phase A: sample
            3'b110 : begin
                if (sync.csn == 1'b1) // transmission aborted?
                  serial.state[1:0] <= 2'b00;
                else if (sync.sck == 1'b1) begin
                  serial.state[1:0] <= 2'b11;
                  serial.cnt[3:0]   <= serial.cnt + 1'b1;
                end
                serial.sdi_ff <= sdi_dat_i;
            end
            // --------------------------------------------------------------
            // bit phase B: shift
            3'b111 : begin
                if (sync.csn == 1'b1) begin // transmission aborted?
                    serial.state[1:0] <= 2'b00;
                end else if (sync.sck == 1'b1) begin
                    if (serial.cnt[3] == 1'b1) begin // done?
                      serial.state[1:0] <= 2'b00;
                      serial.done       <= 1'b1;
                    end else
                      serial.state[1:0] <= 2'b10;
                    serial.sreg <= {serial.sreg[$bits(serial.sreg)-2 : 0], serial.sdi_ff};
                end
            end
            // --------------------------------------------------------------
            // "0--": disabled
            default: begin
                serial.state[1:0] <= 2'b00;
            end
        endcase
    end

    /* serial data output */
    assign sdi_dat_o = serial.sreg[$bits(serial.sreg)-1];

    // Interrupt Generator -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin
        irq_o <= ctrl.enable & (
                 (ctrl.irq_rx_avail & rx_fifo.avail)    | // RX FIFO not empty
                 (ctrl.irq_rx_half  & rx_fifo.half)     | // RX FIFO at least half full
                 (ctrl.irq_rx_full  & (~ rx_fifo.free)) | // RX FIFO full
                 (ctrl.irq_tx_empty & (~ tx_fifo.avail))); // TX FIFO empty
    end

    /* DFT compute */

endmodule