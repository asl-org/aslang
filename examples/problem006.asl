# Project Euler #6 style exercise — closed-form arithmetic. The
# simplest example that exercises only primitive literal
# initializers (u64 100) and primitive method calls without any
# match, data blocks, or recursion.
public module Solver:
  public func solve(): u64!
    n = u64 100
    a = try u64.subtract(n, 1)
    b = try u64.add(n, 1)
    c = try u64.multiply(n, 3)
    d = try u64.add(c, 2)
    e = try u64.multiply(a, b)
    f = try u64.multiply(e, d)
    g = try u64.multiply(n, f)
    u64.quotient(g, 12)

  public func start(): i32
    match Solver.solve():
      case Ok { }:
        i32 0
      case Err { }:
        i32 1