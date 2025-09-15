// ##################################################################################################
// # << CELLRV32 - Processor-Internal Instruction Cache >>                                          #
// # ********************************************************************************************** #
// # Direct mapped (ICACHE_NUM_SETS = 1) or 2-way set-associative (ICACHE_NUM_SETS = 2).            #
// # Least recently used replacement policy (if ICACHE_NUM_SETS > 1).                               #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_icache #(
    parameter int ICACHE_NUM_BLOCKS = 4,  // number of blocks (min 1), has to be a power of 2
    parameter int ICACHE_BLOCK_SIZE = 64, // block size in bytes (min 4), has to be a power of 2
    parameter int ICACHE_NUM_SETS   = 1   // associativity / number of sets (1=direct_mapped), has to be a power of 2
) (
    /* global control */
    input  logic        clk_i,   // global clock, rising edge
    input  logic        rstn_i,  // global reset, low-active, async
    input  logic        clear_i, // cache clear
    output logic        miss_o,  // cache miss
    /* host controller interface */
    input  logic [31:0] host_addr_i,  // bus access address
    output logic [31:0] host_rdata_o, // bus read data
    input  logic        host_re_i,    // read enable
    output logic        host_ack_o,   // bus transfer acknowledge
    output logic        host_err_o,   // bus transfer error
    /* peripheral bus interface */
    output logic        bus_cached_o, // set if cached (!) access in progress
    output logic [31:0] bus_addr_o,   // bus access address
    input  logic [31:0] bus_rdata_i,  // bus read data
    output logic        bus_re_o,     // read enable
    input  logic        bus_ack_i,    // bus transfer acknowledge
    input  logic        bus_err_i     // bus transfer error
);
    /* cache layout */
    localparam int cache_offset_size_c = $clog2(ICACHE_BLOCK_SIZE/4); // offset addresses full 32-bit words
    localparam int cache_index_size_c  = $clog2(ICACHE_NUM_BLOCKS);
    localparam int cache_tag_size_c    = 32 - (cache_offset_size_c + cache_index_size_c + 2); // 2 additonal bits for byte offset
    
    /* cache interface */
    typedef struct {
        logic clear;             // cache clear
        logic [31:0] host_addr;  // cpu access address
        logic [31:0] host_rdata; // cpu read data
        logic host_rstat;        // cpu read status
        logic hit;               // hit access
        logic ctrl_en;           // control access enable
        logic [31:0] ctrl_addr;  // control access address
        logic ctrl_we;           // control write enable
        logic [31:0] ctrl_wdata; // control write data
        logic ctrl_wstat;        // control write status
        logic ctrl_tag_we;       // control tag write enabled
        logic ctrl_valid_we;     // control valid flag set
        logic ctrl_invalid_we;   // control valid flag clear
    } cache_if_t;
    //
    cache_if_t cache;

    /* control engine */
    typedef enum  { S_IDLE, S_CACHE_CLEAR, S_CACHE_CHECK, 
                    S_CACHE_MISS, S_BUS_DOWNLOAD_REQ,
                    S_BUS_DOWNLOAD_GET, S_CACHE_RESYNC_0,
                    S_CACHE_RESYNC_1 } ctrl_engine_state_t;
    
    typedef struct {
        ctrl_engine_state_t state;     // current state
        ctrl_engine_state_t state_nxt; // next state
        logic [31:0] addr_reg;         // address register for block download
        logic [31:0] addr_reg_nxt;
        logic        re_buf;           // read request buffer
        logic        re_buf_nxt;
        logic        clear_buf;        // clear request buffer
        logic        clear_buf_nxt;
    } ctrl_t;
    // 
    ctrl_t ctrl;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* configuration */
    initial begin   
      assert (!(is_power_of_two_f(ICACHE_NUM_BLOCKS) == 1'b0)) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache number of blocks <ICACHE_NUM_BLOCKS> has to be a power of 2.");
      assert (!(is_power_of_two_f(ICACHE_BLOCK_SIZE) == 1'b0)) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache block size <ICACHE_BLOCK_SIZE> has to be a power of 2.");
      assert (!(is_power_of_two_f(ICACHE_NUM_SETS) == 1'b0)) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache associativity <ICACHE_NUM_SETS> has to be a power of 2.");
      assert (!(ICACHE_NUM_BLOCKS < 1)) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache number of blocks <ICACHE_NUM_BLOCKS> has to be >= 1.");
      assert (!(ICACHE_BLOCK_SIZE < 4)) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache block size <ICACHE_BLOCK_SIZE> has to be >= 4.");
      assert (!((ICACHE_NUM_SETS == 0) || (ICACHE_NUM_SETS > 2))) else
      $error("CELLRV32 PROCESSOR CONFIG ERROR! i-cache associativity <ICACHE_NUM_SETS> has to be 1 (direct-mapped) or 2 (2-way set-associative).");
    end

    // Control Engine FSM Sync -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i) begin : ctrl_engine_fsm_sync
        if (rstn_i == 1'b0) begin
            ctrl.state     <= S_CACHE_CLEAR; // to reset cache information memory, which does not have an explicit reset
            ctrl.re_buf    <= 1'b0;
            ctrl.clear_buf <= 1'b0;
            ctrl.addr_reg  <= '0;
        end else begin
            ctrl.state     <= ctrl.state_nxt;
            ctrl.re_buf    <= ctrl.re_buf_nxt;
            ctrl.clear_buf <= ctrl.clear_buf_nxt;
            ctrl.addr_reg  <= ctrl.addr_reg_nxt;
        end
    end : ctrl_engine_fsm_sync

    // Control Engine FSM Comb -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : ctrl_engine_fsm_comb
        /* control defaults */
        ctrl.state_nxt        = ctrl.state;
        ctrl.addr_reg_nxt     = ctrl.addr_reg;
        ctrl.re_buf_nxt       = ctrl.re_buf | host_re_i;
        ctrl.clear_buf_nxt    = ctrl.clear_buf | clear_i; // buffer clear request from CPU

        /* cache defaults */
        cache.clear           = 1'b0;
        cache.host_addr       = host_addr_i;
        cache.ctrl_en         = 1'b0;
        cache.ctrl_addr       = ctrl.addr_reg;
        cache.ctrl_we         = 1'b0;
        cache.ctrl_wdata      = bus_rdata_i;
        cache.ctrl_wstat      = bus_err_i;
        cache.ctrl_tag_we     = 1'b0;
        cache.ctrl_valid_we   = 1'b0;
        cache.ctrl_invalid_we = 1'b0;

        /* host interface defaults */
        host_ack_o            = 1'b0;
        host_err_o            = 1'b0;
        host_rdata_o          = cache.host_rdata;

        /* peripheral bus interface defaults */
        bus_addr_o            = ctrl.addr_reg;
        bus_re_o              = 1'b0;

        /* fsm */
        unique case (ctrl.state)
            // --------------------------------------------------------------
            // wait for host access request or cache control operation
            S_IDLE : begin
                if (ctrl.clear_buf == 1'b1) // cache control operation?
                  ctrl.state_nxt = S_CACHE_CLEAR;
                else if ((host_re_i == 1'b1) || (ctrl.re_buf == 1'b1)) begin // cache access
                  ctrl.re_buf_nxt = 1'b0;
                  ctrl.state_nxt  = S_CACHE_CHECK;
                end
            end
            // --------------------------------------------------------------
            // invalidate all cache entries
            S_CACHE_CLEAR : begin
                ctrl.clear_buf_nxt = 1'b0;
                cache.clear        = 1'b1;
                ctrl.state_nxt     = S_IDLE;
            end
            // --------------------------------------------------------------
            // finalize host access if cache hit
            S_CACHE_CHECK : begin
                if (cache.hit == 1'b1) begin
                    if (cache.host_rstat == 1'b1) begin
                        host_err_o = 1'b1;
                    end else begin
                        host_ack_o = 1'b1;
                    end
                    ctrl.state_nxt = S_IDLE;
                end else begin
                    // cache MISS
                    ctrl.state_nxt = S_CACHE_MISS;
                end
            end
            // --------------------------------------------------------------
            // compute block base address
            S_CACHE_MISS : begin
                 ctrl.addr_reg_nxt = host_addr_i;
                 ctrl.addr_reg_nxt[(2+cache_offset_size_c)-1 : 2] = '0; // block-aligned
                 ctrl.addr_reg_nxt[1:0] = 2'b00; // word-aligned
                 //
                 ctrl.state_nxt = S_BUS_DOWNLOAD_REQ;
            end
            // --------------------------------------------------------------
            // download new cache block: request new word
            S_BUS_DOWNLOAD_REQ : begin
                cache.ctrl_en  = 1'b1; // we are in cache control mode
                bus_re_o       = 1'b1; // request new read transfer
                ctrl.state_nxt = S_BUS_DOWNLOAD_GET;
            end
            // --------------------------------------------------------------
            // download new cache block: wait for bus response
            S_BUS_DOWNLOAD_GET : begin
                cache.ctrl_en = 1'b1; // we are in cache control mode
                //
                if ((bus_ack_i == 1'b1) || (bus_err_i == 1'b1)) begin // ACK or ERROR = write to cache and get next word
                    cache.ctrl_we = 1'b1; // write to cache
                    // block complete?
                    if ((&ctrl.addr_reg[(2+cache_offset_size_c)-1 : 2]) == 1'b1) begin
                      cache.ctrl_tag_we   = 1'b1; // current block is valid now
                      cache.ctrl_valid_we = 1'b1; // write tag of current address
                      ctrl.state_nxt      = S_CACHE_RESYNC_0;
                    end else begin // get next word
                      ctrl.addr_reg_nxt = ctrl.addr_reg + 4;
                      ctrl.state_nxt    = S_BUS_DOWNLOAD_REQ;
                    end
                end 
            end
            // --------------------------------------------------------------
            // re-sync host/cache access: cache read-latency
            S_CACHE_RESYNC_0 : begin
                ctrl.state_nxt = S_CACHE_RESYNC_1;
            end
            // --------------------------------------------------------------
            // re-sync host/cache access: finalize CPU request
            S_CACHE_RESYNC_1 : begin
                if (cache.host_rstat == 1'b1) begin // data word from cache marked as faulty?
                    host_err_o = 1'b1;
                end else begin
                    host_ack_o = 1'b1;
                end
                //
                ctrl.state_nxt = S_IDLE;
            end
            // --------------------------------------------------------------
            // undefined
            default: begin
                ctrl.state_nxt = S_IDLE;
            end
        endcase
    end : ctrl_engine_fsm_comb

    /* signal cache miss to CPU */
    assign miss_o = (ctrl.state == S_CACHE_MISS) ? 1'b1 : 1'b0;

    /* cache access in progress */
    assign bus_cached_o = ((ctrl.state == S_BUS_DOWNLOAD_REQ) || (ctrl.state == S_BUS_DOWNLOAD_GET)) ? 1'b1 : 1'b0;

    // Cache Memory ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    cellrv32_icache_memory #(
        .ICACHE_NUM_BLOCKS(ICACHE_NUM_BLOCKS), // number of blocks (min 1), has to be a power of 2
        .ICACHE_BLOCK_SIZE(ICACHE_BLOCK_SIZE), // block size in bytes (min 4), has to be a power of 2
        .ICACHE_NUM_SETS(ICACHE_NUM_SETS)      // associativity; 0=direct-mapped, 1=2-way set-associative
    ) cellrv32_icache_memory_inst (
        /* global control */
        .clk_i(clk_i),                       // global clock, rising edge
        .invalidate_i(cache.clear),          // invalidate whole cache
        /* host cache access (read-only) */
        .host_addr_i(cache.host_addr),       // access address
        .host_re_i(host_re_i),               // read enable
        .host_rdata_o(cache.host_rdata),     // read data
        .host_rstat_o(cache.host_rstat),     // read status
        /* access status (1 cycle delay to access) */
        .hit_o(cache.hit),            // hit access
        /* ctrl cache access (write-only) */
        .ctrl_en_i(cache.ctrl_en),             // control interface enable
        .ctrl_addr_i(cache.ctrl_addr),         // access address
        .ctrl_we_i(cache.ctrl_we),             // write enable (full-word)
        .ctrl_wdata_i(cache.ctrl_wdata),       // write data
        .ctrl_wstat_i(cache.ctrl_wstat),       // write status
        .ctrl_tag_we_i(cache.ctrl_tag_we),     // write tag to selected block
        .ctrl_valid_i(cache.ctrl_valid_we),    // make selected block valid
        .ctrl_invalid_i(cache.ctrl_invalid_we) // make selected block invalid
    );
    
endmodule