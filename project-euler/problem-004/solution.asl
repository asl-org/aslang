module Example:
  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _a = match op:
      case 1:
        _b = U64.init(a)
      else:
        _c = U64.init(b)

  fn eq(U64 a, U64 b): U8
    op = U64.compare(a, b)
    _a = match op:
      case 0:
        true = U8.init(1)
      else:
        false = U8.init(0)

  fn is_palindrome_loop(U64 a, U64 b, U64 c): U8
    op = U64.compare(c, 0)
    _a = match op:
      case 1:
        b1 = U64.multiply(b, 10)
        b2 = U64.remainder(c, 10)
        b3 = U64.add(b1, b2)

        c1 = U64.quotient(c, 10)
        _b = Example.is_palindrome_loop(a, b3, c1)
      else:
        _c = Example.eq(a, b)

  fn is_palindrome(U64 a): U8
    _a = Example.is_palindrome_loop(a, 0, a)

  fn update_ans(U64 a, U64 k): U64
    op = Example.is_palindrome(a)
    _a = match op:
      case 0:
        _b = U64.init(k)
      case 1:
        _c = Example.max(a, k)

  fn loop_inner(U64 i, U64 j, U64 k, U64 l): U64
    op = U64.compare(j, l)
    _a = match op:
      case -1:
        a = U64.multiply(i, j)
        next_k = Example.update_ans(a, k)
        next_j = U64.add(j, 1)
        _b = Example.loop_inner(i, next_j, next_k, l)
      else:
        _c = U64.init(k)

  fn loop_outer(U64 i, U64 j, U64 k, U64 l): U64
    op = U64.compare(i, l)
    _a = match op:
      case -1:
        next_k = Example.loop_inner(i, j, k, l)
        next_i = U64.add(i, 1)
        _b = Example.loop_outer(next_i, j, next_k, l)
      else:
        _c = U64.init(k)

fn start(U8 seed): U8
  ans = Example.loop_outer(100, 100, 0, 1000)
  _a = System.print_U64(ans)
  exit_success = U8.init(0)

