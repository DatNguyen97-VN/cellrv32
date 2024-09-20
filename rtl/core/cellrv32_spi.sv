// ##################################################################################################
// # << CELLRV32 - Serial Peripheral Interface Controller (SPI) >>                                  #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_spi #(
    parameter int IO_SPI_FIFO = 1 // SPI RTX fifo depth, has to be a power of two, min 1
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
    output logic        clkgen_en_o , // enable clock generator
    input  logic [07:0] clkgen_i,
    /* com lines */
    output logic        spi_clk_o, // SPI serial clock
    output logic        spi_dat_o, // controller data out, peripheral data in
    input  logic        spi_dat_i, // controller data in, peripheral data out
    output logic [07:0] spi_csn_o, // SPI CS
    /* interrupt */
    output logic        irq_o      // transmission done interrupt
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(spi_size_c); // low address boundary bit

    /* control register */
    localparam int ctrl_en_c      =  0; // r/w: spi enable
    localparam int ctrl_cpha_c    =  1; // r/w: spi clock phase
    localparam int ctrl_cpol_c    =  2; // r/w: spi clock polarity
    localparam int ctrl_cs_sel0_c =  3; // r/w: spi CS select bit 0
    localparam int ctrl_cs_sel1_c =  4; // r/w: spi CS select bit 1
    localparam int ctrl_cs_sel2_c =  5; // r/w: spi CS select bit 2
    localparam int ctrl_cs_en_c   =  6; // r/w: enable selected cs line (set bit -> clear line)
    localparam int ctrl_prsc0_c   =  7; // r/w: spi prescaler select bit 0
    localparam int ctrl_prsc1_c   =  8; // r/w: spi prescaler select bit 1
    localparam int ctrl_prsc2_c   =  9; // r/w: spi prescaler select bit 2
    localparam int ctrl_cdiv0_c   = 10; // r/w: clock divider bit 0
    localparam int ctrl_cdiv1_c   = 11; // r/w: clock divider bit 1
    localparam int ctrl_cdiv2_c   = 12; // r/w: clock divider bit 2
    localparam int ctrl_cdiv3_c   = 13; // r/w: clock divider bit 3
    //
    localparam int ctrl_rx_avail_c     = 16; // r/-: rx fifo data available (fifo not empty)
    localparam int ctrl_tx_empty_c     = 17; // r/-: tx fifo empty
    localparam int ctrl_tx_nhalf_c     = 18; // r/-: tx fifo not at least half full
    localparam int ctrl_tx_full_c      = 19; // r/-: tx fifo full
    localparam int ctrl_irq_rx_avail_c = 20; // r/w: fire irq if rx fifo data available (fifo not empty)
    localparam int ctrl_irq_tx_empty_c = 21; // r/w: fire irq if tx fifo empty
    localparam int ctrl_irq_tx_nhalf_c = 22; // r/w: fire irq if tx fifo not at least half full
    localparam int ctrl_fifo_size0_c   = 23; // r/-: log2(fifo size), bit 0 (lsb)
    localparam int ctrl_fifo_size1_c   = 24; // r/-: log2(fifo size), bit 1
    localparam int ctrl_fifo_size2_c   = 25; // r/-: log2(fifo size), bit 2
    localparam int ctrl_fifo_size3_c   = 26; // r/-: log2(fifo size), bit 3 (msb)
    //
    localparam int ctrl_busy_c         = 31; // r/-: spi phy busy or tx fifo not empty yet

    /* access control */
    logic        acc_en ; // module access enable
    logic [31:0] addr;    // access address
    logic        wren;    // word write enable
    logic        rden ;   // read enable
    logic        rden_ff;

    /* control register */
    typedef struct {
        logic       enable;
        logic       cpha;
        logic       cpol;
        logic [2:0] cs_sel;
        logic       cs_en;
        logic [2:0] prsc;
        logic [3:0] cdiv;
        logic       irq_rx_avail;
        logic       irq_tx_empty;
        logic       irq_tx_nhalf;
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* clock generator */
    logic [3:0] cdiv_cnt;
    logic       spi_clk_en;

    /* spi transceiver */
    typedef struct {
        logic [2:0] state;
        logic       busy;
        logic       start;
        logic [7:0] sreg;
        logic [3:0] bitcnt;
        logic       sdi_sync;
        logic       done;
    } rtx_engine_t;
    //
    rtx_engine_t rtx_engine;

    /* FIFO interface */
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
        assert (!(is_power_of_two_f(IO_SPI_FIFO) == 1'b0)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR: SPI FIFO size has to be a power of two.");
        //
        assert (!(IO_SPI_FIFO > 2**15)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR: SPI FIFO size has to be in range 1..32768.");
    end

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == spi_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {spi_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    /* write access */
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            ctrl.enable       <= 1'b0;
            ctrl.cpha         <= 1'b0;
            ctrl.cpol         <= 1'b0;
            ctrl.cs_sel       <= '0;
            ctrl.cs_en        <= 1'b0;
            ctrl.prsc         <= '0;
            ctrl.cdiv         <= '0;
            ctrl.irq_rx_avail <= 1'b0;
            ctrl.irq_tx_empty <= 1'b0;
            ctrl.irq_tx_nhalf <= 1'b0;
        end else begin
            if (wren == 1'b1) begin
                if (addr == spi_ctrl_addr_c) begin // control register
                    ctrl.enable       <= data_i[ctrl_en_c];
                    ctrl.cpha         <= data_i[ctrl_cpha_c];
                    ctrl.cpol         <= data_i[ctrl_cpol_c];
                    ctrl.cs_sel       <= data_i[ctrl_cs_sel2_c : ctrl_cs_sel0_c];
                    ctrl.cs_en        <= data_i[ctrl_cs_en_c];
                    ctrl.prsc         <= data_i[ctrl_prsc2_c : ctrl_prsc0_c];
                    ctrl.cdiv         <= data_i[ctrl_cdiv3_c : ctrl_cdiv0_c];
                    ctrl.irq_rx_avail <= data_i[ctrl_irq_rx_avail_c];
                    ctrl.irq_tx_empty <= data_i[ctrl_irq_tx_empty_c];
                    ctrl.irq_tx_nhalf <= data_i[ctrl_irq_tx_nhalf_c];
                end
            end
        end
    end : write_access

    /* read access */
    always_ff @( posedge clk_i ) begin : read_access
         rden_ff <= rden; // delay read access by one cycle due to sync FIFO read access (FIXME?)
         ack_o   <= rden_ff | wren; // bus access acknowledge
         data_o  <= '0;
         //
         if (rden_ff == 1'b1) begin
            if (addr == spi_ctrl_addr_c) begin // control register
                data_o[ctrl_en_c]                       <= ctrl.enable;
                data_o[ctrl_cpha_c]                     <= ctrl.cpha;
                data_o[ctrl_cpol_c]                     <= ctrl.cpol;
                data_o[ctrl_cs_sel2_c : ctrl_cs_sel0_c] <= ctrl.cs_sel;
                data_o[ctrl_cs_en_c]                    <= ctrl.cs_en;
                data_o[ctrl_prsc2_c : ctrl_prsc0_c]     <= ctrl.prsc;
                data_o[ctrl_cdiv3_c : ctrl_cdiv0_c]     <= ctrl.cdiv;
                //
                data_o[ctrl_rx_avail_c]     <= rx_fifo.avail;
                data_o[ctrl_tx_empty_c]     <= ~ tx_fifo.avail;
                data_o[ctrl_tx_nhalf_c]     <= ~ tx_fifo.half;
                data_o[ctrl_tx_full_c]      <= ~ tx_fifo.free;
                data_o[ctrl_irq_rx_avail_c] <= ctrl.irq_rx_avail;
                data_o[ctrl_irq_tx_empty_c] <= ctrl.irq_tx_empty;
                data_o[ctrl_irq_tx_nhalf_c] <= ctrl.irq_tx_nhalf;
                //
                data_o[ctrl_fifo_size3_c : ctrl_fifo_size0_c] <= 4'(index_size_f(IO_SPI_FIFO));
                //
                data_o[ctrl_busy_c] <= rtx_engine.busy | tx_fifo.avail;
            end else begin // data register (spi_rtx_addr_c)
                data_o[7:0] <= rx_fifo.rdata;
            end
         end
    end : read_access

    /* direct chip-select (low-active) */
    always_ff @( posedge clk_i ) begin
        spi_csn_o <= '1; // default: all disabled
        if ((ctrl.cs_en == 1'b1) && (ctrl.enable == 1'b1)) begin
          spi_csn_o[ctrl.cs_sel] <= 1'b0;
        end
    end

    // Data FIFO ("Ring Buffer") -----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------

    /* TX FIFO */
    cellrv32_fifo #(
        .FIFO_DEPTH(IO_SPI_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(8),           // size of data elements in fifo
        .FIFO_RSYNC(1'b1),        // sync read
        .FIFO_SAFE(1'b1),         // safe access
        .FIFO_GATE(1'b0)          // no output gate required
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

    assign tx_fifo.clear = ~ ctrl.enable;
    assign tx_fifo.we    = ((wren == 1'b1) && (addr == spi_rtx_addr_c)) ? 1'b1 : 1'b0;
    assign tx_fifo.wdata = data_i[7:0];
    assign tx_fifo.re    = ((rtx_engine.state == 3'b100) && (tx_fifo.avail == 1'b1) && (rtx_engine.start == 1'b0)) ? 1'b1 : 1'b0;
    
    /* RX FIFO */
    cellrv32_fifo #(
        .FIFO_DEPTH(IO_SPI_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(8),           // size of data elements in fifo
        .FIFO_RSYNC(1'b1),        // sync read
        .FIFO_SAFE(1'b1),         // safe access
        .FIFO_GATE(1'b0)          // no output gate required
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

    assign rx_fifo.clear = ~ ctrl.enable;
    assign rx_fifo.wdata = rtx_engine.sreg;
    assign rx_fifo.we    = rtx_engine.done;
    assign rx_fifo.re    = ((rden == 1'b1) && (addr == spi_rtx_addr_c)) ? 1'b1 : 1'b0;

    /* IRQ generator */
    always_ff @( posedge clk_i ) begin
        irq_o <= ctrl.enable & (
                 (ctrl.irq_rx_avail &    rx_fifo.avail)  | // IRQ if RX FIFO is not empty
                 (ctrl.irq_tx_empty & (~ tx_fifo.avail)) | // IRQ if TX FIFO is empty
                 (ctrl.irq_tx_nhalf & (~ tx_fifo.half)));  // IRQ if TX buffer is not half full
    end

    // SPI Transceiver ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : spi_tx_rx
        /* defaults */
        rtx_engine.done  <= 1'b0;
        rtx_engine.start <= tx_fifo.re; // delay start trigger by one cycle due to sync FIFO read access

        /* serial engine */
        rtx_engine.state[2] <= ctrl.enable;
        //
        unique case (rtx_engine.state)
            // --------------------------------------------------------------
            // enabled but idle, waiting for new transmission trigger
            3'b100 : begin
                spi_clk_o         <= ctrl.cpol;
                rtx_engine.bitcnt <= '0;
                rtx_engine.sreg   <= tx_fifo.rdata;
                if (rtx_engine.start == 1'b1) begin // trigger new transmission
                  rtx_engine.state[1:0] <= 2'b01;
                end
            end
            // --------------------------------------------------------------
            // start with next new clock pulse
            3'b101 : begin
                if (spi_clk_en == 1'b1) begin
                  if (ctrl.cpha == 1'b1) // clock phase shift
                     spi_clk_o <= ~ ctrl.cpol;
                  rtx_engine.state[1:0] <= 2'b10;
                end
            end
            // --------------------------------------------------------------
            // first phase of bit transmission
            3'b110 : begin
                if (spi_clk_en == 1'b1) begin
                  spi_clk_o             <= ~ (ctrl.cpha ^ ctrl.cpol);
                  rtx_engine.sdi_sync   <= spi_dat_i; // sample data input
                  rtx_engine.bitcnt     <= rtx_engine.bitcnt + 1'b1;
                  rtx_engine.state[1:0] <= 2'b11;
                end
            end
            // --------------------------------------------------------------
            // second phase of bit transmission
            3'b111 : begin
                if (spi_clk_en == 1'b1) begin
                    rtx_engine.sreg <= {rtx_engine.sreg[6:0], rtx_engine.sdi_sync}; // shift and set output
                    // all bits transferred?
                    if (rtx_engine.bitcnt[3] == 1'b1) begin
                        spi_clk_o             <= ctrl.cpol;
                        rtx_engine.done       <= 1'b1; // done!
                        rtx_engine.state[1:0] <= 2'b00; // transmission done
                    end else begin
                        spi_clk_o             <= ctrl.cpha ^ ctrl.cpol;
                        rtx_engine.state[1:0] <= 2'b10;
                    end
                end
            end
            // --------------------------------------------------------------
            // "0--": SPI deactivated
            default: begin
                spi_clk_o             <= ctrl.cpol;
                rtx_engine.sreg       <= '0;
                rtx_engine.state[1:0] <= 2'b00;
            end
        endcase
    end : spi_tx_rx

    /* PHY busy flag */
    assign rtx_engine.busy = (rtx_engine.state[1:0] == 2'b00) ? 1'b0 : 1'b1;

    /* data output */
    assign spi_dat_o = rtx_engine.sreg[7]; // MSB first

    /* clock generator */
    always_ff @( posedge clk_i ) begin
        if (ctrl.enable == 1'b0) begin // reset/disabled
            spi_clk_en <= 1'b0;
            cdiv_cnt   <= '0;
        end else begin
            spi_clk_en <= 1'b0; // default
            if (clkgen_i[ctrl.prsc] == 1'b1) begin // pre-scaled clock
                if (cdiv_cnt == ctrl.cdiv) begin // clock divider for fine-tuning
                   spi_clk_en <= 1'b1;
                   cdiv_cnt   <= '0;
                end else
                   cdiv_cnt <= cdiv_cnt + 1'b1;
            end
        end
    end

    /* clock generator enable */
    assign clkgen_en_o = ctrl.enable;
endmodule