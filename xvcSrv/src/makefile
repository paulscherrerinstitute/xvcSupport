#-----------------------------------------------------------------------------
# Title      : JTAG Support
#-----------------------------------------------------------------------------
# File       : makefile
# Author     : Till Straumann <strauman@slac.stanford.edu>
# Company    : SLAC National Accelerator Laboratory
# Created    : 2017-12-05
# Last update: 2017-12-05
# Platform   :
# Standard   : VHDL'93/02
#-----------------------------------------------------------------------------
# Description:
#-----------------------------------------------------------------------------
# This file is part of 'SLAC Firmware Standard Library'.
# It is subject to the license terms in the LICENSE.txt file found in the
# top-level directory of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of 'SLAC Firmware Standard Library', including this file,
# may be copied, modified, propagated, or distributed except according to
# the terms contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

# If you want to cross-compile this program define
# the path to the cross-tools either here or on the
# command line
#
# CROSS=/path/to/arm-linux-
CROSS=
USR_CPPFLAGS=

CROSS=/opt/eldk-5.2/powerpc-e500v2/sysroots/i686-eldk-linux/usr/bin/ppce500v2-linux-gnuspe/powerpc-e500v2-
TOSCAINC=-I/afs/psi.ch/user/s/straumann_t/epics/modules/tosca/toscaApi/include/
TOSCALIB=-L/afs/psi.ch/user/s/straumann_t/epics/modules/tosca/toscaApi/ -Wl,-Bstatic -ltoscaApi -Wl,-Bdynamic
TMEM_DRIVER_BUILTIN=YES

#
# so that $(CROSS)$(CXX) points to a valid cross compiler
#
DRIVERS += drvAxilFifo.so drvAxiDbgBridgeIP.so

OBJS=xvcSrv.o xvcDrvLoopBack.o xvcConn.o xvcDrvUdp.o jtagDump.o

VERSION_INFO:='"$(shell git describe --always)"'

CPPFLAGS+=-DXVC_SRV_VERSION=$(VERSION_INFO)
CPPFLAGS+=$(USR_CPPFLAGS)


DRVOBJS =

ifneq ($(TOSCALIB),)
ifneq ($(TMEM_DRIVER_BUILTIN),YES)
DRIVERS += drvTmemFifo.so
else
CPPFLAGS+=-DDEFAULTDRVNAME='"tmem"'
DRVOBJS += xvcDrvAxisTmem.o
endif
endif

-include defs.local.mk

TARGETS=xvcSrv $(DRIVERS)

all: $(TARGETS)

$(OBJS): xvcDriver.h xvcSrv.h

xvcSrv: $(OBJS) $(DRVOBJS)
	$(CROSS)$(CXX) -o $@ $^ -ldl -Wl,--export-dynamic $(TOSCALIB) -lm -lpthread -lrt

$(OBJS) $(DRVOBJS): %.o: %.cc
	$(CROSS)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ $< -I. $(TOSCAINC) -O2 -c

drvAxilFifo.so: xvcDrvAxisFifo.cc xvcDriver.h xvcDrvAxisFifo.h
	$(CROSS)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -shared -fPIC -I. -O2 -o $@ $<

drvAxiDbgBridgeIP.so: xvcDrvAxiDbgBridgeIP.cc xvcDriver.h xvcDrvAxiDbgBridgeIP.h
	$(CROSS)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -shared -fPIC -I. -O2 -o $@ $<

drvTmemFifo.so: xvcDrvAxisTmem.cc xvcDrvAxisTmem.h xvcDriver.h
	$(CROSS)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -shared -fPIC -I. $(TOSCAINC) -O2 -o $@ $< $(TOSCALIB) -lrt


xvcDrvAxisTmem.o: xvcDrvAxisTmem.cc xvcDrvAxisTmem.h xvcDriver.h

clean:
	$(RM) xvcSrv $(DRIVERS) $(OBJS) $(DRVOBJS)

-include rules.local.mk
