module S8:
  literal: int8_t
  extern S8_byte_size:
    fn byte_size(U64 items): U64
  extern S8_read:
    fn read(Pointer ptr, U64 offset): S8
  extern S8_write:
    fn write(S8 value, Pointer ptr, U64 offset): Pointer
module S16:
  literal: int16_t
  extern S16_byte_size:
    fn byte_size(U64 items): U64
  extern S16_read:
    fn read(Pointer ptr, U64 offset): S16
  extern S16_write:
    fn write(S16 value, Pointer ptr, U64 offset): Pointer
module S32:
  literal: int32_t
  extern S32_byte_size:
    fn byte_size(U64 items): U64
  extern S32_read:
    fn read(Pointer ptr, U64 offset): S32
  extern S32_write:
    fn write(S32 value, Pointer ptr, U64 offset): Pointer
module S64:
  literal: int64_t
  extern S64_byte_size:
    fn byte_size(U64 items): U64
  extern S64_read:
    fn read(Pointer ptr, U64 offset): S64
  extern S64_write:
    fn write(S64 value, Pointer ptr, U64 offset): Pointer
  extern S64_add_S64:
    fn add(S64 a, S64 b): S64
  extern S64_subtract_S64:
    fn subtract(S64 a, S64 b): S64
  extern S64_multiply_S64:
    fn multiply(S64 a, S64 b): S64
  extern S64_remainder_S64:
    fn remainder(S64 a, S64 b): S64
  extern S64_quotient_S64:
    fn quotient(S64 a, S64 b): S64
  extern S64_compare_S64:
    fn compare(S64 a, S64 b): S8
  extern S64_from_U8:
    fn from(U8 value): S64
  extern S64_from_U64:
    fn from(U64 value): S64
module U8:
  literal: uint8_t
  extern U8_byte_size:
    fn byte_size(U64 items): U64
  extern U8_read:
    fn read(Pointer ptr, U64 offset): U8
  extern U8_write:
    fn write(U8 value, Pointer ptr, U64 offset): Pointer
  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8
  extern U8_rshift_U8:
    fn rshift(U8 value, U64 offset): U8
  extern U8_and_U8:
    fn and(U8 a, U8 b): U8
  extern U8_or_U8:
    fn or(U8 a, U8 b): U8
  extern U8_not:
    fn not(U8 a): U8
  extern U8_from_U64:
    fn from(U64 value): U8
  extern U8_subtract_U8:
    fn subtract(U8 a, U8 b): U8
module U16:
  literal: uint16_t
  extern U16_byte_size:
    fn byte_size(U64 items): U64
  extern U16_read:
    fn read(Pointer ptr, U64 offset): U16
  extern U16_write:
    fn write(U16 value, Pointer ptr, U64 offset): Pointer
module U32:
  literal: uint32_t
  extern U32_byte_size:
    fn byte_size(U64 items): U64
  extern U32_read:
    fn read(Pointer ptr, U64 offset): U32
  extern U32_write:
    fn write(U32 value, Pointer ptr, U64 offset): Pointer
  extern U32_add_U32:
    fn add(U32 a, U32 b): U32
  extern U32_subtract_U32:
    fn subtract(U32 a, U32 b): U32
  extern U32_multiply_U32:
    fn multiply(U32 a, U32 b): U32
  extern U32_compare_U32:
    fn compare(U32 a, U32 b): S8
module U64:
  literal: uint64_t
  extern U64_byte_size:
    fn byte_size(U64 items): U64
  extern U64_read:
    fn read(Pointer ptr, U64 offset): U64
  extern U64_write:
    fn write(U64 value, Pointer ptr, U64 offset): Pointer
  extern U64_add_U64:
    fn add(U64 a, U64 b): U64
  extern U64_subtract_U64:
    fn subtract(U64 a, U64 b): U64
  extern U64_multiply_U64:
    fn multiply(U64 a, U64 b): U64
  extern U64_quotient_U64:
    fn quotient(U64 a, U64 b): U64
  extern U64_remainder_U64:
    fn remainder(U64 a, U64 b): U64
  extern U64_compare_U64:
    fn compare(U64 a, U64 b): S8
  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8
  extern U64_rshift_U64:
    fn rshift(U64 value, U64 offset): U64
  extern U64_and_U64:
    fn and(U64 a, U64 b): U64
  extern U64_or_U64:
    fn or(U64 a, U64 b): U64
  extern U64_not:
    fn not(U64 a): U64
  extern U64_from_U8:
    fn from(U8 value): U64
module F32:
  literal: float
  extern F32_byte_size:
    fn byte_size(U64 items): U64
  extern F32_read:
    fn read(Pointer ptr, U64 offset): F32
  extern F32_write:
    fn write(F32 value, Pointer ptr, U64 offset): Pointer
module F64:
  literal: double
  extern F64_byte_size:
    fn byte_size(U64 items): U64
  extern F64_read:
    fn read(Pointer ptr, U64 offset): F64
  extern F64_write:
    fn write(F64 value, Pointer ptr, U64 offset): Pointer
module String:
  literal: string
  extern String_byte_size:
    fn byte_size(U64 items): U64
  extern String_read:
    fn read(Pointer ptr, U64 offset): String
  extern String_write:
    fn write(String value, Pointer ptr, U64 offset): Pointer
  extern String_get:
    fn get(String value, U64 index): Status[U8]
module Pointer:
  literal: uintptr_t
  extern Pointer_byte_size:
    fn byte_size(U64 items): U64
  extern Pointer_read:
    fn read(Pointer ptr, U64 offset): Pointer
  extern Pointer_write:
    fn write(Pointer value, Pointer ptr, U64 offset): Pointer
module Error:
  struct:
    S32 code
    String message
module Status:
  generic Value
  union:
    Ok:
      Value value
    Err:
      Error error
module Array:
  generic Item
  struct:
    U64 size
  extern Array_init:
    fn init(U64 size): Array[Item]
  extern Array_set:
    fn set(Array[Item] arr, U64 index, Item value): Status[Array[Item]]
  extern Array_get:
    fn get(Array[Item] arr, U64 index): Status[Item]
module System:
  extern System_allocate:
    fn allocate(U64 bytes): Pointer
  extern System_free:
    fn free(Pointer ptr): U64
  extern System_box_U8:
    fn box(U8 value): Pointer
  extern System_box_U64:
    fn box(U64 value): Pointer
  extern System_box_S32:
    fn box(S32 value): Pointer
  extern System_box_S64:
    fn box(S64 value): Pointer
  extern System_box_Pointer:
    fn box(Pointer value): Pointer
  extern System_print_U8:
    fn print(U8 value): U64
  extern System_print_U16:
    fn print(U16 value): U64
  extern System_print_U32:
    fn print(U32 value): U64
  extern System_print_U64:
    fn print(U64 value): U64
  extern System_print_S8:
    fn print(S8 value): U64
  extern System_print_S16:
    fn print(S16 value): U64
  extern System_print_S32:
    fn print(S32 value): U64
  extern System_print_S64:
    fn print(S64 value): U64
  extern System_print_F32:
    fn print(F32 value): U64
  extern System_print_F64:
    fn print(F64 value): U64
  extern System_print_String:
    fn print(String value): U64

module Bitset:
  struct:
    Pointer ptr
    U64 size

  fn get(Bitset bitset, U64 bit): S64
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)
        data = U8.read(ptr, byte)
        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        S64.from(res)
      else:
        S64 -1

  fn set(Bitset bitset, U64 bit): S64
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        data = U8.read(ptr, byte)
        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        U8.write(res, ptr, byte)
        S64.from(res)
      else:
        S64 -1

  fn clear(Bitset bitset, U64 bit): S64
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        data = U8.read(ptr, byte)
        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        U8.write(res, ptr, byte)
        S64.from(res)
      else:
        S64 -1

  fn toggle(Bitset bitset, U64 bit): S64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        Bitset.set(bitset, bit)
      else:
        Bitset.clear(bitset, bit)

module Example:
  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _ = match op:
      case 1:
        a
      else:
        b

  fn mark_non_prime(Bitset primes, U64 j, U64 i): Bitset
    _x = primes.size
    op = U64.compare(j, _x)
    _ = match op:
      case -1:
        Bitset.set(primes, j)
        k = U64.add(j, i)
        Example.mark_non_prime(primes, k, i)
      else:
        primes

  fn check_count(Bitset primes, U64 i, U64 c): U64
    r = U64.compare(c, 10000)
    _ = match r:
      case 0:
        i
      else:
        next_c = U64.add(c, 1)
        next_i = U64.add(i, 1)
        Example.solve(primes, next_i, next_c)

  fn handle_prime(Bitset primes, U64 i, U64 c): U64
    op = Bitset.get(primes, i)
    _ = match op:
      case 0:
        j = U64.multiply(i, 2)
        Example.mark_non_prime(primes, j, i)
        Example.check_count(primes, i, c)
      else:
        next_i = U64.add(i, 1)
        Example.solve(primes, next_i, c)

  fn solve(Bitset primes, U64 i, U64 c): U64
    x = primes.size
    op = U64.compare(i, x)
    _ = match op:
      case -1:
        Example.handle_prime(primes, i, c)
      else:
        U64 0

fn start(U8 seed): U8
  exit_success = U8 0
  max_primes = U64 1000001

  ptr = System.allocate(max_primes)
  primes = Bitset { ptr: ptr, size: max_primes }

  ans = Example.solve(primes, 2, 0)
  _ = System.print(ans)

  exit_success
