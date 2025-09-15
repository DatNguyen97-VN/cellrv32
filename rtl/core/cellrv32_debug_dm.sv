// ##################################################################################################
// # << CELLRV32 - RISC-V-Compatible Debug Module (DM) >>                                           #
// # ********************************************************************************************** #
// # Compatible to the "Minimal RISC-V External Debug Spec. Version 1.0" using "execution-based"    #
// # debugging scheme (via the program buffer).                                                     #
// # ********************************************************************************************** #
// # Key features:                                                                                  #
// # * register access commands only                                                                #
// # * auto-execution commands                                                                      #
// # * for a single hart only                                                                       #
// # * 2 general purpose program buffer entries                                                     #
// # * 1 general purpose data buffer entry                                                          #
// #                                                                                                #
// # CPU access:                                                                                    #
// # * ROM for "park loop" code                                                                     #
// # * program buffer                                                                               #
// # * data buffer                                                                                  #
// # * control and status register                                                                  #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_debug_dm (
    /* global control */
    input  logic        clk_i,  // global clock line
    input  logic        rstn_i, // global reset line, low-active
    /* debug module interface (DMI) */
    input  logic        dmi_req_valid_i,
    output logic        dmi_req_ready_o, // DMI is allowed to make new requests when set
    input  logic [05:0] dmi_req_address_i,
    input  logic [01:0] dmi_req_op_i,
    input  logic [31:0] dmi_req_data_i,
    output logic        dmi_rsp_valid_o, // response valid when set
    input  logic        dmi_rsp_ready_i, // ready to receive respond
    output logic [31:0] dmi_rsp_data_o,
    output logic [01:0] dmi_rsp_op_o,
    /* CPU bus access */
    input  logic        cpu_debug_i, // CPU is in debug mode
    input  logic [31:0] cpu_addr_i,  // address
    input  logic        cpu_rden_i,  // read enable
    input  logic        cpu_wren_i,  // write enable
    input  logic [03:0] cpu_ben_i,   // byte write enable
    input  logic [31:0] cpu_data_i,  // data in
    output logic [31:0] cpu_data_o,  // data out
    output logic        cpu_ack_o,   // transfer acknowledge
    /* CPU control */
    output logic        cpu_ndmrstn_o,  // soc reset
    output logic        cpu_halt_req_o  // request hart to halt (enter debug mode)
);
    
    // **********************************************************
    // DMI Access
    // **********************************************************

    /* DM operations */
    localparam logic[1:0] dmi_nop_c      = 2'b00; // no operation
    localparam logic[1:0] dmi_read_c     = 2'b01; // read data
    localparam logic[1:0] dmi_write_c    = 2'b10; // write data
    localparam logic[1:0] dmi_reserved_c = 2'b11; // reserved
    
    /* available DMI registers */
    localparam logic[5:0] addr_data0_c        = {2'b00, 4'h4};
    localparam logic[5:0] addr_dmcontrol_c    = {2'b01, 4'h0};
    localparam logic[5:0] addr_dmstatus_c     = {2'b01, 4'h1};
    localparam logic[5:0] addr_hartinfo_c     = {2'b01, 4'h2};
    localparam logic[5:0] addr_abstractcs_c   = {2'b01, 4'h6};
    localparam logic[5:0] addr_command_c      = {2'b01, 4'h7};
    localparam logic[5:0] addr_abstractauto_c = {2'b01, 4'h8};
    localparam logic[5:0] addr_nextdm_c       = {2'b01, 4'hd};
    localparam logic[5:0] addr_progbuf0_c     = {2'b10, 4'h0};
    localparam logic[5:0] addr_progbuf1_c     = {2'b10, 4'h1};
    localparam logic[5:0] addr_sbcs_c         = {2'b11, 4'h8};
   
    /* RISC-V 32-bit instruction prototypes */
    localparam logic[31:0] instr_nop_c    = 32'h00000013; // nop
    localparam logic[31:0] instr_lw_c     = 32'h00002003; // lw zero, 0(zero)
    localparam logic[31:0] instr_sw_c     = 32'h00002023; // sw zero, 0(zero)
    localparam logic[31:0] instr_ebreak_c = 32'h00100073; // ebreak

    /* DMI access */
    logic dmi_wren;
    logic dmi_rden;

    /* debug module DMI registers / access */
    typedef logic [0:1][31:0] progbuf_t;
    //
    typedef struct packed {
        logic        dmcontrol_ndmreset;
        logic        dmcontrol_dmactive;
        logic        abstractauto_autoexecdata;
        logic [01:0] abstractauto_autoexecprogbuf;
        progbuf_t    progbuf;
        logic [31:0] command;
        //
        logic halt_req;
        logic resume_req;
        logic reset_ack;
        logic wr_acc_err;
        logic rd_acc_err;
        logic clr_acc_err;
        logic autoexec_wr;
        logic autoexec_rd;
    } dm_reg_t;
    //
    dm_reg_t dm_reg;

    /* cpu program buffer */
    typedef logic [31:0] cpu_progbuf_t [0:4];
    cpu_progbuf_t cpu_progbuf;

    // **********************************************************
    // DM Control
    // **********************************************************

    /* DM configuration */
    localparam logic [03:0] nscratch_c   = 4'b0001; // number of dscratch registers in CPU
    localparam logic [03:0] datasize_c   = 4'b0001; // number of data registers in memory/CSR space
    localparam logic [11:0] dataaddr_c   = dm_data_base_c[11:0]; // signed base address of data registers in memory/CSR space
    localparam logic        dataaccess_c = 1'b1;    // 1: abstract data is memory-mapped, 0: abstract data is CSR-mapped
    
    /* debug module controller */
    typedef enum { CMD_IDLE, 
                   CMD_EXE_CHECK, 
                   CMD_EXE_PREPARE, 
                   CMD_EXE_TRIGGER, 
                   CMD_EXE_BUSY, 
                   CMD_EXE_ERROR } dm_ctrl_state_t;
    //
    typedef struct packed {
        /* fsm */
        dm_ctrl_state_t state;
        logic           busy;
        logic [31:0]    ldsw_progbuf;
        logic           pbuf_en;
        /* error flags */
        logic        illegal_state;
        logic        illegal_cmd;
        logic [02:0] cmderr;
        /* hart status */
        logic hart_halted;
        logic hart_resume_req;
        logic hart_resume_ack;
        logic hart_reset;
    } dm_ctrl_t;
    //
    dm_ctrl_t dm_ctrl;

    // **********************************************************
    // CPU Bus Interface
    // **********************************************************

    /* IO space: module base address */
    localparam int hi_abb_c = 31; // high address boundary bit
    localparam int lo_abb_c = $clog2(dm_size_c); // low address boundary bit

    /* status and control register - bits */
    /* for write access we only care about the actual BYTE WRITE ACCESSES! */
    localparam int sreg_halt_ack_c      =  0; // -/w: CPU is halted in debug mode and waits in park loop
    localparam int sreg_resume_req_c    =  8; // r/-: DM requests CPU to resume
    localparam int sreg_resume_ack_c    =  8; // -/w: CPU starts resuming
    localparam int sreg_execute_req_c   = 16; // r/-: DM requests to execute program buffer
    localparam int sreg_execute_ack_c   = 16; // -/w: CPU starts to execute program buffer
    localparam int sreg_exception_ack_c = 24; // -/w: CPU has detected an exception

    /* code ROM containing "park loop" */
    /* copied manually from 'sw/ocd-firmware/cellrv32_debug_mem_code.vhd' */
    typedef logic [0:15][31:0] code_rom_file_t;
    //
    const code_rom_file_t code_rom_file = '{
        32'h8c0001a3,
        32'h00100073,
        32'h7b241073,
        32'h8c000023,
        32'h8c204403,
        32'h00041c63,
        32'h8c104403,
        32'hfe0408e3,
        32'h8c8000a3,
        32'h7b202473,
        32'h7b200073,
        32'h8c000123,
        32'h7b202473,
        32'h0000100f,
        32'h84000067,
        32'h00000073
    };

    /* Debug Core Interface */
    typedef struct packed {
        logic halt_ack;        // CPU (re-)entered HALT state (single-shot)
        logic resume_req;      // DM wants the CPU to resume when set
        logic resume_ack;      // CPU starts resuming when set (single-shot)
        logic execute_req;     // DM wants CPU to execute program buffer when set
        logic execute_ack;     // CPU starts executing program buffer when set (single-shot)
        logic exception_ack;   // CPU has detected an exception (single-shot)
        logic [255:0] progbuf; // program buffer, 4 32-bit entries
        logic data_we;         // write abstract data
        logic [31:0] wdata;    // abstract write data
        logic [31:0] rdata;    // abstract read data
    } dci_t;
    //
    dci_t dci;

    /* global access control */
    logic        acc_en;
    logic        rden;
    logic        wren;
    logic [01:0] maddr;

    /* data buffer */
    logic [31:0] data_buf;

    /* program buffer access */
    typedef logic [0:3][31:0] prog_buf_t;
    prog_buf_t prog_buf;

    // DMI Access --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign dmi_wren = ((dmi_req_valid_i == 1'b1) && (dmi_req_op_i == dmi_write_c)) ? 1'b1 : 1'b0;
    assign dmi_rden = ((dmi_req_valid_i == 1'b1) && (dmi_req_op_i == dmi_read_c) ) ? 1'b1 : 1'b0;

    // Debug Module Command Controller -----------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : dm_controller
            // DM reset / DM disabled
            if (dm_reg.dmcontrol_dmactive == 1'b0) begin
                dm_ctrl.state         <= CMD_IDLE;
                dm_ctrl.ldsw_progbuf  <= instr_sw_c;
                dci.execute_req       <= 1'b0;
                dm_ctrl.pbuf_en       <= 1'b0;
                //
                dm_ctrl.illegal_cmd   <= 1'b0;
                dm_ctrl.illegal_state <= 1'b0;
                dm_ctrl.cmderr        <= 3'b000;
            end else begin // DM active
                /* defaults */
                dci.execute_req       <= 1'b0;
                dm_ctrl.illegal_cmd   <= 1'b0;
                dm_ctrl.illegal_state <= 1'b0;
  
                /* command execution engine */
                unique case (dm_ctrl.state)
                  // --------------------------------------------------------------
                  // wait for new abstract command
                  CMD_IDLE : begin
                      if (dmi_wren == 1'b1) begin // valid DM write access
                          if (dmi_req_address_i == addr_command_c) begin
                              if (dm_ctrl.cmderr == 3'b000) begin // only execute if no error
                                  dm_ctrl.state <= CMD_EXE_CHECK;
                              end
                          end
                      // auto execution trigger
                      end else if ((dm_reg.autoexec_rd == 1'b1) || (dm_reg.autoexec_wr == 1'b1)) begin
                          dm_ctrl.state <= CMD_EXE_CHECK;
                      end
                  end
                  // --------------------------------------------------------------
                  // check if command is valid / supported
                  CMD_EXE_CHECK : begin
                      if ((dm_reg.command[31:24] == 8'h00)  && // cmdtype: register access
                          (dm_reg.command[23] == 1'b0)      && // reserved
                          (dm_reg.command[22:20] == 3'b010) && // aarsize: has to be 32-bit
                          (dm_reg.command[19] == 1'b0)      && // aarpostincrement: not supported
                         ((dm_reg.command[17] == 1'b0)      || // regno: only GPRs are supported: 0x1000..0x101f if transfer is set
                          (dm_reg.command[15 : 05] == 11'b00010000000))) begin 
                          //
                          // CPU is halted
                          if (dm_ctrl.hart_halted == 1'b1) begin 
                              dm_ctrl.state <= CMD_EXE_PREPARE;
                          end else begin // error! CPU is still running
                              dm_ctrl.illegal_state <= 1'b1;
                              dm_ctrl.state         <= CMD_EXE_ERROR;
                          end
                      end else begin // invalid command
                          dm_ctrl.illegal_cmd <= 1'b1;
                          dm_ctrl.state       <= CMD_EXE_ERROR;
                      end
                  end
                  // --------------------------------------------------------------
                  // setup program buffer
                  CMD_EXE_PREPARE : begin
                      if (dm_reg.command[17] == 1'b1) begin // "transfer"
                          if (dm_reg.command[16] == 1'b0) begin // "write" = 0 -> read from GPR
                              dm_ctrl.ldsw_progbuf        <= instr_sw_c;
                              dm_ctrl.ldsw_progbuf[31:25] <= dataaddr_c[11:05]; // destination address
                              dm_ctrl.ldsw_progbuf[24:20] <= dm_reg.command[04:00]; // "regno" = source register
                              dm_ctrl.ldsw_progbuf[11:07] <= dataaddr_c[04:00]; // destination address
                          end else begin // "write" = 1 -> write to GPR
                              dm_ctrl.ldsw_progbuf        <= instr_lw_c;
                              dm_ctrl.ldsw_progbuf[31:20] <= dataaddr_c; // source address
                              dm_ctrl.ldsw_progbuf[11:07] <= dm_reg.command[04:00]; // "regno" = destination register
                          end
                      end else begin
                          dm_ctrl.ldsw_progbuf <= instr_nop_c; // NOP - do nothing
                      end
                      //
                      if (dm_reg.command[18] == 1'b1) begin // "postexec" - execute program buffer
                          dm_ctrl.pbuf_en <= 1'b1;
                      end else begin // execute all program buffer entries as NOPs
                          dm_ctrl.pbuf_en <= 1'b0;
                      end
                      //
                      dm_ctrl.state <= CMD_EXE_TRIGGER;
                  end
                  // --------------------------------------------------------------
                  // request CPU to execute command
                  CMD_EXE_TRIGGER : begin
                      dci.execute_req <= 1'b1; // request execution
                      if (dci.execute_ack == 1'b1) begin // CPU starts execution
                          dm_ctrl.state <= CMD_EXE_BUSY;
                      end
                  end
                  
                  // --------------------------------------------------------------
                  //  wait for CPU to finish
                  CMD_EXE_BUSY : begin
                      if (dci.halt_ack == 1'b1) begin // CPU is parked (halted) again -> execution done
                          dm_ctrl.state <= CMD_IDLE;
                      end
                  end
                  // --------------------------------------------------------------
                  // delay cycle for error to arrive abstracts.cmderr
                  CMD_EXE_ERROR : begin
                      dm_ctrl.state <= CMD_IDLE;
                  end
                  // --------------------------------------------------------------
                  // undefined
                  default: begin
                      dm_ctrl.state <= CMD_IDLE;
                  end
                endcase
            // --------------------------------------------------------------
            /* error code */
            if (dm_ctrl.cmderr == 3'b000) begin // ready to set new error
                if (dm_ctrl.illegal_state == 1'b1) begin // cannot execute since hart is not in expected state
                    dm_ctrl.cmderr <= 3'b100;
                end else if (dci.exception_ack == 1'b1) begin // exception during execution
                    dm_ctrl.cmderr <= 3'b011;
                end else if (dm_ctrl.illegal_cmd == 1'b1) begin // unsupported command
                    dm_ctrl.cmderr <= 3'b010;
                end else if ((dm_reg.rd_acc_err == 1'b1) || (dm_reg.wr_acc_err == 1'b1)) begin // invalid read/write while command is executing
                    dm_ctrl.cmderr <= 3'b001;
                end
            end else if (dm_reg.clr_acc_err == 1'b1) begin // acknowledge/clear error flags
                dm_ctrl.cmderr <= 3'b000;
            end
        end
    end : dm_controller

    /* controller busy flag */
    assign dm_ctrl.busy = (dm_ctrl.state == CMD_IDLE) ? 1'b0 : 1'b1;

    // Hart Status -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : hart_status
        if (rstn_i == 1'b0) begin
            dm_ctrl.hart_halted     <= 1'b0;
            dm_ctrl.hart_resume_req <= 1'b0;
            dm_ctrl.hart_resume_ack <= 1'b0;
            dm_ctrl.hart_reset      <= 1'b0;
        end else begin
            /* HALTED ACK */
            if (dm_reg.dmcontrol_ndmreset == 1'b1) begin
                dm_ctrl.hart_halted <= 1'b0;
            end else if (dci.halt_ack == 1'b1) begin
                dm_ctrl.hart_halted <= 1'b1;
            end else if (dci.resume_ack == 1'b1) begin
                dm_ctrl.hart_halted <= 1'b0;
            end

            /* RESUME REQ */
            if (dm_reg.dmcontrol_ndmreset == 1'b1) begin
                dm_ctrl.hart_resume_req <= 1'b0;
            end else if (dm_reg.resume_req == 1'b1) begin
                dm_ctrl.hart_resume_req <= 1'b1;
            end else if (dci.resume_ack == 1'b1) begin
                dm_ctrl.hart_resume_req <= 1'b0;
            end

            /* RESUME ACK */
            if (dm_reg.dmcontrol_ndmreset == 1'b1) begin
                dm_ctrl.hart_resume_ack <= 1'b0;
            end else if (dci.resume_ack == 1'b1) begin
                dm_ctrl.hart_resume_ack <= 1'b1;
            end else if (dm_reg.resume_req == 1'b1) begin
                dm_ctrl.hart_resume_ack <= 1'b0;
            end

            /* hart has been RESET */
            if (dm_reg.dmcontrol_ndmreset == 1'b1) begin // explicit RESET triggered by DM
                dm_ctrl.hart_reset <= 1'b1;
            end else if (dm_reg.reset_ack == 1'b1) begin
                dm_ctrl.hart_reset <= 1'b0;
            end
        end
    end : hart_status

    // Debug Module Interface - Write Access -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : dmi_write_access
        if (rstn_i == 1'b0) begin
            dm_reg.dmcontrol_ndmreset <= 1'b0; // no system SoC reset
            dm_reg.dmcontrol_dmactive <= 1'b0; // DM is in reset state after hardware reset
            //
            dm_reg.abstractauto_autoexecdata    <= 1'b0;
            dm_reg.abstractauto_autoexecprogbuf <= 2'b00;
            //
            dm_reg.command <= '0;
            dm_reg.progbuf <= '{instr_nop_c, instr_nop_c};
            //
            dm_reg.halt_req    <= 1'b0;
            dm_reg.resume_req  <= 1'b0;
            dm_reg.reset_ack   <= 1'b0;
            dm_reg.wr_acc_err  <= 1'b0;
            dm_reg.clr_acc_err <= 1'b0;
            dm_reg.autoexec_wr <= 1'b0;
        end else begin
            /* default */
            dm_reg.resume_req  <= 1'b0;
            dm_reg.reset_ack   <= 1'b0;
            dm_reg.wr_acc_err  <= 1'b0;
            dm_reg.clr_acc_err <= 1'b0;
            dm_reg.autoexec_wr <= 1'b0;

            /* DMI access */
            if (dmi_wren == 1'b1) begin // valid DMI write request
                /* debug module control */
                if (dmi_req_address_i == addr_dmcontrol_c) begin
                   dm_reg.halt_req           <= dmi_req_data_i[31]; // haltreq (-/w): write 1 to request halt; has to be cleared again by debugger
                   dm_reg.resume_req         <= dmi_req_data_i[30]; // resumereq (-/w1): write 1 to request resume; auto-clears
                   dm_reg.reset_ack          <= dmi_req_data_i[28]; // ackhavereset (-/w1): write 1 to ACK reset; auto-clears
                   dm_reg.dmcontrol_ndmreset <= dmi_req_data_i[01]; // ndmreset (r/w): soc reset
                   dm_reg.dmcontrol_dmactive <= dmi_req_data_i[00]; // dmactive (r/w): DM reset
                end

                /* write abstract command */
                if (dmi_req_address_i == addr_command_c) begin
                  if ((dm_ctrl.busy == 1'b0) && (dm_ctrl.cmderr == 3'b000)) begin // idle and no errors yet
                    dm_reg.command <= dmi_req_data_i;
                  end
                end

                /* write abstract command autoexec */
                if (dmi_req_address_i == addr_abstractauto_c) begin
                    if (dm_ctrl.busy == 1'b0) begin // idle and no errors yet
                        dm_reg.abstractauto_autoexecdata       <= dmi_req_data_i[00];
                        dm_reg.abstractauto_autoexecprogbuf[0] <= dmi_req_data_i[16];
                        dm_reg.abstractauto_autoexecprogbuf[1] <= dmi_req_data_i[17];
                    end
                end

                /* auto execution trigger */
                if (
                    ((dmi_req_address_i == addr_data0_c)    && (dm_reg.abstractauto_autoexecdata == 1'b1)) ||
                    ((dmi_req_address_i == addr_progbuf0_c) && (dm_reg.abstractauto_autoexecprogbuf[0] == 1'b1)) ||
                    ((dmi_req_address_i == addr_progbuf1_c) && (dm_reg.abstractauto_autoexecprogbuf[1] == 1'b1))
                   ) begin
                   dm_reg.autoexec_wr <= 1'b1;
                end

                /* acknowledge command error */
                if (dmi_req_address_i == addr_abstractcs_c) begin
                  if (dmi_req_data_i[10:08] == 3'b111) begin
                     dm_reg.clr_acc_err <= 1'b1;
                  end
                end

                /* write program buffer */
                if (dmi_req_address_i[$bits(dmi_req_address_i)-1 : 1] == addr_progbuf0_c[$bits(dmi_req_address_i)-1 : 1]) begin
                  if (dm_ctrl.busy == 1'b0) begin // idle
                    if (dmi_req_address_i[0] == addr_progbuf0_c[0])
                      dm_reg.progbuf[0] <= dmi_req_data_i;
                    else
                      dm_reg.progbuf[1] <= dmi_req_data_i;
                  end 
                end

                /* invalid access while command is executing */
                if (dm_ctrl.busy == 1'b1) begin // busy
                  if ((dmi_req_address_i == addr_abstractcs_c)   ||
                      (dmi_req_address_i == addr_command_c)      ||
                      (dmi_req_address_i == addr_abstractauto_c) ||
                      (dmi_req_address_i == addr_data0_c)        ||
                      (dmi_req_address_i == addr_progbuf0_c)     ||
                      (dmi_req_address_i == addr_progbuf1_c)) begin
                    dm_reg.wr_acc_err <= 1'b1;
                  end   
                end
            end
        end
    end : dmi_write_access

    // Direct Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* write to abstract data register */
    assign dci.data_we = ((dmi_wren == 1'b1) && (dmi_req_address_i == addr_data0_c) && (dm_ctrl.busy == 1'b0)) ? 1'b1 : 1'b0;
    assign dci.wdata   = dmi_req_data_i;

    /* CPU halt/resume request */
    assign cpu_halt_req_o = dm_reg.halt_req & dm_reg.dmcontrol_dmactive; // single-shot
    assign dci.resume_req = dm_ctrl.hart_resume_req; // active until explicitly cleared

    /* SoC reset */
    assign cpu_ndmrstn_o = ((dm_reg.dmcontrol_ndmreset == 1'b1) && (dm_reg.dmcontrol_dmactive == 1'b1)) ? 1'b0 : 1'b1; // to processor's reset generator

    /* construct program buffer array for CPU access */
    assign cpu_progbuf[0] = dm_ctrl.ldsw_progbuf; // pseudo program buffer for GPR access
    assign cpu_progbuf[1] = (dm_ctrl.pbuf_en == 1'b0) ? instr_nop_c : dm_reg.progbuf[0];
    assign cpu_progbuf[2] = (dm_ctrl.pbuf_en == 1'b0) ? instr_nop_c : dm_reg.progbuf[1];
    assign cpu_progbuf[3] = instr_ebreak_c; // implicit ebreak instruction

    /* DMI status */
    assign dmi_rsp_op_o    = 2'b00; // operation success
    assign dmi_req_ready_o = 1'b1; // always ready for new read/write access

    // Debug Module Interface - Read Access ------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : dmi_read_access
        dmi_rsp_valid_o    <= dmi_req_valid_i; // DMI transfer ack
        dmi_rsp_data_o     <= '0; // default
        dm_reg.rd_acc_err  <= 1'b0;
        dm_reg.autoexec_rd <= 1'b0;
        //
        unique case (dmi_req_address_i)
            // -------------------------------------------------------------------------------------------
            /* debug module status register */
            addr_dmstatus_c : begin
                dmi_rsp_data_o[31 : 23] <= '0;                       // reserved (r/-)
                dmi_rsp_data_o[22]      <= 1'b1;                      // impebreak (r/-): there is an implicit ebreak instruction after the visible program buffer
                dmi_rsp_data_o[21 : 20] <= '0;                       // reserved (r/-)
                dmi_rsp_data_o[19]      <= dm_ctrl.hart_reset;        // allhavereset (r/-): there is only one hart that can be reset
                dmi_rsp_data_o[18]      <= dm_ctrl.hart_reset;        // anyhavereset (r/-): there is only one hart that can be reset
                dmi_rsp_data_o[17]      <= dm_ctrl.hart_resume_ack;   // allresumeack (r/-): there is only one hart that can acknowledge resume request
                dmi_rsp_data_o[16]      <= dm_ctrl.hart_resume_ack;   // anyresumeack (r/-): there is only one hart that can acknowledge resume request
                dmi_rsp_data_o[15]      <= 1'b0;                      // allnonexistent (r/-): there is only one hart that is always existent
                dmi_rsp_data_o[14]      <= 1'b0;                      // anynonexistent (r/-): there is only one hart that is always existent
                dmi_rsp_data_o[13]      <= dm_reg.dmcontrol_ndmreset; // allunavail (r/-): there is only one hart that is unavailable during reset
                dmi_rsp_data_o[12]      <= dm_reg.dmcontrol_ndmreset; // anyunavail (r/-): there is only one hart that is unavailable during reset
                dmi_rsp_data_o[11]      <= ~dm_ctrl.hart_halted;      // allrunning (r/-): there is only one hart that can be RUNNING or HALTED
                dmi_rsp_data_o[10]      <= ~dm_ctrl.hart_halted;      // anyrunning (r/-): there is only one hart that can be RUNNING or HALTED
                dmi_rsp_data_o[09]      <= dm_ctrl.hart_halted;       // allhalted (r/-): there is only one hart that can be RUNNING or HALTED
                dmi_rsp_data_o[08]      <= dm_ctrl.hart_halted;       // anyhalted (r/-): there is only one hart that can be RUNNING or HALTED
                dmi_rsp_data_o[07]      <= 1'b1;                      // authenticated (r/-): authentication passed since there is no authentication
                dmi_rsp_data_o[06]      <= 1'b0;                      // authbusy (r/-): always ready since there is no authentication
                dmi_rsp_data_o[05]      <= 1'b0;                      // hasresethaltreq (r/-): halt-on-reset not implemented
                dmi_rsp_data_o[04]      <= 1'b0;                      // confstrptrvalid (r/-): no configuration string available
                dmi_rsp_data_o[03 : 00] <= 4'b0011;                   // version (r/-): compatible to spec. version 1.0
            end
            // -------------------------------------------------------------------------------------------
            /* debug module control */
            addr_dmcontrol_c : begin
                dmi_rsp_data_o[31]      <= 1'b0;   // haltreq (-/w): write-only
                dmi_rsp_data_o[30]      <= 1'b0;   // resumereq (-/w1): write-only
                dmi_rsp_data_o[29]      <= 1'b0;   // hartreset (r/w): not supported
                dmi_rsp_data_o[28]      <= 1'b0;   // ackhavereset (-/w1): write-only
                dmi_rsp_data_o[27]      <= 1'b0;   // reserved (r/-)
                dmi_rsp_data_o[26]      <= 1'b0;   // hasel (r/-) - there is a single currently selected hart
                dmi_rsp_data_o[25 : 16] <= '0;    // hartsello (r/-) - there is only one hart
                dmi_rsp_data_o[15 : 06] <= '0;    // hartselhi (r/-) - there is only one hart
                dmi_rsp_data_o[05 : 04] <= '0;    // reserved (r/-)
                dmi_rsp_data_o[03]      <= 1'b0;   // setresethaltreq (-/w1): halt-on-reset request - halt-on-reset not implemented
                dmi_rsp_data_o[02]      <= 1'b0;   // clrresethaltreq (-/w1): halt-on-reset ack - halt-on-reset not implemented
                dmi_rsp_data_o[01]      <= dm_reg.dmcontrol_ndmreset; // ndmreset (r/w): soc reset
                dmi_rsp_data_o[00]      <= dm_reg.dmcontrol_dmactive; // dmactive (r/w): DM reset
            end
            // -------------------------------------------------------------------------------------------
            /* hart info */
            addr_hartinfo_c : begin
                dmi_rsp_data_o[31 : 24] <= '0;  // reserved (r/-)
                dmi_rsp_data_o[23 : 20] <= nscratch_c;       // nscratch (r/-): number of dscratch CSRs
                dmi_rsp_data_o[19 : 17] <= '0;  // reserved (r/-)
                dmi_rsp_data_o[16]      <= dataaccess_c;     // dataaccess (r/-): 1: data registers are memory-mapped, 0: data reisters are CSR-mapped
                dmi_rsp_data_o[15 : 12] <= datasize_c;       // datasize (r/-): number data registers in memory/CSR space
                dmi_rsp_data_o[11 : 00] <= dataaddr_c;       // dataaddr (r/-): data registers base address (memory/CSR)
            end
            // -------------------------------------------------------------------------------------------
            /* abstract control and status */
            addr_abstractcs_c : begin
                dmi_rsp_data_o[31 : 24] <= '0;            // reserved (r/-)
                dmi_rsp_data_o[28 : 24] <= 5'b00010;       // progbufsize (r/-): number of words in program buffer = 2
                dmi_rsp_data_o[12]      <= dm_ctrl.busy;   // busy (r/-): abstract command in progress (1) / idle (0)
                dmi_rsp_data_o[11]      <= 1'b1;           // relaxedpriv (r/-): PMP rules are ignored when in debug-mode
                dmi_rsp_data_o[10 : 08] <= dm_ctrl.cmderr; // cmderr (r/w1c): any error during execution?
                dmi_rsp_data_o[07 : 04] <= '0;            // reserved (r/-)
                dmi_rsp_data_o[03 : 00] <= 4'b0001;        // datacount (r/-): number of implemented data registers = 1
            end
            // -------------------------------------------------------------------------------------------
            /* abstract command autoexec (r/w) */
            addr_abstractauto_c : begin
                dmi_rsp_data_o[00] <= dm_reg.abstractauto_autoexecdata;       // autoexecdata(0):    read/write access to data0 triggers execution of program buffer
                dmi_rsp_data_o[16] <= dm_reg.abstractauto_autoexecprogbuf[0]; // autoexecprogbuf(0): read/write access to progbuf0 triggers execution of program buffer
                dmi_rsp_data_o[17] <= dm_reg.abstractauto_autoexecprogbuf[1]; // autoexecprogbuf(1): read/write access to progbuf1 triggers execution of program buffer
            end
            // -------------------------------------------------------------------------------------------
            /* abstract data 0 (r/w) */
            addr_data0_c : begin
                dmi_rsp_data_o <= dci.rdata;
            end
            // -------------------------------------------------------------------------------------------
            /* not implemented (r/-) */
            default: begin
                dmi_rsp_data_o <= '0;
            end
        endcase

        /* invalid read access while command is executing */
        // --------------------------------------------------------------
        if (dmi_rden == 1'b1) begin // valid DMI read request
           if (dm_ctrl.busy == 1'b1) begin // busy
             if ((dmi_req_address_i == addr_data0_c)    ||
                 (dmi_req_address_i == addr_progbuf0_c) ||
                 (dmi_req_address_i == addr_progbuf1_c)) begin
               dm_reg.rd_acc_err <= 1'b1;
             end
           end
        end

        /* auto execution trigger */
        // --------------------------------------------------------------
        if (dmi_rden == 1'b1) begin // valid DMI read request
          if (((dmi_req_address_i == addr_data0_c)    && (dm_reg.abstractauto_autoexecdata == 1'b1)) ||
              ((dmi_req_address_i == addr_progbuf0_c) && (dm_reg.abstractauto_autoexecprogbuf[0] == 1'b1)) ||
              ((dmi_req_address_i == addr_progbuf1_c) && (dm_reg.abstractauto_autoexecprogbuf[1] == 1'b1))) begin
            dm_reg.autoexec_rd <= 1'b1;
          end
        end
    end : dmi_read_access
    
    // **************************************************************************************************************************
    // CPU Bus Interface
    // **************************************************************************************************************************

    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    assign acc_en = (cpu_addr_i[hi_abb_c : lo_abb_c] == dm_base_c[hi_abb_c : lo_abb_c]) ? 1'b1 : 1'b0;
    assign maddr  = cpu_addr_i[lo_abb_c-1 : lo_abb_c-2]; // (sub-)module select address
    assign rden   = acc_en & cpu_debug_i & cpu_rden_i; // allow access only when in debug mode
    assign wren   = acc_en & cpu_debug_i & cpu_wren_i; // allow access only when in debug mode
    
    // Write Access ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : write_access
        if (rstn_i == 1'b0) begin
            data_buf          <= '0;
            dci.halt_ack      <= 1'b0;
            dci.resume_ack    <= 1'b0;
            dci.execute_ack   <= 1'b0;
            dci.exception_ack <= 1'b0;
        end else begin
            /* data buffer */
            if (dci.data_we == 1'b1) begin // DM write access
               data_buf <= dci.wdata;
            end else if ((maddr == 2'b10) && (wren == 1'b1)) begin // CPU write access
              data_buf <= cpu_data_i;
            end
            /* control and status register CPU write access */
            /* NOTE: we only check the individual BYTE ACCESSES - not the actual write data */
            dci.halt_ack      <= 1'b0; // all writable flags auto-clear
            dci.resume_ack    <= 1'b0;
            dci.execute_ack   <= 1'b0;
            dci.exception_ack <= 1'b0;
            //
            if ((maddr == 2'b11) && (wren == 1'b1)) begin
               if (cpu_ben_i[sreg_halt_ack_c/8] == 1'b1) begin
                 dci.halt_ack <= 1'b1;
               end
               if (cpu_ben_i[sreg_resume_ack_c/8] == 1'b1) begin
                 dci.resume_ack <= 1'b1;
               end
               if (cpu_ben_i[sreg_execute_ack_c/8] == 1'b1) begin
                 dci.execute_ack <= 1'b1;
               end
               if (cpu_ben_i[sreg_exception_ack_c/8] == 1'b1) begin
                 dci.exception_ack <= 1'b1;
               end
            end
        end
    end : write_access

    /* DM data buffer read access */
    assign dci.rdata = data_buf;

    // Read Access -------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : read_access
        cpu_ack_o  <= rden | wren;
        cpu_data_o <= '0;
        //
        if (rden == 1'b1) begin // output enable
            unique case (maddr) // module select
                // code ROM
                2'b00 : begin
                    cpu_data_o <= code_rom_file[cpu_addr_i[5:2]];
                end
                // program buffer
                2'b01 : begin
                    cpu_data_o <= cpu_progbuf[cpu_addr_i[3:2]];
                end
                // data buffer
                2'b10 : begin
                    cpu_data_o <= data_buf;
                end
                // control and status register
                default: begin
                    cpu_data_o[sreg_resume_req_c ] <= dci.resume_req;
                    cpu_data_o[sreg_execute_req_c] <= dci.execute_req;
                end
            endcase
        end
    end : read_access
endmodule