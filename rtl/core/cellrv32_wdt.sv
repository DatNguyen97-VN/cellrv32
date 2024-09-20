// ##################################################################################################
// # << CELLRV32 - Watch Dog Timer (WDT) >>                                                         #
// # ********************************************************************************************** #
// # "Bark and bite" Watchdog. The WDt will trigger a CPU interrupt when the internal 24-bit        #
// # reaches half of the programmed timeout value ("bark") before generating a system-wide          #
// # hardware reset  when it finally reaches the full timeout value ("bite"). The internal counter  #
// # increments at 1/4096 of the processor's main clock.                                            #
// #                                                                                                #
// # Access to the control register can be permanently inhibited by setting the lock bit. This bit  #
// # can only be cleared by a hardware reset.                                                       #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_wdt (
    /* host access */
    input  logic        clk_i,       // global clock line
    input  logic        rstn_ext_i,  // external reset line, low-active, async
    input  logic        rstn_int_i,  // internal reset line, low-active, async
    input  logic [31:0] addr_i,      // address
    input  logic        rden_i,      // read enable
    input  logic        wren_i,      // write enable
    input  logic [31:0] data_i,      // data in
    output logic [31:0] data_o,      // data out
    output logic        ack_o,       // transfer acknowledge
    /* CPU status */
    input  logic        cpu_debug_i, // CPU is in debug mode
    input  logic        cpu_sleep_i, // CPU is in sleep mode
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [07:0] clkgen_i,
    /* timeout event */
    output logic        irq_o,       // timeout IRQ
    output logic        rstn_o       // timeout reset, low_active, sync
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(wdt_size_c); // low address boundary bit

    /* Control register bits */
    localparam int ctrl_enable_c      =  0; // r/w: WDT enable
    localparam int ctrl_lock_c        =  1; // r/w: lock write access to control register when set
    localparam int ctrl_dben_c        =  2; // r/w: allow WDT to continue operation even when CPU is in debug mode
    localparam int ctrl_sen_c         =  3; // r/w: allow WDT to continue operation even when CPU is in sleep mode
    localparam int ctrl_reset_c       =  4; // -/w: reset WDT if set ("feed" watchdog)
    localparam int ctrl_rcause_c      =  5; // r/-: cause of last system reset: 0=external reset, 1=watchdog timeout
    //
    localparam int ctrl_timeout_lsb_c =  8; // r/w: timeout value LSB
    localparam int ctrl_timeout_msb_c = 31; // r/w: timeout value MSB

    /* access control */
    logic acc_en; // module access enable
    logic wren;
    logic rden;

    /* control register */
    typedef struct {
        logic enable;         // WDT enable
        logic lock;           // lock write access to control register when set
        logic dben;           // allow WDT to continue operation even when CPU is in debug mode
        logic sen;            // allow WDT to continue operation even when CPU is in sleep mode
        logic reset ;         // reset WDT if set ("feed" watchdog)
        logic rcause;         // cause of last system reset: 0=external reset, 1=watchdog timeout
        logic [23:0] timeout; // timeout value
    } ctrl_t;
    //
    ctrl_t ctrl;

    /* prescaler clock generator */
    logic prsc_tick;

    /* timeout counter */
    logic [23:0] cnt;                 // timeout counter
    logic        cnt_started;
    logic        cnt_inc, cnt_inc_ff; // increment counter when set
    logic        timeout_rst;
    logic        timeout_irq;

    /* interrupt & reset generators */
    logic irq_gen_buf, hw_rstn;

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == wdt_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;
    
    /* write access */
    always_ff @( posedge clk_i or negedge rstn_int_i ) begin : write_access
        if (rstn_int_i == 1'b0) begin
            ctrl.enable  <= 1'b0; // disable WDT after reset
            ctrl.lock    <= 1'b0; // unlock after reset
            ctrl.dben    <= 1'b0;
            ctrl.sen     <= 1'b0;
            ctrl.reset   <= 1'b0;
            ctrl.timeout <= '0;
        end else begin
            ctrl.reset <= 1'b0; // default
            if (wren == 1'b1) begin
              ctrl.reset <= data_i[ctrl_reset_c];
              if (ctrl.lock == 1'b0) begin // update configuration only if not locked
                  ctrl.enable  <= data_i[ctrl_enable_c];
                  ctrl.lock    <= data_i[ctrl_lock_c] & ctrl.enable; // lock only if already enabled
                  ctrl.dben    <= data_i[ctrl_dben_c];
                  ctrl.sen     <= data_i[ctrl_sen_c];
                  ctrl.timeout <= data_i[ctrl_timeout_msb_c : ctrl_timeout_lsb_c];
              end
            end
        end
    end : write_access

    /* read access */
    always_ff @( posedge clk_i ) begin : read_access
         ack_o  <= rden | wren;
         data_o <= '0;
         //
         if (rden == 1'b1) begin
           data_o[ctrl_enable_c]                           <= ctrl.enable;
           data_o[ctrl_lock_c]                             <= ctrl.lock;
           data_o[ctrl_dben_c]                             <= ctrl.dben;
           data_o[ctrl_sen_c]                              <= ctrl.sen;
           data_o[ctrl_rcause_c]                           <= ctrl.rcause;
           data_o[ctrl_timeout_msb_c : ctrl_timeout_lsb_c] <= ctrl.timeout;
         end
    end : read_access

    /* reset cause indicator */
    always_ff @(posedge clk_i or negedge rstn_ext_i) begin
        if (rstn_ext_i == 1'b0) begin
          ctrl.rcause <= 1'b0;
        end else begin
          ctrl.rcause <= ctrl.rcause | (~ hw_rstn); // sticky-set on WDT timeout/force
        end
    end

    // Timeout Counter ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin
         cnt_inc_ff  <= cnt_inc;
         cnt_started <= ctrl.enable & (cnt_started | prsc_tick); // set with next clock tick
         if ((ctrl.enable == 1'b0) || (ctrl.reset == 1'b1)) begin // watchdog disabled or reset
           cnt <= '0;
         end else if (cnt_inc_ff == 1'b1) begin
           cnt <= cnt + 1'b1;
         end        
    end

    /* clock generator */
    assign clkgen_en_o = ctrl.enable; // enable clock generator
    assign prsc_tick   = clkgen_i[clk_div4096_c]; // clock enable tick

    /* valid counter increment? */
    assign cnt_inc = ((prsc_tick   == 1'b1) && (cnt_started == 1'b1)  && // clock tick and started
                     ((cpu_debug_i == 1'b0) || (ctrl.dben   == 1'b1)) && // not in debug mode or allowed to run in debug mode
                     ((cpu_sleep_i == 1'b0) || (ctrl.sen    == 1'b1))) ? 1'b1 : 1'b0; // not in sleep mode or allowed to run in sleep mode

    /* timeout detection */
    assign timeout_irq = ((cnt_started == 1'b1) && (cnt == {1'b0 ,ctrl.timeout[23:1]})) ? 1'b1 : 1'b0; // half timeout value
    assign timeout_rst = ((cnt_started == 1'b1) && (cnt == ctrl.timeout[23:0])) ? 1'b1 : 1'b0; // full timeout value

    // Event Generators -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* interrupt */
    always_ff @( posedge clk_i ) begin
        irq_gen_buf <= timeout_irq;
        if ((irq_gen_buf == 1'b0) && (timeout_irq == 1'b1) && // rising edge detector
            (ctrl.enable == 1'b1) && (timeout_rst == 1'b0)) begin // enabled and not a HW reset
          irq_o <= 1'b1;
        end else begin
          irq_o <= 1'b0;
        end
    end

    /* hardware reset */
    always_ff @( posedge clk_i or negedge rstn_int_i ) begin
        if (rstn_int_i == 1'b0)
          hw_rstn <= 1'b1;
        else begin
          if ((ctrl.enable == 1'b1) && (timeout_rst == 1'b1)) begin
             hw_rstn <= 1'b0;
          end else begin
             hw_rstn <= 1'b1;
          end
        end
    end

    /* system wide reset */
    assign rstn_o = hw_rstn;
endmodule