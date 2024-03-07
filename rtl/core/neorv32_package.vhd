-- #################################################################################################
-- # << NEORV32 - Main VHDL package file >>                                                        #
-- # ********************************************************************************************* #
-- # BSD 3-Clause License                                                                          #
-- #                                                                                               #
-- # Copyright (c) 2023, Stephan Nolting. All rights reserved.                                     #
-- #                                                                                               #
-- # Redistribution and use in source and binary forms, with or without modification, are          #
-- # permitted provided that the following conditions are met:                                     #
-- #                                                                                               #
-- # 1. Redistributions of source code must retain the above copyright notice, this list of        #
-- #    conditions and the following disclaimer.                                                   #
-- #                                                                                               #
-- # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     #
-- #    conditions and the following disclaimer in the documentation and/or other materials        #
-- #    provided with the distribution.                                                            #
-- #                                                                                               #
-- # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  #
-- #    endorse or promote products derived from this software without specific prior written      #
-- #    permission.                                                                                #
-- #                                                                                               #
-- # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   #
-- # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               #
-- # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    #
-- # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     #
-- # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE #
-- # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    #
-- # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     #
-- # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  #
-- # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            #
-- # ********************************************************************************************* #
-- # The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32       (c) Stephan Nolting #
-- #################################################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package neorv32_package is

-- ****************************************************************************************************************************
-- Custom Types and Functions
-- ****************************************************************************************************************************

  -- Internal Memory Types Configuration Types ----------------------------------------------
  -- -------------------------------------------------------------------------------------------
  type mem32_t is array (natural range <>) of std_ulogic_vector(31 downto 0); -- memory with 32-bit entries
  type mem8_t  is array (natural range <>) of std_ulogic_vector(07 downto 0); -- memory with 8-bit entries

  -- Helper Functions -----------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  
  function index_size_f(input : natural) return natural;
  function and_reduce_f(a : std_ulogic_vector) return std_ulogic;
  impure function mem32_init_f(init : mem32_t; depth : natural) return mem32_t;
  
  -- Internal Bootloader ROM --
  -- Actual bootloader size is determined during runtime via the length of the bootloader initialization image
  constant boot_rom_max_size_c  : natural := 32*1024; -- max module's address space size in bytes, fixed!


-- ****************************************************************************************************************************
-- Entity Definitions
-- ****************************************************************************************************************************

  -- Component: NEORV32 Processor Top Entity ------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  component neorv32_top
    generic (
      -- General --
      CLOCK_FREQUENCY              : natural;           -- clock frequency of clk_i in Hz
      HW_THREAD_ID                 : natural := 0;      -- hardware thread id (32-bit)
      CUSTOM_ID                    : std_ulogic_vector(31 downto 0) := x"00000000"; -- custom user-defined ID
      INT_BOOTLOADER_EN            : boolean := false;  -- boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM
      -- On-Chip Debugger (OCD) --
      ON_CHIP_DEBUGGER_EN          : boolean := false;  -- implement on-chip debugger
      -- RISC-V CPU Extensions --
      CPU_EXTENSION_RISCV_B        : boolean := false;  -- implement bit-manipulation extension?
      CPU_EXTENSION_RISCV_C        : boolean := false;  -- implement compressed extension?
      CPU_EXTENSION_RISCV_E        : boolean := false;  -- implement embedded RF extension?
      CPU_EXTENSION_RISCV_M        : boolean := false;  -- implement mul/div extension?
      CPU_EXTENSION_RISCV_U        : boolean := false;  -- implement user mode extension?
      CPU_EXTENSION_RISCV_Zfinx    : boolean := false;  -- implement 32-bit floating-point extension (using INT regs!)
      CPU_EXTENSION_RISCV_Zicsr    : boolean := true;   -- implement CSR system?
      CPU_EXTENSION_RISCV_Zicntr   : boolean := true;   -- implement base counters?
      CPU_EXTENSION_RISCV_Zicond   : boolean := false;  -- implement conditional operations extension?
      CPU_EXTENSION_RISCV_Zihpm    : boolean := false;  -- implement hardware performance monitors?
      CPU_EXTENSION_RISCV_Zifencei : boolean := false;  -- implement instruction stream sync.?
      CPU_EXTENSION_RISCV_Zmmul    : boolean := false;  -- implement multiply-only M sub-extension?
      CPU_EXTENSION_RISCV_Zxcfu    : boolean := false;  -- implement custom (instr.) functions unit?
      -- Tuning Options --
      FAST_MUL_EN                  : boolean := false;  -- use DSPs for M extension's multiplier
      FAST_SHIFT_EN                : boolean := false;  -- use barrel shifter for shift operations
      CPU_IPB_ENTRIES              : natural := 1;      -- entries in instruction prefetch buffer, has to be a power of 2, min 1
      -- Physical Memory Protection (PMP) --
      PMP_NUM_REGIONS              : natural := 0;      -- number of regions (0..16)
      PMP_MIN_GRANULARITY          : natural := 4;      -- minimal region granularity in bytes, has to be a power of 2, min 4 bytes
      -- Hardware Performance Monitors (HPM) --
      HPM_NUM_CNTS                 : natural := 0;      -- number of implemented HPM counters (0..29)
      HPM_CNT_WIDTH                : natural := 40;     -- total size of HPM counters (0..64)
      -- Internal Instruction memory (IMEM) --
      MEM_INT_IMEM_EN              : boolean := false;  -- implement processor-internal instruction memory
      MEM_INT_IMEM_SIZE            : natural := 16*1024; -- size of processor-internal instruction memory in bytes
      -- Internal Data memory (DMEM) --
      MEM_INT_DMEM_EN              : boolean := false;  -- implement processor-internal data memory
      MEM_INT_DMEM_SIZE            : natural := 8*1024; -- size of processor-internal data memory in bytes
      -- Internal Instruction Cache (iCACHE) --
      ICACHE_EN                    : boolean := false;  -- implement instruction cache
      ICACHE_NUM_BLOCKS            : natural := 4;      -- i-cache: number of blocks (min 1), has to be a power of 2
      ICACHE_BLOCK_SIZE            : natural := 64;     -- i-cache: block size in bytes (min 4), has to be a power of 2
      ICACHE_ASSOCIATIVITY         : natural := 1;      -- i-cache: associativity / number of sets (1=direct_mapped), has to be a power of 2
      -- External memory interface (WISHBONE) --
      MEM_EXT_EN                   : boolean := false;  -- implement external memory bus interface?
      MEM_EXT_TIMEOUT              : natural := 255;    -- cycles after a pending bus access auto-terminates (0 = disabled)
      MEM_EXT_PIPE_MODE            : boolean := false;  -- protocol: false=classic/standard wishbone mode, true=pipelined wishbone mode
      MEM_EXT_BIG_ENDIAN           : boolean := false;  -- byte order: true=big-endian, false=little-endian
      MEM_EXT_ASYNC_RX             : boolean := false;  -- use register buffer for RX data when false
      MEM_EXT_ASYNC_TX             : boolean := false;  -- use register buffer for TX data when false
      -- External Interrupts Controller (XIRQ) --
      XIRQ_NUM_CH                  : natural := 0;      -- number of external IRQ channels (0..32)
      XIRQ_TRIGGER_TYPE            : std_ulogic_vector(31 downto 0) := x"FFFFFFFF"; -- trigger type: 0=level, 1=edge
      XIRQ_TRIGGER_POLARITY        : std_ulogic_vector(31 downto 0) := x"FFFFFFFF"; -- trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge
      -- Processor peripherals --
      IO_GPIO_NUM                  : natural := 0;      -- number of GPIO input/output pairs (0..64)
      IO_MTIME_EN                  : boolean := false;  -- implement machine system timer (MTIME)?
      IO_UART0_EN                  : boolean := false;  -- implement primary universal asynchronous receiver/transmitter (UART0)?
      IO_UART0_RX_FIFO             : natural := 1;      -- RX fifo depth, has to be a power of two, min 1
      IO_UART0_TX_FIFO             : natural := 1;      -- TX fifo depth, has to be a power of two, min 1
      IO_UART1_EN                  : boolean := false;  -- implement secondary universal asynchronous receiver/transmitter (UART1)?
      IO_UART1_RX_FIFO             : natural := 1;      -- RX fifo depth, has to be a power of two, min 1
      IO_UART1_TX_FIFO             : natural := 1;      -- TX fifo depth, has to be a power of two, min 1
      IO_SPI_EN                    : boolean := false;  -- implement serial peripheral interface (SPI)?
      IO_SPI_FIFO                  : natural := 1;      -- SPI RTX fifo depth, has to be a power of two, min 1
      IO_SDI_EN                    : boolean := false;  -- implement serial data interface (SDI)?
      IO_SDI_FIFO                  : natural := 0;      -- SDI RTX fifo depth, has to be zero or a power of two
      IO_TWI_EN                    : boolean := false;  -- implement two-wire interface (TWI)?
      IO_PWM_NUM_CH                : natural := 0;      -- number of PWM channels to implement (0..12); 0 = disabled
      IO_WDT_EN                    : boolean := false;  -- implement watch dog timer (WDT)?
      IO_TRNG_EN                   : boolean := false;  -- implement true random number generator (TRNG)?
      IO_TRNG_FIFO                 : natural := 1;      -- TRNG fifo depth, has to be a power of two, min 1
      IO_CFS_EN                    : boolean := false;  -- implement custom functions subsystem (CFS)?
      IO_CFS_CONFIG                : std_ulogic_vector(31 downto 0) := x"00000000"; -- custom CFS configuration generic
      IO_CFS_IN_SIZE               : positive := 32;    -- size of CFS input conduit in bits
      IO_CFS_OUT_SIZE              : positive := 32;    -- size of CFS output conduit in bits
      IO_NEOLED_EN                 : boolean := false;  -- implement NeoPixel-compatible smart LED interface (NEOLED)?
      IO_NEOLED_TX_FIFO            : natural := 1;      -- NEOLED FIFO depth, has to be a power of two, min 1
      IO_GPTMR_EN                  : boolean := false;  -- implement general purpose timer (GPTMR)?
      IO_XIP_EN                    : boolean := false;  -- implement execute in place module (XIP)?
      IO_ONEWIRE_EN                : boolean := false   -- implement 1-wire interface (ONEWIRE)?
    );
    port (
      -- Global control --
      clk_i          : in  std_ulogic; -- global clock, rising edge
      rstn_i         : in  std_ulogic; -- global reset, low-active, async
      -- JTAG on-chip debugger interface --
      jtag_trst_i    : in  std_ulogic := 'U'; -- low-active TAP reset (optional)
      jtag_tck_i     : in  std_ulogic := 'U'; -- serial clock
      jtag_tdi_i     : in  std_ulogic := 'U'; -- serial data input
      jtag_tdo_o     : out std_ulogic;        -- serial data output
      jtag_tms_i     : in  std_ulogic := 'U'; -- mode select
      -- Wishbone bus interface (available if MEM_EXT_EN = true) --
      wb_tag_o       : out std_ulogic_vector(02 downto 0); -- request tag
      wb_adr_o       : out std_ulogic_vector(31 downto 0); -- address
      wb_dat_i       : in  std_ulogic_vector(31 downto 0) := (others => 'U'); -- read data
      wb_dat_o       : out std_ulogic_vector(31 downto 0); -- write data
      wb_we_o        : out std_ulogic; -- read/write
      wb_sel_o       : out std_ulogic_vector(03 downto 0); -- byte enable
      wb_stb_o       : out std_ulogic; -- strobe
      wb_cyc_o       : out std_ulogic; -- valid cycle
      wb_ack_i       : in  std_ulogic := 'L'; -- transfer acknowledge
      wb_err_i       : in  std_ulogic := 'L'; -- transfer error
      -- Advanced memory control signals --
      fence_o        : out std_ulogic; -- indicates an executed FENCE operation
      fencei_o       : out std_ulogic; -- indicates an executed FENCEI operation
      -- XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) --
      xip_csn_o      : out std_ulogic; -- chip-select, low-active
      xip_clk_o      : out std_ulogic; -- serial clock
      xip_dat_i      : in  std_ulogic := 'L'; -- device data input
      xip_dat_o      : out std_ulogic; -- controller data output
      -- GPIO (available if IO_GPIO_NUM > 0) --
      gpio_o         : out std_ulogic_vector(63 downto 0); -- parallel output
      gpio_i         : in  std_ulogic_vector(63 downto 0) := (others => 'U'); -- parallel input
      -- primary UART0 (available if IO_UART0_EN = true) --
      uart0_txd_o    : out std_ulogic; -- UART0 send data
      uart0_rxd_i    : in  std_ulogic := 'U'; -- UART0 receive data
      uart0_rts_o    : out std_ulogic; -- HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
      uart0_cts_i    : in  std_ulogic := 'L'; -- HW flow control: UART0.TX allowed to transmit, low-active, optional
      -- secondary UART1 (available if IO_UART1_EN = true) --
      uart1_txd_o    : out std_ulogic; -- UART1 send data
      uart1_rxd_i    : in  std_ulogic := 'U'; -- UART1 receive data
      uart1_rts_o    : out std_ulogic; -- HW flow control: UART1.RX ready to receive ("RTR"), low-active, optional
      uart1_cts_i    : in  std_ulogic := 'L'; -- HW flow control: UART1.TX allowed to transmit, low-active, optional
      -- SPI (available if IO_SPI_EN = true) --
      spi_clk_o      : out std_ulogic; -- SPI serial clock
      spi_dat_o      : out std_ulogic; -- controller data out, peripheral data in
      spi_dat_i      : in  std_ulogic := 'U'; -- controller data in, peripheral data out
      spi_csn_o      : out std_ulogic_vector(07 downto 0); -- SPI CS
      -- SDI (available if IO_SDI_EN = true) --
      sdi_clk_i      : in  std_ulogic := 'U'; -- SDI serial clock
      sdi_dat_o      : out std_ulogic; -- controller data out, peripheral data in
      sdi_dat_i      : in  std_ulogic := 'U'; -- controller data in, peripheral data out
      sdi_csn_i      : in  std_ulogic := 'H'; -- chip-select
      -- TWI (available if IO_TWI_EN = true) --
      twi_sda_i      : in  std_ulogic := 'H'; -- serial data line sense input
      twi_sda_o      : out std_ulogic; -- serial data line output (pull low only)
      twi_scl_i      : in  std_ulogic := 'H'; -- serial clock line sense input
      twi_scl_o      : out std_ulogic; -- serial clock line output (pull low only)
      -- 1-Wire Interface (available if IO_ONEWIRE_EN = true) --
      onewire_i      : in  std_ulogic := 'H'; -- 1-wire bus sense input
      onewire_o      : out std_ulogic; -- 1-wire bus output (pull low only)
      -- PWM (available if IO_PWM_NUM_CH > 0) --
      pwm_o          : out std_ulogic_vector(11 downto 0); -- pwm channels
      -- Custom Functions Subsystem IO --
      cfs_in_i       : in  std_ulogic_vector(IO_CFS_IN_SIZE-1 downto 0) := (others => 'U'); -- custom CFS inputs conduit
      cfs_out_o      : out std_ulogic_vector(IO_CFS_OUT_SIZE-1 downto 0); -- custom CFS outputs conduit
      -- NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) --
      neoled_o       : out std_ulogic; -- async serial data line
      -- External platform interrupts (available if XIRQ_NUM_CH > 0) --
      xirq_i         : in  std_ulogic_vector(31 downto 0) := (others => 'L'); -- IRQ channels
      -- CPU Interrupts --
      mtime_irq_i    : in  std_ulogic := 'L'; -- machine timer interrupt, available if IO_MTIME_EN = false
      msw_irq_i      : in  std_ulogic := 'L'; -- machine software interrupt
      mext_irq_i     : in  std_ulogic := 'L'  -- machine external interrupt
      -- DFT signal --
    );
  end component;

end neorv32_package;

package body neorv32_package is

-- ****************************************************************************************************************************
-- Functions
-- ****************************************************************************************************************************

  -- Function: Minimal required number of bits to represent <input> numbers -----------------
  -- -------------------------------------------------------------------------------------------
  function index_size_f(input : natural) return natural is
  begin
    for i in 0 to natural'high loop
      if (2**i >= input) then
        return i;
      end if;
    end loop; -- i
    return 0;
  end function index_size_f;

  -- Function: AND-reduce all bits ----------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  function and_reduce_f(a : std_ulogic_vector) return std_ulogic is
    variable tmp_v : std_ulogic;
  begin
    tmp_v := '1';
    for i in a'range loop
      tmp_v := tmp_v and a(i);
    end loop; -- i
    return tmp_v;
  end function and_reduce_f;

  -- Function: Initialize mem32_t array from another mem32_t array --------------------------
  -- -------------------------------------------------------------------------------------------
  -- impure function: returns NOT the same result every time it is evaluated with the same arguments since the source file might have changed
  impure function mem32_init_f(init : mem32_t; depth : natural) return mem32_t is
    variable mem_v : mem32_t(0 to depth-1);
  begin
    mem_v := (others => (others => '0')); -- make sure remaining memory entries are set to zero
    if (init'length > depth) then
      return mem_v;
    end if;
    for idx_v in 0 to init'length-1 loop -- init only in range of source data array
      mem_v(idx_v) := init(idx_v);
    end loop; -- idx_v
    return mem_v;
  end function mem32_init_f;


end neorv32_package;

-- ****************************************************************************************************************************
-- Additional Packages
-- ****************************************************************************************************************************

  -- Prototype Definition: bootloader_init_image --------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- > memory content in 'neorv32_bootloader_image.vhd', auto-generated by 'image_gen'
  -- > used by 'neorv32_boot_rom.vhd'
  -- > enables body-only recompile in case of firmware change (NEORV32 PR #338)

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

package neorv32_bootloader_image is
  constant bootloader_init_image : mem32_t;
end neorv32_bootloader_image;


  -- Prototype Definition: neorv32_application_image ----------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- > memory content in 'neorv32_application_image.vhd', auto-generated by 'image_gen'
  -- > used by 'mem/neorv32_imem.*.vhd'
  -- > enables body-only recompile in case of firmware change (NEORV32 PR #338)

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

package neorv32_application_image is
  constant application_init_image : mem32_t;
end neorv32_application_image;
