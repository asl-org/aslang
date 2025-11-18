module Solver:
  fn apply(S64 a, S64 b, S64 c): S64
    ans = match c:
      case 0:
        S64.add(a, b)
      else:
        b

  fn solve(S64 a, S64 b, S64 c, S64 d): S64
    op = S64.compare(a, c)
    ans = match op:
      case 1:
        d
      else:
        e = S64.remainder(a, 2)
        f = Solver.apply(a, d, e)
        g = S64.add(a, b)
        Solver.solve(b, g, c, f)

fn start(U8 seed): U8
  exit_success = U8 0

  a = Solver.solve(1, 2, 4000000, 0)
  System.print(a)

  exit_success
