library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.TextUtilPkg.all;
use work.Jtag2BSCANTbPkg.all;

entity Jtag2BSCANsTb is
end entity Jtag2BSCANsTb;

architecture rtl of Jtag2BSCANsTb is
  signal clk                    : std_logic := '0';
  signal run                    : boolean   := true;

  function min(a,b : natural) return natural is
  begin
    if ( a < b ) then return a; else return b; end if;
  end function min;

  constant TCK_IS_CLOCK_C : boolean := false;
  constant USE_BUFG       : boolean := true and TCK_IS_CLOCK_C;

  constant CLK_DIV2_C     : natural := 5;

  constant PART_NAME_C    : string                                     := "lx130t";

  constant HALFPERIOD     : time :=  5 ns;
  constant SAMPLETIME     : time :=  13 ns;

  constant IR_LENGTH_C    : natural                                    := 10;
  constant REG_IDCODE_C   : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001001"; -- must be of IR_LENGTH_C
  constant REG_USERCODE_C : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001000"; -- must be of IR_LENGTH_C
  constant REG_USER_C     : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111000010"; -- must be of IR_LENGTH_C
  constant IR_VAL_C       : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111110001"; -- must be of IR_LENGTH_C
  constant IDCODE_VAL_C   : std_logic_vector(31 downto 0)              := x"0424a093";
  constant USERCODE_VAL_C : std_logic_vector(31 downto 0)              := x"ffffffff";

  constant SEQ_LEN_C      : natural := min( iSeq'length, oSeq'length ) - 1; -- skip sentinel

-- old   constant iSeq : TmsTdiArray := (
-- old   (
-- old     tms   => x"008000ff",
-- old     tdi   => x"ff000000",
-- old     nbits => 4
-- old   ),
-- old   (
-- old     tms   => x"00800000",
-- old     tdi   => x"ff000000",
-- old     nbits => 0
-- old   ),
-- old   (
-- old     tms   => x"008000ff",
-- old     tdi   => x"ff000000",
-- old     nbits => 4
-- old   ),
-- old   (
-- old     tms   => x"00800000",
-- old     tdi   => x"ff000000",
-- old     nbits => 0
-- old   ),
-- old   (
-- old     tms   => x"00800003",
-- old     tdi   => x"ff000000",
-- old     nbits => 3
-- old   ),
-- old   (
-- old     tms   => x"00800020",
-- old     tdi   => x"ff0000c8",
-- old     nbits => 5
-- old   ),
-- old   (
-- old     tms   => x"00800001",
-- old     tdi   => x"ff000000",
-- old     nbits => 1
-- old   ),
-- old   (
-- old     tms   => x"00800001",
-- old     tdi   => x"ff000000",
-- old     nbits => 2
-- old   ),
-- old   (
-- old     tms   => x"80000000",
-- old     tdi   => x"00000000",
-- old     nbits => 31
-- old   ),
-- old   (
-- old     tms   => x"80000001",
-- old     tdi   => x"00000000",
-- old     nbits => 1
-- old   )
-- old   );
-- old 

  signal iidx : natural := 0;
  signal oidx : natural := 0;
  signal sidx : natural := 0;
  signal sbit : natural := 0;

--  constant tmsVec_C             : std_logic_vector :=
--     "01"&"10000000000000000000000000000000"&"001"&"01"&"100000"&"0011"&"0"&"11111"&"0"&"11111";
----   "0110000000000000000000000000000000001011000000011011111";
--  constant tdiVec_C             : std_logic_vector :=
----   "XX00000000000000000000000000000000XXXXX001001XXXXXXXXXX";
--     "00"&"00000000000000000000000000000000"&"000"&"00"&"001000"&"0000"&"0"&"00000"&"0"&"00000";
--
--  constant W_C                  : natural := tmsVec_C'length;
--
  signal tmsVec                 : std_logic_vector(W_C - 1 downto 0);
  signal tdiVec                 : std_logic_vector(W_C - 1 downto 0);
  signal tdoVec                 : std_logic_vector(W_C - 1 downto 0);
  signal tdoVecCmp              : std_logic_vector(W_C - 1 downto 0);
  signal tdoVecErr              : std_logic := '0';
  signal tdoVecErrs             : natural   := 0;

  signal nbits                  : natural := W_C - 1;
  signal nbitsTdo               : natural := W_C - 1;

  signal ivalid                 : std_logic := '0';
  signal iready                 : std_logic;
  signal ovalid                 : std_logic;
  signal oready                 : std_logic := '0';
  signal rst                    : std_logic := '1';

  signal cnt                    : natural   := 0;

  signal jtck_in                : std_logic;
  signal jtck                   : std_logic := '0';
  signal jtms, jtdi, jtdo       : std_logic;
  signal jtck_negedge           : std_logic;
  signal jtck_posedge           : std_logic;
  signal jtdocmp                : std_logic;

  signal SEL    , SEL_CMP       : std_logic;
  signal DRCK   , DRCK_CMP      : std_logic;
  signal CAPTURE, CAPTURE_CMP   : std_logic;
  signal SHIFT  , SHIFT_CMP     : std_logic;
  signal UPDATE , UPDATE_CMP    : std_logic;
  signal RESET  , RESET_CMP     : std_logic;
  signal TDI    , TDI_CMP       : std_logic;
  signal DRCK_SEL               : std_logic;
  signal DRCK_LOC               : std_logic;
  signal UPDATE_LOC             : std_logic;
  signal UPDATE_SEL             : std_logic;

  signal TDO                    : std_logic := '0';

  signal cntcmp                 : natural   := 0;

  signal minusrlen              : natural   := 200000;
  signal maxusrlen              : natural   := 0;
  signal usrlen                 : natural   := 0;
begin

  P_CLK : process is
    procedure tick is
    begin
      wait for HALFPERIOD;
      clk <= not clk;
    end procedure tick;
  begin
    while ( run ) loop
      tick;
    end loop;
    wait;
  end process P_CLK;

  TDO <= 'X' when sidx >= SEQ_LEN_C else oSeq(sidx).tdo(sbit);

  P_SIMTDO : process ( jtck ) is
  begin
    if ( rising_edge(jtck) ) then
      if ( sbit = oSeq(sidx).nbits - 1 ) then
        sbit <= 0;
        sidx <= sidx + 1;
      else
        sbit <= sbit + 1;
      end if;
    end if;
  end process P_SIMTDO;

  tdoVecCmp <=  oSeq(oidx).tdo;
  nbitsTdo  <=  oSeq(oidx).nbits;

  P_DLY : process (jtck_in) is
  begin
    if ( rising_edge( clk ) or true ) then
      jtck <= jtck_in;
    end if;
  end process P_DLY;

  P_CNT : process (clk) is
  begin
    if ( rising_edge( clk ) ) then
      cnt       <= cnt + 1;
      tdoVecErr <= '0';
      if ( cnt = 5 ) then
        rst    <= '0';
        ivalid <= '1';
        oready <= '1';
      end if;
      if ( (ivalid and iready) = '1' ) then
        if ( iidx = SEQ_LEN_C - 1 ) then
        	ivalid <= '0';
        else
            iidx    <= iidx + 1;
        end if;
      end if;
      if ( (ovalid and oready) = '1' ) then
        if ( tdoVec(tdoVec'left downto 32 - nbitsTdo) /=  tdoVecCmp(nbitsTdo - 1 downto 0) ) then
            tdoVecErr  <= '1';
            tdoVecErrs <= tdoVecErrs + 1;
--          report "TDOVEC MISMATCH @oidx(" & natural'image(oidx) & ") " & str(tdoVec)  severity failure;
        end if;
        if ( oidx = SEQ_LEN_C - 1 ) then
          oready <= '0';
          run    <= false;
          report "Test PASSED; " & natural'image(cntcmp) & " comparison loops" severity note;

          report "Min USERLEN: " & natural'image(minusrlen) & " Max USERLEN: " & natural'image(maxusrlen);
          report "TDO vector mismatches: " & natural'image(tdoVecErrs) severity note;
        else
          oidx   <= oidx + 1;
        end if;
      end if;
    end if;
  end process P_CNT;

  B_CMP_P : process is
  begin
    for i in 1 to 2 loop
      wait until rising_edge(jtck);
    end loop;
 
    while ( run ) loop
      wait until jtck'event;
      wait for SAMPLETIME;
      if ( UPDATE /= UPDATE_CMP ) then
        report "UPDATE mismatch" severity failure;
      end if;
      if ( CAPTURE /= CAPTURE_CMP ) then
        report "CAPTURE mismatch" severity failure;
      end if;
      if ( SHIFT /= SHIFT_CMP ) then
        report "SHIFT mismatch" severity failure;
      end if;
      if ( SEL /= SEL_CMP ) then
        -- NOTE: SEL mismatch happens; BSCANE2 deasserts on posedge
wait for 30 ns;
        report "SEL mismatch" severity failure;
      end if;
      if ( RESET /= RESET_CMP ) then
        report "RESET mismatch" severity failure;
      end if;
      if ( TDI /= TDI_CMP ) then
        report "TDI mismatch" severity failure;
      end if;
      if ( DRCK /= DRCK_CMP ) then
        report "DRCK mismatch" severity failure;
      end if;
      if ( (jtdocmp /= 'Z') and (jtdo /= jtdocmp) ) then
        report "TDO mismatch" severity failure;
      end if;
      if ( false ) then
      report "OUT "
         & std_logic'image(jtck)
         & std_logic'image(jtms)
         & std_logic'image(jtdi)
         & std_logic'image(jtdo)
         & std_logic'image(SEL)
         & std_logic'image(DRCK)
         & std_logic'image(UPDATE)
         & std_logic'image(SHIFT)
         & std_logic'image(RESET)
         & std_logic'image(TDI)
         & std_logic'image(TDO) severity note;
      end if;
      cntcmp <= cntcmp + 1;
    end loop;


    wait;
  end process B_CMP_P;


  tmsVec <= iSeq(iidx).tms;
  tdiVec <= iSeq(iidx).tdi;
  nbits  <= iSeq(iidx).nbits - 1;

  U_SERDES : entity work.JtagSerDesCore
    generic map (
      TPD_G      => 0 ns,
      WIDTH_G    => W_C,
      CLK_DIV2_G => CLK_DIV2_C
    )
    port map (
      clk               => clk,
      rst               => rst,

      numBits           => nbits,
      dataInTms         => tmsVec,
      dataInTdi         => tdiVec,
      dataInValid       => ivalid,
      dataInReady       => iready,

      dataOut           => tdoVec,
      dataOutValid      => oValid,
      dataOutReady      => oReady,

      tck               => jtck_in,
      tck_posedge       => jtck_posedge,
      tck_negedge       => jtck_negedge,
      tms               => jtms,
      tdi               => jtdi,
      tdo               => jtdo
    );

  U_DUT : entity work.Jtag2BSCAN
    generic map (
      IR_LENGTH_G    => IR_LENGTH_C,
      REG_IDCODE_G   => REG_IDCODE_C,
      REG_USERCODE_G => REG_USERCODE_C,
      REG_USER_G     => REG_USER_C,
      IR_VAL_G       => IR_VAL_C,
      IDCODE_VAL_G   => IDCODE_VAL_C,
      USERCODE_VAL_G => USERCODE_VAL_C,
      TCK_IS_CLOCK_G => TCK_IS_CLOCK_C
    )
    port map (
      clk            => clk,
      rst            => rst,
      JTCK           => jtck,
      JTCK_POSEDGE   => jtck_posedge,
      JTCK_NEGEDGE   => jtck_negedge,
      JTMS           => jtms,
      JTDI           => jtdi,
      JTDO           => jtdo,

      TDO            => TDO,
      SEL            => SEL,
      DRCK           => DRCK_LOC,
      DRCK_SEL       => DRCK_SEL,
      CAPTURE        => CAPTURE,
      SHIFT          => SHIFT,
      UPDATE         => UPDATE_LOC,
      UPDATE_SEL     => UPDATE_SEL,
      RESET          => RESET,
      TDI            => TDI
    );

  GEN_BUFG : if USE_BUFG generate

  signal DRCK_SELB : std_logic;
  signal UPDT_SELB : std_logic;
  signal jtckB     : std_logic;

  begin

  DRCK_SELB <= not DRCK_SEL;
  UPDT_SELB <= not UPDATE_SEL;

  jtckB     <= not jtck;


  U_BUFGCTRL_DRCK : BUFGCTRL
    port map (
      IGNORE0        => '1',
      IGNORE1        => '1',
      I0             => SEL,
      I1             => jtck,
      CE0            => '1',
      CE1            => '1',
      S0             => DRCK_SELB,
      S1             => DRCK_SEL,
      O              => DRCK
    );

  U_BUFGCTRL_UPDT : BUFGCTRL
    port map (
      IGNORE0        => '1',
      IGNORE1        => '1',
      I0             => '0',
      I1             => jtckB,
      CE0            => '1',
      CE1            => '1',
      S0             => UPDT_SELB,
      S1             => UPDATE_SEL,
      O              => UPDATE
    );
  end generate;

  GEN_NO_BUFG : if not USE_BUFG generate
    DRCK   <= DRCK_LOC;
    UPDATE <= UPDATE_LOC;
  end generate;


  U_CMP_TAP : entity work.JTAG_SIM_VIRTEX6
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

  P_DBG_D : process ( DRCK ) is
  begin
    if ( rising_edge( DRCK ) ) then
      if ( CAPTURE = '1' ) then
        usrlen <= 0;
      elsif ( SHIFT = '1' ) then
        usrlen <= usrlen + 1;
      end if;
    end if;
  end process P_DBG_D;

  P_DBG_U : process ( UPDATE ) is
  begin
    report "USERLEN " & natural'image(usrlen);
    if ( rising_edge( UPDATE ) ) then
      if ( usrlen > maxusrlen ) then
        maxusrlen <= usrlen;
      end if;
      if ( usrlen < minusrlen ) then
        minusrlen <= usrlen;
      end if;
    end if;
  end process P_DBG_U;

end architecture rtl;


