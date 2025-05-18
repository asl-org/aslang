#ifndef ASL_U16_H
#define ASL_U16_H

#include "base.h"

// Module: U16

// safe
U16 U16_and(U16 a, U16 b) { return a & b; }
U16 U16_or(U16 a, U16 b) { return a | b; }
U16 U16_xor(U16 a, U16 b) { return a ^ b; }
U16 U16_not(U16 a) { return ~a; }
U16 U16_lshift(U16 a, U64 b) { return a << b; }
U16 U16_rshift(U16 a, U64 b) { return a >> b; }

// unsafe
U16 U16_add(U16 a, U16 b) { return a + b; }
U16 U16_subtract(U16 a, U16 b) { return a - b; }
U16 U16_multiply(U16 a, U16 b) { return a * b; }
U16 U16_quotient(U16 a, U16 b) { return a / b; }
U16 U16_remainder(U16 a, U16 b) { return a % b; }

// safe
S64 U16_compare(U16 a, U16 b) { return a > b ? 1 : (a == b ? 0 : -1); }
U64 U16_print(U16 value) { return (U64)printf("%u\n", value); }

// safe
U16 U16_from_S8(S8 value) { return (U16)value; }
U16 U16_from_U8(U8 value) { return (U16)value; }

// unsafe
U16 U16_from_S16(S16 value) { return (U16)value; }
U16 U16_from_S32(S32 value) { return (U16)value; }
U16 U16_from_S64(S64 value) { return (U16)value; }
U16 U16_from_U32(U32 value) { return (U16)value; }
U16 U16_from_U64(U64 value) { return (U16)value; }

#endif // ASL_U16_H