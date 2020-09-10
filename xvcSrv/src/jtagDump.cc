#include <jtagDump.h>
#include <stdio.h>

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
const char *mrk  = bits > sizeof(JtagRegType)*8 ? "*" : "";
	printf("%s: DR sent: 0x%s%llx, recv: 0x%s%llx (total %d bits)\n", getName(), mrk, context->getDRo(), mrk, context->getDRi(), bits);
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
const char *mrk  = bits > sizeof(JtagRegType)*8 ? "*" : "";
	printf("%s: IR sent: 0x%llx%s, recv: 0x%s%llx (total %d bits)\n", getName(), context->getIRo(), mrk, mrk, context->getIRi(), bits);
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
	dri_ = 0;
	dro_ = 0;
	drm_ = 1;
	drl_ = 0;
}

void
JtagDumpCtx::clearIR()
{
	iri_ = 0;
	iro_ = 0;
    irm_ = 1;
	irl_ = 0;
}

unsigned
JtagDumpCtx::getDRLen()
{
	return drl_;
}

unsigned
JtagDumpCtx::getIRLen()
{
	return irl_;
}

void
JtagDumpCtx::shiftDR(int tdo, int tdi)
{
#if 0
	if ( 0 == drm_ ) {
		fprintf(stderr,"WARNING: DR contents too long; upper bits not captured\n");
	}
#endif
	if ( tdo )
		dro_ |= drm_;
	if ( tdi )
		dri_ |= drm_;
	drm_ <<= 1;
	drl_++;
}

void
JtagDumpCtx::shiftIR(int tdo, int tdi)
{
const JtagRegType msb = (((JtagRegType)1) << (sizeof(JtagRegType)*8 - 1));
	if ( 0 == irm_ ) {
		fprintf(stderr,"WARNING: IR contents too long; upper bits not captured\n");
		iro_ = iro_ >> 1;
		if ( tdo ) {
			iro_ |= msb;
		} else {
			iro_ &= ~msb;
		}
	}
	if ( tdo )
		iro_ |= irm_;
	if ( tdi )
		iri_ |= irm_;
	irm_ <<= 1;
	irl_++;
}

JtagRegType
JtagDumpCtx::getDRi()
{
	return dri_;
}

JtagRegType
JtagDumpCtx::getDRo()
{
	return dro_;
}

JtagRegType
JtagDumpCtx::getIRi()
{
	return iri_;
}

JtagRegType
JtagDumpCtx::getIRo()
{
	return iro_;
}

void
JtagDumpCtx::changeState(JtagState *newState)
{
#ifdef DEBUG
	if ( (state_ != newState) ) {
		printf("Entering %s\n", newState->getName());
	}
#endif
	state_ = newState;
}

void
JtagDumpCtx::advance(int tms, int tdo, int tdi)
{
#if 0
printf("A(%d)\n", !!tms);
#endif
	state_->advance(this, tms, tdo, tdi);
}

void
JtagDumpCtx::processBuf(int nbits, unsigned char *tmsb, unsigned char *tdob, unsigned char *tdib)
{
unsigned n,m;

	while ( nbits > 0 ) {
		n = 1 << ( nbits < 8 ? nbits : 8 );
		for ( m = 1; m < n; m <<= 1 ) {
			advance( ((*tmsb) & m), ((*tdob) & m), ((*tdib) & m) );
		}

		tmsb++;
		tdob++;
		tdib++;
		
		nbits -= 8;
	}

}
