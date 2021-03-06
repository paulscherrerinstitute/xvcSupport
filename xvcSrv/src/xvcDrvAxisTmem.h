//-----------------------------------------------------------------------------
// Title      : JTAG Support
//-----------------------------------------------------------------------------
// File       : xvcDrvAxisFifo.h
// Author     : Till Straumann <strauman@slac.stanford.edu>
// Company    : SLAC National Accelerator Laboratory
// Created    : 2017-12-05
// Last update: 2017-12-05
// Platform   : 
// Standard   : VHDL'93/02
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

#ifndef JTAG_DRIVER_TMEM_FIFO_H
#define JTAG_DRIVER_TMEM_FIFO_H

#include <xvcDriver.h>
#include <stdint.h>

class JtagDriverTmemFifo : public JtagDriverAxisToJtag {
private:
	static const int      FIFO_DAT_IDX   =  0;
	static const int      FIFO_MAGIC_IDX =  1; // reading this will ALSO read the FIFO
                                                   // (use only during detection)!
	static const int      FIFO_CSR_IDX   =  2;
	static const uint32_t FIFO_CSR_RST   =  (1<<23);
	static const uint32_t FIFO_CSR_EOFO  =  (1<<16);
	static const uint32_t FIFO_CSR_EMPI  =  (1<<17);
	static const uint32_t FIFO_CSR_IENO  =  (1<<18);
	static const uint32_t FIFO_CSR_IENI  =  (1<<19);
	static const uint32_t FIFO_CSR_NWRDS =  0;
	static const uint32_t FIFO_CSR_NWRDM =  0xffff;
	static const uint32_t FIFO_CSR_MAXWS =  24;
	static const uint32_t FIFO_CSR_MAXWM =  0x0f000000;
	static const uint32_t FIFO_CSR_VERSM =  0xf0000000;
	static const uint32_t FIFO_CSR_VERSS =  28;

	static const uint32_t VERSION_0      = 0;
	static const uint32_t VERSION_1      = 1;
	static const uint32_t MAGIC          = 0x6666aaaa;

	static const int      SDES_TMS_IDX   = 4;
	static const int      SDES_TDI_IDX   = 5;
	static const int      SDES_CSR_IDX   = 6;
	static const int      SDES_TDO_IDX   = 7;

	static const uint32_t SDES_CSR_RUN    = 0x00000100;
	static const uint32_t SDES_CSR_BSY    = 0x00000200;
	static const uint32_t SDES_CSR_LENS   = 0;

	static const uint32_t SDES_CSR_LRMSK  = 0x00000fff;
	static const uint32_t SDES_CSR_BBMSK  = 0x000f0000;

	static const uint32_t SDES_CSR_BB_TCK = 0x00010000;
	static const uint32_t SDES_CSR_BB_TMS = 0x00020000;
	static const uint32_t SDES_CSR_BB_TDI = 0x00040000;
	static const uint32_t SDES_CSR_BB_TDO = 0x00080000;
	static const uint32_t SDES_CSR_BB_ENA = 0x80000000;

	unsigned              toscaSpace_;
	unsigned long         toscaBase_;

	unsigned long         maxVec_;
	unsigned              wrdSiz_;
	int                   irqFd_ ;


	bool                  bitBang_;
	bool                  useSdes_;
	unsigned              logBscn_;

	static const unsigned long MIN_SLEEP_NS = 20UL*1000UL*1000UL;

	struct timespec       pollTime_;
	bool                  doSleep_;
	unsigned              measure_;
	unsigned long         maxPollDelayUs_;
	unsigned              version_;

public:

	// I/O
	virtual void     o32(unsigned idx, uint32_t v);
	virtual uint32_t i32(unsigned idx);

	virtual void reset();

	virtual uint32_t wait();

	JtagDriverTmemFifo(int argc, char *const argv[], const char *devnam);

	virtual void
	init();

	virtual unsigned long
	getMaxVectorSize();

	virtual int
	xferFifo( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual int
	xferSdes( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual int
	xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size );

	virtual uint32_t
	xfer32bb(uint32_t tms, uint32_t tdi, unsigned nbits);

	virtual void
	bbsleep();

	virtual uint32_t
	xfer32sdes(uint32_t tms, uint32_t tdi, unsigned nbits, struct timespec *);


	virtual ~JtagDriverTmemFifo();

	static void usage();

};

extern "C" JtagDriver *drvCreate(const char *target);

#endif
