#ifndef ASL_S64_H
#define ASL_S64_H

#include "base.h"

// Module: S64

S64 S64_add(S64 a, S64 b)
{
  return a + b;
}

S64 S64_subtract(S64 a, S64 b)
{
  return a - b;
}

S64 S64_multiply(S64 a, S64 b)
{
  return a * b;
}

S64 S64_quotient(S64 a, S64 b)
{
  return a / b;
}

S64 S64_remainder(S64 a, S64 b)
{
  return a % b;
}

S64 S64_compare(S64 a, S64 b)
{
  return a > b ? 1 : (a == b ? 0 : -1);
}

U64 S64_print(S64 value)
{
  return (S64)printf("%lld\n", value);
}

#endif // ASL_S64_H