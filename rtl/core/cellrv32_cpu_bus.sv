// ##################################################################################################
// # << CELLRV32 - (Data) Bus Interface Unit >>                                                     #
// # ********************************************************************************************** #
// # Data bus interface (load/store unit) and physical memory protection (PMP).                     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_bus #(
    XLEN                = 32,  // data path width
    PMP_NUM_REGIONS     =  0,  // number of regions (0..16)
    PMP_MIN_GRANULARITY =  4   // minimal region granularity in bytes, has to be a power of 2, min 4 bytes
) (
    /* global control */
    input  logic clk_i,       // global clock, rising edge
    input  logic rstn_i,      // global reset, low-active, async
    input  ctrl_bus_t ctrl_i,   // main control bus
    /* cpu instruction fetch interface */
    input  logic [XLEN-1:0] fetch_pc_i, // PC for instruction fetch
    output logic i_pmp_fault_o,         // instruction fetch pmp fault
    /* cpu data access interface */
    input  logic [XLEN-1:0] addr_i,  // ALU result -> access address
    input  logic [XLEN-1:0] wdata_i, // write data
    output logic [XLEN-1:0] rdata_o, // read data
    output logic [XLEN-1:0] mar_o,   // current memory address register
    output logic d_wait_o ,  // wait for access to complete
    output logic ma_load_o,  // misaligned load data address
    output logic ma_store_o, // misaligned store data address
    output logic be_load_o,  // bus error on load data access
    output logic be_store_o, // bus error on store data access
    /* physical memory protection */
    input logic [33:0] pmp_addr_i [15:0], // addresses
    input logic [07:0] pmp_ctrl_i [15:0], // configs
    /* data bus */
    output logic [XLEN-1:0]     d_bus_addr_o,  // bus access address
    input  logic [XLEN-1:0]     d_bus_rdata_i, // bus read data
    output logic [XLEN-1:0]     d_bus_wdata_o, // bus write data
    output logic [(XLEN/8)-1:0] d_bus_ben_o,   // byte enable
    output logic d_bus_we_o,    // write enable
    output logic d_bus_re_o,    // read enable
    input  logic d_bus_ack_i,   // bus transfer acknowledge
    input  logic d_bus_err_i,   // bus transfer error
    output logic d_bus_fence_o, // fence operation
    output logic d_bus_priv_o   // current effective privilege level
);

    /* PMP configuration register bits */
    localparam int pmp_cfg_r_c  = 0; // read permit
    localparam int pmp_cfg_w_c  = 1; // write permit
    localparam int pmp_cfg_x_c  = 2; // execute permit
    localparam int pmp_cfg_al_c = 3; // mode bit low
    localparam int pmp_cfg_ah_c = 4; // mode bit high
    localparam int pmp_cfg_l_c  = 7; // locked entry

    /* PMP minimal granularity */
    localparam int pmp_lsb_c = $clog2(PMP_MIN_GRANULARITY); // min = 2

    /* misc */
    logic  data_sign;      // signed load
    logic  [XLEN-1:0] mar; // data memory address register
    logic misaligned;      // misaligned address

    /* bus arbiter */
    typedef struct {
        logic pend;      // pending bus access
        logic err;       // bus access error
        logic pmp_r_err; // pmp load fault
        logic pmp_w_err; // pmp store fault
    } bus_arbiter_t;
    //
    bus_arbiter_t arbiter;

    /* physical memory protection */
    typedef struct {
        logic [PMP_NUM_REGIONS-1:0] i_cmp_ge;
        logic [PMP_NUM_REGIONS-1:0] i_cmp_lt;
        logic [PMP_NUM_REGIONS-1:0] d_cmp_ge;
        logic [PMP_NUM_REGIONS-1:0] d_cmp_lt;
        logic [PMP_NUM_REGIONS-1:0] i_match;
        logic [PMP_NUM_REGIONS-1:0] d_match;
        logic [PMP_NUM_REGIONS-1:0] perm_ex;
        logic [PMP_NUM_REGIONS-1:0] perm_rd;
        logic [PMP_NUM_REGIONS-1:0] perm_wr;
        logic if_fault;
        logic ld_fault;
        logic st_fault;
    } pmp_t;
    //
    pmp_t pmp;

    /* pmp faults */
    logic  if_pmp_fault; // pmp instruction access fault
    logic  ld_pmp_fault; // pmp load access fault
    logic  st_pmp_fault; // pmp store access fault

    // Access Address ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : mem_adr_reg
        if (ctrl_i.bus_mo_we == 1'b1) begin
            mar <= addr_i; // memory address register
            //
            unique case (ctrl_i.ir_funct3[1:0]) // alignment check
                2'b00 : misaligned <= 1'b0; // byte
                2'b01 : misaligned <= addr_i[0]; // haLf-word
                2'b10 : misaligned <= addr_i[1] | addr_i[0]; // word
                default: begin // double-word
                    if (XLEN == 32) begin // RV32
                        misaligned <= 1'b0;
                    end else begin
                        misaligned <= addr_i[2] | addr_i[1] | addr_i[0];
                    end
                end
            endcase
        end
    end : mem_adr_reg

    /* address output */
    assign d_bus_addr_o = mar;
    assign mar_o        = mar; // for MTVAL CSR

    // Write Data: Byte Enable and Alignment -----------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* RV32 */
    generate
        if (XLEN == 32) begin : mem_do_reg_rv32
            always_ff @( posedge clk_i ) begin : mem_do_reg
                if (ctrl_i.bus_mo_we == 1'b1) begin
                    d_bus_ben_o <= '0; // default
                    //
                    // data size
                    unique case (ctrl_i.ir_funct3[1:0])
                        // byte
                        2'b00 : begin
                            for (int i = 0; i < (XLEN/8); ++i) begin
                                d_bus_wdata_o[i*8 +: 8] <= wdata_i[7:0];
                            end
                            //
                            d_bus_ben_o[addr_i[1:0]] <= 1'b1;
                        end
                        // half-word
                        2'b01 : begin
                            for (int i = 0; i < (XLEN/16); ++i) begin
                                d_bus_wdata_o[i*16 +: 16] <= wdata_i[15:0];
                            end
                            //
                            if (addr_i[1] == 1'b0) begin
                                d_bus_ben_o <= 4'b0011; // low half-word
                            end else begin
                                d_bus_ben_o <= 4'b1100; // high half-word
                            end
                        end
                        default: begin // word
                            for (int i = 0; i < (XLEN/32); ++i) begin
                                d_bus_wdata_o[i*32 +: 32] <= wdata_i[31:0];
                            end
                            //
                            d_bus_ben_o <= '1; // full word
                        end
                    endcase
                end
            end : mem_do_reg
        end : mem_do_reg_rv32
    endgenerate

    /* RV64 */
    generate
        if (XLEN == 64) begin : mem_do_reg_rv64
            // to be define
        end : mem_do_reg_rv64
    endgenerate

    //  Read Data: Alignment and Sign-Extension ---------------------------------------------------
    //  -------------------------------------------------------------------------------------------
    /* RV32 */
    generate
        if (XLEN == 32) begin : mem_di_reg_rv32
            always_ff @( posedge clk_i ) begin : mem_di_reg
                unique case (ctrl_i.ir_funct3[1:0])
                    // byte
                    2'b00 : begin
                        unique case (mar[1:0])
                            // byte 0
                            2'b00 : begin
                                rdata_o[07:00] <= d_bus_rdata_i[07:00];
                                rdata_o[XLEN-1:08] <= (data_sign & d_bus_rdata_i[07]) ? '1 : '0; // sign extension
                            end
                            // byte 1
                            2'b01 : begin
                                rdata_o[07:00] <= d_bus_rdata_i[15:08];
                                rdata_o[XLEN-1:08] <= (data_sign & d_bus_rdata_i[15]) ? '1 : '0; // sign extension
                            end
                            // byte 2
                            2'b10 : begin
                                rdata_o[07:00] <= d_bus_rdata_i[23:16];
                                rdata_o[XLEN-1:08] <= (data_sign & d_bus_rdata_i[23]) ? '1 : '0; // sign extension
                            end
                            // byte 3
                            default: begin
                                rdata_o[07:00] <= d_bus_rdata_i[31:24];
                                rdata_o[XLEN-1:08] <= (data_sign & d_bus_rdata_i[31]) ? '1 : '0; // sign extension
                            end
                        endcase
                    end
                    // half-word
                    2'b01 : begin
                        if (mar[1] == 1'b0) begin
                            rdata_o[15:00] <= d_bus_rdata_i[15:00]; // low half-word
                            rdata_o[XLEN-1:16] <= (data_sign & d_bus_rdata_i[15]) ? '1 : '0; // sign extension
                        end else begin
                            rdata_o[15:00] <= d_bus_rdata_i[31:16]; // high half-word
                            rdata_o[XLEN-1:16] <= (data_sign & d_bus_rdata_i[31]) ? '1 : '0; // sign extension
                        end
                    end
                    default: begin // word
                        rdata_o[XLEN-1:00] <= d_bus_rdata_i[XLEN-1:00]; // full word
                    end
                endcase
            end : mem_di_reg
        end : mem_di_reg_rv32
    endgenerate

    /* RV64 */
    generate
        if (XLEN == 64) begin : mem_di_reg_rv64
           // to be define
        end : mem_di_reg_rv64
    endgenerate

    /* sign extension */
    assign data_sign = ~ctrl_i.ir_funct3[2]; // NOT unsigned LOAD (LBU, LHU)

    // Access Arbiter ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : data_access_arbiter
        if (rstn_i == 1'b0) begin
            arbiter.pend      <= 1'b0;
            arbiter.err       <= 1'b0;
            arbiter.pmp_r_err <= 1'b0;
            arbiter.pmp_w_err <= 1'b0;
        end else begin
            arbiter.pmp_r_err <= ld_pmp_fault;
            arbiter.pmp_w_err <= st_pmp_fault;
            //
            if (arbiter.pend == 1'b0) begin // idle
                if (ctrl_i.bus_req == 1'b1) begin // start bus access
                    arbiter.pend <= 1'b1;
                end
                arbiter.err <= 1'b0;
            end else begin //  bus access in progress
                /* accumulate bus errors */
                if ((d_bus_err_i == 1'b1) || // bus error
                   ((ctrl_i.ir_opcode[5] == 1'b1) && (arbiter.pmp_w_err == 1'b1)) || // PMP store fault
                   ((ctrl_i.ir_opcode[5] == 1'b0) && (arbiter.pmp_r_err == 1'b1))) begin // PMP load fault
                    arbiter.err <= 1'b1;
                end
                // wait for normal termination or start of trap handling
                if ((d_bus_ack_i == 1'b1) || (ctrl_i.cpu_trap == 1'b1)) begin
                    arbiter.pend <= 1'b0;
                end
            end
        end
    end : data_access_arbiter

    /* wait for bus response */
    assign d_wait_o = ~d_bus_ack_i;

    /* output data access error to controller */
    assign ma_load_o  = ((arbiter.pend == 1'b1) && (ctrl_i.ir_opcode[5] == 1'b0) && (misaligned  == 1'b1)) ? 1'b1 : 1'b0;
    assign be_load_o  = ((arbiter.pend == 1'b1) && (ctrl_i.ir_opcode[5] == 1'b0) && (arbiter.err == 1'b1)) ? 1'b1 : 1'b0;
    assign ma_store_o = ((arbiter.pend == 1'b1) && (ctrl_i.ir_opcode[5] == 1'b1) && (misaligned  == 1'b1)) ? 1'b1 : 1'b0;
    assign be_store_o = ((arbiter.pend == 1'b1) && (ctrl_i.ir_opcode[5] == 1'b1) && (arbiter.err == 1'b1)) ? 1'b1 : 1'b0;

    /* data bus control interface (all source signals are driven by registers) */
    assign d_bus_we_o    = ctrl_i.bus_req & ( ctrl_i.ir_opcode[5]) & (~misaligned) & (~arbiter.pmp_w_err);
    assign d_bus_re_o    = ctrl_i.bus_req & (~ctrl_i.ir_opcode[5]) & (~misaligned) & (~arbiter.pmp_r_err);
    assign d_bus_fence_o = ctrl_i.bus_fence;
    assign d_bus_priv_o  = ctrl_i.bus_priv;

    // RISC-V Physical Memory Protection (PMP) ---------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* check address */
    always_comb begin : pmp_check_address
        for (int r = 0; r < PMP_NUM_REGIONS; ++r) begin
            // first entry: use ZERO as base and current entry as bound
            if (r == 0) begin
                pmp.i_cmp_ge[r] = 1'b1; // address is always greater than or equal to zero
                pmp.i_cmp_lt[r] = 1'b0; // unused
                pmp.d_cmp_ge[r] = 1'b1; // address is always greater than or equal to zero
                pmp.d_cmp_lt[r] = 1'b0; // unused
            end else begin // use previous entry as base and current entry as bound
                pmp.i_cmp_ge[r] = (fetch_pc_i[XLEN-1 : pmp_lsb_c] >= pmp_addr_i[r-1][XLEN-1 : pmp_lsb_c]);
                pmp.i_cmp_lt[r] = (fetch_pc_i[XLEN-1 : pmp_lsb_c] <  pmp_addr_i[r-0][XLEN-1 : pmp_lsb_c]);
                pmp.d_cmp_ge[r] = (    addr_i[XLEN-1 : pmp_lsb_c] >= pmp_addr_i[r-1][XLEN-1 : pmp_lsb_c]);
                pmp.d_cmp_lt[r] = (    addr_i[XLEN-1 : pmp_lsb_c] <  pmp_addr_i[r-0][XLEN-1 : pmp_lsb_c]);
            end
        end
    end : pmp_check_address

    /* check mode */
    always_comb begin : pmp_check_mode
        for (int r = 0; r < PMP_NUM_REGIONS; ++r) begin
            // TOR mode
            if (pmp_ctrl_i[r][pmp_cfg_ah_c : pmp_cfg_al_c] == pmp_mode_tor_c) begin
                if (r < (PMP_NUM_REGIONS-1)) begin
                    /* this saves a LOT of comparators */
                    pmp.i_match[r] = pmp.i_cmp_ge[r] & (~pmp.i_cmp_ge[r+1]);
                    pmp.d_match[r] = pmp.d_cmp_ge[r] & (~pmp.d_cmp_ge[r+1]);
                end else begin // very last entry
                    pmp.i_match[r] = pmp.i_cmp_ge[r] & pmp.i_cmp_lt[r];
                    pmp.d_match[r] = pmp.d_cmp_ge[r] & pmp.d_cmp_lt[r];
                end
            end else begin // entry disable
                pmp.i_match[r] = 1'b0;
                pmp.d_match[r] = 1'b0;
            end
        end
    end : pmp_check_mode

    /* check permission */
    always_comb begin : pmp_check_permission
        for (int r = 0; r < PMP_NUM_REGIONS; ++r) begin
            /* instruction fetch access */
            if (ctrl_i.cpu_priv == priv_mode_m_c) begin // Instruction fetch access: M mode always allows if lock bit not set, otherwise check permission
                pmp.perm_ex[r] = (~pmp_ctrl_i[r][pmp_cfg_l_c]) | pmp_ctrl_i[r][pmp_cfg_x_c];
            end else begin // U mode: always check permission
                pmp.perm_ex[r] = pmp_ctrl_i[r][pmp_cfg_x_c];
            end
            //
            /* load/store accesses from M mod (can also use U mode's permissions if MSTATUS.MPRV is set) */
            if (ctrl_i.bus_priv == priv_mode_m_c) begin // M mode: always allow if lock bit not set, otherwise check permission
                pmp.perm_rd[r] = (~pmp_ctrl_i[r][pmp_cfg_l_c]) | pmp_ctrl_i[r][pmp_cfg_r_c];
                pmp.perm_wr[r] = (~pmp_ctrl_i[r][pmp_cfg_l_c]) | pmp_ctrl_i[r][pmp_cfg_w_c];
            end else begin // U mode: always check permission
                pmp.perm_rd[r] = pmp_ctrl_i[r][pmp_cfg_r_c];
                pmp.perm_wr[r] = pmp_ctrl_i[r][pmp_cfg_w_c];
            end
        end
    end : pmp_check_permission

    /* check for access fault (using static prioritization) */
    always_comb begin : pmp_check_fault
        // declare local variable
        logic [PMP_NUM_REGIONS : 0] tmp_if_v, tmp_ld_v, tmp_st_v;
        //
        // -- > This is a *structural* description of a prioritization logic (a multiplexer chain).
        // -- > I prefer this style as I do not like using a loop with 'exit' - and I also think this style might be smaller
        // -- > and faster (could use the carry chain?!) as the synthesizer has less freedom doing what *I* want. ;)
        tmp_if_v[PMP_NUM_REGIONS] = (ctrl_i.cpu_priv != priv_mode_m_c); // default: fault if U mode
        tmp_ld_v[PMP_NUM_REGIONS] = (ctrl_i.bus_priv != priv_mode_m_c); // default: fault if U mode
        tmp_st_v[PMP_NUM_REGIONS] = (ctrl_i.bus_priv != priv_mode_m_c); // default: fault if U mode
        //
        for (int r = PMP_NUM_REGIONS-1; r >= 0; r--) begin // start with lowest priority
            /* instruction fetch access */
            if (pmp.i_match[r] == 1'b1) begin // address matches region r
                tmp_if_v[r] = ~pmp.perm_ex[r]; // fault if no execute permission
            end else begin
                tmp_if_v[r] = tmp_if_v[r+1];
            end
            //
            /* data load/store access */
            if (pmp.d_match[r] == 1'b1) begin  // address matches region r
                tmp_ld_v[r] = ~pmp.perm_rd[r]; // fault if no read permission
                tmp_st_v[r] = ~pmp.perm_wr[r]; // fault if no write permission
            end else begin
                tmp_ld_v[r] = tmp_ld_v[r+1];
                tmp_st_v[r] = tmp_st_v[r+1];
            end
        end
        //
        pmp.if_fault = tmp_if_v[0];
        pmp.ld_fault = tmp_ld_v[0];
        pmp.st_fault = tmp_st_v[0];

        // -- > this is the behavioral version of the code above (instruction fetch access)
        //  pmp.if_fault <= bool_to_ulogic_f(ctrl_i.cpu_priv /= priv_mode_m_c); -- default: fault if U mode
        //  for r in 0 to PMP_NUM_REGIONS-1 loop
        //    if (pmp.i_match(r) = '1') then
        //      pmp.if_fault <= not pmp.perm_ex(r); -- fault if no execute permission
        //      exit;
        //    end if;
        //  end loop; -- r
    end : pmp_check_fault

    /* final PMP access fault signals (ignored when in debug mode) */
    assign if_pmp_fault = ((pmp.if_fault == 1'b1) && (PMP_NUM_REGIONS > 0) && (ctrl_i.cpu_debug == 1'b0)) ? 1'b1 : 1'b0;
    assign ld_pmp_fault = ((pmp.ld_fault == 1'b1) && (PMP_NUM_REGIONS > 0) && (ctrl_i.cpu_debug == 1'b0)) ? 1'b1 : 1'b0;
    assign st_pmp_fault = ((pmp.st_fault == 1'b1) && (PMP_NUM_REGIONS > 0) && (ctrl_i.cpu_debug == 1'b0)) ? 1'b1 : 1'b0;

    /* instruction fetch PMP fault */
    assign i_pmp_fault_o = if_pmp_fault;

endmodule