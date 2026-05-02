import { u8, u32, u64, Array, Status, Any, Error, Bitset, System, String } from "base.asl"
# Project Euler #10 style exercise — sum of primes via sieve.
# The largest single-file example: three top-level modules (Utils,
# Bitset, Solver) in one file, struct with generic Array[u8] field,
# deeply nested union-variant patterns, cross-module function calls
# (Bitset.get from Solver), and Error struct-initializer literals
# embedded inside union variants.
module Utils:
  func div_ceil(a: u64, b: u64): u64
    c = u64.add(a, b)
    d = u64.subtract(c, 1)
    u64.quotient(d, b)

  func max(a: u64, b: u64): u64
    op = u64.compare(a, b)
    _ = match op:
      case 1:
        a
      case _:
        b

public module Solver:
  func mark_non_prime(bitset: Bitset, j: u64, i: u64): Status[u8]
    status = Bitset.get(bitset, j)
    match status:
      case Ok { value: value }:
        Bitset.set(bitset, j)
        k = u64.add(j, i)
        Solver.mark_non_prime(bitset, k, i)
      case _:
        status

  func solve(bitset: Bitset, start: u64, ans: u64): u64
    status = Bitset.get(bitset, start)
    match status:
      case Ok { value: value }:
        next_start = u64.add(start, 1)
        match value:
          case 0:
            Solver.mark_non_prime(bitset, start, start)
            new_ans = u64.add(ans, start)
            Solver.solve(bitset, next_start, new_ans)
          case _:
            Solver.solve(bitset, next_start, ans)
      case _:
        ans

  func start(): u8
    bitset = Bitset.init(2000001)

    ans = Solver.solve(bitset, 2, 0)
    System.print(ans)

    exit_success = u8 0
