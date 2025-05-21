#ifndef ASL_POINTER_H
#define ASL_POINTER_H

#include "base.h"
#include <string.h>

Pointer System_allocate(U64 bytes)
{
  Pointer ptr = (Pointer)malloc(bytes);
  memset((void *)ptr, 0, bytes);
  return ptr;
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

U16 Pointer_read_U16(Pointer ptr)
{
  return (*((U16 *)ptr));
}

U32 Pointer_read_U32(Pointer ptr)
{
  return (*((U32 *)ptr));
}

U64 Pointer_read_U64(Pointer ptr)
{
  return (*((U64 *)ptr));
}

S8 Pointer_read_S8(Pointer ptr)
{
  return (*((S8 *)ptr));
}

S16 Pointer_read_S16(Pointer ptr)
{
  return (*((S16 *)ptr));
}

S32 Pointer_read_S32(Pointer ptr)
{
  return (*((S32 *)ptr));
}

S64 Pointer_read_S64(Pointer ptr)
{
  return (*((S64 *)ptr));
}

F32 Pointer_read_F32(Pointer ptr)
{
  return (*((F32 *)ptr));
}

F64 Pointer_read_F64(Pointer ptr)
{
  return (*((F64 *)ptr));
}

Pointer Pointer_read_Pointer(Pointer ptr)
{
  return (*((Pointer *)ptr));
}

Pointer Pointer_write_U8(Pointer ptr, U8 value)
{
  (*((U8 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_U16(Pointer ptr, U16 value)
{
  (*((U16 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_U32(Pointer ptr, U32 value)
{
  (*((U32 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_U64(Pointer ptr, U64 value)
{
  (*((U64 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_S8(Pointer ptr, S8 value)
{
  (*((S8 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_S16(Pointer ptr, S16 value)
{
  (*((S16 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_S32(Pointer ptr, S32 value)
{
  (*((S32 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_S64(Pointer ptr, S64 value)
{
  (*((S64 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_F32(Pointer ptr, F32 value)
{
  (*((F32 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_F64(Pointer ptr, F64 value)
{
  (*((F64 *)ptr)) = value;
  return ptr;
}

Pointer Pointer_write_Pointer(Pointer ptr, Pointer value)
{
  (*((Pointer *)ptr)) = value;
  return ptr;
}

#endif // ASL_POINTER_H