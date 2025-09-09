#ifndef ASL_F32_H
#define ASL_F32_H

#include "base.h"

// Module: F32
F32 F32_init(F32 a) { return a; }
U64 F32_byte_size(U64 items) { return items * sizeof(F32); }

// unsafe
F32 F32_add(F32 a, F32 b) { return a + b; }
F32 F32_subtract(F32 a, F32 b) { return a - b; }
F32 F32_multiply(F32 a, F32 b) { return a * b; }
F32 F32_divide(F32 a, F32 b) { return a / b; }

// safe
S64 F32_compare(F32 a, F32 b) { return a > b ? 1 : (a == b ? 0 : -1); }

// safe
F32 F32_from_S8(S8 value) { return (F32)value; }
F32 F32_from_S16(S16 value) { return (F32)value; }
F32 F32_from_U8(U8 value) { return (F32)value; }
F32 F32_from_U16(U16 value) { return (F32)value; }

// unsafe
F32 F32_from_S32(S32 value) { return (F32)value; }
F32 F32_from_S64(S64 value) { return (F32)value; }
F32 F32_from_U32(U32 value) { return (F32)value; }
F32 F32_from_U64(U64 value) { return (F32)value; }
F32 F32_from_F64(F64 value) { return (F32)value; }
F32 F32_from_Pointer(Pointer ptr) { return (*((F32 *)ptr)); }
Pointer F32_write_Pointer(Pointer ptr, F32 value)
{
  (*((F32 *)ptr)) = value;
  return ptr;
}
#endif // ASL_F32_H