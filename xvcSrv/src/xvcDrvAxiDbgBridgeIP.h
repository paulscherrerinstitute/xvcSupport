//-----------------------------------------------------------------------------
// Company    : PSI
//-----------------------------------------------------------------------------
// Description: Driver for Vivado's AXI Debug Bridge IP
//-----------------------------------------------------------------------------

#ifndef JTAG_DRIVER_ZYNQ_AXI_DEBUG_BRIDGE_H
#define JTAG_DRIVER_ZYNQ_AXI_DEBUG_BRIDGE_H

#include <xvcDriver.h>
#include <mmioHelper.h>
#include <time.h>

class JtagDriverZynqAxiDbgBridgeIP : public JtagDriverAxisToJtag {

private:
	static const int LENGTH_IDX =  0;
	static const int TMSVEC_IDX =  1;
	static const int TDIVEC_IDX =  2;
	static const int TDOVEC_IDX =  3;
	static const int CSR_IDX    =  4;
	static const uint32_t CSR_RUN = 0x00000001;
	static const int MAP_SIZE   =  0x14;

	MemMap<uint32_t>  map_;

	unsigned long     maxVec_;
    unsigned          wrdSiz_;

	static const unsigned long MIN_SLEEP_NS = 20UL*1000UL*1000UL;
	struct timespec   pollTime_;
	bool              doSleep_;
	unsigned          measure_;
	unsigned long     maxPollDelayUs_;

public:

	// I/O
	virtual void     o32(unsigned idx, uint32_t v);
	virtual uint32_t i32(unsigned idx);

	virtual void reset();

	virtual void wait();

	JtagDriverZynqAxiDbgBridgeIP(int argc, char *const argv[], const char *devnam);
	virtual void
	init();

	virtual unsigned long
	getMaxVectorSize();

	virtual int
	xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual ~JtagDriverZynqAxiDbgBridgeIP();

	static void usage();
};

extern "C" JtagDriver *drvCreate(const char *target);

#endif
