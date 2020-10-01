-- JTAG TAP controller with support for
--   IDCODE,
--   BYPASS,
--   USERCODE (32-bit data)
--   USER     (external data register)
-- instructions.
-- The IR always reads as IR_VAL_G, USERCODE always reads as USERCODE_VAL_G.

-- Till Straumann, 9/2020.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity JtagTapIR is
  generic (
    IR_LENGTH_G    : natural                       := 6;
    REG_IDCODE_G   : std_logic_vector              := "001001"; -- must be of IR_LENGTH_G
    REG_USERCODE_G : std_logic_vector              := "001000"; -- must be of IR_LENGTH_G
    REG_USER_G     : std_logic_vector              := "000010"; -- must be of IR_LENGTH_G
    IR_VAL_G       : std_logic_vector              := "110101"; -- must be of IR_LENGTH_G
    IDCODE_VAL_G   : std_logic_vector(31 downto 0) := x"22228093";
    USERCODE_VAL_G : std_logic_vector(31 downto 0) := x"ffffffff"
  );
  port (
    tck            : in  std_logic;
    tdi            : in  std_logic;
    testLogicReset : in  std_logic; -- input from FSM
    captureIR      : in  std_logic; -- input from FSM
    shiftIR        : in  std_logic; -- input from FSM
    updateIR       : in  std_logic; -- input from FSM
    captureDR      : in  std_logic; -- input from FSM
    shiftDR        : in  std_logic; -- input from FSM
    tdo            : out std_logic;
    selUSER        : out std_logic; -- USER instruction; changes state on falling edge of TCK
    selBYPASS      : out std_logic  -- BYPASS "  "         "       "    "   "       "  "   "
  );
end entity JtagTapIR;

architecture Impl of JtagTapIR is

  function maxl(a,b : std_logic_vector) return natural is
  begin
    if ( b'length > a'length ) then
      return b'length;
    else
      return a'length;
    end if;
  end function maxl;

  constant MAX_DR_C     : natural := maxl(IDCODE_VAL_G, USERCODE_VAL_G);

  constant REG_BYPASS_C : std_logic_vector(IR_LENGTH_G - 1 downto 0 ) := (others => '1' );

  type RegNType is record
    ir           : std_logic_vector(IR_LENGTH_G - 1 downto 0);
    selBypass    : std_logic;
    selUser      : std_logic;
  end record RegNType;

  constant REG_N_INIT_C : RegNType := (
    ir           => REG_IDCODE_G,
    selBypass    => '0',
    selUser      => '0'
  );

  type RegPType is record
    shift_ir     : std_logic_vector(IR_LENGTH_G - 1 downto 0);
    shift_dr     : std_logic_vector(MAX_DR_C    - 1 downto 0);
    dr_decoded   : boolean;
    dr_lst       : natural range 0 to MAX_DR_C - 1;
  end record RegPType;

  constant REG_P_INIT_C : RegPType := (
    shift_ir   => (others => '0'),
    shift_dr   => (others => '0'),
    dr_decoded => true,
    dr_lst     => 0
  );

  signal rn   : RegNType;
  signal rnin : RegNType := REG_N_INIT_C;

  signal rp   : RegPType;
  signal rpin : RegPType := REG_P_INIT_C;

begin

  P_COMB_N : process ( rn, rp, testLogicReset, updateIR ) is
    variable v : RegNType;
  begin
    v := rn;
    if ( testLogicReset = '1' ) then
      v := REG_N_INIT_C;
    elsif ( updateIR = '1' ) then
      v.ir := rp.shift_ir;
    end if;

    v.selBypass := '0';
    v.selUser   := '0';
    if ( v.ir = REG_BYPASS_C ) then
       v.selBypass := '1';
    elsif ( v.ir = REG_USER_G ) then
       v.selUser   := '1';
    end if;

    rnin <= v;
  end process P_COMB_N;

  P_COMB_P : process ( rn, rp, tdi, testLogicReset, captureIR, shiftIR, captureDR, shiftDR ) is
    variable v : RegPType;
  begin
    v := rp;
    if ( testLogicReset = '1' ) then
      v := REG_P_INIT_C;
    elsif ( captureIR = '1' ) then
      v.shift_ir := IR_VAL_G;   
    elsif ( shiftIR = '1' ) then
      v.shift_ir := (tdi & rp.shift_ir(rp.shift_ir'left downto 1));
    elsif ( captureDR = '1' ) then
      v.dr_decoded := true;
      if ( rn.ir = REG_IDCODE_G ) then
          v.shift_dr(IDCODE_VAL_G'range)   := IDCODE_VAL_G; 
          v.dr_lst                         := IDCODE_VAL_G'left;
      elsif ( rn.ir = REG_USERCODE_G ) then
          v.shift_dr(USERCODE_VAL_G'range) := USERCODE_VAL_G; 
          v.dr_lst                         := USERCODE_VAL_G'left;
      else -- includes REG_BYPASS_C
          if ( rn.ir /= REG_BYPASS_C ) then
            v.dr_decoded := false;
          end if;
          v.shift_dr(0) := '0';
          v.dr_lst      := 0;
      end if;
    elsif ( shiftDR = '1' ) then
      v.shift_dr( v.dr_lst )              := tdi;
      v.shift_dr( v.dr_lst - 1 downto 0 ) := rp.shift_dr( v.dr_lst downto 1 );
    end if;

    rpin <= v;
  end process P_COMB_P;

  P_SEQ_N : process ( tck ) is
  begin
    if ( falling_edge( tck ) ) then
      rn <= rnin;
    end if;
  end process P_SEQ_N;

  P_SEQ_P : process ( tck ) is
  begin
    if ( rising_edge( tck ) ) then
      rp <= rpin;
    end if;
  end process P_SEQ_P;


  -- output signals must still be registered on falling edge by the user
  selBYPASS <= rnin.selBypass;
  selUSER   <= rnin.selUser;
  tdo       <= rp.shift_ir(0) when shiftIR = '1' else rp.shift_dr(0) when rp.dr_decoded else '1';

end architecture Impl;
