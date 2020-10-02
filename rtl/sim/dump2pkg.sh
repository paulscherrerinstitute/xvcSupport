#!/bin/bash

# Convert a log obtained from xvcSrv -vv to a VHDL
# package body (declaration in
#   Jtag2Bscan/tb/Jtag2BSCANTbPkg.vhd
# ) for simulations.
if [ $# -lt 1 ] ; then
  echo "Need input file name arg"
  exit 1
fi
ofnam="Jtag2BSCANTbPkgBody.vhd"
rm -i "$ofnam"
echo 'package body Jtag2BSCANTbPkg is'          >> "$ofnam"
echo '  constant iSeq : TmsTdiArray := ('       >> "$ofnam"
grep TMS $1                                     >> "$ofnam"
# append a sentinel (avoid having to eliminate trailing ',')
# --> simulation code must skip last element.
echo '( TMS => x"0000001f", TDI => x"00000000", nbits => 5 )'       >> "$ofnam"
echo '  );'                                     >> "$ofnam"
echo '  constant oSeq : TdoArray := ('          >> "$ofnam"
grep TDO $1                                     >> "$ofnam"
# append a sentinel (avoid having to eliminate trailing ',')
# --> simulation code must skip last element.
echo '( TDO => x"00000000", nbits => 5 )'       >> "$ofnam"
echo '  );'                                     >> "$ofnam"
echo 'end package body Jtag2BSCANTbPkg;'        >> "$ofnam"
