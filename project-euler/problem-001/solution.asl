app Example:

  fn sum(S64 a) returns S64:
    b = S64.add(a, 1)
    c = S64.multiply(a, b)
    S64.quotient(c, 2)

  fn count(S64 a, S64 b) returns S64:
    c = S64.quotient(a, b)
    d = Example.sum(c)
    S64.multiply(b, d)

  fn start(U8 argc) returns U8:
    exit_success = U8 0

    a = Example.count(999, 3)
    b = Example.count(999, 5)

    c = Example.count(999, 15)
    d = S64.add(a, b)

    e = S64.subtract(d, c)
    System.print(e)

    exit_success