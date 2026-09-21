
# Project Euler #1 style exercise — covers module with multiple
# functions, primitive-method calls (i64.add, i64.quotient,
# i64.subtract, i64.multiply), local-variable assignments, and a
# primitive literal initializer (U8 0).
public module Solver:
  func sum(a: i64): i64!
    b = try i64.add(a, 1)
    c = try i64.multiply(a, b)
    i64.quotient(c, 2)

  func count(a: i64, b: i64): i64!
    c = try i64.quotient(a, b)
    d = try Solver.sum(c)
    i64.multiply(b, d)

  func solve(): i64!
    a = try Solver.count(999, 3)
    b = try Solver.count(999, 5)
    c = try Solver.count(999, 15)
    d = try i64.add(a, b)
    i64.subtract(d, c)

  public func start(): i32
    match Solver.solve():
      case Ok {}:
        i32 0
      case _:
        i32 1