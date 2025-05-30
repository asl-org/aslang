module Bitset:
  struct:
    Pointer ptr
    U64 size

  fn get(Bitset bitset, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, bitset.size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(bitset.ptr, byte)
        data = U8.from(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        S64.from(res)
      else:
        failed

  fn set(Bitset bitset, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, bitset.size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(bitset.ptr, byte)
        data = U8.from(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn clear(Bitset bitset, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, bitset.size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(bitset.ptr, byte)
        data = U8.from(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn toggle(Bitset bitset, U64 bit) returns S64:
    data = Bitset.get(bitset, bit)
    match data:
      case 0:
        Bitset.set(bitset, bit)
      case 1:
        Bitset.clear(bitset, bit)
      else:
        data

app Example:
  fn max(U64 a, U64 b) returns U64:
    op = U64.compare(a, b)
    match op:
      case 1:
        a
      else:
        b

  fn mark_non_prime(Bitset primes, U64 j, U64 i) returns Bitset:
    op = U64.compare(j, primes.size)
    match op:
      case -1:
        Bitset.set(primes, j)
        k = U64.add(j, i)
        Example.mark_non_prime(primes, k, i)
      else:
        primes

  fn update_ans(U64 i, U64 ans) returns U64:
    r = U64.remainder(600851475143, i)
    match r:
      case 0:
        Example.max(ans, i)
      else:
        ans

  fn handle_prime(Bitset primes, U64 i, U64 ans) returns U64:
    op = Bitset.get(primes, i)
    match op:
      case 0:
        j = U64.multiply(i, 2)
        Example.mark_non_prime(primes, j, i)
        Example.update_ans(i, ans)
      case 1:
        ans

  fn solve(Bitset primes, U64 start, U64 ans) returns U64:
    op = U64.compare(start, primes.size)
    match op:
      case -1:
        res = Example.handle_prime(primes, start, ans)
        next_start = U64.add(start, 1)
        Example.solve(primes, next_start, res)
      else:
        ans

  fn start(U8 seed) returns U8:
    exit_success = U8 0

    max_primes = U64 1000001
    ptr = System.allocate(max_primes)

    primes = Bitset { ptr: ptr, size: max_primes }
    ans = Example.solve(primes, 2, 0)
    System.print(ans)

    System.free(ptr)
    exit_success