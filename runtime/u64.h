#ifndef ASL_U64_H
#define ASL_U64_H

#include "base.h"

// Module: U64

// safe
U64 U64_and(U64 a, U64 b) { return a & b; }
U64 U64_or(U64 a, U64 b) { return a | b; }
U64 U64_xor(U64 a, U64 b) { return a ^ b; }
U64 U64_not(U64 a) { return ~a; }
U64 U64_lshift(U64 a, U64 b) { return a << b; }
U64 U64_rshift(U64 a, U64 b) { return a >> b; }

// unsafe
U64 U64_add(U64 a, U64 b) { return a + b; }
U64 U64_subtract(U64 a, U64 b) { return a - b; }
U64 U64_multiply(U64 a, U64 b) { return a * b; }
U64 U64_quotient(U64 a, U64 b) { return a / b; }
U64 U64_remainder(U64 a, U64 b) { return a % b; }

// safe
S64 U64_compare(U64 a, U64 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// safe
U64 U64_from_S8(S8 value) { return (U64)value; }
U64 U64_from_S16(S16 value) { return (U64)value; }
U64 U64_from_S32(S32 value) { return (U64)value; }
U64 U64_from_U8(U8 value) { return (U64)value; }
U64 U64_from_U16(U16 value) { return (U64)value; }
U64 U64_from_U32(U32 value) { return (U64)value; }

// unsafe
U64 U64_from_S64(S64 value) { return (U64)value; }
U64 U64_from_Pointer(Pointer ptr) { return (*((U64 *)ptr)); }

#endif // ASL_U64_H