import { i64 } from "base.asl"

# Project Euler #1 style exercise — covers module with multiple
# functions, primitive-method calls (i64.add, i64.quotient,
# i64.subtract, i64.multiply), local-variable assignments, and a
# primitive literal initializer (U8 0).
public module Solver:
  func sum(a: i64): i64
    b = i64.add(a, 1)
    c = i64.multiply(a, b)
    i64.quotient(c, 2)

  func count(a: i64, b: i64): i64
    c = i64.quotient(a, b)
    d = Solver.sum(c)
    i64.multiply(b, d)

  public func test(): i64
    a = Solver.count(999, 3)
    b = Solver.count(999, 5)

    c = Solver.count(999, 15)
    d = i64.add(a, b)

    e = i64.subtract(d, c)
