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

fn is_triplet(U32 a, U32 b, U32 c): U32
  a_square = U32.multiply(a, a)
  b_square = U32.multiply(b, b)
  c_square = U32.multiply(c, c)
  left = U32.add(a_square, b_square)
  cmp = U32.compare(left, c_square)
  match cmp:
    case 0:
      d = U32.multiply(a, b)
      U32.multiply(c, d)
    case 1:
      U32 0

fn solve(U32 a, U32 b): U32
  total = U32.add(a, b)
  c = U32.subtract(1000, total)
  cmp = U32.compare(c, b)
  match cmp:
    case 1: # c > b
      result = is_triplet(a, b, c)
      match result:
        case 0:
          next_b = U32.add(b, 1)
          solve(a, next_b)
        else:
          d = U32.multiply(a, b)
          U32.multiply(c, d)
    else: # c <= b
      U32 0

fn solve(U32 a): U32
  # since a < b < c
  # for min sum; b = a + 1 and c = b + 1 = a + 2
  # min_sum = (a) + (a + 1) + (a + 2) = 3 * (a + 1)
  next_a = U32.add(a, 1)
  min_sum = U32.multiply(3, next_a)

  cmp = U32.compare(min_sum, 1000)
  match cmp:
    case 1:
      U32 0
    else:
      result = solve(a, next_a)
      match result:
        case 0:
          solve(next_a)
        else:
          result

fn start(U8 seed): U8
  ans = solve(1)
  System.print(ans)
  U8 0
