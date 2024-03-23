// ##################################################################################################
// # << CELLRV32 - External Bus Interface (WISHBONE) >>                                             #
// # ********************************************************************************************** #
// # All bus accesses from the CPU, which do not target the internal IO region / the internal       #
// # bootloader / the OCD system / the internal instruction or data memories (if implemented), are  #
// # delegated via this Wishbone gateway to the external bus interface. Wishbone accesses can have  #
// # a response latency of up to BUS_TIMEOUT - 1 cycles or an infinity response time if             #
// # BUS_TIMEOUT = 0 (not recommended!)                                                             #
// #                                                                                                #
// # The Wishbone gateway registers all outgoing signals. These signals will remain stable (gated)  #
// # if there is no active Wishbone access. By default, also the incoming signals are registered,   #
// # too. this can be disabled by setting ASYNC_RX = false.                                         #
// #                                                                                                #
// # Even when all processor-internal memories and IO devices are disabled, the EXTERNAL address    #
// # space ENDS at address 0xffff0000 (begin of internal BOOTROM/OCD/IO address space).             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_wishbone #(
    /* Internal instruction memory */
    parameter logic   MEM_INT_IMEM_EN   = 1'b0, // implement processor-internal instruction memory
    parameter int MEM_INT_IMEM_SIZE = 0,    // size of processor-internal instruction memory in bytes
    /* Internal data memory */
    parameter logic   MEM_INT_DMEM_EN   = 1'b0, // implement processor-internal data memory
    parameter int MEM_INT_DMEM_SIZE = 0,    // size of processor-internal data memory in bytes
    /* Interface Configuration */
    parameter int BUS_TIMEOUT       = 0,    // cycles after an UNACKNOWLEDGED bus access triggers a bus fault exception
    parameter logic   PIPE_MODE         = 1'b0, // protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
    parameter logic   BIG_ENDIAN        = 1'b0, // byte order: true=big-endian, false=little-endian
    parameter logic   ASYNC_RX          = 1'b0, // use register buffer for RX data when false
    parameter logic   ASYNC_TX          = 1'b0  // use register buffer for TX data when false
) (
    /* global control */
    input  logic        clk_i , // global clock line
    input  logic        rstn_i, // global reset line, low-active
    /* host access */
    input  logic        src_i,  // access type (0: data, 1:instruction)
    input  logic [31:0] addr_i, // address
    input  logic        rden_i, // read enable
    input  logic        wren_i, // write enable
    input  logic [03:0] ben_i,  // byte write enable
    input  logic [31:0] data_i, // data in
    output logic [31:0] data_o, // data out
    output logic        ack_o,  // transfer acknowledge
    output logic        err_o,  // transfer error
    output logic        tmo_o,  // transfer timeout
    input  logic        priv_i, // current CPU privilege level
    output logic        ext_o,  // active external access
    /* xip configuration */
    input  logic        xip_en_i,   // XIP module enabled
    input  logic [03:0] xip_page_i, // XIP memory page
    /* wishbone interface */
    output logic [02:0] wb_tag_o, // request tag
    output logic [31:0] wb_adr_o, // address
    input  logic [31:0] wb_dat_i, // read data
    output logic [31:0] wb_dat_o, // write data
    output logic        wb_we_o , // read/write
    output logic [03:0] wb_sel_o, // byte enable
    output logic        wb_stb_o, // strobe
    output logic        wb_cyc_o, // valid cycle
    input  logic        wb_ack_i, // transfer acknowledge
    input  logic        wb_err_i  // transfer error
);
    /* timeout enable */
    localparam logic timeout_en_c = (BUS_TIMEOUT != 0); // timeout enabled if BUS_TIMEOUT > 0

    /* access control */
    logic int_imem_acc;
    logic int_dmem_acc;
    logic int_boot_acc;
    logic xip_acc;
    logic xbus_access ;

    /* bus arbiter */
    typedef struct {
        logic        state;
        logic        state_ff;
        logic        we;
        logic [31:0] adr;
        logic [31:0] wdat;
        logic [31:0] rdat;
        logic [03:0] sel;
        logic        ack;
        logic        err;
        logic        tmo;
        logic [index_size_f(BUS_TIMEOUT) : 0] timeout;
        logic        src;
        logic        priv;
    } ctrl_t;
    //
    ctrl_t ctrl;
    logic stb_int;
    logic cyc_int;
    logic [31:0] rdata;

    /* endianness conversion */
    logic [31:0] end_wdata;
    logic [03:0] end_byteen;

    /* async RX gating */
    logic  ack_gated;
    logic [31:0] rdata_gated;

    // Configuration Info ------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    initial begin
        assert (1'b0) else $info(
               "NEORV32 PROCESSOR CONFIG NOTE: Ext. Bus Interface - %s Wishbone protocol, %s %s -endian byte order, %s RX, %s TX",
               cond_sel_string_f(PIPE_MODE, "PIPELINED", "CLASSIC/STANDARD"),
               cond_sel_string_f(BUS_TIMEOUT != 0, "auto-timeout BUS_TIMEOUT cycles), ", "NO auto-timeout, "),
               cond_sel_string_f(BIG_ENDIAN, "BIG", "LITTLE"),
               cond_sel_string_f(ASYNC_RX, "ASYNC ", "registered "),
               cond_sel_string_f(ASYNC_TX, "ASYNC ", "registered "));
        /* no timeout warning */
        assert (BUS_TIMEOUT != 0) else $warning("NEORV32 PROCESSOR CONFIG WARNING! Ext. Bus Interface - NO auto-timeout (can cause permanent CPU stall!).");
    end

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access to processor-internal IMEM or DMEM? */
    assign int_imem_acc = ((addr_i[31 : index_size_f(MEM_INT_IMEM_SIZE)] == imem_base_c[31 : index_size_f(MEM_INT_IMEM_SIZE)]) && (MEM_INT_IMEM_EN == 1'b1)) ? 1'b1 : 1'b0;
    assign int_dmem_acc = ((addr_i[31 : index_size_f(MEM_INT_DMEM_SIZE)] == dmem_base_c[31 : index_size_f(MEM_INT_DMEM_SIZE)]) && (MEM_INT_DMEM_EN == 1'b1)) ? 1'b1 : 1'b0;
    /* access to processor-internal BOOTROM or IO devices? */
    assign int_boot_acc = (addr_i[31:16] == boot_rom_base_c[31:16]) ? 1'b1 : 1'b0; // hacky!
    /* XIP access? */
    assign xip_acc      = ((xip_en_i == 1'b1) && (addr_i[31:28] == xip_page_i)) ? 1'b1 : 1'b0;
    /* actual external bus access? */
    assign xbus_access  = (~ int_imem_acc) & (~ int_dmem_acc) & (~ int_boot_acc) & (~ xip_acc);
    
    // Bus Arbiter -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : bus_arbiter
        if (rstn_i == 1'b0) begin
            ctrl.state    <= 1'b0;
            ctrl.state_ff <= 1'b0;
            ctrl.we       <= 1'b0;
            ctrl.adr      <= '0;
            ctrl.wdat     <= '0;
            ctrl.rdat     <= '0;
            ctrl.sel      <= '0;
            ctrl.timeout  <= '0;
            ctrl.ack      <= 1'b0;
            ctrl.err      <= 1'b0;
            ctrl.tmo      <= 1'b0;
            ctrl.src      <= 1'b0;
            ctrl.priv     <= 1'b0;
        end else begin
            /* defaults */
            ctrl.state_ff <= ctrl.state;
            ctrl.rdat     <= '0; // required for internal output gating
            ctrl.ack      <= 1'b0;
            ctrl.err      <= 1'b0;
            ctrl.tmo      <= 1'b0;
            ctrl.timeout  <= (index_size_f(BUS_TIMEOUT)+1)'(BUS_TIMEOUT);

            /* state machine */
            if (ctrl.state == 1'b0) begin
               // ------------------------------------------------------------
               // IDLE, waiting for host request
               if ((xbus_access == 1'b1) && ((wren_i || rden_i) == 1'b1)) begin // valid external request
                 /* buffer (and gate) all outgoing signals */
                 ctrl.we    <= wren_i;
                 ctrl.adr   <= addr_i;
                 ctrl.src   <= src_i;
                 ctrl.priv  <= priv_i;
                 ctrl.wdat  <= end_wdata;
                 ctrl.sel   <= end_byteen;
                 ctrl.state <= 1'b1;
               end
            end else begin
                // ------------------------------------------------------------
                // BUSY, transfer in progress
                ctrl.rdat <= wb_dat_i;
                if (wb_err_i == 1'b1) begin // abnormal bus termination
                  ctrl.err   <= 1'b1;
                  ctrl.state <= 1'b0;
                end else if ((timeout_en_c == 1'b1) && (|ctrl.timeout == 1'b0)) begin // enabled timeout
                  ctrl.tmo   <= 1'b1;
                  ctrl.state <= 1'b0;
                end else if (wb_ack_i == 1'b1) begin // normal bus termination
                  ctrl.ack   <= 1'b1;
                  ctrl.state <= 1'b0;
                end
                /* timeout counter */
                if (timeout_en_c == 1'b1) begin
                  ctrl.timeout <= ctrl.timeout - 1'b1; // timeout counter
                end
            end
        end
    end : bus_arbiter

    /* active external access */
    assign ext_o = ctrl.state;

    /* endianness conversion */
    assign end_wdata  = (BIG_ENDIAN == 1'b1) ? bswap32_f(data_i) : data_i;
    assign end_byteen = (BIG_ENDIAN == 1'b1) ? 4'(bit_rev_f(ben_i))  : ben_i;

    /* host access */
    assign ack_gated   = (ctrl.state == 1'b1) ? wb_ack_i : 1'b0; // CPU ACK gate for "async" RX
    assign rdata_gated = (ctrl.state == 1'b1) ? wb_dat_i : '0;  // CPU read data gate for "async" RX
    assign rdata       = (ASYNC_RX == 1'b0) ? ctrl.rdat : rdata_gated;

    assign data_o = (BIG_ENDIAN == 1'b0) ? rdata : bswap32_f(rdata); // endianness conversion
    assign ack_o  = (ASYNC_RX == 1'b0) ? ctrl.ack : ack_gated;
    assign err_o  = ctrl.err;
    assign tmo_o  = ctrl.tmo;

    /* wishbone interface */
    assign wb_tag_o[0] = (ASYNC_TX == 1'b1) ? priv_i : ctrl.priv; // 0 = unprivileged (U-mode), 1 = privileged (M-mode)
    assign wb_tag_o[1] = 1'b0; // 0 = secure, 1 = non-secure
    assign wb_tag_o[2] = (ASYNC_TX == 1'b1) ? src_i : ctrl.src; // 0 = data access, 1 = instruction access

    assign stb_int =  (ASYNC_TX == 1'b1) ?  (xbus_access & (wren_i | rden_i))               : (ctrl.state & (~ ctrl.state_ff));
    assign cyc_int =  (ASYNC_TX == 1'b1) ? ((xbus_access & (wren_i | rden_i)) | ctrl.state) :  ctrl.state;

    assign wb_adr_o = (ASYNC_TX == 1'b1) ? addr_i : ctrl.adr;
    assign wb_dat_o = (ASYNC_TX == 1'b1) ? data_i : ctrl.wdat;
    assign wb_we_o  = (ASYNC_TX == 1'b1) ? (wren_i | (ctrl.we & ctrl.state)) : ctrl.we;
    assign wb_sel_o = (ASYNC_TX == 1'b1) ? end_byteen : ctrl.sel;
    assign wb_stb_o = (PIPE_MODE == 1'b1) ? stb_int : cyc_int;
    assign wb_cyc_o = cyc_int;
endmodule