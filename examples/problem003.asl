import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"

# Project Euler #3 style exercise — heavy union-variant matching.
# Exercises struct data block (Bitset holding Array[u8]), union
# initializers via Status[u8].Ok / Status[Bitset].Err, variant
# patterns with field bindings (case Ok { value: value }), nested
# match expressions, and generic type parameters on method calls.
public module Solver:
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

  func mark_non_prime(bitset: Bitset, j: u64, i: u64): Status[u8]
    status = Bitset.get(bitset, j)
    match status:
      case Ok { value: value }:
        Bitset.set(bitset, j)
        k = u64.add(j, i)
        Solver.mark_non_prime(bitset, k, i)
      case _:
        status

  func update_ans(i: u64, ans: u64): u64
    r = u64.remainder(600851475143, i)
    match r:
      case 0:
        Solver.max(ans, i)
      case _:
        ans

  func solve(bitset: Bitset, start: u64, ans: u64): u64
    status = Bitset.get(bitset, start)
    match status:
      case Ok { value: value }:
        next_start = u64.add(start, 1)
        match value:
          case 0:
            Solver.mark_non_prime(bitset, start, start)
            new_ans = Solver.update_ans(start, ans)
            Solver.solve(bitset, next_start, new_ans)
          case _:
            Solver.solve(bitset, next_start, ans)
      case _:
        ans

  func start(): u8
    bitset = Bitset.init(1000001)

    ans = Solver.solve(bitset, 2, 0)
    System.print(ans)

    exit_success = u8 0
