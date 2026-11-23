// stubs.h - the few ScummVM definitions the AdLib driver of kyra needs, so
// that it builds alone: the OPL only records the register writes
#pragma once
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <utility>
#include <cassert>
typedef uint8_t uint8; typedef int8_t int8; typedef uint16_t uint16; typedef int16_t int16;
typedef uint32_t uint32; typedef int32_t int32; typedef unsigned int uint; typedef uint8_t byte;
#define ARRAYSIZE(x) ((int)(sizeof(x) / sizeof(x[0])))
template<class T> inline T CLIP(T v, T lo, T hi) { return v < lo ? lo : (v > hi ? hi : v); }
template<class T> inline T MIN(T a, T b) { return a < b ? a : b; }
template<class T> inline T MAX(T a, T b) { return a > b ? a : b; }
inline uint16 READ_LE_UINT16(const void *p) { const uint8 *b = (const uint8 *)p; return b[0] | (b[1] << 8); }
inline uint16 READ_BE_UINT16(const void *p) { const uint8 *b = (const uint8 *)p; return (b[0] << 8) | b[1]; }
inline void warning(const char *, ...) {}
inline void error(const char *s, ...) { fprintf(stderr, "error: %s\n", s); exit(1); }
inline void debugC(int, int, const char *, ...) {}
enum { kDebugLevelSound = 1 };
#define override override
