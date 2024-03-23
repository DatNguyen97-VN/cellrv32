// ##################################################################################################
// # << CELLRV32 - Execute In Place (XIP) Module >>                                                 #
// # ********************************************************************************************** #
// # This module allows the CPU to execute code (and read constant data) directly from an SPI       #
// # flash memory. Two host ports are implemented: one  for accessing the control and status        #
// # registers (mapped to the processor's IO space) and one for the actual instruction/data fetch.  #
// # The actual address space mapping of the "instruction/data interface" is done by programming    #
// # special control register bits.                                                                 #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_xip (
    /* global control */
    input  logic        clk_i ,    // global clock line
    input  logic        rstn_i,    // global reset line, low-active, async
    /* host access: control register access port */
    input  logic [31:0] ct_addr_i, // address
    input  logic        ct_rden_i, // read enable
    input  logic        ct_wren_i, // write enable
    input  logic [31:0] ct_data_i, // data in
    output logic [31:0] ct_data_o, // data out
    output logic        ct_ack_o,  // transfer acknowledge
    /* host access: transparent SPI access port (read-only) */
    input  logic [31:0] acc_addr_i, // address
    input  logic        acc_rden_i, // read enable
    input  logic        acc_wren_i, // write enable
    output logic [31:0] acc_data_o, // data out
    output logic        acc_ack_o,  // transfer acknowledge
    output logic        acc_err_o,  // transfer error
    /* status */
    output logic        xip_en_o ,  // XIP enable
    output logic        xip_acc_o,  // pending XIP access
    output logic [03:0] xip_page_o, // XIP page
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [07:0] clkgen_i,
    /* SPI device interface */
    output logic        spi_csn_o, // chip-select, low-active
    output logic        spi_clk_o, // serial clock
    input  logic        spi_dat_i, // device data output
    output logic        spi_dat_o  // controller data output
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(xip_size_c); // low address boundary bit

    /* CT register access control */
    logic        ct_acc_en ; // module access enable
    logic [31:0] ct_addr;    // access address
    logic        ct_wren;    // word write enable
    logic        ct_rden;    // read enable

    /* control register */
    localparam int ctrl_enable_c      =  0; // r/w: module enable
    localparam int ctrl_spi_prsc0_c   =  1; // r/w: SPI clock prescaler select - bit 0
    localparam int ctrl_spi_prsc1_c   =  2; // r/w: SPI clock prescaler select - bit 1
    localparam int ctrl_spi_prsc2_c   =  3; // r/w: SPI clock prescaler select - bit 2
    localparam int ctrl_spi_cpol_c    =  4; // r/w: SPI (idle) clock polarity
    localparam int ctrl_spi_cpha_c    =  5; // r/w: SPI clock phase
    localparam int ctrl_spi_nbytes0_c =  6; // r/w: SPI number of bytes in transmission (1..9) - bit 0
    localparam int ctrl_spi_nbytes3_c =  9; // r/w: SPI number of bytes in transmission (1..9) - bit 3
    localparam int ctrl_xip_enable_c  = 10; // r/w: XIP access mode enable
    localparam int ctrl_xip_abytes0_c = 11; // r/w: XIP number of address bytes (0=1,1=2,2=3,3=4) - bit 0
    localparam int ctrl_xip_abytes1_c = 12; // r/w: XIP number of address bytes (0=1,1=2,2=3,3=4) - bit 1
    localparam int ctrl_rd_cmd0_c     = 13; // r/w: SPI flash read command - bit 0
    localparam int ctrl_rd_cmd7_c     = 20; // r/w: SPI flash read command - bit 7
    localparam int ctrl_page0_c       = 21; // r/w: XIP memory page - bit 0
    localparam int ctrl_page3_c       = 24; // r/w: XIP memory page - bit 3
    localparam int ctrl_spi_csen_c    = 25; // r/w: SPI chip-select enabled
    localparam int ctrl_highspeed_c   = 26; // r/w: SPI high-speed mode enable (ignoring ctrl_spi_prsc)
    localparam int ctrl_burst_en_c    = 27; // r/w: XIP burst mode enable
    //
    localparam int ctrl_phy_busy_c    = 30; // r/-: SPI PHY is busy when set
    localparam int ctrl_xip_busy_c    = 31; // r/-: XIP access in progress
    //
    logic [27:0] ctrl;

    /* Direct SPI access registers */
    logic [31:0] spi_data_lo;
    logic [31:0] spi_data_hi; // write-only!
    logic        spi_trigger; // trigger direct SPI operation

    /* XIP access address */
    logic [31:0] xip_addr;

    /* SPI access fetch arbiter */
    typedef enum { S_DIRECT, S_IDLE,
                   S_CHECK, S_TRIG, 
                   S_BUSY, S_ERROR } arbiter_state_t;
    typedef struct {
        arbiter_state_t state;
        arbiter_state_t state_nxt;
        logic [31:0]    addr;
        logic [31:0]    addr_lookahead;
        logic           busy;
        logic [04:0]    tmo_cnt; // timeout counter for auto CS de-assert (burst mode only)
    } arbiter_t;
    //
    arbiter_t arbiter;

    /* SPI clock */
    logic spi_clk_en;

    /* SPI PHY interface */
    typedef struct {
        logic        start; // trigger new transmission
        logic        Final; // stop current transmission
        logic        busy;  // transmission in progress when set
        logic [71:0] wdata; // write data
        logic [31:0] rdata; // read data
    } phy_if_t;
    //
    phy_if_t phy_if;

    // Access Control (IO/CTRL port) -------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign ct_acc_en = (ct_addr_i[hi_abb_c : lo_abb_c] == xip_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign ct_addr   = {xip_base_c[31 : lo_abb_c], ct_addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign ct_wren   = ct_acc_en & ct_wren_i;
    assign ct_rden   = ct_acc_en & ct_rden_i;


    // Control Write Access ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : ctrl_write_access
        if (rstn_i == 1'b0) begin
            ctrl        <= '0;
            spi_data_lo <= '0;
            spi_data_hi <= '0;
            spi_trigger <= 1'b0;
        end else begin
            spi_trigger <= 1'b0;
            if (ct_wren == 1'b1) begin // only full-word writes!
              /* control register */
              if (ct_addr == xip_ctrl_addr_c) begin
                 ctrl[ctrl_enable_c]                           <= ct_data_i[ctrl_enable_c];
                 ctrl[ctrl_spi_prsc2_c : ctrl_spi_prsc0_c]     <= ct_data_i[ctrl_spi_prsc2_c : ctrl_spi_prsc0_c];
                 ctrl[ctrl_spi_cpol_c]                         <= ct_data_i[ctrl_spi_cpol_c];
                 ctrl[ctrl_spi_cpha_c]                         <= ct_data_i[ctrl_spi_cpha_c];
                 ctrl[ctrl_spi_nbytes3_c : ctrl_spi_nbytes0_c] <= ct_data_i[ctrl_spi_nbytes3_c : ctrl_spi_nbytes0_c];
                 ctrl[ctrl_xip_enable_c]                       <= ct_data_i[ctrl_xip_enable_c];
                 ctrl[ctrl_xip_abytes1_c : ctrl_xip_abytes0_c] <= ct_data_i[ctrl_xip_abytes1_c : ctrl_xip_abytes0_c];
                 ctrl[ctrl_rd_cmd7_c : ctrl_rd_cmd0_c]         <= ct_data_i[ctrl_rd_cmd7_c : ctrl_rd_cmd0_c];
                 ctrl[ctrl_page3_c : ctrl_page0_c]             <= ct_data_i[ctrl_page3_c : ctrl_page0_c];
                 ctrl[ctrl_spi_csen_c]                         <= ct_data_i[ctrl_spi_csen_c];
                 ctrl[ctrl_highspeed_c]                        <= ct_data_i[ctrl_highspeed_c];
                 ctrl[ctrl_burst_en_c]                         <= ct_data_i[ctrl_burst_en_c];
              end
              /* SPI direct data access register lo */
              if (ct_addr == xip_data_lo_addr_c) begin
                 spi_data_lo <= ct_data_i;
              end
              /* SPI direct data access register hi */
              if (ct_addr == xip_data_hi_addr_c) begin
                 spi_data_hi <= ct_data_i;
                 spi_trigger <= 1'b1; // trigger direct SPI transaction
              end
            end
        end
    end : ctrl_write_access

    /* XIP enabled */
    assign xip_en_o = ctrl[ctrl_enable_c];

    /* XIP page output */
    assign xip_page_o = ctrl[ctrl_page3_c : ctrl_page0_c];

    // Control Read Access -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : ctrl_read_access
         ct_ack_o  <= ct_wren | ct_rden; // access acknowledge
         ct_data_o <= '0;
         //
         if (ct_rden == 1'b1) begin
            unique case (ct_addr[3:2])
                // 'xip_ctrl_addr_c' - control register
                2'b00 : begin
                    ct_data_o[ctrl_enable_c]                           <= ctrl[ctrl_enable_c];
                    ct_data_o[ctrl_spi_prsc2_c : ctrl_spi_prsc0_c]     <= ctrl[ctrl_spi_prsc2_c : ctrl_spi_prsc0_c];
                    ct_data_o[ctrl_spi_cpol_c]                         <= ctrl[ctrl_spi_cpol_c];
                    ct_data_o[ctrl_spi_cpha_c]                         <= ctrl[ctrl_spi_cpha_c];
                    ct_data_o[ctrl_spi_nbytes3_c : ctrl_spi_nbytes0_c] <= ctrl[ctrl_spi_nbytes3_c : ctrl_spi_nbytes0_c];
                    ct_data_o[ctrl_xip_enable_c]                       <= ctrl[ctrl_xip_enable_c];
                    ct_data_o[ctrl_xip_abytes1_c : ctrl_xip_abytes0_c] <= ctrl[ctrl_xip_abytes1_c : ctrl_xip_abytes0_c];
                    ct_data_o[ctrl_rd_cmd7_c : ctrl_rd_cmd0_c]         <= ctrl[ctrl_rd_cmd7_c : ctrl_rd_cmd0_c];
                    ct_data_o[ctrl_page3_c : ctrl_page0_c]             <= ctrl[ctrl_page3_c : ctrl_page0_c];
                    ct_data_o[ctrl_spi_csen_c]                         <= ctrl[ctrl_spi_csen_c];
                    ct_data_o[ctrl_highspeed_c]                        <= ctrl[ctrl_highspeed_c];
                    ct_data_o[ctrl_burst_en_c]                         <= ctrl[ctrl_burst_en_c];
                    //
                    ct_data_o[ctrl_phy_busy_c] <= phy_if.busy;
                    ct_data_o[ctrl_xip_busy_c] <= arbiter.busy;
                end
                // 'xip_data_lo_addr_c' - SPI direct data access register lo
                2'b10 : begin
                    ct_data_o <= phy_if.rdata;
                end
                // unavailable (not implemented or write-only)
                default: begin
                    ct_data_o <= '0;
                end
            endcase
         end
    end : ctrl_read_access

    // XIP Address Computation Logic -------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    logic [31:0] tmp_v;
    //
    always_comb begin : xip_access_logic
       tmp_v[31:28] = 4'b0000;
       tmp_v[27:02] = arbiter.addr[27:02];
       tmp_v[01:00] = 2'b00; // always align to 32-bit boundary; sub-word read accesses are handled by the CPU logic
       //
       unique case (ctrl[ctrl_xip_abytes1_c : ctrl_xip_abytes0_c])
        2'b00 : xip_addr = {tmp_v[07:0], 24'h000000}; // 1 address byte 
        2'b01 : xip_addr = {tmp_v[15:0], 16'h0000};   // 2 address bytes
        2'b10 : xip_addr = {tmp_v[23:0], 8'h00};      // 3 address bytes
        default: begin
                xip_addr = tmp_v[31:0];               // 4 address bytes
        end
       endcase
    end : xip_access_logic

    // SPI Access Arbiter ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : arbiter_sync
        /* state control */
        if ((ctrl[ctrl_enable_c] == 1'b0) || (ctrl[ctrl_xip_enable_c] == 1'b0)) begin // sync reset
          arbiter.state <= S_DIRECT;
        end else begin
          arbiter.state <= arbiter.state_nxt;
        end
        /* address look-ahead */
        if ((acc_rden_i == 1'b1) && (acc_addr_i[31:28] == ctrl[ctrl_page3_c : ctrl_page0_c])) begin
          arbiter.addr <= acc_addr_i; // buffer address (reducing fan-out on CPU's address net)
        end
        //
        arbiter.addr_lookahead <= arbiter.addr + 4; // prefetch address of *next* linear access
        //
        /* pending flash access timeout */
        if ((ctrl[ctrl_enable_c] == 1'b0) || (ctrl[ctrl_xip_enable_c] == 1'b0) || (arbiter.state == S_BUSY)) begin // sync reset
          arbiter.tmo_cnt <= '0;
        end else if (arbiter.tmo_cnt[$bits(arbiter.tmo_cnt)-1] == 1'b0) begin // stop if maximum reached
          arbiter.tmo_cnt <= arbiter.tmo_cnt + 1'b1;
        end
    end : arbiter_sync

    /* FSM - combinatorial part */
    always_comb begin : arbiter_comb
        /* arbiter defaults */
        arbiter.state_nxt = arbiter.state;

        /* bus interface defaults */
        acc_data_o = '0;
        acc_ack_o  = 1'b0;
        acc_err_o  = 1'b0;

        /* SPI PHY interface defaults */
        phy_if.start = 1'b0;
        phy_if.Final = arbiter.tmo_cnt[$bits(arbiter.tmo_cnt)-1] | (~ ctrl[ctrl_burst_en_c]); // terminate if timeout or if burst mode not enabled
        phy_if.wdata = {ctrl[ctrl_rd_cmd7_c : ctrl_rd_cmd0_c], xip_addr, 32'h00000000}; // MSB-aligned: CMD + address + 32-bit zero data

        /* fsm */
        unique case (arbiter.state)
            // --------------------------------------------------------------
            // XIP access disabled; direct SPI access
            S_DIRECT : begin
                 phy_if.wdata      = {spi_data_hi, spi_data_lo, 8'h00}; // MSB-aligned data
                 phy_if.start      = spi_trigger;
                 phy_if.Final      = 1'b1; // do not keep CS active after transmission is done
                 arbiter.state_nxt = S_IDLE;
            end
            // --------------------------------------------------------------
            // wait for new bus request
            S_IDLE : begin
                if (acc_addr_i[31:28] == ctrl[ctrl_page3_c : ctrl_page0_c]) begin
                  if (acc_rden_i == 1'b1) begin
                     arbiter.state_nxt = S_CHECK;
                  end else if (acc_wren_i == 1'b1) begin
                     arbiter.state_nxt = S_ERROR;
                  end
                end
            end
            // --------------------------------------------------------------
            // check if we can resume flash access
            S_CHECK : begin
                if ((arbiter.addr[27:2] == arbiter.addr_lookahead[27:2]) && (ctrl[ctrl_burst_en_c] == 1'b1) && // access to *next linear* address
                    (arbiter.tmo_cnt[$bits(arbiter.tmo_cnt)-1] == 1'b0)) begin // no "pending access" timeout yet
                  phy_if.start      = 1'b1; // resume flash access
                  arbiter.state_nxt = S_BUSY;
                end else begin
                  phy_if.Final      = 1'b1; // restart flash access
                  arbiter.state_nxt = S_TRIG;
                end
            end
            // --------------------------------------------------------------
            // trigger NEW flash read
            S_TRIG : begin
                phy_if.start      = 1'b1;
                arbiter.state_nxt = S_BUSY;
            end
            // --------------------------------------------------------------
            // wait for PHY to complete operation
            S_BUSY : begin
                acc_data_o <= bswap32_f(phy_if.rdata); // convert incrementing byte-read to little-endian
                if (phy_if.busy == 1'b0) begin
                  acc_ack_o         = 1'b1;
                  arbiter.state_nxt = S_IDLE;
                end
            end
            // --------------------------------------------------------------
            // access error
            S_ERROR : begin
                acc_err_o         = 1'b1;
                arbiter.state_nxt = S_IDLE;
            end
            // --------------------------------------------------------------
            // undefined
            default: begin
                arbiter.state_nxt = S_IDLE;
            end
        endcase
    end : arbiter_comb

    /* arbiter status */
    assign arbiter.busy = ((arbiter.state == S_TRIG) || (arbiter.state == S_BUSY)) ? 1'b1 : 1'b0; // actual XIP access in progress

    /* status output */
    assign xip_acc_o = arbiter.busy;


    // SPI Clock Generator -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // enable clock generator */
    assign clkgen_en_o = ctrl[ctrl_enable_c];

    /* clock select */
    assign spi_clk_en = clkgen_i[ctrl[ctrl_spi_prsc2_c : ctrl_spi_prsc0_c]] | ctrl[ctrl_highspeed_c];

    // SPI Physical Interface --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_xip_phy cellrv32_xip_phy_inst (
        /* global control */
        .clk_i(clk_i),
        .spi_clk_en_i(spi_clk_en),
        /* operation configuration */
        .cf_enable_i(ctrl[ctrl_enable_c]),  // module enable (reset if low)
        .cf_cpha_i(ctrl[ctrl_spi_cpha_c]),  // clock phase
        .cf_cpol_i(ctrl[ctrl_spi_cpol_c]),  // clock idle polarity
        /* operation control */
        .op_start_i(phy_if.start),          // trigger new transmission
        .op_final_i(phy_if.Final),          // end current transmission
        .op_csen_i(ctrl[ctrl_spi_csen_c]),  // actually enabled device for transmission
        .op_busy_o(phy_if.busy),            // transmission in progress when set
        .op_nbytes_i(ctrl[ctrl_spi_nbytes3_c : ctrl_spi_nbytes0_c]), // actual number of bytes to transmit
        .op_wdata_i(phy_if.wdata),          // write data
        .op_rdata_o(phy_if.rdata),          // read data
        /* SPI interface */
        .spi_csn_o(spi_csn_o),
        .spi_clk_o(spi_clk_o),
        .spi_dat_i(spi_dat_i),
        .spi_dat_o(spi_dat_o)
    );

endmodule