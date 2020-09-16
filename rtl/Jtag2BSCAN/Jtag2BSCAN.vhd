-- Basic Emulation of BSCANE2 for bridging JTAG to xilinx ICON core

-- Till Straumann, 09/2020.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Jtag2BSCAN is
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
    JTCK           : in  std_logic;
    JTMS           : in  std_logic;
    JTDI           : in  std_logic;
    JTDO           : out std_logic;

    TDO            : in  std_logic;
    SEL            : out std_logic;
    DRCK           : out std_logic;
    CAPTURE        : out std_logic;
    SHIFT          : out std_logic;
    UPDATE         : out std_logic;
    RESET          : out std_logic;
    TDI            : out std_logic
  );
end entity Jtag2BSCAN;

architecture Impl of Jtag2BSCAN is

  signal testLogicResetLoc : std_logic;
  signal scanDRLoc         : std_logic;
  signal scanIRLoc         : std_logic;
  signal captureLoc        : std_logic;
  signal shiftLoc          : std_logic;
  signal updateLoc         : std_logic;

  signal captureIRLoc      : std_logic;
  signal shiftIRLoc        : std_logic;
  signal updateIRLoc       : std_logic;
  signal captureDRLoc      : std_logic;
  signal shiftDRLoc        : std_logic;
  signal updateDRLoc       : std_logic;

  signal selUSERLoc        : std_logic;
  signal tapTdoLoc         : std_logic;

  type RegType is record
    tdo       : std_logic;
    captureDR : std_logic;
    shiftDR   : std_logic;
    updateDR  : std_logic;
    drckGate  : std_logic;
  end record RegType;

  constant REG_INIT_C : RegType := (
    tdo       => '0',
    captureDR => '0',
    shiftDR   => '0',
    updateDR  => '0',
    drckGate  => '1'
  );

  signal r, rin : RegType := REG_INIT_C;

begin

  U_TapFsm : entity work.JtagTapFSM
    port map (
      tck             => JTCK,
      tms             => JTMS,
      tdi             => JTDI,
      testLogicReset  => testLogicResetLoc,
      runTestIdle     => open,
      scanDR          => scanDRLoc,
      scanIR          => scanIRLoc,
      selectScan      => open,
      capture         => captureLoc,
      shift           => shiftLoc,
      exit1           => open,
      pause           => open,
      exit2           => open,
      update          => updateLoc
    );

  captureIRLoc <= (captureLoc and scanIRLoc);
  shiftIRLoc   <= (shiftLoc   and scanIRLoc);
  updateIRLoc  <= (updateLoc  and scanIRLoc);

  captureDRLoc <= (captureLoc and scanDRLoc);
  shiftDRLoc   <= (shiftLoc   and scanDRLoc);
  updateDRLoc  <= (updateLoc  and scanDRLoc);

  U_JtagTapIR : entity work.JtagTapIR
    generic map (
      IR_LENGTH_G    => IR_LENGTH_G,
      REG_IDCODE_G   => REG_IDCODE_G,
      REG_USERCODE_G => REG_USERCODE_G,
      REG_USER_G     => REG_USER_G,
      IR_VAL_G       => IR_VAL_G,
      IDCODE_VAL_G   => IDCODE_VAL_G,
      USERCODE_VAL_G => USERCODE_VAL_G
    )
    port map (
      tck            => JTCK,
      tdi            => JTDI,
      testLogicReset => testLogicResetLoc,
      captureIR      => captureIRLoc,
      shiftIR        => shiftIRLoc,
      updateIR       => updateIRLoc,
      captureDR      => captureDRLoc,
      shiftDR        => shiftDRLoc,
      tdo            => tapTdoLoc,
      selUSER        => selUSERLoc,
      selBYPASS      => open
    );
 
  P_COMB : process (r, tapTdoLoc, selUSERLoc, TDO, captureDRLoc, shiftDRLoc, updateDRLoc, shiftIRLoc) is
    variable v  : RegType;
    variable OE : std_logic;
  begin
    v  := r;
    OE := shiftDRLoc or shiftIRLoc;
    -- selUSERLoc changes state on negative clock edges.
    -- However, this never happens anywhere close to the
    -- shifting state when TDO matters. Thus, the extra
    -- clock cycle delay may be ignored...
    if ( selUSERLoc = '1' and shiftIRLoc = '0' ) then
      v.tdo     := TDO;
    else
      v.tdo     := tapTdoLoc;
    end if;
    v.tdo       := v.tdo or not OE;
    v.captureDR := captureDRLoc;
    v.shiftDR   := shiftDRLoc;
    v.updateDR  := updateDRLoc;
    v.drckGate  := (not captureDRLoc and not shiftDRLoc);
    rin <= v;
  end process P_COMB;


  P_SEQ : process ( JTCK ) is
  begin
    if ( falling_edge( JTCK ) ) then
      r <= rin;
    end if;
  end process P_SEQ;

  CAPTURE <= r.captureDR;
  SHIFT   <= r.shiftDR;
  -- original BSCANE2 deasserts on the positive clock edge when IR is
  -- updated:
  --
  --   UPDATE <= r.updateDR and updateDrLoc
  --
  -- however, we want to minimize the combinatorial logic here
  -- because ICON seems to use UPDATE as a clock and any combinatorial
  -- input seems to be treated as a different input clock (which we'd have
  -- to constrain...)
  UPDATE  <= r.updateDR; -- and updateDRLoc;
  SEL     <= selUSERLoc;
  RESET   <= testLogicResetLoc;
  TDI     <= JTDI;
  JTDO    <= r.tdo;

  -- FIXME: should be able to use a clock buffer but this is not trivial
  --        because the muxing signals change on the same clock edges
  --        and we don't have a higher-freq. clock available..
  --
  --        IF we had a clock that is trailing TCK by 90deg. then
  --        we could generate
  --             if ( rising_edge( TCK90deg ) ) then
  --               selMux <= (captureDRLoc or shiftDRLoc) and selUSERLoc
  --             end if;
  --
  --             (polarity of 'selMux' not verified)
  --             BUFGMUX( I0 => JTCK, I1 => selUSERLoc, SEL => selMux );
  --
  --        while selUSERLoc changes on negative clock edges it is guaranteed
  --        to never switch concurrently with captureDRLoc, shiftDRLoc and thus
  --        there is no chance for glitches.

  DRCK    <= (JTCK or r.drckGate ) and selUSERLoc;
end architecture Impl;
