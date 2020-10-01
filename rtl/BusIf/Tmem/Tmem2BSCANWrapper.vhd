library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

library unisim;
use unisim.vcomponents.all;

entity Tmem2BSCANWrapper is
  generic (
    DEVICE_G    : string  := "VIRTEX6";
    TMEM_CS_G   : std_logic_vector(1 downto 0) := "00"; -- CS to which the block responds
    USE_BUFS_G  : natural := 2;
    USE_AXIS_G  : boolean := false
  );
  port (
    clk         : in  sl;
    rst         : in  sl;

    tmemADD     : in  slv(23 downto 3);
    tmemDATW    : in  slv(63 downto 0);
    tmemENA     : in  sl;
    tmemWE      : in  slv( 7 downto 0);
    tmemCS      : in  slv( 1 downto 0);

    tmemDATR    : out slv(63 downto 0);
    tmemBUSY    : out sl;
    tmemPIPE    : out slv( 1 downto 0);

    TDO_IN      : in  std_logic;
    TDI_OUT     : out std_logic;
    RESET_OUT   : out std_logic;
    SHIFT_OUT   : out std_logic;
    UPDATE_OUT  : out std_logic;
    CAPTURE_OUT : out std_logic;
    SEL_OUT     : out std_logic;
    DRCK_OUT    : out std_logic;

    JTCK_OUT    : out std_logic;

    irq         : out sl
  );
end entity Tmem2BSCANWrapper;

architecture Impl of Tmem2BSCANWrapper is

  constant W_C          : natural := 4;

  constant NWORDS_C     : natural := 2048 / W_C; -- 18kBit FIFO

  -- increments of 0100 are backwards incompatible
  constant VERSION_C    : std_logic_vector(3 downto 0) := "0001";

begin

  -- use a block so we have a name we can attach constraints to
  B_XvcJtagWrapper : block is
    signal axisTmsTdiPri  : AxiStreamMasterType; -- incoming stream
    signal axisTmsTdiSub  : AxiStreamSlaveType;
    signal axisTdoPri     : AxiStreamMasterType; -- incoming stream
    signal axisTdoSub     : AxiStreamSlaveType;

    signal tck, tms, tdi, tdo : std_logic;
    signal tck_in             : std_logic;
    signal tck_in_serdes      : std_logic;
    signal tck_in_bitbang     : std_logic;
    signal tms_in_serdes      : std_logic;
    signal tms_in_bitbang     : std_logic;
    signal tdi_in_serdes      : std_logic;
    signal tdi_in_bitbang     : std_logic;

    signal bb_msk             : std_logic;

    signal bscn_tdo, bscn_tdi : std_logic;
    signal bscn_rst, bscn_shf : std_logic;
    signal bscn_upd, bscn_cap : std_logic;
    signal bscn_sel, bscn_dck : std_logic;

    signal bscn_tdo1, bscn_tdi1 : std_logic;
    signal bscn_rst1, bscn_shf1 : std_logic;
    signal bscn_upd1, bscn_cap1 : std_logic;
    signal bscn_sel1, bscn_dck1 : std_logic;


    signal ctrl0              : std_logic_vector(35 downto 0);
    signal trig               : std_logic_vector( 7 downto 0);

    attribute KEEP            : string;
    attribute KEEP of tck     : signal is "TRUE";
    attribute KEEP of tck_in  : signal is "TRUE";
    attribute KEEP of tms     : signal is "TRUE";
    attribute KEEP of tdo     : signal is "TRUE";
    attribute KEEP of tdi     : signal is "TRUE";
    attribute KEEP of bscn_tdo: signal is "TRUE";
    attribute KEEP of bscn_tdi: signal is "TRUE";
    attribute KEEP of bscn_rst: signal is "TRUE";
    attribute KEEP of bscn_shf: signal is "TRUE";
    attribute KEEP of bscn_upd: signal is "TRUE";
    attribute KEEP of bscn_cap: signal is "TRUE";
    attribute KEEP of bscn_sel: signal is "TRUE";
    attribute KEEP of bscn_dck: signal is "TRUE";

    signal drck_loc           : std_logic;
    signal updt_loc           : std_logic;
    signal drck_sel           : std_logic;
    signal updt_sel           : std_logic;

    signal auxIn              : std_logic_vector(127 downto 0) := (others => '0');
    signal auxOut             : std_logic_vector(auxIn'range);

    signal serDesInRdy        : std_logic := '0';
    signal serDesInVal        : std_logic;

    signal serDesOutVal       : std_logic := '0';
    signal tdoVal             : std_logic_vector( 31 downto 0);

    signal numBits            : natural range 0 to 8*W_C - 1;

    function AUX_RO_M_F return std_logic_vector is
      variable v := std_logic_vector(auxIn'range);
    begin
      v := x"ffffffff_7ff8fee0_00000000_00000000";
      if ( USE_AXIS_G ) then
        v := v or x"00000000_0000ffff_00000000_00000000";
      end if;
      return v;
    end function AUX_RO_M_F;

    constant  AUX_INIT_C      : std_logic_vector(auxIn'range) := x"00000000_00020000_00000000_00000000";

  begin

  U_TmemIf : entity work.Axis2TmemFifo
    generic map (
      DEVICE_G      => DEVICE_G,
      TMEM_CS_G     => TMEM_CS_G,
      AUX_INIT_G    => AUX_INIT_C,
      AUX_RO_M_G    => AUX_RO_M_F,
      VERSION_G     => VERSION_C
    )
    port map (
      clk           => clk,
      rst           => rst,

      axisInpPri    => axisTdoPri,
      axisInpSub    => axisTdoSub,

      axisOutPri    => axisTmsTdiPri,
      axisOutSub    => axisTmsTdiSub,

      tmemADD       => tmemADD,
      tmemDATW      => tmemDATW,
      tmemENA       => tmemENA,
      tmemWE        => tmemWE,
      tmemCS        => tmemCS,

      tmemDATR      => tmemDATR,
      tmemBUSY      => tmemBUSY,
      tmemPIPE      => tmemPIPE,

      auxIn         => auxOut,
      auxOut        => auxIn,

      irq           => irq
    );

   auxOut(68 downto  0) <= auxIn(68 downto 0);
   auxOut(71 downto 69) <= (others => '0');

   serDesInVal          <= auxIn(72);
   auxOut(72)           <= serDesInVal and not serDesInRdy;
   auxOut(73)           <= serDesInVal or (auxIn(73) and not serDesOutVal);
   auxOut(79 downto 74) <= (others => '0');
   tck_in_bitbang       <= auxIn(80);
   tms_in_bitbang       <= auxIn(81);
   tdi_in_bitbang       <= auxIn(82);
   auxOut(82 downto 80) <= auxIn(82 downto 80);
   auxOut(83)           <= tdo;

   auxOut(84)           <= tck;
   auxOut(85)           <= tms;
   auxOut(86)           <= tdi;
   auxOut(87)           <= bscn_tdo;
   auxOut(88)           <= bscn_sel;
   auxOut(89)           <= bscn_dck;
   auxOut(90)           <= bscn_upd;
   auxOut(91)           <= bscn_shf;
   auxOut(92)           <= bscn_rst;
   auxOut(93)           <= bscn_tdi;
   auxOut(94)           <= bscn_cap;

   bb_msk               <= auxIn(95);
   auxOut(95)           <= auxIn(95);

   G_SERDES : if ( not USE_AXIS_G ) generate

   P_tdoVal : process ( serDesOutVal, tdoVal, auxIn ) is
   begin
      if ( serDesOutVal = '1' ) then
        auxOut(127 downto 96) <= tdoVal;
      else 
        auxOut(127 downto 96) <= auxIn(127 downto 96);
      end if;
   end process P_tdoVal;

   numBits <= to_integer(unsigned(auxIn(68 downto 64)));

   U_JtagSerDes : entity work.JtagSerDesCore
    generic map (
      WIDTH_G       => (8*W_C),
      CLK_DIV2_G    => 5
    )
    port map (
      clk           => clk,
      rst           => rst,

      numBits       => numBits,
      dataInTms     => auxIn(31 downto  0),
      dataInTdi     => auxIn(63 downto 32),
      dataInValid   => serDesInVal,
      dataInReady   => serDesInRdy,

      dataOut       => tdoVal,
      dataOutValid  => serDesOutVal,
      dataOutReady  => '1',

      tck           => tck_in_serdes,
      tms           => tms_in_serdes,
      tdi           => tdi_in_serdes,
      tdo           => tdo
    );

   end generate G_SERDES;

   G_AXIS2JTAG : if ( USE_AXIS_G ) generate
   U_Jtag : entity work.AxisToJtag
    generic map (
       AXIS_WIDTH_G => W_C,
       AXIS_FREQ_G  => 125.0E6,
       CLK_DIV2_G   => 5,
       MEM_DEPTH_G  => NWORDS_C
    )
    port map (
      axisClk       => clk,
      axisRst       => rst,

      mAxisReq      => axisTmsTdiPri,
      sAxisReq      => axisTmsTdiSub,

      mAxisTdo      => axisTdoPri,
      sAxisTdo      => axisTdoSub,

      tck           => tck_in_serdes,
      tms           => tms_in_serdes,
      tdi           => tdi_in_serdes,
      tdo           => tdo
    );
  end generate G_AXIS2JTAG;

  tck_in <= (tck_in_serdes and not bb_msk) or  tck_in_bitbang;
  tms    <= (tms_in_serdes or      bb_msk) and tms_in_bitbang;
  tdi    <= (tdi_in_serdes and not bb_msk) or  tdi_in_bitbang;

  GEN_NO_TCK_BUF : if ( USE_BUFS_G < 1 ) generate
    tck <= tck_in;
  end generate GEN_NO_TCK_BUF;

  GEN_NO_DCK_UPD_BUFS : if ( USE_BUFS_G < 2 ) generate
    bscn_upd <= updt_loc;
    bscn_dck <= drck_loc;
  end generate GEN_NO_DCK_UPD_BUFS;

  GEN_TCK_BUF : if ( USE_BUFS_G >= 1 ) generate

    U_TCK_BUF  : BUFG
      port map (
        I => tck_in,
        O => tck
      );

  end generate GEN_TCK_BUF;

  GEN_DCK_UPD_BUFS : if ( USE_BUFS_G >= 2 ) generate
    signal drck_sel_b         : std_logic;
    signal updt_sel_b         : std_logic;
    signal tck_in_b           : std_logic;
  begin

    tck_in_b   <= not tck_in;
    drck_sel_b <= not drck_sel;
    updt_sel_b <= not updt_sel;
  
    U_DRCK_BUF : BUFGCTRL
      port map (
        IGNORE0        => '1',
        IGNORE1        => '1',
        I0             => bscn_sel,
        I1             => tck_in,
        CE0            => '1',
        CE1            => '1',
        S0             => drck_sel_b,
        S1             => drck_sel,
        O              => bscn_dck
      );
  
    U_UPDT_BUF : BUFGCTRL
      port map (
        IGNORE0        => '1',
        IGNORE1        => '1',
        I0             => '0',
        I1             => tck_in_b,
        CE0            => '1',
        CE1            => '1',
        S0             => updt_sel_b,
        S1             => updt_sel,
        O              => bscn_upd
      );

  end generate GEN_DCK_UPD_BUFS;

  U_Bscan1 : entity work.Jtag2Bscan
    generic map (
      IR_LENGTH_G   =>  10,
      REG_IDCODE_G  =>  "1111001001", -- must be of IR_LENGTH_G
      REG_USERCODE_G=>  "1111001000", -- must be of IR_LENGTH_G
      REG_USER_G    =>  "1111000010", -- must be of IR_LENGTH_G
      IR_VAL_G      =>  "1111010001", -- must be of IR_LENGTH_G
      IDCODE_VAL_G  =>  x"0424a093"
    )
    port map (
      JTCK          => tck,
      JTMS          => tms,
      JTDI          => tdi,
      JTDO          => tdo,
      
      TDO           => bscn_tdo,
      SEL           => bscn_sel,
      DRCK          => drck_loc,
      DRCK_SEL      => drck_sel,
      UPDATE        => updt_loc,
      UPDATE_SEL    => updt_sel,
      SHIFT         => bscn_shf,
      RESET         => bscn_rst,
      TDI           => bscn_tdi,
      CAPTURE       => bscn_cap
    );

  bscn_tdo          <= TDO_IN;
  SEL_OUT           <= bscn_sel;
  DRCK_OUT          <= bscn_dck;
  UPDATE_OUT        <= bscn_upd;
  SHIFT_OUT         <= bscn_shf;
  RESET_OUT         <= bscn_rst;
  TDI_OUT           <= bscn_tdi;
  CAPTURE_OUT       <= bscn_cap;

  JTCK_OUT <= tck;

  end block B_XvcJtagWrapper;

end architecture Impl;
