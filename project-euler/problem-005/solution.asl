module Example:
  fn gcd(U64 a, U64 b): U64
    op = U64.compare(b, 0)
    _ = match op:
      case 0:
        a
      else:
        c = U64.remainder(a, b)
        Example.gcd(b, c)

  fn lcm(U64 a, U64 b): U64
    c = U64.multiply(a, b)
    d = Example.gcd(a, b)
    U64.quotient(c, d)

  fn solve(U64 i, U64 n, U64 j): U64
    op = U64.compare(i, n)
    _ = match op:
      case -1:
        next_i = U64.add(i, 1)
        next_j = Example.lcm(i, j)
        Example.solve(next_i, n, next_j)
      else:
        j

fn start(U8 seed): U8
  exit_success = U8.init(0)
  ans = Example.solve(2, 20, 1)
  System.print_U64(ans)
  exit_success
