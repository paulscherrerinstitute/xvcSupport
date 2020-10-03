#ifndef JTAG_DUMP_H
#define JTAG_DUMP_H

#include <vector>
#include <stdio.h>
#include <stdint.h>

class JtagRegType {
private:
  int bitpos_;

  typedef std::vector<uint64_t> VType;

  VType v_;

public:
  JtagRegType();

  void addBit(int i);

  unsigned getNumBits() const;

  void clear();

  void print(FILE *f) const;
};

class JtagDumpCtx;

class JtagState {
public:
	virtual const char *getName() const                                   = 0;
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi) = 0;

	virtual int operator==(const JtagState &other) const
	{
		return this->getName() == other.getName();
	}
};

class JtagState_TestLogicReset : public JtagState {
public:
	virtual const char *getName() const
	{
		return "TestLogicReset";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_RunTestIdle : public JtagState {
public:
	virtual const char *getName() const
	{
		return "RunTestIdle";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_SelectDRScan : public JtagState {
public:
	virtual const char *getName() const
	{
		return "SelectDRScan";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_CaptureDR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "CaptureDR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_ShiftDR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "ShiftDR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_Exit1DR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "Exit1DR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_PauseDR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "PauseDR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_Exit2DR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "Exit2DR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_UpdateDR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "UpdateDR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_SelectIRScan : public JtagState {
public:
	virtual const char *getName() const
	{
		return "SelectIRScan";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_CaptureIR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "CaptureIR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_ShiftIR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "ShiftIR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_Exit1IR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "Exit1IR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);

};

class JtagState_PauseIR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "PauseIR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_Exit2IR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "Exit2IR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};

class JtagState_UpdateIR : public JtagState {
public:
	virtual const char *getName() const
	{
		return "UpdateIR";
	}
	virtual void advance(JtagDumpCtx *context, int tms, int tdo, int tdi);
};


class JtagDumpCtx {
private:
	unsigned    irl_, drl_;
	JtagRegType iri_,dri_;
	JtagRegType iro_,dro_;
	JtagState  *state_;

public:
	JtagDumpCtx();

	JtagState_TestLogicReset state_TestLogicReset_;
	JtagState_RunTestIdle    state_RunTestIdle_;
	JtagState_SelectDRScan   state_SelectDRScan_;
	JtagState_CaptureDR      state_CaptureDR_;
	JtagState_ShiftDR        state_ShiftDR_;
	JtagState_Exit1DR        state_Exit1DR_;
	JtagState_PauseDR        state_PauseDR_;
	JtagState_Exit2DR        state_Exit2DR_;
	JtagState_UpdateDR       state_UpdateDR_;
	JtagState_SelectIRScan   state_SelectIRScan_;
	JtagState_CaptureIR      state_CaptureIR_;
	JtagState_ShiftIR        state_ShiftIR_;
	JtagState_Exit1IR        state_Exit1IR_;
	JtagState_PauseIR        state_PauseIR_;
	JtagState_Exit2IR        state_Exit2IR_;
	JtagState_UpdateIR       state_UpdateIR_;

	void clearDR();
	void clearIR();
	void shiftDR(int tdo, int tdi);
	void shiftIR(int tdo, int tdi);
	const JtagRegType *getDRi();
	const JtagRegType *getIRi();
	const JtagRegType *getDRo();
	const JtagRegType *getIRo();

	unsigned getDRLen();
	unsigned getIRLen();

	void changeState(JtagState *newState);	

	void advance(int tms, int tdo, int tdi);

	unsigned processBuf(int nbits, unsigned char *tmsb, unsigned char *tdob, unsigned char *tdib, const JtagState *until = 0);

	const JtagState *getCurrentState() { return state_; }
};

#endif

