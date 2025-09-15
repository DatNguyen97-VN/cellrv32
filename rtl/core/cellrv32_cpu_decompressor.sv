// ##################################################################################################
// # << CELLRV32 - CPU: Compressed Instructions Decoder (RISC-V "C" Extension) >>                   #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_decompressor #(
    parameter FPU_ENABLE = 1  // floating-point instruction enabled
) (
    /* instruction input */
    input logic [15:0]  ci_instr16_i, // compressed instruction input
    /* instruction output */
    output logic        ci_illegal_o, // is an illegal compressed instruction
    output logic [31:0] ci_instr32_o  // 32-bit decompressed instruction
);
    
    /* compressed instruction layout */
    localparam  int ci_opcode_lsb_c =  0;
    localparam  int ci_opcode_msb_c =  1;
    localparam  int ci_rd_3_lsb_c   =  2;
    localparam  int ci_rd_3_msb_c   =  4;
    localparam  int ci_rd_5_lsb_c   =  7;
    localparam  int ci_rd_5_msb_c   = 11;
    localparam  int ci_rs1_3_lsb_c  =  7;
    localparam  int ci_rs1_3_msb_c  =  9;
    localparam  int ci_rs1_5_lsb_c  =  7;
    localparam  int ci_rs1_5_msb_c  = 11;
    localparam  int ci_rs2_3_lsb_c  =  2;
    localparam  int ci_rs2_3_msb_c  =  4;
    localparam  int ci_rs2_5_lsb_c  =  2;
    localparam  int ci_rs2_5_msb_c  =  6;
    localparam  int ci_funct3_lsb_c = 13;
    localparam  int ci_funct3_msb_c = 15;

    // Compressed Instruction Decoder ------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    logic [20:0] imm20_v;
    logic [12:0] imm12_v;
    //
    always_comb begin
        /* defaults */
        ci_illegal_o = 1'b0;
        ci_instr32_o = '0;
        
        /* helper: 22-bit sign-extended immediate for J/JAL */
        imm20_v = ci_instr16_i[12] ? '1 : '0; // sign extension
        imm20_v[00] = 1'b0;
        imm20_v[01] = ci_instr16_i[3];
        imm20_v[02] = ci_instr16_i[4];
        imm20_v[03] = ci_instr16_i[5];
        imm20_v[04] = ci_instr16_i[11];
        imm20_v[05] = ci_instr16_i[2];
        imm20_v[06] = ci_instr16_i[7];
        imm20_v[07] = ci_instr16_i[6];
        imm20_v[08] = ci_instr16_i[9];
        imm20_v[09] = ci_instr16_i[10];
        imm20_v[10] = ci_instr16_i[8];
        imm20_v[11] = ci_instr16_i[12];
    
        /* helper: 12-bit sign-extended immediate for branches */
        imm12_v = ci_instr16_i[12] ? '1 : '0; // sign extension
        imm12_v[00] = 1'b0;
        imm12_v[01] = ci_instr16_i[3];
        imm12_v[02] = ci_instr16_i[4];
        imm12_v[03] = ci_instr16_i[10];
        imm12_v[04] = ci_instr16_i[11];
        imm12_v[05] = ci_instr16_i[2];
        imm12_v[06] = ci_instr16_i[5];
        imm12_v[07] = ci_instr16_i[6];
        imm12_v[08] = ci_instr16_i[12];

        /* actual decoder */
        unique case (ci_instr16_i[ci_opcode_msb_c : ci_opcode_lsb_c])
            // C0: Register-Based Loads and Stores
            2'b00 : begin
                unique case (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c])
                    //  C.LW / C.FLW
                    3'b010, 3'b011 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_load_c;
                        ci_instr32_o[21 : 20]                                 = 2'b00;
                        ci_instr32_o[22]                                      = ci_instr16_i[6];
                        ci_instr32_o[23]                                      = ci_instr16_i[10];
                        ci_instr32_o[24]                                      = ci_instr16_i[11];
                        ci_instr32_o[25]                                      = ci_instr16_i[12];
                        ci_instr32_o[26]                                      = ci_instr16_i[5];
                        ci_instr32_o[31 : 27]                                 = '0;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_lw_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = {2'b01, ci_instr16_i[ci_rs1_3_msb_c : ci_rs1_3_lsb_c]}; // x8 - x15
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = {2'b01, ci_instr16_i[ci_rd_3_msb_c : ci_rd_3_lsb_c]};   // x8 - x15
                        //
                        // C.FLW
                        if ((ci_instr16_i[ci_funct3_lsb_c] == 1'b1) && (FPU_ENABLE == 0)) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.SW / C.FSW
                    3'b110, 3'b111 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_store_c;
                        ci_instr32_o[08 : 07]                                 = 2'b00;
                        ci_instr32_o[09]                                      = ci_instr16_i[6];
                        ci_instr32_o[10]                                      = ci_instr16_i[10];
                        ci_instr32_o[11]                                      = ci_instr16_i[11];
                        ci_instr32_o[25]                                      = ci_instr16_i[12];
                        ci_instr32_o[26]                                      = ci_instr16_i[5];
                        ci_instr32_o[31 : 27]                                 = '0;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_sw_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = {2'b01, ci_instr16_i[ci_rs1_3_msb_c : ci_rs1_3_lsb_c]}; // x8 - x15
                        ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c]       = {2'b01, ci_instr16_i[ci_rs2_3_msb_c : ci_rs2_3_lsb_c]}; // x8 - x15
                        //
                        if ((ci_instr16_i[ci_funct3_lsb_c] == 1'b1) && (FPU_ENABLE == 0)) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    default: begin // "000": Illegal_instruction, C.ADDI4SPN; others: illegal
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = 5'b00010; // stack pointer
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = {2'b01, ci_instr16_i[ci_rd_3_msb_c : ci_rd_3_lsb_c]};
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_subadd_c;
                        ci_instr32_o[instr_imm12_msb_c : instr_imm12_lsb_c]   = '0; // zero extend
                        ci_instr32_o[instr_imm12_lsb_c + 0]                   = 1'b0;
                        ci_instr32_o[instr_imm12_lsb_c + 1]                   = 1'b0;
                        ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[6];
                        ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                        ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[11];
                        ci_instr32_o[instr_imm12_lsb_c + 5]                   = ci_instr16_i[12];
                        ci_instr32_o[instr_imm12_lsb_c + 6]                   = ci_instr16_i[7];
                        ci_instr32_o[instr_imm12_lsb_c + 7]                   = ci_instr16_i[8];
                        ci_instr32_o[instr_imm12_lsb_c + 8]                   = ci_instr16_i[9];
                        ci_instr32_o[instr_imm12_lsb_c + 9]                   = ci_instr16_i[10];
                        //
                        if ((ci_instr16_i[12:5] == 8'b00000000) || // canonical illegal C instruction or C.ADDI4SPN with nzuimm = 0
                            (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c] == 3'b001) || // C.FLS / C.LQ
                            (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c] == 3'b100) || // reserved
                            (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c] == 3'b101)) begin // C.FSD / C.SQ
                            ci_illegal_o = 1'b1;
                        end
                    end
                endcase
            end
            // C1: Control Transfer Instructions, int Constant-Generation Instructions
            2'b01 : begin
                unique case (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c])
                    // C.J, C.JAL
                    3'b101, 3'b001 : begin
                        // C.J
                        if (ci_instr16_i[ci_funct3_msb_c] == 1'b1) begin
                            ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c] = 5'b00000; // discard return address
                        end else begin // C.JAL
                            ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c] = 5'b00001; // save return address to link register
                        end
                        //
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_jal_c;
                        ci_instr32_o[19 : 12]                                 = imm20_v[19 : 12];
                        ci_instr32_o[20]                                      = imm20_v[11];
                        ci_instr32_o[30 : 21]                                 = imm20_v[10 : 01];
                        ci_instr32_o[31]                                      = imm20_v[20];
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.BEQZ, C.BNEZ
                    3'b110, 3'b111 : begin
                        // C.BEQZ
                        if (ci_instr16_i[ci_funct3_lsb_c] == 1'b0) begin
                            ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_beq_c;
                        end else begin // C.BNEZ
                            ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_bne_c;
                        end
                        //
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_branch_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = {2'b01, ci_instr16_i[ci_rs1_3_msb_c : ci_rs1_3_lsb_c]};
                        ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c]       = 5'b00000; // x0
                        ci_instr32_o[07]                                      = imm12_v[11];
                        ci_instr32_o[11 : 08]                                 = imm12_v[04 : 01];
                        ci_instr32_o[30 : 25]                                 = imm12_v[10 : 05];
                        ci_instr32_o[31]                                      = imm12_v[12];
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.LI
                    3'b010 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_subadd_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = 5'b00000; // x0
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                        ci_instr32_o[instr_imm12_msb_c : instr_imm12_lsb_c]   = ci_instr16_i[12] ? '1 : '0; // sign extend
                        ci_instr32_o[instr_imm12_lsb_c + 0]                   = ci_instr16_i[2];
                        ci_instr32_o[instr_imm12_lsb_c + 1]                   = ci_instr16_i[3];
                        ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[4];
                        ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                        ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[6];
                        ci_instr32_o[instr_imm12_lsb_c + 5]                   = ci_instr16_i[12];
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.LUI / C.ADDI16SP
                    3'b011 : begin
                        // C.ADDI16SP
                        if (ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c] == 5'b00010) begin
                            ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c]  = opcode_alui_c;
                            ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c]  = funct3_subadd_c;
                            //ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]          = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                            ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]        = 5'b00010; // stack pointer
                            ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]          = 5'b00010; // stack pointer
                            ci_instr32_o[instr_imm12_msb_c : instr_imm12_lsb_c]    = ci_instr16_i[12] ? '1 : 1'b0; // sign extend
                            ci_instr32_o[instr_imm12_lsb_c + 0]                    = 1'b0;
                            ci_instr32_o[instr_imm12_lsb_c + 1]                    = 1'b0;
                            ci_instr32_o[instr_imm12_lsb_c + 2]                    = 1'b0;
                            ci_instr32_o[instr_imm12_lsb_c + 3]                    = 1'b0;
                            ci_instr32_o[instr_imm12_lsb_c + 4]                    = ci_instr16_i[6];
                            ci_instr32_o[instr_imm12_lsb_c + 5]                    = ci_instr16_i[2];
                            ci_instr32_o[instr_imm12_lsb_c + 6]                    = ci_instr16_i[5];
                            ci_instr32_o[instr_imm12_lsb_c + 7]                    = ci_instr16_i[3];
                            ci_instr32_o[instr_imm12_lsb_c + 8]                    = ci_instr16_i[4];
                            ci_instr32_o[instr_imm12_lsb_c + 9]                    = ci_instr16_i[12];
                        end else begin // C.LUI
                            ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_lui_c;
                            ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                            ci_instr32_o[instr_imm20_msb_c : instr_imm20_lsb_c]   = ci_instr16_i[12] ? '1 : '0; // sign extend
                            ci_instr32_o[instr_imm20_lsb_c + 0]                   = ci_instr16_i[2];
                            ci_instr32_o[instr_imm20_lsb_c + 1]                   = ci_instr16_i[3];
                            ci_instr32_o[instr_imm20_lsb_c + 2]                   = ci_instr16_i[4];
                            ci_instr32_o[instr_imm20_lsb_c + 3]                   = ci_instr16_i[5];
                            ci_instr32_o[instr_imm20_lsb_c + 4]                   = ci_instr16_i[6];
                            ci_instr32_o[instr_imm20_lsb_c + 5]                   = ci_instr16_i[12];
                        end
                        //
                        // reserved if nzimm = 0
                        if ((ci_instr16_i[6 : 2] == 5'b00000) && (ci_instr16_i[12] == 1'b0)) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.NOP (rd=0) / C.ADDI
                    3'b000 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_subadd_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = ci_instr16_i[ci_rs1_5_msb_c : ci_rs1_5_lsb_c];
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                        ci_instr32_o[instr_imm12_msb_c : instr_imm12_lsb_c]   = ci_instr16_i[12] ? '1 : '0; // sign extend
                        ci_instr32_o[instr_imm12_lsb_c + 0]                   = ci_instr16_i[2];
                        ci_instr32_o[instr_imm12_lsb_c + 1]                   = ci_instr16_i[3];
                        ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[4];
                        ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                        ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[6];
                        ci_instr32_o[instr_imm12_lsb_c + 5]                   = ci_instr16_i[12];
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // 100: C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND, reserved
                    default: begin
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]   = {2'b01, ci_instr16_i[ci_rs1_3_msb_c : ci_rs1_3_lsb_c]};
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c] = {2'b01, ci_instr16_i[ci_rs1_3_msb_c : ci_rs1_3_lsb_c]};
                        ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c] = {2'b01, ci_instr16_i[ci_rs2_3_msb_c : ci_rs2_3_lsb_c]};
                        //
                        unique case (ci_instr16_i[11 : 10])
                            // C.SRLI, C.SRAI
                            2'b00, 2'b01 : begin
                                if (ci_instr16_i[10] == 1'b0) begin // C.SRLI
                                    ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0000000;
                                end else begin // C.SRAI
                                    ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0100000;
                                end
                                //
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                                ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_sr_c;
                                ci_instr32_o[instr_imm12_lsb_c + 0]                   = ci_instr16_i[2];
                                ci_instr32_o[instr_imm12_lsb_c + 1]                   = ci_instr16_i[3];
                                ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[4];
                                ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                                ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[6];
                                //
                                // nzuimm[5] = 1 -> RV32 custom
                                if (ci_instr16_i[12] == 1'b1) begin
                                    ci_illegal_o = 1'b1;
                                end
                            end
                            // C.ANDI
                            2'b10 : begin
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                                ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_and_c;
                                ci_instr32_o[instr_imm12_msb_c : instr_imm12_lsb_c]   = ci_instr16_i[12] ? '1 : '0; // sign extend
                                ci_instr32_o[instr_imm12_lsb_c + 0]                   = ci_instr16_i[2];
                                ci_instr32_o[instr_imm12_lsb_c + 1]                   = ci_instr16_i[3];
                                ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[4];
                                ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                                ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[6];
                                ci_instr32_o[instr_imm12_lsb_c + 5]                   = ci_instr16_i[12];
                            end
                            // "11" = register-register operation
                            default: begin
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alu_c;
                                //
                                unique case (ci_instr16_i[6:5])
                                    // C.SUB
                                    2'b00 : begin
                                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_subadd_c;
                                        ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0100000;
                                    end
                                    // C.XOR
                                    2'b01 : begin
                                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_xor_c;
                                        ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0000000;
                                    end
                                    // C.OR
                                    2'b10 : begin
                                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_or_c;
                                        ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0000000;
                                    end
                                    // C.AND
                                    default: begin
                                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_and_c;
                                        ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0000000;
                                    end
                                endcase
                                // Reserved
                                ci_illegal_o = ci_instr16_i[12];
                            end
                        endcase
                    end
                endcase
            end
            // C2: Stack-Pointer-Based Loads and Stores, Control Transfer Instructions (or C3, which is not a RVC instruction)
            default: begin
                unique case (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c])
                    // C.SLLI
                    3'b000 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alui_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = ci_instr16_i[ci_rs1_5_msb_c : ci_rs1_5_lsb_c];
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rs1_5_msb_c : ci_rs1_5_lsb_c];
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_sll_c;
                        ci_instr32_o[instr_funct7_msb_c : instr_funct7_lsb_c] = 7'b0000000;
                        ci_instr32_o[instr_imm12_lsb_c + 0]                   = ci_instr16_i[2];
                        ci_instr32_o[instr_imm12_lsb_c + 1]                   = ci_instr16_i[3];
                        ci_instr32_o[instr_imm12_lsb_c + 2]                   = ci_instr16_i[4];
                        ci_instr32_o[instr_imm12_lsb_c + 3]                   = ci_instr16_i[5];
                        ci_instr32_o[instr_imm12_lsb_c + 4]                   = ci_instr16_i[6];
                        //
                        // nzuimm[5] = 1 -> RV32 custom
                        if (ci_instr16_i[12] == 1'b1) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.LWSP / C.FLWSP
                    3'b010, 3'b011 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_load_c;
                        ci_instr32_o[21 : 20]                                 = 2'b00;
                        ci_instr32_o[22]                                      = ci_instr16_i[4];
                        ci_instr32_o[23]                                      = ci_instr16_i[5];
                        ci_instr32_o[24]                                      = ci_instr16_i[6];
                        ci_instr32_o[25]                                      = ci_instr16_i[12];
                        ci_instr32_o[26]                                      = ci_instr16_i[2];
                        ci_instr32_o[27]                                      = ci_instr16_i[3];
                        ci_instr32_o[31 : 28]                                 = '0;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_lw_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = 5'b00010; // stack pointer
                        ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                        //
                        // C.FLWSP
                        if ((ci_instr16_i[ci_funct3_lsb_c] == 1'b1) && (FPU_ENABLE == 0)) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // C.SWSP / C.FSWSP
                    3'b110, 3'b111 : begin
                        ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_store_c;
                        ci_instr32_o[08 : 07]                                 = 2'b00;
                        ci_instr32_o[09]                                      = ci_instr16_i[9];
                        ci_instr32_o[10]                                      = ci_instr16_i[10];
                        ci_instr32_o[11]                                      = ci_instr16_i[11];
                        ci_instr32_o[25]                                      = ci_instr16_i[12];
                        ci_instr32_o[26]                                      = ci_instr16_i[7];
                        ci_instr32_o[27]                                      = ci_instr16_i[8];
                        ci_instr32_o[31 : 28]                                 = '0;
                        ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = funct3_sw_c;
                        ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = 5'b00010; // stack pointer
                        ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c]       = ci_instr16_i[ci_rs2_5_msb_c : ci_rs2_5_lsb_c];
                        //
                        // C.FSWSP
                        if ((ci_instr16_i[ci_funct3_lsb_c] == 1'b1) && (FPU_ENABLE == 0)) begin
                            ci_illegal_o = 1'b1;
                        end
                    end
                    // ------------------------------------------------------------------------------------------------------------
                    // "100": C.JR, C.JALR, C.MV, C.EBREAK, C.ADD; others: undefined
                    default: begin
                        // C.JR, C.MV
                        if (ci_instr16_i[12] == 1'b0) begin
                            if (ci_instr16_i[6:2] == 5'b00000) begin // C.JR
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_jalr_c;
                                ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = ci_instr16_i[ci_rs1_5_msb_c : ci_rs1_5_lsb_c];
                                ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = 5'b00000; // discard return address
                            end else begin // C.MV
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alu_c;
                                ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = 3'b000;
                                ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                                ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = 5'b00000; // x0
                                ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c]       = ci_instr16_i[ci_rs2_5_msb_c : ci_rs2_5_lsb_c];
                            end
                        end else begin // C.EBREAK, C.JALR, C.ADD
                            if (ci_instr16_i[6:2] == 5'b00000) begin // C.EBREAK, C.JALR
                                if (ci_instr16_i[11:7] == 5'b00000) begin // C.EBREAK
                                    ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c]   = opcode_system_c;
                                    ci_instr32_o[instr_funct12_msb_c : instr_funct12_lsb_c] = funct12_ebreak_c;
                                end else begin // C.JALR
                                     ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_jalr_c;
                                     ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = ci_instr16_i[ci_rs1_5_msb_c : ci_rs1_5_lsb_c];
                                     ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = 5'b00001; // save return address to link register
                                end
                            end else begin // C.ADD
                                ci_instr32_o[instr_opcode_msb_c : instr_opcode_lsb_c] = opcode_alu_c;
                                ci_instr32_o[instr_funct3_msb_c : instr_funct3_lsb_c] = 3'b000;
                                ci_instr32_o[instr_rd_msb_c : instr_rd_lsb_c]         = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                                ci_instr32_o[instr_rs1_msb_c : instr_rs1_lsb_c]       = ci_instr16_i[ci_rd_5_msb_c : ci_rd_5_lsb_c];
                                ci_instr32_o[instr_rs2_msb_c : instr_rs2_lsb_c]       = ci_instr16_i[ci_rs2_5_msb_c : ci_rs2_5_lsb_c];
                            end
                            //
                            if ((ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c] == 3'b001) || // C.FLDSP / C.LQSP
                                (ci_instr16_i[ci_funct3_msb_c : ci_funct3_lsb_c] == 3'b101)) begin // C.FSDSP / C.SQSP
                                ci_illegal_o = 1'b1;
                            end
                        end
                    end
                endcase
            end
        endcase
    end
endmodule