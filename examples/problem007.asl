
# Project Euler #7 style exercise — the first file with multiple
# top-level modules in the same file (Bitset and Example), each
# with its own struct/functions. Also exercises the 'pointer'
# primitive type and negative signed-integer literal initializers
# (i64 -1).
public module Example:
  func mark_non_prime(primes: Bitset, j: u32, i: u32): Bitset!
    primes = try Bitset.set(primes, j)
    k = try u32.add(j, i)
    Example.mark_non_prime(primes, k, i)

  func check_count(primes: Bitset, i: u32, c: u32): u32!
    match u32.compare(c, 10000):
      case 0:
        u32!.Ok { value: i }
      case _:
        next_c = try u32.add(c, 1)
        next_i = try u32.add(i, 1)
        Example.solve(primes, next_i, next_c)

  func handle_prime(primes: Bitset, i: u32, c: u32): u32!
    op = try Bitset.get(primes, i)
    match op:
      case 0:
        j = try u32.multiply(i, 2)
        Example.mark_non_prime(primes, j, i)
        Example.check_count(primes, i, c)
      case _:
        next_i = try u32.add(i, 1)
        Example.solve(primes, next_i, c)

  func solve(primes: Bitset, i: u32, c: u32): u32!
    _ = try Bitset.get(primes, i)
    Example.handle_prime(primes, i, c)

  public func start(): i32
    match Bitset.init(1000001):
      case Ok { value: primes }:
        match Example.solve(primes, 2, 0):
          case Ok { value: _ }:
            i32 0
          case _:
            i32 1
      case _:
        i32 1
