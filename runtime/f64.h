#ifndef ASL_F64_H
#define ASL_F64_H

#include "base.h"

// Module: F64

// unsafe
F64 F64_add(F64 a, F64 b) { return a + b; }
F64 F64_subtract(F64 a, F64 b) { return a - b; }
F64 F64_multiply(F64 a, F64 b) { return a * b; }
F64 F64_divide(F64 a, F64 b) { return a / b; }

// safe
S64 F64_compare(F64 a, F64 b) { return a > b ? 1 : (a == b ? 0 : -1); }
U64 F64_print(F64 value) { return (U64)printf("%lf\n", value); }

// safe
F64 F64_from_S8(S8 value) { return (F64)value; }
F64 F64_from_S16(S16 value) { return (F64)value; }
F64 F64_from_S32(S32 value) { return (F64)value; }
F64 F64_from_U8(U8 value) { return (F64)value; }
F64 F64_from_U16(U16 value) { return (F64)value; }
F64 F64_from_U32(U32 value) { return (F64)value; }

// unsafe
F64 F64_from_S64(S64 value) { return (F64)value; }
F64 F64_from_U64(U64 value) { return (F64)value; }
F64 F64_from_F32(F32 value) { return (F64)value; }

#endif // ASL_F64_H