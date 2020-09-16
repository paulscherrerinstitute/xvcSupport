library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

library unisim;
use unisim.vcomponents.all;

entity Tmem2BSCANWrapper is
  generic (
    DEVICE_G    : string := "VIRTEX6";
    TMEM_CS_G   : std_logic_vector(1 downto 0) := "00" -- CS to which the block responds
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

    irq         : out sl
  );
end entity Tmem2BSCANWrapper;

architecture Impl of Tmem2BSCANWrapper is

  constant W_C          : natural := 4;

  constant NWORDS_C     : natural := 2048 / W_C; -- 18kBit FIFO

begin

  -- use a block so we have a name we can attach constraints to
  B_XvcJtagWrapper : block is
    signal axisTmsTdiPri  : AxiStreamMasterType; -- incoming stream
    signal axisTmsTdiSub  : AxiStreamSlaveType;
    signal axisTdoPri     : AxiStreamMasterType; -- incoming stream
    signal axisTdoSub     : AxiStreamSlaveType;

    signal tck, tms, tdi, tdo : std_logic;
    signal tck_in             : std_logic;

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

    signal countr : unsigned(7 downto 0) := x"00";
    signal ila    : std_logic_vector(19 downto 0);

  begin

  U_TmemIf : entity work.Axis2TmemFifo
    generic map (
      DEVICE_G      => DEVICE_G,
      TMEM_CS_G     => TMEM_CS_G
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

      irq           => irq
    );

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

      tck           => tck_in,
      tms           => tms,
      tdi           => tdi,
      tdo           => tdo
    );

  U_TCK_BUF : BUFG port map( I => tck_in, O => tck );

  U_Bscan1 : entity work.Jtag2Bscan
    generic map (
      IR_LENGTH_G   =>  10,
      REG_IDCODE_G  =>  "1111001001", -- must be of IR_LENGTH_G
      REG_USERCODE_G=>  "1111001000", -- must be of IR_LENGTH_G
      REG_USER_G    =>  "1111000010", -- must be of IR_LENGTH_G
      IR_VAL_G      =>  "1111110001", -- must be of IR_LENGTH_G
      IDCODE_VAL_G  =>  x"0424a093"
    )
    port map (
      JTCK          => tck,
      JTMS          => tms,
      JTDI          => tdi,
      JTDO          => tdo,
      
      TDO           => bscn_tdo,
      SEL           => bscn_sel,
      DRCK          => bscn_dck,
      UPDATE        => bscn_upd,
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

  end block B_XvcJtagWrapper;

end architecture Impl;
