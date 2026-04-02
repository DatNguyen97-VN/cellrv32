// ######################################################################################################
// # << CELLRV32 - NPU Weight Buffer >>                                                                 #
// # ************************************************************************************************** #
// # This component includes the weight buffer, a buffer used for neural net weights.                   #
// # The buffer can store data from the master (host system). The stored data can then be               #
// # used for matrix multiplies.                                                                        #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module celrv32_npu_weight_buffer #(
    parameter int MATRIX_WIDTH = 14,
    parameter int TILE_WIDTH   = 32768  // The depth of the buffer.
)(
    input  logic                            clk_i                        ,
    input  logic                            rstn_i                       ,
    input  logic                            enable_i                     ,
    // Port0
    input  logic [WEIGHT_ADDRESS_WIDTH-1:0] addr0_i                      , // Address of port 0
    input  logic                            en0_i                        , // Enable of port 0
    input  logic                            wr_en0_i                     , // Write enable of port 0
    input  logic [BYTE_WIDTH-1:0]           wr_port0_i [MATRIX_WIDTH-1:0], // Write port of port 0
    output logic [BYTE_WIDTH-1:0]           rd_port0_o [MATRIX_WIDTH-1:0], // Read port of port 0
    // Port1
    input  logic [WEIGHT_ADDRESS_WIDTH-1:0] addr1_i                      , // Address of port 1
    input  logic                            en1_i                        , // Enable of port 1
    input  logic [MATRIX_WIDTH-1:0]         wr_en1_i                     , // Write enable of port 1 (per-byte)
    input  logic [BYTE_WIDTH-1:0]           wr_port1_i [MATRIX_WIDTH-1:0], // Write port of port 1
    output logic [BYTE_WIDTH-1:0]           rd_port1_o [MATRIX_WIDTH-1:0]  // Read port of port 1
);

    // Pipeline registers for read outputs
    logic [BYTE_WIDTH-1:0] READ_PORT0_REG0_ns [MATRIX_WIDTH-1:0];

    logic [BYTE_WIDTH-1:0] READ_PORT1_REG0_cs [MATRIX_WIDTH-1:0];
    logic [BYTE_WIDTH-1:0] READ_PORT1_REG0_ns [MATRIX_WIDTH-1:0];
    logic [BYTE_WIDTH-1:0] READ_PORT1_REG1_cs [MATRIX_WIDTH-1:0];

    // Bit vectors for RAM interface
    logic [MATRIX_WIDTH*BYTE_WIDTH-1:0] WRITE_PORT0_BITS;
    logic [MATRIX_WIDTH*BYTE_WIDTH-1:0] WRITE_PORT1_BITS;
    logic [MATRIX_WIDTH*BYTE_WIDTH-1:0] READ_PORT0_BITS;
    logic [MATRIX_WIDTH*BYTE_WIDTH-1:0] READ_PORT1_BITS;

    // RAM storage - using block RAM attribute
    (* ram_style = "block" *) 
    logic [MATRIX_WIDTH*BYTE_WIDTH-1:0] RAM [0:TILE_WIDTH-1];

`ifndef _QUARTUS_IGNORE_INCLUDES
    // Initialize RAM with identity matrix for testing (synthesis will ignore)
    initial begin
        for (int i = 0; i < TILE_WIDTH; i++) begin
            RAM[i] = '0;
        end
        // Test values - Identity matrix (first 14 entries)
        RAM[0]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80};
        RAM[1]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00};
        RAM[2]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00};
        RAM[3]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00};
        RAM[4]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[5]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[6]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[7]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[8]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[9]  = {8'h00, 8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[10] = {8'h00, 8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[11] = {8'h00, 8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[12] = {8'h00, 8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        RAM[13] = {8'h80, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
    end
`endif // _QUARTUS_IGNORE_INCLUDES

    // Convert between array and bit vector formats
    always_comb begin
        // Pack write arrays into bit vectors
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            WRITE_PORT0_BITS[i*BYTE_WIDTH +: BYTE_WIDTH] = wr_port0_i[i];
            WRITE_PORT1_BITS[i*BYTE_WIDTH +: BYTE_WIDTH] = wr_port1_i[i];
        end
        
        // Unpack read bit vectors into arrays
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            READ_PORT0_REG0_ns[i] = READ_PORT0_BITS[i*BYTE_WIDTH +: BYTE_WIDTH];
            READ_PORT1_REG0_ns[i] = READ_PORT1_BITS[i*BYTE_WIDTH +: BYTE_WIDTH];
        end
    end

    // Port 0 - Full word write enable
    always_ff @(posedge clk_i) begin
        if (en0_i) begin
            if (addr0_i < TILE_WIDTH) begin  // Bounds checking (synthesis will optimize out)
                if (wr_en0_i) begin
                    RAM[addr0_i] <= WRITE_PORT0_BITS;
                end
                READ_PORT0_BITS <= RAM[addr0_i];
            end
        end
    end
    
    // Port 1 - Per-byte write enable
    always_ff @(posedge clk_i) begin
        if (en1_i) begin
            if (addr1_i < TILE_WIDTH) begin  // Bounds checking (synthesis will optimize out)
                for (int i = 0; i < MATRIX_WIDTH; i++) begin
                    if (wr_en1_i[i]) begin
                        RAM[addr1_i][i*BYTE_WIDTH +: BYTE_WIDTH] <= wr_port1_i[i];
                    end
                end
                READ_PORT1_BITS <= RAM[addr1_i];
            end
        end
    end
    
    // Pipeline registers for read outputs
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                READ_PORT1_REG0_cs[i] <= '0;
                READ_PORT1_REG1_cs[i] <= '0;
            end
        end else if (enable_i) begin
            READ_PORT1_REG0_cs <= READ_PORT1_REG0_ns;
            READ_PORT1_REG1_cs <= READ_PORT1_REG0_cs;
        end
    end

    // Output assignments - 2-cycle latency from RAM read
    assign rd_port0_o = READ_PORT0_REG0_ns;
    assign rd_port1_o = READ_PORT1_REG1_cs;

endmodule