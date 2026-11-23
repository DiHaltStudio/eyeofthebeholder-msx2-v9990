#pragma once
namespace Common {
class Mutex {};
class StackLock { public: StackLock(const Mutex &) {} };
template<class Res> struct Functor0 { virtual ~Functor0() {} };
template<class Res, class T> struct Functor0Mem : public Functor0<Res> { Functor0Mem(T *, Res (T::*)()) {} };
}
namespace Audio { class Mixer; }
