package cellrv32_package;
  // ****************************************************************************************************************************

// ****************************************************************************************************************************
// Architecture Configuration and consts
// ****************************************************************************************************************************
  // Boolean Define ----------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam logic true  = 1'b1;
  localparam logic false = 1'b0;

  // Architecture Configuration ----------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // address space --
  localparam logic [31:0] ispace_base_c = 32'h00000000; // default instruction memory address space base address
  localparam logic [31:0] dspace_base_c = 32'h80000000; // default data memory address space base address

  // if register x0 is implemented as a *physical register* it has to be explicitly set to zero by the CPU hardware --
  const logic reset_x0_c = 1'b1; // has to be 'true' for the default register file rtl description (BRAM-based)

  // "response time window" for processor-internal modules --
  // = cycles after which an *unacknowledged* internal bus access will timeout and trigger a bus fault exception
  localparam int max_proc_int_response_time_c = 15; // min 2

  // log2 of co-processor timeout cycles --
  localparam int cp_timeout_c = 7; // default = 7 (= 128 cycles)

  // JTAG tap - identifier --
  localparam logic [03:0] jtag_tap_idcode_version_c = 4'h0; // version
  localparam logic [15:0] jtag_tap_idcode_partid_c  = 16'hcafe; // part number
  localparam logic [10:0] jtag_tap_idcode_manid_c   = 11'b00000000000; // manufacturer id

  // Architecture consts (do not modify!) ------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  const logic [31:0] hw_version_c = 32'h01080202; // CELLRV32 version
  const int archid_c = 19; // official RISC-V architecture ID

  // Check if we're inside the Matrix ----------------------------------------------------------
  // -------------------------------------------------------------------------------------------
`ifndef _QUARTUS_IGNORE_INCLUDES
  localparam logic is_simulation_c = 1'b1; // this MIGHT be a simulation
`else // _QUARTUS_IGNORE_INCLUDES
  localparam logic is_simulation_c = 1'b0; // seems like we're on real hardware
`endif
// pragma translate_off
// synthesis translate_off
// synthesis synthesis_off
// RTL_SYNTHESIS OFF
//  or true // this MIGHT be a simulation
// RTL_SYNTHESIS ON
// synthesis synthesis_on
// synthesis translate_on
// pragma translate_on

// ****************************************************************************************************************************
// Custom Types and Functions
// ****************************************************************************************************************************

  // Internal Interface Types ------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  typedef logic [07:0] pmp_ctrl_if_t [0:15];
  typedef logic [33:0] pmp_addr_if_t [0:15];
  // Internal Memory Types Configuration Types -------------------------------------------------
  // -------------------------------------------------------------------------------------------
  //typedef logic [31:0] mem32_t [0 : 32*1024]; // memory with 32-bit entries, 16kb = 4096 cell, 1 cell = 4(B)
  //typedef logic [7:0]  mem8_t  [0 : 16*1024]; // memory with 8-bit entries
  // Helper Functions --------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------

// ****************************************************************************************************************************
// Processor Address Space Layout
// ****************************************************************************************************************************

  // Internal Instruction Memory (IMEM) and Date Memory (DMEM) --
  localparam logic [31:0] imem_base_c = ispace_base_c; // internal instruction memory base address
  localparam logic [31:0] dmem_base_c = dspace_base_c; // internal data memory base address
  // --> internal data/instruction memory sizes are configured via top's generics

  // !!! IMPORTANT: The base address of each component/module has to be aligned to the !!!
  // !!! total size of the module's occupied address space. The occupied address space !!!
  // !!! has to be a power of two (minimum 4 bytes). Address spaces must not overlap.  !!!

  // Internal Bootloader ROM --
  // Actual bootloader size is determined during runtime via the length of the bootloader initialization image
  parameter logic [31:0] boot_rom_base_c      = 32'hffff0000; // bootloader base address, fixed!
  parameter int          boot_rom_max_size_c  = 16*1024; // max module's address space size in bytes, fixed!

  // On-Chip Debugger: Debug Module --
  localparam logic [31:0] dm_base_c          = 32'hfffff800; // base address, fixed!
  localparam int          dm_size_c          = 4*16*4; // debug ROM address space size in bytes, fixed
  localparam logic [31:0] dm_code_base_c     = 32'hfffff800;
  localparam logic [31:0] dm_pbuf_base_c     = 32'hfffff840;
  localparam logic [31:0] dm_data_base_c     = 32'hfffff880;
  localparam logic [31:0] dm_sreg_base_c     = 32'hfffff8c0;
  // park loop entry points - these need to be sync with the OCD firmware (sw/ocd-firmware/park_loop.S) --
  localparam logic [31:0] dm_exc_entry_c     = dm_code_base_c + 0; // entry point for exceptions
  localparam logic [31:0] dm_park_entry_c    = dm_code_base_c + 8; // normal entry point

  // IO: Peripheral Devices ("IO") Area --
  // Control register(s) (including the device-enable flag) should be located at the base address of each device
  localparam logic [31:0] io_base_c = 32'hfffffe00;
  localparam int          io_size_c = 512; // IO address space size in bytes, fixed!

  // Custom Functions Subsystem (CFS) --
  const logic [31:0] cfs_base_c           = 32'hfffffe00; // base address
  const int          cfs_size_c           = 64*4; // module's address space in bytes
  const logic [31:0] cfs_reg0_addr_c      = 32'hfffffe00;
  const logic [31:0] cfs_reg1_addr_c      = 32'hfffffe04;
  const logic [31:0] cfs_reg2_addr_c      = 32'hfffffe08;
  const logic [31:0] cfs_reg3_addr_c      = 32'hfffffe0c;
  const logic [31:0] cfs_reg4_addr_c      = 32'hfffffe10;
  const logic [31:0] cfs_reg5_addr_c      = 32'hfffffe14;
  const logic [31:0] cfs_reg6_addr_c      = 32'hfffffe18;
  const logic [31:0] cfs_reg7_addr_c      = 32'hfffffe1c;
  const logic [31:0] cfs_reg8_addr_c      = 32'hfffffe20;
  const logic [31:0] cfs_reg9_addr_c      = 32'hfffffe24;
  const logic [31:0] cfs_reg10_addr_c     = 32'hfffffe28;
  const logic [31:0] cfs_reg11_addr_c     = 32'hfffffe2c;
  const logic [31:0] cfs_reg12_addr_c     = 32'hfffffe30;
  const logic [31:0] cfs_reg13_addr_c     = 32'hfffffe34;
  const logic [31:0] cfs_reg14_addr_c     = 32'hfffffe38;
  const logic [31:0] cfs_reg15_addr_c     = 32'hfffffe3c;
  const logic [31:0] cfs_reg16_addr_c     = 32'hfffffe40;
  const logic [31:0] cfs_reg17_addr_c     = 32'hfffffe44;
  const logic [31:0] cfs_reg18_addr_c     = 32'hfffffe48;
  const logic [31:0] cfs_reg19_addr_c     = 32'hfffffe4c;
  const logic [31:0] cfs_reg20_addr_c     = 32'hfffffe50;
  const logic [31:0] cfs_reg21_addr_c     = 32'hfffffe54;
  const logic [31:0] cfs_reg22_addr_c     = 32'hfffffe58;
  const logic [31:0] cfs_reg23_addr_c     = 32'hfffffe5c;
  const logic [31:0] cfs_reg24_addr_c     = 32'hfffffe60;
  const logic [31:0] cfs_reg25_addr_c     = 32'hfffffe64;
  const logic [31:0] cfs_reg26_addr_c     = 32'hfffffe68;
  const logic [31:0] cfs_reg27_addr_c     = 32'hfffffe6c;
  const logic [31:0] cfs_reg28_addr_c     = 32'hfffffe70;
  const logic [31:0] cfs_reg29_addr_c     = 32'hfffffe74;
  const logic [31:0] cfs_reg30_addr_c     = 32'hfffffe78;
  const logic [31:0] cfs_reg31_addr_c     = 32'hfffffe7c;
  const logic [31:0] cfs_reg32_addr_c     = 32'hfffffe80;
  const logic [31:0] cfs_reg33_addr_c     = 32'hfffffe84;
  const logic [31:0] cfs_reg34_addr_c     = 32'hfffffe88;
  const logic [31:0] cfs_reg35_addr_c     = 32'hfffffe8c;
  const logic [31:0] cfs_reg36_addr_c     = 32'hfffffe90;
  const logic [31:0] cfs_reg37_addr_c     = 32'hfffffe94;
  const logic [31:0] cfs_reg38_addr_c     = 32'hfffffe98;
  const logic [31:0] cfs_reg39_addr_c     = 32'hfffffe9c;
  const logic [31:0] cfs_reg40_addr_c     = 32'hfffffea0;
  const logic [31:0] cfs_reg41_addr_c     = 32'hfffffea4;
  const logic [31:0] cfs_reg42_addr_c     = 32'hfffffea8;
  const logic [31:0] cfs_reg43_addr_c     = 32'hfffffeac;
  const logic [31:0] cfs_reg44_addr_c     = 32'hfffffeb0;
  const logic [31:0] cfs_reg45_addr_c     = 32'hfffffeb4;
  const logic [31:0] cfs_reg46_addr_c     = 32'hfffffeb8;
  const logic [31:0] cfs_reg47_addr_c     = 32'hfffffebc;
  const logic [31:0] cfs_reg48_addr_c     = 32'hfffffec0;
  const logic [31:0] cfs_reg49_addr_c     = 32'hfffffec4;
  const logic [31:0] cfs_reg50_addr_c     = 32'hfffffec8;
  const logic [31:0] cfs_reg51_addr_c     = 32'hfffffecc;
  const logic [31:0] cfs_reg52_addr_c     = 32'hfffffed0;
  const logic [31:0] cfs_reg53_addr_c     = 32'hfffffed4;
  const logic [31:0] cfs_reg54_addr_c     = 32'hfffffed8;
  const logic [31:0] cfs_reg55_addr_c     = 32'hfffffedc;
  const logic [31:0] cfs_reg56_addr_c     = 32'hfffffee0;
  const logic [31:0] cfs_reg57_addr_c     = 32'hfffffee4;
  const logic [31:0] cfs_reg58_addr_c     = 32'hfffffee8;
  const logic [31:0] cfs_reg59_addr_c     = 32'hfffffeec;
  const logic [31:0] cfs_reg60_addr_c     = 32'hfffffef0;
  const logic [31:0] cfs_reg61_addr_c     = 32'hfffffef4;
  const logic [31:0] cfs_reg62_addr_c     = 32'hfffffef8;
  const logic [31:0] cfs_reg63_addr_c     = 32'hfffffefc;

  // Serial Data Interface (SDI) --
  localparam logic [31:0] sdi_base_c           = 32'hffffff00; // base address
  localparam int          sdi_size_c           = 2*4; // module's address space size in bytes
  localparam logic [31:0] sdi_ctrl_addr_c      = 32'hffffff00;
  localparam logic [31:0] sdi_rtx_addr_c       = 32'hffffff04;

  // reserved --
//const reserved_base_c      : std_ulogic_vector(31 downto 0) := x"ffffff08"; // base address
//const reserved_size_c      : natural := 2*4; // module's address space size in bytes

  // reserved --
//const reserved_base_c      : std_ulogic_vector(31 downto 0) := x"ffffff10"; // base address
//const reserved_size_c      : natural := 4*4; // module's address space size in bytes

  // reserved --
//const reserved_base_c      : std_ulogic_vector(31 downto 0) := x"ffffff20"; // base address
//const reserved_size_c      : natural := 8*4; // module's address space size in bytes

  // Execute In-Place Module (XIP) --
  localparam logic [31:0] xip_base_c          = 32'hffffff40; // base address
  localparam int          xip_size_c          = 4*4; // module's address space size in bytes
  localparam logic [31:0] xip_ctrl_addr_c     = 32'hffffff40;
//const logic [31:0] xip_reserved_addr_c = 32'hffffff44;
  localparam logic [31:0] xip_data_lo_addr_c  = 32'hffffff48;
  localparam logic [31:0] xip_data_hi_addr_c  = 32'hffffff4C;

  // Pulse-Width Modulation Controller (PWM) --
  localparam logic [31:0] pwm_base_c           = 32'hffffff50; // base address
  localparam int          pwm_size_c           = 4*4; // module's address space size in bytes
  localparam logic [31:0] pwm_ctrl_addr_c      = 32'hffffff50;
  localparam logic [31:0] pwm_dc0_addr_c       = 32'hffffff54;
  localparam logic [31:0] pwm_dc1_addr_c       = 32'hffffff58;
  localparam logic [31:0] pwm_dc2_addr_c       = 32'hffffff5c;

  // General Purpose Timer (GPTMR) --
  localparam logic [31:0] gptmr_base_c         = 32'hffffff60; // base address
  localparam int          gptmr_size_c         = 4*4; // module's address space size in bytes
  localparam logic [31:0] gptmr_ctrl_addr_c    = 32'hffffff60;
  localparam logic [31:0] gptmr_thres_addr_c   = 32'hffffff64;
  localparam logic [31:0] gptmr_count_addr_c   = 32'hffffff68;
//const logic [31:0] gptmr_reserve_addr_c = 32'hffffff6c;

  // 1-Wire Interface Controller (ONEWIRE) --
  const logic [31:0] onewire_base_c       = 32'hffffff70; // base address
  const int          onewire_size_c       = 2*4; // module's address space size in bytes
  const logic [31:0] onewire_ctrl_addr_c  = 32'hffffff70;
  const logic [31:0] onewire_data_addr_c  = 32'hffffff74;

  // Bus Access Monitor (BUSKEEPER) --
  const logic [31:0] buskeeper_base_c  = 32'hffffff78; // base address
  localparam  int    buskeeper_size_c  = 2*4; // module's address space size in bytes

  // External Interrupt Controller (XIRQ) --
  localparam logic [31:0] xirq_base_c          = 32'hffffff80; // base address
  localparam int          xirq_size_c          = 4*4; // module's address space size in bytes
  localparam logic [31:0] xirq_enable_addr_c   = 32'hffffff80;
  localparam logic [31:0] xirq_pending_addr_c  = 32'hffffff84;
  localparam logic [31:0] xirq_source_addr_c   = 32'hffffff88;
//const logic [31:0] xirq_reserved_addr_c = 32'hffffff8c;

  // Machine System Timer (MTIME) --
  localparam logic [31:0] mtime_base_c         = 32'hffffff90; // base address
  localparam int          mtime_size_c         = 4*4; // module's address space size in bytes
  localparam logic [31:0] mtime_time_lo_addr_c = 32'hffffff90;
  localparam logic [31:0] mtime_time_hi_addr_c = 32'hffffff94;
  localparam logic [31:0] mtime_cmp_lo_addr_c  = 32'hffffff98;
  localparam logic [31:0] mtime_cmp_hi_addr_c  = 32'hffffff9c;

  // Primary Universal Asynchronous Receiver/Transmitter (UART0) --
  localparam logic [31:0] uart0_base_c         = 32'hffffffa0; // base address
  localparam int          uart0_size_c         = 2*4; // module's address space size in bytes
  localparam logic [31:0] uart0_ctrl_addr_c    = 32'hffffffa0;
  localparam logic [31:0] uart0_rtx_addr_c     = 32'hffffffa4;

  // Serial Peripheral Interface (SPI) --
  localparam logic [31:0] spi_base_c           = 32'hffffffa8; // base address
  localparam int          spi_size_c           = 2*4; // module's address space size in bytes
  localparam logic [31:0] spi_ctrl_addr_c      = 32'hffffffa8;
  localparam logic [31:0] spi_rtx_addr_c       = 32'hffffffac;

  // Two Wire Interface (TWI) --
  localparam logic [31:0] twi_base_c      = 32'hffffffb0; // base address
  localparam int          twi_size_c      = 2*4; // module's address space size in bytes
  localparam logic [31:0] twi_ctrl_addr_c = 32'hffffffb0;
  localparam logic [31:0] twi_rtx_addr_c  = 32'hffffffb4;

  // True Random Number Generator (TRNG) --
  localparam logic [31:0] trng_base_c          = 32'hffffffb8; // base address
  localparam int          trng_size_c          = 1*4; // module's address space size in bytes
  localparam logic [31:0] trng_ctrl_addr_c     = 32'hffffffb8;

  // Watch Dog Timer (WDT) --
  localparam logic [31:0] wdt_base_c           = 32'hffffffbc; // base address
  localparam int          wdt_size_c           = 1*4; // module's address space size in bytes
  localparam logic [31:0] wdt_ctrl_addr_c      = 32'hffffffbc;

  // General Purpose Input/Output Controller (GPIO) --
  localparam logic [31:0] gpio_base_c          = 32'hffffffc0; // base address
  localparam int          gpio_size_c          = 4*4; // module's address space size in bytes
  localparam logic [31:0] gpio_in_lo_addr_c    = 32'hffffffc0;
  localparam logic [31:0] gpio_in_hi_addr_c    = 32'hffffffc4;
  localparam logic [31:0] gpio_out_lo_addr_c   = 32'hffffffc8;
  localparam logic [31:0] gpio_out_hi_addr_c   = 32'hffffffcc;

  // Secondary Universal Asynchronous Receiver/Transmitter (UART1) --
  localparam logic [31:0] uart1_base_c         = 32'hffffffd0; // base address
  localparam int          uart1_size_c         = 2*4; // module's address space size in bytes
  localparam logic [31:0] uart1_ctrl_addr_c    = 32'hffffffd0;
  localparam logic [31:0] uart1_rtx_addr_c     = 32'hffffffd4;

  // Smart LED (WS2811/WS2812) Interface (NEOLED) --
  localparam logic [31:0] neoled_base_c        = 32'hffffffd8; // base address
  localparam int          neoled_size_c        = 2*4; // module's address space size in bytes
  localparam logic [31:0] neoled_ctrl_addr_c   = 32'hffffffd8;
  localparam logic [31:0] neoled_data_addr_c   = 32'hffffffdc;

  // System Information Memory (SYSINFO) --
  localparam logic [31:0] sysinfo_base_c       = 32'hffffffe0; // base address
  localparam int          sysinfo_size_c       = 8*4; // module's address space size in bytes

// ****************************************************************************************************************************
// SoC Definitions
// ****************************************************************************************************************************

  // SoC Clock Generator --
  localparam int clk_div2_c    = 0;
  localparam int clk_div4_c    = 1;
  localparam int clk_div8_c    = 2;
  localparam int clk_div64_c   = 3;
  localparam int clk_div128_c  = 4;
  localparam int clk_div1024_c = 5;
  localparam int clk_div2048_c = 6;
  localparam int clk_div4096_c = 7;

// ****************************************************************************************************************************
// RISC-V ISA Definitions
// ****************************************************************************************************************************

  // RISC-V 32-Bit Instruction Word Layout --------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam int instr_opcode_lsb_c  =  0; // opcode bit 0
  localparam int instr_opcode_msb_c  =  6; // opcode bit 6
  localparam int instr_rd_lsb_c      =  7; // destination register address bit 0
  localparam int instr_rd_msb_c      = 11; // destination register address bit 4
  localparam int instr_funct3_lsb_c  = 12; // funct3 bit 0
  localparam int instr_funct3_msb_c  = 14; // funct3 bit 2
  localparam int instr_rs1_lsb_c     = 15; // source register 1 address bit 0
  localparam int instr_rs1_msb_c     = 19; // source register 1 address bit 4
  localparam int instr_rs2_lsb_c     = 20; // source register 2 address bit 0
  localparam int instr_rs2_msb_c     = 24; // source register 2 address bit 4
  localparam int instr_rs3_lsb_c     = 27; // source register 3 address bit 0
  localparam int instr_rs3_msb_c     = 31; // source register 3 address bit 4
  localparam int instr_funct7_lsb_c  = 25; // funct7 bit 0
  localparam int instr_funct7_msb_c  = 31; // funct7 bit 6
  localparam int instr_funct12_lsb_c = 20; // funct12 bit 0
  localparam int instr_funct12_msb_c = 31; // funct12 bit 11
  localparam int instr_imm12_lsb_c   = 20; // immediate12 bit 0
  localparam int instr_imm12_msb_c   = 31; // immediate12 bit 11
  localparam int instr_imm20_lsb_c   = 12; // immediate20 bit 0
  localparam int instr_imm20_msb_c   = 31; // immediate20 bit 21
  localparam int instr_funct5_lsb_c  = 27; // funct5 select bit 0
  localparam int instr_funct5_msb_c  = 31; // funct5 select bit 4

  // RISC-V Opcodes -------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // alu --
  const logic [6:0] opcode_alui_c   = 7'b0010011; // ALU operation with immediate (operation via funct3 and funct7)
  const logic [6:0] opcode_alu_c    = 7'b0110011; // ALU operation (operation via funct3 and funct7)
  const logic [6:0] opcode_lui_c    = 7'b0110111; // load upper immediate
  const logic [6:0] opcode_auipc_c  = 7'b0010111; // add upper immediate to PC
  // control flow --
  const logic [6:0] opcode_jal_c    = 7'b1101111; // jump and link
  const logic [6:0] opcode_jalr_c   = 7'b1100111; // jump and link with register
  const logic [6:0] opcode_branch_c = 7'b1100011; // branch (condition set via funct3)
  // memory access --
  const logic [6:0] opcode_load_c   = 7'b0000011; // load (data type via funct3)
  const logic [6:0] opcode_store_c  = 7'b0100011; // store (data type via funct3)
  // sync/system/csr --
  const logic [6:0] opcode_fence_c  = 7'b0001111; // fence / fence.i
  const logic [6:0] opcode_system_c = 7'b1110011; // system/csr access (type via funct3)
  // floating point operations --
  const logic [6:0] opcode_fop_c    = 7'b1010011; // dual/single operand instruction
  // vector operation --
  const logic [6:0] opcode_vector_c = 7'b1010111; // vector instruction 
  // vector memory access --
  const logic [6:0] opcode_vload_c  = 7'b0000111; // vector load instruction
  const logic [6:0] opcode_vstore_c = 7'b0100111; // vector store instruction
  // official *custom* RISC-V opcodes - free for custom instructions --
  const logic [6:0] opcode_cust0_c  = 7'b0001011; // custom-0
  const logic [6:0] opcode_cust1_c  = 7'b0101011; // custom-1
  const logic [6:0] opcode_cust2_c  = 7'b1011011; // custom-2
  const logic [6:0] opcode_cust3_c  = 7'b1111011; // custom-3

  // RISC-V Funct3 --------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // control flow --
  const logic [2:0] funct3_beq_c    = 3'b000; // branch if equal
  const logic [2:0] funct3_bne_c    = 3'b001; // branch if not equal
  const logic [2:0] funct3_blt_c    = 3'b100; // branch if less than
  const logic [2:0] funct3_bge_c    = 3'b101; // branch if greater than or equal
  const logic [2:0] funct3_bltu_c   = 3'b110; // branch if less than (unsigned)
  const logic [2:0] funct3_bgeu_c   = 3'b111; // branch if greater than or equal (unsigned)
  // memory access --
  const logic [2:0] funct3_lb_c     = 3'b000; // load byte
  const logic [2:0] funct3_lh_c     = 3'b001; // load half word
  const logic [2:0] funct3_lw_c     = 3'b010; // load word
  const logic [2:0] funct3_ld_c     = 3'b011; // load half word (unsigned, rv64-only)
  const logic [2:0] funct3_lbu_c    = 3'b100; // load byte (unsigned)
  const logic [2:0] funct3_lhu_c    = 3'b101; // load half word (unsigned)
  const logic [2:0] funct3_lwu_c    = 3'b110; // load word (unsigned, rv64-only)
  const logic [2:0] funct3_sb_c     = 3'b000; // store byte
  const logic [2:0] funct3_sh_c     = 3'b001; // store half word
  const logic [2:0] funct3_sw_c     = 3'b010; // store word
  const logic [2:0] funct3_sd_c     = 3'b011; // store double-word (rv64-only)
  // alu --
  const logic [2:0] funct3_subadd_c = 3'b000; // sub/add via funct7
  const logic [2:0] funct3_sll_c    = 3'b001; // shift logical left
  const logic [2:0] funct3_slt_c    = 3'b010; // set on less
  const logic [2:0] funct3_sltu_c   = 3'b011; // set on less unsigned
  const logic [2:0] funct3_xor_c    = 3'b100; // xor
  const logic [2:0] funct3_sr_c     = 3'b101; // shift right via funct7
  const logic [2:0] funct3_or_c     = 3'b110; // or
  const logic [2:0] funct3_and_c    = 3'b111; // and
  // system/csr --
  const logic [2:0] funct3_env_c    = 3'b000; // ecall, ebreak, mret, wfi, ...
  const logic [2:0] funct3_csrrw_c  = 3'b001; // csr r/w
  const logic [2:0] funct3_csrrs_c  = 3'b010; // csr read & set bit
  const logic [2:0] funct3_csrrc_c  = 3'b011; // csr read & clear bit
  const logic [2:0] funct3_csril_c  = 3'b100; // undefined/illegal
  const logic [2:0] funct3_csrrwi_c = 3'b101; // csr r/w immediate
  const logic [2:0] funct3_csrrsi_c = 3'b110; // csr read & set bit immediate
  const logic [2:0] funct3_csrrci_c = 3'b111; // csr read & clear bit immediate
  // fence --
  const logic [2:0] funct3_fence_c  = 3'b000; // fence - order IO/memory access
  const logic [2:0] funct3_fencei_c = 3'b001; // fence.i - instruction stream sync
  // vector arithmetic
  const logic [2:0] funct3_opivv_c  = 3'b000; // integer vector-vector
  const logic [2:0] funct3_opivi_c  = 3'b011; // integer vector-immediate
  const logic [2:0] funct3_opivx_c  = 3'b100; // integer vector-scalar
  const logic [2:0] funct3_opfvv_c  = 3'b001; // fp32 vector-vector
  const logic [2:0] funct3_opfvx_c  = 3'b101; // fp32 vector-scalar
  const logic [2:0] funct3_opmvv_c  = 3'b010; // integer reduction vector-scalar
  const logic [2:0] funct3_opmvx_c  = 3'b110; // integer reduction vector-scalar
  const logic [2:0] funct3_opcfg_c  = 3'b111; // Conguration-Setting Instructions

  // RISC-V Funct6 --------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // integer alu
  const logic [5:0] funct6_vadd_c  = 6'b000000; // Vector Single-Width Integer Add
  const logic [5:0] funct6_vsub_c  = 6'b000010; // Vector Single-Width Integer Sub
  const logic [5:0] funct6_vrsub_c = 6'b000011; // Vector Single-Width Integer Reverse Sub
  // integer reduction
  const logic [5:0] funct6_vredsum_c = 6'b000000;
  const logic [5:0] funct6_vredand_c = 6'b000001;
  const logic [5:0] funct6_vredor_c  = 6'b000010;
  const logic [5:0] funct6_vredxor_c = 6'b000011;

  // RISC-V Funct12 -------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // system --
  const logic [11:0] funct12_ecall_c  = 12'h000; // ecall
  const logic [11:0] funct12_ebreak_c = 12'h001; // ebreak
  const logic [11:0] funct12_wfi_c    = 12'h105; // wfi
  const logic [11:0] funct12_mret_c   = 12'h302; // mret
  const logic [11:0] funct12_dret_c   = 12'h7b2; // dret

  // RISC-V Floating-Point Stuff ------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // formats --
  const logic [1:0] float_single_c    = 2'b00; // single-precision (32-bit)
  const logic [1:0] float_half_c      = 2'b10; // half-precision (16-bit)
//const float_double_c : std_ulogic_vector(1 downto 0) := "01"; // double-precision (64-bit)
//const float_quad_c   : std_ulogic_vector(1 downto 0) := "11"; // quad-precision (128-bit)

  // number class flags --
  const int fp_class_neg_inf_c    = 0; // negative infinity
  const int fp_class_neg_norm_c   = 1; // negative normal number
  const int fp_class_neg_denorm_c = 2; // negative subnormal number
  const int fp_class_neg_zero_c   = 3; // negative zero
  const int fp_class_pos_zero_c   = 4; // positive zero
  const int fp_class_pos_denorm_c = 5; // positive subnormal number
  const int fp_class_pos_norm_c   = 6; // positive normal number
  const int fp_class_pos_inf_c    = 7; // positive infinity
  const int fp_class_snan_c       = 8; // signaling NaN (sNaN)
  const int fp_class_qnan_c       = 9; // quiet NaN (qNaN)

  // exception flags --
  localparam int fp_exc_nv_c = 0; // invalid operation
  localparam int fp_exc_dz_c = 1; // divide by zero
  localparam int fp_exc_of_c = 2; // overflow
  localparam int fp_exc_uf_c = 3; // underflow
  localparam int fp_exc_nx_c = 4; // inexact

  // special values (single-precision) --
  const logic [31:0] fp32_single_qnan_c     = 32'h7fc00000; // quiet NaN
  const logic [31:0] fp32_single_snan_c     = 32'h7fa00000; // signaling NaN
  const logic [31:0] fp32_single_pos_inf_c  = 32'h7f800000; // positive infinity
  const logic [31:0] fp32_single_neg_inf_c  = 32'hff800000; // negative infinity
  const logic [31:0] fp32_single_pos_zero_c = 32'h00000000; // positive zero
  const logic [31:0] fp32_single_neg_zero_c = 32'h80000000; // negative zero

  // special values (half-precision) --
  const logic [15:0] fp16_half_qnan_c     = 16'h7e00; // quiet NaN
  const logic [15:0] fp16_half_snan_c     = 16'h7d00; // signaling NaN
  const logic [15:0] fp16_half_pos_inf_c  = 16'h7c00; // positive infinity
  const logic [15:0] fp16_half_neg_inf_c  = 16'hfc00; // negative infinity
  const logic [15:0] fp16_half_pos_zero_c = 16'h0000; // positive zero
  const logic [15:0] fp16_half_neg_zero_c = 16'h8000; // negative zero

  // RISC-V CSR Addresses -------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  const logic [11:0] csr_zero_c           = 12'h000; // always returns zero, only relevant for hardware access
  // <<< standard read/write CSRs >>> //
  // user floating-point CSRs //
  const logic [9:0]  csr_class_float_c    = {8'h00, 1'b0}; // floating point
  const logic [11:0] csr_fflags_c         = 12'h001;
  const logic [11:0] csr_frm_c            = 12'h002;
  const logic [11:0] csr_fcsr_c           = 12'h003;
  // vector extension CSRs //
  const logic [8:0]  csr_class_vector_c   = {8'h00, 1'b0}; // vector extension
  const logic [11:0] csr_vstart_c         = 12'h008;
  const logic [11:0] csr_vxsat_c          = 12'h009;
  const logic [11:0] csr_vxrm_c           = 12'h00a;
  const logic [11:0] csr_vcsr_c           = 12'h00f;
  const logic [11:0] csr_vl_c             = 12'hc20;
  const logic [11:0] csr_vtype_c          = 12'hc21;
  const logic [11:0] csr_vlenb_c          = 12'hc22;
  // machine trap setup //
  const logic [8:0]  csr_class_setup_c    = {8'h30, 1'b0}; // trap setup
  const logic [11:0] csr_mstatus_c        = 12'h300;
  const logic [11:0] csr_misa_c           = 12'h301;
  const logic [11:0] csr_mie_c            = 12'h304;
  const logic [11:0] csr_mtvec_c          = 12'h305;
  const logic [11:0] csr_mcounteren_c     = 12'h306;
  //
  const logic [11:0] csr_mstatush_c       = 12'h310;
  // machine configuration //
  const logic [6:0]  csr_class_envcfg_c   = {4'h3, 3'b000}; // environment configuration
  const logic [11:0] csr_menvcfg_c        = 12'h30a;
  const logic [11:0] csr_menvcfgh_c       = 12'h31a;
  // machine counter setup //
  const logic [6:0]  csr_cnt_setup_c      = {4'h3, 3'b001}; // counter setup
  const logic [11:0] csr_mcountinhibit_c  = 12'h320;
  const logic [11:0] csr_mhpmevent3_c     = 12'h323;
  const logic [11:0] csr_mhpmevent4_c     = 12'h324;
  const logic [11:0] csr_mhpmevent5_c     = 12'h325;
  const logic [11:0] csr_mhpmevent6_c     = 12'h326;
  const logic [11:0] csr_mhpmevent7_c     = 12'h327;
  const logic [11:0] csr_mhpmevent8_c     = 12'h328;
  const logic [11:0] csr_mhpmevent9_c     = 12'h329;
  const logic [11:0] csr_mhpmevent10_c    = 12'h32a;
  const logic [11:0] csr_mhpmevent11_c    = 12'h32b;
  const logic [11:0] csr_mhpmevent12_c    = 12'h32c;
  const logic [11:0] csr_mhpmevent13_c    = 12'h32d;
  const logic [11:0] csr_mhpmevent14_c    = 12'h32e;
  const logic [11:0] csr_mhpmevent15_c    = 12'h32f;
  const logic [11:0] csr_mhpmevent16_c    = 12'h330;
  const logic [11:0] csr_mhpmevent17_c    = 12'h331;
  const logic [11:0] csr_mhpmevent18_c    = 12'h332;
  const logic [11:0] csr_mhpmevent19_c    = 12'h333;
  const logic [11:0] csr_mhpmevent20_c    = 12'h334;
  const logic [11:0] csr_mhpmevent21_c    = 12'h335;
  const logic [11:0] csr_mhpmevent22_c    = 12'h336;
  const logic [11:0] csr_mhpmevent23_c    = 12'h337;
  const logic [11:0] csr_mhpmevent24_c    = 12'h338;
  const logic [11:0] csr_mhpmevent25_c    = 12'h339;
  const logic [11:0] csr_mhpmevent26_c    = 12'h33a;
  const logic [11:0] csr_mhpmevent27_c    = 12'h33b;
  const logic [11:0] csr_mhpmevent28_c    = 12'h33c;
  const logic [11:0] csr_mhpmevent29_c    = 12'h33d;
  const logic [11:0] csr_mhpmevent30_c    = 12'h33e;
  const logic [11:0] csr_mhpmevent31_c    = 12'h33f;
  // machine trap handling --
  const logic [7:0]  csr_class_trap_c     = 8'h34; // machine trap handling
  const logic [11:0] csr_mscratch_c       = 12'h340;
  const logic [11:0] csr_mepc_c           = 12'h341;
  const logic [11:0] csr_mcause_c         = 12'h342;
  const logic [11:0] csr_mtval_c          = 12'h343;
  const logic [11:0] csr_mip_c            = 12'h344;
  // physical memory protection - configuration --
  const logic [9:0]  csr_class_pmpcfg_c   = {8'h3a, 2'b00}; // pmp configuration
  const logic [11:0] csr_pmpcfg0_c        = 12'h3a0;
  const logic [11:0] csr_pmpcfg1_c        = 12'h3a1;
  const logic [11:0] csr_pmpcfg2_c        = 12'h3a2;
  const logic [11:0] csr_pmpcfg3_c        = 12'h3a3;
  // physical memory protection - address --
  const logic [7:0]  csr_class_pmpaddr_c  = 8'h3b; // pmp address
  const logic [11:0] csr_pmpaddr0_c       = 12'h3b0;
  const logic [11:0] csr_pmpaddr1_c       = 12'h3b1;
  const logic [11:0] csr_pmpaddr2_c       = 12'h3b2;
  const logic [11:0] csr_pmpaddr3_c       = 12'h3b3;
  const logic [11:0] csr_pmpaddr4_c       = 12'h3b4;
  const logic [11:0] csr_pmpaddr5_c       = 12'h3b5;
  const logic [11:0] csr_pmpaddr6_c       = 12'h3b6;
  const logic [11:0] csr_pmpaddr7_c       = 12'h3b7;
  const logic [11:0] csr_pmpaddr8_c       = 12'h3b8;
  const logic [11:0] csr_pmpaddr9_c       = 12'h3b9;
  const logic [11:0] csr_pmpaddr10_c      = 12'h3ba;
  const logic [11:0] csr_pmpaddr11_c      = 12'h3bb;
  const logic [11:0] csr_pmpaddr12_c      = 12'h3bc;
  const logic [11:0] csr_pmpaddr13_c      = 12'h3bd;
  const logic [11:0] csr_pmpaddr14_c      = 12'h3be;
  const logic [11:0] csr_pmpaddr15_c      = 12'h3bf;
  // trigger module registers --
  const logic [7:0]  csr_class_trigger_c  = 8'h7a; // trigger registers
  const logic [11:0] csr_tselect_c        = 12'h7a0;
  const logic [11:0] csr_tdata1_c         = 12'h7a1;
  const logic [11:0] csr_tdata2_c         = 12'h7a2;
  const logic [11:0] csr_tdata3_c         = 12'h7a3;
  const logic [11:0] csr_tinfo_c          = 12'h7a4;
  const logic [11:0] csr_tcontrol_c       = 12'h7a5;
  const logic [11:0] csr_mcontext_c       = 12'h7a8;
  const logic [11:0] csr_scontext_c       = 12'h7aa;
  // debug mode registers --
  const logic [9:0]  csr_class_debug_c    = {8'h7b, 2'b00}; // debug registers
  const logic [11:0] csr_dcsr_c           = 12'h7b0;
  const logic [11:0] csr_dpc_c            = 12'h7b1;
  const logic [11:0] csr_dscratch0_c      = 12'h7b2;
  // machine counters/timers --
  const logic [3:0]  csr_class_mcnt_c     = 4'hb; // machine-mode counters
  const logic [11:0] csr_mcycle_c         = 12'hb00;
  const logic [11:0] csr_minstret_c       = 12'hb02;
  const logic [11:0] csr_mhpmcounter3_c   = 12'hb03;
  const logic [11:0] csr_mhpmcounter4_c   = 12'hb04;
  const logic [11:0] csr_mhpmcounter5_c   = 12'hb05;
  const logic [11:0] csr_mhpmcounter6_c   = 12'hb06;
  const logic [11:0] csr_mhpmcounter7_c   = 12'hb07;
  const logic [11:0] csr_mhpmcounter8_c   = 12'hb08;
  const logic [11:0] csr_mhpmcounter9_c   = 12'hb09;
  const logic [11:0] csr_mhpmcounter10_c  = 12'hb0a;
  const logic [11:0] csr_mhpmcounter11_c  = 12'hb0b;
  const logic [11:0] csr_mhpmcounter12_c  = 12'hb0c;
  const logic [11:0] csr_mhpmcounter13_c  = 12'hb0d;
  const logic [11:0] csr_mhpmcounter14_c  = 12'hb0e;
  const logic [11:0] csr_mhpmcounter15_c  = 12'hb0f;
  const logic [11:0] csr_mhpmcounter16_c  = 12'hb10;
  const logic [11:0] csr_mhpmcounter17_c  = 12'hb11;
  const logic [11:0] csr_mhpmcounter18_c  = 12'hb12;
  const logic [11:0] csr_mhpmcounter19_c  = 12'hb13;
  const logic [11:0] csr_mhpmcounter20_c  = 12'hb14;
  const logic [11:0] csr_mhpmcounter21_c  = 12'hb15;
  const logic [11:0] csr_mhpmcounter22_c  = 12'hb16;
  const logic [11:0] csr_mhpmcounter23_c  = 12'hb17;
  const logic [11:0] csr_mhpmcounter24_c  = 12'hb18;
  const logic [11:0] csr_mhpmcounter25_c  = 12'hb19;
  const logic [11:0] csr_mhpmcounter26_c  = 12'hb1a;
  const logic [11:0] csr_mhpmcounter27_c  = 12'hb1b;
  const logic [11:0] csr_mhpmcounter28_c  = 12'hb1c;
  const logic [11:0] csr_mhpmcounter29_c  = 12'hb1d;
  const logic [11:0] csr_mhpmcounter30_c  = 12'hb1e;
  const logic [11:0] csr_mhpmcounter31_c  = 12'hb1f;
  //
  const logic [11:0] csr_mcycleh_c        = 12'hb80;
  const logic [11:0] csr_minstreth_c      = 12'hb82;
  const logic [11:0] csr_mhpmcounter3h_c  = 12'hb83;
  const logic [11:0] csr_mhpmcounter4h_c  = 12'hb84;
  const logic [11:0] csr_mhpmcounter5h_c  = 12'hb85;
  const logic [11:0] csr_mhpmcounter6h_c  = 12'hb86;
  const logic [11:0] csr_mhpmcounter7h_c  = 12'hb87;
  const logic [11:0] csr_mhpmcounter8h_c  = 12'hb88;
  const logic [11:0] csr_mhpmcounter9h_c  = 12'hb89;
  const logic [11:0] csr_mhpmcounter10h_c = 12'hb8a;
  const logic [11:0] csr_mhpmcounter11h_c = 12'hb8b;
  const logic [11:0] csr_mhpmcounter12h_c = 12'hb8c;
  const logic [11:0] csr_mhpmcounter13h_c = 12'hb8d;
  const logic [11:0] csr_mhpmcounter14h_c = 12'hb8e;
  const logic [11:0] csr_mhpmcounter15h_c = 12'hb8f;
  const logic [11:0] csr_mhpmcounter16h_c = 12'hb90;
  const logic [11:0] csr_mhpmcounter17h_c = 12'hb91;
  const logic [11:0] csr_mhpmcounter18h_c = 12'hb92;
  const logic [11:0] csr_mhpmcounter19h_c = 12'hb93;
  const logic [11:0] csr_mhpmcounter20h_c = 12'hb94;
  const logic [11:0] csr_mhpmcounter21h_c = 12'hb95;
  const logic [11:0] csr_mhpmcounter22h_c = 12'hb96;
  const logic [11:0] csr_mhpmcounter23h_c = 12'hb97;
  const logic [11:0] csr_mhpmcounter24h_c = 12'hb98;
  const logic [11:0] csr_mhpmcounter25h_c = 12'hb99;
  const logic [11:0] csr_mhpmcounter26h_c = 12'hb9a;
  const logic [11:0] csr_mhpmcounter27h_c = 12'hb9b;
  const logic [11:0] csr_mhpmcounter28h_c = 12'hb9c;
  const logic [11:0] csr_mhpmcounter29h_c = 12'hb9d;
  const logic [11:0] csr_mhpmcounter30h_c = 12'hb9e;
  const logic [11:0] csr_mhpmcounter31h_c = 12'hb9f;
  // <<< standard read-only CSRs >>> --
  // user counters/timers --
  const logic [3:0]  csr_class_ucnt_c     = 4'hc; // user-mode counters
  const logic [11:0] csr_cycle_c          = 12'hc00;
  const logic [11:0] csr_instret_c        = 12'hc02;
  const logic [11:0] csr_hpmcounter3_c    = 12'hc03;
  const logic [11:0] csr_hpmcounter4_c    = 12'hc04;
  const logic [11:0] csr_hpmcounter5_c    = 12'hc05;
  const logic [11:0] csr_hpmcounter6_c    = 12'hc06;
  const logic [11:0] csr_hpmcounter7_c    = 12'hc07;
  const logic [11:0] csr_hpmcounter8_c    = 12'hc08;
  const logic [11:0] csr_hpmcounter9_c    = 12'hc09;
  const logic [11:0] csr_hpmcounter10_c   = 12'hc0a;
  const logic [11:0] csr_hpmcounter11_c   = 12'hc0b;
  const logic [11:0] csr_hpmcounter12_c   = 12'hc0c;
  const logic [11:0] csr_hpmcounter13_c   = 12'hc0d;
  const logic [11:0] csr_hpmcounter14_c   = 12'hc0e;
  const logic [11:0] csr_hpmcounter15_c   = 12'hc0f;
  const logic [11:0] csr_hpmcounter16_c   = 12'hc10;
  const logic [11:0] csr_hpmcounter17_c   = 12'hc11;
  const logic [11:0] csr_hpmcounter18_c   = 12'hc12;
  const logic [11:0] csr_hpmcounter19_c   = 12'hc13;
  const logic [11:0] csr_hpmcounter20_c   = 12'hc14;
  const logic [11:0] csr_hpmcounter21_c   = 12'hc15;
  const logic [11:0] csr_hpmcounter22_c   = 12'hc16;
  const logic [11:0] csr_hpmcounter23_c   = 12'hc17;
  const logic [11:0] csr_hpmcounter24_c   = 12'hc18;
  const logic [11:0] csr_hpmcounter25_c   = 12'hc19;
  const logic [11:0] csr_hpmcounter26_c   = 12'hc1a;
  const logic [11:0] csr_hpmcounter27_c   = 12'hc1b;
  const logic [11:0] csr_hpmcounter28_c   = 12'hc1c;
  const logic [11:0] csr_hpmcounter29_c   = 12'hc1d;
  const logic [11:0] csr_hpmcounter30_c   = 12'hc1e;
  const logic [11:0] csr_hpmcounter31_c   = 12'hc1f;
  //
  const logic [11:0] csr_cycleh_c         = 12'hc80;
  const logic [11:0] csr_instreth_c       = 12'hc82;
  const logic [11:0] csr_hpmcounter3h_c   = 12'hc83;
  const logic [11:0] csr_hpmcounter4h_c   = 12'hc84;
  const logic [11:0] csr_hpmcounter5h_c   = 12'hc85;
  const logic [11:0] csr_hpmcounter6h_c   = 12'hc86;
  const logic [11:0] csr_hpmcounter7h_c   = 12'hc87;
  const logic [11:0] csr_hpmcounter8h_c   = 12'hc88;
  const logic [11:0] csr_hpmcounter9h_c   = 12'hc89;
  const logic [11:0] csr_hpmcounter10h_c  = 12'hc8a;
  const logic [11:0] csr_hpmcounter11h_c  = 12'hc8b;
  const logic [11:0] csr_hpmcounter12h_c  = 12'hc8c;
  const logic [11:0] csr_hpmcounter13h_c  = 12'hc8d;
  const logic [11:0] csr_hpmcounter14h_c  = 12'hc8e;
  const logic [11:0] csr_hpmcounter15h_c  = 12'hc8f;
  const logic [11:0] csr_hpmcounter16h_c  = 12'hc90;
  const logic [11:0] csr_hpmcounter17h_c  = 12'hc91;
  const logic [11:0] csr_hpmcounter18h_c  = 12'hc92;
  const logic [11:0] csr_hpmcounter19h_c  = 12'hc93;
  const logic [11:0] csr_hpmcounter20h_c  = 12'hc94;
  const logic [11:0] csr_hpmcounter21h_c  = 12'hc95;
  const logic [11:0] csr_hpmcounter22h_c  = 12'hc96;
  const logic [11:0] csr_hpmcounter23h_c  = 12'hc97;
  const logic [11:0] csr_hpmcounter24h_c  = 12'hc98;
  const logic [11:0] csr_hpmcounter25h_c  = 12'hc99;
  const logic [11:0] csr_hpmcounter26h_c  = 12'hc9a;
  const logic [11:0] csr_hpmcounter27h_c  = 12'hc9b;
  const logic [11:0] csr_hpmcounter28h_c  = 12'hc9c;
  const logic [11:0] csr_hpmcounter29h_c  = 12'hc9d;
  const logic [11:0] csr_hpmcounter30h_c  = 12'hc9e;
  const logic [11:0] csr_hpmcounter31h_c  = 12'hc9f;
  // machine information registers --
  const logic [11:0] csr_mvendorid_c      = 12'hf11;
  const logic [11:0] csr_marchid_c        = 12'hf12;
  const logic [11:0] csr_mimpid_c         = 12'hf13;
  const logic [11:0] csr_mhartid_c        = 12'hf14;
  const logic [11:0] csr_mconfigptr_c     = 12'hf15;
  // <<< CELLRV32-specific (custom) read-only CSRs >>> ---
  // machine extended ISA extensions information --
  const logic [11:0] csr_mxisa_c          = 12'hfc0;

  // PMP Modes ------------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  const logic [1:0] pmp_mode_off_c   = 2'b00; // null region (disabled)
  const logic [1:0] pmp_mode_tor_c   = 2'b01; // top of range
  const logic [1:0] pmp_mode_na4_c   = 2'b10; // naturally aligned four-byte region
  const logic [1:0] pmp_mode_napot_c = 2'b11; // naturally aligned power-of-two region (>= 8 bytes)

// ****************************************************************************************************************************
// CPU Control
// ****************************************************************************************************************************

  // Main CPU Control Bus ----------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
   typedef struct packed {
     /* register file */
     logic        rf_wb_en;      // write back enable
     logic [4:0]  rf_rs1;        // source register 1 address
     logic [4:0]  rf_rs2;        // source register 2 address
     logic [4:0]  rf_rs3;        // source register 3 address
     logic [4:0]  rf_rd ;        // destination register address
     logic [1:0]  rf_mux;        // input source select
     logic        rf_zero_we;    // allow/force write access to x0
     /* alu */
     logic [2:0]  alu_op;        // ALU operation select
     logic        alu_opa_mux;   // operand A select (0=rs1, 1=PC)
     logic        alu_opb_mux;   // operand B select (0=rs2, 1=IMM)
     logic        alu_unsigned;  // is unsigned ALU operation
     logic [2:0]  alu_frm;       // FPU rounding mode
     logic        alu_reconfig;  // vector reconfiguration request
     logic [31:0] alu_vlmax;     // vector maximum length
     logic [31:0] alu_vl;        // vector length
     logic [7:0]  alu_cp_trig;   // co-processor trigger (one-hot)
     /* bus interface */
     logic        bus_req;       // trigger memory request
     logic        bus_mo_we;     // memory address and data output register write enable
     logic        bus_fence;     // fence operation
     logic        bus_fencei;    // fence.i operation
     logic        bus_priv;      // effective privilege level for load/store
     /* instruction word */
     logic [2:0]  ir_funct3;     // funct3 bit field
     logic [11:0] ir_funct12;    // funct12 bit field
     logic [6:0]  ir_opcode;     // opcode bit field
     /* cpu status */
     logic        cpu_priv;      // effective privilege mode
     logic        cpu_sleep;     // set when CPU is in sleep mode
     logic        cpu_trap;      // set when CPU is entering trap exec
     logic        cpu_debug;     // set when CPU is in debug mode
   } ctrl_bus_t;

  // control bus reset initializer --
   const ctrl_bus_t ctrl_bus_zero_c = '{
     rf_wb_en     : '0,
     rf_rs1       : '0,
     rf_rs2       : '0,
     rf_rs3       : '0,
     rf_rd        : '0,
     rf_mux       : '0,
     rf_zero_we   : '0,
     alu_op       : '0,
     alu_opa_mux  : '0,
     alu_opb_mux  : '0,
     alu_unsigned : '0,
     alu_frm      : '0,
     alu_reconfig : '0,
     alu_vlmax    : '0,
     alu_vl       : '0,
     alu_cp_trig  : '0,
     bus_req      : '0,
     bus_mo_we    : '0,
     bus_fence    : '0,
     bus_fencei   : '0,
     bus_priv     : '0,
     ir_funct3    : '0,
     ir_funct12   : '0,
     ir_opcode    : '0,
     cpu_priv     : '0,
     cpu_sleep    : '0,
     cpu_trap     : '0,
     cpu_debug    : '0
   };
  
  // Main Vector ALU Control Bus ---------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // Memory Unit definitions
  parameter int MEM_OP_RANGE_HI = 7;
  parameter int MEM_OP_RANGE_LO = 6;
  
  const logic[1:0] OP_UNIT_STRIDED = 2'b00;
  const logic[1:0] OP_STRIDED      = 2'b10;
  const logic[1:0] OP_INDEXED      = 2'b11;

  // to Vector Pipeline
  typedef struct packed {
      logic        valid;
  
      logic [04:0] dst;
      logic [04:0] src1;
      logic [04:0] src2;
      logic [04:0] immediate;
  
      logic [31:0] data1;
      logic [31:0] data2;
  
      logic        reconfigure;
      logic [11:0] ir_funct12;
      logic [02:0] ir_funct3;
      logic [06:0] microop;
      logic [01:0] use_mask;
  
      logic [06:0] maxvl;
      logic [06:0] vl;
  } to_vector;

  //--------------------------------------
  //Remapped Vector Instruction
  typedef struct packed {
      logic        valid      ;
  
      logic [04:0] dst        ;
      logic        dst_iszero ;
      logic [04:0] src1       ;
      logic        src1_iszero;
      logic [04:0] src2       ;
      logic        src2_iszero;
      logic [04:0] immediate;
      logic [04:0] mask_src   ;
  
      logic [31:0] data1      ;
      logic [31:0] data2      ;
  
      logic        reconfigure;
      logic [04:0] ticket     ;
      logic [11:0] ir_funct12 ;
      logic [02:0] ir_funct3  ;
      logic [06:0] microop    ;
      logic        use_mask   ;
      logic [01:0] lock       ;
  
      logic [06:0] maxvl;
      logic [06:0] vl;
  } remapped_v_instr;

  //--------------------------------------
  //Remapped Memory Vector Instruction
  typedef struct packed {
      logic valid           ;
  
      logic [04:0] dst             ;
      logic [04:0] src1            ;
      logic [04:0] src2            ;

      logic [31:0] data1           ;
      logic [31:0] data2           ;

      logic [04:0] ticket          ;
      logic [04:0] last_ticket_src1;
      logic [04:0] last_ticket_src2;
      logic [06:0] microop         ;
      logic        reconfigure     ;
      logic [11:0] ir_funct12 ;
  
      logic [06:0] maxvl           ;
      logic [06:0] vl              ;
  } memory_remapped_v_instr;
  
  //--------------------------------------
  //to_Execution Stage
  typedef struct packed {
      logic        valid    ;
      logic        mask     ;
  
      logic [31:0] data1    ;
      logic [31:0] data2    ;
  } to_vector_exec;

  typedef struct packed {
      logic [04:0] dst     ;
      logic [04:0] ticket  ;
      logic [05:0] ir_funct6;
      logic [02:0] ir_funct3;
      logic [06:0] vl      ;
      logic        head_uop;
      logic        end_uop ;
  } to_vector_exec_info;

  //--------------------------------------
  //Vector memory Request
  typedef struct packed {
      logic [31:0]  address;
      logic [06:0]  microop;
      logic [255:0] data;
      logic [03:0]  ticket;
  } vector_mem_req;

  //--------------------------------------
  //Vector memory response
  typedef struct packed {
      logic [03:0]  ticket;
      logic [255:0] data;
  } vector_mem_resp;

  // Comparator Bus ----------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam int cmp_equal_c = 0;
  localparam int cmp_less_c  = 1; // for signed and unsigned comparisons

  // CPU Co-Processor IDs ----------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam int cp_sel_shifter_c  = 0; // CP0: shift operations (base ISA)
  localparam int cp_sel_muldiv_c   = 1; // CP1: multiplication/division operations ('M' extensions)
  localparam int cp_sel_bitmanip_c = 2; // CP2: bit manipulation ('B' extensions)
  localparam int cp_sel_fpu32_c    = 3; // CP3: floating-point unit ('Zfinx' extension)
  localparam int cp_sel_fpu16_c    = 4; // CP4: floating-point unit ('Zhinx' extension)
  localparam int cp_sel_cfu_c      = 5; // CP5: custom instructions CFU ('Zxcfu' extension)
  localparam int cp_sel_cond_c     = 6; // CP6: conditional operations ('Zicond' extension)
  localparam int cp_sel_vector_c   = 7; // CP7: vector operations ('Vector' extension)

  // ALU Function Codes [DO NOT CHANGE ENCODING!] -------------------------------------------
  // -------------------------------------------------------------------------------------------
  const logic [2:0] alu_op_add_c  = 3'b000; // result <= A + B
  const logic [2:0] alu_op_sub_c  = 3'b001; // result <= A - B
  const logic [2:0] alu_op_cp_c   = 3'b010; // result <= co-processor
  const logic [2:0] alu_op_slt_c  = 3'b011; // result <= A < B
  const logic [2:0] alu_op_movb_c = 3'b100; // result <= B
  const logic [2:0] alu_op_xor_c  = 3'b101; // result <= A xor B
  const logic [2:0] alu_op_or_c   = 3'b110; // result <= A or B
  const logic [2:0] alu_op_and_c  = 3'b111; // result <= A and B

  // Register File Input Select -------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  const logic [1:0] rf_mux_alu_c = 2'b00; // register file <= alu result
  const logic [1:0] rf_mux_mem_c = 2'b01; // register file <= memory read data
  const logic [1:0] rf_mux_csr_c = 2'b10; // register file <= CSR read data
  const logic [1:0] rf_mux_npc_c = 2'b11; // register file <= next-PC (for branch-and-link)

  // Trap ID Codes --------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // MSB:   1 = async exception (IRQ), 0 = sync exception (e.g. ebreak)
  // MSB-1: 1 = entry to debug mode, 0 = normal trapping
  // RISC-V compliant synchronous exceptions --
  const logic [6:0] trap_ima_c      = {1'b0, 1'b0, 5'b00000}; // 0:  instruction misaligned
  const logic [6:0] trap_iba_c      = {1'b0, 1'b0, 5'b00001}; // 1:  instruction access fault
  const logic [6:0] trap_iil_c      = {1'b0, 1'b0, 5'b00010}; // 2:  illegal instruction
  const logic [6:0] trap_brk_c      = {1'b0, 1'b0, 5'b00011}; // 3:  breakpoint
  const logic [6:0] trap_lma_c      = {1'b0, 1'b0, 5'b00100}; // 4:  load address misaligned
  const logic [6:0] trap_lbe_c      = {1'b0, 1'b0, 5'b00101}; // 5:  load access fault
  const logic [6:0] trap_sma_c      = {1'b0, 1'b0, 5'b00110}; // 6:  store address misaligned
  const logic [6:0] trap_sbe_c      = {1'b0, 1'b0, 5'b00111}; // 7:  store access fault
  const logic [6:0] trap_env_c      = {1'b0, 1'b0, 5'b010??}; // 8..11:  environment call from u/s/h/m
//const trap_ipf_c      : std_ulogic_vector(6 downto 0) := "0" & "0" & "01100"; // 12: instruction page fault
//const trap_lpf_c      : std_ulogic_vector(6 downto 0) := "0" & "0" & "01101"; // 13: load page fault
//const trap_???_c      : std_ulogic_vector(6 downto 0) := "0" & "0" & "01110"; // 14: reserved
//const trap_spf_c      : std_ulogic_vector(6 downto 0) := "0" & "0" & "01111"; // 15: store page fault
  // RISC-V compliant asynchronous exceptions (interrupts) --
  const logic [6:0] trap_msi_c      = {1'b1, 1'b0, 5'b00011}; // 3:  machine software interrupt
  const logic [6:0] trap_mti_c      = {1'b1, 1'b0, 5'b00111}; // 7:  machine timer interrupt
  const logic [6:0] trap_mei_c      = {1'b1, 1'b0, 5'b01011}; // 11: machine external interrupt
  // CELLRV32-specific (RISC-V custom) asynchronous exceptions (interrupts) --
  const logic [6:0] trap_firq0_c    = {1'b1, 1'b0, 5'b10000}; // 16: fast interrupt 0
  const logic [6:0] trap_firq1_c    = {1'b1, 1'b0, 5'b10001}; // 17: fast interrupt 1
  const logic [6:0] trap_firq2_c    = {1'b1, 1'b0, 5'b10010}; // 18: fast interrupt 2
  const logic [6:0] trap_firq3_c    = {1'b1, 1'b0, 5'b10011}; // 19: fast interrupt 3
  const logic [6:0] trap_firq4_c    = {1'b1, 1'b0, 5'b10100}; // 20: fast interrupt 4
  const logic [6:0] trap_firq5_c    = {1'b1, 1'b0, 5'b10101}; // 21: fast interrupt 5
  const logic [6:0] trap_firq6_c    = {1'b1, 1'b0, 5'b10110}; // 22: fast interrupt 6
  const logic [6:0] trap_firq7_c    = {1'b1, 1'b0, 5'b10111}; // 23: fast interrupt 7
  const logic [6:0] trap_firq8_c    = {1'b1, 1'b0, 5'b11000}; // 24: fast interrupt 8
  const logic [6:0] trap_firq9_c    = {1'b1, 1'b0, 5'b11001}; // 25: fast interrupt 9
  const logic [6:0] trap_firq10_c   = {1'b1, 1'b0, 5'b11010}; // 26: fast interrupt 10
  const logic [6:0] trap_firq11_c   = {1'b1, 1'b0, 5'b11011}; // 27: fast interrupt 11
  const logic [6:0] trap_firq12_c   = {1'b1, 1'b0, 5'b11100}; // 28: fast interrupt 12
  const logic [6:0] trap_firq13_c   = {1'b1, 1'b0, 5'b11101}; // 29: fast interrupt 13
  const logic [6:0] trap_firq14_c   = {1'b1, 1'b0, 5'b11110}; // 30: fast interrupt 14
  const logic [6:0] trap_firq15_c   = {1'b1, 1'b0, 5'b11111}; // 31: fast interrupt 15
  // entering debug mode (sync./async. exceptions) --
  const logic [6:0] trap_db_break_c = {1'b0, 1'b1, 5'b00001}; // 1: break instruction (sync)
  const logic [6:0] trap_db_trig_c  = {1'b0, 1'b1, 5'b00010}; // 2: hardware trigger (sync)
  const logic [6:0] trap_db_halt_c  = {1'b1, 1'b1, 5'b00011}; // 3: external halt request (async)
  const logic [6:0] trap_db_step_c  = {1'b1, 1'b1, 5'b00100}; // 4: single-stepping (async)

  // CPU Trap System ------------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  // exception source bits --
  localparam int exc_iaccess_c  =  0; // instruction access fault
  localparam int exc_iillegal_c =  1; // illegal instruction
  localparam int exc_ialign_c   =  2; // instruction address misaligned
  localparam int exc_envcall_c  =  3; // environment call
  localparam int exc_break_c    =  4; // breakpoint
  localparam int exc_salign_c   =  5; // store address misaligned
  localparam int exc_lalign_c   =  6; // load address misaligned
  localparam int exc_saccess_c  =  7; // store access fault
  localparam int exc_laccess_c  =  8; // load access fault
  // for debug mode only --
  localparam int exc_db_break_c =  9; // enter debug mode via ebreak instruction ("sync EXCEPTION")
  localparam int exc_db_hw_c    = 10; // enter debug mode via hw trigger ("sync EXCEPTION")
  //
  localparam int exc_width_c    = 11; // length of this list in bits
  // interrupt source bits --
  localparam int irq_msi_irq_c  =  0; // machine software interrupt
  localparam int irq_mti_irq_c  =  1; // machine timer interrupt
  localparam int irq_mei_irq_c  =  2; // machine external interrupt
  localparam int irq_firq_0_c   =  3; // fast interrupt channel 0
  localparam int irq_firq_1_c   =  4; // fast interrupt channel 1
  localparam int irq_firq_2_c   =  5; // fast interrupt channel 2
  localparam int irq_firq_3_c   =  6; // fast interrupt channel 3
  localparam int irq_firq_4_c   =  7; // fast interrupt channel 4
  localparam int irq_firq_5_c   =  8; // fast interrupt channel 5
  localparam int irq_firq_6_c   =  9; // fast interrupt channel 6
  localparam int irq_firq_7_c   = 10; // fast interrupt channel 7
  localparam int irq_firq_8_c   = 11; // fast interrupt channel 8
  localparam int irq_firq_9_c   = 12; // fast interrupt channel 9
  localparam int irq_firq_10_c  = 13; // fast interrupt channel 10
  localparam int irq_firq_11_c  = 14; // fast interrupt channel 11
  localparam int irq_firq_12_c  = 15; // fast interrupt channel 12
  localparam int irq_firq_13_c  = 16; // fast interrupt channel 13
  localparam int irq_firq_14_c  = 17; // fast interrupt channel 14
  localparam int irq_firq_15_c  = 18; // fast interrupt channel 15
  // for debug mode only --
  localparam int irq_db_halt_c  = 19; // enter debug mode via external halt request ("async IRQ")
  localparam int irq_db_step_c  = 20; // enter debug mode via single-stepping ("async IRQ")
  //
  localparam int irq_width_c    = 21; // length of this list in bits

  // CPU Privilege Modes --------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam logic priv_mode_m_c = 1'b1; // machine mode
  localparam logic priv_mode_u_c = 1'b0; // user mode

  // HPM Event System -----------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  localparam int hpmcnt_event_cy_c      = 0;  // Active cycle
  localparam int hpmcnt_event_never_c   = 1;  // Unused / never (actually, this would be used for TIME)
  localparam int hpmcnt_event_ir_c      = 2;  // Retired instruction
  localparam int hpmcnt_event_cir_c     = 3;  // Retired compressed instruction
  localparam int hpmcnt_event_wait_if_c = 4;  // Instruction fetch memory wait cycle
  localparam int hpmcnt_event_wait_ii_c = 5;  // Instruction issue wait cycle
  localparam int hpmcnt_event_wait_mc_c = 6;  // Multi-cycle ALU-operation wait cycle
  localparam int hpmcnt_event_load_c    = 7;  // Load operation
  localparam int hpmcnt_event_store_c   = 8;  // Store operation
  localparam int hpmcnt_event_wait_ls_c = 9;  // Load/store memory wait cycle
  localparam int hpmcnt_event_jump_c    = 10; // Unconditional jump
  localparam int hpmcnt_event_branch_c  = 11; // Conditional branch (taken or not taken)
  localparam int hpmcnt_event_tbranch_c = 12; // Conditional taken branch
  localparam int hpmcnt_event_trap_c    = 13; // Entered trap
  localparam int hpmcnt_event_illegal_c = 14; // Illegal instruction exception
  //
  localparam int hpmcnt_event_size_c    = 15; // length of this list

  // ****************************************************************************************************************************
  // Functions
  // ****************************************************************************************************************************

  // Function: select lmul ---------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function logic [3:0] vlmul2lmul (input logic [2:0] vlmul);
     case (vlmul)
       3'b001: return 4'd2;  // LMUL= 2
       3'b010: return 4'd4;  // LMUL= 4
       3'b011: return 4'd8;  // LMUL= 8
       default: return 4'd1; // LMUL= 1 : 1/2 : 1/4 : 1/8
     endcase
  endfunction
  
  // Function: compute propagate and generate signals for prefix adder tree --------------------
  // -------------------------------------------------------------------------------------------
  function logic [31:0] pro_and_gen_f (input logic [15:0] pleft,
                                       input logic [15:0] pright,
                                       input logic [15:0] gleft,
                                       input logic [15:0] gright);
    logic [15:0] pnext;
    logic [15:0] gnext;
    // generate
    pnext = pleft & pright;
    gnext = (pleft & gright) | gleft;
    //
    return {pnext, gnext};
  endfunction

  // Function: Convert binary to gray ----------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function logic [31:0] bin_to_gray_f (input logic [31:0] bin_num);
    logic [$bits(bin_num)-1:0] tmp_v;
    // keep MSB
    tmp_v[$bits(bin_num)-1] = bin_num[$bits(bin_num)-1];
    for (int i = $bits(bin_num)-2; i >= 0; --i) begin
      tmp_v[i] = tmp_v[i+1] ^ bin_num[i];
    end
    return tmp_v;
  endfunction : bin_to_gray_f

  // Function: Convert gray to binary ----------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function logic [31:0] gray_to_bin_f (input logic [31:0] gray_num);
    logic [$bits(gray_num)-1:0] tmp_v;
    // keep MSB
    tmp_v[$bits(gray_num)-1] = gray_num[$bits(gray_num)-1];
    for (int i = $bits(gray_num)-2; i >= 0; --i) begin
      tmp_v[i] = tmp_v[i+1] ^ gray_num[i];
    end
    return tmp_v;
  endfunction : gray_to_bin_f

  // Function: Bit reversal --------------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function logic [31:0] bit_rev_f (input logic [31:0] bin_num);
    logic [31:0] r_num;
    // i loop
    for ( int i = 0; i < $bits(bin_num); ++i) begin
      r_num[$bits(bin_num)-i-1] = bin_num[i];
    end
    return r_num;
  endfunction : bit_rev_f

  // Function: Swap all bytes of a 32-bit word (endianness conversion) ----------------------
  // -------------------------------------------------------------------------------------------
  function logic [31:0] bswap32_f (input logic [31:0] word_i);
    logic [31:0] swap_word;
    // swap
    swap_word[7:0]   = word_i[31:24];
    swap_word[15:8]  = word_i[23:16];
    swap_word[23:16] = word_i[15:8];
    swap_word[31:24] = word_i[7:0];
    //
    return swap_word;
  endfunction : bswap32_f

  // Function: Conditional select string -------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function string cond_sel_string_f(input logic cond,
                                    input string val_t,
                                    input string val_f);
    // select value
    if (cond == 1'b1) return val_t;
    else              return val_f;
  endfunction : cond_sel_string_f

  // Function: Population count (number of set bits) -------------------------------------------
  // -------------------------------------------------------------------------------------------
  function int popcount_f(input logic[31:0] bin_num);
    int cnt;
    cnt = 0;
    // count high bit
    for (int i = 0; i < $bits(bin_num); ++i) begin
      if (bin_num[i] == 1'b1) begin
        cnt = cnt + 1;
      end
    end
    return cnt;
  endfunction : popcount_f

  // Function: Count leading zeros -------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function int leading_zeros_f(input logic[31:0] bin_num);
    int cnt;
    cnt = 0;
    // count low bit
    for (int i = 0; i < $bits(bin_num); ++i) begin
      if (bin_num[i] == 1'b0) begin
        cnt  = cnt  + 1;
      end else begin
        return cnt;
      end
    end
    return cnt;
  endfunction : leading_zeros_f

  // Function: Conditional select int ------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function int cond_sel_int_f(input logic cond,
                                  input int val_t,
                                  input int val_f);
    // select value
    if (cond == 1'b1) return val_t;
    else              return val_f;
  endfunction : cond_sel_int_f

  // Function: Test if input number is a power of two ------------------------------------------
  // -------------------------------------------------------------------------------------------
  function logic is_power_of_two_f(input int num);
     logic [31:0] tmp;
     //
     tmp = 'b0;
     if (num == 0) begin
      return 1'b0;
     end else if (num == 1) begin
      return 1'b1;
     end else begin
       tmp = num;
       if ((tmp & (tmp-1)) == 0) begin
         return 1'b1;
       end else begin
         return 1'b0;
       end
     end
  endfunction : is_power_of_two_f

  // Function: Conditional select natural ------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function int cond_sel_natural_f(input logic   cond,
                                      input int val_t,
                                      input int val_f);
      // select value
      if (cond == 1'b1) begin
        return val_t;
      end else begin
        return val_f;
      end
  endfunction : cond_sel_natural_f

  // Function: priority Encoder-----------------------------------------------------------------
  // -------------------------------------------------------------------------------------------
  function int prior_encoder(input int LEN,
                             input logic[31:0] en);
    for (int i = 0; i < LEN; ++i) begin
      if (en[i] == 1'b1) begin
        return i;
      end
    end
    return 0;
  endfunction : prior_encoder

endpackage : cellrv32_package

