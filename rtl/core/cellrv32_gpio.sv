// ##################################################################################################
// # << CELLRV32 - General Purpose Parallel Input/Output Port (GPIO) >>                             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_gpio #(
    parameter int GPIO_NUM = 64 // number of GPIO input/output pairs (0..64)
) (
    /* host access */
    input  logic        clk_i , // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    /* parallel io */
    input  logic [63:0] gpio_i,
    output logic [63:0] gpio_o
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(gpio_size_c); // low address boundary bit

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* accessible regs */
    logic [63:0] din, din_rd, dout, dout_rd;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
       assert (!((GPIO_NUM < 0) || (GPIO_NUM > 64)))
       else $error("CELLRV32 PROCESSOR CONFIG ERROR! Invalid GPIO pin number configuration (0..64).");
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == gpio_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {gpio_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            dout <= '0;
        end else begin
            if (wren == 1'b1) begin
                // low output
                if (addr == gpio_out_lo_addr_c) begin
                    dout[31:00] <= data_i;
                end
                // high output
                if (addr == gpio_out_hi_addr_c) begin
                    dout[63:32] <= data_i;
                end
            end
        end
    end : write_access

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        /* bus handshake */
        ack_o <= wren | rden;
        /* read data */
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            unique case (addr[3:2])
                2'b00 : data_o <= din_rd[31:00];
                2'b01 : data_o <= din_rd[63:32];
                2'b10 : data_o <= dout_rd[31:00];
                default: begin
                        data_o <= dout_rd[63:32];
                end
            endcase
        end
    end : read_access

    // Physical Pin Mapping ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : pin_mapping
        /* defaults */
        din_rd  = '0;
        dout_rd = '0;
        // loop
        for (int i = 0; i < GPIO_NUM; ++i) begin
            din_rd[i]  = din[i];
            dout_rd[i] = dout[i];
        end
    end : pin_mapping

    /* IO */
    always_ff @(posedge clk_i) begin
        din <= gpio_i; // sample buffer to prevent metastability
    end
    //
    assign gpio_o = dout_rd;
    
endmodule