// ##################################################################################################
// # << CELLRV32 - External Interrupt Controller (XIRQ) >>                                          #
// # ********************************************************************************************** #
// # Simple interrupt controller for platform (processor-external) interrupts. Up to 32 channels    #
// # are supported that get (optionally) prioritized into a single CPU interrupt.                   #
// #                                                                                                #
// # The actual trigger configuration has to be done BEFORE synthesis using the XIRQ_TRIGGER_TYPE   #
// # and XIRQ_TRIGGER_POLARITY generics. These allow to configure channel-independent low-level,    #
// # high-level, falling-edge and rising-edge triggers.                                             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_xirq #(
    parameter int     XIRQ_NUM_CH           = 0,   // number of external IRQ channels (0..32)
    parameter logic[31:0] XIRQ_TRIGGER_TYPE     = '0, // trigger type: 0=level, 1=edge
    parameter logic[31:0] XIRQ_TRIGGER_POLARITY = '0  // trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge
) (
    /* host access */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active, async
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    /* external interrupt lines */
    input  logic [31:0] xirq_i,
    /* CPU interrupt */
    output logic        cpu_irq_o
);
    /* IO space: module base address */
    localparam int hi_abb_c = $clog2(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = $clog2(xirq_size_c); // low address boundary bit

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* control registers */
    logic [XIRQ_NUM_CH-1 : 0] irq_enable;  // r/w: interrupt enable
    logic [XIRQ_NUM_CH-1 : 0] clr_pending; // r/w: clear pending IRQs
    logic [4:0]               irq_src;     // r/w: source IRQ, ACK on any write

    /* interrupt trigger */
    logic [XIRQ_NUM_CH-1 : 0] irq_sync;
    logic [XIRQ_NUM_CH-1 : 0] irq_sync2;
    logic [XIRQ_NUM_CH-1 : 0] irq_trig;

    /* interrupt buffer */
    logic [XIRQ_NUM_CH-1 : 0] irq_buf;
    logic irq_fire;

    /* interrupt source */
    logic [4:0] irq_src_nxt;

    /* arbiter */
    logic irq_run;

    // Sanity Checks -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert ((XIRQ_NUM_CH >= 0) && (XIRQ_NUM_CH <= 32)) else
        $error("CELLRV32 PROCESSOR CONFIG ERROR: Number of XIRQ inputs <XIRQ_NUM_CH> has to be 0..32.");
    end

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == xirq_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {xirq_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    /* write access */
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (rstn_i == 1'b0) begin
            clr_pending <= '0; // clear all pending interrupts
            irq_enable  <= '0;
        end else begin
            clr_pending <= '1;
            if (wren == 1'b1) begin
              if (addr == xirq_enable_addr_c) begin // channel-enable
                 irq_enable <= data_i[XIRQ_NUM_CH-1 : 0];
              end
              //
              if (addr == xirq_pending_addr_c) begin // clear pending IRQs
                 clr_pending <= data_i[XIRQ_NUM_CH-1 : 0]; // set zero to clear pending IRQ
              end
            end
        end
    end

    /* read access */
    always_ff @( posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            ack_o  <= 1'b0;
            data_o <= '0;
        end else begin
            ack_o  <= rden | wren; // bus handshake
            if (rden == 1'b1) begin
                case (addr)
                    xirq_enable_addr_c  : data_o[XIRQ_NUM_CH-1 : 0] <= irq_enable; // channel-enable
                    xirq_pending_addr_c : data_o[XIRQ_NUM_CH-1 : 0] <= irq_buf; // pending IRQs
                    default: begin
                                          data_o[4:0] <= irq_src; // source IRQ
                    end
                endcase
            end else begin
                data_o <= '0;
            end
        end
    end

    // IRQ Trigger -----------------------------------------------------------------
    // -----------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rstn_i) begin : synchronizer
        if (!rstn_i) begin
            irq_sync  <= '0;
            irq_sync2 <= '0;
        end else begin
            irq_sync  <= xirq_i[XIRQ_NUM_CH-1 : 0];
            irq_sync2 <= irq_sync;
        end
    end : synchronizer

    /* trigger select */
    logic[1:0] sel_v;
    //
    always_comb begin
        for (int i = 0; i < XIRQ_NUM_CH; ++i) begin
           sel_v = {XIRQ_TRIGGER_TYPE[i], XIRQ_TRIGGER_POLARITY[i]};
           //
           unique case (sel_v)
            2'b00 : irq_trig[i] = ~ irq_sync[i]; // low-level                      
            2'b01 : irq_trig[i] = irq_sync[i]; // high-level                         
            2'b10 : irq_trig[i] = (~ irq_sync[i]) & irq_sync2[i]; // falling-edge
            2'b11 : irq_trig[i] = irq_sync[i] & (~ irq_sync2[i]); // rising-edge 
            default: begin
                    irq_trig[i] <= 1'b0;
            end
           endcase
        end
    end

    // IRQ Buffer ------------------------------------------------------------------
    // -----------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin
        irq_buf <= (irq_buf | (irq_trig & irq_enable)) & clr_pending;
    end

    /* priority encoder */
    assign irq_src_nxt[$clog2(XIRQ_NUM_CH)-1:0] = $clog2(XIRQ_NUM_CH)'(prior_encoder(XIRQ_NUM_CH, irq_buf));

    /* anyone firing? */
    assign irq_fire = (|irq_buf) ? 1'b1 : 1'b0;

    // IRQ Arbiter -----------------------------------------------------------------
    // -----------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin
        if (rstn_i == 1'b0) begin
            cpu_irq_o <= 1'b0;
            irq_run   <= 1'b0;
            irq_src   <= '0;
        end else begin
            cpu_irq_o <= 1'b0; // default; trigger only once
            if (irq_run == 1'b0) begin // no active IRQ
              irq_src <= irq_src_nxt; // get IRQ source that has highest priority
              if (irq_fire == 1'b1) begin
                cpu_irq_o <= 1'b1;
                irq_run   <= 1'b1;
              end
            end else if ((wren == 1'b1) && (addr == xirq_source_addr_c)) begin // write access to acknowledge
              irq_run <= 1'b0;
            end
        end
    end
endmodule