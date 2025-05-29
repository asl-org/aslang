app Example:
  fn gcd(U64 a, U64 b) returns U64:
    op = U64.compare(b, 0)
    match op:
      case 0:
        a
      else:
        c = U64.remainder(a, b)
        Example.gcd(b, c)

  fn lcm(U64 a, U64 b) returns U64:
    c = U64.multiply(a, b)
    d = Example.gcd(a, b)
    U64.quotient(c, d)

  fn solve(U64 i, U64 n, U64 j) returns U64:
    op = U64.compare(i, n)
    match op:
      case -1:
        next_i = U64.add(i, 1)
        next_j = Example.lcm(i, j)
        Example.solve(next_i, n, next_j)
      else:
        j

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    ans = Example.solve(2, 20, 1)
    System.print(ans)
    exit_success
