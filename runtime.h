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

/** NOTE: System calls fall under System module */
Pointer System_allocate(U64 bytes)
{
  Pointer ptr = malloc(bytes);
  memset(ptr, 0, bytes);
  return ptr;
}

U64 System_free(Pointer ptr)
{
  U64 size = sizeof(ptr);
  free(ptr);
  return size;
}

/** NOTE: Macro for generating System_print_{Type} function for Native Types.
 *
 * U64 System_print_U8(U8 value) {
 *    return printf("%u\n", value);
 * }
 *
 */

#define PRINT(TYPE, SPEC)             \
  U64 System_print_##TYPE(TYPE value) \
  {                                   \
    return printf(SPEC, value);       \
  }

PRINT(U8, "%hhu\n")
PRINT(U16, "%hu\n")
PRINT(U32, "%u\n")
PRINT(U64, "%llu\n")
PRINT(S8, "%hhd\n")
PRINT(S16, "%hd\n")
PRINT(S32, "%d\n")
PRINT(S64, "%lld\n")
PRINT(F32, "%f\n")
PRINT(F64, "%lf\n")
PRINT(String, "%s\n")

#undef PRINT

/** NOTE: Macro for generating {Type}_byte_size function for Native Types.
 *
 * U64 U8_byte_size(U64 items) {
 *    return items * sizeof(U8);
 * }
 *
 */
#define BYTE_SIZE(TYPE)           \
  U64 TYPE##_byte_size(U64 items) \
  {                               \
    return items * sizeof(TYPE);  \
  }

/** NOTE: Macro for generating {Type}_read function for Native Types.
 *
 * U8 U8_read(Pointer ptr, U64 offset) {
 *    return *((U8 *)(ptr + offset));
 * }
 *
 */
#define POINTER_READ(TYPE)                  \
  TYPE TYPE##_read(Pointer ptr, U64 offset) \
  {                                         \
    return *((TYPE *)(ptr + offset));       \
  }

/** NOTE: Macro for generating {Type}_write function for Native Types.
 *
 *  Pointer U8_write(U8 value, Pointer ptr, U64 offset) {
 *    *((U8 *)(ptr + offset)) = value;
 *    return ptr;
 * }
 *
 */
#define POINTER_WRITE(TYPE)                                 \
  Pointer TYPE##_write(TYPE value, Pointer ptr, U64 offset) \
  {                                                         \
    *((TYPE *)(ptr + offset)) = value;                      \
    return ptr;                                             \
  }

/** NOTE: Macro for generating System_box_{Type} function for Native Types.
 *
 *  Pointer System_box_U8(U8 value) {
 *    U64 bytes = U8_byte_size(1);
 *    Pointer ptr = System_allocate(bytes);
 *    return U8_write(value, ptr, 0);
 *  }
 *
 */
#define BOX_POINTER(TYPE)                 \
  Pointer System_box_##TYPE(TYPE value)   \
  {                                       \
    U64 bytes = TYPE##_byte_size(1);      \
    Pointer ptr = System_allocate(bytes); \
    return TYPE##_write(value, ptr, 0);   \
  }

#define BASIC_OPS(TYPE) \
  BYTE_SIZE(TYPE);      \
  POINTER_READ(TYPE);   \
  POINTER_WRITE(TYPE);  \
  BOX_POINTER(TYPE);

BASIC_OPS(U8)
BASIC_OPS(U16)
BASIC_OPS(U32)
BASIC_OPS(U64)
BASIC_OPS(S8)
BASIC_OPS(S16)
BASIC_OPS(S32)
BASIC_OPS(S64)
BASIC_OPS(F32)
BASIC_OPS(F64)
BASIC_OPS(String)
BASIC_OPS(Pointer)

#undef BASIC_OPS
#undef BOX
#undef BYTE_SIZE
#undef POINTER_READ
#undef POINTER_WRITE

U8 U8_and_U8(U8 x, U8 y)
{
  return x & y;
}

U8 U8_or_U8(U8 x, U8 y)
{
  return x | y;
}

U8 U8_not(U8 x)
{
  return ~x;
}

U8 U8_lshift_U8(U8 x, U64 y)
{
  return x << y;
}

U8 U8_rshift_U8(U8 x, U64 y)
{
  return x >> y;
}

S8 U64_compare_U64(U64 x, U64 y)
{
  return (x < y) ? -1 : (x > y ? 1 : 0);
}

U64 U64_add_U64(U64 x, U64 y)
{
  return x + y;
}

U64 U64_subtract_U64(U64 x, U64 y)
{
  return x - y;
}

U64 U64_multiply_U64(U64 x, U64 y)
{
  return x * y;
}

U64 U64_quotient_U64(U64 x, U64 y)
{
  return x / y;
}

U64 U64_remainder_U64(U64 x, U64 y)
{
  return x % y;
}

S64 S64_add_S64(S64 x, S64 y)
{
  return x + y;
}

S64 S64_subtract_S64(S64 x, S64 y)
{
  return x - y;
}

S64 S64_multiply_S64(S64 x, S64 y)
{
  return x * y;
}

S64 S64_quotient_S64(S64 x, S64 y)
{
  return x / y;
}

S64 S64_remainder_S64(S64 x, S64 y)
{
  return x % y;
}

S8 S64_compare_S64(S64 x, S64 y)
{
  return (x < y) ? -1 : (x > y ? 1 : 0);
}

S64 S64_from_U8(U8 x)
{
  return (S64)x;
}