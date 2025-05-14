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
        e = S64.remainder(a, 2)
        f = MODULE.apply(a, d, e)
        g = S64.add(a, b)
        MODULE.solve(b, g, c, f)

  fn start(Byte seed) returns Byte:
    exit_success = Byte 0
    a = Example.solve(1, 2, 4000000, 0)
    S64.print(a)
    exit_success

