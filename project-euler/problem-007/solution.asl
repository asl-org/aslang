struct Bitset:
  Pointer ptr
  U64 size

module Bitset:
  fn get(Bitset bitset, U64 bit): S64
    failed = S64.init(-1)
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer.shift(y, byte)
        data = U8.from(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        _x = S64.from(res)
      else:
        _y = S64.init(failed)

  fn set(Bitset bitset, U64 bit): S64
    failed = S64.init(-1)
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer.shift(y, byte)
        data = U8.from(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        _a = Pointer.write(bptr, res)
        _b = S64.from(res)
      else:
        _c = S64.init(failed)

  fn clear(Bitset bitset, U64 bit): S64
    failed = S64.init(-1)
    x = bitset.size
    op = U64.compare(bit, x)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        y = bitset.ptr
        bptr = Pointer.shift(y, byte)
        data = U8.from(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        _a = Pointer.write(bptr, res)
        _b = S64.from(res)
      else:
        _c = S64.init(failed)

  fn toggle(Bitset bitset, U64 bit): S64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        _a = Bitset.set(bitset, bit)
      case 1:
        _b = Bitset.clear(bitset, bit)
      else:
        _c = S64.init(data)

module Example:
  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _ = match op:
      case 1:
        _a = U64.init(a)
      else:
        _b = U64.init(b)

  fn mark_non_prime(Bitset primes, U64 j, U64 i): Bitset
    _x = primes.size
    op = U64.compare(j, _x)
    _ = match op:
      case -1:
        _a = Bitset.set(primes, j)
        k = U64.add(j, i)
        _y = Example.mark_non_prime(primes, k, i)
      else:
        # TODO: Handle return ops and get rid of init functions
        _c = Pointer.init(primes)

  fn check_count(Bitset primes, U64 i, U64 c): U64
    r = U64.compare(c, 10000)
    _ = match r:
      case 0:
        _a = U64.init(i)
      else:
        next_c = U64.add(c, 1)
        next_i = U64.add(i, 1)
        _b = Example.solve(primes, next_i, next_c)

  fn handle_prime(Bitset primes, U64 i, U64 c): U64
    op = Bitset.get(primes, i)
    _ = match op:
      case 0:
        j = U64.multiply(i, 2)
        _a = Example.mark_non_prime(primes, j, i)
        _b = Example.check_count(primes, i, c)
      case 1:
        next_i = U64.add(i, 1)
        _c = Example.solve(primes, next_i, c)

  fn solve(Bitset primes, U64 i, U64 c): U64
    failed = U64.init(0)
    _x = primes.size
    op = U64.compare(i, _x)
    _ = match op:
      case -1:
        _a = Example.handle_prime(primes, i, c)
      else:
        _b = U64.init(failed)

fn start(U8 seed): U8
  max_primes = U64.init(1000001)
  ptr = System.allocate(max_primes)
  primes = Bitset { ptr: ptr, size: max_primes }
  ans = Example.solve(primes, 2, 0)
  _ = System.print_U64(ans)

  exit_success = U8.init(0)
