// ##################################################################################################
// # << CELLRV32 - General Purpose Timer (GPTMR) >>                                                 #
// # ********************************************************************************************** #
// # 32-bit timer with configurable clock prescaler. The timer fires an interrupt whenever the      #
// # counter register value reaches the programmed threshold value. The timer can operate in        #
// # single-shot mode (count until it reaches THRESHOLD and stop) or in continuous mode (count      #
// # until it reaches THRESHOLD and auto-reset).                                                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module neorv32_gptmr(
    /* host access */
    input  logic        clk_i,       // global clock line
    input  logic        rstn_i,      // global reset line, low-active, async
    input  logic [31:0] addr_i,      // address
    input  logic        rden_i,      // read enable
    input  logic        wren_i,      // write enable
    input  logic [31:0] data_i,      // data in
    output logic [31:0] data_o,      // data out
    output logic        ack_o,       // transfer acknowledge
    /* clock generator */
    output logic        clkgen_en_o, // enable clock generator
    input  logic [07:0] clkgen_i,
    /* interrupt */
    output logic        irq_o        // timer match interrupt
);
    /* IO space: module base address */
    localparam int hi_abb_c = index_size_f(io_size_c)-1; // high address boundary bit
    localparam int lo_abb_c = index_size_f(gptmr_size_c); // low address boundary bit

    /* control register */
    localparam int ctrl_en_c    = 0; // r/w: timer enable
    localparam int ctrl_prsc0_c = 1; // r/w: clock prescaler select bit 0
    localparam int ctrl_prsc1_c = 2; // r/w: clock prescaler select bit 1
    localparam int ctrl_prsc2_c = 3; // r/w: clock prescaler select bit 2
    localparam int ctrl_mode_c  = 4; // r/w: mode (0=single-shot, 1=continuous)
    //
    logic [4:0] ctrl;

    /* access control */
    logic        acc_en; // module access enable
    logic [31:0] addr;   // access address
    logic        wren;   // word write enable
    logic        rden;   // read enable

    /* timer core */
    typedef struct { 
        logic [31:0] count; // counter register
        logic [31:0] thres; // threshold value
        logic tick;         // clock generator tick
        logic match;        // count == thres
        logic cnt_we;       // write access to count
    } timer_t;
    //
    timer_t timer;

    // Host Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* write access */
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            timer.cnt_we <= 1'b0;
            ctrl         <= '0;
            timer.thres  <= '0;
        end else begin
            timer.cnt_we <= 1'b0; // default
            //
            if (wren == 1'b1) begin
                if (addr == gptmr_ctrl_addr_c) begin // control register
                ctrl[ctrl_en_c]    <= data_i[ctrl_en_c];
                ctrl[ctrl_prsc0_c] <= data_i[ctrl_prsc0_c];
                ctrl[ctrl_prsc1_c] <= data_i[ctrl_prsc1_c];
                ctrl[ctrl_prsc2_c] <= data_i[ctrl_prsc2_c];
                ctrl[ctrl_mode_c]  <= data_i[ctrl_mode_c];
                end 
                // threshold register
                if (addr == gptmr_thres_addr_c) begin 
                  timer.thres <= data_i;
                end
                // counter register
                if (addr == gptmr_count_addr_c) begin 
                  timer.cnt_we <= 1'b1;
                end
            end
        end
    end : write_access

    /* read access */
    always_ff @( posedge clk_i ) begin : read_access
        ack_o  <= rden | wren; // bus access acknowledge
        data_o <= '0;
        //
        if (rden == 1'b1) begin
            unique case (addr[3:2])
                // control register
                2'b00 : begin
                    data_o[ctrl_en_c]    <= ctrl[ctrl_en_c];
                    data_o[ctrl_prsc0_c] <= ctrl[ctrl_prsc0_c];
                    data_o[ctrl_prsc1_c] <= ctrl[ctrl_prsc1_c];
                    data_o[ctrl_prsc2_c] <= ctrl[ctrl_prsc2_c];
                    data_o[ctrl_mode_c]  <= ctrl[ctrl_mode_c];
                end
                // threshold register
                2'b01 : begin
                     data_o <= timer.thres;
                end
                // counter register
                default: begin
                    data_o <= timer.count;
                end
            endcase
        end
    end : read_access

    /* access control */
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == gptmr_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign addr   = {gptmr_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; // word aligned
    assign wren   = acc_en & wren_i;
    assign rden   = acc_en & rden_i;

    // Timer Core --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin
       if (rstn_i == 1'b0) begin
           timer.count <= '0;
       end else begin
          if (timer.cnt_we == 1'b1) begin // write access
             timer.count <= data_i; // data_i will stay unchanged for min. 1 cycle after WREN has returned to low again
          end else if ((ctrl[ctrl_en_c] == 1'b1) && (timer.tick == 1'b1)) begin
              if (timer.match == 1'b1) begin
                // reset counter if continuous mode
                if (ctrl[ctrl_mode_c] == 1'b1) begin
                    timer.count <= '0;
                end
              end else begin
                timer.count <= timer.count + 1;
              end
          end
       end 
    end

    /* counter = threshold? */
    assign timer.match = (timer.count == timer.thres) ? 1'b1 : 1'b0;

    /* clock generator enable */
    assign clkgen_en_o = ctrl[ctrl_en_c];

    /* clock select */
    always @(posedge clk_i) begin
        timer.tick <= clkgen_i[ctrl[ctrl_prsc2_c : ctrl_prsc0_c]];
    end

    /* interrupt */
    always @(posedge clk_i) begin
        irq_o <= ctrl[ctrl_en_c] & timer.match;
    end
endmodule