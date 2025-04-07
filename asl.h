#ifndef ASL_H
#define ASL_H

#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>

// Integer type aliases
typedef int8_t S8;
typedef int16_t S16;
typedef int32_t S32;
typedef int64_t S64;

typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;

// Floating-point type aliases
typedef float F32;
typedef double F64;

// C specific type aliases
typedef char c_char;
typedef int c_int;

// Note : functions having `unsafe` in their name may cause inmom.
S32 S8_unsafe_print(S8 num) { return printf("%" PRId8 "\n", num); }
S32 S16_unsafe_print(S16 num) { return printf("%" PRId16 "\n", num); }
S32 S32_unsafe_print(S32 num) { return printf("%" PRId32 "\n", num); }
S32 S64_unsafe_print(S64 num) { return printf("%" PRId64 "\n", num); }
S32 U8_unsafe_print(U8 num) { return printf("%" PRIu8 "\n", num); }
S32 U16_unsafe_print(U16 num) { return printf("%" PRIu16 "\n", num); }
S32 U32_unsafe_print(U32 num) { return printf("%" PRIu32 "\n", num); }
S32 U64_unsafe_print(U64 num) { return printf("%" PRIu64 "\n", num); }
S32 F32_unsafe_print(F32 num) { return printf("%f\n", num); }
S32 F64_unsafe_print(F64 num) { return printf("%lf\n", num); }

// Module: S8
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

// Module: S16
S16 S16_unsafe_add_S8(S16 num1, S8 num2) { return num1 + num2; }
S16 S16_unsafe_add_S16(S16 num1, S16 num2) { return num1 + num2; }
S32 S16_unsafe_add_S32(S16 num1, S32 num2) { return num1 + num2; }
S64 S16_unsafe_add_S64(S16 num1, S64 num2) { return num1 + num2; }
S16 S16_unsafe_add_U8(S16 num1, U8 num2) { return num1 + num2; }
S16 S16_unsafe_add_U16(S16 num1, U16 num2) { return num1 + num2; }
S32 S16_unsafe_add_U32(S16 num1, U32 num2) { return num1 + num2; }
S64 S16_unsafe_add_U64(S16 num1, U64 num2) { return num1 + num2; }
F32 S16_unsafe_add_F32(S16 num1, F32 num2) { return num1 + num2; }
F64 S16_unsafe_add_F64(S16 num1, F64 num2) { return num1 + num2; }

// Module: S32
S32 S32_unsafe_add_S8(S32 num1, S8 num2) { return num1 + num2; }
S32 S32_unsafe_add_S16(S32 num1, S16 num2) { return num1 + num2; }
S32 S32_unsafe_add_S32(S32 num1, S32 num2) { return num1 + num2; }
S64 S32_unsafe_add_S64(S32 num1, S64 num2) { return num1 + num2; }
S32 S32_unsafe_add_U8(S32 num1, U8 num2) { return num1 + num2; }
S32 S32_unsafe_add_U16(S32 num1, U16 num2) { return num1 + num2; }
S32 S32_unsafe_add_U32(S32 num1, U32 num2) { return num1 + num2; }
S64 S32_unsafe_add_U64(S32 num1, U64 num2) { return num1 + num2; }
F32 S32_unsafe_add_F32(S32 num1, F32 num2) { return num1 + num2; }
F64 S32_unsafe_add_F64(S32 num1, F64 num2) { return num1 + num2; }

// Module: S64
S64 S64_unsafe_add_S8(S64 num1, S8 num2) { return num1 + num2; }
S64 S64_unsafe_add_S16(S64 num1, S16 num2) { return num1 + num2; }
S64 S64_unsafe_add_S32(S64 num1, S32 num2) { return num1 + num2; }
S64 S64_unsafe_add_S64(S64 num1, S64 num2) { return num1 + num2; }
S64 S64_unsafe_add_U8(S64 num1, U8 num2) { return num1 + num2; }
S64 S64_unsafe_add_U16(S64 num1, U16 num2) { return num1 + num2; }
S64 S64_unsafe_add_U32(S64 num1, U32 num2) { return num1 + num2; }
S64 S64_unsafe_add_U64(S64 num1, U64 num2) { return num1 + num2; }
F64 S64_unsafe_add_F32(S64 num1, F32 num2) { return num1 + num2; }
F64 S64_unsafe_add_F64(S64 num1, F64 num2) { return num1 + num2; }

// Module: U8
S8 U8_unsafe_add_S8(U8 num1, S8 num2) { return num1 + num2; }
S16 U8_unsafe_add_S16(U8 num1, S16 num2) { return num1 + num2; }
S32 U8_unsafe_add_S32(U8 num1, S32 num2) { return num1 + num2; }
S64 U8_unsafe_add_S64(U8 num1, S64 num2) { return num1 + num2; }
U8 U8_unsafe_add_U8(U8 num1, U8 num2) { return num1 + num2; }
U16 U8_unsafe_add_U16(U8 num1, U16 num2) { return num1 + num2; }
U32 U8_unsafe_add_U32(U8 num1, U32 num2) { return num1 + num2; }
U64 U8_unsafe_add_U64(U8 num1, U64 num2) { return num1 + num2; }
F32 U8_unsafe_add_F32(U8 num1, F32 num2) { return num1 + num2; }
F64 U8_unsafe_add_F64(U8 num1, F64 num2) { return num1 + num2; }

// Module: U16
S16 U16_unsafe_add_S8(U16 num1, S8 num2) { return num1 + num2; }
S16 U16_unsafe_add_S16(U16 num1, S16 num2) { return num1 + num2; }
S32 U16_unsafe_add_S32(U16 num1, S32 num2) { return num1 + num2; }
S64 U16_unsafe_add_S64(U16 num1, S64 num2) { return num1 + num2; }
U16 U16_unsafe_add_U8(U16 num1, U8 num2) { return num1 + num2; }
U16 U16_unsafe_add_U16(U16 num1, U16 num2) { return num1 + num2; }
U32 U16_unsafe_add_U32(U16 num1, U32 num2) { return num1 + num2; }
U64 U16_unsafe_add_U64(U16 num1, U64 num2) { return num1 + num2; }
F32 U16_unsafe_add_F32(U16 num1, F32 num2) { return num1 + num2; }
F64 U16_unsafe_add_F64(U16 num1, F64 num2) { return num1 + num2; }

// Module: U32
S32 U32_unsafe_add_S8(U32 num1, S8 num2) { return num1 + num2; }
S32 U32_unsafe_add_S16(U32 num1, S16 num2) { return num1 + num2; }
S32 U32_unsafe_add_S32(U32 num1, S32 num2) { return num1 + num2; }
S64 U32_unsafe_add_S64(U32 num1, S64 num2) { return num1 + num2; }
U32 U32_unsafe_add_U8(U32 num1, U8 num2) { return num1 + num2; }
U32 U32_unsafe_add_U16(U32 num1, U16 num2) { return num1 + num2; }
U32 U32_unsafe_add_U32(U32 num1, U32 num2) { return num1 + num2; }
U64 U32_unsafe_add_U64(U32 num1, U64 num2) { return num1 + num2; }
F32 U32_unsafe_add_F32(U32 num1, F32 num2) { return num1 + num2; }
F64 U32_unsafe_add_F64(U32 num1, F64 num2) { return num1 + num2; }

// Module: U64
S64 U64_unsafe_add_S8(U64 num1, S8 num2) { return num1 + num2; }
S64 U64_unsafe_add_S16(U64 num1, S16 num2) { return num1 + num2; }
S64 U64_unsafe_add_S32(U64 num1, S32 num2) { return num1 + num2; }
S64 U64_unsafe_add_S64(U64 num1, S64 num2) { return num1 + num2; }
U64 U64_unsafe_add_U8(U64 num1, U8 num2) { return num1 + num2; }
U64 U64_unsafe_add_U16(U64 num1, U16 num2) { return num1 + num2; }
U64 U64_unsafe_add_U32(U64 num1, U32 num2) { return num1 + num2; }
U64 U64_unsafe_add_U64(U64 num1, U64 num2) { return num1 + num2; }
F64 U64_unsafe_add_F32(U64 num1, F32 num2) { return num1 + num2; }
F64 U64_unsafe_add_F64(U64 num1, F64 num2) { return num1 + num2; }

// Module: F32
F32 F32_unsafe_add_S8(F32 num1, S8 num2) { return num1 + num2; }
F32 F32_unsafe_add_S16(F32 num1, S16 num2) { return num1 + num2; }
F32 F32_unsafe_add_S32(F32 num1, S32 num2) { return num1 + num2; }
F64 F32_unsafe_add_S64(F32 num1, S64 num2) { return num1 + num2; }
F32 F32_unsafe_add_U8(F32 num1, U8 num2) { return num1 + num2; }
F32 F32_unsafe_add_U16(F32 num1, U16 num2) { return num1 + num2; }
F32 F32_unsafe_add_U32(F32 num1, U32 num2) { return num1 + num2; }
F64 F32_unsafe_add_U64(F32 num1, U64 num2) { return num1 + num2; }
F32 F32_unsafe_add_F32(F32 num1, F32 num2) { return num1 + num2; }
F64 F32_unsafe_add_F64(F32 num1, F64 num2) { return num1 + num2; }

// Module: F64
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

#endif // ASL_H
