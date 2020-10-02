//-----------------------------------------------------------------------------
// Title      : JTAG Support
//-----------------------------------------------------------------------------
// File       : xvcDrvAxisFifo.cc
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

#include <xvcDrvAxisTmem.h>
#include <unistd.h>
#include <stdlib.h>
#include <toscaApi.h>
#include <fcntl.h>

#define SDES_PROBEVAL (0xa<<(SDES_CSR_LENS))

JtagDriverTmemFifo::JtagDriverTmemFifo(int argc, char *const argv[], const char *devnam)
: JtagDriverAxisToJtag( argc, argv       ),
  toscaSpace_         ( TOSCA_USER2      ),
  toscaBase_          ( 0x200000         ),
  maxVec_             ( 128              ),
  wrdSiz_             ( sizeof(uint32_t) ),
  irqFd_              ( - 1              ),
  bitBang_            ( false            ),
  logBscn_            ( false            ),
  doSleep_            ( false            ),
  measure_            ( 100              ),
  maxPollDelayUs_     ( 0                )
{
uint32_t      csrVal, csrSdes;
unsigned long maxBytes;
unsigned long maxWords = 512;
int           opt;
const char   *basp;
char         *endp;
const char   *irqfn = 0;

	toscaSpace_ = toscaStrToAddrSpace(devnam, &basp);
	toscaBase_  = strtoul(basp, &endp, 0);
	if ( ! toscaSpace_ || (endp == basp)  ) {
		fprintf(stderr, "Invalid <target>: must be '<tosca_addr_space>:<numerical_base_address>'\n");
		throw std::runtime_error("Invalid <target>");
	}

	if ( MAGIC != i32( FIFO_MAGIC_IDX ) ) {
		fprintf( stderr, "No magic firmware ID found; please verify address-space and base-address\n" );
		throw std::runtime_error("TMEM Device not found");
	}

	while ( (opt = getopt(argc, argv, "i:bl")) > 0 ) {
		switch ( opt ) {
			case 'b': bitBang_ = true;          break;
			case 'l': logBscn_ = true;          break;
			case 'i': irqfn    = optarg;        break;
			default:
				fprintf( stderr,"Unknown driver option -%c\n", opt );
				throw std::runtime_error("Unknown driver option");
		}
	}

	csrVal   = i32( FIFO_CSR_IDX );
	version_ = ((csrVal & FIFO_CSR_VERSM) >> FIFO_CSR_VERSS);

	switch ( version_ ) {
		case VERSION_0:
			if ( bitBang_ || logBscn_ ) {
				fprintf( stderr, "Bit-banging not supported for FW interface; disabling\n");
				bitBang_ = false;
				logBscn_ = false;
			}
		break;

		case VERSION_1:
			csrSdes = i32( SDES_CSR_IDX ) & ~SDES_CSR_LRMSK;
			o32( SDES_CSR_IDX, (csrSdes | SDES_PROBEVAL ) );
			if ( (i32(SDES_CSR_IDX) & SDES_CSR_LRMSK) == SDES_PROBEVAL ) {
				useSdes_ = true;
				printf("JtagSerDes raw interface detected\n");
			}
		break;

		default:
			fprintf( stderr, "Firmware interface version not supported by this driver\n");
			throw std::runtime_error("TMEM Device wrong FW version");
	}


	if ( logBscn_ ) {
		bitBang_ = true;
	}

	if ( bitBang_ || ~useSdes_ ) {
		measure_ = 0;
	}

	if ( bitBang_ || useSdes_ ) {
		if ( irqfn ) {
			fprintf(stderr, "Interrupts not supported (sdes or bit-bang)\n");
		}	
		irqfn = 0;
	}


	maxWords = (((csrVal & FIFO_CSR_MAXWM) >> FIFO_CSR_MAXWS) << 10 ) / wrdSiz_;

	// one header word; two vectors must fit
	maxBytes = (maxWords - 1) * wrdSiz_;

	maxVec_ = maxBytes/2;

	if ( irqfn && ( (irqFd_ = open(irqfn, O_RDWR)) < 0 ) ) {
		perror("WARNING: Interrupt descriptor not found -- using polled mode");
	}

	// one header word; two vectors must fit
	maxBytes = (maxWords - 1) * wrdSiz_;

	maxVec_ = maxBytes/2;

	reset();
}

JtagDriverTmemFifo::~JtagDriverTmemFifo()
{
	if ( irqFd_ >= 0 ) {
		close( irqFd_ );
	}
}

void
JtagDriverTmemFifo::o32(unsigned idx, uint32_t v)
{
	if ( debug_ > 2 ) {
		fprintf(stderr, "r[%d]:=0x%08x\n", idx, v);
	}
	toscaWrite( toscaSpace_, toscaBase_ + (idx << 2), v );
}

uint32_t
JtagDriverTmemFifo::i32(unsigned idx)
{
	uint32_t v = toscaRead( toscaSpace_, toscaBase_ + (idx << 2) );
	if ( debug_ > 2 ) {
		fprintf(stderr, "r[%d]=>0x%08x\n", idx, v);
	}
	return v;
}

uint32_t
JtagDriverTmemFifo::wait()
{
uint32_t evs = 0;
	if ( irqFd_ >= 0 ) {
		evs = 1;
		if ( sizeof(evs) != write( irqFd_, &evs, sizeof(evs) ) ) {
			throw SysErr("Unable to write to IRQ descriptor");
		}
		if ( sizeof(evs) != read( irqFd_, &evs, sizeof(evs) ) ) {
			throw SysErr("Unable to read from IRQ descriptor");
		}
	} else if ( doSleep_ ) {
		nanosleep( &pollTime_, 0 );
	} // else busy wait

	return evs;
}

void
JtagDriverTmemFifo::reset()
{
int      set = 0;
uint32_t csr;

	/* Do this first; resets the internal registers, too! */
	if ( ! useSdes_ ) {
		o32( FIFO_CSR_IDX, FIFO_CSR_RST );
		o32( FIFO_CSR_IDX, 0              );
		if ( irqFd_ >= 0 ) {
			o32( FIFO_CSR_IDX, FIFO_CSR_IENI );
		}
	}

	if ( version_ == VERSION_1 ) {
		/* Have bitbang */
		csr = i32( SDES_CSR_IDX );

		// reset bit-banging interface
		csr &= ~ SDES_CSR_BBMSK;
		// must pull TMS high; TMS on jtag is bb-TMS AND serdes-TMS
		// TCK and TDI must be low (ORed)
		csr |=   SDES_CSR_BB_TMS;
		csr &= ~ SDES_CSR_BB_TDI;
		csr &= ~ SDES_CSR_BB_TCK;

		csr &= ~ SDES_CSR_BB_ENA;

		o32( SDES_CSR_IDX, csr );

		if ( useSdes_ ) {
			// reset TAP and leave with TMS asserted (in fact; TMS seems deasserted due to a bug?), TDI deasserted

			xfer32sdes( 0xff, 0x00, 8, 0 );
		}
	}

	if ( bitBang_ ) {
		o32( SDES_CSR_IDX, csr | SDES_CSR_BB_ENA );
	}

}

uint32_t
JtagDriverTmemFifo::xfer32bb(uint32_t tms, uint32_t tdi, unsigned nbits)
{
uint32_t m;
uint32_t csr, tdo, csrrb;
unsigned i;

	tdo = 0;

	csr = i32( SDES_CSR_IDX ) & ~SDES_CSR_BBMSK;
	for ( i = 0, m = 1; i < nbits; i++, m <<= 1 ) {
		if ( (tms & m ) )
			csr |=   SDES_CSR_BB_TMS;
		else
			csr &= ~ SDES_CSR_BB_TMS;

		if ( (tdi & m ) )
			csr |=   SDES_CSR_BB_TDI;
		else
			csr &= ~ SDES_CSR_BB_TDI;
			
		o32( SDES_CSR_IDX, csr );
		bbsleep();
		if ( (csrrb = i32( SDES_CSR_IDX )) & SDES_CSR_BB_TDO ) {
			tdo |= m;
		}
		if ( logBscn_ ) {
			fprintf(stderr, "BSCNL: 0x%08x\n", (unsigned long)csrrb);
		}
		csr |= SDES_CSR_BB_TCK;
		o32( SDES_CSR_IDX, csr );
		bbsleep();
		if ( logBscn_ ) {
			csrrb = i32( SDES_CSR_IDX );
			fprintf(stderr, "BSCNH: 0x%08x\n", (unsigned long)csrrb);
		}
		csr &= ~SDES_CSR_BB_TCK;
	}
//	o32( SDES_CSR_IDX, csr );
	return tdo;
}

void
JtagDriverTmemFifo::bbsleep()
{
struct timespec t;
	t.tv_sec  = 0;
	t.tv_nsec = 1000;
	nanosleep( &t, 0 );
}

uint32_t
JtagDriverTmemFifo::xfer32sdes(uint32_t tms, uint32_t tdi, unsigned nbits, struct timespec *then)
{
uint32_t csr, tdo;

	csr  = i32( SDES_CSR_IDX ) & ~ SDES_CSR_LRMSK;
	csr |= (nbits - 1) << SDES_CSR_LENS;

	o32( SDES_TMS_IDX, tms );
	o32( SDES_TDI_IDX, tdi );
	o32( SDES_CSR_IDX, csr | SDES_CSR_RUN );

	if ( then && measure_ ) {
		doSleep_ = false;
		clock_gettime( CLOCK_MONOTONIC, then );
	}

	while ( i32(SDES_CSR_IDX) & SDES_CSR_BSY ) {
		wait();
	}

	tdo = i32( SDES_TDO_IDX );
	tdo >>= (32 - nbits);
	return tdo;
}


void
JtagDriverTmemFifo::init()
{
	reset();
	JtagDriverAxisToJtag::init();
	// have now the target word size -- verify:
	if ( getWordSize() != wrdSiz_ ) {
		throw std::runtime_error("ERROR: firmware misconfigured -- FIFO word size /= JTAG stream word size");
	}
}

unsigned long
JtagDriverTmemFifo::getMaxVectorSize()
{
	return maxVec_;
}

int
JtagDriverTmemFifo::xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
{
	if ( bitBang_ || useSdes_ ) {
		return xferSdes( txb, txBytes, hdbuf, hsize, rxb, size );
	} else {
		return xferFifo( txb, txBytes, hdbuf, hsize, rxb, size );
	}
}

int
JtagDriverTmemFifo::xferFifo( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
{
unsigned txWords   = (txBytes + 3)/4;
uint32_t lastBytes = txBytes - 4*(txWords - 1);
unsigned i;
unsigned got, min, minw, rem;
uint32_t w;
uint32_t csr;

	if ( hsize % 4 != 0 ) {
		throw std::runtime_error("AXIS2TMEM FIFO only supports word-lengths that are a multiple of 4");
	}

	if ( lastBytes ) {
		txWords--;
	}
	for ( i=0; i<txWords; i++ ) {
		memcpy( &w, &txb[4*i], 4 );
		o32( FIFO_DAT_IDX, __builtin_bswap32( w ) );
	}
	if ( lastBytes ) {
		w = 0;
		memcpy( &w, &txb[4*i], lastBytes );
		o32( FIFO_DAT_IDX, __builtin_bswap32( w ) );
	}

	o32( FIFO_CSR_IDX, i32( FIFO_CSR_IDX ) | FIFO_CSR_EOFO );

	while ( ( (csr = i32( FIFO_CSR_IDX )) & FIFO_CSR_EMPI ) ) {
		wait();
	}

	got = ( (csr >> FIFO_CSR_NWRDS) & FIFO_CSR_NWRDM ) * wrdSiz_;

	if ( 0 == got ) {
		throw ProtoErr("Didn't receive enough data for header");
	}

	for ( i=0; i<hsize; i+= 4 ) {
		w = i32( FIFO_DAT_IDX );
		if ( got < 4 ) {
			throw ProtoErr("Didn't receive enough data for header");
		}
		w = __builtin_bswap32( w );
		memcpy( hdbuf + i, &w, 4 );
		got   -= 4;
	}
	min  = got;

	if ( size < min ) {
		min = size;
	}

	minw = min/4;

	for ( i=0; i<4*minw; i+=4 ) {
		w = i32( FIFO_DAT_IDX );
		w = __builtin_bswap32( w );
		memcpy( &rxb[i], &w, 4 );
	}

	if ( (rem = (min - i)) ) {
		w = i32( FIFO_DAT_IDX );
		w = __builtin_bswap32( w );
		memcpy( &rxb[i], &w, rem );
		i += 4;
	}

	/* Discard excess */
	while ( i < got ) {
		i32( FIFO_DAT_IDX );
		i += 4;
	}

	if ( drEn_ && 0 == ((++drop_) & 0xff) ) {
		fprintf(stderr, "Drop\n");
		fflush(stderr);
		throw TimeoutErr();
	}

	return min;
}

int
JtagDriverTmemFifo::xferSdes( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
{
Header   hdr;
unsigned nbits, l, lb;
uint8_t  *pi, *po;
int      min;
unsigned nbytes;
unsigned nwords;
unsigned wsz = hsize;

uint32_t tms, tdi, tdo;

struct   timespec then, now;

	/* This firmware does not expect a stream in our usual format, so we must handle the header here */
	pi  = txb;
	po  = rxb;

	/* Header is in little-endian format */
	hdr = getHdr( txb );
	pi += wsz;

	if ( getVrs(hdr) != PVER0 ) {
		throw std::runtime_error("AxiDbgBridgeIP driver: xfer() found unexpected version");
	}

	if ( hsize != sizeof(uint32_t) ) {
		throw std::runtime_error("AxiDbgBridgeIP driver: xfer() found unexpected header size");
	}

	switch ( getCmd(hdr) ) {
		case CMD_S: /* normal/main case */
		break;

		case CMD_Q:
			hdr = mkQueryReply( PVER0, sizeof(uint32_t), 0, UNKNOWN_PERIOD );
			setHdr( hdbuf, hdr ); po += sizeof(hdr);
			return sizeof(uint32_t);

		default:
printf("%08x\n", (unsigned long)hdr);
			throw std::runtime_error("AxiDbgBridgeIP driver: xfer() found unexpected command");
	}

	if ( wsz != sizeof(tms) ) {
		throw std::runtime_error("AXI-DebugBridge IP only supports word-lengths of 4");
	}

	nbits  = getLen( hdr );
	nbytes = (nbits + 7)/8;
	nwords = (nbytes + wsz - 1)/wsz;

	if ( txBytes < nwords * 2 * wsz ) {
		throw std::runtime_error("AXI-DebugBridge IP: not enough input data");
	}

	if ( size < nbytes ) {
		throw std::runtime_error("AXI-DebugBridge IP: output buffer too small");
	}

	setHdr( hdbuf, hdr );


	lb = sizeof(tms);
	l  = 8*lb;

	while ( nbits > 0 ) {

		tms = getw32( pi ); pi += sizeof(tms);
		tdi = getw32( pi ); pi += sizeof(tms);
		if (nbits < 8*sizeof(tms)) {
			l   = nbits;
			lb  = (l + 7)/8;
		}

		tdo = bitBang_ ? xfer32bb( tms, tdi, l ) : xfer32sdes( tms, tdi, l, &then );

		setw32( po, tdo, lb ); po += lb;

		if ( measure_ ) {
			unsigned long diffNs, diffUs;
			clock_gettime( CLOCK_MONOTONIC, &now );
			diffNs  = (now.tv_sec  - then.tv_sec ) * 1000000000UL;
			diffNs += (now.tv_nsec - then.tv_nsec);
			if ( diffNs >= MIN_SLEEP_NS ) {
				pollTime_.tv_sec  = 0;
				pollTime_.tv_nsec = diffNs;
				measure_          = 0;
				doSleep_          = true;
			} else {
				measure_--;
			}
			diffUs = diffNs/1000UL;
			if ( diffUs > maxPollDelayUs_ ) {
				maxPollDelayUs_ = diffUs;
				if ( getDebug() ) {
					printf("axiDebugBridgeIP Driver max poll delay %lu us so far...\n", maxPollDelayUs_);
				}
			}
		}
		
		nbits -= l;
	}

	return nbytes;
}


void
JtagDriverTmemFifo::usage()
{
	printf("  Axi Stream <-> TMEM Fifo Driver options: [-i]\n");
	printf("  -t <aspace>:<base_address>, e.g., -t USER2:0x200000\n");
	printf("  -i <irq_file_name>        , e.g., -i /dev/toscauserevent1.13 (defaults to polled mode)\n");
	printf("  -b                          use bit-bang interface (for debugging)\n");
	printf("  -l                          use bit-bang interface and log BSCAN signals\n");
}

static DriverRegistrar<JtagDriverTmemFifo> r("tmem");
