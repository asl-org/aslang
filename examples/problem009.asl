# Project Euler #9 style exercise — Pythagorean triplet search.
# Exercises inline `# comment` on case arms and at statement scope,
# function overloading (two solve functions with different arity),
# and deeply nested match expressions.
module Solver:
  func is_triplet(a: u32, b: u32, c: u32): u32
    a_square = u32.multiply(a, a)
    b_square = u32.multiply(b, b)
    c_square = u32.multiply(c, c)
    left = u32.add(a_square, b_square)
    cmp = u32.compare(left, c_square)
    match cmp:
      case 0:
        d = u32.multiply(a, b)
        u32.multiply(c, d)
      case _:
        u32 0

  func solve(a: u32, b: u32): u32
    total = u32.add(a, b)
    c = u32.subtract(1000, total)
    cmp = u32.compare(c, b)
    match cmp:
      case 1: # c > b
        result = Solver.is_triplet(a, b, c)
        match result:
          case 0:
            next_b = u32.add(b, 1)
            Solver.solve(a, next_b)
          case _:
            d = u32.multiply(a, b)
            u32.multiply(c, d)
      case _: # c <= b
        u32 0

  func solve(a: u32): u32
    # since a < b < c
    # for min sum; b = a + 1 and c = b + 1 = a + 2
    # min_sum = (a) + (a + 1) + (a + 2) = 3 * (a + 1)
    next_a = u32.add(a, 1)
    min_sum = u32.multiply(3, next_a)

    cmp = u32.compare(min_sum, 1000)
    match cmp:
      case 1:
        u32 0
      case _:
        result = Solver.solve(a, next_a)
        match result:
          case 0:
            Solver.solve(next_a)
          case _:
            result

  func start(sys: System): u8
    ans = Solver.solve(1)
    System.print(ans)
    u8 0
