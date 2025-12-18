// ##################################################################################################
// # << CELLRV32 - Processor-internal data memory (DMEM) >>                                         #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_dmem #(
    parameter logic [31:0] DMEM_BASE = 32'h00000000, // memory base address
    parameter int          DMEM_SIZE = 0             // processor-internal instruction memory size in bytes
) (
    input  logic        clk_i,  // global clock line
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [03:0] ben_i,  // byte write enable
    input  logic [31:0] addr_i, // address
    input  logic [31:0] data_i, // data in
    input  logic [03:0] ticket_i, // request ticket
    output logic [31:0] data_o, // data out
    output logic [03:0] ticket_o, // response ticket
    output logic        ack_o,  // transfer acknowledge
    output logic        err_o   // transfer error
);
    /* IO space: module base address */
    localparam int hi_abb_c = 31; // high address boundary bit
    localparam int lo_abb_c = $clog2(DMEM_SIZE); // low address boundary bit

    /* local signals */
    logic                             acc_en;
    logic [31:0]                      rdata;
    logic                             rden;
    logic [$clog2(DMEM_SIZE/4)-1 : 0] addr;

    /* -------------------------------------------------------------------------------------------------------------- */
    /* The memory (RAM) is built from 4 individual byte-wide memories b0..b3, since some synthesis tools have         */
    /* problems with 32-bit memories that provide dedicated byte-enable signals AND/OR with multi-dimensional arrays. */
    /* -------------------------------------------------------------------------------------------------------------- */

    /* RAM - not initialized at all */
    logic [7:0] mem_ram_b0 [0 : DMEM_SIZE/4-1];
    logic [7:0] mem_ram_b1 [0 : DMEM_SIZE/4-1];
    logic [7:0] mem_ram_b2 [0 : DMEM_SIZE/4-1];
    logic [7:0] mem_ram_b3 [0 : DMEM_SIZE/4-1];

    /* read data */
    logic [7:0] mem_ram_b0_rd, mem_ram_b1_rd, mem_ram_b2_rd, mem_ram_b3_rd;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert ("CELLRV32 PROCESSOR CONFIG NOTE: Using DEFAULT platform-agnostic DMEM.");
        assert (1'b0) else $info("CELLRV32 PROCESSOR CONFIG NOTE: Implementing processor-internal DMEM (RAM, %0d bytes)", DMEM_SIZE);
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == DMEM_BASE[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = addr_i[$clog2(DMEM_SIZE/4)+1 : 2]; // word aligned

    // Memory Access -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : mem_access
        // this RAM style should not require "no_rw_check" attributes as the read-after-write behavior
        // is intended to be defined implicitly via the if-WRITE-else-READ construct
        if (acc_en == 1'b1) begin // reduce switching activity when not accessed
          // byte 0
          if ((wren_i == 1'b1) && (ben_i[0] == 1'b1))
            mem_ram_b0[addr] <= data_i[07:00];
          else
            mem_ram_b0_rd <= mem_ram_b0[addr];
          // byte 1
          if ((wren_i == 1'b1) && (ben_i[1] == 1'b1))
            mem_ram_b1[addr] <= data_i[15:08];
          else
            mem_ram_b1_rd <= mem_ram_b1[addr];
          // byte 2
          if ((wren_i == 1'b1) && (ben_i[2] == 1'b1))
            mem_ram_b2[addr] <= data_i[23:16];
          else
            mem_ram_b2_rd <= mem_ram_b2[addr];
          // byte 3
          if ((wren_i == 1'b1) && (ben_i[3] == 1'b1))
            mem_ram_b3[addr] <= data_i[31:24];
          else
            mem_ram_b3_rd <= mem_ram_b3[addr];
        end
    end : mem_access

    // Bus Feedback ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : bus_feedback
        rden  <= acc_en & rden_i;
        ticket_o <= acc_en ? ticket_i : 4'b0000;
        ack_o <= acc_en &  (rden_i | wren_i);
        err_o <= acc_en & ~(rden_i | wren_i); // error on write or read access within acc_en not simultaneously
    end : bus_feedback

    /* pack */
    assign rdata = {mem_ram_b3_rd, mem_ram_b2_rd, mem_ram_b1_rd, mem_ram_b0_rd};

    /* output gate */
    assign data_o = rden ? rdata : '0;

endmodule