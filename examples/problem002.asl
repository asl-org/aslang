
# Project Euler #2 style exercise — exercises match-as-expression
# with integer-literal patterns (case 0, case 1) and wildcard
# (case _), function recursion, and assignment-from-match
# (ans = match c: ...).
public module Solver:
  func apply(a: i64, b: i64, c: i64): Status[i64]
    ans = match c:
      case 0:
        i64.add(a, b)
      case _:
        Status[i64].Ok { value: b }

  func solve(a: i64, b: i64, c: i64, d: i64): Status[i64]
    ans = match i64.compare(a, c):
      case 1:
        Status[i64].Ok { value: d }
      case _:
        e = i64.remainder(a, 2)
        match Solver.apply(a, d, e):
          case Ok { value: f }:
            match i64.add(a, b):
              case Ok { value: g }:
                Solver.solve(b, g, c, f)
              case Err { error: err2 }:
                Status[i64].Err { error: err2 }
          case Err { error: err1 }:
            Status[i64].Err { error: err1 }

  public func start(): i32
    match Solver.solve(1, 2, 4000000, 0):
      case Ok { value: x }:
        i32 0
      case _:
        i32 1
