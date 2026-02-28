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
  import tpu_pkg::*;
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

    // Type definitions
    typedef logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] accumulator_address_array_type [MATRIX_WIDTH-1+2+3:0];
    
    // Counter width calculation
    localparam int WEIGHT_COUNTER_WIDTH = $clog2(MATRIX_WIDTH-1) > 0 ? $clog2(MATRIX_WIDTH-1) : 1;
    
    // Internal signals
    logic buf_read_en_cs, buf_read_en_ns;
    logic mmu_sds_en_cs, mmu_sds_en_ns;
    logic [2:0] mmu_sds_delay_cs, mmu_sds_delay_ns;
    logic mmu_signed_cs, mmu_signed_ns;
    logic [2:0] signed_pipe_cs, signed_pipe_ns;
    
    logic [WEIGHT_COUNTER_WIDTH-1:0] weight_counter_cs, weight_counter_ns;
    logic [2:0] weight_pipe_cs, weight_pipe_ns;
    logic [2:0] activate_weight_delay_cs, activate_weight_delay_ns;
    
    logic acc_enable_cs, acc_enable_ns;
    logic running_cs, running_ns;
    logic [MATRIX_WIDTH-1+2+3:0] running_pipe_cs, running_pipe_ns;
    
    logic accumulate_cs, accumulate_ns;
    logic [BUFFER_ADDRESS_WIDTH-1:0] buf_addr_pipe_cs, buf_addr_pipe_ns;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_addr_pipe_cs, acc_addr_pipe_ns;
    
    logic [2:0] buf_read_pipe_cs, buf_read_pipe_ns;
    logic [2:0] mmu_sds_en_pipe_cs, mmu_sds_en_pipe_ns;
    logic [2:0] acc_en_pipe_cs, acc_en_pipe_ns;
    logic [2:0] accumulate_pipe_cs, accumulate_pipe_ns;
    
    logic acc_load, acc_reset;
    accumulator_address_array_type acc_addr_delay_cs, acc_addr_delay_ns;
    logic [MATRIX_WIDTH-1+2+3:0] accumulate_delay_cs, accumulate_delay_ns;
    logic [MATRIX_WIDTH-1+2+3:0] acc_en_delay_cs, acc_en_delay_ns;
    
    // Counter signals
    logic length_reset, length_load, length_event;
    logic address_load;
    logic weight_reset;
    
    // Instantiate LENGTH_COUNTER
    cellrv32_npu_counter #(
        .COUNTER_WIDTH(LENGTH_WIDTH)
    ) length_counter (
        .clk_i        (clk_i          ),
        .rstn_i       (length_reset   ),
        .enable_i     (enable_i       ),
        .end_val_i    (inst_i.calc_len),
        .load_i       (length_load    ),
        .count_val_o  (               ),
        .count_event_o(length_event   )
    );
    
    // Instantiate ADDRESS_COUNTER for accumulator
    cellrv32_npu_acc_counter  #(
        .COUNTER_WIDTH(ACCUMULATOR_ADDRESS_WIDTH),
        .MATRIX_WIDTH (MATRIX_WIDTH             )
    ) address_counter0 (
        .clk_i      (clk_i           ),
        .rstn_i     (rstn_i          ),
        .enable_i   (enable_i        ),
        .start_val_i(inst_i.acc_addr ),
        .load_i     (address_load    ),
        .count_val_o(acc_addr_pipe_ns)
    );
    
    // Instantiate ADDRESS_COUNTER for buffer
    cellrv32_npu_load_counter #(
        .COUNTER_WIDTH(BUFFER_ADDRESS_WIDTH),
        .MATRIX_WIDTH (MATRIX_WIDTH        )
    ) address_counter1 (
        .clk_i      (clk_i           ),
        .rstn_i     (rstn_i          ),
        .enable_i   (enable_i        ),
        .start_val_i(inst_i.buff_addr),
        .load_i     (address_load    ),
        .count_val_o(buf_addr_pipe_ns)
    );
    
    // Combinational logic
    assign accumulate_ns = inst_i.opcode[1];
    assign buff_sds_addr_o = buf_addr_pipe_cs;
    assign acc_addr_delay_ns[0] = acc_addr_pipe_cs;
    assign acc_addr_o = acc_addr_delay_cs[MATRIX_WIDTH-1+2+3];
    
    // Pipeline assignments
    assign buf_read_pipe_ns[2:1] = buf_read_pipe_cs[1:0];
    assign mmu_sds_en_pipe_ns[2:1] = mmu_sds_en_pipe_cs[1:0];
    assign acc_en_pipe_ns[2:1] = acc_en_pipe_cs[1:0];
    assign accumulate_pipe_ns[2:1] = accumulate_pipe_cs[1:0];
    assign signed_pipe_ns[2:1] = signed_pipe_cs[1:0];
    assign weight_pipe_ns[2:1] = weight_pipe_cs[1:0];
    
    assign buf_read_pipe_ns[0] = buf_read_en_cs;
    assign mmu_sds_en_pipe_ns[0] = mmu_sds_en_cs;
    assign acc_en_pipe_ns[0] = acc_enable_cs;
    assign accumulate_pipe_ns[0] = accumulate_cs;
    assign signed_pipe_ns[0] = mmu_signed_cs;
    assign weight_pipe_ns[0] = !weight_counter_cs;
    
    assign mmu_signed_ns = inst_i.opcode[0];
    
    assign buff_read_en_o         = !buf_read_en_cs ? 1'b0 : buf_read_pipe_cs[2];
    assign mmu_sds_delay_ns[0]    = (mmu_sds_en_cs == 1'b0) ? 1'b0 : mmu_sds_en_pipe_cs[2];
    assign acc_en_delay_ns[0]     = (acc_enable_cs == 1'b0) ? 1'b0 : acc_en_pipe_cs[2];
    assign accumulate_delay_ns[0] = (accumulate_cs == 1'b0) ? 1'b0 : accumulate_pipe_cs[2];
    
    assign mmu_signed_o = (mmu_sds_delay_cs[2] == 1'b0) ? 1'b0 : signed_pipe_cs[2];
    
    assign activate_weight_delay_ns[0] = weight_pipe_cs[2];
    assign activate_weight_delay_ns[2:1] = activate_weight_delay_cs[1:0];
    assign act_wei_o = (mmu_sds_delay_cs[2] == 1'b0) ? 1'b0 : activate_weight_delay_cs[2];
    
    assign acc_en_o = acc_en_delay_cs[MATRIX_WIDTH-1+2+3];
    assign acc_o = accumulate_delay_cs[MATRIX_WIDTH-1+2+3];
    assign mmu_sds_en_o = mmu_sds_delay_cs[2];
    
    assign busy_o = running_cs;
    assign running_pipe_ns[0] = running_cs;
    assign running_pipe_ns[MATRIX_WIDTH+2+3-1:1] = running_pipe_cs[MATRIX_WIDTH+2+2-1:0];
    
    // Delay line assignments
    assign acc_addr_delay_ns[MATRIX_WIDTH-1+2+3:1] = acc_addr_delay_cs[MATRIX_WIDTH-1+2+2:0];
    assign accumulate_delay_ns[MATRIX_WIDTH-1+2+3:1] = accumulate_delay_cs[MATRIX_WIDTH-1+2+2:0];
    assign acc_en_delay_ns[MATRIX_WIDTH-1+2+3:1] = acc_en_delay_cs[MATRIX_WIDTH-1+2+2:0];
    assign mmu_sds_delay_ns[2:1] = mmu_sds_delay_cs[1:0];
    
    // Resource busy logic
    always_comb begin
        logic resource_busy_v;
        resource_busy_v = running_cs;
        for (int i = 0; i < MATRIX_WIDTH+2+3; i++) begin
            resource_busy_v = resource_busy_v | running_pipe_cs[i];
        end
        resource_busy_o = resource_busy_v;
    end
    
    // Weight counter logic
    always_comb begin
        if (weight_counter_cs == (MATRIX_WIDTH-1)) begin
            weight_counter_ns = '0;
        end else begin
            weight_counter_ns = weight_counter_cs + 1'b1;
        end
    end
    
    // Control logic
    always_comb begin
        // Default assignments
        running_ns = running_cs;
        address_load = 1'b0;
        buf_read_en_ns = 1'b0;
        mmu_sds_en_ns = 1'b0;
        acc_enable_ns = 1'b0;
        length_load = 1'b0;
        length_reset = 1'b1;
        acc_load = 1'b0;
        acc_reset = 1'b0;
        weight_reset = 1'b0;
        
        if (!running_cs) begin
            if (inst_en_i) begin
                running_ns = 1'b1;
                address_load = 1'b1;
                buf_read_en_ns = 1'b1;
                mmu_sds_en_ns = 1'b1;
                acc_enable_ns = 1'b1;
                length_load = 1'b1;
                length_reset = 1'b0;
                acc_load = 1'b1;
                weight_reset = 1'b1;
            end
        end else begin
            if (length_event) begin
                running_ns = 1'b0;
                acc_reset = 1'b1;
            end else begin
                running_ns = 1'b1;
                buf_read_en_ns = 1'b1;
                mmu_sds_en_ns = 1'b1;
                acc_enable_ns = 1'b1;
            end
        end
    end
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            buf_read_en_cs           <= 1'b0;
            mmu_sds_en_cs            <= 1'b0;
            acc_enable_cs            <= 1'b0;
            running_cs               <= 1'b0;
            running_pipe_cs          <= '0;
            buf_addr_pipe_cs         <= '0;
            acc_addr_pipe_cs         <= '0;
            acc_addr_delay_cs        <= '{default: '0};
            accumulate_delay_cs      <= '0;
            acc_en_delay_cs          <= '0;
            mmu_sds_delay_cs         <= '0;
            signed_pipe_cs           <= '0;
            weight_pipe_cs           <= '0;
            activate_weight_delay_cs <= '0;
        end else if (enable_i) begin
            buf_read_en_cs           <= buf_read_en_ns;
            mmu_sds_en_cs            <= mmu_sds_en_ns;
            acc_enable_cs            <= acc_enable_ns;
            running_cs               <= running_ns;
            running_pipe_cs          <= running_pipe_ns;
            buf_addr_pipe_cs         <= buf_addr_pipe_ns;
            acc_addr_pipe_cs         <= acc_addr_pipe_ns;
            acc_addr_delay_cs        <= acc_addr_delay_ns;
            accumulate_delay_cs      <= accumulate_delay_ns;
            acc_en_delay_cs          <= acc_en_delay_ns;
            mmu_sds_delay_cs         <= mmu_sds_delay_ns;
            signed_pipe_cs           <= signed_pipe_ns;
            weight_pipe_cs           <= weight_pipe_ns;
            activate_weight_delay_cs <= activate_weight_delay_ns;
        end
        
        if (acc_reset) begin
            accumulate_cs      <= 1'b0;
            buf_read_pipe_cs   <= '0;
            mmu_sds_en_pipe_cs <= '0;
            acc_en_pipe_cs     <= '0;
            accumulate_pipe_cs <= '0;
            mmu_signed_cs      <= 1'b0;
        end else begin
            if (acc_load) begin
                accumulate_cs <= accumulate_ns;
                mmu_signed_cs <= mmu_signed_ns;
            end
            
            if (enable_i) begin
                buf_read_pipe_cs   <= buf_read_pipe_ns;
                mmu_sds_en_pipe_cs <= mmu_sds_en_pipe_ns;
                acc_en_pipe_cs     <= acc_en_pipe_ns;
                accumulate_pipe_cs <= accumulate_pipe_ns;
            end
        end
        
        if (weight_reset) begin
            weight_counter_cs <= '0;
        end else if (enable_i) begin
            weight_counter_cs <= weight_counter_ns;
        end
    end

endmodule