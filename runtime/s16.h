#ifndef ASL_S16_H
#define ASL_S16_H

#include "base.h"

// Module: S16

// safe
S16 S16_and(S16 a, S16 b) { return a & b; }
S16 S16_or(S16 a, S16 b) { return a | b; }
S16 S16_xor(S16 a, S16 b) { return a ^ b; }
S16 S16_not(S16 a) { return ~a; }
S16 S16_lshift(S16 a, U64 b) { return a << b; }
S16 S16_rshift(S16 a, U64 b) { return a >> b; }

// unsafe
S16 S16_add(S16 a, S16 b) { return a + b; }
S16 S16_subtract(S16 a, S16 b) { return a - b; }
S16 S16_multiply(S16 a, S16 b) { return a * b; }
S16 S16_quotient(S16 a, S16 b) { return a / b; }
S16 S16_remainder(S16 a, S16 b) { return a % b; }

// safe
S64 S16_compare(S16 a, S16 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// safe
S16 S16_from_S8(S8 value) { return (S16)value; }
S16 S16_from_U8(U8 value) { return (S16)value; }

// unsafe
S16 S16_from_S32(S32 value) { return (S16)value; }
S16 S16_from_S64(S64 value) { return (S16)value; }
S16 S16_from_U16(U16 value) { return (S16)value; }
S16 S16_from_U32(U32 value) { return (S16)value; }
S16 S16_from_U64(U64 value) { return (S16)value; }
S16 S16_from_Pointer(Pointer ptr) { return (*((S16 *)ptr)); }

#endif // ASL_S16_H