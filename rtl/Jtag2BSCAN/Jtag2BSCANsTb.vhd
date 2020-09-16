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

  constant CLK_DIV2_C     : natural := 2;

  constant PART_NAME_C    : string                                     := "lx130t";

  constant SAMPLETIME     : time := 10 ns;

  constant IR_LENGTH_C    : natural                                    := 10;
  constant REG_IDCODE_C   : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001001"; -- must be of IR_LENGTH_C
  constant REG_USERCODE_C : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111001000"; -- must be of IR_LENGTH_C
  constant REG_USER_C     : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111000010"; -- must be of IR_LENGTH_C
  constant IR_VAL_C       : std_logic_vector(IR_LENGTH_C - 1 downto 0) := "1111010001"; -- must be of IR_LENGTH_C
  constant IDCODE_VAL_C   : std_logic_vector(31 downto 0)              := x"0424a093";
  constant USERCODE_VAL_C : std_logic_vector(31 downto 0)              := x"ffffffff";

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

  signal nbits                  : natural := W_C - 1;

  signal ivalid                 : std_logic := '0';
  signal iready                 : std_logic;
  signal ovalid                 : std_logic;
  signal oready                 : std_logic := '0';
  signal rst                    : std_logic := '1';

  signal cnt                    : natural   := 0;

  signal jtck, jtms, jtdi, jtdo : std_logic;
  signal jtdocmp                : std_logic;

  signal SEL    , SEL_CMP       : std_logic;
  signal DRCK   , DRCK_CMP      : std_logic;
  signal CAPTURE, CAPTURE_CMP   : std_logic;
  signal SHIFT  , SHIFT_CMP     : std_logic;
  signal UPDATE , UPDATE_CMP    : std_logic;
  signal RESET  , RESET_CMP     : std_logic;
  signal TDI    , TDI_CMP       : std_logic;

  signal TDO                    : std_logic := '0';

  signal togl                   : std_logic := '1';

  signal cntcmp                 : natural   := 0;
begin

  P_CLK : process is
    procedure tick is
    begin
      wait for 30 ns;
      clk <= not clk;
    end procedure tick;
  begin
    while ( run ) loop
      tick;
    end loop;
    wait;
  end process P_CLK;

  P_TGL : process (jtck) is
  begin
    if (falling_edge(jtck)) then
      togl <= not togl;
    end if;
  end process P_TGL;

  TDO <= togl;

  P_CNT : process (clk) is
  begin
    if ( rising_edge( clk ) ) then
      cnt <= cnt + 1;
      if ( cnt = 5 ) then
        rst    <= '0';
        ivalid <= '1';
        oready <= '1';
      end if;
      if ( (ivalid and iready) = '1' ) then
        if ( iidx = iSeq'length - 1 ) then
        	ivalid <= '0';
        else
            iidx    <= iidx + 1;
        end if;
      end if;
      if ( (ovalid and oready) = '1' ) then
--NOPRINT        print( str(tdoVec) );
        if ( oidx = iSeq'length - 1 ) then
          oready <= '0';
          run    <= false;
          report "Test PASSED; " & natural'image(cntcmp) & " comparison loops" severity note;
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
      clk => clk,
      rst => rst,
      numBits           => nbits,
      dataInTms         => tmsVec,
      dataInTdi         => tdiVec,
      dataInValid       => ivalid,
      dataInReady       => iready,

      dataOut           => tdoVec,
      dataOutValid      => oValid,
      dataOutReady      => oReady,

      tck               => jtck,
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

end architecture rtl;


