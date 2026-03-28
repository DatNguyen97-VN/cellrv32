// ######################################################################################################
// # << CELLRV32 - NPU Weight Control >>                                                                #
// # ************************************************************************************************** #
// # This component includes the control unit for weight loading.                                       #
// # Weights are read from the weight buffer and get stored sequentially in the matrix multiply unit.   #
// # If the control unit gets to the end of the preweight registers of the matrix multiply unit,        #
// # it restarts loading the next batch of values.                                                      #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_weight_control #(
    parameter MATRIX_WIDTH = 14
)(
    input  logic                            clk_i           ,
    input  logic                            rstn_i          ,
    input  logic                            enable_i        ,
    input  weight_instruction_t             instruction_i   , // The weight instruction to be executed
    input  logic                            instruction_en_i, // Enable for instruction
    output logic                            wei_read_en_o   , // Read enable flag for weight buffer
    output logic [WEIGHT_ADDRESS_WIDTH-1:0] wei_buff_addr_o , // Address for weight buffer read
    output logic                            load_wei_o      , // Load weight flag for matrix multiply unit
    output logic [7:0]                      wei_addr_o      , // Address of the weight for matrix multiply unit
    output logic                            wei_signed_o    , // Determines if the weights are signed or unsigned
    output logic                            busy_o          , // If the control unit is busy, a new instruction shouldn't be fed
    output logic                            resource_busy_o   // The resources are in use and the instruction is not fully finished yet
);

    // Local parameters
    localparam int WEIGHT_COUNTER_WIDTH = $clog2(MATRIX_WIDTH);
    
    // Internal signals
    logic weight_read_en_cs, weight_read_en_ns;
    logic [2:0] load_weight;
    logic weight_signed_cs, weight_signed_ns;
    logic [2:0] signed_pipe;
    
    logic [WEIGHT_COUNTER_WIDTH-1:0] weight_address_cs, weight_address_ns;
    logic [WEIGHT_COUNTER_WIDTH-1:0] weight_address_pipe [5:0];
    
    logic [WEIGHT_ADDRESS_WIDTH-1:0] buffer_pipe_cs, buffer_pipe_ns;
    
    logic [2:0] read_pipe;
    logic signed_reset;
    
    logic running_cs, running_ns;
    logic [2:0] running_pipe;
    
    // Counter signals
    logic length_reset, length_load, length_event;
    logic address_load;
    
    // LENGTH_COUNTER instance
    cellrv32_npu_counter #(
        .COUNTER_WIDTH (LENGTH_WIDTH          )
    ) length_counter_i (
        .clk_i         (clk_i                 ),
        .rstn_i        (length_reset          ),
        .enable_i      (enable_i              ),
        .end_val_i     (instruction_i.calc_len),
        .load_i        (length_load           ),
        .count_val_o   (                      ),
        .count_event_o (length_event          )
    );
    
    // ADDRESS_COUNTER instance
    cellrv32_npu_load_counter #(
        .COUNTER_WIDTH  (WEIGHT_ADDRESS_WIDTH  )
    ) address_counter_i (
        .clk_i          (clk_i                 ),
        .rstn_i         (rstn_i                ),
        .enable_i       (enable_i              ),
        .start_val_i    (instruction_i.wei_addr),
        .load_i         (address_load          ),
        .count_val_o    (buffer_pipe_ns        )
    );
    
    // Combinational logic
    assign wei_read_en_o = weight_read_en_cs & read_pipe[$bits(read_pipe)-1];
    
    // Weight buffer read takes 3 clock cycles
    assign load_wei_o = load_weight[$bits(load_weight)-1];
    
    assign weight_signed_ns = instruction_i.opcode[0];
    assign wei_signed_o = load_weight[$bits(load_weight)-1] & signed_pipe[$bits(signed_pipe)-1];
    
    // Weight address output assignment
    assign wei_addr_o[WEIGHT_COUNTER_WIDTH-1:0] = weight_address_pipe[5];
    generate
        if (BYTE_WIDTH > WEIGHT_COUNTER_WIDTH) begin
            assign wei_addr_o[BYTE_WIDTH-1:WEIGHT_COUNTER_WIDTH] = '0;
        end
    endgenerate
    
    assign wei_buff_addr_o = buffer_pipe_cs;
    assign busy_o = running_cs;
    
    // Resource busy logic
    assign resource_busy_o = running_cs | (|running_pipe);
    
    // Weight address counter logic
    always_comb begin
        if (weight_address_cs == (MATRIX_WIDTH - 1)) begin
            weight_address_ns = '0;
        end else begin
            weight_address_ns = weight_address_cs + 1'b1;
        end
    end
    
    // Control logic
    always_comb begin
        // Default assignments
        running_ns        = running_cs;
        address_load      = 1'b0;
        weight_read_en_ns = 1'b0;
        length_load       = 1'b0;
        length_reset      = 1'b1;
        signed_reset      = 1'b0;
        
        if (!running_cs) begin
            if (instruction_en_i) begin
                running_ns        = 1'b1;
                address_load      = 1'b1;
                weight_read_en_ns = 1'b1;
                length_load       = 1'b1;
                length_reset      = 1'b0;
            end
        end else begin
            if (length_event) begin
                running_ns        = 1'b0;
                weight_read_en_ns = 1'b0;
                signed_reset      = 1'b1;
            end else begin
                running_ns        = 1'b1;
                weight_read_en_ns = 1'b1;
            end
        end
    end
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            weight_read_en_cs      <= 1'b0;
            load_weight            <= '0;
            running_cs             <= 1'b0;
            running_pipe           <= '0;
            weight_address_pipe[0] <= '0;
            weight_address_pipe[1] <= '0;
            weight_address_pipe[2] <= '0;
            weight_address_pipe[3] <= '0;
            weight_address_pipe[4] <= '0;
            weight_address_pipe[5] <= '0;
            buffer_pipe_cs         <= '0;
            signed_pipe            <= '0;
            weight_signed_cs       <= '0;
            read_pipe              <= '0;
            weight_address_cs      <= '0;
        end else begin
            if (enable_i) begin
                weight_read_en_cs      <= weight_read_en_ns;
                load_weight            <= {load_weight[$bits(load_weight)-2:0], wei_read_en_o};
                running_cs             <= running_ns;
                running_pipe           <= {running_pipe[$bits(running_pipe)-2:0], running_cs};
                weight_address_pipe[0] <= weight_address_cs;
                weight_address_pipe[1] <= weight_address_pipe[0];
                weight_address_pipe[2] <= weight_address_pipe[1];
                weight_address_pipe[3] <= weight_address_pipe[2];
                weight_address_pipe[4] <= weight_address_pipe[3];
                weight_address_pipe[5] <= weight_address_pipe[4];
                buffer_pipe_cs         <= buffer_pipe_ns;
                signed_pipe            <= {signed_pipe[$bits(signed_pipe)-2:0], weight_signed_cs};
            end

            if (signed_reset) begin
                read_pipe <= '0;
            end else if (enable_i) begin
                read_pipe <= {read_pipe[$bits(read_pipe)-2:0], weight_read_en_cs};
            end
            
            // Weight address counter with separate reset condition
            if (!length_reset) begin
                weight_address_cs <= '0;
            end else if (enable_i) begin
                weight_address_cs <= weight_address_ns;
            end
            
            // Weight signed with separate load condition
            if (signed_reset) begin
                weight_signed_cs <= 1'b0;
            end else if (length_load && enable_i) begin
                weight_signed_cs <= weight_signed_ns;
            end
        end
    end

endmodule