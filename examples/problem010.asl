# Project Euler #10 style exercise — sum of primes via sieve.
# The largest single-file example: three top-level modules (Utils,
# Bitset, Solver) in one file, struct with generic Array[u8] field,
# deeply nested union-variant patterns, cross-module function calls
# (Bitset.get from Solver), and Error struct-initializer literals
# embedded inside union variants.
public module Solver:
  func mark_non_prime(bitset: Bitset, j: u32, i: u32): Status[u8]
    match Bitset.set(bitset, j):
      case Ok { value: _ }:
        match u32.add(j, i):
          case Ok { value: k }:
            Solver.mark_non_prime(bitset, k, i)
          case Err { error: err2 }:
            Status[u8].Err { error: err2 }
      case Err { error: err1 }:
        Status[u8].Err { error: err1 }

  func solve(bitset: Bitset, start: u32, ans: u32): Status[u32]
    match Bitset.get(bitset, start):
      case Ok { value: value }:
        match u32.add(start, 1):
          case Ok { value: next_start }:
            match value:
              case 0:
                match Solver.mark_non_prime(bitset, start, start):
                  case Ok { value: _ }:
                    match u32.add(ans, start):
                      case Ok { value: new_ans }:
                        Solver.solve(bitset, next_start, new_ans)
                      case Err { error: err4 }:
                        Status[u32].Err { error: err4 }
                  case Err { error: err3 }:
                    Status[u32].Err { error: err3 }
              case _:
                Solver.solve(bitset, next_start, ans)
          case Err { error: err2 }:
            Status[u32].Err { error: err2 }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

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
