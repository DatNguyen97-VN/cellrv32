// ######################################################################################################
// # << CELLRV32 - NPU Unified Buffer >>                                                                #
// # ************************************************************************************************** #
// # Unified buffer for neural net layer inputs                                                         #
// # The buffer can store data from the master (host system). The stored data can then be used          #
// # for matrix multiplies. After activation, the calculated data can be stored back for the next       #
// # neural net layer.                                                                                  #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_unified_buffer #(
    parameter int MATRIX_WIDTH = 14,
    /// How many tiles can be saved (depth of the buffer)
    parameter int TILE_WIDTH   = 4096
)(
    input  logic                    clk_i                          ,
    input  logic                    rstn_i                         ,
    input  logic                    enable_i                       ,
    // Master port - overrides other ports
    input  logic [23:0]             ms_addr_i                      , // Master (host) address, overrides other addresses
    input  logic                    ms_en_i                        , // Master (host) enable, overrides other enables
    input  logic [MATRIX_WIDTH-1:0] ms_wr_en_i                     , // Per-byte master write enable
    input  logic [7:0]              ms_wr_port_i [MATRIX_WIDTH-1:0], // Master write data
    output logic [7:0]              ms_rd_port_o [MATRIX_WIDTH-1:0], // Master read data
    // Port 0 (read-only from non-master)
    input  logic [23:0]             addr0_i                        , // Address of port 0
    input  logic                    en0_i                          , // Enable of port 0
    output logic [7:0]              rd_port0_o   [MATRIX_WIDTH-1:0], // Read port 0 data
    // Port 1 (read/write)
    input  logic [23:0]             addr1_i                        , // Address of port 1
    input  logic                    en1_i                          , // Enable of port 1
    input  logic                    wr_en1_i                       , // Write enable of port 1
    input  logic [7:0]              wr_port1_i   [MATRIX_WIDTH-1:0]  // Write port 1 data
);

    // -----------------------------------------------------------------------
    // Local parameters
    // -----------------------------------------------------------------------
    localparam int DATA_WIDTH = MATRIX_WIDTH * 8; // one row in bits

    // -----------------------------------------------------------------------
    // Flat bit-vector helpers (equivalent to BYTE_ARRAY_TO_BITS / BITS_TO_BYTE_ARRAY)
    // -----------------------------------------------------------------------
    // Pack/unpack functions are inlined via the signals below.

    // Flattened write/read vectors
    logic [DATA_WIDTH-1:0] WRITE_PORT1_BITS;
    logic [DATA_WIDTH-1:0] MASTER_WRITE_PORT_BITS;
    logic [DATA_WIDTH-1:0] READ_PORT0_BITS;
    logic [DATA_WIDTH-1:0] MASTER_READ_PORT_BITS;

    // BYTE_ARRAY_TO_BITS: byte[0] → bits[7:0], byte[1] → bits[15:8], …
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            WRITE_PORT1_BITS      [i*8 +: 8] = wr_port1_i[i];
            MASTER_WRITE_PORT_BITS[i*8 +: 8] = ms_wr_port_i[i];
        end
    end

    // -----------------------------------------------------------------------
    // Output pipeline registers
    // -----------------------------------------------------------------------
    logic [7:0] READ_PORT0_REG0       [MATRIX_WIDTH-1:0];
    logic [7:0] READ_PORT0_REG1       [MATRIX_WIDTH-1:0];
    logic [7:0] MASTER_READ_PORT_REG0 [MATRIX_WIDTH-1:0];
    logic [7:0] MASTER_READ_PORT_REG1 [MATRIX_WIDTH-1:0];

    // BITS_TO_BYTE_ARRAY for the combinational _ns wires is folded into the
    // SEQ_LOG process below (read from RAM → REG0 → REG1 → output).

    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            rd_port0_o[i]   = READ_PORT0_REG1      [i];
            ms_rd_port_o[i] = MASTER_READ_PORT_REG1[i];
        end
    end

    // -----------------------------------------------------------------------
    // Address / enable override (MASTER_EN takes priority)
    // -----------------------------------------------------------------------
    logic [23:0] ADDRESS0_OVERRIDE;
    logic [23:0] ADDRESS1_OVERRIDE;
    logic        EN0_OVERRIDE;
    logic        EN1_OVERRIDE;

    always_comb begin
        if (ms_en_i) begin
            EN0_OVERRIDE      = ms_en_i;
            EN1_OVERRIDE      = ms_en_i;
            ADDRESS0_OVERRIDE = ms_addr_i;
            ADDRESS1_OVERRIDE = ms_addr_i;
        end else begin
            EN0_OVERRIDE      = en0_i;
            EN1_OVERRIDE      = en1_i;
            ADDRESS0_OVERRIDE = addr0_i;
            ADDRESS1_OVERRIDE = addr1_i;
        end
    end

    // -----------------------------------------------------------------------
    // RAM declaration
    // The VHDL uses a 'shared variable' accessed from two clocked processes.
    // In SystemVerilog, a simple 2-D logic array with two always_ff blocks
    // replicates the same inferred true dual-port block RAM behaviour.
    // (* ram_style = "block" *) maps to the Xilinx synthesis attribute.
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] RAM [0:TILE_WIDTH-1];

`ifndef _QUARTUS_IGNORE_INCLUDES
    // Only For Simulation initialisation
    initial begin : RAM_INIT
        // Zero-initialise all entries first
        for (int idx = 0; idx < TILE_WIDTH; idx++) begin
            RAM[idx] = '0;
        end
        // Each row is written byte-by-byte: byte[0] at bits[7:0], etc.
        // Row 0
        RAM[ 0] = {8'h72,8'h73,8'h74,8'h75,8'h76,8'h77,8'h78,8'h79,8'h7A,8'h7B,8'h7C,8'h7D,8'h7E,8'h7F};
        RAM[ 1] = {8'h64,8'h65,8'h66,8'h67,8'h68,8'h69,8'h6A,8'h6B,8'h6C,8'h6D,8'h6E,8'h6F,8'h70,8'h71};
        RAM[ 2] = {8'h56,8'h57,8'h58,8'h59,8'h5A,8'h5B,8'h5C,8'h5D,8'h5E,8'h5F,8'h60,8'h61,8'h62,8'h63};
        RAM[ 3] = {8'h48,8'h49,8'h4A,8'h4B,8'h4C,8'h4D,8'h4E,8'h4F,8'h50,8'h51,8'h52,8'h53,8'h54,8'h55};
        RAM[ 4] = {8'h3A,8'h3B,8'h3C,8'h3D,8'h3E,8'h3F,8'h40,8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47};
        RAM[ 5] = {8'h2C,8'h2D,8'h2E,8'h2F,8'h30,8'h31,8'h32,8'h33,8'h34,8'h35,8'h36,8'h37,8'h38,8'h39};
        RAM[ 6] = {8'h1E,8'h1F,8'h20,8'h21,8'h22,8'h23,8'h24,8'h25,8'h26,8'h27,8'h28,8'h29,8'h2A,8'h2B};
        RAM[ 7] = {8'h10,8'h11,8'h12,8'h13,8'h14,8'h15,8'h16,8'h17,8'h18,8'h19,8'h1A,8'h1B,8'h1C,8'h1D};
        RAM[ 8] = {8'h02,8'h03,8'h04,8'h05,8'h06,8'h07,8'h08,8'h09,8'h0A,8'h0B,8'h0C,8'h0D,8'h0E,8'h0F};
        RAM[ 9] = {8'hF4,8'hF5,8'hF6,8'hF7,8'hF8,8'hF9,8'hFA,8'hFB,8'hFC,8'hFD,8'hFE,8'hFF,8'h00,8'h01};
        RAM[10] = {8'hE6,8'hE7,8'hE8,8'hE9,8'hEA,8'hEB,8'hEC,8'hED,8'hEE,8'hEF,8'hF0,8'hF1,8'hF2,8'hF3};
        RAM[11] = {8'hD8,8'hD9,8'hDA,8'hDB,8'hDC,8'hDD,8'hDE,8'hDF,8'hE0,8'hE1,8'hE2,8'hE3,8'hE4,8'hE5};
        RAM[12] = {8'hCA,8'hCB,8'hCC,8'hCD,8'hCE,8'hCF,8'hD0,8'hD1,8'hD2,8'hD3,8'hD4,8'hD5,8'hD6,8'hD7};
        RAM[13] = {8'hBC,8'hBD,8'hBE,8'hBF,8'hC0,8'hC1,8'hC2,8'hC3,8'hC4,8'hC5,8'hC6,8'hC7,8'hC8,8'hC9};
    end
`endif // _QUARTUS_IGNORE_INCLUDES

    // -----------------------------------------------------------------------
    // PORT 0: master byte-write + read
    // -----------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (EN0_OVERRIDE) begin
            // synthesis translate_off
            if (ADDRESS0_OVERRIDE < TILE_WIDTH) begin
            // synthesis translate_on

                // Per-byte master write
                for (int i = 0; i < MATRIX_WIDTH; i++) begin
                    if (ms_wr_en_i[i])
                        RAM[ADDRESS0_OVERRIDE][i*8 +: 8] = MASTER_WRITE_PORT_BITS[i*8 +: 8];
                end

                // Read, only for simulation
                READ_PORT0_BITS <= RAM[ADDRESS0_OVERRIDE];

            // synthesis translate_off
            end
            // synthesis translate_on
        end
    end

    // -----------------------------------------------------------------------
    // PORT 1: full-row write + read
    // -----------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (EN1_OVERRIDE) begin
            // synthesis translate_off
            if (ADDRESS1_OVERRIDE < TILE_WIDTH) begin
            // synthesis translate_on

                if (wr_en1_i)
                    RAM[ADDRESS1_OVERRIDE] = WRITE_PORT1_BITS;
                
                // Read, only for simulation
                MASTER_READ_PORT_BITS <= RAM[ADDRESS1_OVERRIDE];

            // synthesis translate_off
            end
            // synthesis translate_on
        end
    end

    // -----------------------------------------------------------------------
    // SEQ_LOG: pipeline the read data through two register stages
    // -----------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                READ_PORT0_REG0      [i] <= 8'h00;
                READ_PORT0_REG1      [i] <= 8'h00;
                MASTER_READ_PORT_REG0[i] <= 8'h00;
                MASTER_READ_PORT_REG1[i] <= 8'h00;
            end
        end else if (enable_i) begin
            // Stage 0: flat bits → byte array (BITS_TO_BYTE_ARRAY equivalent)
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                READ_PORT0_REG0      [i] <= READ_PORT0_BITS      [i*8 +: 8];
                MASTER_READ_PORT_REG0[i] <= MASTER_READ_PORT_BITS[i*8 +: 8];
            end
            // Stage 1
            READ_PORT0_REG1       <= READ_PORT0_REG0;
            MASTER_READ_PORT_REG1 <= MASTER_READ_PORT_REG0;
        end
    end

endmodule