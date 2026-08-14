# Project Euler #9 style exercise — Pythagorean triplet search.
# Exercises inline `# comment` on case arms and at statement scope,
# function overloading (two solve functions with different arity),
# and deeply nested match expressions.
public module Solver:
  func is_triplet(a: u32, b: u32, c: u32): Status[u32]
    match u32.multiply(a, a):
      case Ok { value: a_square }:
        match u32.multiply(b, b):
          case Ok { value: b_square }:
            match u32.multiply(c, c):
              case Ok { value: c_square }:
                match u32.add(a_square, b_square):
                  case Ok { value: left }:
                    match u32.compare(left, c_square):
                      case 0:
                        match u32.multiply(a, b):
                          case Ok { value: d }:
                            u32.multiply(c, d)
                          case Err { error: err5 }:
                            Status[u32].Err { error: err5 }
                      case _:
                        Status.Ok { value: u32 0 }
                  case Err { error: err4 }:
                    Status[u32].Err { error: err4 }
              case Err { error: err3 }:
                Status[u32].Err { error: err3 }
          case Err { error: err2 }:
            Status[u32].Err { error: err2 }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

  func solve(a: u32, b: u32): Status[u32]
    match u32.add(a, b):
      case Ok { value: total }:
        match u32.subtract(1000, total):
          case Ok { value: c }:
            match u32.compare(c, b):
              case 1: # c > b
                match Solver.is_triplet(a, b, c):
                  case Ok { value: result }:
                    match result:
                      case 0:
                        match u32.add(b, 1):
                          case Ok { value: next_b }:
                            Solver.solve(a, next_b)
                          case Err { error: err4 }:
                            Status[u32].Err { error: err4 }
                      case _:
                        match u32.multiply(a, b):
                          case Ok { value: d }:
                            u32.multiply(c, d)
                          case Err { error: err4 }:
                            Status[u32].Err { error: err4 }
                  case Err { error: err3 }:
                    Status[u32].Err { error: err3 }
              case _: # c <= b
                Status.Ok { value: u32 0 }
          case Err { error: err2 }:
            Status[u32].Err { error: err2 }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

  func solve(a: u32): Status[u32]
    # since a < b < c
    # for min sum; b = a + 1 and c = b + 1 = a + 2
    # min_sum = (a) + (a + 1) + (a + 2) = 3 * (a + 1)
    match u32.add(a, 1):
      case Ok { value: next_a }:
        match u32.multiply(3, next_a):
          case Ok { value: min_sum }:
            match u32.compare(min_sum, 1000):
              case 1:
                Status.Ok { value: u32 0 }
              case _:
                match Solver.solve(a, next_a):
                  case Ok { value: result }:
                    match result:
                      case 0:
                        Solver.solve(next_a)
                      case _:
                        Status.Ok { value: result }
                  case Err { error: err3 }:
                    Status[u32].Err { error: err3 }
          case Err { error: err2 }:
            Status[u32].Err { error: err2 }
      case Err { error: err1 }:
        Status[u32].Err { error: err1 }

  public func start(): i32
    match Solver.solve(1):
      case Ok { value: _ }:
        i32 0
      case _:
        i32 1
