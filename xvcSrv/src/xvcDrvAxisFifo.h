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

#ifndef JTAG_DRIVER_ZYNQ_FIFO_H
#define JTAG_DRIVER_ZYNQ_FIFO_H

#include <xvcDriver.h>
#include <mmioHelper.h>

class JtagDriverZynqFifo : public JtagDriverAxisToJtag {
private:
	static const int TX_STA_IDX =  0;
	static const int TX_IEN_IDX =  1;
	static const int TX_RST_IDX =  2;
	static const uint32_t RST_MAGIC = 0xa5;
	static const int TX_OCC_IDX =  3;
	static const int TX_DAT_IDX =  4;
	static const int TX_END_IDX =  5;
	static const int TX_SIZ_IDX =  6;
	static const int RX_STA_IDX =  8;
	static const int RX_IEN_IDX =  9;
	static const int RX_RST_IDX = 10;
	static const int RX_OCC_IDX = 11;
	static const int RX_DAT_IDX = 12;
	static const int RX_CNT_IDX = 13;
	static const int RX_SIZ_IDX = 14;

	static const int RX_RDY_SHF =  5;
	static const int RX_RST_SHF =  0;
	static const int TX_RST_SHF =  0;

	MemMap<uint32_t>  map_;

	unsigned long     maxVec_;
    unsigned          wrdSiz_;
    bool              useIrq_;

public:

	// I/O
	virtual void     o32(unsigned idx, uint32_t v);
	virtual uint32_t i32(unsigned idx);

	virtual void reset();

	virtual uint32_t wait();

	JtagDriverZynqFifo(int argc, char *const argv[], const char *devnam);

	virtual void
	init();

	virtual unsigned long
	getMaxVectorSize();

	virtual int
	xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual ~JtagDriverZynqFifo();

	static void usage();
};

extern "C" JtagDriver *drvCreate(const char *target);

#endif
