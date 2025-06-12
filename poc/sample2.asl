fn apply(S64 a, S64 b, S64 c): S64
  ans = match c:
    case 0:
      _a = S64_add(a, b)
    case 1:
      _b = S64_init(b)

fn solve(S64 a, S64 b, S64 c, S64 d): S64
  op = S64_compare(a, c)
  ans = match op:
    case 1:
      _x = S64_init(d)
    else:
      e = S64_remainder(a, 2)
      f = apply(a, d, e)
      g = S64_add(a, b)
      _y = solve(b, g, c, f)

fn start(U8 seed): U8
  a = solve(1, 2, 4000000, 0)
  _ = System_print_S64(a)
  exit_success = U8_init(0)
