// ######################################################################################################
// # << CELLRV32 - NPU Accumulator Counter >>                                                           #
// # ************************************************************************************************** #
// # This component is a counter, which uses a DSP block for fast, big adders.                          #
// # The counter can be loaded with any given value and adds the start value every clock cycle.         #
// # The counter will be resetted to the start value, when the counter reaches a value .                #
// # ************************************************************************************************** #

module cellrv32_npu_acc_counter #(
    parameter int COUNTER_WIDTH = 32,
    parameter int MATRIX_WIDTH  = 14
)(
    input  logic                     clk_i      ,
    input  logic                     rstn_i     ,
    input  logic                     enable_i   ,
    input  logic [COUNTER_WIDTH-1:0] start_val_i,
    input  logic                     load_i     ,
    output logic [COUNTER_WIDTH-1:0] count_val_o
);

    logic [COUNTER_WIDTH-1:0] counter_input_reg;
    logic [COUNTER_WIDTH-1:0] start_val_reg;
    logic [COUNTER_WIDTH-1:0] input_pipe_cs, input_pipe_ns;
    logic [COUNTER_WIDTH-1:0] counter_cs, counter_ns;
    logic                     load_reg;

    // Hint for synthesis tool to use DSP block
    (* use_dsp = "yes" *) logic [COUNTER_WIDTH-1:0] counter_ns_dsp;

    // Combinational logic
    assign input_pipe_ns = load_i ? start_val_i : {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};

    assign counter_ns = (counter_cs == ((COUNTER_WIDTH)'(MATRIX_WIDTH - 1) + start_val_reg))
                        ? start_val_reg
                        : counter_cs + counter_input_reg;

    assign count_val_o = counter_cs;

    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            counter_input_reg <= '0;
            input_pipe_cs     <= '0;
            load_reg          <= 1'b0;
        end else if (enable_i) begin
            input_pipe_cs     <= input_pipe_ns;
            counter_input_reg <= input_pipe_cs;
            load_reg          <= load_i;
        end

        // counter_cs: load_i condition uses load_reg (registered load)
        if (load_reg) begin
            counter_cs <= '0;
        end else if (enable_i) begin
            counter_cs <= counter_ns;
        end

        // start_val_reg: updated on load (unregistered)
        if (load_i) begin
            start_val_reg <= start_val_i;
        end
    end

endmodule