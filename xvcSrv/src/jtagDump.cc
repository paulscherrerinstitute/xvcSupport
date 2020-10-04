#include <jtagDump.h>
#include <stdio.h>
#include <vector>

JtagRegType::JtagRegType()
: bitpos_(0)
{
	v_.push_back(0ULL);
}

void
JtagRegType::clear()
{
	v_.clear();
	v_.push_back(0ULL);
	bitpos_ = 0;
}

unsigned
JtagRegType::getNumBits() const
{
	return (v_.size() - 1) * 8 * sizeof(VType::value_type) + bitpos_;
}

void
JtagRegType::print(FILE *f) const
{
	VType::const_reverse_iterator it = v_.rbegin();
	fprintf(f, "0x");
	if ( bitpos_ > 0 ) {
		fprintf(f,"%llx",(unsigned long long) *it);
	}
	while ( ++it != v_.rend() ) {
		fprintf(f,"%016llx", (unsigned long long) *it);
	}
}

void
JtagRegType::addBit(int b)
{
	if ( b ) {
		v_.back() |= (1<<bitpos_);
	}
	bitpos_++;
	if ( bitpos_ >= 8*sizeof(VType::value_type) ) {
		bitpos_ = 0;
		v_.push_back( 0ULL );
	}
}

void
JtagState_TestLogicReset::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( ! tms ) {
		context->changeState( &context->state_RunTestIdle_ );
	}
}

void
JtagState_RunTestIdle::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_SelectDRScan_ );
	}
}

void
JtagState_SelectDRScan::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_SelectIRScan_ );
	} else {
		context->changeState( &context->state_CaptureDR_    );
	}
}

void
JtagState_CaptureDR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	context->clearDR();
	if ( tms ) {
		context->changeState( &context->state_Exit1DR_ );
	} else {
		context->changeState( &context->state_ShiftDR_ );
	}
}

void
JtagState_ShiftDR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	context->shiftDR( tdo, tdi );
	if ( tms ) {
		context->changeState( &context->state_Exit1DR_ );
	}
}

void
JtagState_Exit1DR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_UpdateDR_ );
	} else {
		context->changeState( &context->state_PauseDR_  );
	}
}

void
JtagState_PauseDR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_Exit2DR_ );
	}
}

void
JtagState_Exit2DR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_UpdateDR_ );
	} else {
		context->changeState( &context->state_ShiftDR_  );
	}
}

void
JtagState_UpdateDR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
unsigned    bits = context->getDRLen();
	fprintf(stderr, "%s: DR[IR = ", getName());
	context->getIRo()->print( stderr );
	fprintf(stderr, "], nbits: %u\n", bits);
	fprintf(stderr, "  sent: "); context->getDRo()->print( stderr ); fprintf(stderr,"\n");
	fprintf(stderr, "  rcvd: "); context->getDRi()->print( stderr ); fprintf(stderr,"\n");
	if ( tms ) {
		context->changeState( &context->state_SelectDRScan_ );
	} else {
		context->changeState( &context->state_RunTestIdle_  );
	}
}

void
JtagState_SelectIRScan::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_TestLogicReset_ );
	} else {
		context->changeState( &context->state_CaptureIR_      );
	}
}

void
JtagState_CaptureIR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	context->clearIR();
	if ( tms ) {
		context->changeState( &context->state_Exit1IR_ );
	} else {
		context->changeState( &context->state_ShiftIR_ );
	}
}

void
JtagState_ShiftIR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	context->shiftIR( tdo, tdi );
	if ( tms ) {
		context->changeState( &context->state_Exit1IR_ );
	}
}

void
JtagState_Exit1IR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_UpdateIR_ );
	} else {
		context->changeState( &context->state_PauseIR_  );
	}
}

void
JtagState_PauseIR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_Exit2IR_ );
	}
}

void
JtagState_Exit2IR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
	if ( tms ) {
		context->changeState( &context->state_UpdateIR_ );
	} else {
		context->changeState( &context->state_ShiftIR_  );
	}
}

void
JtagState_UpdateIR::advance(JtagDumpCtx *context, int tms, int tdo, int tdi)
{
unsigned    bits = context->getIRLen();
	fprintf(stderr, "%s: IR sent: ", getName());
	context->getIRo()->print( stderr );
	fprintf(stderr, ", recv: ");
	context->getIRi()->print( stderr );
	fprintf(stderr, " (nbits: %u)\n", bits);
	if ( tms ) {
		context->changeState( &context->state_SelectDRScan_ );
	} else {
		context->changeState( &context->state_RunTestIdle_  );
	}
}

JtagDumpCtx::JtagDumpCtx()
{
	state_ = &state_TestLogicReset_;
}

void
JtagDumpCtx::clearDR()
{
	dri_.clear();
	dro_.clear();
}

void
JtagDumpCtx::clearIR()
{
	iri_.clear();
	iro_.clear();
}

unsigned
JtagDumpCtx::getDRLen()
{
	return dri_.getNumBits();
}

unsigned
JtagDumpCtx::getIRLen()
{
	return iri_.getNumBits();
}

void
JtagDumpCtx::shiftDR(int tdo, int tdi)
{
	dro_.addBit( tdo );
	dri_.addBit( tdi );
}

void
JtagDumpCtx::shiftIR(int tdo, int tdi)
{
	iro_.addBit( tdo );
	iri_.addBit( tdi );
}

const JtagRegType *
JtagDumpCtx::getDRi()
{
	return &dri_;
}

const JtagRegType *
JtagDumpCtx::getDRo()
{
	return &dro_;
}

const JtagRegType *
JtagDumpCtx::getIRi()
{
	return &iri_;
}

const JtagRegType *
JtagDumpCtx::getIRo()
{
	return &iro_;
}

void
JtagDumpCtx::changeState(JtagState *newState)
{
#ifdef DEBUG
	if ( (state_ != newState) ) {
		fprintf(stderr, "Entering %s\n", newState->getName());
	}
#endif
	state_ = newState;
}

void
JtagDumpCtx::advance(int tms, int tdo, int tdi)
{
#if 0
fprintf(stderr, "A(%d)\n", !!tms);
#endif
	state_->advance(this, tms, tdo, tdi);
}

unsigned
JtagDumpCtx::processBuf(int nbits, unsigned char *tmsb, unsigned char *tdob, unsigned char *tdib, const JtagState *until)
{
unsigned n,m;

	while ( nbits > 0 ) {
		n = 1 << ( nbits < 8 ? nbits : 8 );
		for ( m = 1; m < n; m <<= 1 ) {
			if ( until && ( *state_ == *until ) ) {
				return nbits;
			} 
			advance( ((*tmsb) & m), ((*tdob) & m), ((*tdib) & m) );
			nbits--;
		}

		tmsb++;
		tdob++;
		tdib++;
	}
	return 0;
}
