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

// Signed Integer
typedef enum
{
  SIT_8,
  SIT_16,
  SIT_32,
  SIT_64,
} SignedIntegerType;

typedef union
{
  s8 a;
  s16 b;
  s32 c;
  s64 d;
} SignedIntegerData;

typedef struct
{
  SignedIntegerType type;
  SignedIntegerData data;
} SignedInteger;

// Unsigned Integer
typedef enum
{
  UIT_8,
  UIT_16,
  UIT_32,
  UIT_64,
} UnsignedIntegerType;

typedef union
{
  u8 a;
  u16 b;
  u32 c;
  u64 d;
} UnsignedIntegerData;

typedef struct
{
  UnsignedIntegerType type;
  UnsignedIntegerData data;
} UnsignedInteger;

// Integer
typedef enum
{
  IT_SIGNED,
  IT_UNSIGNED,
} IntegerType;

typedef union
{
  SignedInteger a;
  UnsignedInteger b;
} IntegerData;

typedef struct
{
  IntegerType type;
  IntegerData data;
} Integer;

// Float
typedef enum
{
  FT_32,
  FT_64,
} FloatType;

typedef union
{
  f32 a;
  f64 b;
} FloatData;

typedef struct
{
  FloatType type;
  FloatData data;
} Float;

// Number
typedef enum
{
  NT_INTEGER,
  NT_FLOAT,
} NumberType;

typedef union
{
  Integer a;
  Float b;
} NumberData;

typedef struct
{
  NumberType type;
  NumberData data;
} Number;

typedef enum
{
  AT_U8 = 1,  // 1 byte
  AT_U16 = 2, // 2 bytes
  AT_U32 = 4, // 4 bytes
  AT_U64 = 8, // 8 bytes
  AT_S8 = 1,  // 1 byte
  AT_S16 = 2, // 2 bytes
  AT_S32 = 4, // 4 bytes
  AT_S64 = 8, // 8 bytes
  AT_F32 = 4, // 4 bytes
  AT_F64 = 8, // 8 bytes
} ArrayType;

typedef struct
{
  ArrayType type;
  void *data;
  u64 length;
} Array;

static SignedInteger new_signed_integer(SignedIntegerType type, SignedIntegerData data)
{
  SignedInteger result = {.type = type, .data = data};
  return result;
}

static UnsignedInteger new_unsigned_integer(UnsignedIntegerType type, UnsignedIntegerData data)
{
  UnsignedInteger result = {.type = type, .data = data};
  return result;
}

static Integer new_integer(IntegerType type, IntegerData data)
{
  Integer result = {.type = type, .data = data};
  return result;
}

static Integer signed_integer_as_integer(SignedInteger si)
{
  IntegerData id = {.a = si};
  return new_integer(IT_SIGNED, id);
}

static Integer unsigned_integer_as_integer(UnsignedInteger ui)
{
  IntegerData ud = {.b = ui};
  return new_integer(IT_UNSIGNED, ud);
}

static Float new_float(FloatType type, FloatData data)
{
  Float result = {.type = type, .data = data};
  return result;
}

static Float f32_as_float(f32 f)
{
  FloatData fd = {.a = f};
  return new_float(FT_32, fd);
}

static Float f64_as_float(f64 f)
{
  FloatData fd = {.b = f};
  return new_float(FT_64, fd);
}

static Number new_number(NumberType type, NumberData data)
{
  Number result = {.type = type, .data = data};
  return result;
}

static Number integer_as_number(Integer i)
{
  NumberData nd = {.a = i};
  return new_number(NT_INTEGER, nd);
}

static Number float_as_number(Float f)
{
  NumberData nd = {.b = f};
  return new_number(NT_FLOAT, nd);
}

static Number signed_integer_as_number(SignedInteger si)
{
  return integer_as_number(signed_integer_as_integer(si));
}

static Number unsigned_integer_as_number(UnsignedInteger ui)
{
  return integer_as_number(unsigned_integer_as_integer(ui));
}

static Number s8_as_number(s8 num)
{
  SignedIntegerData sd = {.a = num};
  return signed_integer_as_number(new_signed_integer(SIT_8, sd));
}

static Number s16_as_number(s16 num)
{
  SignedIntegerData sd = {.b = num};
  return signed_integer_as_number(new_signed_integer(SIT_16, sd));
}

static Number s32_as_number(s32 num)
{
  SignedIntegerData sd = {.c = num};
  return signed_integer_as_number(new_signed_integer(SIT_32, sd));
}

static Number s64_as_number(s64 num)
{
  SignedIntegerData sd = {.d = num};
  return signed_integer_as_number(new_signed_integer(SIT_64, sd));
}

static Number u8_as_number(u8 num)
{
  UnsignedIntegerData usd = {.a = num};
  return unsigned_integer_as_number(new_unsigned_integer(UIT_8, usd));
}

static Number u16_as_number(u16 num)
{
  UnsignedIntegerData usd = {.b = num};
  return unsigned_integer_as_number(new_unsigned_integer(UIT_16, usd));
}

static Number u32_as_number(u32 num)
{
  UnsignedIntegerData usd = {.c = num};
  return unsigned_integer_as_number(new_unsigned_integer(UIT_32, usd));
}

static Number u64_as_number(u64 num)
{
  UnsignedIntegerData usd = {.d = num};
  return unsigned_integer_as_number(new_unsigned_integer(UIT_64, usd));
}

static Number f32_as_number(f32 num)
{
  FloatData fd = {.a = num};
  return float_as_number(new_float(FT_32, fd));
}

static Number f64_as_number(f64 num)
{
  FloatData fd = {.b = num};
  return float_as_number(new_float(FT_64, fd));
}

// NOTE: Syscall
static Array new_array(ArrayType type, u64 length)
{
  Array result = {
      .type = type,
      .length = length,
      .data = malloc(type * length),
  };

  return result;
}

static Array human_readable_signed_integer(SignedInteger num)
{
  Array result = new_array(AT_U8, 32);

  switch (num.type)
  {
  case SIT_8:
    snprintf((c_char *)result.data, result.length, "%" PRId8, num.data.a);
    break;
  case SIT_16:
    snprintf((c_char *)result.data, result.length, "%" PRId16, num.data.b);
    break;
  case SIT_32:
    snprintf((c_char *)result.data, result.length, "%" PRId32, num.data.c);
    break;
  case SIT_64:
    snprintf((c_char *)result.data, result.length, "%" PRId64, num.data.d);
    break;
  default:
    assert(0); // Unreachable
  }

  return result;
}

static Array human_readable_unsigned_integer(UnsignedInteger num)
{
  Array result = new_array(AT_U8, 32);

  switch (num.type)
  {
  case UIT_8:
    snprintf((c_char *)result.data, result.length, "%" PRIu8, num.data.a);
    break;
  case UIT_16:
    snprintf((c_char *)result.data, result.length, "%" PRIu16, num.data.b);
    break;
  case UIT_32:
    snprintf((c_char *)result.data, result.length, "%" PRIu32, num.data.c);
    break;
  case UIT_64:
    snprintf((c_char *)result.data, result.length, "%" PRIu64, num.data.d);
    break;
  default:
    assert(0); // Unreachable
  }

  return result;
}

static Array human_readable_integer(Integer num)
{
  switch (num.type)
  {
  case IT_SIGNED:
    return human_readable_signed_integer(num.data.a);
  case IT_UNSIGNED:
    return human_readable_unsigned_integer(num.data.b);
  default:
    assert(0); // Unreachable
  }
}

static Array human_readable_float(Float num)
{
  Array result = new_array(AT_U8, 32);

  switch (num.type)
  {
  case FT_32:
    snprintf((c_char *)result.data, result.length, "%f", num.data.a);
    break;
  case FT_64:
    snprintf((c_char *)result.data, result.length, "%lf", num.data.b);
    break;
  default:
    assert(0); // Unreachable
  }

  return result;
}

static Array human_readable_number(Number num)
{
  switch (num.type)
  {
  case NT_INTEGER:
    return human_readable_integer(num.data.a);
  case NT_FLOAT:
    return human_readable_float(num.data.b);
  default:
    assert(0); // Unreachable
  }
}

// NOTE: Syscall
s32 print(Number num)
{
  Array result = human_readable_number(num);
  return printf("%s\n", (u8 *)result.data);
}

#endif // ASL_H
