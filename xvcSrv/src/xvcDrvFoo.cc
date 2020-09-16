//-----------------------------------------------------------------------------
// Title      : JTAG Support
//-----------------------------------------------------------------------------
// Company    : SLAC National Accelerator Laboratory
//-----------------------------------------------------------------------------
// Description: 
//-----------------------------------------------------------------------------
// This file is part of 'SLAC Firmware Standard Library'.
// It is subject to the license terms in the LICENSE.txt file found in the 
// top-level directory of this distribution and at: 
//    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
// No part of 'SLAC Firmware Standard Library', including this file, 
// may be copied, modified, propagated, or distributed except according to 
// the terms contained in the LICENSE.txt file.
//-----------------------------------------------------------------------------

#include <xvcDriver.h>

// Skeleton for xvcSrv communication driver

class JtagDriverFoo : public JtagDriverAxisToJtag {
public:
	JtagDriverFoo(int argc, char *const argv[], const char *devnam)
	: JtagDriverAxisToJtag(argc, argv)
	{
	}

	// This is the core method; send/receive a packet to the firmware
	// driver we support. Return then number of bytes transferred.
	virtual int
	xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
	{
		return 0;
	}

	// return max. TMS/TDI/TDO vector size (in bits) this driver can handle
	// (size of a single vector, e.g., TMS)
	virtual unsigned long getMaxVectorSize() { return 0; }

	virtual ~JtagDriverFoo() {}

	// print usage info
	static void usage() { printf("FOO driver\n"); }

	// override default if your drive does not need a '-t <target>' option
	// to identify a target. Avoids the main program from flagging an error.
	// static bool needTargetArg() { return false; }
};

// Register, so -D <name> can find this driver
static DriverRegistrar<JtagDriverFoo> r("foo");
