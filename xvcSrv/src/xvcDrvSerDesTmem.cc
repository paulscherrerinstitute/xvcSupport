//-----------------------------------------------------------------------------
// Title      : JTAG Support
//-----------------------------------------------------------------------------
// Company    : PSI
//-----------------------------------------------------------------------------
// Description: Driver for Vivado's AXI Debug Bridge IP
//-----------------------------------------------------------------------------

#include <xvcDrvSerDesTmem.h>
#include <unistd.h>

JtagDriverSerDesTmem::JtagDriverSerDesTmem(int argc, char *const argv[], const char *devnam)
: JtagDriverAxisToJtag( argc, argv       ),
  doSleep_            ( false            ),
  measure_            ( 100              ),
  maxPollDelayUs_     ( 0                ),
  toscaSpace_         ( TOSCA_USER2      ),
  toscaBase_          ( 0x200000         )
{
uint32_t      csrVal;
unsigned long maxBytes;
unsigned long maxWords;
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

	while ( (opt = getopt(argc, argv, "")) > 0 ) {
		switch ( opt ) {
			default:
				fprintf( stderr,"Unknown driver option -%c\n", opt );
				throw std::runtime_error("Unknown driver option");
		}
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

	maxWords = (((csrVal & FIFO_CSR_MAXWM) >> FIFO_CSR_MAXWS) << 10 ) / wrdSiz_;

	// one header word; two vectors must fit
	maxBytes = (maxWords - 1) * wrdSiz_;

	maxVec_ = maxBytes/2;

}

{
unsigned long maxBytes = 1024; /* arbitrary; could support an option to change this */
int           opt;

	while ( (opt = getopt(argc, argv, "M:")) > 0 ) {
		switch ( opt ) {
			case 'M':
				if ( 1 != sscanf(optarg, "%li", &maxBytes) ) {
					fprintf( stderr,"Error: Unable to scan value for option -%c\n", opt);
					throw std::runtime_error("Invalid scan driver option value");
				}
			break;
			default:
				fprintf( stderr,"Unknown driver option -%c\n", opt );
				throw std::runtime_error("Unknown driver option");
		}
	}

	reset();

	wrdSiz_ = 4;
    maxVec_ = maxBytes;
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
	map_.wr(idx, v);
}

uint32_t
JtagDriverSerDesTmem::i32(unsigned idx)
{
	uint32_t v = map_.rd(idx);
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

int
JtagDriverSerDesTmem::xfer( uint8_t *txb, unsigned txBytes, uint8_t *hdbuf, unsigned hsize, uint8_t *rxb, unsigned size )
{
Header   hdr;
unsigned nbits, l, lb;
uint8_t  *pi, *po;
int      min;
uint32_t w;
unsigned nbytes;
unsigned nwords;
unsigned wsz = hsize;

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

	if ( wsz != sizeof(w) ) {
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


	lb = sizeof(w);
	l  = 8*lb;
	o32( LENGTH_IDX, l);

	while ( nbits > 0 ) {

		w = getw32( pi ); pi += sizeof(w);
		o32( TMSVEC_IDX, w );
		w = getw32( pi ); pi += sizeof(w);
		o32( TDIVEC_IDX, w );
		if (nbits < 8*sizeof(w)) {
			l = nbits;
			o32( LENGTH_IDX, l );
			lb = (l + 7)/8;
		}
		w = i32( CSR_IDX );
		w |= CSR_RUN;
		o32( CSR_IDX, w );

		if ( measure_ ) {
			doSleep_ = false;
			clock_gettime( CLOCK_MONOTONIC, &then );
		}

		while ( i32(CSR_IDX) & CSR_RUN ) {
			wait();
		}

		w = i32( TDOVEC_IDX );
		setw32( po, w, lb ); po += lb;

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
	printf("  Axi-Debug Bridge IP Fifo Driver options: (none)\n");
}

static DriverRegistrar<JtagDriverSerDesTmem> r("serDesTmem");
