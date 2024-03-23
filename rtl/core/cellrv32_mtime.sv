// ##################################################################################################
// # << CELLRV32 - Machine System Timer (MTIME) >>                                                  #
// # ********************************************************************************************** #
// # Compatible to RISC-V spec's 64-bit MACHINE system timer including "mtime[h]" & "mtimecmp[h]".  #
// # Note: The 64-bit counter and compare systems are de-coupled into two 32-bit systems.           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_mtime (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    /* interrupt */
    output logic        irq_o   // interrupt request
);
    /* IO space: module base address */
    localparam hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam lo_abb_c = index_size_f(mtime_size_c); // low address boundary bit

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // module access enable
    logic        rden;   // read enable

    /* time write access buffer */
    logic mtime_lo_we;
    logic mtime_hi_we;

    /* accessible regs */
    logic [31:0] mtimecmp_lo;
    logic [31:0] mtimecmp_hi;
    logic [31:0] mtime_lo;
    logic [32:0] mtime_lo_nxt;
    logic [00:0] mtime_lo_ovfl;
    logic [31:0] mtime_hi;

    /* comparators */
    logic cmp_lo_ge;
    logic cmp_lo_ge_ff;
    logic cmp_hi_eq;
    logic cmp_hi_gt;

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == mtime_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {mtime_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            mtimecmp_lo   <= '0;
            mtimecmp_hi   <= '0;
            mtime_lo_we   <= 1'b0;
            mtime_hi_we   <= 1'b0;
            mtime_lo      <= '0;
            mtime_lo_ovfl <= '0;
            mtime_hi      <= '0;
        end else begin
            /* mtimecmp */
            if (wren == 1'b1) begin
              if (addr == mtime_cmp_lo_addr_c) 
                mtimecmp_lo <= data_i;
              //
              if (addr == mtime_cmp_hi_addr_c) 
                mtimecmp_hi <= data_i;
            end

            /* mtime write access buffer */
            mtime_lo_we <= 1'b0;
            if ((wren == 1'b1) && (addr == mtime_time_lo_addr_c)) begin
                mtime_lo_we <= 1'b1;
            end
            //
            mtime_hi_we <= 1'b0;
            if ((wren == 1'b1) && (addr == mtime_time_hi_addr_c)) begin
                mtime_hi_we <= 1'b1;
            end

            /* mtime low */
            if (mtime_lo_we == 1'b1) // write access
              mtime_lo <= data_i;
            else // auto increment
              mtime_lo <= mtime_lo_nxt[31:0];
            mtime_lo_ovfl[0] <= mtime_lo_nxt[32]; // overflow (carry)

            /* mtime high */
            if (mtime_hi_we == 1'b1) // write access
              mtime_hi <= data_i;
            else // auto increment (if mtime.low overflows)
              mtime_hi <= mtime_hi + mtime_lo_ovfl;
        end
    end : write_access

    /* mtime.time_LO increment */
    assign mtime_lo_nxt = {1'b0, mtime_lo} + 1;

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus handshake
        data_o <= '0; // default
        //
        if (rden == 1'b1) begin
            unique case (addr[3:2])
                2'b00 : data_o <= mtime_lo;
                2'b01 : data_o <= mtime_hi;
                2'b10 : data_o <= mtimecmp_lo;
                default: begin
                        data_o <= mtimecmp_hi;
                end
            endcase
        end
    end : read_access

    // Comparator --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : cmp_sync
        cmp_lo_ge_ff <= cmp_lo_ge; // there is one cycle delay between low (earlier) and high (later) word
        irq_o        <= cmp_hi_gt | (cmp_hi_eq & cmp_lo_ge_ff);
    end : cmp_sync

    /* sub-word comparators */
    assign cmp_lo_ge = (mtime_lo >= mtimecmp_lo) ? 1'b1 : 1'b0; // low-word: greater than or equal
    assign cmp_hi_eq = (mtime_hi == mtimecmp_hi) ? 1'b1 : 1'b0; // high-word: equal
    assign cmp_hi_gt = (mtime_hi >  mtimecmp_hi) ? 1'b1 : 1'b0; // high-word: greater than

endmodule