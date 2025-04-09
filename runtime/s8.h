#ifndef ASL_S8_H
#define ASL_S8_H

#include "base.h"

// Module: S8

// Function: unsafe_print
S32 S8_unsafe_print(S8 num) { return printf("%" PRId8 "\n", num); }

// Function: unsafe_add
S8 S8_unsafe_add_S8(S8 num1, S8 num2) { return num1 + num2; }
S16 S8_unsafe_add_S16(S8 num1, S16 num2) { return num1 + num2; }
S32 S8_unsafe_add_S32(S8 num1, S32 num2) { return num1 + num2; }
S64 S8_unsafe_add_S64(S8 num1, S64 num2) { return num1 + num2; }
S8 S8_unsafe_add_U8(S8 num1, U8 num2) { return num1 + num2; }
S16 S8_unsafe_add_U16(S8 num1, U16 num2) { return num1 + num2; }
S32 S8_unsafe_add_U32(S8 num1, U32 num2) { return num1 + num2; }
S64 S8_unsafe_add_U64(S8 num1, U64 num2) { return num1 + num2; }
F32 S8_unsafe_add_F32(S8 num1, F32 num2) { return num1 + num2; }
F64 S8_unsafe_add_F64(S8 num1, F64 num2) { return num1 + num2; }
// Function: unsafe_subtract
S8 S8_unsafe_subtract_S8(S8 num1, S8 num2) { return num1 - num2; }
S16 S8_unsafe_subtract_S16(S8 num1, S16 num2) { return num1 - num2; }
S32 S8_unsafe_subtract_S32(S8 num1, S32 num2) { return num1 - num2; }
S64 S8_unsafe_subtract_S64(S8 num1, S64 num2) { return num1 - num2; }
S8 S8_unsafe_subtract_U8(S8 num1, U8 num2) { return num1 - num2; }
S16 S8_unsafe_subtract_U16(S8 num1, U16 num2) { return num1 - num2; }
S32 S8_unsafe_subtract_U32(S8 num1, U32 num2) { return num1 - num2; }
S64 S8_unsafe_subtract_U64(S8 num1, U64 num2) { return num1 - num2; }
F32 S8_unsafe_subtract_F32(S8 num1, F32 num2) { return num1 - num2; }
F64 S8_unsafe_subtract_F64(S8 num1, F64 num2) { return num1 - num2; }
// Function: unsafe_multiply
S16 S8_unsafe_multiply_S8(S8 num1, S8 num2) { return num1 * num2; }
S32 S8_unsafe_multiply_S16(S8 num1, S16 num2) { return num1 * num2; }
S64 S8_unsafe_multiply_S32(S8 num1, S32 num2) { return num1 * num2; }
S64 S8_unsafe_multiply_S64(S8 num1, S64 num2) { return num1 * num2; }
S16 S8_unsafe_multiply_U8(S8 num1, U8 num2) { return num1 * num2; }
S32 S8_unsafe_multiply_U16(S8 num1, U16 num2) { return num1 * num2; }
S64 S8_unsafe_multiply_U32(S8 num1, U32 num2) { return num1 * num2; }
S64 S8_unsafe_multiply_U64(S8 num1, U64 num2) { return num1 * num2; }
F64 S8_unsafe_multiply_F32(S8 num1, F32 num2) { return num1 * num2; }
F64 S8_unsafe_multiply_F64(S8 num1, F64 num2) { return num1 * num2; }
// Function: unsafe_division
S8 S8_unsafe_division_S8(S8 num1, S8 num2) { return num1 / num2; }
S8 S8_unsafe_division_S16(S8 num1, S16 num2) { return num1 / num2; }
S8 S8_unsafe_division_S32(S8 num1, S32 num2) { return num1 / num2; }
S8 S8_unsafe_division_S64(S8 num1, S64 num2) { return num1 / num2; }
S8 S8_unsafe_division_U8(S8 num1, U8 num2) { return num1 / num2; }
S8 S8_unsafe_division_U16(S8 num1, U16 num2) { return num1 / num2; }
S8 S8_unsafe_division_U32(S8 num1, U32 num2) { return num1 / num2; }
S8 S8_unsafe_division_U64(S8 num1, U64 num2) { return num1 / num2; }
F32 S8_unsafe_division_F32(S8 num1, F32 num2) { return num1 / num2; }
F64 S8_unsafe_division_F64(S8 num1, F64 num2) { return num1 / num2; }
// Function: unsafe_modulo (Does not support F32/F64)
S8 S8_unsafe_modulo_S8(S8 num1, S8 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_S16(S8 num1, S16 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_S32(S8 num1, S32 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_S64(S8 num1, S64 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_U8(S8 num1, U8 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_U16(S8 num1, U16 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_U32(S8 num1, U32 num2) { return num1 % num2; }
S8 S8_unsafe_modulo_U64(S8 num1, U64 num2) { return num1 % num2; }
// Function: and (Does not support F32/F64)
S8 S8_and_S8(S8 num1, S8 num2) { return num1 & num2; }
S8 S8_and_S16(S8 num1, S16 num2) { return num1 & num2; }
S8 S8_and_S32(S8 num1, S32 num2) { return num1 & num2; }
S8 S8_and_S64(S8 num1, S64 num2) { return num1 & num2; }
S8 S8_and_U8(S8 num1, U8 num2) { return num1 & num2; }
S8 S8_and_U16(S8 num1, U16 num2) { return num1 & num2; }
S8 S8_and_U32(S8 num1, U32 num2) { return num1 & num2; }
S8 S8_and_U64(S8 num1, U64 num2) { return num1 & num2; }
// Function: or (Does not support F32/F64)
S8 S8_or_S8(S8 num1, S8 num2) { return num1 | num2; }
S16 S8_or_S16(S8 num1, S16 num2) { return num1 | num2; }
S32 S8_or_S32(S8 num1, S32 num2) { return num1 | num2; }
S64 S8_or_S64(S8 num1, S64 num2) { return num1 | num2; }
S8 S8_or_U8(S8 num1, U8 num2) { return num1 | num2; }
S16 S8_or_U16(S8 num1, U16 num2) { return num1 | num2; }
S32 S8_or_U32(S8 num1, U32 num2) { return num1 | num2; }
S64 S8_or_U64(S8 num1, U64 num2) { return num1 | num2; }
// Function: xor (Does not support F32/F64)
S8 S8_xor_S8(S8 num1, S8 num2) { return num1 ^ num2; }
S16 S8_xor_S16(S8 num1, S16 num2) { return num1 ^ num2; }
S32 S8_xor_S32(S8 num1, S32 num2) { return num1 ^ num2; }
S64 S8_xor_S64(S8 num1, S64 num2) { return num1 ^ num2; }
S8 S8_xor_U8(S8 num1, U8 num2) { return num1 ^ num2; }
S16 S8_xor_U16(S8 num1, U16 num2) { return num1 ^ num2; }
S32 S8_xor_U32(S8 num1, U32 num2) { return num1 ^ num2; }
S64 S8_xor_U64(S8 num1, U64 num2) { return num1 ^ num2; }

#endif // ASL_S8_H