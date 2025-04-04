#ifndef ASL_H
#define ASL_H

#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>

// Integer type aliases
typedef int8_t s8;
typedef int16_t s16;
typedef int32_t s32;
typedef int64_t s64;

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

// Floating-point type aliases
typedef float f32;
typedef double f64;

// C specific type aliases
typedef char c_char;
typedef int c_int;

s32 print_s8(s8 num) { return printf("%" PRId8 "\n", num); }
s32 print_s16(s16 num) { return printf("%" PRId16 "\n", num); }
s32 print_s32(s32 num) { return printf("%" PRId32 "\n", num); }
s32 print_s64(s64 num) { return printf("%" PRId64 "\n", num); }
s32 print_u8(u8 num) { return printf("%" PRIu8 "\n", num); }
s32 print_u16(u16 num) { return printf("%" PRIu16 "\n", num); }
s32 print_u32(u32 num) { return printf("%" PRIu32 "\n", num); }
s32 print_u64(u64 num) { return printf("%" PRIu64 "\n", num); }
s32 print_f32(f32 num) { return printf("%f\n", num); }
s32 print_f64(f64 num) { return printf("%lf\n", num); }

#endif // ASL_H
