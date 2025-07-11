module Solver:
  fn sum(S64 a): S64
    b = S64.add(a, 1)
    c = S64.multiply(a, b)
    _ = S64.quotient(c, 2)

  fn count(S64 a, S64 b): S64
    c = S64.quotient(a, b)
    d = Solver.sum(c)
    _ = S64.multiply(b, d)

fn start(U8 seed): U8
  a = Solver.count(999, 3)
  b = Solver.count(999, 5)

  c = Solver.count(999, 15)
  d = S64.add(a, b)

  e = S64.subtract(d, c)
  _ = System.print_S64(e)

  exit_success = U8.init(0)
