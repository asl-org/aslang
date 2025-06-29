#ifndef ASL_S64_H
#define ASL_S64_H

#include "base.h"

// Module: S64
S64 S64_init(S64 a) { return a; }

// safe
S64 S64_and(S64 a, S64 b) { return a & b; }
S64 S64_or(S64 a, S64 b) { return a | b; }
S64 S64_xor(S64 a, S64 b) { return a ^ b; }
S64 S64_not(S64 a) { return ~a; }

// unsafe
S64 S64_add(S64 a, S64 b) { return a + b; }
S64 S64_subtract(S64 a, S64 b) { return a - b; }
S64 S64_multiply(S64 a, S64 b) { return a * b; }
S64 S64_quotient(S64 a, S64 b) { return a / b; }
S64 S64_remainder(S64 a, S64 b) { return a % b; }
S64 S64_lshift(S64 a, U64 b) { return a << b; }
S64 S64_rshift(S64 a, U64 b) { return a >> b; }

// safe
S64 S64_compare(S64 a, S64 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// safe
S64 S64_from_S8(S8 value) { return (S64)value; }
S64 S64_from_S16(S16 value) { return (S64)value; }
S64 S64_from_S32(S32 value) { return (S64)value; }
S64 S64_from_U8(U8 value) { return (S64)value; }
S64 S64_from_U16(U16 value) { return (S64)value; }
S64 S64_from_U32(U32 value) { return (S64)value; }

// unsafe
S64 S64_from_U64(U64 value) { return (S64)value; }
S64 S64_from_Pointer(Pointer ptr) { return (*((S64 *)ptr)); }

#endif // ASL_S64_H