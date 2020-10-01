library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package Jtag2BSCANTbPkg is

  constant W_C : natural := 32;

  type   TmsTdiType is record
    tms   : std_logic_vector(W_C - 1 downto 0);
    tdi   : std_logic_vector(W_C - 1 downto 0);
    nbits : natural range 0 to W_C;
  end record;

  type   TdoType is record
    tdo   : std_logic_vector(W_C - 1 downto 0);
    nbits : natural range 0 to W_C;
  end record;


  type TmsTdiArray is array (natural range <>) of TmsTdiType;
  type TdoArray    is array (natural range <>) of TdoType;

  constant iSeq : TmsTdiArray;
  constant oSeq : TdoArray;

end package Jtag2BSCANTbPkg;


