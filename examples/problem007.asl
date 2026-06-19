import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"

# Project Euler #7 style exercise — the first file with multiple
# top-level modules in the same file (Bitset and Example), each
# with its own struct/functions. Also exercises the 'pointer'
# primitive type and negative signed-integer literal initializers
# (i64 -1).
public module Example:
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

  func start(): u8
    exit_success = u8 0
    max_primes = u64 1000001

    # ptr = System.allocate(max_primes)
    # primes = Bitset { bits: max_primes }

    # ans = Example.solve(primes, 2, 0)
    # _ = System.print(ans)

    exit_success
