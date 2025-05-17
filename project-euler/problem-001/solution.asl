app Example:

  fn sum(S64 a) returns S64:
    b = S64.add(a, 1)
    c = S64.multiply(a, b)
    S64.quotient(c, 2)

  fn count(S64 a, S64 b) returns S64:
    c = S64.quotient(a, b)
    d = MODULE.sum(c)
    S64.multiply(b, d)

  fn start(U8 argc) returns U8:
    exit_success = U8 0

    a = MODULE.count(999, 3)
    b = MODULE.count(999, 5)

    c = MODULE.count(999, 15)
    d = S64.add(a, b)

    e = S64.subtract(d, c)
    S64.print(e)

    exit_success