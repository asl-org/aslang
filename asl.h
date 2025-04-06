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

#endif // ASL_H
