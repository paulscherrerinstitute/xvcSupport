library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.TextUtilPkg.all;

use work.Jtag2BSCANTbPkg.all;

use work.ifc1210_simu_procedures_pkg.all;

entity Tmem2BSCANWrapperTb is
end entity Tmem2BSCANWrapperTb;

architecture tb of Tmem2BSCANWrapperTb is

  constant DEPTH_C     : slv := x"2";

  constant IR_RB_VAL_C : slv(9 downto 0) := "1111010001";

  function min(a,b : natural) return natural is
  begin
    if ( a < b ) then return a; else return b; end if;
  end function min;

  constant SEQ_LEN_C   : natural :=  4; -- min( iSeq'length, oSeq'length );

  signal clk : sl      := '0';
  signal rst : sl      := '1';
  signal run : boolean := true;
  signal cnt : integer := 0;

  signal idx      : integer;
  signal tdocmp   : std_logic_vector(31 downto 0);
  signal sidx     : natural := 0;
  signal sbit     : natural := 0;
  signal TDO      : std_logic;
  signal jtck     : std_logic;

  signal ovecErr  : sl      := '0';
  signal ovecErrs : natural := 0;

  signal tmemBusI  : tmem_bus_in_t := (
    TMEM_ADD_i  => (others => 'X'),
    TMEM_DATW_i => (others => 'X'),
    TMEM_ENA_i  => '0',
    TMEM_WE_i   => (others => '0'),
    TMEM_CS_i   => "00"
  );
  signal tmemBusO  : tmem_bus_out_t;

  signal tmemData  : slv(63 downto 0);

  constant tstData : Slv32Array := (
-- TMS 01 1000 0000 0000 1101 1111
-- TDI 00 1111 0010 0100 0000 0000
    0 => x"001800df",
    1 => x"000f2400",
    2 => x"00000115"
  );

  constant altData : Slv32Array := (
    0 => x"ffffffff",
    1 => x"ffffffff",
    2 => x"affecafe"
  );


  signal   rbidx : natural;

  signal   irq   : std_logic;

  signal   dxbg   : std_logic := '0';

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

  TDO <= 'X' when sidx >= SEQ_LEN_C else oSeq( sidx ).tdo( sbit );

  P_FEED : process ( jtck ) is
  begin
    if ( rising_edge( jtck ) and (dxbg = '1') ) then
      if ( sbit = oSeq(sidx).nbits - 1 ) then
        sbit <= 0;
        sidx <= sidx + 1;
      else
        sbit <= sbit + 1;
      end if;
    end if;
  end process P_FEED;

  P_TEST : process is
    variable nvals : natural;

    procedure xact(tms, tdi: std_logic_vector(31 downto 0); numBits : natural; signal rbd : inout std_logic_vector(63 downto 0)) is
      variable csr : std_logic_vector(63 downto 0);
    begin

    rbd <= x"00000000_00000200";

    TMEM_BUS_WRITE( "writing test  values",
        x"00_0010",
        x"FF",
        tdi & tms,
        1,
        clk,
        tmemBusI,
        tmemBusO);

    csr := x"0000_0000" & x"0002_01" & "000" & std_logic_vector(to_unsigned(numBits - 1, 5));

    TMEM_BUS_WRITE( "writing test  values",
        x"00_0018",
        x"0F",
        csr,
        1,
        clk,
        tmemBusI,
        tmemBusO);

    while ( rbd(9) = '1' ) loop

    TMEM_BUS_READ( "Status readback",
                   x"00_0018",
                   1,
                   clk,
                   rbd,
                   tmemBusI,
                   tmemBusO );
    wait until rising_edge( clk );

    end loop;

    print("TDO " & str(tmemData(63 downto 64 - numBits )));

    end procedure xact;

  begin

    while ( rst = '1' ) loop
      wait until rising_edge( clk );
    end loop;

    wait for 1000 ns;

    xact( tms => tstData(0), tdi => tstData(1), numBits => to_integer(unsigned(tstData(2)(4 downto 0)) + 1), rbd => tmemData );

    if ( tmemData(61 downto 52) /= IR_RB_VAL_C ) then
      report "IR content mismatch; got " & str(tmemData(61 downto 52)) severity failure;
    end if;

    xact( tms => x"0000_0001", tdi => x"0000_0000", numBits =>  3, rbd => tmemData );
    xact( tms => x"8000_0000", tdi => x"0000_0000", numBits => 32, rbd => tmemData );
    
    if ( tmemData(63 downto 32) /= x"0424a093" ) then
      report "ID mismatch" severity failure;
    end if;
    -- back to idle
    xact( tms => x"8000_0001", tdi => x"0000_0000", numBits =>  2, rbd => tmemData );

    dxbg <= '1';

    for i in 0 to SEQ_LEN_C - 1 loop
      idx    <= i;
      tdocmp <= oSeq(i).tdo;
      xact( tms => iSeq(i).tms, tdi => iSeq(i).tdi, numBits => iSeq(i).nbits, rbd => tmemData );
      if ( tmemData(63 downto 64 - oSeq(i).nbits) /= oSeq(i).tdo(oSeq(i).nbits - 1 downto 0) ) then
        ovecErr  <= '1';
        ovecErrs <= ovecErrs + 1;
        wait until rising_edge( clk );
        ovecErr <= '0';
      end if;
    end loop;

    xact( tms => x"0000_00ff", tdi => x"0000_0000", numBits =>  8, rbd => tmemData );

    report "TDO vector mismatches: " & natural'image(ovecErrs);

    report "TEST PASSED";
 
    run <= false;
    wait;
  end process P_TEST;

  U_DUT : entity work.Tmem2BSCANWrapper
    generic map (
      USE_AXIS_G      => false,
      USE_BUFS_G      => 0
    )
    port map (
      clk             => clk,
      rst             => rst,

      tmemADD         => tmemBusI.TMEM_ADD_i,
      tmemDATW        => tmemBusI.TMEM_DATW_i,
      tmemENA         => tmemBusI.TMEM_ENA_i,
      tmemWE          => tmemBusI.TMEM_WE_i,
      tmemCS          => tmemBusI.TMEM_CS_i,

      tmemDATR        => tmemBusO.TMEM_DATR_o,
      tmemBUSY        => tmemBusO.TMEM_BUSY_o,
      tmemPIPE        => tmemBusO.TMEM_PIPE_o,

      TDO_IN          => TDO,
      TDI_OUT         => open,
      RESET_OUT       => open,
      SHIFT_OUT       => open,
      UPDATE_OUT      => open,
      CAPTURE_OUT     => open,
      SEL_OUT         => open,
      DRCK_OUT        => open,

      JTCK_OUT        => jtck,

      irq             => open
    );

end architecture tb;
