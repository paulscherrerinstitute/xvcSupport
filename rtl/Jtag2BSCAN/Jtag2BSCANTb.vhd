-- JTAG TAP with BSCAN interface (support for external USER register)
-- Emulates a Xilinx BSCANE2 unit while offering fabric JTAG connections
-- (The hard BSCANE2 units require access to the dedicated hardware pins).
-- 
-- Till Straumann, 9/2020. (Inspiration from bscan_equiv.v by Patrick Allison)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.Jtag2BSCANTbPkg.all;

entity Jtag2BSCANTb is
end entity Jtag2BSCANTb;

architecture Impl of Jtag2BSCANTb is

--  constant PART_NAME_C    : string                                     := "3s700a";
--  constant IR_LENGTH_C    : natural                                    := 6;
--  constant REG_IDCODE_C   : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "001001"; -- must be of IR_LENGTH_C
--  constant REG_USERCODE_C : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "001000"; -- must be of IR_LENGTH_C
--  constant REG_USER_C     : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "000010"; -- must be of IR_LENGTH_C
--  constant IR_VAL_C       : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "110101"; -- must be of IR_LENGTH_C
--  constant IDCODE_VAL_C   : std_logic_vector(31 downto 0)              := x"02228093";
  constant PART_NAME_C    : string                                     := "lx130t";

  constant IR_LENGTH_C    : natural                                    := 10;
  constant REG_IDCODE_C   : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001001"; -- must be of IR_LENGTH_C
  constant REG_USERCODE_C : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001000"; -- must be of IR_LENGTH_C
  constant REG_USER_C     : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111000010"; -- must be of IR_LENGTH_C
  constant IR_VAL_C       : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111010001"; -- must be of IR_LENGTH_C
  constant IDCODE_VAL_C   : std_logic_vector(31 downto 0)              := x"0424a093";
  constant USERCODE_VAL_C : std_logic_vector(31 downto 0)              := x"ffffffff";
  constant USER_VAL_C     : std_logic_vector(31 downto 0)              := x"affecafe";

  constant HALFPERIOD     : time := 60 ns;
  constant SAMPLETIME     : time := 10 ns;

  signal jtck             : std_logic := '0';
  signal jtms             : std_logic := '1';
  signal jtdi             : std_logic := 'X';
  signal jtdo             : std_logic;
  signal jtdocmp          : std_logic;

  signal TDO              : std_logic := 'X';
  signal SEL              : std_logic;
  signal DRCK             : std_logic;
  signal CAPTURE          : std_logic;
  signal SHIFT            : std_logic;
  signal UPDATE           : std_logic;
  signal RESET            : std_logic;
  signal TDI              : std_logic;
  signal SEL_CMP          : std_logic;
  signal DRCK_CMP         : std_logic;
  signal CAPTURE_CMP      : std_logic;
  signal SHIFT_CMP        : std_logic;
  signal UPDATE_CMP       : std_logic;
  signal RESET_CMP        : std_logic;
  signal TDI_CMP          : std_logic;


  signal tstDone          : boolean := false;

  signal IRegOut          : std_logic_vector(IR_LENGTH_C - 1 downto 0);
  signal DRegOut          : std_logic_vector(31              downto 0);

  signal usr              : std_logic_vector(31              downto 0) := (others => 'X');

begin

  P_CLK : process is
  begin
    wait for HALFPERIOD;
    jtck <= not jtck;
    if ( tstDone ) then
      wait;
    end if;
  end process P_CLK;

  P_USR : process ( DRCK ) is
  begin
    if ( rising_edge( DRCK ) ) then
      if ( CAPTURE = '1' ) then
        usr <= USER_VAL_C;
      elsif ( SHIFT = '1' ) then
        usr <= 'X' & usr(usr'left downto 1);
      end if;
    end if;
  end process P_USR;

  TDO <= usr(0);

  B_TST : process  is

    procedure setTMSTDI(constant tms_i : std_logic; constant tdi_i : std_logic) is
    begin
      wait until falling_edge( jtck );
      jtms <= tms_i;
      jtdi <= tdi_i;
      wait until rising_edge( jtck );
    end procedure setTMSTDI;

    procedure setTMS(constant tms_i : std_logic) is
    begin
      setTMSTDI(tms_i, 'X');
    end procedure setTMS;

    procedure testLogicReset is
    begin
      for i in 1 to 5 loop
        setTMS('1');
      end loop;
    end procedure testLogicReset;

    procedure runTestIdle is
    begin
      testLogicReset;
      setTMS('0');
    end procedure runTestIdle;

    procedure doShift(constant reg_i : std_logic_vector; signal reg_o : inout std_logic_vector) is
      variable tmsVal : std_logic;
    begin
      tmsVal := '0';
      for i in reg_i'right to reg_i'left loop
        if ( i = reg_i'left ) then 
          tmsVal := '1';
        end if;
        setTMSTDI(tmsVal, reg_i(i));
        -- reg_o might be wider than reg_i
        reg_o(reg_i'left)              <= jtdo;
        reg_o(reg_i'left - 1 downto 0) <= reg_o(reg_i'left downto 1);
      end loop;
    end procedure doShift;

    -- assume we start from testRunIdle
    procedure scanReg(constant isIR: boolean; constant reg_i : std_logic_vector; signal reg_o : inout std_logic_vector) is
    begin
      setTMS('1');   -- select DR -> selectIR/Capture
      if ( isIR ) then
        setTMS('1'); -- selectIR  -> capture
      end if;
      setTMS('0');   -- capture   -> scan
      setTMS('0');   -- scan      -> exit1
      doShift(reg_i, reg_o);
      setTMS('1');   -- exit1     -> update
      setTMS('0');   -- update    -> testLogicReset
    end procedure scanReg;

    procedure scanIR(constant reg_i : std_logic_vector; signal reg_o : inout std_logic_vector) is
    begin
      scanReg(true, reg_i, reg_o);
    end procedure scanIR;
    
    procedure scanDR(constant reg_i : std_logic_vector; signal reg_o : inout std_logic_vector) is
    begin
      scanReg(false, reg_i, reg_o);
    end procedure scanDR;

    variable DReg : std_logic_vector(DRegOut'range);

  begin

    for i in 1 to 4 loop
      wait until rising_edge( jtck );
    end loop;

    runTestIdle;

    scanIR( REG_IDCODE_C, IRegOut );
    if ( IRegOut /= IR_VAL_C ) then
      report "IR READOUT FAILED" severity failure;
    end if;

    DReg := (others => '0');
    scanDR( DReg, DRegOut );
    if ( DRegOut /= IDCODE_VAL_C ) then
      report "ID READOUT FAILED" severity failure;
    end if;

    scanIR( REG_USER_C, IRegOut );
    DReg := (others => '0');
    scanDR( DReg, DRegOut );
    if ( DRegOut /= USER_VAL_C ) then
      report "USER REG readout failed" severity failure;
    end if;

    scanIR( REG_USERCODE_C, IRegOut );
    DReg := (others => '0');
    scanDR( DReg, DRegOut );
    if ( DRegOut /= USERCODE_VAL_C ) then
      report "USERCODE REG readout failed" severity failure;
    end if;


    tstDone <= true;
    wait;
  end process B_TST;

  B_CMP_P : process is
    variable cnt : natural;
  begin
    cnt := 0;
    for i in 1 to 2 loop
      wait until rising_edge(jtck);
    end loop;
 
    while ( not tstDone ) loop
      wait until jtck'event;
      wait for SAMPLETIME;
      if ( UPDATE /= UPDATE_CMP ) then
        wait until rising_edge(jtck);
        report "UPDATE mismatch" severity failure;
      end if;
      if ( CAPTURE /= CAPTURE_CMP ) then
        wait until rising_edge(jtck);
        report "CAPTURE mismatch" severity failure;
      end if;
      if ( SHIFT /= SHIFT_CMP ) then
        wait until rising_edge(jtck);
        report "SHIFT mismatch" severity failure;
      end if;
      if ( SEL /= SEL_CMP ) then
        wait until rising_edge(jtck);
        report "SEL mismatch" severity failure;
      end if;
      if ( RESET /= RESET_CMP ) then
        wait until rising_edge(jtck);
        report "RESET mismatch" severity failure;
      end if;
      if ( TDI /= TDI_CMP ) then
        wait until rising_edge(jtck);
        report "TDI mismatch" severity failure;
      end if;
      if ( DRCK /= DRCK_CMP ) then
        wait until rising_edge(jtck);
        report "DRCK mismatch" severity failure;
      end if;
      cnt := cnt + 1;
    end loop;

    report "Test PASSED; " & natural'image(cnt) & " comparison loops" severity note;

    wait;
  end process B_CMP_P;

  U_DUT : entity work.Jtag2BSCAN
    generic map (
      IR_LENGTH_G    => IR_LENGTH_C,
      REG_IDCODE_G   => REG_IDCODE_C,
      REG_USERCODE_G => REG_USERCODE_C,
      REG_USER_G     => REG_USER_C,
      IR_VAL_G       => IR_VAL_C,
      IDCODE_VAL_G   => IDCODE_VAL_C,
      USERCODE_VAL_G => USERCODE_VAL_C
    )
    port map (
      JTCK           => jtck,
      JTMS           => jtms,
      JTDI           => jtdi,
      JTDO           => jtdo,

      TDO            => TDO,
      SEL            => SEL,
      DRCK           => DRCK,
      CAPTURE        => CAPTURE,
      SHIFT          => SHIFT,
      UPDATE         => UPDATE,
      RESET          => RESET,
      TDI            => TDI
    );

  U_CMP_TAP : JTAG_SIM_VIRTEX6
    generic map (
      PART_NAME      => PART_NAME_C
    )
    port map (
      TCK            => jtck,
      TMS            => jtms,
      TDI            => jtdi,
      TDO            => jtdocmp
    );

  U_CMP_BSCAN : BSCANE2
    port map (
      TDO            => TDO,

      SEL            => SEL_CMP,
      DRCK           => DRCK_CMP,
      CAPTURE        => CAPTURE_CMP,
      SHIFT          => SHIFT_CMP,
      UPDATE         => UPDATE_CMP,
      RESET          => RESET_CMP,
      TDI            => TDI_CMP,

      RUNTEST        => open,
      TCK            => open,
      TMS            => open
    );
end architecture Impl;

