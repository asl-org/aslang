module S8:
  extern S8_byte_size:
    fn byte_size(U64 items): U64

  extern S8_read:
    fn read(Pointer ptr, U64 offset): S8

  extern S8_write:
    fn write(S8 value, Pointer ptr, U64 offset): Pointer

module S16:
  extern S16_byte_size:
    fn byte_size(U64 items): U64

  extern S16_read:
    fn read(Pointer ptr, U64 offset): S16

  extern S16_write:
    fn write(S16 value, Pointer ptr, U64 offset): Pointer

module S32:
  extern S32_byte_size:
    fn byte_size(U64 items): U64

  extern S32_read:
    fn read(Pointer ptr, U64 offset): S32

  extern S32_write:
    fn write(S32 value, Pointer ptr, U64 offset): Pointer

module S64:
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
