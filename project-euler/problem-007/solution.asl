struct Bitset:
    Pointer ptr
    U64 size

module Bitset:
  fn get(Bitset bitset, U64 bit): S64
    failed = S64_init(-1)
    x = bitset.size
    op = U64_compare(bit, x)
    _ = match op:
      case -1:
        byte = U64_quotient(bit, 8)
        offset = U64_remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer_shift(y, byte)
        data = U8_from(bptr)

        bdata = U8_rshift(data, offset)
        res = U8_and(bdata, 1)
        _x = S64_from(res)
      else:
        _y = S64_init(failed)

  fn set(Bitset bitset, U64 bit): S64
    failed = S64_init(-1)
    x = bitset.size
    op = U64_compare(bit, x)
    _ = match op:
      case -1:
        byte = U64_quotient(bit, 8)
        offset = U64_remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer_shift(y, byte)
        data = U8_from(bptr)

        mask = U8_lshift(1, offset)
        res = U8_or(data, mask)
        _a = Pointer_write(bptr, res)
        _b = S64_from(res)
      else:
        _c = S64_init(failed)

  fn clear(Bitset bitset, U64 bit): S64
    failed = S64_init(-1)
    x = bitset.size
    op = U64_compare(bit, x)
    _ = match op:
      case -1:
        byte = U64_quotient(bit, 8)
        offset = U64_remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer_shift(y, byte)
        data = U8_from(bptr)

        mask = U8_lshift(1, offset)
        imask = U8_not(mask)
        res = U8_and(data, imask)
        _a = Pointer_write(bptr, res)
        _b = S64_from(res)
      else:
        _c = S64_init(failed)

  fn toggle(Bitset bitset, U64 bit): S64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        _a = Bitset.set(bitset, bit)
      case 1:
        _b = Bitset.clear(bitset, bit)
      else:
        _c = S64_init(data)

module Example:
  fn max(U64 a, U64 b): U64
    op = U64_compare(a, b)
    _ = match op:
      case 1:
        _a = U64_init(a)
      else:
        _b = U64_init(b)

  fn mark_non_prime(Bitset primes, U64 j, U64 i): Bitset
    _x = primes.size
    op = U64_compare(j, _x)
    _ = match op:
      case -1:
        _a = Bitset.set(primes, j)
        k = U64_add(j, i)
        _y = Example.mark_non_prime(primes, k, i)
      else:
        _c = Pointer_init(primes)

  fn check_count(Bitset primes, U64 i, U64 c): U64
    r = U64_compare(c, 10000)
    _ = match r:
      case 0:
        _a = U64_init(i)
      else:
        next_c = U64_add(c, 1)
        next_i = U64_add(i, 1)
        _b = Example.solve(primes, next_i, next_c)

  fn handle_prime(Bitset primes, U64 i, U64 c): U64
    op = Bitset.get(primes, i)
    _ = match op:
      case 0:
        j = U64_multiply(i, 2)
        _a = Example.mark_non_prime(primes, j, i)
        _b = Example.check_count(primes, i, c)
      case 1:
        next_i = U64_add(i, 1)
        _c = Example.solve(primes, next_i, c)

  fn solve(Bitset primes, U64 i, U64 c): U64
    failed = U64_init(0)
    _x = primes.size
    op = U64_compare(i, _x)
    _ = match op:
      case -1:
        _a = Example.handle_prime(primes, i, c)
      else:
        _b = U64_init(failed)

fn start(U8 seed): U8
  max_primes = U64_init(1000001)
  ptr = System_allocate(max_primes)
  primes = Bitset { ptr: ptr, size: max_primes }
  ans = Example.solve(primes, 2, 0)
  _ = System_print_U64(ans)

  exit_success = U8_init(0)
