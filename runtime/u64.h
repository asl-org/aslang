#ifndef ASL_U64_H
#define ASL_U64_H

#include "base.h"

// Module: U64

U64 U64_and(U64 a, U64 b)
{
  return a & b;
}

U64 U64_or(U64 a, U64 b)
{
  return a | b;
}

U64 U64_not(U64 a)
{
  return ~a;
}

U64 U64_lshift(U64 a, U64 b)
{
  return a << b;
}

U64 U64_rshift(U64 a, U64 b)
{
  return a >> b;
}

U64 U64_add(U64 a, U64 b)
{
  return a + b;
}

U64 U64_subtract(U64 a, U64 b)
{
  return a - b;
}

U64 U64_multiply(U64 a, U64 b)
{
  return a * b;
}

U64 U64_quotient(U64 a, U64 b)
{
  return a / b;
}

U64 U64_remainder(U64 a, U64 b)
{
  return a % b;
}

S64 U64_compare(U64 a, U64 b)
{
  return a > b ? 1 : (a == b ? 0 : -1);
}

U64 U64_print(U64 value)
{
  return (U64)printf("%llu\n", value);
}

#endif // ASL_U64_H