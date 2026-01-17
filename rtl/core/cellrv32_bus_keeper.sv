// ###########################################################################################################
// # << CELLRV32 - Bus Keeper (BUSKEEPER) >>                                                                 #
// # ********************************************************************************************************#
// # This unit monitors the processor-internal bus. If the accessed module does not respond within           #
// # the defined number of cycles (systemVerilog package: max_proc_int_response_time_c) or issues an ERROR   #
// # condition, the BUS KEEPER asserts the error signal to inform the CPU.                                   #
// # ********************************************************************************************************#
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_bus_keeper (
    // bus monitoring
    input  logic [31:0] bus_addr_i, // address
    input  logic        bus_rden_i, // read enable
    input  logic        bus_wren_i, // write enable
    input  logic        bus_ack_i,  // transfer acknowledge from bus system
    input  logic        bus_err_i,  // transfer error from bus system
    input  logic        bus_tmo_i,  // transfer timeout (external interface)
    input  logic        bus_ext_i,  // external bus access
    input  logic        bus_xip_i,  // pending XIP access
    // host access
    input  logic        clk_i,      // global clock line
    input  logic        rstn_i,     // global reset, low-active, async
    input  logic [31:0] addr_i,     // address
    input  logic        rden_i,     // read enable
    input  logic        wren_i,     // write enable
    input  logic [31:0] data_i,     // data in
    output logic [31:0] data_o,     // data out
    output logic        ack_o,      // transfer acknowledge
    output logic        err_o       // transfer error
);
    // IO space: module base address 
    localparam hi_abb_c = $clog2(io_size_c); // high address boundary bit
    localparam lo_abb_c = $clog2(buskeeper_size_c+1); // low address boundary bit
    
    // Control register 
    const int ctrl_err_type_c =  0; // r/-: error type: 0=device error, 1=access timeout
    const int ctrl_err_flag_c = 31; // r/c: bus error encountered, sticky

    // error codes 
    const logic err_device_c  = 1'b0; // device access error
    const logic err_timeout_c = 1'b1; // timeout error

    // sticky error flags 
    logic err_flag;
    logic err_type;

    // access control 
    logic acc_en; // module access enable
    logic wren;   // word write enable
    logic rden;   // read enable

    // timeout counter size 
    localparam cnt_width_c = $clog2(max_proc_int_response_time_c+1);

    // controller
    typedef struct {
        logic pending;
        logic [cnt_width_c-1:0] timeout;
        logic err_type;
        logic bus_err;
        logic ignore;
        logic expired;
    } control_t;
    control_t control;

    // Sanity Check -----------------------------------------------------------------------------
    // ------------------------------------------------------------------------------------------
    initial begin
        assert (max_proc_int_response_time_c >= 2) else $error("CELLRV32 PROCESSOR CONFIG ERROR! Processor-internal bus timeout <max_proc_int_response_time_c> has to >= 2.");
    end

    // Host Access ------------------------------------------------------------------------------
    // ------------------------------------------------------------------------------------------
    // access control
    assign acc_en = (addr_i[hi_abb_c:lo_abb_c] == buskeeper_base_c[hi_abb_c:lo_abb_c]) ? 1'b1 : 1'b0;
    assign wren = acc_en & wren_i;
    assign rden = acc_en & rden_i;

    // write access
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (rstn_i == 1'b0) begin
            err_flag <= 1'b0;
            err_type <= 1'b0;
        end else begin
            if (control.bus_err == 1'b1) begin // sticky error flag
                err_flag <= 1'b1;
                err_type <= control.err_type;
            end else if (wren || rden) begin // clear on read or write access
                err_flag <= 1'b0;
            end
        end
    end

    // read access
    always_ff @(posedge clk_i) begin
        ack_o <= wren | rden; // bus handshake
        data_o <= '0;
        if (rden) begin
            data_o[ctrl_err_type_c] <= err_type;
            data_o[ctrl_err_flag_c] <= err_flag;
        end
    end

    // Monitor -----------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : keeper_control
        if (rstn_i == 1'b0) begin
            control.pending  <= 1'b0;
            control.bus_err  <= 1'b0;
            control.err_type <= 1'b0;
            control.timeout  <= '0;
            control.ignore   <= 1'b0;
        end else begin
            // defaults
            control.bus_err <= 1'b0;
            // IDLE
            if (control.pending == 1'b0) begin
                control.timeout <= max_proc_int_response_time_c - 4'd1;
                control.ignore <= 1'b0;
                if (bus_rden_i || bus_wren_i) begin
                    control.pending <= 1'b1;
                end
            // PENDING
            end else begin
                // counter timer
                if (control.expired == 1'b0) begin
                    control.timeout <= control.timeout - 1'b1;
                end
                // bus keeper shall ignore internal timeout during this access (because it's "external")
                control.ignore <= control.ignore | (bus_ext_i | bus_xip_i);
                // response handling
                if (bus_err_i == 1'b1) begin // error termination by bus system
                    control.err_type <= err_device_c; // device error
                    control.bus_err  <= 1'b1;
                    control.pending  <= 1'b0;
                    // valid INTERNAL access timeout
                    // EXTERNAL access timeout
                end else if (((control.expired == 1'b1) && (control.ignore == 1'b0)) || (bus_tmo_i == 1'b1)) begin
                    control.err_type <= err_timeout_c; // timeout error
                    control.bus_err  <= 1'b1;
                    control.pending  <= 1'b0;
                end else if (bus_ack_i == 1'b1) begin // normal termination by bus system
                    control.err_type <= 1'b0; // don't care
                    control.bus_err  <= 1'b0;
                    control.pending  <= 1'b0;
                end
            end
        end
    end : keeper_control

    // timeout counter expired?
    assign control.expired = (|control.timeout == 1'b0) ? 1'b1 : 1'b0;

    // signal bus error to CPU
    assign err_o = control.bus_err;

endmodule