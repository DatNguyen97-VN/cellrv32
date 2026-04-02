// ######################################################################################################
// # << CELLRV32 - NPU Register File >>                                                                 #
// # ************************************************************************************************** #
// # This component includes accumulator register file. Registers are accumulated or overwritten.       #
// # The register file consists of block RAM, which is redundant for a separate accumulation port.      #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_register_file #(
    parameter int MATRIX_WIDTH   = 14,
    parameter int REGISTER_DEPTH = 512
)(
    input  logic                                 clk_i                       ,
    input  logic                                 rstn_i                      ,
    input  logic                                 enable_i                    ,
    input  logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] wr_addr_i                   ,
    input  logic [31:0]                          wr_port_i [MATRIX_WIDTH-1:0],
    input  logic                                 wr_en_i                     ,
    input  logic                                 acc_i                       ,
    input  logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] rd_addr_i                   ,
    output logic [31:0]                          rd_port_o [MATRIX_WIDTH-1:0] 
);

    // Memory arrays
    (* ram_style = "block" *) 
    logic [4*BYTE_WIDTH*MATRIX_WIDTH-1:0] ACCUMULATORS [0:REGISTER_DEPTH-1];
    
    (* ram_style = "block" *) 
    logic [4*BYTE_WIDTH*MATRIX_WIDTH-1:0] ACCUMULATORS_COPY [0:REGISTER_DEPTH-1];
    
    // Memory port signals
    logic                                 ACC_WRITE_EN;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] ACC_WRITE_ADDRESS;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] ACC_READ_ADDRESS;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] ACC_ACCU_ADDRESS;
    logic [31:0]                          ACC_WRITE_PORT [MATRIX_WIDTH-1:0];
    logic [31:0]                          ACC_READ_PORT [MATRIX_WIDTH-1:0];
    logic [31:0]                          ACC_ACCUMULATE_PORT [MATRIX_WIDTH-1:0];
    
    // DSP signals
    logic [31:0] DSP_ADD_PORT0_cs [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_ADD_PORT0_ns [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_ADD_PORT1_cs [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_ADD_PORT1_ns [MATRIX_WIDTH-1:0];
    
    (* use_dsp = "yes" *)
    logic [31:0] DSP_RESULT_PORT_cs [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_RESULT_PORT_ns [MATRIX_WIDTH-1:0];
    
    logic [31:0] DSP_PIPE0_cs [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_PIPE0_ns [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_PIPE1_cs [MATRIX_WIDTH-1:0];
    logic [31:0] DSP_PIPE1_ns [MATRIX_WIDTH-1:0];
    
    // Pipeline registers
    logic [31:0] ACCUMULATE_PORT_PIPE0_cs [MATRIX_WIDTH-1:0];
    logic [31:0] ACCUMULATE_PORT_PIPE0_ns [MATRIX_WIDTH-1:0];
    logic [31:0] ACCUMULATE_PORT_PIPE1_cs [MATRIX_WIDTH-1:0];
    logic [31:0] ACCUMULATE_PORT_PIPE1_ns [MATRIX_WIDTH-1:0];
    
    logic [2:0]  ACCUMULATE_PIPE_cs;
    logic [2:0]  ACCUMULATE_PIPE_ns;
    
    logic [31:0] WRITE_PORT_PIPE0_cs [MATRIX_WIDTH-1:0];
    logic [31:0] WRITE_PORT_PIPE0_ns [MATRIX_WIDTH-1:0];
    logic [31:0] WRITE_PORT_PIPE1_cs [MATRIX_WIDTH-1:0];
    logic [31:0] WRITE_PORT_PIPE1_ns [MATRIX_WIDTH-1:0];
    logic [31:0] WRITE_PORT_PIPE2_cs [MATRIX_WIDTH-1:0];
    logic [31:0] WRITE_PORT_PIPE2_ns [MATRIX_WIDTH-1:0];
    
    logic [5:0]  WRITE_ENABLE_PIPE_cs;
    logic [5:0]  WRITE_ENABLE_PIPE_ns;
    
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE0_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE0_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE1_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE1_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE2_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE2_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE3_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE3_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE4_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE4_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE5_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] WRITE_ADDRESS_PIPE5_ns;
    
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE0_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE0_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE1_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE1_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE2_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE2_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE3_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE3_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE4_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE4_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE5_cs;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] READ_ADDRESS_PIPE5_ns;

    // Helper functions for array conversion (equivalent to VHDL package functions)
    function automatic logic [4*BYTE_WIDTH*MATRIX_WIDTH-1:0] word_array_to_bits(input logic [31:0] word_array [MATRIX_WIDTH-1:0]);
        logic [4*BYTE_WIDTH*MATRIX_WIDTH-1:0] result;
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            result[i*32 +: 32] = word_array[i];
        end
        return result;
    endfunction
    
    function automatic void bits_to_word_array(input logic [4*BYTE_WIDTH*MATRIX_WIDTH-1:0] bitvector, output logic [31:0] word_array [MATRIX_WIDTH-1:0]);
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            word_array[i] = bitvector[i*32 +: 32];
        end
    endfunction

`ifndef _QUARTUS_IGNORE_INCLUDES
    // -----------------------------------------
    // Only For Simulation initialisation
    // -----------------------------------------
    initial begin : ACCUMULATORS_INIT
        // Each row is written byte-by-byte: byte[0] at bits[7:0], etc.
        // Row 0
        ACCUMULATORS[00] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[01] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[02] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[03] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[04] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[05] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[06] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[07] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[08] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[09] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[10] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[11] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[12] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS[13] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
    end
    //
    initial begin : ACCUMULATORS_COPY_INIT
        // Each row is written byte-by-byte: byte[0] at bits[7:0], etc.
        // Row 0
        ACCUMULATORS_COPY[00] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[01] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[02] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[03] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[04] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[05] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[06] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[07] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[08] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[09] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[10] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[11] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[12] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
        ACCUMULATORS_COPY[13] = {32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1};
    end
`endif // _QUARTUS_IGNORE_INCLUDES

    // Continuous assignments for pipeline stages
    always_comb begin
        WRITE_PORT_PIPE0_ns = wr_port_i;
        WRITE_PORT_PIPE1_ns = WRITE_PORT_PIPE0_cs;
        WRITE_PORT_PIPE2_ns = WRITE_PORT_PIPE1_cs;
        
        DSP_ADD_PORT0_ns = WRITE_PORT_PIPE2_cs;
        
        ACC_WRITE_PORT = DSP_RESULT_PORT_cs;
        
        ACCUMULATE_PORT_PIPE0_ns = ACC_ACCUMULATE_PORT;
        ACCUMULATE_PORT_PIPE1_ns = ACCUMULATE_PORT_PIPE0_cs;
        
        ACCUMULATE_PIPE_ns = {ACCUMULATE_PIPE_cs[1:0], acc_i};
        
        ACC_ACCU_ADDRESS = wr_addr_i;
        WRITE_ADDRESS_PIPE0_ns = wr_addr_i;
        WRITE_ADDRESS_PIPE1_ns = WRITE_ADDRESS_PIPE0_cs;
        WRITE_ADDRESS_PIPE2_ns = WRITE_ADDRESS_PIPE1_cs;
        WRITE_ADDRESS_PIPE3_ns = WRITE_ADDRESS_PIPE2_cs;
        WRITE_ADDRESS_PIPE4_ns = WRITE_ADDRESS_PIPE3_cs;
        WRITE_ADDRESS_PIPE5_ns = WRITE_ADDRESS_PIPE4_cs;
        ACC_WRITE_ADDRESS = WRITE_ADDRESS_PIPE5_cs;
        
        WRITE_ENABLE_PIPE_ns = {WRITE_ENABLE_PIPE_cs[4:0], wr_en_i};
        ACC_WRITE_EN = WRITE_ENABLE_PIPE_cs[5];
        
        READ_ADDRESS_PIPE0_ns = rd_addr_i;
        READ_ADDRESS_PIPE1_ns = READ_ADDRESS_PIPE0_cs;
        READ_ADDRESS_PIPE2_ns = READ_ADDRESS_PIPE1_cs;
        READ_ADDRESS_PIPE3_ns = READ_ADDRESS_PIPE2_cs;
        READ_ADDRESS_PIPE4_ns = READ_ADDRESS_PIPE3_cs;
        READ_ADDRESS_PIPE5_ns = READ_ADDRESS_PIPE4_cs;
        ACC_READ_ADDRESS = READ_ADDRESS_PIPE5_cs;
        
        rd_port_o = ACC_READ_PORT;
        
        DSP_PIPE0_ns = DSP_ADD_PORT0_cs;
        DSP_PIPE1_ns = DSP_ADD_PORT1_cs;
    end
    
    // DSP addition
    always_comb begin
        for (int i = 0; i < MATRIX_WIDTH; i++) begin
            DSP_RESULT_PORT_ns[i] = DSP_PIPE0_cs[i] + DSP_PIPE1_cs[i];
        end
    end
    
    // Accumulator multiplexer
    always_comb begin
        if (ACCUMULATE_PIPE_cs[2]) begin
            DSP_ADD_PORT1_ns = ACCUMULATE_PORT_PIPE1_cs;
        end else begin
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                DSP_ADD_PORT1_ns[i] = 32'h0;
            end
        end
    end
    
    // Memory write port
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
`ifdef _QUARTUS_IGNORE_INCLUDES
            for (int i = 0; i < REGISTER_DEPTH; i++) begin
                ACCUMULATORS[i] <= '0;
                ACCUMULATORS_COPY[i] <= '0;
            end
`endif // _QUARTUS_IGNORE_INCLUDES
        end else if (enable_i) begin
            if (ACC_WRITE_ADDRESS < REGISTER_DEPTH) begin
                if (ACC_WRITE_EN) begin
                    ACCUMULATORS[ACC_WRITE_ADDRESS] <= word_array_to_bits(ACC_WRITE_PORT);
                    ACCUMULATORS_COPY[ACC_WRITE_ADDRESS] <= word_array_to_bits(ACC_WRITE_PORT);
                end
            end
        end
    end
    
    // Memory read port
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < REGISTER_DEPTH; i++) begin
                ACC_READ_PORT[i] <= '0;
                ACC_ACCUMULATE_PORT[i] <= '0;
            end
        end else if (enable_i) begin
            if (ACC_READ_ADDRESS < REGISTER_DEPTH) begin
                bits_to_word_array(ACCUMULATORS[ACC_READ_ADDRESS], ACC_READ_PORT);
                bits_to_word_array(ACCUMULATORS_COPY[ACC_ACCU_ADDRESS], ACC_ACCUMULATE_PORT);
            end
        end
    end
    
    // Sequential logic for pipeline registers
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            // Reset all pipeline registers
            for (int i = 0; i < MATRIX_WIDTH; i++) begin
                DSP_ADD_PORT0_cs[i] <= 32'h0;
                DSP_ADD_PORT1_cs[i] <= 32'h0;
                DSP_RESULT_PORT_cs[i] <= 32'h0;
                DSP_PIPE0_cs[i] <= 32'h0;
                DSP_PIPE1_cs[i] <= 32'h0;
                
                ACCUMULATE_PORT_PIPE0_cs[i] <= 32'h0;
                ACCUMULATE_PORT_PIPE1_cs[i] <= 32'h0;
                
                WRITE_PORT_PIPE0_cs[i] <= 32'h0;
                WRITE_PORT_PIPE1_cs[i] <= 32'h0;
                WRITE_PORT_PIPE2_cs[i] <= 32'h0;
            end
            
            ACCUMULATE_PIPE_cs <= 3'b0;
            WRITE_ENABLE_PIPE_cs <= 6'b0;
            
            WRITE_ADDRESS_PIPE0_cs <= '0;
            WRITE_ADDRESS_PIPE1_cs <= '0;
            WRITE_ADDRESS_PIPE2_cs <= '0;
            WRITE_ADDRESS_PIPE3_cs <= '0;
            WRITE_ADDRESS_PIPE4_cs <= '0;
            WRITE_ADDRESS_PIPE5_cs <= '0;
            
            READ_ADDRESS_PIPE0_cs <= '0;
            READ_ADDRESS_PIPE1_cs <= '0;
            READ_ADDRESS_PIPE2_cs <= '0;
            READ_ADDRESS_PIPE3_cs <= '0;
            READ_ADDRESS_PIPE4_cs <= '0;
            READ_ADDRESS_PIPE5_cs <= '0;
        end else begin
            if (enable_i) begin
                DSP_ADD_PORT0_cs <= DSP_ADD_PORT0_ns;
                DSP_ADD_PORT1_cs <= DSP_ADD_PORT1_ns;
                DSP_RESULT_PORT_cs <= DSP_RESULT_PORT_ns;
                DSP_PIPE0_cs <= DSP_PIPE0_ns;
                DSP_PIPE1_cs <= DSP_PIPE1_ns;
                
                ACCUMULATE_PORT_PIPE0_cs <= ACCUMULATE_PORT_PIPE0_ns;
                ACCUMULATE_PORT_PIPE1_cs <= ACCUMULATE_PORT_PIPE1_ns;
                
                ACCUMULATE_PIPE_cs <= ACCUMULATE_PIPE_ns;
                
                WRITE_PORT_PIPE0_cs <= WRITE_PORT_PIPE0_ns;
                WRITE_PORT_PIPE1_cs <= WRITE_PORT_PIPE1_ns;
                WRITE_PORT_PIPE2_cs <= WRITE_PORT_PIPE2_ns;
                
                WRITE_ENABLE_PIPE_cs <= WRITE_ENABLE_PIPE_ns;
                
                WRITE_ADDRESS_PIPE0_cs <= WRITE_ADDRESS_PIPE0_ns;
                WRITE_ADDRESS_PIPE1_cs <= WRITE_ADDRESS_PIPE1_ns;
                WRITE_ADDRESS_PIPE2_cs <= WRITE_ADDRESS_PIPE2_ns;
                WRITE_ADDRESS_PIPE3_cs <= WRITE_ADDRESS_PIPE3_ns;
                WRITE_ADDRESS_PIPE4_cs <= WRITE_ADDRESS_PIPE4_ns;
                WRITE_ADDRESS_PIPE5_cs <= WRITE_ADDRESS_PIPE5_ns;
                
                READ_ADDRESS_PIPE0_cs <= READ_ADDRESS_PIPE0_ns;
                READ_ADDRESS_PIPE1_cs <= READ_ADDRESS_PIPE1_ns;
                READ_ADDRESS_PIPE2_cs <= READ_ADDRESS_PIPE2_ns;
                READ_ADDRESS_PIPE3_cs <= READ_ADDRESS_PIPE3_ns;
                READ_ADDRESS_PIPE4_cs <= READ_ADDRESS_PIPE4_ns;
                READ_ADDRESS_PIPE5_cs <= READ_ADDRESS_PIPE5_ns;
            end
        end
    end

endmodule