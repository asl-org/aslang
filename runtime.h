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

typedef const char *string;