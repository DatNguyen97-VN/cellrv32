// ##################################################################################################
// # << CELLRV32 - CPU Co-Processor: Bit-Manipulation Co-Processor Unit (RISC-V "B" Extension) >>   #
// # *********************************************************************************************  #
// # Supported B sub-extensions (Zb*):                                                              #
// # - Zba: Address-generation instructions                                                         #
// # - Zbb: Basic bit-manipulation instructions                                                     #
// # - Zbs: Single-bit instructions                                                                 #
// # - Zbc: Carry-less multiplication instructions                                                  #
// #                                                                                                #
// # Processor/CPU configuration generic FAST_MUL_EN is also used to enable implementation of fast  #
// # (full-parallel) logic for all shift-related B-instructions (ROL, ROR[I], CLZ, CTZ, CPOP).      #
// # ***********************************************************************************************#
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_bitmanip #(
    parameter XLEN          = 32, // data path width
    parameter FAST_SHIFT_EN = 1   // use barrel shifter for shift operations
) (
    /* global control */
    input logic                   clk_i,   // global clock, rising edge
    input logic                   rstn_i,  // global reset, low-active, async
    input ctrl_bus_t              ctrl_i,  // main control bus
    input logic                   start_i, // trigger operation
    /* data input */
    input logic [1:0]             cmp_i,   // comparator status
    input logic [XLEN-1:0]        rs1_i,   // rf source 1
    input logic [XLEN-1:0]        rs2_i,   // rf source 2
    input logic [index_size_f(XLEN)-1:0] shamt_i, // shift amount
    /* result and status */
    output logic [XLEN-1:0]       res_o,   // operation result
    output logic                  valid_o  // data output valid
);
    // Sub-extension configuration ----------------------------
    // Note that this configurations does NOT effect the CPU's (illegal) instruction decoding logic!
    const logic zbb_en_c = 1'b1;
    const logic zba_en_c = 1'b1;
    const logic zbc_en_c = 1'b1;
    const logic zbs_en_c = 1'b1;
    // --------------------------------------------------------

    /* Zbb - logic with negate */
    localparam int op_andn_c   = 0;
    localparam int op_orn_c    = 1;
    localparam int op_xnor_c   = 2;
    /* Zbb - count leading/trailing zero bits */
    localparam int op_clz_c    = 3;
    localparam int op_ctz_c    = 4;
    /* Zbb - count population */
    localparam int op_cpop_c   = 5;
    /* Zbb - int minimum/maximum */
    localparam int op_max_c    = 6; // signed/unsigned
    localparam int op_min_c    = 7; // signed/unsigned
    /* Zbb - sign- and zero-extension */
    localparam int op_sextb_c  = 8;
    localparam int op_sexth_c  = 9;
    localparam int op_zexth_c  = 10;
    /* Zbb - bitwise rotation */
    localparam int op_rol_c    = 11;
    localparam int op_ror_c    = 12; // also rori
    /* Zbb - or-combine */
    localparam int op_orcb_c   = 13;
    /* Zbb - byte-reverse */
    localparam int op_rev8_c   = 14;
    /* Zba - shifted-add */
    localparam int op_sh1add_c = 15;
    localparam int op_sh2add_c = 16;
    localparam int op_sh3add_c = 17;
    /* Zbs - single-bit operations */
    localparam int op_bclr_c   = 18;
    localparam int op_bext_c   = 19;
    localparam int op_binv_c   = 20;
    localparam int op_bset_c   = 21;
    /* Zbc - carry-less multiplication */
    localparam int op_clmul_c  = 22;
    localparam int op_clmulh_c = 23;
    localparam int op_clmulr_c = 24;
    //
    localparam int op_width_c = 25;

  /* controller */
  typedef enum logic[2:0] { S_IDLE, 
                            S_START_SHIFT, 
                            S_BUSY_SHIFT, 
                            S_START_CLMUL, 
                            S_BUSY_CLMUL
                            } ctrl_state_t;
  ctrl_state_t ctrl_state;
  logic [op_width_c-1:0] cmd, cmd_buf;
  logic valid;

  /* operand buffers */
  logic [XLEN-1:0]        rs1_reg;
  logic [XLEN-1:0]        rs2_reg;
  logic [index_size_f(XLEN)-1:0] sha_reg;
  logic                   less_reg;

  /* serial shifter */
  typedef struct {
    logic start;  
    logic run;     
    logic [index_size_f(XLEN):0] bcnt; // bit counter    
    logic [index_size_f(XLEN):0] cnt;  // iteration counter  
    logic [index_size_f(XLEN):0] cnt_max; 
    logic [XLEN-1:0] sreg;    
  } shifter_t;

  shifter_t shifter;

  /* barrel shifter */
  typedef logic [XLEN-1:0] bs_level_t [index_size_f(XLEN):0];
  bs_level_t bs_level;

  /* operation results */
  typedef logic [XLEN-1:0] res_t [op_width_c-1:0];
  res_t res_int, res_out;

  /* shifted-add unit */
  logic [XLEN-1:0] adder_core;

  /* one-hot decoder */
  logic [XLEN-1:0] one_hot_core;

  /* carry-less multiplier */
  typedef struct {
    logic                 start;
    logic                 busy;
    logic [XLEN-1:0]      rs2;
    logic [index_size_f(XLEN):0] cnt;
    logic [2*XLEN-1:0]    prod;
  } clmultiplier_t;
  clmultiplier_t clmul;

  // Sub-Extension Configuration ---------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  initial begin
    assert (1'b0)
    else $info("CELLRV32 CPU: Implementing bit-manipulation (B) sub-extensions %s %s %s %s",
                cond_sel_string_f(zba_en_c, "Zba ", ""),
                cond_sel_string_f(zbb_en_c, "Zbb ", ""),
                cond_sel_string_f(zbc_en_c, "Zbc ", ""),
                cond_sel_string_f(zbs_en_c, "Zbs ", ""));
  end
  
  // Instruction Decoding (One-Hot) ------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // A minimal decoding logic is used here just to distinguish between the different B instruction.
  // A more precise decoding as well as a valid-instruction-check is performed by the CPU control unit.

  /* Zbb - Basic bit-manipulation instructions */
  assign cmd[op_andn_c]  = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b10) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[1 : 0] == 2'b11)) ? 1'b1 : 1'b0;
  assign cmd[op_orn_c]   = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b10) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[1 : 0] == 2'b10)) ? 1'b1 : 1'b0;
  assign cmd[op_xnor_c]  = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b10) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[1 : 0] == 2'b00)) ? 1'b1 : 1'b0;
  //
  assign cmd[op_max_c]   = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b1) && (ctrl_i.ir_funct3[2 : 1] == 2'b11)) ? 1'b1 : 1'b0;
  assign cmd[op_min_c]   = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b1) && (ctrl_i.ir_funct3[2 : 1] == 2'b10)) ? 1'b1 : 1'b0;
  assign cmd[op_zexth_c] = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b0)) ? 1'b1 : 1'b0;
  //
  assign cmd[op_orcb_c]  = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b01) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2 : 0] == 3'b101)) ? 1'b1 : 1'b0;
  //
  assign cmd[op_clz_c]    = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct12[2 : 0] == 3'b000) && (ctrl_i.ir_opcode[5] == 1'b0) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_ctz_c]    = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct12[2 : 0] == 3'b001) && (ctrl_i.ir_opcode[5] == 1'b0) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_cpop_c]   = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct12[2 : 0] == 3'b010) && (ctrl_i.ir_opcode[5] == 1'b0) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_sextb_c]  = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct12[2 : 0] == 3'b100) && (ctrl_i.ir_opcode[5] == 1'b0) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_sexth_c]  = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct12[2 : 0] == 3'b101) && (ctrl_i.ir_opcode[5] == 1'b0) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_rol_c]    = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[2 : 0] == 3'b001) && (ctrl_i.ir_opcode[5] == 1'b1)) ? 1'b1 : 1'b0;
  assign cmd[op_ror_c]    = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[2 : 0] == 3'b101) && (ctrl_i.ir_funct3[2] == 1'b1)) ? 1'b1 : 1'b0;
  assign cmd[op_rev8_c]   = ((zbb_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2 : 0] == 3'b101)) ? 1'b1 : 1'b0;

  /* Zba - Address generation instructions */
  assign cmd[op_sh1add_c] = ((zba_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b01) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[2 : 1] == 2'b01)) ? 1'b1 : 1'b0;
  assign cmd[op_sh2add_c] = ((zba_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b01) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[2 : 1] == 2'b10)) ? 1'b1 : 1'b0;
  assign cmd[op_sh3add_c] = ((zba_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b01) && (ctrl_i.ir_funct12[7] == 1'b0) && (ctrl_i.ir_funct3[2 : 1] == 2'b11)) ? 1'b1 : 1'b0;

  /* Zbs - Single-bit instructions */
  assign cmd[op_bclr_c]   = ((zbs_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b10) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_bext_c]   = ((zbs_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b10) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2] == 1'b1)) ? 1'b1 : 1'b0;
  assign cmd[op_binv_c]   = ((zbs_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b11) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;
  assign cmd[op_bset_c]   = ((zbs_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b01) && (ctrl_i.ir_funct12[7] == 1'b1) && (ctrl_i.ir_funct3[2] == 1'b0)) ? 1'b1 : 1'b0;

  /* Zbc - Carry-less multiplication instructions */
  assign cmd[op_clmul_c]  = ((zbc_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b1) && (ctrl_i.ir_funct3[2 : 0] == 3'b001)) ? 1'b1 : 1'b0;
  assign cmd[op_clmulh_c] = ((zbc_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b1) && (ctrl_i.ir_funct3[2 : 0] == 3'b011)) ? 1'b1 : 1'b0;
  assign cmd[op_clmulr_c] = ((zbc_en_c == 1'b1) && (ctrl_i.ir_funct12[10 : 9] == 2'b00) && (ctrl_i.ir_funct12[5] == 1'b1) && (ctrl_i.ir_funct3[2 : 0] == 3'b010)) ? 1'b1 : 1'b0;
  
  // Co-Processor Controller -------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  always_ff @( posedge clk_i or negedge rstn_i ) begin : coprocessor_ctrl
    if (rstn_i == 1'b0) begin
        ctrl_state    <= S_IDLE;
        cmd_buf       <= '0;
        rs1_reg       <= '0;
        rs2_reg       <= '0;
        sha_reg       <= '0;
        less_reg      <= '0;
        clmul.start   <= '0;
        shifter.start <= '0;
        valid         <= '0;
    end else begin
        /* defaults */
        shifter.start <= '0;
        clmul.start   <= '0;
        valid         <= '0;

        /* operand registers */
        if (start_i == 1'b1) begin
            less_reg <= cmp_i[cmp_less_c];
            cmd_buf  <= cmd;
            rs1_reg  <= rs1_i;
            rs2_reg  <= rs2_i;
            sha_reg  <= shamt_i;
        end

        /* FSM */
        unique case (ctrl_state)
            // wait for operation trigger
            S_IDLE : begin
                if (start_i == 1'b1) begin
                    // multi-cycle shift operation
                    if ((FAST_SHIFT_EN == 1'b1) && ((cmd[op_clz_c] || cmd[op_ctz_c] 
                        || cmd[op_cpop_c] || cmd[op_ror_c] || cmd[op_rol_c]) == 1'b1)) begin
                        shifter.start <= 1'b1;
                        ctrl_state    <= S_START_SHIFT;
                    // multi-cycle clmul operation
                    end else if ((zbc_en_c == 1'b1) && ((cmd[op_clmul_c] 
                                 || cmd[op_clmulh_c] || cmd[op_clmulr_c]) == 1'b1)) begin
                        clmul.start <= 1'b1;
                        ctrl_state  <= S_START_CLMUL;
                    end else begin
                        valid      <= 1'b1;
                        ctrl_state <= S_IDLE;
                    end
                end
            end

            // one cycle delay to start shift operation
            S_START_SHIFT : begin
                ctrl_state <= S_BUSY_SHIFT;
            end

            // wait for multi-cycle shift operation to finish
            S_BUSY_SHIFT : begin
                // abort on trap
                if ((shifter.run == 1'b0) || (ctrl_i.cpu_trap == 1'b1)) begin
                    valid      <= 1'b1;
                    ctrl_state <= S_IDLE;
                end
            end

            // one cycle delay to start clmul operation
            S_START_CLMUL : begin
                ctrl_state <= S_BUSY_CLMUL;
            end

            // wait for multi-cycle clmul operation to finish
            S_BUSY_CLMUL : begin
                // abort on trap
                if ((clmul.busy == 1'b0) || (ctrl_i.cpu_trap == 1'b1)) begin
                    valid      <= 1'b1;
                    ctrl_state <= S_IDLE;
                end
            end
            default: begin
                ctrl_state <= S_IDLE;
            end
        endcase
    end
  end : coprocessor_ctrl

  // Shifter Function Core (iterative: small but slow) -----------------------------------------
  // -------------------------------------------------------------------------------------------
  generate
    begin : serial_shifter
        if (FAST_SHIFT_EN == 1'b0) begin
            logic new_bit_v;
            always_ff @( posedge clk_i ) begin : shifter_unit
                if (shifter.start == 1'b1) begin  //  trigger new shift
                    shifter.cnt <= 1'b0;
                    /* shift operand */
                        // clz, rol
                    if ((cmd_buf[op_clz_c] == 1'b1) || (cmd_buf[op_rol_c] == 1'b1))
                         shifter.sreg <= bit_rev_f(rs1_reg); // reverse - we can only do right shifts here
                    else //  ctz, cpop, ror
                         shifter.sreg <= rs1_reg;
                    /* max shift amount */
                    if (cmd_buf[op_cpop_c] == 1'b1) begin // population count
                        shifter.cnt_max <= 1'b0;
                        shifter.cnt_max[$bits(shifter.cnt_max)-1] <= 1'b1;
                    end else
                        shifter.cnt_max <= {1'b0, sha_reg};
                    shifter.bcnt <= '0;
                end else if (shifter.run == 1'b1) begin // right shifts only
                    new_bit_v     = ((cmd_buf[op_ror_c] || cmd_buf[op_rol_c]) && shifter.sreg[0]) || (cmd_buf[op_clz_c] || cmd_buf[op_ctz_c]);
                    shifter.sreg <= {new_bit_v, shifter.sreg[$bits(shifter.sreg)-1 : 1]}; // ro[r/l]/lsr(for counting)
                    shifter.cnt  <= shifter.cnt + 1; // iteration counter
                    if (shifter.sreg[0] == 1'b1) begin
                        shifter.bcnt <= shifter.bcnt + 1; // bit counter
                    end
                end
            end : shifter_unit
            
            /* run control */
            always_comb begin : shifter_unit_ctrl
                /* keep shifting until all bits are processed */
                if ((cmd_buf[op_clz_c] == 1'b1) || (cmd_buf[op_ctz_c] == 1'b1)) // count leading/trailing zeros
                    shifter.run = ~shifter.sreg[0];
                else if (shifter.cnt == shifter.cnt_max) //  population count / rotate
                        shifter.run = 1'b0;
                else 
                        shifter.run = 1'b1;
            end : shifter_unit_ctrl
        end
    end : serial_shifter
  endgenerate

  // Shifter Function Core (parallel: fast but large) ------------------------------------------
  // -------------------------------------------------------------------------------------------
  genvar i;
  generate
        if (FAST_SHIFT_EN == 1'b1) begin : parallel_shifter
            /* barrel shifter array */
            // input level: convert left shifts to right shifts
            assign bs_level[index_size_f(XLEN)] = (cmd_buf[op_rol_c == 1'b1]) // is left shift?, if right is reverse bit order of input operand.
                                                  ? bit_rev_f(rs1_reg) : rs1_reg;
            for (i = index_size_f(XLEN)-1; i >= 0; --i) begin : shifter_array
                assign bs_level[i][XLEN-1 : XLEN-(2**i)] = (sha_reg[i] == 1'b1) ? bs_level[i+1][(2**i)-1 : 0]  : bs_level[i+1][XLEN-1 : XLEN-(2**i)];
                assign bs_level[i][(XLEN-(2**i))-1 : 0]  = (sha_reg[i] == 1'b1) ? bs_level[i+1][XLEN-1 : 2**i] : bs_level[i+1][(XLEN-(2**i))-1 : 0];
            end : shifter_array

            /* barrel_shifter */
            assign shifter.sreg = bs_level[0]; // rol/ror[i]

            /* population count */
            assign shifter.bcnt = (index_size_f(XLEN)+1)'(popcount_f(rs1_reg)); // CPOP

            /* count leading/trailing zeros */
            assign shifter.cnt  = (cmd_buf[op_clz_c] == 1'b1) ? 
                                    (index_size_f(XLEN)+1)'(leading_zeros_f(rs1_reg)) // CLZ
                                  : (index_size_f(XLEN)+1)'(leading_zeros_f(bit_rev_f(rs1_reg))); // CTZ

            assign shifter.run  = 1'b0; // we are done already!
        end : parallel_shifter
  endgenerate

  // Shifted-Add Core --------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  logic [XLEN-1:0] opb_v;
  always_comb begin : shift_adder
    unique case (ctrl_i.ir_funct3[2:1])
        2'b01 : opb_v = {rs1_reg[$bits(rs1_reg)-2 : 0], 1'b0};   // << 1
        2'b10 : opb_v = {rs1_reg[$bits(rs1_reg)-3 : 0], 2'b0};   // << 2
        default: begin
                opb_v = {rs1_reg[$bits(rs1_reg)-4 : 0], 3'b0};   // << 3
        end
    endcase
    //
    adder_core = rs2_reg + opb_v;
  end : shift_adder

  // One-Hot Generator Core --------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  always_comb begin : shift_one_hot
    one_hot_core = '0;
    one_hot_core[int'(sha_reg)] = 1'b1;
  end : shift_one_hot
  
  // Carry-Less Multiplication Core ------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  always_ff @( posedge clk_i ) begin : clmul_core
    if (clmul.start == 1'b1) begin // start new multiplication
        clmul.cnt                     <= '0;
        clmul.cnt[$bits(clmul.cnt)-1] <= '1;
        clmul.prod[63 : 32]           <= '0;
        if (cmd_buf[op_clmulr_c] == 1'b1) begin // reverse input operands?
            clmul.prod[31 : 0] <= bit_rev_f(rs1_reg);
        end else begin
            clmul.prod[31 : 0] <= rs1_reg;
        end
    end else if (clmul.busy == 1'b1) begin // processing
        clmul.cnt <= clmul.cnt - 1'b1;
        if (clmul.prod[0] == 1'b1) begin
            clmul.prod[62 : 31] <= clmul.prod[63 : 32] ^ clmul.rs2;
        end else begin
            clmul.prod[62 : 31] <= clmul.prod[63 : 32];
        end
        clmul.prod[30 : 0] <= clmul.prod[31 : 1];
    end
  end : clmul_core

  /* reverse input operands? */
  assign clmul.rs2 = (cmd_buf[op_clmulr_c] == 1'b1) ? bit_rev_f(rs2_reg) : rs2_reg;

  /* multiplier busy? */
  assign clmul.busy = ((|clmul.cnt) == 1'b1) ? 1'b1 : 1'b0;

  // Operation Results -------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  /* logic with negate */
  assign res_int[op_andn_c] = rs1_reg & (~rs2_reg);
  assign res_int[op_orn_c]  = rs1_reg | (~rs2_reg);
  assign res_int[op_xnor_c] = rs1_reg ^ (~rs2_reg);
  
  /* count leading/trailing zeros */
  assign res_int[op_clz_c][XLEN-1 : $bits(shifter.cnt)] = '0;
  assign res_int[op_clz_c][$bits(shifter.cnt)-1 : 0] = shifter.cnt;
  assign res_int[op_ctz_c] = '0; // unused/redundant

  /* count set bits */
  assign res_int[op_cpop_c][XLEN-1 : $bits(shifter.bcnt)] = '0;
  assign res_int[op_cpop_c][$bits(shifter.bcnt)-1 : 0] = shifter.bcnt;

  /* min/max select */
  assign res_int[op_min_c] = ((less_reg ^ cmd_buf[op_max_c]) == 1'b1) ? rs1_reg : rs2_reg;
  assign res_int[op_max_c] = '0; // unused/redundant

  /* sign-extension */
  assign res_int[op_sextb_c][XLEN-1:8]  = (rs1_reg[7] == 1'b1) ? '1 : '0;
  assign res_int[op_sextb_c][7:0]       = rs1_reg[7:0]; // sign-extend byte
  assign res_int[op_sexth_c][XLEN-1:16] = (rs1_reg[15] == 1'b1) ? '1 : '0;
  assign res_int[op_sexth_c][15:0]      = rs1_reg[15:0]; // sign-extend half-word
  assign res_int[op_zexth_c][XLEN-1:16] = '0;
  assign res_int[op_zexth_c][15:0]      = rs1_reg[15:0]; // zero-extend half-word
  
  /* rotate right/left */
  assign res_int[op_ror_c] = shifter.sreg;
  assign res_int[op_rol_c] = bit_rev_f(shifter.sreg); // reverse to compensate internal right-only shifts
  
  /* or-combine.byte */
  generate
    begin : or_combine_gen
    genvar i;
        for (i = 0; i < (XLEN/8); ++i) begin :sub_byte_loop
            assign res_int[op_orcb_c][i*8+7 : i*8] = ((|rs1_reg[i*8+7 : i*8]) == 1'b1) ? '1 : '0;
        end : sub_byte_loop
    end : or_combine_gen
  endgenerate

  /* reversal.8 (byte swap) */
  assign res_int[op_rev8_c] = bswap32_f(rs1_reg);

  /* address generation instructions */
  assign res_int[op_sh1add_c] = adder_core;
  assign res_int[op_sh2add_c] = '0; // unused/redundant
  assign res_int[op_sh3add_c] = '0; // unused/redundant

  /* single-bit instructions */
  assign res_int[op_bclr_c]           = rs1_reg & (~one_hot_core);
  assign res_int[op_bext_c][XLEN-1:1] = '0;
  assign res_int[op_bext_c][0]        = (|(rs1_reg & one_hot_core) == 1'b1) ? 1'b1 : 1'b0;
  assign res_int[op_binv_c]           = rs1_reg ^ one_hot_core;
  assign res_int[op_bset_c]           = rs1_reg | one_hot_core;

  /* carry-less multiplication instructions */
  assign res_int[op_clmul_c]  = clmul.prod[31 : 0];
  assign res_int[op_clmulh_c] = clmul.prod[63 : 32];
  assign res_int[op_clmulr_c] = bit_rev_f(clmul.prod[31 : 0]);

  // Output Selector ------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  assign res_out[op_andn_c]  = (cmd_buf[op_andn_c]  == 1'b1) ? res_int[op_andn_c] : '0;
  assign res_out[op_orn_c]   = (cmd_buf[op_orn_c]   == 1'b1) ? res_int[op_orn_c]  : '0;
  assign res_out[op_xnor_c]  = (cmd_buf[op_xnor_c]  == 1'b1) ? res_int[op_xnor_c] : '0;
  assign res_out[op_clz_c]   = ((cmd_buf[op_clz_c] || cmd_buf[op_ctz_c]) == 1'b1) ? res_int[op_clz_c] : '0;
  assign res_out[op_ctz_c]   = '0; // unused/redundant
  assign res_out[op_cpop_c]  = (cmd_buf[op_cpop_c]  == 1'b1) ? res_int[op_cpop_c] : '0;
  assign res_out[op_min_c]   = ((cmd_buf[op_min_c] || cmd_buf[op_max_c]) == 1'b1) ? res_int[op_min_c] : '0;
  assign res_out[op_max_c]   = '0; // unused/redundant
  assign res_out[op_sextb_c] = (cmd_buf[op_sextb_c] == 1'b1) ? res_int[op_sextb_c] : '0;
  assign res_out[op_sexth_c] = (cmd_buf[op_sexth_c] == 1'b1) ? res_int[op_sexth_c] : '0;
  assign res_out[op_zexth_c] = (cmd_buf[op_zexth_c] == 1'b1) ? res_int[op_zexth_c] : '0;
  assign res_out[op_ror_c]   = (cmd_buf[op_ror_c ]  == 1'b1) ? res_int[op_ror_c ]  : '0;
  assign res_out[op_rol_c]   = (cmd_buf[op_rol_c ]  == 1'b1) ? res_int[op_rol_c ]  : '0;
  assign res_out[op_orcb_c]  = (cmd_buf[op_orcb_c]  == 1'b1) ? res_int[op_orcb_c]  : '0;
  assign res_out[op_rev8_c]  = (cmd_buf[op_rev8_c]  == 1'b1) ? res_int[op_rev8_c]  : '0;
  //
  assign res_out[op_sh1add_c] = ((cmd_buf[op_sh1add_c] || cmd_buf[op_sh2add_c] || cmd_buf[op_sh3add_c])  == 1'b1) ? res_int[op_sh1add_c] : '0;
  assign res_out[op_sh2add_c] = '0; // unused/redundant
  assign res_out[op_sh3add_c] = '0; // unused/redundant
  //
  assign res_out[op_bclr_c] = (cmd_buf[op_bclr_c] == 1'b1) ? res_int[op_bclr_c] : '0;
  assign res_out[op_bext_c] = (cmd_buf[op_bext_c] == 1'b1) ? res_int[op_bext_c] : '0;
  assign res_out[op_binv_c] = (cmd_buf[op_binv_c] == 1'b1) ? res_int[op_binv_c] : '0;
  assign res_out[op_bset_c] = (cmd_buf[op_bset_c] == 1'b1) ? res_int[op_bset_c] : '0;
  //
  assign res_out[op_clmul_c ] = (cmd_buf[op_clmul_c ] == 1'b1) ? res_int[op_clmul_c ] : '0;
  assign res_out[op_clmulh_c] = (cmd_buf[op_clmulh_c] == 1'b1) ? res_int[op_clmulh_c] : '0;
  assign res_out[op_clmulr_c] = (cmd_buf[op_clmulr_c] == 1'b1) ? res_int[op_clmulr_c] : '0;

  // Output Gate -------------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  always_ff @( posedge clk_i ) begin : output_gate
    res_o <= '0; // default
    if (valid == 1'b1) begin
        res_o <= res_out[op_andn_c]   | res_out[op_orn_c]    | res_out[op_xnor_c]  |
                 res_out[op_clz_c]    | res_out[op_cpop_c]   | // res_out(op_ctz_c) is unused here
                 res_out[op_min_c]    | // res_out(op_max_c) is unused here
                 res_out[op_sextb_c]  | res_out[op_sexth_c]  | res_out[op_zexth_c] |
                 res_out[op_ror_c]    | res_out[op_rol_c]    |
                 res_out[op_orcb_c]   | res_out[op_rev8_c]   |
                 res_out[op_sh1add_c] | // res_out(op_sh2add_c) and res_out(op_sh3add_c) are unused here
                 res_out[op_bclr_c]   | res_out[op_bext_c]   | res_out[op_binv_c]  | res_out[op_bset_c] |
                 res_out[op_clmul_c]  | res_out[op_clmulh_c] | res_out[op_clmulr_c];
    end
  end : output_gate

  /* valid output */
  assign valid_o = valid;
endmodule