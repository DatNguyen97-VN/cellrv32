// ##################################################################################################
// # << CELLRV32 - Cache Memory >>                                                                  #
// # ********************************************************************************************** #
// # Direct mapped (ICACHE_NUM_SETS = 1) or 2-way set-associative (ICACHE_NUM_SETS = 2).            #
// # Least recently used replacement policy (if ICACHE_NUM_SETS > 1).                               #
// # Read-only for host, write-only for control. All output signals have one cycle latency.         #
// #                                                                                                #
// # Cache sets are mapped to individual memory components - no multi-dimensional memory arrays     #
// # are used as some synthesis tools have problems to map these to actual BRAM primitives.         #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_icache_memory #(
    parameter int ICACHE_NUM_BLOCKS = 4,  // number of blocks (min 1), has to be a power of 2
    parameter int ICACHE_BLOCK_SIZE = 16, // block size in bytes (min 4), has to be a power of 2
    parameter int ICACHE_NUM_SETS   = 1   // associativity; 1=direct-mapped, 2=2-way set-associative
) (
    /* global control */
    input  logic        clk_i,         // global clock, rising edge
    input  logic        invalidate_i,  // invalidate whole cache
    /* host cache access (read-only) */
    input  logic [31:0] host_addr_i,   // access address
    input  logic        host_re_i,     // read enable
    output logic [31:0] host_rdata_o,  // read data
    output logic        host_rstat_o,  // read status
    /* access status (1 cycle delay to access) */
    output logic        hit_o,         // hit access
    /* ctrl cache access (write-only) */
    input  logic        ctrl_en_i,     // control interface enable
    input  logic [31:0] ctrl_addr_i,   // access address
    input  logic        ctrl_we_i,     // write enable (full-word)
    input  logic [31:0] ctrl_wdata_i,  // write data
    input  logic        ctrl_wstat_i,  // write status
    input  logic        ctrl_tag_we_i, // write tag to selected block
    input  logic        ctrl_valid_i,  // make selected block valid
    input  logic        ctrl_invalid_i // make selected block invalid
);
    /* cache layout */
    localparam int cache_offset_size_c = index_size_f(ICACHE_BLOCK_SIZE/4); // offset addresses full 32-bit words
    localparam int cache_index_size_c  = index_size_f(ICACHE_NUM_BLOCKS);
    localparam int cache_tag_size_c    = 32 - (cache_offset_size_c + cache_index_size_c + 2); // 2 additional bits for byte offset
    localparam int cache_entries_c     = ICACHE_NUM_BLOCKS * (ICACHE_BLOCK_SIZE/4); // number of 32-bit entries (per set)

    /* status flag memory */
    logic [ICACHE_NUM_BLOCKS-1:0] valid_flag_s0;
    logic [ICACHE_NUM_BLOCKS-1:0] valid_flag_s1;
    logic [1:0]                   valid; // valid flag read data

    /* tag memory */
    typedef logic [cache_tag_size_c-1:0] tag_mem_t [0:ICACHE_NUM_BLOCKS-1];
    tag_mem_t tag_mem_s0;
    tag_mem_t tag_mem_s1;
    typedef logic [cache_tag_size_c-1:0] tag_rd_t [0:1];
    tag_rd_t tag; // tag read data

    /* access status */
    logic [1:0] hit;

    /* access address decomposition */
    typedef struct {
        logic [cache_tag_size_c-1:0]    tag;
        logic [cache_index_size_c-1:0]  index;
        logic [cache_offset_size_c-1:0] offset;
    } acc_addr_t;
    //
    acc_addr_t host_acc_addr, ctrl_acc_addr;

    /* cache data memory (32-bit data + 1-bit status) */
    typedef logic[31+1:0] cache_mem_t [0:cache_entries_c-1];
    //
    cache_mem_t cache_data_memory_s0; // set 0
    cache_mem_t cache_data_memory_s1; // set 1

    /* cache data memory access */
    typedef logic[31+1:0] cache_rdata_t [0:1];
    //
    cache_rdata_t cache_rd;
    logic [cache_index_size_c-1:0] cache_index;
    logic [cache_offset_size_c-1:0] cache_offset;
    logic [cache_index_size_c+cache_offset_size_c-1:0] cache_addr; // index & offset
    logic cache_we; // write enable (full-word)
    logic set_select;

    /* access history */
    typedef struct {
        logic re_ff;
        logic [ICACHE_NUM_BLOCKS-1:0] last_used_set;
        logic to_be_replaced;
    } history_t;
    //
    history_t history;

    // Access Address Decomposition --------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign host_acc_addr.tag    = host_addr_i[31 : 31-(cache_tag_size_c-1)];
    assign host_acc_addr.index  = host_addr_i[31-cache_tag_size_c : 2+cache_offset_size_c];
    assign host_acc_addr.offset = host_addr_i[2+(cache_offset_size_c-1) : 2]; // discard byte offset

    assign ctrl_acc_addr.tag    = ctrl_addr_i[31 : 31-(cache_tag_size_c-1)];
    assign ctrl_acc_addr.index  = ctrl_addr_i[31-cache_tag_size_c : 2+cache_offset_size_c];
    assign ctrl_acc_addr.offset = ctrl_addr_i[2+(cache_offset_size_c-1) : 2]; // discard byte offset

    // Cache Access History ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : access_history
        history.re_ff <= host_re_i;
        // invalidate whole cache
        if (invalidate_i == 1'b1) begin
            history.last_used_set <= '1;
        end else if ((history.re_ff == 1'b1) && ((|hit) == 1'b1) && (ctrl_en_i == 1'b0)) begin
            history.last_used_set[cache_index] <= ~hit[0];
        end
        //
        history.to_be_replaced <= history.last_used_set[cache_index];
    end : access_history

    /* which set is going to be replaced? -> opposite of last used set = least recently used set */
    assign set_select = (ICACHE_NUM_SETS == 1) ? 1'b0 : (~history.to_be_replaced);
    
    // Status flag memory ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : status_memory
        /* write access */
        if (invalidate_i == 1'b1) begin // invalidate whole cache
            valid_flag_s0 <= '0;
            valid_flag_s1 <= '0;
        end else if (ctrl_en_i == 1'b1) begin
            if (ctrl_invalid_i == 1'b1) begin // make current block invalid
                if (set_select == 1'b0)
                  valid_flag_s0[cache_index] <= 1'b0;
                else
                  valid_flag_s1[cache_index] <= 1'b0;
            end else if (ctrl_valid_i == 1'b1) begin // make current block valid
                if (set_select == 1'b0) 
                  valid_flag_s0[cache_index] <= 1'b1;
                else
                  valid_flag_s1[cache_index] <= 1'b1;
            end
        end
        /* read access (sync) */
        valid[0] <= valid_flag_s0[cache_index];
        valid[1] <= valid_flag_s1[cache_index];
    end : status_memory

    // Tag memory --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : tag_memory
        if ((ctrl_en_i == 1'b1) && (ctrl_tag_we_i == 1'b1)) begin // write access
           if (set_select == 1'b0)
             tag_mem_s0[cache_index] <= ctrl_acc_addr.tag;
           else
             tag_mem_s1[cache_index] <= ctrl_acc_addr.tag;
        end
        tag[0] <= tag_mem_s0[cache_index];
        tag[1] <= tag_mem_s1[cache_index];
    end : tag_memory

    /* comparator */
    always_comb begin : comparator
        hit = '0;
        // loop i
        for (int i = 0; i < ICACHE_NUM_SETS; ++i) begin
            if ((host_acc_addr.tag == tag[i]) && (valid[i] == 1'b1)) begin
                hit[i] = 1'b1;
            end
        end
    end : comparator

    /* global hit */
    assign hit_o = (|hit == 1'b1) ? 1'b1 : 1'b0;

    // Cache Data Memory -------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : cache_mem_access
        if (cache_we == 1'b1) begin // write access from control (full-word)
          if ((set_select == 1'b0) || (ICACHE_NUM_SETS == 1))
            cache_data_memory_s0[cache_addr] <= {ctrl_wstat_i, ctrl_wdata_i};
          else
            cache_data_memory_s1[cache_addr] <= {ctrl_wstat_i, ctrl_wdata_i};
        end
        /* read access from host (full-word) */
        cache_rd[0] <= cache_data_memory_s0[cache_addr];
        cache_rd[1] <= cache_data_memory_s1[cache_addr];
    end : cache_mem_access

    /* data output */
    assign host_rdata_o = ((hit[0] == 1'b1) || (ICACHE_NUM_SETS == 1)) ? cache_rd[0][31:0] : cache_rd[1][31:0];
    assign host_rstat_o = ((hit[0] == 1'b1) || (ICACHE_NUM_SETS == 1)) ? cache_rd[0][32]   : cache_rd[1][32];

    /* cache block ram access address */
    assign cache_addr = {cache_index, cache_offset};

    /* cache access select */
    assign cache_index  = (ctrl_en_i == 1'b0) ? host_acc_addr.index  : ctrl_acc_addr.index;
    assign cache_offset = (ctrl_en_i == 1'b0) ? host_acc_addr.offset : ctrl_acc_addr.offset;
    assign cache_we     = (ctrl_en_i == 1'b0) ? 1'b0                 : ctrl_we_i;

endmodule