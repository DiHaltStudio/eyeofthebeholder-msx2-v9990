#pragma once
#include "common/mutex.h"
namespace OPL {
// the writes of the current tick: (register, value)
extern std::vector<std::pair<int, int>> g_writes;
class OPL {
public:
	virtual ~OPL() {}
	bool init() { return true; }
	void reset() {}
	void writeReg(int r, int v) { g_writes.push_back(std::make_pair(r, v)); }
	void start(Common::Functor0<void> *f, int) { delete f; }
	void stop() {}
	void setCallbackFrequency(int) {}
};
class Config { public: static OPL *create() { return new OPL(); } };
}
