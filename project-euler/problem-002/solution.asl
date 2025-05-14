app Example:
  fn apply(S64 a, S64 b, S64 c) returns S64:
    match c:
      case 0:
        S64.add(a, b)
      case 1:
        b

  fn solve(S64 a, S64 b, S64 c, S64 d) returns S64:
    op = S64.compare(a, c)
    match op:
      case 1:
        d
      else:
        s = S64 2
        e = S64.remainder(a, s)
        f = MODULE.apply(a, d, e)
        g = S64.add(a, b)
        MODULE.solve(b, g, c, f)

  fn start(Byte seed) returns Byte:
    a = S64 1
    b = S64 2
    c = S64 4000000
    d = S64 0
    e = Example.solve(a, b, c, d)
    S64.print(e)
    f = Byte 0

