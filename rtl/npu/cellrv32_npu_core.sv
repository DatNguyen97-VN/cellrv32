//! @file tpu_core.sv
//! @brief SystemVerilog conversion of TPU_CORE.vhdl
//! @details The TPU core includes all components necessary for calculation and controlling.
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_core
#(
    parameter int MATRIX_WIDTH         = 14   , // The width of the Matrix Multiply Unit and busses.
    parameter int WEIGHT_BUFFER_DEPTH  = 32768, // The depth of the weight buffer.
    parameter int UNIFIED_BUFFER_DEPTH = 4096   // The depth of the unified buffer.
)(
    input  logic                            clk_i                           ,
    input  logic                            rstn_i                          ,
    input  logic                            enable_i                        ,
    // Host weight buffer ports
    input  logic [BYTE_WIDTH-1:0]           wei_wr_port_i [MATRIX_WIDTH-1:0],
    input  logic [WEIGHT_ADDRESS_WIDTH-1:0] wei_addr_i                      ,
    input  logic                            wei_en_i                        ,
    input  logic [MATRIX_WIDTH-1:0]         wei_wr_en_i                     ,
    // Host unified buffer ports
    input  logic [BYTE_WIDTH-1:0]           buf_wr_port_i [MATRIX_WIDTH-1:0],
    output logic [BYTE_WIDTH-1:0]           buf_rd_port_o [MATRIX_WIDTH-1:0],
    input  logic [BUFFER_ADDRESS_WIDTH-1:0] buf_addr_i                      ,
    input  logic                            buf_en_i                        ,
    input  logic [MATRIX_WIDTH-1:0]         buf_wr_en_i                     ,
    // Instruction interface
    input  instruction_t                    inst_port_i                     ,
    input  logic                            inst_en_i                       ,
    // Status
    output logic                            busy_o                          ,
    output logic                            sync_o
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    // Weight buffer internal port 0
    logic [WEIGHT_ADDRESS_WIDTH-1:0] weight_address0;
    logic                            weight_en0;
    logic [BYTE_WIDTH-1:0]           weight_read_port0 [MATRIX_WIDTH-1:0];
    // Unified buffer internal port 0 (read by SDS)
    logic [BUFFER_ADDRESS_WIDTH-1:0] buffer_address0;
    logic                            buffer_en0;
    logic [BYTE_WIDTH-1:0]           buffer_read_port0 [MATRIX_WIDTH-1:0];
    // Unified buffer internal port 1 (write from activation)
    logic [BUFFER_ADDRESS_WIDTH-1:0] buffer_address1;
    logic                            buffer_write_en1;
    logic [BYTE_WIDTH-1:0]           buffer_write_port1 [MATRIX_WIDTH-1:0];
    // Systolic Data Setup output
    logic [BYTE_WIDTH-1:0]           sds_systolic_output [MATRIX_WIDTH-1:0];
    // MMU control signals
    logic                            mmu_weight_signed;
    logic                            mmu_systolic_signed;
    logic                            mmu_activate_weight;
    logic                            mmu_load_weight;
    logic [BYTE_WIDTH-1:0]           mmu_weight_address;
    logic [31:0]                     mmu_result_data [MATRIX_WIDTH-1:0];
    // Register file signals
    accumulator_address_t            reg_write_address;
    logic                            reg_write_en;
    logic                            reg_accumulate;
    accumulator_address_t            reg_read_address;
    logic [31:0]                     reg_read_port [MATRIX_WIDTH-1:0];
    // Activation signals
    logic [3:0]                      activation_function;
    logic                            activation_signed;
    // Control signals
    weight_instruction_t             weight_instruction;
    logic                            weight_instruction_en;
    logic                            weight_resource_busy;
    logic                            weight_busy;

    instruction_t                    mmu_instruction;
    logic                            mmu_instruction_en;
    logic                            mmu_sds_en;
    logic                            mmu_resource_busy;
    logic                            matrix_busy;

    instruction_t                    activation_instruction;
    logic                            activation_instruction_en;
    logic                            activation_resource_busy;
    logic                            activation_busy;

    logic                            instruction_busy;
    instruction_t                    instruction_output;
    logic                            instruction_read;

    // -------------------------------------------------------------------------
    // Weight Buffer
    // -------------------------------------------------------------------------
    celrv32_npu_weight_buffer #(
        .MATRIX_WIDTH (MATRIX_WIDTH       ),
        .TILE_WIDTH   (WEIGHT_BUFFER_DEPTH)
    ) weight_buffer_inst (
        .clk_i        (clk_i              ),
        .rstn_i       (rstn_i             ),
        .enable_i     (enable_i           ),
        // Port 0 (internal read)
        .addr0_i      (weight_address0    ),
        .en0_i        (weight_en0         ),
        .wr_en0_i     (1'b0               ),
        .wr_port0_i   ('0                 ),
        .rd_port0_o   (weight_read_port0  ),
        // Port 1 (host write)
        .addr1_i      (wei_addr_i         ),
        .en1_i        (wei_en_i           ),
        .wr_en1_i     (wei_wr_en_i        ),
        .wr_port1_i   (wei_wr_port_i      ),
        .rd_port1_o   (                   )
    );

    // -------------------------------------------------------------------------
    // Unified Buffer
    // -------------------------------------------------------------------------
    cellrv32_npu_unified_buffer #(
        .MATRIX_WIDTH (MATRIX_WIDTH        ),
        .TILE_WIDTH   (UNIFIED_BUFFER_DEPTH)
    ) unified_buffer_inst (
        .clk_i        (clk_i               ),
        .rstn_i       (rstn_i              ),
        .enable_i     (enable_i            ),
        // Master port (host, overrides internal ports)
        .ms_addr_i    (buf_addr_i          ),
        .ms_en_i      (buf_en_i            ),
        .ms_wr_en_i   (buf_wr_en_i         ),
        .ms_wr_port_i (buf_wr_port_i       ),
        .ms_rd_port_o (buf_rd_port_o       ),
        // Port 0 (internal read → SDS)
        .addr0_i      (buffer_address0     ),
        .en0_i        (buffer_en0          ),
        .rd_port0_o   (buffer_read_port0   ),
        // Port 1 (internal write ← activation)
        .addr1_i      (buffer_address1     ),
        .en1_i        (buffer_write_en1    ),
        .wr_en1_i     (buffer_write_en1    ),
        .wr_port1_i   (buffer_write_port1  )
    );

    // -------------------------------------------------------------------------
    // Systolic Data Setup
    // -------------------------------------------------------------------------
    cellrv32_npu_systolic_data_setup #(
        .MATRIX_WIDTH (MATRIX_WIDTH       )
    ) systolic_data_setup_inst (
        .clk_i        (clk_i              ),
        .rstn_i       (rstn_i             ),
        .enable_i     (enable_i           ),
        .data_i       (buffer_read_port0  ),
        .systolic_o   (sds_systolic_output)
    );

    // -------------------------------------------------------------------------
    // Matrix Multiply Unit
    // -------------------------------------------------------------------------
    cellrv32_npu_matrix_multiply_unit #(
        .MATRIX_WIDTH      (MATRIX_WIDTH       )
    ) matrix_multiply_unit_inst (
        .clk_i             (clk_i              ),
        .rstn_i            (rstn_i             ),
        .enable_i          (enable_i           ),
        .wei_data_i        (weight_read_port0  ),
        .wei_signed_i      (mmu_weight_signed  ),
        .systolic_data_i   (sds_systolic_output),
        .systolic_signed_i (mmu_systolic_signed),
        .act_wei_i         (mmu_activate_weight),
        .load_wei_i        (mmu_load_weight    ),
        .wei_addr_i        (mmu_weight_address ),
        .result_o          (mmu_result_data    )
    );

    // -------------------------------------------------------------------------
    // Register File (Accumulator)
    // -------------------------------------------------------------------------
    cellrv32_npu_register_file #(
        .MATRIX_WIDTH   (MATRIX_WIDTH     ),
        .REGISTER_DEPTH (512              )
    ) register_file_inst (
        .clk_i          (clk_i            ),
        .rstn_i         (rstn_i           ),
        .enable_i       (enable_i         ),
        .wr_addr_i      (reg_write_address),
        .wr_port_i      (mmu_result_data  ),
        .wr_en_i        (reg_write_en     ),
        .acc_i          (reg_accumulate   ),
        .rd_addr_i      (reg_read_address ),
        .rd_port_o      (reg_read_port    )
    );

    // -------------------------------------------------------------------------
    // Activation
    // -------------------------------------------------------------------------
    cellrv32_npu_activation #(
        .MATRIX_WIDTH          (MATRIX_WIDTH       )
    ) activation_inst          (
        .clk_i                 (clk_i              ),
        .rstn_i                (rstn_i             ),
        .enable_i              (enable_i           ),
        .activation_function_i (activation_function),
        .signed_not_unsigned_i (activation_signed  ),
        .activation_input_i    (reg_read_port      ),
        .activation_output_o   (buffer_write_port1 )
    );

    // -------------------------------------------------------------------------
    // Weight Control
    // -------------------------------------------------------------------------
    cellrv32_npu_weight_control #(
        .MATRIX_WIDTH     (MATRIX_WIDTH         )
    ) weight_control_inst (
        .clk_i            (clk_i                ),
        .rstn_i           (rstn_i               ),
        .enable_i         (enable_i             ),
        .instruction_i    (weight_instruction   ),
        .instruction_en_i (weight_instruction_en),
        .wei_read_en_o    (weight_en0           ),
        .wei_buff_addr_o  (weight_address0      ),
        .load_wei_o       (mmu_load_weight      ),
        .wei_addr_o       (mmu_weight_address   ),
        .wei_signed_o     (mmu_weight_signed    ),
        .busy_o           (weight_busy          ),
        .resource_busy_o  (weight_resource_busy )
    );

    // -------------------------------------------------------------------------
    // Matrix Multiply Control
    // -------------------------------------------------------------------------
    cellrv32_npu_matrix_multiply_control #(
        .MATRIX_WIDTH    (MATRIX_WIDTH       )
    ) matrix_multiply_control_inst (
        .clk_i           (clk_i              ),
        .rstn_i          (rstn_i             ),
        .enable_i        (enable_i           ),
        .inst_i          (mmu_instruction    ),
        .inst_en_i       (mmu_instruction_en ),
        // unified buffer reading signals
        .buff_sds_addr_o (buffer_address0    ),
        .buff_read_en_o  (buffer_en0         ),
        // mac control signals
        .mmu_sds_en_o    (                   ),
        .mmu_signed_o    (mmu_systolic_signed),
        .act_wei_o       (mmu_activate_weight),
        // register file control signals
        .acc_addr_o      (reg_write_address  ),
        .acc_o           (reg_accumulate     ),
        .acc_en_o        (reg_write_en       ),
        .busy_o          (matrix_busy        ),
        .resource_busy_o (mmu_resource_busy  )
    );

    // -------------------------------------------------------------------------
    // Activation Control
    // -------------------------------------------------------------------------
    cellrv32_npu_activation_control #(
        .MATRIX_WIDTH      (MATRIX_WIDTH             )
    ) activation_control_inst  (
        .clk_i             (clk_i                    ),
        .rstn_i            (rstn_i                   ),
        .enable_i          (enable_i                 ),
        .inst_i            (activation_instruction   ), // activation instruction
        .inst_en_i         (activation_instruction_en), // valid signal
        .acc_act_addr_o    (reg_read_address         ), // address for the accumulators
        .activation_func_o (activation_function      ), // type of activation function
        .signed_unsigned_o (activation_signed        ), // data is signed or unsigned
        .act_buff_addr_o   (buffer_address1          ), // address for the unified buffer
        .buff_wr_en_o      (buffer_write_en1         ), // write enable
        .busy_o            (activation_busy          ), // busy
        .resource_busy_o   (activation_resource_busy )  // resource busy
    );

    // -------------------------------------------------------------------------
    // Look-Ahead Buffer
    // -------------------------------------------------------------------------
    cellrv32_npu_look_ahead_buffer look_ahead_buffer_inst (
        .clk_i       (clk_i             ),
        .rstn_i      (rstn_i            ),
        .enable_i    (enable_i          ),
        .inst_busy_i (instruction_busy  ),
        .inst_i      (inst_port_i       ),
        .inst_wr_i   (inst_en_i         ),
        .inst_o      (instruction_output),
        .inst_rd_o   (instruction_read  )
    );

    // -------------------------------------------------------------------------
    // Control Coordinator
    // -------------------------------------------------------------------------
    cellrv32_npu_control_coordinator control_coordinator_inst (
        .clk_i                      (clk_i                    ),
        .rstn_i                     (rstn_i                   ),
        .enable_i                   (enable_i                 ),
        .inst_i                     (instruction_output       ),
        .inst_en_i                  (instruction_read         ),
        .busy_o                     (instruction_busy         ),
        .wei_busy_i                 (weight_busy              ),
        .wei_resource_busy_i        (weight_resource_busy     ),
        .wei_inst_o                 (weight_instruction       ),
        .wei_inst_en_o              (weight_instruction_en    ),
        .matrix_busy_i              (matrix_busy              ),
        .matrix_resource_busy_i     (mmu_resource_busy        ),
        .matrix_inst_o              (mmu_instruction          ),
        .matrix_inst_en_o           (mmu_instruction_en       ),
        .activation_busy_i          (activation_busy          ),
        .activation_resource_busy_i (activation_resource_busy ),
        .activation_inst_o          (activation_instruction   ),
        .activation_inst_en_o       (activation_instruction_en),
        .syn_o                      (sync_o                   )
    );

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign busy_o = instruction_busy;

endmodule : cellrv32_npu_core