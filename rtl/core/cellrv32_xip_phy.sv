// ##################################################################################################
// # << CELLRV32 - XIP Module - SPI Physical Interface >>                                           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_xip_phy (
    /* global control */
    input  logic        clk_i,        // clock
    input  logic        spi_clk_en_i, // pre-scaled SPI clock-enable
    /* operation configuration */
    input  logic        cf_enable_i,  // module enable (reset if low)
    input  logic        cf_cpha_i,    // clock phase
    input  logic        cf_cpol_i,    // clock idle polarity
    /* operation control */
    input  logic        op_start_i,   // trigger new transmission
    input  logic        op_final_i,   // end current transmission
    input  logic        op_csen_i,    // actually enabled device for transmission
    output logic        op_busy_o,    // transmission in progress when set
    input  logic [03:0] op_nbytes_i,  // actual number of bytes to transmit (1..9)
    input  logic [71:0] op_wdata_i,   // write data
    output logic [31:0] op_rdata_o,   // read data
    /* SPI interface */
    output logic        spi_csn_o,
    output logic        spi_clk_o,
    input  logic        spi_dat_i,
    output logic        spi_dat_o
);
    /* serial engine */
    typedef enum { S_IDLE, S_WAIT, S_START,
                   S_SYNC, S_RTX_A, S_RTX_B, S_DONE } ctrl_state_t;
    typedef struct {
        ctrl_state_t state;
        logic [71:0] sreg; // only the lowest 32-bit are used as RX data
        logic [06:0] bitcnt;
        logic        di_sync;
        logic        csen;
    } ctrl_t;
    //
    ctrl_t ctrl;

    // Serial Interface Engine -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : serial_engine
        if (cf_enable_i == 1'b0) begin // sync reset
            spi_clk_o    <= 1'b0;
            spi_csn_o    <= 1'b1;
            ctrl.state   <= S_IDLE;
            ctrl.csen    <= 1'b0;
            ctrl.sreg    <= '0;
            ctrl.bitcnt  <= '0;
            ctrl.di_sync <= 1'b0;
        end else begin // FSM
            unique case (ctrl.state)
                // --------------------------------------------------------------
                // wait for new transmission trigger
                S_IDLE : begin
                    spi_csn_o   <= 1'b1; // flash disabled
                    spi_clk_o   <= cf_cpol_i;
                    ctrl.bitcnt <= {op_nbytes_i, 3'b000}; // number of bytes
                    ctrl.csen   <= op_csen_i;
                    if (op_start_i == 1'b1) begin
                      ctrl.state <= S_START;
                    end
                end
                // --------------------------------------------------------------
                // start of transmission (keep current spi_csn_o state!)
                S_START : begin
                    ctrl.sreg <= op_wdata_i;
                    if (spi_clk_en_i == 1'b1) begin
                      ctrl.state <= S_SYNC;
                    end
                end
                // --------------------------------------------------------------
                // wait for resume transmission trigger
                S_WAIT : begin
                    spi_csn_o   <= ~ ctrl.csen; // keep CS active
                    ctrl.bitcnt <= 7'b0100000; // 4 bytes = 32-bit read data
                    //ctrl.sreg   <= (others => '0'); // do we need this???
                    if (op_final_i == 1'b1) begin // terminate pending flash access
                      ctrl.state  <= S_IDLE;
                    end else if (op_start_i == 1'b1) begin // resume flash access
                      ctrl.state  <= S_SYNC;
                    end
                end
                // --------------------------------------------------------------
                // synchronize SPI clock
                S_SYNC : begin
                    spi_csn_o <= ~ ctrl.csen; // enable flash
                    if (spi_clk_en_i == 1'b1) begin
                      if (cf_cpha_i == 1'b1) begin // clock phase shift
                        spi_clk_o <= ~ cf_cpol_i;
                      end
                      ctrl.state <= S_RTX_A;
                    end
                end
                // --------------------------------------------------------------
                // first half of bit transmission
                S_RTX_A : begin
                    if (spi_clk_en_i == 1'b1) begin
                      spi_clk_o    <= ~ (cf_cpha_i ^ cf_cpol_i);
                      ctrl.di_sync <= spi_dat_i;
                      ctrl.bitcnt  <= ctrl.bitcnt - 1'b1;
                      ctrl.state   <= S_RTX_B;
                    end
                end
                // --------------------------------------------------------------
                // second half of bit transmission
                S_RTX_B : begin
                    if (spi_clk_en_i == 1'b1) begin
                      ctrl.sreg <= {ctrl.sreg[$bits(ctrl.sreg)-2 : 0], ctrl.di_sync};
                      if (|ctrl.bitcnt == 1'b0) begin // all bits transferred?
                         spi_clk_o  <= cf_cpol_i;
                         ctrl.state <= S_DONE; // transmission done
                      end else begin
                         spi_clk_o  <= cf_cpha_i ^ cf_cpol_i;
                         ctrl.state <= S_RTX_A; // next bit
                      end
                    end
                end
                // --------------------------------------------------------------
                // transmission done
                S_DONE : begin
                     if (spi_clk_en_i == 1'b1) begin
                         ctrl.state <= S_WAIT;
                     end
                end
                // --------------------------------------------------------------
                // undefined
                default: begin
                    ctrl.state <= S_IDLE;
                end
            endcase
        end
    end : serial_engine

    /* serial unit busy */
    assign op_busy_o = ((ctrl.state === S_IDLE) || (ctrl.state == S_WAIT)) ? 1'b1 : 1'b0;

    /* serial data output */
    assign spi_dat_o = ctrl.sreg[$bits(ctrl.sreg)-1];

    /* RX data */
    assign op_rdata_o = ctrl.sreg[31:0];
    
endmodule