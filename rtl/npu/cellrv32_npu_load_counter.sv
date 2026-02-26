// ######################################################################################################
// # << CELLRV32 - NPU Load Counter >>                                                                  #
// # ************************************************************************************************** #
// # This component is a counter, which uses a DSP block for fast, big adders.                          #
// # The counter can be loaded with any given value and adds the start value every clock cycle.         #
// # ************************************************************************************************** #

module cellrv32_npu_load_counter #(
    parameter COUNTER_WIDTH = 32,
    parameter MATRIX_WIDTH = 14
) (
    input  logic                     clk_i      ,
    input  logic                     rstn_i     ,
    input  logic                     enable_i   ,
    
    input  logic [COUNTER_WIDTH-1:0] start_val_i, // The given start value of the counter.
    input  logic                     load_i     , // load_i flag for the start value.
    
    output logic [COUNTER_WIDTH-1:0] count_val_o  // The current value of the counter.
);

    // Internal signals - current state
    logic [COUNTER_WIDTH-1:0] counter_input_cs;
    logic [COUNTER_WIDTH-1:0] input_pipe_cs;
    logic [COUNTER_WIDTH-1:0] counter_cs;
    logic                     load_cs;
    
    // Internal signals - next state
    logic [COUNTER_WIDTH-1:0] counter_input_ns;
    logic [COUNTER_WIDTH-1:0] input_pipe_ns;
    (* use_dsp = "yes" *) logic [COUNTER_WIDTH-1:0] counter_ns;
    logic                     load_ns;
    
    // Combinational logic
    assign load_ns = load_i;
    
    // Input pipe logic: load_i start_val_i when load_i is asserted, otherwise load_i 1
    assign input_pipe_ns = load_i ? start_val_i : {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
    assign counter_input_ns = input_pipe_cs;
    
    // Counter addition logic
    assign counter_ns = counter_cs + counter_input_cs;
    
    // Output assignment
    assign count_val_o = counter_cs;
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            counter_input_cs <= '0;
            input_pipe_cs    <= '0;
            load_cs          <= '0;
        end else begin
            if (enable_i) begin
                counter_input_cs <= counter_input_ns;
                input_pipe_cs    <= input_pipe_ns;
                load_cs          <= load_ns;
            end
        end
        
        // Counter register with separate rstn_i condition
        if (load_cs) begin
            counter_cs <= '0;
        end else begin
            if (enable_i) begin
                counter_cs <= counter_ns;
            end
        end
    end

endmodule