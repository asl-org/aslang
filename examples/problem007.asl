import { i8, u8, u32, Array, Status, Any, Error, Bitset, System } from "base.asl"

# Project Euler #7 style exercise — the first file with multiple
# top-level modules in the same file (Bitset and Example), each
# with its own struct/functions. Also exercises the 'pointer'
# primitive type and negative signed-integer literal initializers
# (i64 -1).
public module Example:
  func mark_non_prime(primes: Bitset, j: u32, i: u32): Status[Bitset]
    match Bitset.set(primes, j):
      case Ok { value: primes }:
        match u32.add(j, i):
          case Ok { value: k }:
            Example.mark_non_prime(primes, k, i)
          case Err { error: err2 }:
            Status[Bitset].Err { error: err2 }
      case Err { error: err1 }:
        Status[Bitset].Err { error: err1 }

  func check_count(primes: Bitset, i: u32, c: u32): Status[u32]
    match u32.compare(c, 10000):
      case 0:
        Status.Ok { value: i }
      case _:
        match u32.add(c, 1):
          case Ok { value: next_c }:
            match u32.add(i, 1):
              case Ok { value: next_i }:
                Example.solve(primes, next_i, next_c)
              case Err { error: err2 }:
                Status[u32].Err { error: err2 }
          case Err { error: err1 }:
            Status[u32].Err { error: err1 }

  func handle_prime(primes: Bitset, i: u32, c: u32): Status[u32]
    match Bitset.get(primes, i):
      case Ok { value: op }:
        match op:
          case 0:
            match u32.multiply(i, 2):
              case Ok { value: j }:
                Example.mark_non_prime(primes, j, i)
                Example.check_count(primes, i, c)
              case Err { error: err2 }:
                Status[u32].Err { error: err2 }
          case _:
            match u32.add(i, 1):
              case Ok { value: next_i }:
                Example.solve(primes, next_i, c)
              case Err { error: err2 }:
                Status[u32].Err { error: err2 }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

  func solve(primes: Bitset, i: u32, c: u32): Status[u32]
    match Bitset.get(primes, i):
      case Ok { value: op }:
        Example.handle_prime(primes, i, c)
      case Err { error: err }:
        Status[u32].Err { error: err }

  func start(): u8
    match Bitset.init(1000001):
      case Ok { value: primes }:
        match Example.solve(primes, 2, 0):
          case Ok { value: _ }:
            u8 0
          case _:
            u8 1
      case _:
        u8 1
