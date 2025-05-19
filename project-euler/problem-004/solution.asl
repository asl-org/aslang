app Example:
  fn max(U64 a, U64 b) returns U64:
    op = U64.compare(a, b)
    match op:
      case 1:
        a
      else:
        b

  fn eq(U64 a, U64 b) returns U8:
    true = U8 1
    false = U8 0

    op = U64.compare(a, b)
    match op:
      case 0:
        true
      else:
        false

  fn is_palindrome_loop(U64 a, U64 b, U64 c) returns U8:
    op = U64.compare(c, 0)
    match op:
      case 1:
        b1 = U64.multiply(b, 10)
        b2 = U64.remainder(c, 10)
        b3 = U64.add(b1, b2)

        c1 = U64.quotient(c, 10)
        MODULE.is_palindrome_loop(a, b3, c1)
      else:
        MODULE.eq(a, b)

  fn is_palindrome(U64 a) returns U8:
    MODULE.is_palindrome_loop(a, 0, a)

  fn update_ans(U64 a, U64 k) returns U64:
    op = MODULE.is_palindrome(a)
    match op:
      case 0:
        k
      case 1:
        MODULE.max(a, k)

  fn loop_inner(U64 i, U64 j, U64 k, U64 l) returns U64:
    op = U64.compare(j, l)
    match op:
      case -1:
        a = U64.multiply(i, j)
        next_k = MODULE.update_ans(a, k)
        next_j = U64.add(j, 1)
        MODULE.loop_inner(i, next_j, next_k, l)
      else:
        k

  fn loop_outer(U64 i, U64 j, U64 k, U64 l) returns U64:
    op = U64.compare(i, l)
    match op:
      case -1:
        next_k = MODULE.loop_inner(i, j, k, l)
        next_i = U64.add(i, 1)
        MODULE.loop_outer(next_i, j, next_k, l)
      else:
        k

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    ans = MODULE.loop_outer(100, 100, 0, 1000)
    U64.print(ans)
    exit_success

