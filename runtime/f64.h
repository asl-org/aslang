#ifndef ASL_F64_H
#define ASL_F64_H

#include "base.h"

// Module: F64

// Function: unsafe_print
S32 F64_unsafe_print(F64 num) { return printf("%lf\n", num); }

// Function: unsafe_add
F64 F64_unsafe_add_S8(F64 num1, S8 num2) { return num1 + num2; }
F64 F64_unsafe_add_S16(F64 num1, S16 num2) { return num1 + num2; }
F64 F64_unsafe_add_S32(F64 num1, S32 num2) { return num1 + num2; }
F64 F64_unsafe_add_S64(F32 num1, S64 num2) { return num1 + num2; }
F64 F64_unsafe_add_U8(F64 num1, U8 num2) { return num1 + num2; }
F64 F64_unsafe_add_U16(F64 num1, U16 num2) { return num1 + num2; }
F64 F64_unsafe_add_U32(F64 num1, U32 num2) { return num1 + num2; }
F64 F64_unsafe_add_U64(F32 num1, U64 num2) { return num1 + num2; }
F64 F64_unsafe_add_F32(F64 num1, F32 num2) { return num1 + num2; }
F64 F64_unsafe_add_F64(F32 num1, F64 num2) { return num1 + num2; }
// Function: unsafe_subtract
F64 F64_unsafe_subtract_S8(F64 num1, S8 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_S16(F64 num1, S16 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_S32(F64 num1, S32 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_S64(F32 num1, S64 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_U8(F64 num1, U8 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_U16(F64 num1, U16 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_U32(F64 num1, U32 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_U64(F32 num1, U64 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_F32(F64 num1, F32 num2) { return num1 - num2; }
F64 F64_unsafe_subtract_F64(F32 num1, F64 num2) { return num1 - num2; }
// Function: unsafe_multiply
F64 F64_unsafe_multiply_S8(F64 num1, S8 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_S16(F64 num1, S16 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_S32(F64 num1, S32 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_S64(F32 num1, S64 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_U8(F64 num1, U8 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_U16(F64 num1, U16 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_U32(F64 num1, U32 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_U64(F32 num1, U64 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_F32(F64 num1, F32 num2) { return num1 * num2; }
F64 F64_unsafe_multiply_F64(F32 num1, F64 num2) { return num1 * num2; }
// Function: unsafe_division
F64 F64_unsafe_division_S8(F64 num1, S8 num2) { return num1 / num2; }
F64 F64_unsafe_division_S16(F64 num1, S16 num2) { return num1 / num2; }
F64 F64_unsafe_division_S32(F64 num1, S32 num2) { return num1 / num2; }
F64 F64_unsafe_division_S64(F32 num1, S64 num2) { return num1 / num2; }
F64 F64_unsafe_division_U8(F64 num1, U8 num2) { return num1 / num2; }
F64 F64_unsafe_division_U16(F64 num1, U16 num2) { return num1 / num2; }
F64 F64_unsafe_division_U32(F64 num1, U32 num2) { return num1 / num2; }
F64 F64_unsafe_division_U64(F32 num1, U64 num2) { return num1 / num2; }
F64 F64_unsafe_division_F32(F64 num1, F32 num2) { return num1 / num2; }
F64 F64_unsafe_division_F64(F32 num1, F64 num2) { return num1 / num2; }

#endif // ASL_F64_H