import "base.asl"

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

  func update_ans(maybe_prime: u32, ans: u32): Status[u32]
    maybe_prime_u64 = u64.from(maybe_prime)
    match u64.remainder(600851475143, maybe_prime_u64):
      case Ok { value: val }:
        new_ans = match val:
          case 0:
            u32.max(ans, maybe_prime)
          case _:
            ans
        Status[u32].Ok { value: new_ans }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

  func solve(bitset: Bitset, num: u32, ans: u32): Status[u32]
    match Bitset.get(bitset, num):
      case Ok { value: flag }:
        match u32.add(num, 1):
          case Ok { value: next_num }:
            match flag:
              case 0: # 0 stands for prime
                match Solver.mark_non_prime(bitset, num, num):
                  case Ok { value: _ }:
                    match Solver.update_ans(num, ans):
                      case Ok { value: new_ans }:
                        Solver.solve(bitset, next_num, new_ans)
                      case _:
                        Status.Ok { value: ans }
                  case _:
                    Status.Ok { value: ans }
              case _:
                Solver.solve(bitset, next_num, ans)
          case _:
            Status.Ok { value: ans }
      case _:
        Status.Ok { value: ans }

  public func start(): u8
    match Bitset.init(1000001):
      case Ok { value: bitset }:
        match Solver.solve(bitset, 2, 0):
          case Ok { value: _ }:
            u8 0
          case _:
            u8 1
      case _:
        u8 1
