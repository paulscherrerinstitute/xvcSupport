#!/usr/bin/python3
import socket
import math

# XVC Client to drive JTAG on a remote TAP

class ConnectionClosedError(RuntimeError):
  def __init__(self, msg):
    super().__init__( msg )

# Create client providing a connected socket.
# You can use the XvcClientMgr to do that...
#
# Methods starting with an underscore are
# considered 'private'
class XvcClient:
  def __init__(self, sock):
    self.sock_ = sock
    self.maxv_ = None
    self.maxv_ = self.getMaxVectorBits()
    self.iLen_ = None
    self.iLen_ = self.getIRLength()

  def _send(self, buf):
    l = len(buf)
    p = 0
    while l > 0:
      g = self.sock_.send(buf[p:])
      p += g;
      l -= g;

  def _recv(self, minl, maxl=0):
    if 0 == maxl:
      maxl = minl
    l = 0
    b = bytearray()
    while l < minl:
      g = self.sock_.recv(maxl - l)
      if 0 == len(g):
        raise ConnectionClosedError("Connection is dead")
      l += len(g)
      b += g
    return b

  # Get the server info string
  def getinfo(self):
    self._send( bytearray('getinfo:', encoding='ascii') )
    return self._recv(10,100).decode('ascii')

  # Get max. bit-vector length supported
  # by the server
  def getMaxVectorBits(self):
    if not self.maxv_ is None:
      return self.maxv_
    info = self.getinfo()
    info = info.split(':')
    return int(info[1])

  # Send raw vectors -- low-level routine
  def sendVecs(self, tms, tdi, nbits):
    if nbits > self.maxv_:
      raise RuntimeError("Vectors larger than {} not supported".format(self.maxv_))
    nbytes = int( (nbits + 7 ) / 8 )
    tmsbuf = tms.to_bytes(nbytes, 'little')
    tdibuf = tdi.to_bytes(nbytes, 'little')
    nbuf   = nbits.to_bytes(4, 'little')
    obuf   = bytearray('shift:','ascii') + nbuf + tmsbuf + tdibuf
    self._send(obuf)
    ibuf   = self._recv(nbytes, nbytes)
    return int.from_bytes(ibuf, 'little', signed=False)

  # Bring into TestLogicReset, then TestRunIdle
  def resetToIdle(self):
    l = 6
    self.sendVecs(0b011111,0,l)

  # Select for IR scan
  # ASSUMPTION: TAP is in TestRunIdle state when you call this
  def selIR(self):
    self.sendVecs(0b0011,0,4)

  # Select for DR scan
  # ASSUMPTION: TAP is in TestRunIdle state when you call this
  def selDR(self):
    self.sendVecs(0b001,0,3)

  # Shift DR or IR; if 'update' is
  # - False:
  #     Tap is left in shiftDR/shiftIR state when 
  #     'shift' returns (useful for inspecting tdo and further
  #     shifting).
  # - True:
  #     DR/IR is updated after shifting and the TAP
  #     is driven into TestRunIdle state
  # ASSUMPTION: TAP is in shiftDR or shirtIR state when you call this
  def shift(self, regin, reglen, update=True):
    tms    = 0
    tdolen = reglen
    if update:
      tms    |= 3<<(reglen - 1)
      reglen += 2  # prepended 0b01
    tdo = self.sendVecs(tms, regin, reglen)
    if update:
      tdo &= (1<<tdolen) - 1
    return tdo

  # get the IDCODE
  # NOTES:
  #  - Goes through a TestLogicReset cycle
  #  - Leaves Tap in TestRunIdle state
  def getID(self):
    self.resetToIdle()
    self.selDR()
    myId = self.shift(0, 32, False)
    self.shift(myId, 32, True)
    return myId

  # probe IR length
  # NOTES:
  #  - Goes through a TestLogicReset cycle
  #  - Leaves Tap in TestRunIdle state
  def getIRLength(self):
    self.resetToIdle()
    if not self.iLen_ is None:
      return self.iLen_
    lmax = 1024
    ones = (1<<lmax) - 1
    self.selIR()
    self.shift( ones, lmax, False )
    tdo  = self.shift( 0, lmax, True )
    rval = int( math.log2( tdo + 1 ) )
    return rval

# Context manager for XVC client socket
#
# mgr = XvcClientMgr()
#
# with mgr as clnt:
#   clnt.resetToIdle()
#   print("ID is 0x{:x}".format( clnt.getID() ) )
#   # perform other work...
#
class XvcClientMgr:
  def __init__(self, host='localhost', port=2542):
    self.peer_ = (socket.gethostbyname(host), port)
    self.sock_ = None

  def __enter__(self):
    self.sock_ = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    self.sock_.connect( self.peer_ )
    return XvcClient( self.sock_ )

  def __exit__(self, typ, val, traceback):
    self.sock_.shutdown( socket.SHUT_RDWR )
    self.sock_.close()
    self.sock_ = None


with XvcClientMgr() as c:
  print("ID is 0x{:x}".format( c.getID() ))

