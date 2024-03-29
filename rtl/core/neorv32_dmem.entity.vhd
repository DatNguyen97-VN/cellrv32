-- #################################################################################################
-- # << CELLRV32 - Processor-Internal Data Memory (DMEM) - Entity-Only >>                          #
-- # ********************************************************************************************* #

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cellrv32_dmem is
  generic (
    DMEM_BASE : std_ulogic_vector(31 downto 0); -- memory base address
    DMEM_SIZE : natural -- processor-internal instruction memory size in bytes
  );
  port (
    clk_i  : in  std_ulogic; -- global clock line
    rden_i : in  std_ulogic; -- read enable
    wren_i : in  std_ulogic; -- write enable
    ben_i  : in  std_ulogic_vector(03 downto 0); -- byte write enable
    addr_i : in  std_ulogic_vector(31 downto 0); -- address
    data_i : in  std_ulogic_vector(31 downto 0); -- data in
    data_o : out std_ulogic_vector(31 downto 0); -- data out
    ack_o  : out std_ulogic -- transfer acknowledge
  );
end cellrv32_dmem;
