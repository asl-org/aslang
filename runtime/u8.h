#ifndef ASL_U8_H
#define ASL_U8_H

#include "base.h"

// Module: U8

U8 U8_init(U8 a) { return a; }
U64 U8_byte_size(U64 items) { return items * sizeof(U8); }

// safe
U8 U8_and(U8 a, U8 b) { return a & b; }
U8 U8_or(U8 a, U8 b) { return a | b; }
U8 U8_xor(U8 a, U8 b) { return a ^ b; }
U8 U8_not(U8 a) { return ~a; }
U8 U8_lshift(U8 a, U64 b) { return a << b; }
U8 U8_rshift(U8 a, U64 b) { return a >> b; }

// unsafe
U8 U8_add(U8 a, U8 b) { return a + b; }
U8 U8_subtract(U8 a, U8 b) { return a - b; }
U8 U8_multiply(U8 a, U8 b) { return a * b; }
U8 U8_quotient(U8 a, U8 b) { return a / b; }
U8 U8_remainder(U8 a, U8 b) { return a % b; }

// safe
S64 U8_compare(U8 a, U8 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// unsafe
U8 U8_from_S8(S8 value) { return (U8)value; }
U8 U8_from_S16(S16 value) { return (U8)value; }
U8 U8_from_S32(S32 value) { return (U8)value; }
U8 U8_from_S64(S64 value) { return (U8)value; }
U8 U8_from_U16(U16 value) { return (U8)value; }
U8 U8_from_U32(U32 value) { return (U8)value; }
U8 U8_from_U64(U64 value) { return (U8)value; }
U8 U8_from_Pointer(Pointer ptr) { return (*((U8 *)ptr)); }

#endif // ASL_U8_H