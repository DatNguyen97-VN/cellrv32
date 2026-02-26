// ######################################################################################################
// # << CELLRV32 - NPU Activation Control >>                                                            #
// # ************************************************************************************************** #
// # This component includes the control unit for the activation operation.                             #
// # This unit controls the data flow from the accumulators, pipes it through the activation component  #
// # and stores the results back in the unified buffer.                                                 #
// # Instructions will be executed delayed, so a previous matrix multiply can be finished just in time. #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import tpu_pkg::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_activation_control #(
    parameter int MATRIX_WIDTH = 14
) (
    input  logic                                 clk_i            ,
    input  logic                                 rstn_i           ,
    input  logic                                 enable_i         ,
    input  instruction_t                         inst_i           , // The activation instruction to be executed.
    input  logic                                 inst_en_i        , // enable_i for instruction.
    output logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_act_addr_o   , // Address for the accumulators
    output logic [ACTIVATION_BIT_WIDTH-1:0]      activation_func_o, // The type of activation function to be calculated.
    output logic                                 signed_unsigned_o, // Determines if the input and output is signed or unsigned.
    output logic [BUFFER_ADDRESS_WIDTH-1:0]      act_buff_addr_o  , // Address for the unified buffer.
    output logic                                 buff_wr_en_o     , // Write enable_i flag for the unified buffer.
    output logic                                 busy_o           , // If the control unit is busy_o, a new instruction shouldn't be fed.
    output logic                                 resource_busy_o    // The resources are in use and the instruction is not fully finished yet.
);

    // CONTROL: 3 clock cycles
    // MATRIX_MULTIPLY_UNIT: MATRIX_WIDTH+2 clock cycles
    // REGISTER_FILE: 7 clock cycles
    // ACTIVATION: 3 clock cycles
    localparam int TOTAL_DELAY = 3 + MATRIX_WIDTH + 2 + 7 + 3;
    localparam int ACC_DELAY = 3 + MATRIX_WIDTH + 2;
    localparam int ACT_DELAY = 3 + MATRIX_WIDTH + 2 + 7;
    
    // Type definitions
    typedef logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] accumulator_address_t;
    typedef logic [ACTIVATION_BIT_WIDTH-1:0] activation_bit_t;
    typedef logic [BUFFER_ADDRESS_WIDTH-1:0] buffer_address_t;
    
    // Array type definitions
    typedef accumulator_address_t acc_addr_array_t [ACC_DELAY-1:0];
    typedef activation_bit_t act_bit_array_t [ACT_DELAY-1:0];
    typedef buffer_address_t buf_addr_array_t [TOTAL_DELAY-1:0];
    
    // Internal signals
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_to_act_addr_cs, acc_to_act_addr_ns;
    logic [BUFFER_ADDRESS_WIDTH-1:0] act_to_buf_addr_cs, act_to_buf_addr_ns;
    logic [ACTIVATION_BIT_WIDTH-1:0] activation_function_cs, activation_function_ns;
    logic signed_not_unsigned_cs, signed_not_unsigned_ns;
    logic buf_write_en_cs, buf_write_en_ns;
    logic running_cs, running_ns;
    
    logic [TOTAL_DELAY-1:0] running_pipe_cs, running_pipe_ns;
    
    logic act_load, act_reset;
    
    // Delay registers
    logic [2:0] buf_write_en_delay_cs, buf_write_en_delay_ns;
    logic [2:0] signed_delay_cs, signed_delay_ns;
    
    logic [ACTIVATION_BIT_WIDTH-1:0] activation_pipe0_cs, activation_pipe0_ns;
    logic [ACTIVATION_BIT_WIDTH-1:0] activation_pipe1_cs, activation_pipe1_ns;
    logic [ACTIVATION_BIT_WIDTH-1:0] activation_pipe2_cs, activation_pipe2_ns;
    
    // Counter signals
    logic length_reset, length_load, length_event;
    logic address_load;
    
    // Delay arrays
    acc_addr_array_t acc_address_delay_cs, acc_address_delay_ns;
    act_bit_array_t activation_delay_cs, activation_delay_ns;
    logic [ACT_DELAY-1:0] s_not_u_delay_cs, s_not_u_delay_ns;
    buf_addr_array_t act_to_buf_delay_cs, act_to_buf_delay_ns;
    logic [TOTAL_DELAY-1:0] write_en_delay_cs, write_en_delay_ns;
    
    // Counter instances
    cellrv32_npu_counter #(
        .COUNTER_WIDTH (LENGTH_WIDTH)
    ) LENGTH_COUNTER_i (
        .clk_i         (clk_i          ),
        .rstn_i        (rstn_i         ),
        .enable_i      (enable_i       ),
        .end_val_i     (inst_i.calc_len),
        .load_i        (length_load    ),
        .count_val_o   (               ),
        .count_event_o (length_event   )
    );
    
    cellrv32_npu_load_counter #(
        .COUNTER_WIDTH (ACCUMULATOR_ADDRESS_WIDTH)
    ) ADDRESS_COUNTER0_i (
        .clk_i       (clk_i             ),
        .rstn_i      (rstn_i            ),
        .enable_i    (enable_i          ),
        .start_val_i (inst_i.acc_addr   ),
        .load_i      (address_load      ),
        .count_val_o (acc_to_act_addr_ns)
    );
    
    cellrv32_npu_load_counter #(
        .COUNTER_WIDTH (BUFFER_ADDRESS_WIDTH)
    ) ADDRESS_COUNTER1_i (
        .clk_i       (clk_i             ),
        .rstn_i      (rstn_i            ),
        .enable_i    (enable_i          ),
        .start_val_i (inst_i.buff_addr  ),
        .load_i      (address_load      ),
        .count_val_o (act_to_buf_addr_ns)
    );
    
    // Combinational logic
    assign signed_not_unsigned_ns = inst_i.opcode[4];
    assign activation_function_ns = inst_i.opcode[3:0];
    
    // Shift register logic
    always_comb begin
        // Shift delay arrays
        acc_address_delay_ns[ACC_DELAY-1:1]  = acc_address_delay_cs[ACC_DELAY-2:0];
        activation_delay_ns[ACT_DELAY-1:1]   = activation_delay_cs[ACT_DELAY-2:0];
        s_not_u_delay_ns[ACT_DELAY-1:1]      = s_not_u_delay_cs[ACT_DELAY-2:0];
        act_to_buf_delay_ns[TOTAL_DELAY-1:1] = act_to_buf_delay_cs[TOTAL_DELAY-2:0];
        write_en_delay_ns[TOTAL_DELAY-1:1]   = write_en_delay_cs[TOTAL_DELAY-2:0];
        
        // Input to delay arrays
        acc_address_delay_ns[0] = acc_to_act_addr_cs;
        act_to_buf_delay_ns[0]  = act_to_buf_addr_cs;
        
        // Conditional assignments
        activation_delay_ns[0] = (activation_function_cs == 4'b0000) ? 4'b0000 : activation_pipe2_cs;
        s_not_u_delay_ns[0]    = (signed_not_unsigned_cs == 1'b0) ? 1'b0 : signed_delay_cs[2];
        write_en_delay_ns[0]   = (buf_write_en_cs == 1'b0) ? 1'b0 : buf_write_en_delay_cs[2];
        
        // Running pipe
        running_pipe_ns[0] = running_cs;
        running_pipe_ns[TOTAL_DELAY-1:1] = running_pipe_cs[TOTAL_DELAY-2:0];
        
        // Buffer write enable_i delay
        buf_write_en_delay_ns[0]   = buf_write_en_cs;
        buf_write_en_delay_ns[2:1] = buf_write_en_delay_cs[1:0];
        
        // Signed delay
        signed_delay_ns[0]   = signed_not_unsigned_cs;
        signed_delay_ns[2:1] = signed_delay_cs[1:0];
        
        // Activation pipes
        activation_pipe0_ns = activation_function_cs;
        activation_pipe1_ns = activation_pipe0_cs;
        activation_pipe2_ns = activation_pipe1_cs;
    end
    
    // Output assignments
    assign acc_act_addr_o    = acc_address_delay_cs[ACC_DELAY-1];
    assign activation_func_o = activation_delay_cs[ACT_DELAY-1];
    assign signed_unsigned_o = s_not_u_delay_cs[ACT_DELAY-1];
    assign act_buff_addr_o   = act_to_buf_delay_cs[TOTAL_DELAY-1];
    assign buff_wr_en_o      = write_en_delay_cs[TOTAL_DELAY-1];
    assign busy_o            = running_cs;
    
    // Resource busy_o logic
    always_comb begin
        logic resource_busy_v;
        resource_busy_v = running_cs;
        for (int i = 0; i < TOTAL_DELAY; i++) begin
            resource_busy_v = resource_busy_v | running_pipe_cs[i];
        end
        resource_busy_o = resource_busy_v;
    end
    
    // Control logic
    always_comb begin
        // Default values
        running_ns      = 1'b0;
        address_load    = 1'b0;
        buf_write_en_ns = 1'b0;
        length_load     = 1'b0;
        length_reset    = 1'b0;
        act_load        = 1'b0;
        act_reset       = 1'b0;
        //
        if (!running_cs) begin
            if (inst_en_i) begin
                running_ns      = 1'b1;
                address_load    = 1'b1;
                buf_write_en_ns = 1'b1;
                length_load     = 1'b1;
                act_load        = 1'b1;
            end else begin
                length_reset    = 1'b1;
            end
        end else begin
            if (length_event) begin
                length_reset    = 1'b1;
                act_reset       = 1'b1;
            end else begin
                running_ns      = 1'b1;
                buf_write_en_ns = 1'b1;
                length_reset    = 1'b1;
            end
        end
    end
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            buf_write_en_cs       <= 1'b0;
            running_cs            <= 1'b0;
            running_pipe_cs       <= '0;
            acc_to_act_addr_cs    <= '0;
            act_to_buf_addr_cs    <= '0;
            buf_write_en_delay_cs <= '0;
            signed_delay_cs       <= '0;
            activation_pipe0_cs   <= '0;
            activation_pipe1_cs   <= '0;
            activation_pipe2_cs   <= '0;
            // Delay registers
            acc_address_delay_cs  <= '{default: '0};
            activation_delay_cs   <= '{default: '0};
            s_not_u_delay_cs      <= '0;
            act_to_buf_delay_cs   <= '{default: '0};
            write_en_delay_cs     <= '0;
        end else if (enable_i) begin
            buf_write_en_cs       <= buf_write_en_ns;
            running_cs            <= running_ns;
            running_pipe_cs       <= running_pipe_ns;
            acc_to_act_addr_cs    <= acc_to_act_addr_ns;
            act_to_buf_addr_cs    <= act_to_buf_addr_ns;
            buf_write_en_delay_cs <= buf_write_en_delay_ns;
            signed_delay_cs       <= signed_delay_ns;
            activation_pipe0_cs   <= activation_pipe0_ns;
            activation_pipe1_cs   <= activation_pipe1_ns;
            activation_pipe2_cs   <= activation_pipe2_ns;
            // Delay registers
            acc_address_delay_cs  <= acc_address_delay_ns;
            activation_delay_cs   <= activation_delay_ns;
            s_not_u_delay_cs      <= s_not_u_delay_ns;
            act_to_buf_delay_cs   <= act_to_buf_delay_ns;
            write_en_delay_cs     <= write_en_delay_ns;
        end
        
        // Activation function and signed registers with separate rstn_i
        if (act_reset) begin
            activation_function_cs <= '0;
            signed_not_unsigned_cs <= 1'b0;
        end else if (act_load) begin
            activation_function_cs <= activation_function_ns;
            signed_not_unsigned_cs <= signed_not_unsigned_ns;
        end
    end

endmodule