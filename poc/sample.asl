struct Bitset:
  Pointer ptr
  U64 size

fn Bitset_get(Bitset bitset, U64 bit): S64
  ptr = bitset.ptr
  size = bitset.size
  op = U64_compare(bit, size)
  _ = match op:
    case -1:
      byte = U64_quotient(bit, 8)
      offset = U64_remainder(bit, 8)

      bptr = Pointer_shift(ptr, byte)
      data = U8_from_Pointer(bptr)

      bdata = U8_rshift(data, offset)
      res = U8_and(bdata, 1)
      ans = S64_from_U8(res)
    else:
      failed = S64_init(-1)

fn Bitset_set(Bitset bitset, U64 bit): S64
  ptr = bitset.ptr
  size = bitset.size
  op = U64_compare(bit, size)
  _ = match op:
    case -1:
      byte = U64_quotient(bit, 8)
      offset = U64_remainder(bit, 8)

      bptr = Pointer_shift(ptr, byte)
      data = U8_from_Pointer(bptr)

      mask = U8_lshift(1, offset)
      res = U8_or(data, mask)
      _x = Pointer_write_U8(bptr, res)
      ans = S64_from_U8(res)
    else:
      failed = S64_init(-1)

fn Bitset_clear(Bitset bitset, U64 bit): S64
  ptr = bitset.ptr
  size = bitset.size
  op = U64_compare(bit, size)
  _ = match op:
    case -1:
      byte = U64_quotient(bit, 8)
      offset = U64_remainder(bit, 8)

      bptr = Pointer_shift(ptr, byte)
      data = U8_from_Pointer(bptr)

      mask = U8_lshift(1, offset)
      imask = U8_not(mask)
      res = U8_and(data, imask)
      _ = Pointer_write(bptr, res)
      ans = S64_from_U8(res)
    else:
      failure = S64_init(-1)

fn Bitset_toggle(Bitset bitset, U64 bit): S64
  data = Bitset_get(bitset, bit)
  _ = match data:
    case 0:
      ans = Bitset_set(bitset, bit)
    case 1:
      ans = Bitset_clear(bitset, bit)
    else:
      failure = S64_init(-1)

fn max(U64 a, U64 b): U64
  op = U64_compare(a, b)
  _ = match op:
    case 1:
      ans = U64_init(a)
    else:
      ans = U64_init(b)

fn mark_non_prime(Bitset bitset, U64 j, U64 i): Pointer
  ptr = bitset.ptr
  size = bitset.size
  op = U64_compare(j, size)
  _ = match op:
    case -1:
      _x = Bitset_set(bitset, j)
      k = U64_add(j, i)
      ans = mark_non_prime(bitset, k, i)
    else:
      # TODO: Fix this hack by allowing identifier assignment
      ans = Pointer_init(ptr)

fn update_ans(U64 i, U64 ans): U64
  r = U64_remainder(600851475143, i)
  _ = match r:
    case 0:
      _x = max(ans, i)
    else:
      _y = U64_init(ans)

fn handle_prime(Bitset bitset, U64 i, U64 ans): U64
  op = Bitset_get(bitset, i)
  _ = match op:
    case 0:
      j = U64_multiply(i, 2)
      _x = mark_non_prime(bitset, j, i)
      _y = update_ans(i, ans)
    case 1:
      _z = U64_init(ans)

fn solve(Bitset bitset, U64 start, U64 ans): U64
  size = bitset.size
  op = U64_compare(start, size)
  _ = match op:
    case -1:
      res = handle_prime(bitset, start, ans)
      next_start = U64_add(start, 1)
      _a = solve(bitset, next_start, res)
    else:
      _b = U64_init(ans)

fn start(U8 seed): U8
  max_primes = U64_init(1000001)
  ptr = System_allocate(max_primes)
  bitset = Bitset_init(ptr, max_primes)

  ans = solve(bitset, 2, 0)
  _ = System_print_U64(ans)

  _x = Bitset_free(bitset)
  _y = System_free(ptr)

  exit_success = U8_init(0)