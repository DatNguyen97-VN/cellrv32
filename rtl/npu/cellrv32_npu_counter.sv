// ####################################################################################################################
// # << CELLRV32 - NPU Counter >>                                                                                     #
// # **************************************************************************************************************** #
// # This component is a counter, which uses a DSP block for fast, big adders.                                        #
// # The counter starts at 0 and can be reset. If the counter reaches a given end value, an event signal is asserted. #
// # **************************************************************************************************************** #

module cellrv32_npu_counter #(
    parameter int COUNTER_WIDTH = 32  // The width of the counter.
) (
    input  logic                     clk_i        ,
    input  logic                     rstn_i       ,
    input  logic                     enable_i     ,
    
    input  logic [COUNTER_WIDTH-1:0] end_val_i    , // The end value of the counter, at which this component will produce the event signal.
    input  logic                     load_i       , // Signal for the end value.
    
    output logic [COUNTER_WIDTH-1:0] count_val_o  , // The current value of the counter.
    output logic                     count_event_o  // The event, which will be asserted when the end value was reached.
);

    // Internal signals
    (* use_dsp = "yes" *) logic [COUNTER_WIDTH-1:0] counter;
    logic [COUNTER_WIDTH-1:0] end_reg;
    logic event_reg;
    logic event_pipe_reg;
    
    // Output assignments
    assign count_val_o = counter;
    assign count_event_o = event_pipe_reg;
    
    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            counter        <= '0;
            event_reg      <= '0;
            event_pipe_reg <= '0;
        end else if (enable_i) begin
            counter        <= counter + 1'b1;
            event_reg      <= (counter == end_reg);
            event_pipe_reg <= event_reg;
        end
        
        // End value register (independent of rstn_i)
        if (!rstn_i) begin
            end_reg <= '1;
        end else if (load_i) begin
            end_reg <= end_val_i;
        end
    end

endmodule