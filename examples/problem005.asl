import { i8, u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"
# Project Euler #5 style exercise — gcd/lcm via Euclidean recursion.
# Exercises integer comparison with signed literal patterns
# (case -1), mutually-calling functions within a module, and
# tail-recursive loops.
public module Example:
  func gcd(a: u64, b: u64): Status[u64]
    match u64.compare(b, 0):
      case 0:
        Status.Ok { value: a }
      case _:
        match u64.remainder(a, b):
          case Ok { value: c }:
            Example.gcd(b, c)
          case Err { error: error }:
            Status[u64].Err { error: error }

  func lcm(a: u64, b: u64): Status[u64]
    match u64.multiply(a, b):
      case Ok { value: c }:
        match Example.gcd(a, b):
          case Ok { value: d }:
            u64.quotient(c, d)
          case Err { error: err2 }:
            Status[u64].Err { error: err2 }
      case Err { error: err1 }:
        Status[u64].Err { error: err1 }

  func solve(i: u64, n: u64, j: u64): Status[u64]
    op = u64.compare(i, n)
    _ = match op:
      case -1:
        match u64.add(i, 1):
          case Ok { value: next_i }:
            match Example.lcm(i, j):
              case Ok { value: next_j }:
                Example.solve(next_i, n, next_j)
              case Err { error: err2 }:
                Status[u64].Err { error: err2 }
          case Err { error: err1 }:
            Status[u64].Err { error: err1 }
      case _:
        Status.Ok { value: j }

  func start(): u8
    Example.solve(2, 20, 1)
    u8 0
