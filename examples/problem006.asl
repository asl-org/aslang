module Solver:
  func start(sys: System): u8
    exit_success = u8 0
    n = u64 100

    a = u64.subtract(n, 1)
    b = u64.add(n, 1)

    c = u64.multiply(n, 3)
    d = u64.add(c, 2)

    e = u64.multiply(a, b)
    f = u64.multiply(e, d)
    g = u64.multiply(n, f)

    h = u64.quotient(g, 12)
    System.print(h)

    exit_success
