library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

use work.ifc1210_simu_procedures_pkg.all;

entity Axis2TmemFifoTb is
end entity Axis2TmemFifoTb;

architecture tb of Axis2TmemFifoTb is

  signal clk : sl      := '0';
  signal rst : sl      := '1';
  signal run : boolean := true;
  signal cnt : integer := 0;

  constant CS_C : slv  := "10";

  function makeAddr(reg : in natural range 0 to 4095) return slv is
    variable rval : slv(23 downto 0);
  begin
    rval := "00" & CS_C & x"00" & slv(to_unsigned(reg, 12));
    return rval;
  end function makeAddr;

  constant PREFIX_C : slv := "00" & CS_C & x"00";

  signal axisInpPri : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
  signal axisInpSub : AxiStreamSlaveType;
  signal axisOutPri : AxiStreamMasterType;
  signal axisOutSub : AxiStreamSlaveType  := AXI_STREAM_SLAVE_INIT_C;

  signal tmemDATRDly: Slv64Array(2 downto 0) := (others => (others => '0'));

  constant DEPTH_C : slv := x"2";

  signal tmemBusI  : tmem_bus_in_t := (
    TMEM_ADD_i  => (others => 'X'),
    TMEM_DATW_i => (others => 'X'),
    TMEM_ENA_i  => '0',
    TMEM_WE_i   => (others => '0'),
    TMEM_CS_i   => CS_C
  );
  signal tmemBusO  : tmem_bus_out_t;

  signal tmemData  : slv(63 downto 0);

  signal axisCmp   : slv(31 downto 0);

  function AXI_STREAM_CONFIG_F return AxiStreamConfigType is
    variable v : AxiStreamConfigType;
  begin
    v := AXI_STREAM_CONFIG_INIT_C;
    v.TDATA_BYTES_C := 4;
    v.TDEST_BITS_C  := 0;
    v.TUSER_BITS_C  := 0;
    return v;
  end function AXI_STREAM_CONFIG_F;

  procedure axiStreamSendFrame(
    signal   clkk     : in  sl;
    signal   pri      : out AxiStreamMasterType;
    signal   sub      : in  AxiStreamSlaveType;
    constant data     : in  Slv32Array
  ) is
  begin
    for i in data'range loop
      wait until clkk = '1';
      pri                        <= AXI_STREAM_MASTER_INIT_C;
      pri.tData( data(i)'range ) <= data(i);
      pri.tValid                 <= '1';
      if i = data'right then
        pri.tLast <= '1';
      end if;
      while ( sub.tReady /= '1' ) loop
        wait until clkk = '1';
      end loop;
    end loop;
    wait until clkk = '1';
    pri.tValid <= '0';
  end procedure axiStreamSendFrame;

  constant axisTstData : Slv32Array := (
    0 => x"01020304",
    1 => x"abcdef01",
    2 => x"deadbeef"
  );

  constant axisAltData : Slv32Array := (
    0 => x"ffffffff",
    1 => x"ffffffff",
    2 => x"affecafe"
  );


  constant AXIS_CONFIG_C : AxiStreamConfigType := AXI_STREAM_CONFIG_F;

  signal   rbidx : natural;

begin

  P_CLK : process is
  begin
    if ( run ) then
      clk <= not clk;
      wait for 5 ns;
    else
      wait;
    end if;
  end process P_CLK;

  P_CNT : process ( clk ) is
  begin
    if ( rising_edge( clk ) ) then
      cnt <= cnt + 1;
      case ( cnt ) is
        when 10 => 
          rst <= '0';
        when others =>
      end case;
    end if;
  end process P_CNT;

  P_TEST : process is
    variable nvals : natural;
  begin

    while ( rst = '1' ) loop
      wait until rising_edge( clk );
    end loop;

    wait for 1000 ns;

    TMEM_BUS_READ( "Initial Read",
                   makeAddr(8),
                   1,
                   clk,
                   tmemData,
                   tmemBusI,
                   tmemBusO );
    wait until rising_edge( clk );
    nvals := to_integer(unsigned(tmemData(15 downto 0)));

    if ( nvals /= 0 ) then
      report "FIFO not empty initially" severity warning;
    end if;

    if ( tmemData(31 downto 16) /= x"0" & DEPTH_C & x"02" ) then
      report "FIFO initial flag settings unexpected" severity warning;
    end if;

    axiStreamSendFrame(
      clk,
      axisInpPri,
      axisInpSub,
      axisTstData
    );

	rbidx <= 0;

    while ( nvals = 0 ) loop

      TMEM_BUS_READ( "First Read",
                     makeAddr(8),
                     1,
                     clk,
                     tmemData,
                     tmemBusI,
                     tmemBusO );
      wait until rising_edge( clk );
      nvals := to_integer(unsigned(tmemData(15 downto 0)));
    end loop;

    if ( tmemData(31 downto 16) /= x"0" & DEPTH_C & x"00" ) then
      report "Unexpected flags after first FIFO read" severity failure;
    end if;

    for i in 1 to nvals loop
      TMEM_BUS_READ( "Read Loop",
                     makeAddr(0),
                     1,
                     clk,
                     tmemData,
                     tmemBusI,
                     tmemBusO );
      wait until rising_edge( clk );
      if ( tmemData(axisTstData(0)'range) /= axisTstData( rbidx ) ) then
        report "Test data mismatch (index " & integer'image(rbidx) & ")" severity failure;
      end if;
      rbidx <= rbidx + 1;
    end loop;

    wait until rising_edge( clk );

    if ( rbidx /= axisTstData'length ) then
        report "Test data length mismatch -- only " & integer'image(rbidx) & " items read!" severity failure;
    end if;

    TMEM_BUS_READ( "First Read",
                   makeAddr(8),
                   1,
                   clk,
                   tmemData,
                   tmemBusI,
                   tmemBusO );
    wait until rising_edge( clk );

    nvals := to_integer(unsigned(tmemData(15 downto 0)));

    if ( nvals /= 0 ) then
      report "Fifo not empty after reading" severity failure;
    end if;

    axiStreamSendFrame(
      clk,
      axisInpPri,
      axisInpSub,
      axisTstData
    );

    tmemData <= x"00000000_01010101";
    for i in 1 to 4 loop
      TMEM_BUS_WRITE( "writing dummy values",
        makeAddr(0),
        x"0F",
        tmemData,
        1,
        clk,
        tmemBusI,
        tmemBusO);

      tmemData <= slv( unsigned(tmemData) + to_unsigned(1, 64) );
    end loop;

    TMEM_BUS_WRITE( "writing EOF",
      makeAddr(8),
      x"04",
      x"00000000_00010000",
      1,
      clk,
      tmemBusI,
      tmemBusO);

    for i in 1 to 20 loop
      wait until rising_edge( clk );
    end loop;

    TMEM_BUS_READ( "Initial Read",
      makeAddr(8),
      1,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
	axisCmp <= x"ffff_0000";
    wait until rising_edge( clk );

      wait until rising_edge( clk );
    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"010003" ) then
      report "Re-filling fifos failed" severity failure;
    end if;

    axisOutSub.tReady <= '1';

    for i in 1 to 20 loop
      wait until rising_edge( clk );
    end loop;

    TMEM_BUS_READ( "Checking out fifo drain",
      makeAddr(8),
      1,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
    wait until rising_edge( clk );

    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"000003" ) then
      report "Draining out fifo failed" severity failure;
    end if;

    TMEM_BUS_WRITE( "writing reset",
      makeAddr(8),
      x"04",
      x"00000000_00800000",
      1,
      clk,
      tmemBusI,
      tmemBusO);

    -- wait for reset state machine
    for i in 1 to 10 loop
      wait until rising_edge( clk );
    end loop;

    TMEM_BUS_READ( "readback reset flag",
      makeAddr(8),
      1,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
    wait until rising_edge( clk );

    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"820000" ) then
      report "Resetting fifos failed" severity failure;
    end if;

    TMEM_BUS_WRITE( "clearing reset",
      makeAddr(8),
      x"04",
      x"00000000_00000000",
      1,
      clk,
      tmemBusI,
      tmemBusO);

    TMEM_BUS_READ( "clearing reset readback",
      makeAddr(8),
      1,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
    wait until rising_edge( clk );

    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"020000" ) then
wait for 1 ns;
      report "Readback after clearing fifos" severity failure;
    end if;

    tmemData          <= x"00000000_a0b0c0d0";
	axisOutSub.tReady <= '0';

    wait until rising_edge( clk );
    for i in 1 to 4 loop
      TMEM_BUS_WRITE( "writing new values",
        makeAddr(0),
        x"0F",
        tmemData,
        1,
        clk,
        tmemBusI,
        tmemBusO);

      tmemData <= slv( unsigned(tmemData) + to_unsigned(1, 64) );
    end loop;

    TMEM_BUS_WRITE( "writing EOF",
      makeAddr(8),
      x"04",
      x"00000000_00010000",
      1,
      clk,
      tmemBusI,
      tmemBusO);

    for i in 1 to 20 loop
      wait until rising_edge( clk );
    end loop;

    TMEM_BUS_READ( "checking EOF",
      makeAddr(8),
      1,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
    axisCmp <= x"f0f0f0f0";
    wait until rising_edge( clk );

    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"030000" ) then
      report "EOF readback mismatch" severity failure;
    end if;

    axisOutSub.tReady <= '1';
    axisCmp           <= x"a0b0c0d0";

    while ( (axisOutPri.tValid and axisOutSub.tReady) = '0' ) loop
      wait until rising_edge( clk );
    end loop;

    if ( axisOutPri.tData(31 downto 0) /= axisCmp ) then
      report "Stream readback data mismatch" severity failure;
    end if;

    TMEM_BUS_READ( "testing pipeline",
      makeAddr(0),
      8,
      clk,
      tmemData,
      tmemBusI,
      tmemBusO );
    wait until rising_edge( clk );


    report "TEST PASSED";

    run <= false;
    wait;
  end process P_TEST;

  U_DUT : entity work.Axis2TmemFifo
    generic map (
      TMEM_CS_G       => CS_C
    )
    port map (
      clk             => clk,
      rst             => rst,

      axisInpPri      => axisInpPri,
      axisInpSub      => axisInpSub,
      axisOutPri      => axisOutPri,
      axisOutSub      => axisOutSub,

      tmemADD         => tmemBusI.TMEM_ADD_i,
      tmemDATW        => tmemBusI.TMEM_DATW_i,
      tmemENA         => tmemBusI.TMEM_ENA_i,
      tmemWE          => tmemBusI.TMEM_WE_i,
      tmemCS          => tmemBusI.TMEM_CS_i,

      tmemDATR        => tmemBusO.TMEM_DATR_o,
      tmemBUSY        => tmemBusO.TMEM_BUSY_o,
      tmemPIPE        => tmemBusO.TMEM_PIPE_o
    );

  P_DLY : process ( clk ) is
  begin
    if ( rising_edge( clk ) ) then
      tmemDATRDly <= tmemDATRDly(tmemDATRDly'left - 1 downto 0) & tmemBusO.TMEM_DATR_o;
    end if;
  end process P_DLY;

end architecture tb;
