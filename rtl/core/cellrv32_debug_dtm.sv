// ##################################################################################################
// # << CELLRV32 - RISC-V Debug Transport Module (DTM) >>                                           #
// # ********************************************************************************************** #
// # Provides a JTAG-compatible TAP to access the DMI register interface.                           #
// # Compatible to the RISC-V debug specification version 1.0.                                      #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_debug_dtm #(
    parameter logic[03:0] IDCODE_VERSION = '0, // version
    parameter logic[15:0] IDCODE_PARTID  = '0, // part number
    parameter logic[10:0] IDCODE_MANID   = '0  // manufacturer id
) (
    /* global control */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active
    /* jtag connection */
    input  logic        jtag_trst_i,
    input  logic        jtag_tck_i,
    input  logic        jtag_tdi_i,
    output logic        jtag_tdo_o,
    input  logic        jtag_tms_i,
    /* debug module interface (DMI) */
    output logic        dmi_req_valid_o,
    input  logic        dmi_req_ready_i, // DMI is allowed to make new requests when set
    output logic [05:0] dmi_req_address_o,
    output logic [31:0] dmi_req_data_o,
    output logic [01:0] dmi_req_op_o,
    input  logic        dmi_rsp_valid_i, // response valid when set
    output logic        dmi_rsp_ready_o, // ready to receive response
    input  logic [31:0] dmi_rsp_data_i,
    input  logic [01:0] dmi_rsp_op_i
);
    /* DMI Configuration (fixed!) */
    localparam logic[02:0] dmi_idle_c    = 3'b000; // no idle cycles required
    localparam logic[03:0] dmi_version_c = 4'b0001; // debug spec. version (0.13 & 1.0)
    localparam logic[05:0] dmi_abits_c   = 6'b000110; // number of DMI address bits (6)
    
    /* tap JTAG signal synchronizer */
    typedef struct {
        /* internal */
        logic [2:0] trst_ff;
        logic [2:0] tck_ff;
        logic [2:0] tdi_ff;
        logic [2:0] tms_ff;
        /* external */
        logic trst;
        logic tck_rising ;
        logic tck_falling;
        logic tdi;
        logic tms;
    } tap_sync_t;
    //
    tap_sync_t tap_sync;

    /* tap controller - fsm */
    typedef enum { LOGIC_RESET, DR_SCAN, DR_CAPTURE, DR_SHIFT, DR_EXIT1, DR_PAUSE, DR_EXIT2, DR_UPDATE,
                      RUN_IDLE, IR_SCAN, IR_CAPTURE, IR_SHIFT, IR_EXIT1, IR_PAUSE, IR_EXIT2, IR_UPDATE } tap_ctrl_state_t;
    //
    tap_ctrl_state_t tap_ctrl_state;

    /* update trigger */
    typedef struct {
        logic valid;      
        logic is_update;   
        logic is_update_ff;
    } dr_update_trig_t;
    //
    dr_update_trig_t dr_update_trig;

    /* tap registers */
    typedef struct {
        logic [04:0]         ireg;
        logic                bypass;
        logic [31:0]         idcode;
        logic [31:0]         dtmcs, dtmcs_nxt;
        logic [(6+32+2)-1:0] dmi, dmi_nxt; // 6-bit address + 32-bit data + 2-bit operation
    } tap_reg_t;
    //
    tap_reg_t tap_reg;

    /* debug module interface */
    typedef enum { DMI_IDLE, DMI_READ_WAIT, DMI_READ, DMI_READ_BUSY,
                   DMI_WRITE_WAIT, DMI_WRITE, DMI_WRITE_BUSY } dmi_ctrl_state_t;
    //
    typedef struct {
        dmi_ctrl_state_t state;
        logic            dmihardreset;
        logic            dmireset;
        logic [01:0]     rsp; // sticky response status
        logic [31:0]     rdata;
        logic [31:0]     wdata;
        logic [05:0]     addr;
    } dmi_ctrl_t;
    //
    dmi_ctrl_t dmi_ctrl;

    // JTAG Input Synchronizer -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : tap_synchronizer
        if (rstn_i == 1'b0) begin
            tap_sync.trst_ff <= '0;
            tap_sync.tck_ff  <= '0;
            tap_sync.tdi_ff  <= '0;
            tap_sync.tms_ff  <= '0;
        end else begin
            tap_sync.trst_ff <= {tap_sync.trst_ff[1:0], jtag_trst_i};
            tap_sync.tck_ff  <= {tap_sync.tck_ff[1:0], jtag_tck_i};
            tap_sync.tdi_ff  <= {tap_sync.tdi_ff[1:0], jtag_tdi_i};
            tap_sync.tms_ff  <= {tap_sync.tms_ff[1:0], jtag_tms_i};
        end
    end : tap_synchronizer

    /* JTAG reset */
    assign tap_sync.trst = (tap_sync.trst_ff[2:1] == 2'b00) ? 1'b0 : 1'b1;

    /* JTAG clock edge */
    assign tap_sync.tck_rising  = (tap_sync.tck_ff[2:1] == 2'b01) ? 1'b1 : 1'b0;
    assign tap_sync.tck_falling = (tap_sync.tck_ff[2:1] == 2'b10) ? 1'b1 : 1'b0;

    /* JTAG test mode select */
    assign tap_sync.tms = tap_sync.tms_ff[2];

    /* JTAG serial data input */
    assign tap_sync.tdi = tap_sync.tdi_ff[2];

    // Tap Control FSM ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : tap_control
        if (rstn_i == 1'b0) begin
            tap_ctrl_state <= LOGIC_RESET;
        end else begin
            if (tap_sync.trst == 1'b0) begin // reset
                tap_ctrl_state <= LOGIC_RESET;
            // clock pulse (evaluate TMS on the rising edge of TCK)
            end else if (tap_sync.tck_rising == 1'b1) begin
                unique case (tap_ctrl_state) // JTAG state machine
                    LOGIC_RESET : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= RUN_IDLE;   else tap_ctrl_state <= LOGIC_RESET;
                    RUN_IDLE    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= RUN_IDLE;   else tap_ctrl_state <= DR_SCAN;    
                    DR_SCAN     : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_CAPTURE; else tap_ctrl_state <= IR_SCAN;    
                    DR_CAPTURE  : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_SHIFT;   else tap_ctrl_state <= DR_EXIT1;   
                    DR_SHIFT    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_SHIFT;   else tap_ctrl_state <= DR_EXIT1;   
                    DR_EXIT1    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_PAUSE;   else tap_ctrl_state <= DR_UPDATE;  
                    DR_PAUSE    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_PAUSE;   else tap_ctrl_state <= DR_EXIT2;   
                    DR_EXIT2    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= DR_SHIFT;   else tap_ctrl_state <= DR_UPDATE;  
                    DR_UPDATE   : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= RUN_IDLE;   else tap_ctrl_state <= DR_SCAN;    
                    IR_SCAN     : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_CAPTURE; else tap_ctrl_state <= LOGIC_RESET;
                    IR_CAPTURE  : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_SHIFT;   else tap_ctrl_state <= IR_EXIT1;   
                    IR_SHIFT    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_SHIFT;   else tap_ctrl_state <= IR_EXIT1;   
                    IR_EXIT1    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_PAUSE;   else tap_ctrl_state <= IR_UPDATE;  
                    IR_PAUSE    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_PAUSE;   else tap_ctrl_state <= IR_EXIT2;   
                    IR_EXIT2    : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= IR_SHIFT;   else tap_ctrl_state <= IR_UPDATE;  
                    IR_UPDATE   : if (tap_sync.tms == 1'b0)  tap_ctrl_state <= RUN_IDLE;   else tap_ctrl_state <= DR_SCAN;    
                    default: begin
                        tap_ctrl_state <= LOGIC_RESET;
                    end
                endcase
            end
        end
    end : tap_control

    // Tap Register Access -----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : reg_access
        if (rstn_i == 1'b0) begin
            tap_reg.ireg   <= '0;
            tap_reg.idcode <= '0;
            tap_reg.dtmcs  <= '0;
            tap_reg.dmi    <= '0;
            tap_reg.bypass <= 1'b0;
            jtag_tdo_o     <= 1'b0;
        end else begin
            /* serial data input: instruction register */
            if ((tap_ctrl_state == LOGIC_RESET) || (tap_ctrl_state == IR_CAPTURE)) begin // preload phase
              tap_reg.ireg <= 5'b00001; // IDCODE
            end else if (tap_ctrl_state == IR_SHIFT) begin // access phase
              if (tap_sync.tck_rising == 1'b1) begin // [JTAG-SYNC] evaluate TDI on rising edge of TCK
                tap_reg.ireg <= {tap_sync.tdi, tap_reg.ireg[$bits(tap_reg.ireg)-1 : 1]};
              end
            end

            /* serial data input: data register */
            if (tap_ctrl_state == DR_CAPTURE) begin // preload phase
                unique case (tap_reg.ireg)
                    5'b00001 : tap_reg.idcode <= {IDCODE_VERSION, IDCODE_PARTID, IDCODE_MANID, 1'b1}; // identifier (LSB has to be set)
                    5'b10000 : tap_reg.dtmcs  <= tap_reg.dtmcs_nxt; // status register
                    5'b10001 : tap_reg.dmi    <= tap_reg.dmi_nxt; // register interface
                    default: begin
                        tap_reg.bypass <= 1'b0; // pass through
                    end
                endcase
            end else if (tap_ctrl_state == DR_SHIFT) begin // access phase
                if (tap_sync.tck_rising == 1'b1) begin // [JTAG-SYNC] evaluate TDI on rising edge of TCK
                    unique case (tap_reg.ireg)
                        5'b00001 : tap_reg.idcode <= {tap_sync.tdi, tap_reg.idcode[$bits(tap_reg.idcode)-1 : 1]};
                        5'b10000 : tap_reg.dtmcs  <= {tap_sync.tdi, tap_reg.dtmcs[$bits(tap_reg.dtmcs)-1 : 1]};
                        5'b10001 : tap_reg.dmi    <= {tap_sync.tdi, tap_reg.dmi[$bits(tap_reg.dmi)-1 : 1]};
                        default: begin
                            tap_reg.bypass <= tap_sync.tdi;
                        end
                    endcase
                end
            end

            /* serial data output */
            if (tap_sync.tck_falling == 1'b1) begin // [JTAG-SYNC] update TDO on falling edge of TCK
                if (tap_ctrl_state == IR_SHIFT) begin
                    jtag_tdo_o <= tap_reg.ireg[0];
                end else begin
                    unique case (tap_reg.ireg)
                        5'b00001 : jtag_tdo_o <= tap_reg.idcode[0];
                        5'b10000 : jtag_tdo_o <= tap_reg.dtmcs[0]; 
                        5'b10001 : jtag_tdo_o <= tap_reg.dmi[0];   
                        default: begin
                            jtag_tdo_o <= tap_reg.bypass;
                        end
                    endcase
                end
            end
        end
    end : reg_access

    /* DTM Control and Status Register (dtmcs) */
    assign tap_reg.dtmcs_nxt[31 : 18] = '0; // unused
    assign tap_reg.dtmcs_nxt[17]      = 1'b0; // dmihardreset, always reads as zero
    assign tap_reg.dtmcs_nxt[16]      = 1'b0; // dmireset, always reads as zero
    assign tap_reg.dtmcs_nxt[15]      = 1'b0; // unused
    assign tap_reg.dtmcs_nxt[14 : 12] = dmi_idle_c; // minimum number of idle cycles
    assign tap_reg.dtmcs_nxt[11 : 10] = tap_reg.dmi_nxt[1:0]; // dmistat
    assign tap_reg.dtmcs_nxt[09 : 04] = dmi_abits_c; // number of DMI address bits
    assign tap_reg.dtmcs_nxt[03 : 00] = dmi_version_c; // version

    /* DMI register read access */
    assign tap_reg.dmi_nxt[39 : 34] = dmi_ctrl.addr; // address
    assign tap_reg.dmi_nxt[33 : 02] = dmi_ctrl.rdata; // read data
    assign tap_reg.dmi_nxt[01 : 00] = (dmi_ctrl.state != DMI_IDLE) ? 2'b11 : dmi_ctrl.rsp; // status


    // Debug Module Interface --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : dmi_controller
        if (rstn_i == 1'b0) begin
            dmi_ctrl.state        <= DMI_IDLE;
            dmi_ctrl.dmihardreset <= 1'b1;
            dmi_ctrl.dmireset     <= 1'b1;
            dmi_ctrl.rsp          <= 2'b00;
            dmi_ctrl.rdata        <= '0;
            dmi_ctrl.wdata        <= '0;
            dmi_ctrl.addr         <= '0;
        end else begin
            /* DMI status and control */
            dmi_ctrl.dmihardreset <= 1'b0; // default
            dmi_ctrl.dmireset     <= 1'b0; // default
            //
            if ((dr_update_trig.valid == 1'b1) && (tap_reg.ireg == 5'b10000)) begin
                dmi_ctrl.dmireset     <= tap_reg.dtmcs[16];
                dmi_ctrl.dmihardreset <= tap_reg.dtmcs[17];
            end

            /* DMI interface arbiter */
            if (dmi_ctrl.dmihardreset == 1'b1) begin // DMI hard reset
                dmi_ctrl.state <= DMI_IDLE;
            end else begin
                unique case (dmi_ctrl.state)
                    // -----------------------------------------------------------------
                    /* waiting for new request */
                    DMI_IDLE : begin
                        if ((dr_update_trig.valid == 1'b1) && (tap_reg.ireg == 5'b10001)) begin
                            dmi_ctrl.addr  <= tap_reg.dmi[39 : 34];
                            dmi_ctrl.wdata <= tap_reg.dmi[33 : 02];
                            //
                            if (tap_reg.dmi[1:0] == 2'b01) begin // read
                                dmi_ctrl.state <= DMI_READ_WAIT;
                            end else if (tap_reg.dmi[1:0] == 2'b10) begin // write
                                dmi_ctrl.state <= DMI_WRITE_WAIT;
                            end
                        end
                    end
                    // -----------------------------------------------------------------
                    /* wait for DMI to become ready */
                    DMI_READ_WAIT : begin
                        if (dmi_req_ready_i == 1'b1) begin
                            dmi_ctrl.state <= DMI_READ;
                        end
                    end
                    // -----------------------------------------------------------------
                    /* trigger/start read access */
                    DMI_READ : begin
                        dmi_ctrl.state <= DMI_READ_BUSY;
                    end
                    // -----------------------------------------------------------------
                    /* pending read access */
                    DMI_READ_BUSY : begin
                        if (dmi_rsp_valid_i == 1'b1) begin
                            dmi_ctrl.rdata <= dmi_rsp_data_i;
                            dmi_ctrl.state <= DMI_IDLE;
                        end
                    end
                    // -----------------------------------------------------------------
                    /* wait for DMI to become ready */
                    DMI_WRITE_WAIT : begin
                        if (dmi_req_ready_i == 1'b1) begin
                            dmi_ctrl.state <= DMI_WRITE;
                        end
                    end
                    // -----------------------------------------------------------------
                    /* trigger/start write access */
                    DMI_WRITE : begin
                        dmi_ctrl.state <= DMI_WRITE_BUSY;
                    end
                    // -----------------------------------------------------------------
                    /* pending write access */
                    DMI_WRITE_BUSY : begin
                        if (dmi_rsp_valid_i == 1'b1) begin
                            dmi_ctrl.state <= DMI_IDLE;
                        end
                    end
                    // -----------------------------------------------------------------
                    /* undefined */
                    default: begin
                        dmi_ctrl.state <= DMI_IDLE;
                    end
                endcase
            end

            /* sticky response flags */
            if ((dmi_ctrl.dmireset == 1'b1) || (dmi_ctrl.dmihardreset == 1'b1)) begin
                dmi_ctrl.rsp <= 2'b00;
            end else begin
                // access attempt while DMI is busy
                if ((dmi_ctrl.state != DMI_IDLE) && (dr_update_trig.valid == 1'b1) && (tap_reg.ireg == 5'b10001)) begin
                    dmi_ctrl.rsp <= 2'b11;
                // accumulate DMI response
                end else if ((dmi_ctrl.state == DMI_READ_BUSY) || (dmi_ctrl.state == DMI_WRITE_BUSY)) begin
                    dmi_ctrl.rsp <= dmi_ctrl.rsp | dmi_rsp_op_i;
                end
            end
        end
    end : dmi_controller
    
    /* trigger for UPDATE state */
    always_ff @( posedge clk_i or negedge rstn_i ) begin : tap_update_trigger
        if (rstn_i == 1'b0) begin
            dr_update_trig.is_update_ff <= 1'b0;
        end else begin
            dr_update_trig.is_update_ff <= dr_update_trig.is_update;
        end
    end : tap_update_trigger

    assign dr_update_trig.is_update = (tap_ctrl_state == DR_UPDATE) ? 1'b1 : 1'b0;
    assign dr_update_trig.valid     = ((dr_update_trig.is_update == 1'b1) && (dr_update_trig.is_update_ff == 1'b0)) ? 1'b1 : 1'b0;

    /* direct DMI output */
    assign dmi_req_valid_o   = ((dmi_ctrl.state == DMI_READ) || (dmi_ctrl.state == DMI_WRITE)) ? 1'b1 : 1'b0;
    assign dmi_req_op_o      = tap_reg.dmi[1:0];
    assign dmi_rsp_ready_o   = ((dmi_ctrl.state == DMI_READ_BUSY) || (dmi_ctrl.state == DMI_WRITE_BUSY)) ? 1'b1 : 1'b0;
    assign dmi_req_address_o = dmi_ctrl.addr;
    assign dmi_req_data_o    = dmi_ctrl.wdata;
    
endmodule