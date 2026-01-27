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

fn start(U8 seed): U8
  exit_success = U8 0
  n = U64 100

  a = U64.subtract(n, 1)
  b = U64.add(n, 1)

  c = U64.multiply(n, 3)
  d = U64.add(c, 2)

  e = U64.multiply(a, b)
  f = U64.multiply(e, d)
  g = U64.multiply(n, f)

  h = U64.quotient(g, 12)
  System.print(h)

  exit_success
