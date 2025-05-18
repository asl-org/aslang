#ifndef ASL_BYTE_H
#define ASL_BYTE_H

#include "base.h"

// Module: U8

U8 U8_and(U8 a, U8 b)
{
  return a & b;
}

U8 U8_or(U8 a, U8 b)
{
  return a | b;
}

U8 U8_lshift(U8 a, U64 b)
{
  return a << b;
}

U8 U8_rshift(U8 a, U64 b)
{
  return a >> b;
}

U8 U8_not(U8 a)
{
  return ~a;
}

U8 U8_print(U8 value)
{
  return printf("%d\n", value);
}

#endif // ASL_BYTE_H