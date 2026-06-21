import { i8, u8, u32, i64, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"

# Project Euler #3 style exercise — heavy union-variant matching.
# Exercises struct data block (Bitset holding Array[Any]), union
# initializers via Status.Ok / Status.Err (impls inferred), variant
# patterns with field bindings (case Ok { value: value }), nested
# match expressions, and module-method calls.
public module Solver:
  func mark_non_prime(bitset: Bitset, num: u32, offset: u32): Status[u8]
    _ = Bitset.set(bitset, num)
    match u32.add(num, offset):
      case Ok { value: next_num }:
        Solver.mark_non_prime(bitset, next_num, offset)
      case Err { error: err }:
        Status[u8].Err { error: err }

  func update_ans(maybe_prime: u32, ans: u32): u32
    maybe_prime_u64 = u64.from(maybe_prime)
    match u64.remainder(600851475143, maybe_prime_u64):
      case 0:
        u32.max(ans, maybe_prime)
      case _:
        ans

  func solve(bitset: Bitset, num: u32, ans: u32): u32
    match Bitset.get(bitset, num):
      case Ok { value: flag }:
        next_num = u32.add(num, 1)
        match flag:
          case 0: # 0 stands for prime
            Solver.mark_non_prime(bitset, num, num)
            new_ans = Solver.update_ans(num, ans)
            Solver.solve(bitset, next_num, new_ans)
          case _:
            Solver.solve(bitset, next_num, ans)
      case _:
        ans

  func start(): u8
    bitset = Bitset.init(1000001)

    ans = Solver.solve(bitset, 2, 0)
    System.print(ans)

    exit_success = u8 0
