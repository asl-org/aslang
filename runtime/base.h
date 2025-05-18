#ifndef ASL_BASE_H
#define ASL_BASE_H

#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>

// Integer type aliases
typedef uint8_t U8;
typedef uint64_t U64;
typedef int64_t S64;

// Pointer type
typedef uintptr_t Pointer;

// Floating-point type aliases
typedef float F32;
typedef double F64;

// C specific type aliases
typedef char c_char;
typedef int c_int;

#ifdef __GNUC__
#define UNREACHABLE() __builtin_unreachable()
#elif defined(_MSC_VER)
#define UNREACHABLE() __assume(0)
#else
#include <stdlib.h>
#define UNREACHABLE() abort()
#endif

#endif // ASL_BASE_H