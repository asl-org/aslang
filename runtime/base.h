#ifndef ASL_BASE_H
#define ASL_BASE_H

#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>

// Signed Integer type aliases
typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;

// Unsigned Integer type aliases
typedef int8_t S8;
typedef int16_t S16;
typedef int32_t S32;
typedef int64_t S64;

// Floating-point type aliases
typedef float F32;
typedef double F64;

// Pointer type
typedef uintptr_t Pointer;

// C specific type aliases
typedef unsigned char UChar;
typedef char Char;
typedef int CInt;

#ifdef __GNUC__
#define UNREACHABLE() __builtin_unreachable()
#elif defined(_MSC_VER)
#define UNREACHABLE() __assume(0)
#else
#include <stdlib.h>
#define UNREACHABLE() abort()
#endif

#endif // ASL_BASE_H