#include <stdint.h>
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
  return malloc(bytes);
}

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