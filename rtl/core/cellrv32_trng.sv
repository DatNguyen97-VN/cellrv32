// ##################################################################################################
// # << CELLRV32 - True Random Number Generator (TRNG) >>                                           #
// # ********************************************************************************************** #
// # This processor module instantiates the "neoTRNG" true random number generator. An optional     #
// # "random pool" FIFO can be configured using the TRNG_FIFO generic.                              #
// # See the neoTRNG's documentation for more information: https://github.com/stnolting/neoTRNG     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_trng #(
    parameter int IO_TRNG_FIFO = 1 // RND fifo depth, has to be a power of two, min 1
) (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o   // transfer acknowledge
);
    // neoTRNG Configuration -------------------------------------------------------------------------------------------
    localparam int num_cells_c     = 3; // total number of ring-oscillator cells
    localparam int num_inv_start_c = 3; // number of inverters in first cell (short path), has to be odd
    localparam int num_inv_inc_c   = 2; // number of additional inverters in next cell (short path), has to be even
    localparam int num_inv_delay_c = 2; // additional inverters to form cell's long path, has to be even
    // -----------------------------------------------------------------------------------------------------------------

    /* use simulation mode (PRNG!!!) */
    localparam logic sim_mode_c = is_simulation_c;

    /* control register bits */
    localparam int ctrl_data_lsb_c =  0; // r/-: Random data byte LSB
    localparam int ctrl_data_msb_c =  7; // r/-: Random data byte MSB
    //
    localparam int ctrl_fifo_clr_c = 28; // -/w: Clear data FIFO (auto clears)
    localparam int ctrl_sim_mode_c = 29; // r/-: TRNG implemented in PRNG simulation mode
    localparam int ctrl_en_c       = 30; // r/w: TRNG enable
    localparam int ctrl_valid_c    = 31; // r/-: Output data valid

    /* IO space: module base address */
    localparam hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam lo_abb_c = index_size_f(trng_size_c); // low address boundary bit

    /* access control */
    logic acc_en; // module access enable
    logic wren;   // full word write enable
    logic rden;   // read enable

    /* arbiter */
    logic enable;
    logic fifo_clr;

    /* data FIFO */
    typedef struct {
        logic       we;    // write enable
        logic       re;    // read enable
        logic       clear; // sync reset, high-active
        logic [7:0] wdata; // write data
        logic [7:0] rdata; // read data
        logic       avail; // data available?
    } fifo_t;
    //
    fifo_t fifo;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (IO_TRNG_FIFO >= 1) else $error("NEORV32 PROCESSOR CONFIG ERROR: TRNG FIFO size <IO_TRNG_FIFO> has to be >= 1.");
        assert (is_power_of_two_f(IO_TRNG_FIFO) != 1'b0) else $error("NEORV32 PROCESSOR CONFIG ERROR: TRNG FIFO size <IO_TRNG_FIFO> has to be a power of two.");
        assert (sim_mode_c != 1'b1) else $warning("NEORV32 PROCESSOR CONFIG WARNING: TRNG uses SIMULATION mode!");
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == trng_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : write_access
        if (rstn_i == 1'b0) begin
            enable   <= 1'b0;
            fifo_clr <= 1'b0;
        end else begin
            fifo_clr <= 1'b0; // default
            //
            if (wren == 1'b1) begin
                enable   <= data_i[ctrl_en_c];
                fifo_clr <= data_i[ctrl_fifo_clr_c];
            end
        end
    end : write_access

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= wren | rden; // host bus acknowledge
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            data_o[ctrl_data_msb_c : ctrl_data_lsb_c] <= fifo.rdata;
            //
            data_o[ctrl_sim_mode_c] <= sim_mode_c;
            data_o[ctrl_en_c]       <= enable;
            data_o[ctrl_valid_c]    <= fifo.avail;
        end
    end : read_access

    // neoTRNG True Random Number Generator ------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellTRNG #(
        .NUM_CELLS(num_cells_c),
        .NUM_INV_START(num_inv_start_c),
        .NUM_INV_INC(num_inv_inc_c),
        .NUM_INV_DELAY(num_inv_delay_c),
        .POST_PROC_EN(1'b1) // post-processing enabled to improve "random quality"
    ) cellTRNG_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .enable_i(enable),
        .data_o(fifo.wdata),
        .valid_o(fifo.we)
    );

    // Data FIFO ("Random Pool") -----------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_fifo #(
        .FIFO_DEPTH(IO_TRNG_FIFO), // number of fifo entries; has to be a power of two; min 1
        .FIFO_WIDTH(8),            // size of data elements in fifo
        .FIFO_RSYNC(1'b0),        // async read
        .FIFO_SAFE(1'b1),         // safe access
        .FIFO_GATE(1'b1)         // make sure the same RND data byte cannot be read twice
    ) rnd_pool_fifo_inst (
        /* control */
        .clk_i(clk_i),      // clock, rising edge
        .rstn_i(rstn_i),     // async reset, low-active
        .clear_i(fifo.clear), // sync reset, high-active
        .half_o( ),
        /* write port */
        .wdata_i(fifo.wdata), // write data
        .we_i(fifo.we),    // write enable
        .free_o(  ),       // at least one entry is free when set
        /* read port */
        .re_i(fifo.re),    // read enable
        .rdata_o(fifo.rdata), // read data
        .avail_o(fifo.avail)  // data available when set
    );

    /* fifo reset */
    assign fifo.clear = ((enable == 1'b0) || (fifo_clr == 1'b1)) ? 1'b1 : 1'b0;

    /* read access */
    assign fifo.re = (rden == 1'b1) ? 1'b1 : 1'b0;
endmodule