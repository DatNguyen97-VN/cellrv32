// ##################################################################################################
// # << CELLRV32 - Generic Single-Clock FIFO >>                                                     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_fifo #(
    parameter int FIFO_DEPTH = 2,    // number of fifo entries; has to be a power of two; min 1
    parameter int FIFO_WIDTH = 18,   // size of data elements in fifo
    parameter logic   FIFO_RSYNC = 1'b0, // false = async read; true = sync read
    parameter logic   FIFO_SAFE  = 1'b0, // true = allow read/write only if entry available
    parameter logic   FIFO_GATE  = 1'b0  // true = use output gate (set to zero if no valid data available)
) (
    /* control */
    input  logic clk_i,   // clock, rising edge
    input  logic rstn_i,  // async reset, low-active
    input  logic clear_i, // sync reset, high-active
    output logic half_o,  // FIFO is at least half full
    /* write port */
    input  logic [FIFO_WIDTH-1:0] wdata_i,  // write data
    input  logic                  we_i,     // write enable
    output logic                  free_o,   // at least one entry is free when set
    /* read port */
    input  logic                  re_i,     // read enable
    output logic [FIFO_WIDTH-1:0] rdata_o,  // read data
    output logic                  avail_o   // data available when set
);
    /* FIFO */
    typedef logic [FIFO_DEPTH-1:0][FIFO_WIDTH-1:0] fifo_data_t;
    //
    typedef struct {
        logic we; // write enable
        logic re; // read enable
        logic [index_size_f(FIFO_DEPTH):0] w_pnt; // write pointer
        logic [index_size_f(FIFO_DEPTH):0] r_pnt; // read pointer
        fifo_data_t data; // fifo memory
        logic [FIFO_WIDTH-1:0] buffer; // if single-entry FIFO
        logic match;
        logic empty;
        logic full;
        logic free;
        logic avail;
    } fifo_t;
    //
    fifo_t fifo;

    /* misc */
    logic [FIFO_WIDTH-1:0] rdata;
    logic [index_size_f(FIFO_DEPTH):0] level_diff;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (!(FIFO_DEPTH == 0)) 
        else   $error("CELLRV32 CONFIG ERROR: FIFO depth has to be > 0.");
        //
        assert (!(is_power_of_two_f(FIFO_DEPTH) == 1'b0))
        else $error("CELLRV32 CONFIG ERROR: FIFO depth has to be a power of two.");
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign fifo.re = (FIFO_SAFE == 0) ? re_i : (re_i & fifo.avail); // SAFE = read only if data available
    assign fifo.we = (FIFO_SAFE == 0) ? we_i : (we_i & fifo.free); // SAFE = write only if space left
    
    // FIFO Pointers -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : fifo_pointers
        if (rstn_i == 1'b0) begin
            fifo.w_pnt <= '0;
            fifo.r_pnt <= '0;
        end else begin
            /* write port */
            if (clear_i == 1'b1) begin
                fifo.w_pnt <= '0;
            end else if (fifo.we == 1'b1) begin
                fifo.w_pnt <= fifo.w_pnt + 1'b1;
            end
            /* read port */
            if (clear_i == 1'b1) begin
                fifo.r_pnt <= '0;
            end else if (fifo.re == 1'b1) begin
                fifo.r_pnt <= fifo.r_pnt + 1'b1;
            end
        end
    end : fifo_pointers

    // FIFO Status -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // check_large
    generate
        if (FIFO_DEPTH > 1) begin : check_large
            assign fifo.match = (fifo.r_pnt[$bits(fifo.r_pnt)-2 : 0] == fifo.w_pnt[$bits(fifo.w_pnt)-2 : 0]) ? 1'b1 : 1'b0;
            assign fifo.full  = ((fifo.r_pnt[$bits(fifo.r_pnt)-1] != fifo.w_pnt[$bits(fifo.w_pnt)-1]) && (fifo.match == 1'b1)) ? 1'b1 : 1'b0;
            assign fifo.empty = ((fifo.r_pnt[$bits(fifo.r_pnt)-1]  == fifo.w_pnt[$bits(fifo.w_pnt)-1]) && (fifo.match == 1'b1)) ? 1'b1 : 1'b0;
        end : check_large
    endgenerate
    
    // check_small
    generate
        if (FIFO_DEPTH <= 1) begin : check_small
            assign fifo.match = (fifo.r_pnt[0] == fifo.w_pnt[0]) ? 1'b1 : 1'b0;
            assign fifo.full  = ~fifo.match;
            assign fifo.empty =  fifo.match;
        end : check_small
    endgenerate
    //
    assign fifo.free  = ~fifo.full;
    assign fifo.avail = ~fifo.empty;

    assign free_o  = fifo.free;
    assign avail_o = fifo.avail;

    // fifo_half_level_simple
    generate
        if (FIFO_DEPTH == 1) begin : fifo_half_level_simple
            assign half_o = fifo.full;
        end : fifo_half_level_simple
    endgenerate

    // fifo_half_level_complex
    generate
        if (FIFO_DEPTH > 1) begin : fifo_half_level_complex
             assign level_diff = fifo.w_pnt - fifo.r_pnt;
             assign half_o     = level_diff[$bits(level_diff)-2] | fifo.full;
        end : fifo_half_level_complex
    endgenerate

    // FIFO Memory - Write -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* "real" FIFO memory (several entries) */
    generate
        if (FIFO_DEPTH > 1) begin : fifo_memory
            always_ff @( posedge clk_i ) begin : fifo_write
                if (fifo.we == 1'b1) begin
                    fifo.data[fifo.w_pnt[$bits(fifo.w_pnt)-2 : 0]] <= wdata_i;
                end
            end : fifo_write
            // unused
            assign fifo.buffer = '0;
        end : fifo_memory
    endgenerate

    /* simple register/buffer (single entry) */
    generate
        if (FIFO_DEPTH == 1) begin : fifo_buffer
            always_ff @( posedge clk_i ) begin : fifo_write
                if (fifo.we == 1'b1) begin
                    fifo.buffer <= wdata_i;
                end
            end : fifo_write
            // unused
            assign fifo.data = '0;
        end : fifo_buffer
    endgenerate

    // FIFO Memory - Read ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* "asynchronous" read */
    generate
        if (FIFO_RSYNC == 1'b0) begin : fifo_read_async
            always_comb begin : fifo_read
                if (FIFO_DEPTH == 1) begin
                    rdata = fifo.buffer;
                end else begin
                    rdata = fifo.data[fifo.r_pnt[$bits(fifo.r_pnt)-2 : 0]];
                end
            end : fifo_read
        end : fifo_read_async
    endgenerate

    /* synchronous read */
    generate
        if (FIFO_RSYNC == 1'b1) begin : fifo_read_sync
            always_ff @( posedge clk_i ) begin : fifo_read
                if (FIFO_DEPTH == 1) begin
                    rdata = fifo.buffer;
                end else begin
                    rdata = fifo.data[fifo.r_pnt[$bits(fifo.r_pnt)-2 : 0]];
                end
            end : fifo_read
        end : fifo_read_sync
    endgenerate

    // Output Gate -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // Since the FIFO memory (block RAM) does not have a reset, this option can be used to
    // ensure the output data is always *defined* (by setting the output to all-zero if
    // not valid data is available).
    assign rdata_o = ((FIFO_GATE == 0) || (fifo.avail == 1'b1)) ? rdata : '0;
endmodule
