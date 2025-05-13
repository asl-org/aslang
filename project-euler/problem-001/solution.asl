app Example:

  fn sum(S64 a) returns S64:
    x = S64 1
    y = S64 2
    b = S64.add(a, x)
    c = S64.multiply(a, b)
    S64.quotient(c, y)

  fn count(S64 a, S64 b) returns S64:
    c = S64.quotient(a, b)
    d = MODULE.sum(c)
    S64.multiply(b, d)

  fn start(Byte argc) returns Byte:
    n  = S64 999
    na = S64 3
    nb = S64 5
    nc = S64 15

    a = MODULE.count(n, na)
    b = MODULE.count(n, nb)
    c = MODULE.count(n, nc)

    d = S64.add(a, b)
    e = S64.subtract(d, c)
    S64.print(e)

    # return code 0
    _ = Byte 0