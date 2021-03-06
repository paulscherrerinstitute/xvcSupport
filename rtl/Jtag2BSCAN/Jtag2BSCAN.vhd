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
    USERCODE_VAL_G : std_logic_vector(31 downto 0) := x"ffffffff";
    TCK_IS_CLOCK_G : boolean                       := true
  );
  port (
    clk            : in  std_logic := '0';
    rst            : in  std_logic := '0';
    JTCK_POSEDGE   : in  std_logic := '0';
    JTCK_NEGEDGE   : in  std_logic := '0';

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
    TDI            : out std_logic;
    UPDATE_SEL     : out std_logic;
    DRCK_SEL       : out std_logic
  );
end entity Jtag2BSCAN;

architecture Impl of Jtag2BSCAN is

  signal testLogicResetLoc     : std_logic;
  signal scanDRLoc             : std_logic;
  signal scanIRLoc             : std_logic;
  signal captureLoc            : std_logic;
  signal shiftLoc              : std_logic;
  signal updateLoc             : std_logic;

  signal captureIRLoc          : std_logic;
  signal shiftIRLoc            : std_logic;
  signal updateIRLoc           : std_logic;
  signal captureDRLoc          : std_logic;
  signal shiftDRLoc            : std_logic;
  signal updateDRLoc           : std_logic;

  signal selUSERTap            : std_logic;
  signal tapTdoLoc             : std_logic;

  signal testLogicResetPredict : std_logic;

  type RegType is record
    tdo        : std_logic;
    captureDR  : std_logic;
    shiftDR    : std_logic;
    updateDR   : std_logic;
    selUSER    : std_logic;
    drckSel    : std_logic;
  end record RegType;

  constant REG_INIT_C : RegType := (
    tdo        => '0',
    captureDR  => '0',
    shiftDR    => '0',
    updateDR   => '0',
    selUSER    => '0',
    drckSel    => '0'
  );

  signal r, rin : RegType := REG_INIT_C;

begin

  U_TapFsm : entity work.JtagTapFSM
    generic map (
      TCK_IS_CLOCK_G  => TCK_IS_CLOCK_G
    )
    port map (
      clk             => clk,
      rst             => rst,
      tck_posedge     => JTCK_POSEDGE,
      tck_negedge     => JTCK_NEGEDGE,
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
      update          => updateLoc,
      nextStateTLR    => testLogicResetPredict
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
      USERCODE_VAL_G => USERCODE_VAL_G,
      TCK_IS_CLOCK_G => TCK_IS_CLOCK_G
    )
    port map (
      clk            => clk,
      rst            => rst,
      tck_posedge    => JTCK_POSEDGE,
      tck_negedge    => JTCK_NEGEDGE,
      tck            => JTCK,
      tdi            => JTDI,
      testLogicReset => testLogicResetLoc,
      captureIR      => captureIRLoc,
      shiftIR        => shiftIRLoc,
      updateIR       => updateIRLoc,
      captureDR      => captureDRLoc,
      shiftDR        => shiftDRLoc,
      tdo            => tapTdoLoc,
      selUSER        => selUSERTap,
      selBYPASS      => open
    );

  P_COMB : process (r, tapTdoLoc, selUSERTap, TDO, captureDRLoc, shiftDRLoc, updateDRLoc, shiftIRLoc, updateIRLoc, testLogicResetLoc) is
    variable v  : RegType;
    variable OE : std_logic;
  begin
    v  := r;
    OE := shiftDRLoc or shiftIRLoc;
    if ( (selUSERTap = '1') and (shiftIRLoc = '0') ) then
      v.tdo     := TDO;
    else
      v.tdo     := tapTdoLoc;
    end if;

    -- BSCANE2 (vhdl -- verilog seems different!) asserts SEL only when USER2 is captured the first time;
    -- if captured again (while not changing IR contents in between) then SEL is deasserted!
    -- This is most likely a bug in the VHDL simulation code (JTAG_SIM_VIRTEX6) and does not work with ICON.
    -- Thus, we stick to asserting selUSER while the IR holds USER2
    if ( testLogicResetLoc = '1' ) then
      v.selUSER    := '0';
    elsif ( updateIRLoc = '1' ) then
      v.selUSER    := selUSERTap;
    end if;
    v.tdo       := v.tdo or not OE;
    v.captureDR := captureDRLoc;
    v.shiftDR   := shiftDRLoc;
    v.updateDR  := updateDRLoc;
    v.drckSel   := (captureDRLoc or shiftDRLoc) and v.selUSER;
    rin <= v;
  end process P_COMB;

  G_TCK : if ( TCK_IS_CLOCK_G ) generate
    signal selUSERLoc        : std_logic;
  begin
    P_SEQ : process ( JTCK ) is
    begin
      if ( falling_edge( JTCK ) ) then
        r <= rin;
      end if;
    end process P_SEQ;

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
    selUSERLoc <= r.selUSER and not testLogicResetLoc;

    DRCK       <= (JTCK and r.drckSel ) or (not r.drckSel and selUSERLoc);
    SEL        <= selUSERLoc;

  -- original BSCANE2 simulation deasserts on the positive clock edge when IR is
  -- updated:
  --
  --   UPDATE <= r.updateDR and updateDrLoc
  --
  -- however, we want to minimize the combinatorial logic here
  -- because ICON seems to use UPDATE as a clock and any combinatorial
  -- input seems to be treated as a different input clock (which we'd have
  -- to constrain...)
    UPDATE     <= r.updateDR; -- and updateDRLoc;


  end generate G_TCK;

  G_TCK_CE : if ( not TCK_IS_CLOCK_G ) generate
  begin

    P_SEQ : process ( clk ) is
    begin
      if ( rising_edge( clk ) ) then
        if ( rst = '1' ) then
          r      <= REG_INIT_C;
          DRCK   <= '0';
          SEL    <= '0';
          UPDATE <= '0';
        elsif ( (JTCK_NEGEDGE = '1') or (JTCK_POSEDGE = '1') ) then
          if ( (JTCK_NEGEDGE = '1') ) then
            r      <= rin;
            UPDATE <= rin.updateDR;
            SEL    <= rin.selUSER;
          else
            UPDATE <= '0';
          end if;
          DRCK     <= (JTCK and rin.drckSel ) or (not rin.drckSel and rin.selUSER);
          if ( testLogicResetPredict = '1' and JTCK_POSEDGE = '1' ) then
              SEL  <= '0';
              DRCK <= '0';
           end if;
        end if;
      end if;
    end process P_SEQ;

  end generate G_TCK_CE;

  CAPTURE <= r.captureDR;
  SHIFT   <= r.shiftDR;
  RESET   <= testLogicResetLoc;
  TDI     <= JTDI;
  JTDO    <= r.tdo;

  DRCK_SEL   <= r.drckSel;
  UPDATE_SEL <= updateDRLoc;

end architecture Impl;
