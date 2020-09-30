library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;

library unimacro;
use unimacro.vcomponents.all;

-- Generate and consume 32-bit AXI streams over a TMEM interface
-- via FIFOs. The FIFO is operated in store-and-forward fashion.
--   Producer:
--     1. write a series of words to register 'FIFO_RW_REG_C'.
--     2. to terminate the frame set the OwnerAXIS bit (1<<16) in
--        register 'FIFO_CS_REG_C'. This initiates transfer
--        of the frame. Once the AXI stream is consumed the OwnerAXIS
--        bit self-clears.
--   Consumer:
--     1. poll the frame size 'FIFO_CS_REG_C(15:0)'. Once it is
--        non-zero
--     2. read the corresponding number of words from
--        'FIFO_RW_REG_C'.
--   Other
--     FIFO_CS_REG(15:0) (RO) : # words to for TMEM interface available
--                              to read from incoming FIFO.
--     FIFO_CS_REG(16)   (SC) : outgoing fifo owned by AXIS; writeable
--                              to '1'; self-clears once the frame
--                              has been sent.
--     FIFO_CS_REG(17)   (RO) : incoming FIFO owned by AXIS (TMEM must
--                              not read data in this state).
--     FIFO_CS_REG(18)   (RW) : outgoing FIFO IRQ enable (IRQ asserted
--                              while enabled and outgoing FIFO owned
--                              by TMEM interface).
--     FIFO_CS_REG(19)   (RW) : incoming FIFO IRQ enable (IRQ asserted
--                              while enabled and incoming FIFO owned
--                              by TMEM interface).
--     FIFO_CS_REG(23)   (RW) : hold the block in RESET while asserted.
--     FIFO_CS_REG(27:24)(RO) : FIFO depth in kBytes.
--     FIFO_AU_REG(31: 0)(RW) : Aux RW reg
--     FIFO_AU_REG(63:32)(RO) : Aux RO reg

entity Axis2TmemFifo is
  generic (
    DEVICE_G    : string := "VIRTEX6";
    TMEM_CS_G   : std_logic_vector(  1 downto 0) := "00"; -- CS to which the block responds
    AUX_INIT_G  : std_logic_vector(127 downto 0) := (others => '0');
    AUX_RO_M_G  : std_logic_vector(127 downto 0) := (others => '0')
  );
  port (
    clk         : in  sl;
    rst         : in  sl;

    axisInpPri  : in  AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C; -- incoming stream
    axisInpSub  : out AxiStreamSlaveType;

    axisOutPri  : out AxiStreamMasterType; -- outgoing stream
    axisOutSub  : in  AxiStreamSlaveType := AXI_STREAM_SLAVE_FORCE_C;

    tmemADD     : in  slv(23 downto 3);
    tmemDATW    : in  slv(63 downto 0);
    tmemENA     : in  sl;
    tmemWE      : in  slv( 7 downto 0);
    tmemCS      : in  slv( 1 downto 0);

    tmemDATR    : out slv(63 downto 0);
    tmemBUSY    : out sl;
    tmemPIPE    : out slv( 1 downto 0);

    auxIn       : in  slv(127 downto 0) := AUX_INIT_G;
    auxOut      : out slv(127 downto 0);

    irq         : out sl
  );
end entity Axis2TmemFifo;

architecture Impl of Axis2TmemFifo is

  constant DATA_BYTES_C : natural := 4;
  constant DATA_WIDTH_C : natural := 8*DATA_BYTES_C;

  constant DEPTH_KB_C   : unsigned(3 downto 0) := to_unsigned(2, 4);

  constant FIFO_SIZE_C  : string  := "18Kb";
  -- simulation doesn't work with DO_REG_C -- no data is ever read out; output register's reset
  -- seems permanently asserted.
  constant DO_REG_C     : integer := 0;

  constant CNT_WIDTH_C  : natural :=   9; -- depends on fifo-size and data-width

  constant FIFO_RW_REG_C: natural := 0;
  constant FIFO_CS_REG_C: natural := 1;
  constant FIFO_A1_REG_C: natural := 2;
  constant FIFO_A2_REG_C: natural := 3;

  signal   fifoInpDI             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
  signal   fifoInpDO             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
  signal   fifoInpRDEN           : std_logic;
  signal   fifoInpWREN           : std_logic;
  signal   fifoInpFull           : std_logic;
  signal   fifoInpEmpty          : std_logic;
  signal   fifoInpRDENs          : std_logic := '0';
  signal   aRst                  : std_logic;
  signal   tReadyInp             : std_logic;
  signal   tmemRDEN              : std_logic;
  signal   tmemRDENOnce          : std_logic;
  signal   tmemDATRLoc           : std_logic_vector(63 downto 0);
  signal   wcntReg               : unsigned(15 downto 0) := (others => '0');
  signal   wcntCnt               : unsigned(15 downto 0) := (others => '0');
  signal   auxReg                : std_logic_vector(127 downto 0) := AUX_INIT_G;

  signal   fifoUsrRst            : std_logic := '0';
  signal   usrRstSeq             : unsigned(2 downto 0) := (others => '0');


  signal   fifoOutDI             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
  signal   fifoOutDO             : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
  signal   fifoOutRDEN           : std_logic;
  signal   fifoOutWREN           : std_logic;
  signal   fifoOutFull           : std_logic;
  signal   fifoOutEmpty          : std_logic;
  signal   fifoOutLast           : std_logic;
  signal   fifoOutValid          : std_logic;
  signal   fifoOutOwnerAXIS      : std_logic := '0';
  signal   fifoRegSel            : std_logic_vector( 3 downto 0);
  signal   fifoRegSelDly         : std_logic_vector( 3 downto 0);
  signal   statusReg             : std_logic_vector(23 downto 0);

  -- unused; ghdl demands connection of unconstrained vectors
  signal   rdcntInp              : std_logic_vector(CNT_WIDTH_C - 1 downto 0);
  signal   wrcntInp              : std_logic_vector(CNT_WIDTH_C - 1 downto 0);
  signal   rdcntOut              : std_logic_vector(CNT_WIDTH_C - 1 downto 0);
  signal   wrcntOut              : std_logic_vector(CNT_WIDTH_C - 1 downto 0);

  signal   rstInProg             : std_logic;

  signal   fifoInpOwnerAXIS      : std_logic;

  signal   fifoInpIrq            : std_logic;
  signal   fifoInpIrqEna         : std_logic := '0';
  signal   fifoOutIrq            : std_logic;
  signal   fifoOutIrqEna         : std_logic := '0';

  constant TPD_C                 : time := 100 ps; -- must match xilinx model sync datapath delay

begin

  -- Xilinx FIFO block has restrictions for RESET:
  --  - WEN/REN must be held low >= 4 cycles prior to
  --    asserting RESET and must remain low during RESET.
  --  - RESET must be asserted >= 3 cycles.
  --

  -- Mini state-machine to generate proper reset and masks
  -- for WEN/REN ('rstInProg').

  aRst              <= '1' when usrRstSeq >  4 else '0';
  rstInProg         <= '1' when usrRstSeq /= 0 else '0';

  P_RESET : process (clk) is
  begin
    if ( rising_edge( clk ) ) then
      if usrRstSeq /= 0 then
        usrRstSeq <= usrRstSeq + 1;
      else
        if ( (rst or fifoUsrRst) = '1' ) then
          usrRstSeq <= to_unsigned(1, usrRstSeq'length);
        end if;
      end if;
    end if;
  end process P_RESET;

  -- the 'wcntReg'(ister) holds then number of words remaining
  -- to read from the incoming FIFO.
  --  a) wcntReg is set once the tLast bit is received on the
  --     incoming stream. No more data is then accepted on the
  --     streaming interface.
  --  b) wcntReg is counted down while reading words from the
  --     TMEM interface. When the count reaches zero the frame
  --     is consumed and the FIFO again 'owned' by the streaming
  --     side.
  
  -- while the 'wcntReg' register is zero the AXIS interface
  -- 'owns' the incoming FIFO fifo.
  fifoInpOwnerAXIS  <= '1' when (wcntReg = 0) else '0';

  -- handshake for incoming stream

  tReadyInp         <= not fifoInpFull and fifoInpOwnerAXIS;
  fifoInpWREN       <= (axisInpPri.tValid and tReadyInp and not rstInProg) after TPD_C;
  fifoInpDI         <= axisInpPri.tData(DATA_WIDTH_C - 1 downto 0);

  U_FIFO_IN : FIFO_SYNC_MACRO
    generic map (
      DEVICE                      => DEVICE_G,
      ALMOST_FULL_OFFSET          => X"0080",
      ALMOST_EMPTY_OFFSET         => X"0080",
      DATA_WIDTH                  => DATA_WIDTH_C,
      FIFO_SIZE                   => FIFO_SIZE_C,
      DO_REG                      => DO_REG_C
    )
    port map (
      CLK                         => clk,
      RST                         => aRst,

      WREN                        => fifoInpWREN,
      DI                          => fifoInpDI,
      FULL                        => fifoInpFull,
      ALMOSTFULL                  => open,
      WRCOUNT                     => wrcntInp,
      WRERR                       => open,

      DO                          => fifoInpDO,
      RDEN                        => fifoInpRDEN,
      EMPTY                       => fifoInpEmpty,

      ALMOSTEMPTY                 => open,
      RDCOUNT                     => rdcntInp,
      RDERR                       => open
    );

  -- handshake for TMEM READ FIFO interface
  tmemRDEN <= '1' when fifoRegSel(0) = '1' and tmemWE = x"00" and fifoInpOwnerAXIS = '0' else '0';

  -- state machine
  P_SEQ : process ( clk ) is
    variable t, f: natural;
  begin
    if ( rising_edge( clk ) ) then
      if ( aRst = '1' ) then
        fifoInpRDENs     <= '0';
        wcntReg          <= (others => '0');
        wcntCnt          <= (others => '0');
        fifoOutOwnerAxis <= '0';
        fifoOutValid     <= '0';
        fifoInpIrqEna    <= '0';
        fifoOutIrqEna    <= '0';
        auxReg           <= AUX_INIT_G;
        fifoRegSelDly    <= (others => '0');
        statusReg        <= (others => '0');
      else
        -- delayed 'tmemRDEN' so we can generate a single RDEN pulse
        fifoInpRDENs <= tmemRDEN;

        if    ( fifoOutValid = '0' or (fifoOutValid = '1' and axisOutSub.tReady = '1' ) ) then
          fifoOutValid <= fifoOutRDEN;
          -- if valid and not tReady then remain ready
        end if;

		if    ( fifoInpRDEN = '1' and fifoInpWREN = '0' ) then
          wcntCnt <= wcntCnt - 1;
        elsif ( fifoInpRDEN = '0' and fifoInpWREN = '1' ) then
          wcntCnt <= wcntCnt + 1;
        end if;

        -- when TLAST is seen on the incoming stream then set 'wcntReg';
        -- otherwise count down while non-zero.
        if ( (fifoInpWREN and axisInpPri.tLast) = '1' ) then
          wcntReg                 <= wcntCnt + 1;
        elsif ( tmemRDENOnce = '1' ) then
          wcntReg                 <= wcntReg - 1;
        end if;

        -- TMEM write to fifoOutOwnerAXIS bit for outgoing stream
        if ( fifoRegSel(1) = '1' and tmemWE(2) = '1' ) then
          if ( '0' = fifoOutOwnerAXIS ) then
            fifoOutOwnerAXIS <= tmemDATW(16);
          end if;
        end if;

        -- TMEM write to MSB
        if ( fifoRegSel(1) = '1' and tmemWE(3) = '1' ) then
          fifoOutIrqEna <= tmemDATW(18);
          fifoInpIrqEna <= tmemDATW(19);
        end if;

        auxReg <= auxIn;

        if ( fifoRegSel(2) = '1' ) then 
          for i in tmemWE'right to tmemWE'left loop
            f := 8*i;
            t := f+7;
            if ( tmemWE(i) = '1' ) then
              auxReg(t downto f) <=    (tmemDATW(t -  0 downto f -  0) and not AUX_RO_M_G(t downto f))
                                    or (auxIn   (t      downto f     ) and     AUX_RO_M_G(t downto f));
            end if;
          end loop;
        end if;

        if ( fifoRegSel(3) = '1' ) then 
          for i in tmemWE'right to tmemWE'left loop
            f := 8*i + 64;
            t := f+7;
            if ( tmemWE(i) = '1' ) then
              auxReg(t downto f) <=    (tmemDATW(t - 64 downto f - 64) and not AUX_RO_M_G(t downto f))
                                    or (auxIn   (t      downto f     ) and     AUX_RO_M_G(t downto f));
            end if;
          end loop;
        end if;

        -- outgoing stream takes over frame ownership
        if ( (fifoOutValid and axisOutSub.tReady and fifoOutEmpty) = '1' ) then
          fifoOutOwnerAXIS <= '0';
        end if;

        fifoRegSelDly <= fifoRegSel;

        statusReg     <= (fifoUsrRst & "000" & fifoInpIrqEna & fifoOutIrqEna & fifoInpOwnerAXIS & fifoOutOwnerAXIS & slv( wcntReg ));

      end if;

      if ( rst = '1' ) then
        fifoUsrRst <= '0';
      else
        if ( fifoRegSel(1) = '1' and tmemWE(2) = '1' ) then
          fifoUsrRst <= tmemDATW(23);
        end if;
      end if;
    end if;
  end process P_SEQ;

  -- TMEM DATR readout mux

  -- Note: all readout paths must have the same pipeline delay (1); thus we register the statusReg
  P_DATR_MUX : process (fifoRegSelDly, fifoInpDO, statusReg) is
  begin
    tmemDATRLoc <= (others => '0');
    case ( fifoRegSelDly ) is
      when "0001"   => tmemDATRLoc                                    <= x"6666_aaaa"  & fifoInpDO;
      when "0010"   => tmemDATRLoc( 16 + wcntReg'length - 1 downto 0) <= (x"0" & slv(DEPTH_KB_C) &  statusReg );
      when "0100"   => tmemDATRLoc                                    <= auxReg( 63 downto  0);
      when "1000"   => tmemDATRLoc                                    <= auxReg(127 downto 64);
      when others  => tmemDATRLoc <= x"affecafe" & x"5555aaaa";
    end case;
  end process P_DATR_MUX;

  -- Address decoding
  P_tmemSEL : process( tmemCS, tmemENA, tmemADD ) is
  begin
    fifoRegSel <= (others => '0');
    if ( ( tmemCS = TMEM_CS_G ) and (tmemENA = '1') ) then
      case ( to_integer( unsigned( tmemADD(12 downto tmemAdd'right) ) ) ) is
        when FIFO_RW_REG_C => fifoRegSel(0) <= '1';
        when FIFO_CS_REG_C => fifoRegSel(1) <= '1';
        when FIFO_A1_REG_C => fifoRegSel(2) <= '1';
        when FIFO_A2_REG_C => fifoRegSel(3) <= '1';
        when others        =>
      end case;
    end if;
  end process P_tmemSEL;

  tmemRDENOnce <= not fifoInpRDENs and tmemRDEN;
  fifoInpRDEN  <= tmemRDENOnce and not fifoInpEmpty and not rstInProg;

  U_FIFO_OUT : FIFO_SYNC_MACRO
    generic map (
      DEVICE                      => DEVICE_G,
      ALMOST_FULL_OFFSET          => X"0080",
      ALMOST_EMPTY_OFFSET         => X"0001",
      DATA_WIDTH                  => DATA_WIDTH_C,
      FIFO_SIZE                   => FIFO_SIZE_C,
      DO_REG                      => DO_REG_C
    )
    port map (
      CLK                         => clk,
      RST                         => aRst,

      WREN                        => fifoOutWREN,
      DI                          => fifoOutDI,
      FULL                        => fifoOutFull,
      ALMOSTFULL                  => open,
      WRCOUNT                     => wrcntOut,
      WRERR                       => open,

      DO                          => fifoOutDO,
      RDEN                        => fifoOutRDEN,
      EMPTY                       => fifoOutEmpty,

      ALMOSTEMPTY                 => fifoOutLast,
      RDCOUNT                     => rdcntOut,
      RDERR                       => open
    );

  fifoOutWREN  <= ( fifoRegSel(0) and not fifoOutOwnerAXIS and not fifoOutFull and not rstInProg ) when tmemWE(3 downto 0) = x"f" else '0';

  fifoOutDI    <= tmemDATW( fifoOutDI'range );

  P_fifoOutREN : process (rstInProg, fifoOutOwnerAXIS, fifoOutValid, fifoOutEmpty, axisOutSub) is
    variable v : std_logic;
  begin
    v := fifoOutRDEN;
    if ( (rstInProg = '1') or (fifoOutOwnerAXIS = '0')) then
      v := '0';
    else
      if ( fifoOutValid = '0' ) then
        v := not fifoOutEmpty;
      else
        if ( axisOutSub.tReady = '1' ) then
          v := not fifoOutEmpty;
        else
          v := '0';
        end if;
      end if;
    end if;
    fifoOutRDEN <= v after TPD_C;
  end process P_fifoOutREN;

  -- assing output signals

  -- incoming stream
  axisInpSub.tReady <= tReadyInp after TPD_C;

  -- outgoing stream
  P_axisOut : process (fifoOutDO, fifoOutValid, fifoOutEmpty) is
    variable v : AxiStreamMasterType;
  begin
    v                                  := AXI_STREAM_MASTER_INIT_C;
    v.tKeep(DATA_BYTES_C - 1 downto 0) := (others => '1');
    v.tStrb(DATA_BYTES_C - 1 downto 0) := (others => '1');
    v.tData(DATA_WIDTH_C - 1 downto 0) := fifoOutDO;
    v.tValid                           := fifoOutValid;
    v.tLast                            := fifoOutEmpty;

    axisOutPri <= v after TPD_C;
  end process P_axisOut;


  -- TMEM interface

  tmemDATR   <= tmemDATRLoc;
  tmemBUSY   <= '0';
  tmemPIPE   <= "00";

  fifoInpIrq <= not fifoInpOwnerAXIS and fifoInpIrqEna;
  fifoOutIrq <= not fifoOutOwnerAXIS and fifoOutIrqEna;

  irq        <= fifoInpIrq or fifoOutIrq;

  auxOut     <= auxReg;

end architecture Impl;
