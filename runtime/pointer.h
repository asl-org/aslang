#ifndef ASL_POINTER_H
#define ASL_POINTER_H

#include "base.h"
#include <string.h>

Pointer Pointer_init(Pointer ptr) { return ptr; }

Pointer Pointer_shift(Pointer ptr, U64 offset) { return ptr + offset; }

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