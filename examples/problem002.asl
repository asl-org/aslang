module Solver:
  func apply(a: i64, b: i64, c: i64): i64
    ans = match c:
      case 0:
        i64.add(a, b)
      case _:
        b

  func solve(a: i64, b: i64, c: i64, d: i64): i64
    op = i64.compare(a, c)
    ans = match op:
      case 1:
        d
      case _:
        e = i64.remainder(a, 2)
        f = Solver.apply(a, d, e)
        g = i64.add(a, b)
        Solver.solve(b, g, c, f)

  func start(sys: System): u8
    exit_success = u8 0

    a = Solver.solve(1, 2, 4000000, 0)
    System.print(a)

    exit_success
