#ifndef ASL_SYSTEM_H
#define ASL_SYSTEM_H

#include "base.h"
#include <string.h>

Pointer System_allocate(U64 bytes)
{
  void *ptr = malloc(bytes);
  memset(ptr, 0, bytes);
  return (Pointer)ptr;
}

U8 System_free(Pointer ptr)
{
  free((void *)ptr);
  return 0;
}

U64 System_print_Pointer(Pointer ptr) { return printf("%p\n", (void *)ptr); }
U64 System_print_F32(F32 value) { return (U64)printf("%f\n", value); }
U64 System_print_F64(F64 value) { return (U64)printf("%lf\n", value); }
U64 System_print_S8(S8 value) { return (U64)printf("%d\n", value); }
U64 System_print_S16(S16 value) { return (U64)printf("%d\n", value); }
U64 System_print_S32(S32 value) { return (U64)printf("%d\n", value); }
U64 System_print_S64(S64 value) { return (U64)printf("%lld\n", value); }
U64 System_print_U8(U8 value) { return (U64)printf("%u\n", value); }
U64 System_print_U16(U16 value) { return (U64)printf("%u\n", value); }
U64 System_print_U32(U32 value) { return (U64)printf("%u\n", value); }
U64 System_print_U64(U64 value) { return (U64)printf("%llu\n", value); }

#endif // ASL_SYSTEM_H
