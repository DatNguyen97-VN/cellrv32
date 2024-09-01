module uart_rx_simple #(
    parameter string name = "",
    parameter real uart_baud_val_c = 0.0
)(
    input logic clk,
    input logic uart_txd
);

    // Internal signals
    logic [4:0] uart_rx_sync = 5'b11111;
    logic uart_rx_busy = 1'b0;
    logic [8:0] uart_rx_sreg = 9'b0;
    real uart_rx_baud_cnt;
    int uart_rx_bitcnt;
    int i;

    // File handle for output
    int file_uart_tx_out;
    initial begin
        file_uart_tx_out = $fopen({"cellrv32.testbench_", name, ".out"}, "w");
    end

    always_ff @(posedge clk) begin
        // "UART" --
        // Synchronizer
        uart_rx_sync <= {uart_rx_sync[3:0], uart_txd};

        // Arbiter
        if (!uart_rx_busy) begin  // Idle
            uart_rx_busy <= 1'b0;
            uart_rx_baud_cnt <= $rtoi(0.5 * uart_baud_val_c);
            uart_rx_bitcnt <= 9;
            if (uart_rx_sync[4:1] == 4'b1100) begin  // Start bit? (falling edge)
                uart_rx_busy <= 1'b1;
            end
        end else begin
            if (uart_rx_baud_cnt <= 0.0) begin
                if (uart_rx_bitcnt == 1) begin
                    uart_rx_baud_cnt <= $rtoi(0.5 * uart_baud_val_c);
                end else begin
                    uart_rx_baud_cnt <= $rtoi(uart_baud_val_c);
                end
                if (uart_rx_bitcnt == 0) begin
                    uart_rx_busy <= 1'b0;  // Done
                    i = $unsigned(uart_rx_sreg[8:1]);

                    if (i < 32 || i > 32 + 95) begin  // Printable char?
                        $display("%s.tx: (%0d)", name, i);  // Print code
                    end else begin
                        $display("%s.tx: %c", name, i);  // Print ASCII
                    end

                    if (i == 10) begin  // Linux line break
                        $fwrite(file_uart_tx_out, "\n");
                    end else if (i != 13) begin  // Remove additional carriage return
                        $fwrite(file_uart_tx_out, "%c", i);
                    end
                end else begin
                    uart_rx_sreg <= {uart_rx_sync[4], uart_rx_sreg[8:1]};
                    uart_rx_bitcnt <= uart_rx_bitcnt - 1;
                end
            end else begin
                uart_rx_baud_cnt <= uart_rx_baud_cnt - 1.0;
            end
        end
    end

endmodule
