import "base.asl"

# Project Euler #1 style exercise — covers module with multiple
# functions, primitive-method calls (i64.add, i64.quotient,
# i64.subtract, i64.multiply), local-variable assignments, and a
# primitive literal initializer (U8 0).
public module Solver:
  func sum(a: i64): Status[i64]
    match i64.add(a, 1):
      case Ok { value: b }:
        match i64.multiply(a, b):
          case Ok { value: c }:
            i64.quotient(c, 2)
          case Err { error: err2 }:
            Status[i64].Err { error: err2 }
      case Err { error: err1 }:
        Status[i64].Err { error: err1 }

  func count(a: i64, b: i64): Status[i64]
    match i64.quotient(a, b):
      case Ok { value: c }:
        match Solver.sum(c):
          case Ok { value: d }:
            i64.multiply(b, d)
          case Err { error: err2 }:
            Status[i64].Err { error: err2 }
      case Err { error: err1 }:
        Status[i64].Err { error: err1 }

  public func start(): i64
    match Solver.count(999, 3):
      case Ok { value: a }:
        match Solver.count(999, 5):
          case Ok { value: b }:
            match Solver.count(999, 15):
              case Ok { value: c }:
                match i64.add(a, b):
                  case Ok { value: d }:
                    match i64.subtract(d, c):
                      case Ok { value: e }:
                        e
                      case _:
                        i64 1
                  case _:
                    i64 1
              case _:
                i64 1
          case _:
            i64 1
      case _:
        i64 1
