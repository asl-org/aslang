#include "runtime.h"

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

U8 U8_lshift_U8(U8 x, U8 y)
{
  return x << y;
}

U8 U8_rshift_U8(U8 x, U8 y)
{
  return x >> y;
}

U8 U8_subtract_U8(U8 x, U8 y)
{
  return x - y;
}

U64 U64_lshift_U64(U64 x, U64 y)
{
  return x << y;
}

U64 U64_rshift_U64(U64 x, U64 y)
{
  return x >> y;
}

U64 U64_and_U64(U64 x, U64 y)
{
  return x & y;
}

U64 U64_or_U64(U64 x, U64 y)
{
  return x | y;
}

U64 U64_not(U64 x)
{
  return ~x;
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
U64 U64_from_U8(U8 x)
{
  return (U64)x;
}

U8 U8_from_U64(U64 x)
{
  return (U8)x;
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

S64 S64_from_U64(U64 x)
{
  return (S64)x;
}

S32 ASL_Error_get_code(Pointer error)
{
  return S32_read(error, 0);
}

Pointer ASL_Error_set_code(Pointer error, S32 code)
{
  return S32_write(code, error, 0);
}

String ASL_Error_get_message(Pointer error)
{
  return String_read(error, 4);
}

Pointer ASL_Error_set_message(Pointer error, String message)
{
  return String_write(message, error, 4);
}

Pointer ASL_Error_init(S32 code, String message)
{
  Pointer ptr = System_allocate(12);
  ptr = ASL_Error_set_code(ptr, code);
  ptr = ASL_Error_set_message(ptr, message);
  return ptr;
}

U64 ASL_Status_get_id(Pointer status)
{
  return U64_read(status, 0);
}

Pointer ASL_Status_set_id(Pointer status, U64 id)
{
  return U64_write(id, status, 0);
}

Pointer ASL_Status_Ok_get_value(Pointer status)
{
  return Pointer_read(status, 8);
}

Pointer ASL_Status_Ok_set_value(Pointer status, Pointer value)
{
  return Pointer_write(value, status, 8);
}

Pointer ASL_Status_Ok_init(Pointer value)
{
  Pointer ptr = System_allocate(16);
  ptr = ASL_Status_set_id(ptr, 0);
  ptr = ASL_Status_Ok_set_value(ptr, value);
  return ptr;
}

Pointer ASL_Status_Err_get_error(Pointer status)
{
  return Pointer_read(status, 8);
}

Pointer ASL_Status_Err_set_error(Pointer status, Pointer error)
{
  return Pointer_write(error, status, 8);
}

Pointer ASL_Status_Err_init(Pointer error)
{

  Pointer ptr = System_allocate(16);
  ptr = ASL_Status_set_id(ptr, 1);
  ptr = ASL_Status_Err_set_error(ptr, error);
  return ptr;
}

U64 byte_size(U64 impl_id)
{
  switch (impl_id)
  {
  case 0:
    return 1; // S8
  case 1:
    return 2; // S16
  case 2:
    return 3; // S32
  case 3:
    return 4; // S64
  case 4:
    return 1; // U8
  case 5:
    return 2; // U16
  case 6:
    return 3; // U32
  case 7:
    return 4; // U64
  case 8:
    return 3; // F32
  case 9:
    return 4; // F64
  default:
    return 4; // Pointer types
  }
  UNREACHABLE();
}

Pointer byte_read(U64 impl_id, Pointer data, U64 offset)
{
  switch (impl_id)
  {
  case 0:
    return System_box_S8(S8_read(data, offset)); // S8
  case 1:
    return System_box_S16(S16_read(data, offset)); // S16
  case 2:
    return System_box_S32(S32_read(data, offset)); // S32
  case 3:
    return System_box_S64(S64_read(data, offset)); // S64
  case 4:
    return System_box_U8(U8_read(data, offset)); // U8
  case 5:
    return System_box_U16(U16_read(data, offset)); // U16
  case 6:
    return System_box_U32(U32_read(data, offset)); // U32
  case 7:
    return System_box_U64(U64_read(data, offset)); // U64
  case 8:
    return System_box_F32(F32_read(data, offset)); // F32
  case 9:
    return System_box_F64(F64_read(data, offset)); // F64
  default:
    return System_box_Pointer(Pointer_read(data, offset)); // Pointer types
  }
  UNREACHABLE();
}

Pointer byte_write(U64 impl_id, Pointer data, U64 offset, Pointer value)
{
  switch (impl_id)
  {
  case 0:
    return S8_write(S8_read(value, 0), data, offset); // S8
  case 1:
    return S16_write(S16_read(value, 0), data, offset); // S16
  case 2:
    return S32_write(S32_read(value, 0), data, offset); // S32
  case 3:
    return S64_write(S64_read(value, 0), data, offset); // S64
  case 4:
    return U8_write(U8_read(value, 0), data, offset); // U8
  case 5:
    return U16_write(U16_read(value, 0), data, offset); // U16
  case 6:
    return U32_write(U32_read(value, 0), data, offset); // U32
  case 7:
    return U64_write(U64_read(value, 0), data, offset); // U64
  case 8:
    return F32_write(F32_read(value, 0), data, offset); // F32
  case 9:
    return F64_write(F64_read(value, 0), data, offset); // F64
  default:
    return Pointer_write(Pointer_read(value, 0), data, offset); // Pointer types
  }
  UNREACHABLE();
}

Pointer String_get(String str, U64 index)
{
  if (index >= strlen(str))
  {
    Pointer err = ASL_Error_init(1, "Index out of Bounds");
    Pointer status = ASL_Status_Err_init(err);
    return status;
  }

  U64 impl_id = 4; // U8 impl_id
  U64 offset = index * byte_size(impl_id);
  Pointer value = byte_read(impl_id, (Pointer)str, offset);

  Pointer status = ASL_Status_Ok_init(value);
  return status;
}

U64 ASL_Array_get_size(Pointer ptr)
{
  return U64_read(ptr, 0);
}

Pointer ASL_Array_set_size(Pointer ptr, U64 size)
{
  return U64_write(size, ptr, 0);
}

Pointer Array_get_data(Pointer ptr)
{
  return Pointer_read(ptr, 8);
}

Pointer Array_set_data(Pointer ptr, Pointer data)
{
  return Pointer_write(data, ptr, 8);
}

Pointer Array_init(U64 impl_id, U64 size)
{
  Pointer ptr = System_allocate(16); // U64 size + Pointer data
  ptr = ASL_Array_set_size(ptr, size);

  U64 bytes = size * byte_size(impl_id);
  Pointer data = System_allocate(bytes);
  ptr = Array_set_data(ptr, data);

  return ptr;
}

Pointer Array_get(U64 impl_id, Pointer arr, U64 index)
{
  if (index >= ASL_Array_get_size(arr))
  {
    Pointer err = ASL_Error_init(1, "Index out of Bounds");
    Pointer status = ASL_Status_Err_init(err);
    return status;
  }

  U64 offset = index * byte_size(impl_id);
  Pointer data = Array_get_data(arr);
  Pointer value = byte_read(impl_id, data, offset);

  Pointer status = ASL_Status_Ok_init(value);
  return status;
}

Pointer Array_set(U64 impl_id, Pointer arr, U64 index, Pointer value)
{
  if (index >= ASL_Array_get_size(arr))
  {
    Pointer err = ASL_Error_init(1, "Index out of Bounds");
    Pointer status = ASL_Status_Err_init(err);
    return status;
  }

  U64 offset = index * byte_size(impl_id);
  Pointer data = Array_get_data(arr);
  data = byte_write(impl_id, data, offset, value);

  Pointer status = ASL_Status_Ok_init(data);
  return status;
}