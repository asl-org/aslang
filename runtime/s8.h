#ifndef ASL_S8_H
#define ASL_S8_H

#include "base.h"

// Module: S8
S8 S8_init(S8 a) { return a; }
U64 S8_byte_size(U64 items) { return items * sizeof(S8); }

// safe
S8 S8_and(S8 a, S8 b) { return a & b; }
S8 S8_or(S8 a, S8 b) { return a | b; }
S8 S8_xor(S8 a, S8 b) { return a ^ b; }
S8 S8_not(S8 a) { return ~a; }
S8 S8_lshift(S8 a, U64 b) { return a << b; }
S8 S8_rshift(S8 a, U64 b) { return a >> b; }

// unsafe
S8 S8_add(S8 a, S8 b) { return a + b; }
S8 S8_subtract(S8 a, S8 b) { return a - b; }
S8 S8_multiply(S8 a, S8 b) { return a * b; }
S8 S8_quotient(S8 a, S8 b) { return a / b; }
S8 S8_remainder(S8 a, S8 b) { return a % b; }

// safe
S64 S8_compare(S8 a, S8 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// unsafe
S8 S8_from_S16(S16 value) { return (S8)value; }
S8 S8_from_S32(S32 value) { return (S8)value; }
S8 S8_from_S64(S64 value) { return (S8)value; }
S8 S8_from_U8(U8 value) { return (S8)value; }
S8 S8_from_U16(U16 value) { return (S8)value; }
S8 S8_from_U32(U32 value) { return (S8)value; }
S8 S8_from_U64(U64 value) { return (S8)value; }

S8 S8_from_Pointer(Pointer ptr) { return (*((S8 *)ptr)); }
Pointer S8_write_Pointer(Pointer ptr, S8 value)
{
  (*((S8 *)ptr)) = value;
  return ptr;
}

#endif // ASL_S8_H