//-----------------------------------------------------------------------------
// Title      : JTAG Support
//-----------------------------------------------------------------------------
// Company    : PSI
//-----------------------------------------------------------------------------
// Description: Driver for Vivado's AXI Debug Bridge IP
//-----------------------------------------------------------------------------

#include <xvcDrvSerDesTmem.h>
#include <unistd.h>
#include <stdlib.h>
#include <toscaApi.h>

#define DBG_LOG_BSCAN 1

JtagDriverSerDesTmem::JtagDriverSerDesTmem(int argc, char *const argv[], const char *devnam)
: JtagDriverAxisToJtag( argc, argv       ),
  doSleep_            ( false            ),
  measure_            ( 100              ),
  maxPollDelayUs_     ( 0                ),
  toscaSpace_         ( TOSCA_USER2      ),
  toscaBase_          ( 0x200000         ),
  bitBang_            ( false            ),
  debug_              ( 0                )
{
uint32_t      csrVal;
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

	while ( (opt = getopt(argc, argv, "bl")) > 0 ) {
		switch ( opt ) {
			case 'b': bitBang_ = true;          break;
			case 'l': debug_  |= DBG_LOG_BSCAN; break;
			default:
				fprintf( stderr,"Unknown driver option -%c\n", opt );
				throw std::runtime_error("Unknown driver option");
		}
	}

	if ( debug_ & DBG_LOG_BSCAN ) {
		bitBang_ = true;
	}

	if ( bitBang_ ) {
		measure_ = 0;
	}

	reset();

	if ( MAGIC != i32( FIFO_MAGIC_IDX ) ) {
		fprintf( stderr, "No magic firmware ID found; please verify address-space and base-address\n" );
		throw std::runtime_error("TMEM Device not found");
	}

	csrVal  = i32( FIFO_CSR_IDX );

	if ( ((csrVal & FIFO_CSR_VERSM) >> FIFO_CSR_VERSS) != SUPPORTED_VERS ) {
		fprintf( stderr, "Firmware interface version not supported by this driver\n");
		throw std::runtime_error("TMEM Device wrong FW version");
	}

	wrdSiz_ = 4;

	// one header word; two vectors must fit
	maxBytes = (maxWords - 1) * wrdSiz_;

	maxVec_ = maxBytes/2;

}

JtagDriverSerDesTmem::~JtagDriverSerDesTmem()
{
}

void
JtagDriverSerDesTmem::o32(unsigned idx, uint32_t v)
{
	if ( getDebug() > 2 ) {
		fprintf(stderr, "r[%d]:=0x%08x\n", idx, v);
	}
	toscaWrite( toscaSpace_, toscaBase_ + (idx<<2), v );
}

uint32_t
JtagDriverSerDesTmem::i32(unsigned idx)
{
	uint32_t v = toscaRead( toscaSpace_, toscaBase_ + (idx << 2) );
	if ( getDebug() > 2 ) {
		fprintf(stderr, "r[%d]=>0x%08x\n", idx, v);
	}
	return v;
}

void
JtagDriverSerDesTmem::wait()
{
	if ( doSleep_ ) {
		nanosleep( &pollTime_, 0 );
	}
}

void
JtagDriverSerDesTmem::reset()
{
uint32_t csr = i32( SDES_CSR_IDX );

	// reset bit-banging interface
	csr &= ~ SDES_CSR_BBMSK;
	// must pull TMS high; TMS on jtag is bb-TMS AND serdes-TMS
	// TCK and TDI must be low (ORed)
	csr |=   SDES_CSR_BB_TMS;
	csr &= ~ SDES_CSR_BB_TDI;
	csr &= ~ SDES_CSR_BB_TCK;

	csr &= ~ SDES_CSR_BB_ENA;

	o32( SDES_CSR_IDX, csr );
	// reset TAP and leave with TMS asserted (in fact; TMS seems deasserted due to a bug?), TDI deasserted
	xfer32sdes( 0xff, 0x00, 8, 0 );

	if ( bitBang_ ) {
		o32( SDES_CSR_IDX, csr | SDES_CSR_BB_ENA );
	}
}

void
JtagDriverSerDesTmem::init()
{
	reset();
	JtagDriverAxisToJtag::init();
	// have now the target word size -- verify:
	if ( getWordSize() != wrdSiz_ ) {
		throw std::runtime_error("ERROR: firmware misconfigured -- AXI-IP word size /= JTAG stream word size");
	}
}

unsigned long
JtagDriverSerDesTmem::getMaxVectorSize()
{
	return maxVec_;
}

uint32_t
JtagDriverSerDesTmem::xfer32bb(uint32_t tms, uint32_t tdi, unsigned nbits)
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
		if ( (debug_ & DBG_LOG_BSCAN) ) {
			fprintf(stderr, "BSCNL: 0x%08x\n", (unsigned long)csrrb);
		}
		csr |= SDES_CSR_BB_TCK;
		o32( SDES_CSR_IDX, csr );
		bbsleep();
		if ( (debug_ & DBG_LOG_BSCAN) ) {
			csrrb = i32( SDES_CSR_IDX );
			fprintf(stderr, "BSCNH: 0x%08x\n", (unsigned long)csrrb);
		}
		csr &= ~SDES_CSR_BB_TCK;
	}
//	o32( SDES_CSR_IDX, csr );
	return tdo;
}

void
JtagDriverSerDesTmem::bbsleep()
{
struct timespec t;
	t.tv_sec  = 0;
	t.tv_nsec = 1000;
	nanosleep( &t, 0 );
}

uint32_t
JtagDriverSerDesTmem::xfer32sdes(uint32_t tms, uint32_t tdi, unsigned nbits, struct timespec *then)
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

int
JtagDriverSerDesTmem::xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
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
JtagDriverSerDesTmem::usage()
{
	printf("  Raw JtagSerDes/TMEM Driver options: -b -> use bit-banging interface\n");
}

static DriverRegistrar<JtagDriverSerDesTmem> r("serDesTmem");
