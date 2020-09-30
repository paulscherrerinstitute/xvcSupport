//-----------------------------------------------------------------------------
// Company    : PSI
//-----------------------------------------------------------------------------
// Description: Driver for raw register-mapped JtagSerDes (w/o fifo; for debugging)
//-----------------------------------------------------------------------------

#ifndef JTAG_DRIVER_SERDES_TMEM_H
#define JTAG_DRIVER_SERDES_TMEM_H

#include <xvcDriver.h>
#include <time.h>

class JtagDriverSerDesTmem : public JtagDriverAxisToJtag {

private:
    static const int FIFO_DAT_IDX   = 0;
    static const int FIFO_MAGIC_IDX = 1;
    static const int FIFO_CSR_IDX   = 2;
    static const int SDES_TMS_IDX   = 4;
    static const int SDES_TDI_IDX   = 5;
    static const int SDES_CSR_IDX   = 6;
    static const int SDES_TDO_IDX   = 7;

	static const uint32_t CSR_RUN       = 0x00000200;
    static const uint32_t CSR_LEN_SHIFT = 0;

	unsigned long     maxVec_;
    unsigned          wrdSiz_;

    unsigned          toscaSpace_;
    unsigned long     toscaBase_;

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

	JtagDriverSerDesTmem(int argc, char *const argv[], const char *devnam);
	virtual void
	init();

	virtual unsigned long
	getMaxVectorSize();

	virtual int
	xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual ~JtagDriverSerDesTmem();

	static void usage();
};

extern "C" JtagDriver *drvCreate(const char *target);

#endif
