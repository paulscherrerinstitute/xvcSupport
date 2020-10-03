#!/usr/bin/python3
import re
import sys
import JtagSniffer

if ( len(sys.argv) < 2 ):
  print("Need filename arg")
  sys.exit(1)

f=sys.argv[1]

patt=re.compile('^BSCN')

msk_tck_o    = (1<<16)
msk_tms_o    = (1<<17)
msk_tdi_o    = (1<<18)
msk_tdo_i    = (1<<19)
msk_tck_rb   = (1<<20)
msk_tms_rb   = (1<<21)
msk_tdi_rb   = (1<<22)
msk_bscn_tdo = (1<<23)
msk_bscn_sel = (1<<24)
msk_bscn_dck = (1<<25)
msk_bscn_upd = (1<<26)
msk_bscn_shf = (1<<27)
msk_bscn_rst = (1<<28)
msk_bscn_tdi = (1<<29)
msk_bscn_cap = (1<<30)

def pval(v, endmark='\n'):
  print("SE({:d}) CK({:d}) CA({:d}) DI({:d}) DO({:d}) BO({:d}) SH({:d}) UP({:d}) DK({:d}) TI({:d})".format(
    not not (v & msk_bscn_sel),
    not not (v & msk_tck_rb  ),
    not not (v & msk_bscn_cap),
    not not (v & msk_bscn_tdi),
    not not (v & msk_tdo_i   ),
    not not (v & msk_bscn_tdo),
    not not (v & msk_bscn_shf),
    not not (v & msk_bscn_upd),
    not not (v & msk_bscn_dck),
    not not (v & msk_tdi_o   )
    ), end=endmark)

def process_file(f, cb, cl):
  lno = 1
  for l in open(f):
    l = l.rstrip('\n')
    if ( None != patt.match(l) ):
      v = int(l.split()[1],0)
      cb(v, lno, l, cl)
    lno += 1

def check_tck_tms_tdi_readback(val, lineNo, line, closure):
  if ( ((val >> 16) & 0x7) != ((val>>20) & 0x7) ):
        pval( val )
        raise RuntimeError("TMS/TDI/TCK Readback Mismatch: line #{} {}".format(lineNo, line))
  if ( (not not (val & msk_bscn_tdi)) != (not not (val & msk_tdi_o)) ):
        pval( val )
        raise RuntimeError("BSCN_TDI readback mismatch: line #{} {}".format(lineNo, line))
  if ( (lineNo > 1) and ((closure[0] & msk_tck_rb) == (val & msk_tck_rb)) ):
        raise RuntimeError("TCK does not toggle (line #{})".format(lineNo))
  closure[0] = val

def filter_sel(val, lineNo, line, closure):
  if ( (val & msk_bscn_sel) != 0 ):
    # print preceding non-SEL value
    if (closure[0] == 0):
      pval(closure[1])
    pval(val)
    closure[0]=1
  else:
    if (closure[0]!=0):
      pval(val)
    closure[0]=0
    closure[1]=val

def filter_upd_and_sel(val, lineNo, line, closure):
  if ( (val & (msk_bscn_sel | msk_bscn_upd)) == (msk_bscn_sel | msk_bscn_upd) ):
    print(line)

def print_all(val, lineNo, line, closure):
  pval(val)

def sig_posedge(prev, val, msk = msk_tck_rb):
  return ( ((prev & msk) == 0) and ((val & msk) != 0) )

def filter_bscan_irregular_tdo_change(val, lineNo, line, closure):
  prev       = closure[0]
  closure[0] = val
  if ((prev & msk_bscn_tdo) != (val & msk_bscn_tdo)):
    if ( ((prev & msk_tck_rb) != 0) or ((val & msk_tck_rb) == 0) ):
      msg = "Irregular TDO #line {}".format(lineNo)
      pval(prev)
      pval(val)
      if (lineNo > 1):
        raise RuntimeError(msg)
      print("Warning: {}".format(msg))

def filter_upd_shf_cap_overlap(val, lineNo, line, closure):
  bits = 0
  if ( (val & msk_bscn_cap) != 0):
    bits += 1
  if ( (val & msk_bscn_shf) != 0):
    bits += 1
  if ( (val & msk_bscn_upd) != 0):
    bits += 1
  if ( bits > 1 ):
    msg = "CAP/SHF/UPD overlap detected @#{}".format(lineNo)
    pval( val )
    raise RuntimeError(msg)

process_file(f, check_tck_tms_tdi_readback, [0,0])
process_file(f, filter_bscan_irregular_tdo_change, [0,0])
process_file(f, filter_upd_shf_cap_overlap, [0,0])
print("Elementary Checks PASSES")

def track_user_data_from_jtag(val, lineNo, line, closure):
  scanner = closure[1]
  pval    = closure[0]
  if ( sig_posedge(pval, val, msk_tck_o) ):
    scanner.advance( not not (val & msk_tms_o), not not (val & msk_tdi_o) )
  closure[0] = val

def track_user_data_from_bscn(val, lineNo, line, closure):
  shr  = closure[1]
  pval = closure[0]
  closure[0] = val
  if ( sig_posedge( pval, val, msk_bscn_dck) ):
    if ( (val & msk_bscn_cap) != 0 ):
      print("CAP")
      shr.capture()
    if ( (val & msk_bscn_shf) != 0 ):
      shr.shift( not not (val & msk_bscn_tdi) )
    if ( (val & msk_bscn_upd) != 0 ):
      print("New DR [{}]: {:x}".format(shr.getLength(), shr.getData()))

class VhdlPkgConverter:
  def __init__(self):
    self.lim_ = 32
    self.vec_ = []
    self.clear()

  def clear(self):
    self.len_ = 0
    self.msk_ = 1
    self.tms_ = 0
    self.tdi_ = 0
    self.tdo_ = 0

  def push(self):
    if ( self.len_ > 0 ):
      self.vec_.append( {"TMS": self.tms_, "TDI": self.tdi_, "TDO": self.tdo_, "LEN": self.len_} )
      self.clear()

  def dump(self, feil=None):
    self.push()
    print("package body Jtag2BSCANTbPkg is", file=feil)
    print("  constant iSeq : TmsTdiArray := (", file=feil)
    w = int((self.lim_ + 3)/4)
    for r in self.vec_:
      print("( TMS => x\"{:0{}x}\", TDI => x\"{:0{}x}\", nbits => {:d} ),".format(r["TMS"], w, r["TDI"], w, r["LEN"]), file=feil)
    # sentinel
    print("( TMS => x\"{:0{}x}\", TDI => x\"{:0{}x}\", nbits => {:d} )".format(0,w,0,w,0), file=feil)
    print(");", file=feil)
    print("  constant oSeq : TdoArray := (", file=feil)
    for r in self.vec_:
      print("( TDO => x\"{:0{}x}\", nbits => {:d} ),".format(r["TDO"], w, r["LEN"]), file=feil)
    # sentinel
    print("( TDO => x\"{:0{}x}\", nbits => {:d} )".format(0, w, 0), file=feil)
    print(");", file=feil)
    print("end package body Jtag2BSCANTbPkg;", file=feil)

  def append(self, tms, tdi, tdo):
    if ( tms ):
      self.tms_ |= self.msk_
    if ( tdi ):
      self.tdi_ |= self.msk_
    if ( tdo ):
      self.tdo_ |= self.msk_
    self.msk_ <<= 1
    self.len_  += 1
    if (self.len_ >= self.lim_):
      self.push()

def filter_vhdl_pkg(val, lineNo, line, closure):
  cvt = closure[1]
  cvt.append( not not (val & msk_tms_o), not not (val & msk_tdi_o), not not (val & msk_tdo_i) )

def gen_vhdl_pkg(fnam = "Jtag2BSCANTbPkgBody.vhd"):
  feil = open(fnam, "w")
  
  cvt = VhdlPkgConverter()
  process_file(f, filter_vhdl_pkg, [0, cvt])
  cvt.dump( feil )
  feil.close()

#process_file(f, track_user_data_from_jtag, [0,JtagSniffer.JtagSniffer()])
#process_file(f, track_user_data_from_bscn, [0,JtagSniffer.JtagShiftReg()])
#process_file(f, filter_sel, [0,0])
#process_file(f, print_all, None)
gen_vhdl_pkg()
