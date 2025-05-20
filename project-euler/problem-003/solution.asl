module Bitset:
  fn init(U64 size) returns Pointer:
    System.allocate(size)

  fn free(Pointer ptr) returns U8:
    System.free(ptr)

  fn get(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        S64.from(res)
      else:
        failed

  fn set(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn clear(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn toggle(Pointer ptr, U64 size, U64 bit) returns S64:
    data = MODULE.get(ptr, size, bit)
    match data:
      case 0:
        MODULE.set(ptr, size, bit)
      case 1:
        MODULE.clear(ptr, size, bit)
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

  fn mark_non_prime(Pointer primes, U64 j, U64 max_primes, U64 i) returns Pointer:
    op = U64.compare(j, max_primes)
    match op:
      case -1:
        Bitset.set(primes, max_primes, j)
        k = U64.add(j, i)
        MODULE.mark_non_prime(primes, k, max_primes, i)
      else:
        primes

  fn update_ans(U64 i, U64 ans) returns U64:
    r = U64.remainder(600851475143, i)
    match r:
      case 0:
        MODULE.max(ans, i)
      else:
        ans

  fn handle_prime(Pointer primes, U64 max_primes, U64 i, U64 ans) returns U64:
    op = Bitset.get(primes, max_primes, i)
    match op:
      case 0:
        j = U64.multiply(i, 2)
        MODULE.mark_non_prime(primes, j, max_primes, i)
        MODULE.update_ans(i, ans)
      case 1:
        ans

  fn solve(Pointer primes, U64 max_primes, U64 start, U64 ans) returns U64:
    op = U64.compare(start, max_primes)
    match op:
      case -1:
        res = MODULE.handle_prime(primes, max_primes, start, ans)
        next_start = U64.add(start, 1)
        MODULE.solve(primes, max_primes, next_start, res)
      else:
        ans

  fn start(U8 seed) returns U8:
    exit_success = U8 0

    max_primes = U64 1000001
    primes = Bitset.init(max_primes)
    ans = MODULE.solve(primes, max_primes, 2, 0)
    U64.print(ans)

    exit_success