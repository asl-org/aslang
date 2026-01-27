module S8:
  extern S8_byte_size:
    fn byte_size(U64 items): U64

  extern S8_read:
    fn read(Pointer ptr, U64 offset): S8

  extern S8_write:
    fn write(S8 value, Pointer ptr, U64 offset): Pointer

module S16:
  extern S16_byte_size:
    fn byte_size(U64 items): U64

  extern S16_read:
    fn read(Pointer ptr, U64 offset): S16

  extern S16_write:
    fn write(S16 value, Pointer ptr, U64 offset): Pointer

module S32:
  extern S32_byte_size:
    fn byte_size(U64 items): U64

  extern S32_read:
    fn read(Pointer ptr, U64 offset): S32

  extern S32_write:
    fn write(S32 value, Pointer ptr, U64 offset): Pointer

module S64:
  extern S64_byte_size:
    fn byte_size(U64 items): U64

  extern S64_read:
    fn read(Pointer ptr, U64 offset): S64

  extern S64_write:
    fn write(S64 value, Pointer ptr, U64 offset): Pointer

  extern S64_add_S64:
    fn add(S64 a, S64 b): S64

  extern S64_subtract_S64:
    fn subtract(S64 a, S64 b): S64

  extern S64_multiply_S64:
    fn multiply(S64 a, S64 b): S64

  extern S64_remainder_S64:
    fn remainder(S64 a, S64 b): S64

  extern S64_quotient_S64:
    fn quotient(S64 a, S64 b): S64

  extern S64_compare_S64:
    fn compare(S64 a, S64 b): S8

  extern S64_from_U8:
    fn from(U8 value): S64

  extern S64_from_U64:
    fn from(U64 value): S64

module Example:
  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _a = match op:
      case 1:
        a
      else:
        b

  fn eq(U64 a, U64 b): U8
    op = U64.compare(a, b)
    _a = match op:
      case 0:
        U8 1
      else:
        U8 0

  fn is_palindrome_loop(U64 a, U64 b, U64 c): U8
    op = U64.compare(c, 0)
    _a = match op:
      case 1:
        b1 = U64.multiply(b, 10)
        b2 = U64.remainder(c, 10)
        b3 = U64.add(b1, b2)

        c1 = U64.quotient(c, 10)
        Example.is_palindrome_loop(a, b3, c1)
      else:
        Example.eq(a, b)

  fn is_palindrome(U64 a): U8
    Example.is_palindrome_loop(a, 0, a)

  fn update_ans(U64 a, U64 k): U64
    op = Example.is_palindrome(a)
    _a = match op:
      case 1:
        Example.max(a, k)
      else:
        k

  fn loop_inner(U64 i, U64 j, U64 k, U64 l): U64
    op = U64.compare(j, l)
    _a = match op:
      case -1:
        a = U64.multiply(i, j)
        next_k = Example.update_ans(a, k)
        next_j = U64.add(j, 1)
        Example.loop_inner(i, next_j, next_k, l)
      else:
        k

  fn loop_outer(U64 i, U64 j, U64 k, U64 l): U64
    op = U64.compare(i, l)
    _a = match op:
      case -1:
        next_k = Example.loop_inner(i, j, k, l)
        next_i = U64.add(i, 1)
        Example.loop_outer(next_i, j, next_k, l)
      else:
        k

fn start(U8 seed): U8
  exit_success = U8 0
  ans = Example.loop_outer(100, 100, 0, 1000)
  System.print(ans)

  exit_success
