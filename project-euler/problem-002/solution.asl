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
        f = Example.apply(a, d, e)
        g = S64.add(a, b)
        Example.solve(b, g, c, f)

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    a = Example.solve(1, 2, 4000000, 0)
    System.print(a)
    exit_success

