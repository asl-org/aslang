#ifndef ASL_POINTER_H
#define ASL_POINTER_H

#include "base.h"

Pointer System_allocate(U64 bytes)
{
  return (Pointer)malloc(bytes);
}

U8 System_free(Pointer ptr)
{
  free((void *)ptr);
  return 0;
}

U64 Pointer_print(Pointer ptr)
{
  return printf("%llu\n", (U64)ptr);
}

Pointer Pointer_shift(Pointer ptr, U64 offset)
{
  return ptr + offset;
}

U8 Pointer_read_U8(Pointer ptr)
{
  return (*((U8 *)ptr));
}

U64 Pointer_read_U64(Pointer ptr)
{
  return (*((U64 *)ptr));
}

S64 Pointer_read_S64(Pointer ptr)
{
  return (*((S64 *)ptr));
}

Pointer Pointer_write_U8(Pointer ptr, U8 value)
{
  (*((U8 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_U64(Pointer ptr, U64 value)
{
  (*((U64 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_S64(Pointer ptr, S64 value)
{
  (*((S64 *)ptr)) = value;
  return ptr;
}

#endif // ASL_POINTER_H