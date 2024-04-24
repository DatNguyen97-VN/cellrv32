// ##################################################################################################
// # << CELLRV32 - Processor-internal instruction memory (IMEM) >>                                  #
// # ********************************************************************************************** #
// # This memory optionally includes the in-place executable image of the application. See the      #
// # processor's documentary to get more information.                                               #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

// this package is generated by the image generator
import cellrv32_application_image::*;

module cellrv32_imem #(
    parameter logic[31:0] IMEM_BASE    = 32'h00000000, // memory base address
    parameter int         IMEM_SIZE    = 0,            // processor-internal instruction memory size in bytes
    parameter logic       IMEM_AS_IROM = 1'b0          // implement IMEM as pre-initialized read-only memory?
) (
    input  logic         clk_i,  // global clock line
    input  logic         rden_i, // read enable
    input  logic         wren_i, // write enable
    input  logic [03:0]  ben_i,  // byte write enable
    input  logic [31:0]  addr_i, // address
    input  logic [31:0]  data_i, // data in
    output logic [31:0]  data_o, // data out
    output logic         ack_o,  // transfer acknowledge
    output logic         err_o   // transfer error
);
    /* IO space: module base address */
    localparam int hi_abb_c = 31; // high address boundary bit
    localparam int lo_abb_c = index_size_f(IMEM_SIZE); // low address boundary bit

    /* local signals */
    logic        acc_en;
    logic [31:0] rdata;
    logic        rden;
    logic [index_size_f(IMEM_SIZE/4)-1 : 0] addr;

    /* --------------------------- */
    /* IMEM as pre-initialized ROM */
    /* --------------------------- */

    /* application (image) size in bytes */
    const int imem_app_size_c = ($size(application_init_image))*4;

    /* ROM - initialized with executable code */
    const logic [31:0] mem_rom [32*1024] = mem32_init_app_f(application_init_image, IMEM_SIZE/4);

    /* read data */
    logic [31:0] mem_rom_rd;

    /* -------------------------------------------------------------------------------------------------------------- */
    /* The memory (RAM) is built from 4 individual byte-wide memories b0..b3, since some synthesis tools have         */
    /* problems with 32-bit memories that provide dedicated byte-enable signals AND/OR with multi-dimensional arrays. */
    /* -------------------------------------------------------------------------------------------------------------- */

    /* RAM - not initialized at all */
    logic [7:0] mem_ram_b0 [0 : IMEM_SIZE/4-1];
    logic [7:0] mem_ram_b1 [0 : IMEM_SIZE/4-1];
    logic [7:0] mem_ram_b2 [0 : IMEM_SIZE/4-1];
    logic [7:0] mem_ram_b3 [0 : IMEM_SIZE/4-1];

    /* read data */
    logic [7:0] mem_b0_rd, mem_b1_rd, mem_b2_rd, mem_b3_rd;
    
    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert ("CELLRV32 PROCESSOR CONFIG NOTE: Using DEFAULT platform-agnostic IMEM.");
        assert (IMEM_AS_IROM != 1'b1) else $info("CELLRV32 PROCESSOR CONFIG NOTE: Implementing processor-internal IMEM as ROM ( %0d bytes), pre-initialized with application ( %0d bytes).", IMEM_SIZE,imem_app_size_c);
        assert (IMEM_AS_IROM != 1'b0) else $info("CELLRV32 PROCESSOR CONFIG NOTE: Implementing processor-internal IMEM as blank RAM (%0d bytes).", IMEM_SIZE);
        assert ((IMEM_AS_IROM != 1'b1) || (imem_app_size_c <= IMEM_SIZE)) else $error("CELLRV32 PROCESSOR CONFIG ERROR: Application (image = %0d bytes) does not fit into processor-internal IMEM (ROM = %0d bytes)!", imem_app_size_c, IMEM_SIZE);
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == IMEM_BASE[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = addr_i[index_size_f(IMEM_SIZE/4)+1 : 2]; // word aligned

    // Implement IMEM as pre-initialized ROM -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IMEM_AS_IROM == 1'b1) begin : imem_rom
            always_ff @( posedge clk_i ) begin : mem_access
                 if (acc_en == 1'b1) begin // reduce switching activity when not accessed
                   mem_rom_rd <= mem_rom[addr];
                 end
            end : mem_access
            /* read data */
            assign rdata = mem_rom_rd;
        end : imem_rom
    endgenerate

    // Implement IMEM as not-initialized RAM -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (IMEM_AS_IROM == 1'b0) begin : imem_ram
            always_ff @( posedge clk_i ) begin : mem_access
                // this RAM style should not require "no_rw_check" attributes as the read-after-write behavior
                // is intended to be defined implicitly via the if-WRITE-else-READ construct
                if (acc_en == 1'b1) begin // reduce switching activity when not accessed
                  if ((wren_i == 1'b1) && (ben_i[0] == 1'b1))  // byte 0
                     mem_ram_b0[addr] <= data_i[07:00];
                  else
                    mem_b0_rd <= mem_ram_b0[addr];

                  if ((wren_i == 1'b1) && (ben_i[1] == 1'b1))  // byte 1
                     mem_ram_b1[addr] <= data_i[15:08];
                  else
                    mem_b1_rd <= mem_ram_b1[addr];
                  
                  if ((wren_i == 1'b1) && (ben_i[2] == 1'b1))  // byte 2
                     mem_ram_b2[addr] <= data_i[23:16];
                  else
                    mem_b2_rd <= mem_ram_b2[addr];
                  
                  if ((wren_i == 1'b1) && (ben_i[3] == 1'b1))  // byte 3
                     mem_ram_b3[addr] <= data_i[31:24];
                  else
                     mem_b3_rd <= mem_ram_b3[addr];
                end
            end  : mem_access
            /* read data */
            assign rdata = {mem_b3_rd, mem_b2_rd, mem_b1_rd, mem_b0_rd};
        end : imem_ram
    endgenerate

    // Bus Feedback ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : bus_feedback
        rden <= acc_en & rden_i;
        if (IMEM_AS_IROM == 1'b1) begin
          ack_o <= acc_en & rden_i;
          err_o <= acc_en & wren_i;
        end else begin
          ack_o <= acc_en & (rden_i | wren_i);
          err_o <= 1'b0;
        end
    end : bus_feedback

    /* output gate */
    assign data_o =  (rden == 1'b1) ? rdata : '0;

endmodule