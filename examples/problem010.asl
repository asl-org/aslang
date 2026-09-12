# Project Euler #10 style exercise — sum of primes via sieve.
# The largest single-file example: three top-level modules (Utils,
# Bitset, Solver) in one file, struct with generic Array[u8] field,
# deeply nested union-variant patterns, cross-module function calls
# (Bitset.get from Solver), and Error struct-initializer literals
# embedded inside union variants.
public module Solver:
  func mark_non_prime(bitset: Bitset, j: u32, i: u32): u8!
    _ = try Bitset.set(bitset, j)
    k = try u32.add(j, i)
    Solver.mark_non_prime(bitset, k, i)

  func solve(bitset: Bitset, start: u32, ans: u32): u32!
    value = try Bitset.get(bitset, start)
    next_start = try u32.add(start, 1)
    match value:
      case 0:
        _ = try Solver.mark_non_prime(bitset, start, start)
        new_ans = try u32.add(ans, start)
        Solver.solve(bitset, next_start, new_ans)
      case _:
        Solver.solve(bitset, next_start, ans)

  public func start(): i32
    match Bitset.init(2000001):
      case Ok { value: bitset }:
        match Solver.solve(bitset, 2, 0):
          case Ok { value: ans }:
            i32 0
          case Err { error: _ }:
            i32 1
      case Err { error: _ }:
        i32 1
