#ifndef ASL_S64_H
#define ASL_S64_H

#include "base.h"

// Module: S64

// Function: unsafe_print
S64 S64_unsafe_print(S64 num) { return printf("%" PRId64 "\n", num); }

// Function: unsafe_add
S64 S64_unsafe_add(S64 num1, S64 num2) { return num1 + num2; }

// Function: unsafe_from
F64 S64_unsafe_from(S64 num) { return num; }

// Function: not
S64 S64_not(S64 num) { return ~num; }

// Function: or
S64 S64_or(S64 num1, S64 num2) { return num1 | num2; }

// Function: and
S64 S64_and(S64 num1, S64 num2) { return num1 & num2; }

// Function: xor
S64 S64_xor(S64 num1, S64 num2) { return num1 ^ num2; }

// Function: lshift
S64 S64_lshift(S64 num, S64 bits) { return num << bits; }

// Function: rshift
S64 S64_rshift(S64 num, S64 bits) { return num >> bits; }

// Function: unsafe_add
// S64 S64_unsafe_add_S8(S64 num1, S8 num2) { return num1 + num2; }
// S64 S64_unsafe_add_S16(S64 num1, S16 num2) { return num1 + num2; }
// S64 S64_unsafe_add_S32(S64 num1, S32 num2) { return num1 + num2; }
// S64 S64_unsafe_add_S64(S64 num1, S64 num2) { return num1 + num2; }
// S64 S64_unsafe_add_U8(S64 num1, U8 num2) { return num1 + num2; }
// S64 S64_unsafe_add_U16(S64 num1, U16 num2) { return num1 + num2; }
// S64 S64_unsafe_add_U32(S64 num1, U32 num2) { return num1 + num2; }
// S64 S64_unsafe_add_U64(S64 num1, U64 num2) { return num1 + num2; }
// F64 S64_unsafe_add_F32(S64 num1, F32 num2) { return num1 + num2; }
// F64 S64_unsafe_add_F64(S64 num1, F64 num2) { return num1 + num2; }
// Function: unsafe_subtract
// S64 S64_unsafe_subtract_S8(S64 num1, S8 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_S16(S64 num1, S16 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_S32(S64 num1, S32 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_S64(S64 num1, S64 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_U8(S64 num1, U8 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_U16(S64 num1, U16 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_U32(S64 num1, U32 num2) { return num1 - num2; }
// S64 S64_unsafe_subtract_U64(S64 num1, U64 num2) { return num1 - num2; }
// F64 S64_unsafe_subtract_F32(S64 num1, F32 num2) { return num1 - num2; }
// F64 S64_unsafe_subtract_F64(S64 num1, F64 num2) { return num1 - num2; }
// Function: unsafe_multiply
// S64 S64_unsafe_multiply_S8(S64 num1, S8 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_S16(S64 num1, S16 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_S32(S64 num1, S32 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_S64(S64 num1, S64 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_U8(S64 num1, U8 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_U16(S64 num1, U16 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_U32(S64 num1, U32 num2) { return num1 * num2; }
// S64 S64_unsafe_multiply_U64(S64 num1, U64 num2) { return num1 * num2; }
// F64 S64_unsafe_multiply_F32(S64 num1, F32 num2) { return num1 * num2; }
// F64 S64_unsafe_multiply_F64(S64 num1, F64 num2) { return num1 * num2; }
// Function: unsafe_division
// S64 S64_unsafe_division_S8(S64 num1, S8 num2) { return num1 / num2; }
// S64 S64_unsafe_division_S16(S64 num1, S16 num2) { return num1 / num2; }
// S64 S64_unsafe_division_S32(S64 num1, S32 num2) { return num1 / num2; }
// S64 S64_unsafe_division_S64(S64 num1, S64 num2) { return num1 / num2; }
// S64 S64_unsafe_division_U8(S64 num1, U8 num2) { return num1 / num2; }
// S64 S64_unsafe_division_U16(S64 num1, U16 num2) { return num1 / num2; }
// S64 S64_unsafe_division_U32(S64 num1, U32 num2) { return num1 / num2; }
// S64 S64_unsafe_division_U64(S64 num1, U64 num2) { return num1 / num2; }
// F64 S64_unsafe_division_F32(S64 num1, F32 num2) { return num1 / num2; }
// F64 S64_unsafe_division_F64(S64 num1, F64 num2) { return num1 / num2; }
// Function: unsafe_modulo (Does not support F32/F64)
// S8 S64_unsafe_modulo_S8(S64 num1, S8 num2) { return num1 % num2; }
// S16 S64_unsafe_modulo_S16(S64 num1, S16 num2) { return num1 % num2; }
// S32 S64_unsafe_modulo_S32(S64 num1, S32 num2) { return num1 % num2; }
// S64 S64_unsafe_modulo_S64(S64 num1, S64 num2) { return num1 % num2; }
// S8 S64_unsafe_modulo_U8(S64 num1, U8 num2) { return num1 % num2; }
// S16 S64_unsafe_modulo_U16(S64 num1, U16 num2) { return num1 % num2; }
// S32 S64_unsafe_modulo_U32(S64 num1, U32 num2) { return num1 % num2; }
// S64 S64_unsafe_modulo_U64(S64 num1, U64 num2) { return num1 % num2; }
// Function: and (Does not support F32/F64)
// S8 S64_and_S8(S64 num1, S8 num2) { return num1 & num2; }
// S16 S64_and_S16(S64 num1, S16 num2) { return num1 & num2; }
// S32 S64_and_S32(S64 num1, S32 num2) { return num1 & num2; }
// S64 S64_and_S64(S64 num1, S64 num2) { return num1 & num2; }
// S8 S64_and_U8(S64 num1, U8 num2) { return num1 & num2; }
// S16 S64_and_U16(S64 num1, U16 num2) { return num1 & num2; }
// S32 S64_and_U32(S64 num1, U32 num2) { return num1 & num2; }
// S64 S64_and_U64(S64 num1, U64 num2) { return num1 & num2; }
// Function: or (Does not support F32/F64)
// S64 S64_or_S8(S64 num1, S8 num2) { return num1 | num2; }
// S64 S64_or_S16(S64 num1, S16 num2) { return num1 | num2; }
// S64 S64_or_S32(S64 num1, S32 num2) { return num1 | num2; }
// S64 S64_or_S64(S64 num1, S64 num2) { return num1 | num2; }
// S64 S64_or_U8(S64 num1, U8 num2) { return num1 | num2; }
// S64 S64_or_U16(S64 num1, U16 num2) { return num1 | num2; }
// S64 S64_or_U32(S64 num1, U32 num2) { return num1 | num2; }
// S64 S64_or_U64(S64 num1, U64 num2) { return num1 | num2; }
// Function: xor (Does not support F32/F64)
// S64 S64_xor_S8(S64 num1, S8 num2) { return num1 ^ num2; }
// S64 S64_xor_S16(S64 num1, S16 num2) { return num1 ^ num2; }
// S64 S64_xor_S32(S64 num1, S32 num2) { return num1 ^ num2; }
// S64 S64_xor_S64(S64 num1, S64 num2) { return num1 ^ num2; }
// S64 S64_xor_U8(S64 num1, U8 num2) { return num1 ^ num2; }
// S64 S64_xor_U16(S64 num1, U16 num2) { return num1 ^ num2; }
// S64 S64_xor_U32(S64 num1, U32 num2) { return num1 ^ num2; }
// S64 S64_xor_U64(S64 num1, U64 num2) { return num1 ^ num2; }
// Function: not
// S64 S64_not(S64 num) { return ~num; }

#endif // ASL_S64_H