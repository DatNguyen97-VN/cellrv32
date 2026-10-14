// ####################################################################################################################
// # << CELLRV32 - NPU Matrix Multiply Control >>                                                                     #
// # **************************************************************************************************************** #
// # This component controls the matrix multiply operation in the NPU.                                                #
// # Systolic data from the systolic data setup is read and piped through the matrix multiply unit.                   #
// # Weights are activated (preweights are loaded in weights registers).                                              #
// # Weights are activated in a round trip. So weight instructions and matrix multiply instructions can be executed   #
// # in parallel to calculate a sequence of data.                                                                     #
// # Data is stored in the accumulators (register file) and can be accumulated to consisting data or overwritten.     #
// # **************************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_matrix_multiply_control #(
    parameter int MATRIX_WIDTH = 14
) (
    input  logic                                 clk_i          ,
    input  logic                                 rstn_i         ,
    input  logic                                 enable_i       ,
    input  instruction_t                         inst_i         , // The matrix multiply instruction to be executed
    input  logic                                 inst_en_i      , // Enable for instruction
    output logic [BUFFER_ADDRESS_WIDTH-1:0]      buff_sds_addr_o, // Address for unified buffer read
    output logic                                 buff_read_en_o , // Read enable flag for unified buffer
    output logic                                 mmu_sds_en_o   , // Enable flag for matrix multiply unit and systolic data setup
    output logic                                 mmu_signed_o   , // Determines if the data is signed or unsigned
    output logic                                 act_wei_o      , // Activate flag for the preweights in the matrix multiply unit
    output logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_addr_o     , // Address of the accumulators
    output logic                                 acc_o          , // Determines if data should be accumulated or overwritten
    output logic                                 acc_en_o       , // Enable flag for accumulators
    output logic                                 busy_o         , // If the control unit is busy, a new instruction shouldn't be fed
    output logic                                 resource_busy_o  // The resources are in use and the instruction is not fully finished yet
);
    // internal signals
    logic [BUFFER_ADDRESS_WIDTH-1:0]      buff_sds_addr;
    logic                                 buff_read_en;
    logic                                 mmu_sds_en;
    logic                                 mmu_signed;
    logic                                 detect_act_wei;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_addr;
    logic                                 acc;
    logic [MATRIX_WIDTH-1+2:0]            acc_en_pipe;
    logic                                 running;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] length;

    // ------------------------------------
    // Main control logic
    // ------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : read_unified_buffer
        if (!rstn_i) begin
            buff_sds_addr <= '0;
            buff_read_en  <= 1'b0;
            mmu_signed    <= 1'b0;
            acc           <= 1'b0;
            running       <= 1'b0;
            length        <= '0;
        end else if (enable_i) begin
            if (!running && inst_en_i) begin
                buff_sds_addr <= inst_i.buff_addr;
                buff_read_en  <= 1'b1;
                mmu_signed    <= inst_i.opcode[0];
                acc           <= inst_i.opcode[1];
                running       <= 1'b1;
                length        <= inst_i.calc_len;
            end else if (running) begin
                if (buff_sds_addr < length - 1) begin
                    buff_sds_addr <= buff_sds_addr + 1'b1;
                    buff_read_en  <= 1'b1;
                    running       <= 1'b1;
                end else begin
                    buff_sds_addr <= '0;
                    buff_read_en  <= 1'b0; // Stop reading after the last data is read
                    running       <= 1'b0;
                end
            end
        end    
    end : read_unified_buffer

    always_ff @(posedge clk_i or negedge rstn_i) begin : load_weights_input_into_mmu
        if (!rstn_i) begin
            mmu_sds_en     <= 1'b0;
            detect_act_wei <= 1'b0;
        end else if (enable_i) begin
            mmu_sds_en     <= buff_read_en;
            detect_act_wei <= mmu_sds_en;
        end
    end : load_weights_input_into_mmu

    always_ff @(posedge clk_i or negedge rstn_i) begin : load_accumulator_control
        if (!rstn_i) begin
            acc_addr    <= '0;
            acc_en_pipe <= '0;
        end else if (enable_i) begin
            acc_en_pipe <= {acc_en_pipe[$bits(acc_en_pipe)-1:0], mmu_sds_en};
            // The accumulator address is loaded in the beginning of the operation and 
            // then incremented in each cycle until the length of the operation is reached
            if (inst_en_i) begin
                acc_addr <= inst_i.acc_addr;
            end else if (acc_en_pipe[$bits(acc_en_pipe)-1]) begin
                if (acc_addr < length - 1) begin
                    acc_addr <= acc_addr + 1'b1;
                end else begin
                    acc_addr <= '0;
                end
            end
        end
    end : load_accumulator_control

    // Output assignments
    assign buff_sds_addr_o = buff_sds_addr;
    assign buff_read_en_o  = buff_read_en;
    assign mmu_sds_en_o    = mmu_sds_en;
    assign mmu_signed_o    = mmu_signed & mmu_sds_en;
    assign act_wei_o       = ~detect_act_wei & mmu_sds_en;
    assign acc_addr_o      = acc_addr;
    assign acc_o           = acc & acc_en_pipe[$bits(acc_en_pipe)-1];
    assign acc_en_o        = acc_en_pipe[$bits(acc_en_pipe)-1];
    assign busy_o          = running;
    // data is not fully written to the accumulators until the last stage of the pipeline
    assign resource_busy_o = running | (acc_en_pipe != 0);
    
endmodule