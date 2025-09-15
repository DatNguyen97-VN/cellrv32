// ##################################################################################################
// # << CELLRV32 - Bus Switch >>                                                                    #
// # ********************************************************************************************** #
// # Allows to access a single peripheral bus ("p_bus") by two controller ports. Controller port A  #
// # ("ca_bus") has priority over controller port B ("cb_bus").                                     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_busswitch #(
    parameter int PORT_CA_READ_ONLY = 1,
    parameter int PORT_CB_READ_ONLY = 1
)(
    // global control //
    input  logic clk_i,                 // global clock, rising edge
    input  logic rstn_i,                // global reset, low-active, async
    // controller interface a //
    input  logic ca_bus_priv_i,         // current privilege level
    input  logic ca_bus_cached_i,       // set if cached transfer
    input  logic [31:0] ca_bus_addr_i,  // bus access address
    output logic [31:0] ca_bus_rdata_o, // bus read data
    input  logic [31:0] ca_bus_wdata_i, // bus write data
    input  logic [03:0] ca_bus_ben_i,   // byte enable
    input  logic ca_bus_we_i,           // write enable
    input  logic ca_bus_re_i,           // read enable
    output logic ca_bus_ack_o,          // bus transfer acknowledge
    output logic ca_bus_err_o,          // bus transfer error
    // controller interface b //
    input  logic cb_bus_priv_i,         // current privilege level
    input  logic cb_bus_cached_i,       // set if cached transfer
    input  logic [31:0] cb_bus_addr_i,  // bus access address
    output logic [31:0] cb_bus_rdata_o, // bus read data
    input  logic [31:0] cb_bus_wdata_i, // bus write data
    input  logic [03:0] cb_bus_ben_i,   // byte enable
    input  logic cb_bus_we_i,           // write enable
    input  logic cb_bus_re_i,           // read enable
    output logic cb_bus_ack_o,          // bus transfer acknowledge
    output logic cb_bus_err_o,          // bus transfer error
    // peripheral bus //
    output logic p_bus_priv_o,          // current privilege level
    output logic p_bus_cached_o,        // set if cached transfer
    output logic p_bus_src_o,           // access source: 0 = A, 1 = B
    output logic [31:0] p_bus_addr_o,   // bus access address
    input  logic [31:0] p_bus_rdata_i,  // bus read data
    output logic [31:0] p_bus_wdata_o,  // bus write data
    output logic [03:0]  p_bus_ben_o,    // byte enable
    output logic p_bus_we_o,            // write enable
    output logic p_bus_re_o,            // read enable
    input  logic p_bus_ack_i,           // bus transfer acknowledge
    input  logic p_bus_err_i            // bus transfer error
    );

    // access request //
    logic ca_rd_req_buf,  ca_wr_req_buf;
    logic cb_rd_req_buf,  cb_wr_req_buf;
    logic ca_req_current, ca_req_pending;
    logic cb_req_current, cb_req_pending;

    // internal bus lines //
    logic p_bus_we,   p_bus_re;

    // access arbiter //
    typedef enum logic [3:0] {IDLE, A_BUSY, A_RETIRE, B_BUSY, B_RETIRE} arbiter_state_t;
    typedef struct {
        arbiter_state_t state;
        arbiter_state_t state_nxt;
        logic           bus_sel;
        logic           re_trig;
        logic           we_trig;
    } arbiter_t;
    arbiter_t arbiter;

    // Access Arbiter ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : arbiter_sync
        if (rstn_i == 1'b0) begin
            arbiter.state <= IDLE;
            ca_rd_req_buf <= 1'b0;
            ca_wr_req_buf <= 1'b0;
            cb_rd_req_buf <= 1'b0;
            cb_wr_req_buf <= 1'b0;
        end else begin
            arbiter.state <= arbiter.state_nxt;
            // port A requests //
            ca_rd_req_buf <= (ca_rd_req_buf | ca_bus_re_i) & (~(ca_bus_err_o | ca_bus_ack_o));
            ca_wr_req_buf <= (ca_wr_req_buf | ca_bus_we_i) & (~(ca_bus_err_o | ca_bus_ack_o)) & (PORT_CA_READ_ONLY == 1'b0);
            // port B requests //
            cb_rd_req_buf <= (cb_rd_req_buf | cb_bus_re_i) & (~(cb_bus_err_o | cb_bus_ack_o));
            cb_wr_req_buf <= (cb_wr_req_buf | cb_bus_we_i) & (~(cb_bus_err_o | cb_bus_ack_o)) & (PORT_CB_READ_ONLY == 1'b0);
        end
    end : arbiter_sync

    // any current requests? //
    assign ca_req_current = (PORT_CA_READ_ONLY == 1'b0) ? (ca_bus_re_i | ca_bus_we_i) : ca_bus_re_i;
    assign cb_req_current = (PORT_CB_READ_ONLY == 1'b0) ? (cb_bus_re_i | cb_bus_we_i) : cb_bus_re_i;

    // any pending requests? //
    assign ca_req_pending = (PORT_CA_READ_ONLY == 1'b0) ? (ca_rd_req_buf | ca_wr_req_buf) : ca_rd_req_buf;
    assign cb_req_pending = (PORT_CB_READ_ONLY == 1'b0) ? (cb_rd_req_buf | cb_wr_req_buf) : cb_rd_req_buf;

    // FSM //
    always_comb begin : arbiter_comb
        // arbiter defaults //
        arbiter.state_nxt = arbiter.state;
        arbiter.bus_sel   = 1'b0;
        arbiter.we_trig   = 1'b0;
        arbiter.re_trig   = 1'b0;
         // state machine //
         unique case (arbiter.state)
            // port A or B access
            IDLE : begin
                // current request from port A?
                if (ca_req_current) begin
                    arbiter.bus_sel = 1'b0;
                    arbiter.state_nxt = A_BUSY;
                // pending request from port A?
                end else if (ca_req_pending) begin
                    arbiter.bus_sel = 1'b0;
                    arbiter.state_nxt = A_RETIRE;
                // current request from port B?
                end else if (cb_req_current) begin
                    arbiter.bus_sel = 1'b1;
                    arbiter.state_nxt = B_BUSY;
                // pending request from port B?
                end else if (cb_req_pending) begin
                    arbiter.bus_sel = 1'b1;
                    arbiter.state_nxt = B_RETIRE;
                end
            end
            // port A pending access
            A_BUSY : begin
                // access from port A
                arbiter.bus_sel = 1'b0;
                if (p_bus_err_i || p_bus_ack_i) begin
                    arbiter.state_nxt = IDLE;
                end
            end
            // retire port A pending access
            A_RETIRE : begin
                arbiter.bus_sel   = 1'b0; // access from port A
                arbiter.we_trig   = ca_wr_req_buf;
                arbiter.re_trig   = ca_rd_req_buf;
                arbiter.state_nxt = A_BUSY;
            end
            // port B pending access
            B_BUSY : begin
                arbiter.bus_sel = 1'b1;
                if (p_bus_ack_i || p_bus_ack_i) begin
                    if (ca_req_pending || ca_req_current) begin // any request from B?
                        arbiter.state_nxt = A_RETIRE;
                    end else begin
                        arbiter.state_nxt = IDLE;
                    end
                end
            end
            // retire port B pending access
            B_RETIRE : begin
                arbiter.bus_sel   = 1'b1; // access from port B
                arbiter.we_trig   = cb_wr_req_buf;
                arbiter.re_trig   = cb_rd_req_buf;
                arbiter.state_nxt = B_BUSY;
            end
            default: begin // undefined
                arbiter.state_nxt = IDLE;
            end
         endcase
    end : arbiter_comb

    // Peripheral Bus Switch ---------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign p_bus_addr_o = (arbiter.bus_sel == 1'b0) ? ca_bus_addr_i : cb_bus_addr_i;

    assign p_bus_wdata_o = (PORT_CA_READ_ONLY == 1'b1) ? cb_bus_wdata_i :
                           (PORT_CB_READ_ONLY == 1'b1) ? ca_bus_wdata_i :
                           (arbiter.bus_sel == 1'b0)   ? ca_bus_wdata_i : cb_bus_wdata_i;

    assign p_bus_ben_o = (PORT_CA_READ_ONLY == 1'b1) ? cb_bus_ben_i :
                         (PORT_CB_READ_ONLY == 1'b1) ? ca_bus_ben_i :
                         (arbiter.bus_sel == 1'b0)   ? ca_bus_ben_i : cb_bus_ben_i;

    assign p_bus_cached_o = (arbiter.bus_sel == 1'b0) ? ca_bus_cached_i : cb_bus_cached_i;
    assign p_bus_priv_o = (arbiter.bus_sel == 1'b0) ? ca_bus_priv_i : cb_bus_priv_i;

    assign p_bus_we = (arbiter.bus_sel == 1'b0) ? ca_bus_we_i : cb_bus_we_i;
    assign p_bus_re = (arbiter.bus_sel == 1'b0) ? ca_bus_re_i : cb_bus_re_i;
    assign p_bus_we_o = p_bus_we | arbiter.we_trig;
    assign p_bus_re_o = p_bus_re | arbiter.re_trig;

    assign p_bus_src_o = arbiter.bus_sel;

    assign ca_bus_rdata_o = (arbiter.bus_sel == 1'b0) ? p_bus_rdata_i : '0;
    assign cb_bus_rdata_o = (arbiter.bus_sel == 1'b1) ? p_bus_rdata_i : '0;

    assign ca_bus_ack_o = (arbiter.bus_sel == 1'b0) ? p_bus_ack_i : 1'b0;
    assign cb_bus_ack_o = (arbiter.bus_sel == 1'b1) ? p_bus_ack_i : 1'b0;

    assign ca_bus_err_o = (arbiter.bus_sel == 1'b0) ? p_bus_err_i : 1'b0;
    assign cb_bus_err_o = (arbiter.bus_sel == 1'b1) ? p_bus_err_i : 1'b0;

endmodule