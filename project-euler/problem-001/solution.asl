module Solver:
  fn sum(S64 a): S64
    b = S64_add(a, 1)
    c = S64_multiply(a, b)
    _ = S64_quotient(c, 2)

  fn count(S64 a, S64 b): S64
    c = S64_quotient(a, b)
    d = Solver.sum(c)
    _ = S64_multiply(b, d)

fn start(U8 seed): U8
  a = Solver.count(999, 3)
  b = Solver.count(999, 5)

  c = Solver.count(999, 15)
  d = S64_add(a, b)

  e = S64_subtract(d, c)
  _ = System_print_S64(e)

  exit_success = U8_init(0)
