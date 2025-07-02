fn Example_max(U64 a, U64 b): U64
  op = U64_compare(a, b)
  _a = match op:
    case 1:
      _b = U64_init(a)
    else:
      _c = U64_init(b)

fn Example_eq(U64 a, U64 b): U8
  op = U64_compare(a, b)
  _a = match op:
    case 0:
      true = U8_init(1)
    else:
      false = U8_init(0)

fn Example_is_palindrome_loop(U64 a, U64 b, U64 c): U8
  op = U64_compare(c, 0)
  _a = match op:
    case 1:
      b1 = U64_multiply(b, 10)
      b2 = U64_remainder(c, 10)
      b3 = U64_add(b1, b2)

      c1 = U64_quotient(c, 10)
      _b = Example_is_palindrome_loop(a, b3, c1)
    else:
      _c = Example_eq(a, b)

fn Example_is_palindrome(U64 a): U8
  _a = Example_is_palindrome_loop(a, 0, a)

fn Example_update_ans(U64 a, U64 k): U64
  op = Example_is_palindrome(a)
  _a = match op:
    case 0:
      _b = U64_init(k)
    case 1:
      _c = Example_max(a, k)

fn Example_loop_inner(U64 i, U64 j, U64 k, U64 l): U64
  op = U64_compare(j, l)
  _a = match op:
    case -1:
      a = U64_multiply(i, j)
      next_k = Example_update_ans(a, k)
      next_j = U64_add(j, 1)
      _b = Example_loop_inner(i, next_j, next_k, l)
    else:
      _c = U64_init(k)

fn Example_loop_outer(U64 i, U64 j, U64 k, U64 l): U64
  op = U64_compare(i, l)
  _a = match op:
    case -1:
      next_k = Example_loop_inner(i, j, k, l)
      next_i = U64_add(i, 1)
      _b = Example_loop_outer(next_i, j, next_k, l)
    else:
      _c = U64_init(k)

fn start(U8 seed): U8
  ans = Example_loop_outer(100, 100, 0, 1000)
  _a = System_print_U64(ans)
  exit_success = U8_init(0)

