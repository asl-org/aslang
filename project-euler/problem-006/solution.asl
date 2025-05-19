app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 0
    n = U64 100

    a = U64.subtract(n, 1)
    b = U64.add(n, 1)

    c = U64.multiply(n, 3)
    d = U64.add(c, 2)

    e = U64.multiply(a, b)
    f = U64.multiply(e, d)
    g = U64.multiply(n, f)

    h = U64.quotient(g, 12)
    U64.print(h)

    exit_success
