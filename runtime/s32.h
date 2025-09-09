#ifndef ASL_S32_H
#define ASL_S32_H

#include "base.h"

// Module: S32
S32 S32_init(S32 a) { return a; }
U64 S32_byte_size(U64 items) { return items * sizeof(S32); }

// safe
S32 S32_and(S32 a, S32 b) { return a & b; }
S32 S32_or(S32 a, S32 b) { return a | b; }
S32 S32_xor(S32 a, S32 b) { return a ^ b; }
S32 S32_not(S32 a) { return ~a; }
S32 S32_lshift(S32 a, U64 b) { return a << b; }
S32 S32_rshift(S32 a, U64 b) { return a >> b; }

// unsafe
S32 S32_add(S32 a, S32 b) { return a + b; }
S32 S32_subtract(S32 a, S32 b) { return a - b; }
S32 S32_multiply(S32 a, S32 b) { return a * b; }
S32 S32_quotient(S32 a, S32 b) { return a / b; }
S32 S32_remainder(S32 a, S32 b) { return a % b; }

// safe
S64 S32_compare(S32 a, S32 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// safe
S32 S32_from_S8(S8 value) { return (S32)value; }
S32 S32_from_S16(S16 value) { return (S32)value; }
S32 S32_from_U8(U8 value) { return (S32)value; }
S32 S32_from_U16(U16 value) { return (S32)value; }

// unsafe
S32 S32_from_S64(S64 value) { return (S32)value; }
S32 S32_from_U32(U32 value) { return (S32)value; }
S32 S32_from_U64(U64 value) { return (S32)value; }
S32 S32_from_Pointer(Pointer ptr) { return (*((S32 *)ptr)); }

Pointer S32_write_Pointer(Pointer ptr, S32 value)
{
  (*((S32 *)ptr)) = value;
  return ptr;
}

#endif // ASL_S32_H