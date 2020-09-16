library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

use work.ifc1210_simu_procedures_pkg.all;

entity Axis2TmemLoopbackTb is
end entity Axis2TmemLoopbackTb;

architecture tb of Axis2TmemLoopbackTb is

  signal clk : sl      := '0';
  signal rst : sl      := '1';
  signal run : boolean := true;
  signal cnt : integer := 0;

  constant DEPTH_C     : slv := x"2";

  signal axisPri       : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
  signal axisSub       : AxiStreamSlaveType;

  signal tmemBusI  : tmem_bus_in_t := (
    TMEM_ADD_i  => (others => 'X'),
    TMEM_DATW_i => (others => 'X'),
    TMEM_ENA_i  => '0',
    TMEM_WE_i   => (others => '0'),
    TMEM_CS_i   => "00"
  );
  signal tmemBusO  : tmem_bus_out_t;

  signal tmemData  : slv(63 downto 0);

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


  signal   rbidx : natural;

  signal   irq   : std_logic;

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

  -- enable interrupts

    TMEM_BUS_WRITE( "enable output IRQ",
        x"00_0008",
        x"0F",
        x"0000_0000_0004_0000",
        1,
        clk,
        tmemBusI,
        tmemBusO);

    while ( not irq ) loop
      wait until rising_edge( clk );
    end loop;

    for i in axisTstData'range loop
      TMEM_BUS_WRITE( "writing test  values",
        x"00_0000",
        x"0F",
        x"0000_0000" & axisTstData(i),
        1,
        clk,
        tmemBusI,
        tmemBusO);
    end loop;

    -- write EOF and enable input IRQ

    TMEM_BUS_WRITE( "writing EOF",
      x"00_0008",
      x"0F",
      x"00000000_00090000",
      1,
      clk,
      tmemBusI,
      tmemBusO);

    while ( not irq ) loop
      wait until rising_edge( clk );
    end loop;

    TMEM_BUS_READ( "Status readback",
                   x"00_0008",
                   1,
                   clk,
                   tmemData,
                   tmemBusI,
                   tmemBusO );
    wait until rising_edge( clk );

    nvals := to_integer( unsigned( tmemData(15 downto 0) ) );

    if ( tmemData(31 downto 0) /= x"0" & DEPTH_C & x"08" & slv(to_unsigned(axisTstData'length, 16)) ) then
      report "Reading status mismatch" severity failure;
    end if;


    wait until rising_edge( clk );

    for i in 1 to nvals loop
      TMEM_BUS_READ( "reading data",
        x"00_0000",
        1,
        clk,
        tmemData,
        tmemBusI,
        tmemBusO);
      wait until rising_edge( clk );
      if ( tmemData( axisTstData(0)'range ) /= axisTstData(i - 1) ) then
         report "readback data mismatch" severity failure;
      end if;
    end loop;

    if ( irq = '1' ) then
      report "IRQ still asserted!" severity failure;
    end if;

    report "TEST PASSED";
 
    run <= false;
    wait;
  end process P_TEST;

  U_DUT : entity work.Axis2TmemFifo
    port map (
      clk             => clk,
      rst             => rst,

      axisInpPri      => axisPri,
      axisInpSub      => axisSub,
      axisOutPri      => axisPri,
      axisOutSub      => axisSub,

      tmemADD         => tmemBusI.TMEM_ADD_i,
      tmemDATW        => tmemBusI.TMEM_DATW_i,
      tmemENA         => tmemBusI.TMEM_ENA_i,
      tmemWE          => tmemBusI.TMEM_WE_i,
      tmemCS          => tmemBusI.TMEM_CS_i,

      tmemDATR        => tmemBusO.TMEM_DATR_o,
      tmemBUSY        => tmemBusO.TMEM_BUSY_o,
      tmemPIPE        => tmemBusO.TMEM_PIPE_o,

      irq             => irq
    );

end architecture tb;
