// ##################################################################################################
// # << cellTRNG V2 - A Tiny and Platform-Independent True Random Number Generator for any FPGA >>  #
// # ********************************************************************************************** #
// # This generator is based on entropy cells, which implement simple ring-oscillators. Each ring-  #
// # oscillator features a short and a long delay path that is dynamically switched. The cells are  #
// # cascaded so that the random data output of a cell controls the delay path of the next cell.    #
// #                                                                                                #
// # The random data output of the very last cell in the chain is synchronized and de-biased using  #
// # a simple 2-bit a von Neumann randomness extractor (converting edges into bits). Eight result   #
// # bits are samples to create one "raw" random data sample. If the post-processing module is      #
// # enabled (POST_PROC_EN), 8 byte samples will be combined into a single output byte to improve   #
// # whitening.                                                                                     #
// #                                                                                                #
// # The entropy cell architecture uses individually-controlled latches and inverters to create     #
// # the inverter chain in a platform-agnostic style that can be implemented for any FPGA without   #
// # requiring primitive instantiation or technology-specific attributes.                           #
// #                                                                                                #
// # See the neoTRNG's documentation for more information: https://github.com/stnolting/neoTRNG     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellTRNG #(
    parameter int NUM_CELLS     = 0,    // total number of ring-oscillator cells
    parameter int NUM_INV_START = 0,    // number of inverters in first cell (short path), has to be odd
    parameter int NUM_INV_INC   = 0,    // number of additional inverters in next cell (short path), has to be even
    parameter int NUM_INV_DELAY = 0,    // additional inverters to form cell's long path, has to be even
    parameter logic   POST_PROC_EN  = 1'b0 // implement post-processing for advanced whitening when true
) (
    input  logic       clk_i,    // global clock line
    input  logic       rstn_i,   // global reset line, low-active, async, optional
    input  logic       enable_i, // unit enable (high-active), reset unit when low
    output logic [7:0] data_o,   // random data byte output
    output logic       valid_o   // data_o is valid when set
);
    /* ring-oscillator array interconnect */
    typedef struct {
        logic [NUM_CELLS-1:0] en_in;
        logic [NUM_CELLS-1:0] en_out;
        logic [NUM_CELLS-1:0] out;
        logic [NUM_CELLS-1:0] in;
    } cell_array_t;
    //
    cell_array_t cell_array;

    /* raw synchronizer */
    logic [1:0] rnd_sync;

    /* von-Neumann de-biasing */
    typedef struct {
        logic [1:0] sreg;
        logic       state; // process de-biasing every second cycle
        logic       valid; // de-biased data
        logic       data;  // de-biased data valid
    } debiasing_t;
    //
    debiasing_t db;

    /* sample unit */
    typedef struct {
        logic       enable;
        logic       run;
        logic [7:0] sreg;  // data shift register
        logic       valid; // valid data sample (one byte)
        logic [2:0] cnt;   // bit counter
    } sample_t;
    //
    sample_t sample;

    /* post processing */
    typedef struct {
        logic [1:0] state;
        logic [3:0] cnt;   // byte counter
        logic [7:0] buff;   // post processing buffer
        logic       valid; // valid data type
    } post_t;
    //
    post_t post;

    /* data output */
    logic [7:0] data;
    logic       valid;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (1'b0) else $info("<< cellTRNG V2 - A Tiny and Platform-Independent True Random Number Generator for any FPGA >>");
        assert (POST_PROC_EN != 1'b1) else $info("cellTRNG note: Post-processing enabled.");
        //assert (IS_SIM != 1'b1) else $warning("cellTRNG WARNING: Simulation mode (PRNG!) enabled!");
        assert (NUM_CELLS >= 2) else $error("cellTRNG config ERROR: Total number of ring-oscillator cells <NUM_CELLS> has to be >= 2.");
        assert ((NUM_INV_START % 2) != 0) else $error("neoTRNG config ERROR: Number of inverters in first cell <NUM_INV_START> has to be odd.");
        assert ((NUM_INV_INC   % 2) == 0) else $error("neoTRNG config ERROR: Inverter increment for each next cell <NUM_INV_INC> has to be even.");
        assert ((NUM_INV_DELAY % 2) == 0) else $error("neoTRNG config ERROR: Inverter increment to form long path <NUM_INV_DELAY> has to be even.");
    end

    // Entropy Source ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        genvar i;
        for (i = 0; i < NUM_CELLS; ++i) begin : cellTRNG_cell_inst
            cellTRNG_cell #(
                .NUM_INV_S(NUM_INV_START + (i*NUM_INV_INC)), // number of inverters in short chain
                .NUM_INV_L(NUM_INV_START + (i*NUM_INV_INC) + NUM_INV_DELAY) // number of inverters in long chain
            ) cellTRNG_cell_inst (
                .clk_i(clk_i),
                .rstn_i(rstn_i),
                .select_i(cell_array.in[i]),
                .enable_i(cell_array.en_in[i]),
                .enable_o(cell_array.en_out[i]),
                .data_o(cell_array.out[i]) // SYNC data output
            );
        end : cellTRNG_cell_inst
    endgenerate

    /* enable chain */
    assign cell_array.en_in[0] = sample.enable; // start of chain
    assign cell_array.en_in[NUM_CELLS-1 : 1] = cell_array.en_out[NUM_CELLS-2 : 0]; // i+1 <= i
    
    /* feedback chain */
    always_comb begin : path_select
        if (rnd_sync[0] == 1'b0) begin // forward
            cell_array.in[0] = cell_array.out[NUM_CELLS-1];
            //
            for (int i = 0; i < NUM_CELLS -1; ++i) begin
                cell_array.in[i+1] = cell_array.out[i];
            end
        end else begin // backward
            cell_array.in[NUM_CELLS-1] = cell_array.out[0];
            //
            for (int i = NUM_CELLS-1; i > 0; --i) begin
                cell_array.in[i-1] = cell_array.out[i];
            end
        end
    end : path_select

    // Synchronizer ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : synchronizer
        if (rstn_i == 1'b0) begin
            rnd_sync <= '0;
        end else begin
            // no more metastability beyond this point
            rnd_sync[1] <= rnd_sync[0];
            rnd_sync[0] <= cell_array.out[NUM_CELLS-1];
        end
    end : synchronizer

    // John von Neumann Randomness Extractor (De-Biasing) ----------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : debiasing_sync
        if (rstn_i == 1'b0) begin
            db.sreg  <= '0;
            db.state <= 1'b0;
        end else begin
            db.sreg <= {db.sreg[0] ,rnd_sync[$bits(rnd_sync)-1]};
            // start operation when last cell is enabled and process in every second cycle --
            db.state <= (~ db.state) & cell_array.en_out[NUM_CELLS-1];
        end
    end : debiasing_sync

    /* edge detector */
    logic [2:0] tmp_v;
    //
    always_comb begin : debiasing_comb
        tmp_v = {db.state, db.sreg[1:0]}; // check groups of two non-overlapping bits from the input stream
        unique case (tmp_v)
            3'b101 : db.valid = 1'b1; // rising edge 
            3'b110 : db.valid = 1'b1; // falling edge
            default: begin
                     db.valid = 1'b0; // no valid data
            end
        endcase
    end : debiasing_comb

    /* edge data */
    assign db.data = db.sreg[0];

    // Sample Unit -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : sample_unit
        if (rstn_i == 1'b0) begin
            sample.enable <= 1'b0;
            sample.cnt    <= '0;
            sample.run    <= 1'b0;
            sample.sreg   <= '0;
            sample.valid  <= 1'b0;
        end else begin
            sample.enable <= enable_i;

            /* sample chunks of 8 bit */
            if (sample.enable == 1'b0) begin
              sample.cnt <= '0;
              sample.run <= 1'b0;
            end else if (db.valid == 1'b1) begin // valid random sample?
              sample.cnt <= sample.cnt + 1'b1;
              sample.run <= 1'b1;
            end

            /* sample shift register */
            if (db.valid == 1'b1) begin
              sample.sreg <= {sample.sreg[$bits(sample.sreg)-2 : 0], db.data};
            end

            /* sample valid? */
            if ((sample.cnt == 3'b000) && (sample.run == 1'b1) && (db.valid == 1'b1))
              sample.valid <= 1'b1;
            else
              sample.valid <= 1'b0;
        end
    end : sample_unit

    // Post Processing ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (POST_PROC_EN == 1'b1) begin : post_processing_enable
            // sync
            always_ff @(posedge clk_i or negedge rstn_i) begin : post_processing
                if (rstn_i == 1'b0) begin
                    post.state <= '0;
                    post.valid <= 1'b0;
                    post.cnt   <= '0;
                    post.buff  <= '0;
                end else begin
                    /* defaults */
                    post.state[1] <= sample.run;
                    post.valid    <= 1'b0;

                    /* FSM */
                    unique case (post.state)
                        // start new post-processing
                        2'b10 : begin
                            post.cnt      <= '0;
                            post.buff     <= '0;
                            post.state[0] <= 1'b1;
                        end
                        // combine eight samples
                        2'b11 : begin
                            if (sample.valid == 1'b1) begin
                              post.buff <= {post.buff[0], post.buff[7:1]} + sample.sreg; // combine function
                              post.cnt  <= post.cnt + 1'b1;
                            end
                            //
                            if (post.cnt[3] == 1'b1) begin
                              post.valid    <= 1'b1;
                              post.state[0] <= 1'b0;
                            end
                        end
                        // reset/disabled
                        default: begin
                            post.state[0] <= 1'b0;
                        end
                    endcase
                end
            end : post_processing

            assign data  = post.buff;
            assign valid = post.valid;

        end : post_processing_enable
    endgenerate

    generate
        if (POST_PROC_EN == 1'b0) begin : post_processing_disable
            assign data  = sample.sreg;
            assign valid = sample.valid;
        end : post_processing_disable
    endgenerate

    /* data output */
    assign data_o  = data;
    assign valid_o = valid;
endmodule