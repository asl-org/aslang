# Project Euler #9 style exercise — Pythagorean triplet search.
# Exercises inline `# comment` on case arms and at statement scope,
# function overloading (two solve functions with different arity),
# and deeply nested match expressions.
public module Solver:
  func is_triplet(a: u32, b: u32, c: u32): u32!
    a_square = try u32.multiply(a, a)
    b_square = try u32.multiply(b, b)
    c_square = try u32.multiply(c, c)
    left = try u32.add(a_square, b_square)
    match u32.compare(left, c_square):
      case 0:
        d = try u32.multiply(a, b)
        u32.multiply(c, d)
      case _:
        u32!.Ok { value: u32 0 }

  func solve(a: u32, b: u32): u32!
    total = try u32.add(a, b)
    c = try u32.subtract(1000, total)
    match u32.compare(c, b):
      case 1: # c > b
        result = try Solver.is_triplet(a, b, c)
        match result:
          case 0:
            next_b = try u32.add(b, 1)
            Solver.solve(a, next_b)
          case _:
            d = try u32.multiply(a, b)
            u32.multiply(c, d)
      case _: # c <= b
        u32!.Ok { value: u32 0 }

  func solve(a: u32): u32!
    # since a < b < c
    # for min sum; b = a + 1 and c = b + 1 = a + 2
    # min_sum = (a) + (a + 1) + (a + 2) = 3 * (a + 1)
    next_a = try u32.add(a, 1)
    min_sum = try u32.multiply(3, next_a)
    match u32.compare(min_sum, 1000):
      case 1:
        u32!.Ok { value: u32 0 }
      case _:
        result = try Solver.solve(a, next_a)
        match result:
          case 0:
            Solver.solve(next_a)
          case _:
            u32!.Ok { value: result }

  public func start(): i32
    match Solver.solve(1):
      case Ok { value: _ }:
        i32 0
      case _:
        i32 1
