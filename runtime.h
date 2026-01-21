#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/** NOTE: Needed for UNREACHABLE Macro */
#if __STDC_VERSION__ >= 202311L
// Using C23 unreachable()
#include <stddef.h>
#define UNREACHABLE() unreachable()
#elif defined(__GNUC__) || defined(__clang__)
// Using compiler-specific built-ins
#define UNREACHABLE() __builtin_unreachable()
#elif defined(_MSC_VER)
// Using compiler-specific built-ins
#define UNREACHABLE() __assume(0)
#else
// Fallback - abort or trigger undefined behavior
#define UNREACHABLE() abort()
#endif

/** NOTE: Type definitions for Native C types */
typedef int8_t S8;
typedef int16_t S16;
typedef int32_t S32;
typedef int64_t S64;
typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;
typedef float F32;
typedef double F64;
typedef char *String;
typedef void *Pointer;
