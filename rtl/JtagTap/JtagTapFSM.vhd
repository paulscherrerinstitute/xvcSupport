-- JTAG State Machine

-- Till Straumann, 9/2020.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The current state is flagged on the respective output.
-- During one of the the shifting (sub-)states (selectScan..update)
-- either scanDR or scanIR is asserted.
-- E.g., capture_DR may be detected as
--
--   capture_DR <= capture and scanDR;
--
-- The outputs change state on the rising edge of tck.

entity JtagTapFsm is
  generic (
    TCK_IS_CLOCK_G : boolean := true
  );
  port (
    clk            : in  std_logic := '0';
    rst            : in  std_logic := '0';
    tck_posedge    : in  std_logic := '0';
    tck_negedge    : in  std_logic := '0';
    tck            : in  std_logic;
    tms            : in  std_logic;
    tdi            : in  std_logic;
    testLogicReset : out std_logic;
    runTestIdle    : out std_logic;
    scanDR         : out std_logic;
    scanIR         : out std_logic;
    selectScan     : out std_logic;
    capture        : out std_logic;
    shift          : out std_logic;
    exit1          : out std_logic;
    pause          : out std_logic;
    exit2          : out std_logic;
    update         : out std_logic
  );
end entity JtagTapFsm;

architecture Impl of JtagTapFsm is

  constant TEST_LOGIC_RESET_C : natural := 0;
  constant RUN_TEST_IDLE_C    : natural := 1;
  constant SCAN_DR_C          : natural := 2;
  constant SCAN_IR_C          : natural := 3;

  constant SELECT_SCAN_C      : natural := 0;
  constant CAPTURE_C          : natural := 1;
  constant SHIFT_C            : natural := 2;
  constant EXIT1_C            : natural := 3;
  constant PAUSE_C            : natural := 4;
  constant EXIT2_C            : natural := 5;
  constant UPDATE_C           : natural := 6;

  subtype  TapPrimaryStateType is std_logic_vector(SCAN_IR_C downto TEST_LOGIC_RESET_C);
  subtype  TapScanStateType    is std_logic_vector(UPDATE_C  downto SELECT_SCAN_C     );

  type RegType is record
    primaryState : TapPrimaryStateType;
    scanSubState : TapScanStateType;
  end record;

  constant REG_INIT_C : RegType := (
    primaryState => ( TEST_LOGIC_RESET_C => '1', others => '0' ),
    scanSubState => (others => '0' )
  );

  signal r   : RegType := REG_INIT_C;
  signal rin : RegType;

  function nextPrimaryState(s : natural range TapPrimaryStateType'range) return TapPrimaryStateType is
    variable v : TapPrimaryStateType;
  begin
    v := (others => '0');
    v(s) := '1';
    return v;
  end function nextPrimaryState;

  function nextScanState(s : natural range TapScanStateType'range) return TapScanStateType is
    variable v : TapScanStateType;
  begin
    v := (others => '0');
    v(s) := '1';
    return v;
  end function nextScanState;

  function nextScanState return TapScanStateType is
    variable v : TapScanStateType;
  begin
    v := (others => '0');
    return v;
  end function nextScanState;


begin

  P_COMB : process (r, tms, tdi) is
    variable v : RegType;
  begin
    v := r;

    if ( r.primaryState(TEST_LOGIC_RESET_C) = '1' ) then
      if ( tms = '0' ) then
        v.primaryState := nextPrimaryState( RUN_TEST_IDLE_C );
      end if;
    elsif ( r.primaryState(RUN_TEST_IDLE_C) = '1' ) then
      if ( tms = '1' ) then
        v.primaryState := nextPrimaryState( SCAN_DR_C     );
        v.scanSubState    := nextScanState   ( SELECT_SCAN_C );
      end if;
    elsif ( r.primaryState(SCAN_DR_C) = '1' or r.primaryState(SCAN_IR_C) = '1' ) then
      if ( r.scanSubState(SELECT_SCAN_C) = '1' ) then
        if ( tms = '1' ) then
          if ( r.primaryState(SCAN_DR_C) = '1' ) then
            v.primaryState := nextPrimaryState( SCAN_IR_C );
          else
            v.primaryState := nextPrimaryState( TEST_LOGIC_RESET_C );
            v.scanSubState := nextScanState;
          end if;
        else
          v.scanSubState := nextScanState( CAPTURE_C );
        end if;
      elsif ( r.scanSubState(CAPTURE_C) = '1' ) then
        if ( tms = '1' ) then
          v.scanSubState := nextScanState( EXIT1_C );
        else
          v.scanSubState := nextScanState( SHIFT_C );
        end if;
      elsif ( r.scanSubState( SHIFT_C ) = '1' ) then
        if ( tms = '1' ) then
          v.scanSubState := nextScanState( EXIT1_C );
        end if;
      elsif ( r.scanSubState( EXIT1_C ) = '1' ) then
        if ( tms = '1' ) then
          v.scanSubState := nextScanState( UPDATE_C );
        else
          v.scanSubState := nextScanState( PAUSE_C  );
        end if;
      elsif ( r.scanSubState( PAUSE_C ) = '1' ) then
        if ( tms = '1' ) then
          v.scanSubState := nextScanState( EXIT2_C  );
        end if;
      elsif ( r.scanSubState( EXIT2_C ) = '1' ) then
        if ( tms = '1' ) then
          v.scanSubState := nextScanState( UPDATE_C );
        else
          v.scanSubState := nextScanState( SHIFT_C  );
        end if;
      elsif ( r.scanSubState( UPDATE_C ) = '1' ) then
        if ( tms = '1' ) then
          v.primaryState := nextPrimaryState( SCAN_DR_C     );
          v.scanSubState := nextScanState   ( SELECT_SCAN_C );
        else
          v.primaryState := nextPrimaryState( RUN_TEST_IDLE_C );
          v.scanSubState := nextScanState;
        end if;
      else
        report "This Scan State Should Never Be Reached" severity failure;
        
        v.primaryState := nextPrimaryState( TEST_LOGIC_RESET_C );
        v.scanSubState := nextScanState;
      end if;
    else
      report "This Primary State Should Never Be Reached" severity failure;
      v.primaryState := nextPrimaryState( TEST_LOGIC_RESET_C );
      v.scanSubState := nextScanState;
    end if;

    rin <= v;
  end process P_COMB;  

  G_TCK : if ( TCK_IS_CLOCK_G ) generate
    P_SEQ : process (tck) is
    begin
      if ( rising_edge( tck ) ) then
        r <= rin;
      end if;
    end process P_SEQ;
  end generate G_TCK;

  G_TCK_CE : if ( not TCK_IS_CLOCK_G ) generate
    P_SEQ : process (clk) is
    begin
      if ( rising_edge( clk ) ) then
        if ( rst = '1' ) then
          r <= REG_INIT_C;
        elsif ( tck_posedge = '1' ) then
          r <= rin;
        end if;
      end if;
    end process P_SEQ;
  end generate G_TCK_CE;

  testLogicReset <= r.primaryState( TEST_LOGIC_RESET_C );
  runTestIdle    <= r.primaryState( RUN_TEST_IDLE_C    );
  scanDR         <= r.primaryState( SCAN_DR_C          );
  scanIR         <= r.primaryState( SCAN_IR_C          );
  selectScan     <= r.scanSubState( SELECT_SCAN_C      );
  capture        <= r.scanSubState( CAPTURE_C          );
  shift          <= r.scanSubState( SHIFT_C            );
  exit1          <= r.scanSubState( EXIT1_C            );
  pause          <= r.scanSubState( PAUSE_C            );
  exit2          <= r.scanSubState( EXIT2_C            );
  update         <= r.scanSubState( UPDATE_C           );

end architecture Impl;
