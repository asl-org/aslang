#include <stdint.h>
#include <string.h>

/* unsigned int types */
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

/* integer types */
// typedef int int;
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

/* float types */
typedef float f32;
typedef double f64;

/* char types */
// typedef char char;
typedef unsigned char uchar;

/* pointer type */
typedef void *pointer;

/* value type */
typedef struct
{
  u8 id;
  union
  {
    u8 u8_val;
    u16 u16_val;
    u32 u32_val;
    u64 u64_val;

    i8 i8_val;
    i16 i16_val;
    i32 i32_val;
    i64 i64_val;
    int int_val;

    f32 f32_val;
    f64 f64_val;

    char char_val;
    uchar uchar_val;

    pointer pointer_val;
  } data;
} value;

#define DEFINE_VALUE_INIT(TYPE, ID) \
  value value_init_##TYPE(TYPE val) \
  {                                 \
    value result;                   \
    result.id = ID;                 \
    result.data.TYPE##_val = val;   \
    return result;                  \
  }

DEFINE_VALUE_INIT(u8, 0);
DEFINE_VALUE_INIT(u16, 1);
DEFINE_VALUE_INIT(u32, 2);
DEFINE_VALUE_INIT(u64, 3);
DEFINE_VALUE_INIT(i8, 4);
DEFINE_VALUE_INIT(i16, 5);
DEFINE_VALUE_INIT(i32, 6);
DEFINE_VALUE_INIT(i64, 7);
DEFINE_VALUE_INIT(int, 8);
DEFINE_VALUE_INIT(f32, 9);
DEFINE_VALUE_INIT(f64, 10);
DEFINE_VALUE_INIT(char, 11);
DEFINE_VALUE_INIT(uchar, 12);
DEFINE_VALUE_INIT(pointer, 13);

#undef DEFINE_VALUE_INIT

/* string type */
typedef struct
{
  u64 size;
  pointer ptr;
} string;

string string_init(const char *ptr)
{
  string str;
  str.size = (u64)strlen(ptr);
  str.ptr = (pointer)ptr;
  return str;
}

/* error type */
typedef struct
{
  i64 code;
  string message;
} error;

error error_init(i64 code, string message)
{
  error err;
  err.code = code;
  err.message = message;
  return err;
}

/* status type */
typedef struct
{
  u8 id;
  union
  {
    error err;
    value val;
  } data;
} status;

#define DEFINE_STATUS_INIT(TYPE, NAME, ID) \
  status status_init_##TYPE(TYPE NAME)     \
  {                                        \
    status st;                             \
    st.id = ID;                            \
    st.data.NAME = NAME;                   \
    return st;                             \
  }

DEFINE_STATUS_INIT(value, val, 0);
DEFINE_STATUS_INIT(error, err, 1);

#undef DEFINE_STATUS_INIT