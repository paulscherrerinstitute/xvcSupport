class TestLogicReset:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self
    else:
      return self.ctx_.RunTestIdle

class RunTestIdle:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.SelectDRScan
    else:
      return self

class SelectDRScan:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.SelectIRScan
    else:
      return self.ctx_.CaptureDR

class CaptureDR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.captureDR()
    if ( tms ):
      return self.ctx_.Exit1DR
    else:
      return self.ctx_.ShiftDR

class ShiftDR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.shiftDR(tdi)
    if ( tms ):
      return self.ctx_.Exit1DR
    else:
      return self

class Exit1DR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.UpdateDR
    else:
      return self.ctx_.PauseDR

class PauseDR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.Exit2DR
    else:
      return self

class Exit2DR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.UpdateDR
    else:
      return self.ctx_.ShiftDR

class UpdateDR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.updateDR()
    if ( tms ):
      return self.ctx_.SelectDRScan
    else:
      return self.ctx_.RunTestIdle

class SelectIRScan:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.TestLogicReset
    else:
      return self.ctx_.CaptureIR

class CaptureIR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.captureIR()
    if ( tms ):
      return self.ctx_.Exit1IR
    else:
      return self.ctx_.ShiftIR

class ShiftIR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.shiftIR(tdi)
    if ( tms ):
      return self.ctx_.Exit1IR
    else:
      return self

class Exit1IR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.UpdateIR
    else:
      return self.ctx_.PauseIR

class PauseIR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.Exit2IR
    else:
      return self

class Exit2IR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    if ( tms ):
      return self.ctx_.UpdateIR
    else:
      return self.ctx_.ShiftIR

class UpdateIR:
  def __init__(self,ctx):
    self.ctx_=ctx

  def advance(self, tms, tdi):
    self.ctx_.updateIR()
    if ( tms ):
      return self.ctx_.SelectDRScan
    else:
      return self.ctx_.RunTestIdle


class JtagShiftReg:
  def __init__(self, LIM=0):
    self.reg_ = 0
    self.len_ = 0
    self.shr_ = 0
    self.shl_ = 0
    self.msk_ = 1
    self.lim_ = LIM

  def capture(self):
    self.shr_ = 0
    self.shl_ = 0
    self.msk_ = 1

  def shift(self, tdi):
    if ( tdi ):
      self.shr_ |= self.msk_
    self.shl_  += 1
    self.msk_ <<= 1

  def update(self):
    if (self.lim_ > 0 and self.shl_ != self.lim_ ):
      raise RuntimeError("Bad DATA? Register length mismatch")
    self.reg_ = self.shr_
    self.len_ = self.shl_

  def getLength(self):
    return self.len_

  def getData(self):
    return self.reg_

class JtagSniffer:

  def __init__(self, IR_USER=0x3c2, IR_LEN=10):
    self.TestLogicReset=TestLogicReset(self)
    self.RunTestIdle=RunTestIdle(self)
    self.SelectDRScan=SelectDRScan(self)
    self.CaptureDR=CaptureDR(self)
    self.ShiftDR=ShiftDR(self)
    self.Exit1DR=Exit1DR(self)
    self.PauseDR=PauseDR(self)
    self.Exit2DR=Exit2DR(self)
    self.UpdateDR=UpdateDR(self)
    self.SelectIRScan=SelectIRScan(self)
    self.CaptureIR=CaptureIR(self)
    self.ShiftIR=ShiftIR(self)
    self.Exit1IR=Exit1IR(self)
    self.PauseIR=PauseIR(self)
    self.Exit2IR=Exit2IR(self)
    self.UpdateIR=UpdateIR(self)

    self.IR_USR_ = IR_USER
    self.IR_ULN_ = IR_LEN
    self.state_  = self.TestLogicReset
    self.IR_     = ~IR_USER
    self.IR_SHR_ = 0
    self_IR_LEN_ = 0

    self.DR_     = 0
    self.DR_SHR_ = 0
    self.DR_LEN_ = 0

    self.DR      = JtagShiftReg()
    self.IR      = JtagShiftReg(LIM=IR_LEN)

  def advance(self, tms, tdi):
    self.state_ = self.state_.advance(tms, tdi)

  def isUSER(self):
    return self.IR.getData() == self.IR_USR_

  def captureIR(self):
    self.IR.capture()

  def captureDR(self):
    if (self.isUSER()):
      self.DR.capture()

  def shiftIR(self, tdi):
    self.IR.shift(tdi)

  def shiftDR(self, tdi):
    if (self.isUSER()):
      self.DR.shift(tdi)

  def updateIR(self):
    self.IR.update()
    #print("New IR: 0x{:x}".format(self.IR.getData()))

  def updateDR(self):
    if (self.isUSER()):
      self.DR.update()
      print("New DR[{}]: {:x}".format(self.DR.getLength(),self.DR.getData()))


  def processVecs(self, tms, tdi, nbits):
    for i in range(nbits):
      self.advance( not not (tms & 1), not not (tdi & 1) )
      tms >>= 1
      tdi >>= 1
