# Project Euler #7 style exercise — the first file with multiple
# top-level modules in the same file (Bitset and Example), each
# with its own struct/functions. Also exercises the 'pointer'
# primitive type and negative signed-integer literal initializers
# (i64 -1).
module Bitset:
  struct:
    ptr: ptr
    size: u64

  func get(bitset: Bitset, bit: u64): i64
    x = bitset.size
    op = u64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = u64.quotient(bit, 8)
        offset = u64.remainder(bit, 8)
        data = u8.read(ptr, byte)
        bdata = u8.rshift(data, offset)
        res = u8.and(bdata, 1)
        i64.from(res)
      case _:
        i64 -1

  func set(bitset: Bitset, bit: u64): i64
    x = bitset.size
    op = u64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = u64.quotient(bit, 8)
        offset = u64.remainder(bit, 8)

        data = u8.read(ptr, byte)
        mask = u8.lshift(1, offset)
        res = u8.or(data, mask)
        u8.write(res, ptr, byte)
        i64.from(res)
      case _:
        i64 -1

  func clear(bitset: Bitset, bit: u64): i64
    x = bitset.size
    op = u64.compare(bit, x)
    _ = match op:
      case -1:
        ptr = bitset.ptr
        byte = u64.quotient(bit, 8)
        offset = u64.remainder(bit, 8)

        data = u8.read(ptr, byte)
        mask = u8.lshift(1, offset)
        imask = u8.not(mask)
        res = u8.and(data, imask)
        u8.write(res, ptr, byte)
        i64.from(res)
      case _:
        i64 -1

  func toggle(bitset: Bitset, bit: u64): i64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        Bitset.set(bitset, bit)
      case _:
        Bitset.clear(bitset, bit)

module Example:
  func max(a: u64, b: u64): u64
    op = u64.compare(a, b)
    _ = match op:
      case 1:
        a
      case _:
        b

  func mark_non_prime(primes: Bitset, j: u64, i: u64): Bitset
    _x = primes.size
    op = u64.compare(j, _x)
    _ = match op:
      case -1:
        Bitset.set(primes, j)
        k = u64.add(j, i)
        Example.mark_non_prime(primes, k, i)
      case _:
        primes

  func check_count(primes: Bitset, i: u64, c: u64): u64
    r = u64.compare(c, 10000)
    _ = match r:
      case 0:
        i
      case _:
        next_c = u64.add(c, 1)
        next_i = u64.add(i, 1)
        Example.solve(primes, next_i, next_c)

  func handle_prime(primes: Bitset, i: u64, c: u64): u64
    op = Bitset.get(primes, i)
    _ = match op:
      case 0:
        j = u64.multiply(i, 2)
        Example.mark_non_prime(primes, j, i)
        Example.check_count(primes, i, c)
      case _:
        next_i = u64.add(i, 1)
        Example.solve(primes, next_i, c)

  func solve(primes: Bitset, i: u64, c: u64): u64
    x = primes.size
    op = u64.compare(i, x)
    _ = match op:
      case -1:
        Example.handle_prime(primes, i, c)
      case _:
        u64 0

  func start(sys: System): u8
    exit_success = u8 0
    max_primes = u64 1000001

    ptr = System.allocate(max_primes)
    primes = Bitset { ptr: ptr, size: max_primes }

    ans = Example.solve(primes, 2, 0)
    _ = System.print(ans)

    exit_success
