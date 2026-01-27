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
  exit_success = U8 0
  ans = Example.solve(2, 20, 1)
  System.print(ans)
  exit_success
