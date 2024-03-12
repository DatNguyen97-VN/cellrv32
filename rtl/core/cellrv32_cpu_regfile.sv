// ##################################################################################################
// # << CELLRV32 - CPU General Purpose Data Register File >>                                        #
// # ********************************************************************************************** #
// # Data register file. 32 entries (= 1024 bit) for RV32I ISA (default), 16 entries (= 512 bit)    #
// # for RV32E ISA (when RISC-V "E" extension is enabled).                                          #
// #                                                                                                #
// # Register zero (x0) is a "normal" physical register that is set to zero by the CPU control      #
// # hardware. This is not required for non-BRAM-based register files where x0 is hardwired to      #
// # zero. Set <reset_x0_c> to 'false' in this case.                                                #
// #                                                                                                #
// # The register file uses synchronous read accesses and a *single* (multiplexed) address port     #
// # for writing and reading rd/rs1 and a single read-only port for rs2. Therefore, the whole       #
// # register file can be mapped to a single true-dual-port block RAM. A third and a fourth read    #
// # port can be optionally enabled.                                                                #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_regfile #(
    parameter XLEN                  = 32, // data path width
    parameter CPU_EXTENSION_RISCV_E = 1,  // implement embedded RF extension?
    parameter RS3_EN                = 1,  // enable 3rd read port
    parameter RS4_EN                = 1   // enable 4th read port
) (
    /* global control */
    input logic      clk_i,  // global clock, rising edge
    input ctrl_bus_t ctrl_i, // main control bus
    /* data input */
    input logic [XLEN-1:0] alu_i, // ALU result
    input logic [XLEN-1:0] mem_i, // memory read data
    input logic [XLEN-1:0] csr_i, // CSR read data
    input logic [XLEN-1:0] pc2_i, // next PC
    /* data output */
    output logic [XLEN-1:0] rs1_o, // operand 1
    output logic [XLEN-1:0] rs2_o, // operand 2
    output logic [XLEN-1:0] rs3_o, // operand 4
    output logic [XLEN-1:0] rs4_o  // operand 3
);
    /* register file */
    typedef logic[XLEN-1:0] reg_file_t [31:0];
    typedef logic[XLEN-1:0] reg_file_emb_t [15:0];
    reg_file_t reg_file;
    reg_file_emb_t reg_file_emb;

    /* access */
    logic [XLEN-1:0] rf_wdata; // actual write-back data
    logic  rf_we;   // write enable
    logic  rd_zero; // writing to x0?
    logic  [4:0] opa_addr; // rs1/dst address
    logic  [4:0] opb_addr; // rs2 address
    logic  [4:0] opc_addr; // rs3 address
    logic  [4:0] opd_addr; // rs4 address
    
    // Data Write-Back Select --------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : wb_select
        unique case (ctrl_i.rf_mux)
            rf_mux_alu_c : rf_wdata = alu_i; // ALU result
            rf_mux_mem_c : rf_wdata = mem_i; // memory read data
            rf_mux_csr_c : rf_wdata = csr_i; // CSR read data
            rf_mux_npc_c : rf_wdata = pc2_i; // next PC (branch return/link address)
            default: begin
                           rf_wdata = alu_i; // don't care 
            end
        endcase
    end : wb_select
    
    // Register File Access ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    /* access addresses */
    assign opa_addr = (ctrl_i.rf_zero_we == 1'b1) ? 5'b00000 :   // force rd = zero
                      (ctrl_i.rf_wb_en == 1'b1) ? ctrl_i.rf_rd : // rd
                       ctrl_i.rf_rs1; // rs1
    assign opb_addr = ctrl_i.rf_rs2;  // rs2
    assign opc_addr = ctrl_i.rf_rs3;  // rs3
    assign opd_addr = {ctrl_i.ir_funct12[6:5], ctrl_i.ir_funct3}; // rs4: [26:25] & [14:12]; not RISC-V-standard!

    /* write enable */
    assign rd_zero = (ctrl_i.rf_rd == 5'b00000) ? 1'b1 : 1'b0;
    assign rf_we   = (ctrl_i.rf_wb_en & (~rd_zero)) | ctrl_i.rf_zero_we; // do not write to x0 unless explicitly forced
    
    // RV32I Register File with 32 Entries -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (CPU_EXTENSION_RISCV_E == 0) begin : reg_file_rv32i
            // sync read and write
            always_ff @( posedge clk_i ) begin : rf_access
                if (rf_we == 1'b1) begin
                    reg_file[opa_addr[4:0]] <= rf_wdata;
                end
                //
                rs1_o <= reg_file[opa_addr[4:0]];
                rs2_o <= reg_file[opb_addr[4:0]];
                //
                /* optional 3rd read port */
                if (RS3_EN == 1) begin
                    rs3_o <= reg_file[opc_addr[4:0]];
                end else begin
                    rs3_o <= '0;
                end
                //
                /* optional 4th read port */
                if (RS4_EN == 1) begin
                    rs4_o <= reg_file[opd_addr[4:0]];
                end else begin
                    rs4_o <= '0;
                end
            end : rf_access
        end : reg_file_rv32i
    endgenerate

    // RV32E Register File with 16 Entries -------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    generate
        if (CPU_EXTENSION_RISCV_E == 1) begin : reg_file_rv32e
            // sync read and write
            always_ff @( posedge clk_i ) begin : rf_access
                if (rf_we == 1'b1) begin
                    reg_file_emb[opa_addr[3:0]] <= rf_wdata;
                end
                //
                rs1_o <= reg_file_emb[opa_addr[3:0]];
                rs2_o <= reg_file_emb[opb_addr[3:0]];
                //
                /* optional 3rd read port */
                if (RS3_EN == 1) begin
                    rs3_o <= reg_file_emb[opc_addr[3:0]];
                end else begin
                    rs3_o <= '0;
                end
                //
                /* optional 4th read port */
                if (RS4_EN == 1) begin // implement fourth read port?
                    rs4_o <= reg_file_emb[opd_addr[3:0]];
                end else begin
                    rs4_o <= '0;
                end
            end : rf_access
        end : reg_file_rv32e
    endgenerate
endmodule