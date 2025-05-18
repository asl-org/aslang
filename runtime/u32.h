#ifndef ASL_U32_H
#define ASL_U32_H

#include "base.h"

// Module: U32

// safe
U32 U32_and(U32 a, U32 b) { return a & b; }
U32 U32_or(U32 a, U32 b) { return a | b; }
U32 U32_xor(U32 a, U32 b) { return a ^ b; }
U32 U32_not(U32 a) { return ~a; }
U32 U32_lshift(U32 a, U64 b) { return a << b; }
U32 U32_rshift(U32 a, U64 b) { return a >> b; }

// unsafe
U32 U32_add(U32 a, U32 b) { return a + b; }
U32 U32_subtract(U32 a, U32 b) { return a - b; }
U32 U32_multiply(U32 a, U32 b) { return a * b; }
U32 U32_quotient(U32 a, U32 b) { return a / b; }
U32 U32_remainder(U32 a, U32 b) { return a % b; }

// safe
S64 U32_compare(U32 a, U32 b) { return a > b ? 1 : (a == b ? 0 : -1); }
U64 U32_print(U32 value) { return (U64)printf("%u\n", value); }

// safe
U32 U32_from_S8(S8 value) { return (U32)value; }
U32 U32_from_S16(S16 value) { return (U32)value; }
U32 U32_from_U8(U8 value) { return (U32)value; }
U32 U32_from_U16(U16 value) { return (U32)value; }

// unsafe
U32 U32_from_S32(S32 value) { return (U32)value; }
U32 U32_from_S64(S64 value) { return (U32)value; }
U32 U32_from_U64(U64 value) { return (U32)value; }

#endif // ASL_U32_H