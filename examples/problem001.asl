module Solution:
  func sum(a: i64): i64
    b = i64.add(a, 1)
    c = i64.multiply(a, b)
    i64.quotient(c, 2)

  func count(a: i64, b: i64): i64
    c = i64.quotient(a, b)
    d = Solver.sum(c)
    i64.multiply(b, d)

  func start(sys: System): U8
    exit_success = U8 0

    a = Solver.count(999, 3)
    b = Solver.count(999, 5)

    c = Solver.count(999, 15)
    d = i64.add(a, b)

    e = i64.subtract(d, c)
    System.print(e)

    exit_success
