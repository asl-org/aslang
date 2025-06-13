
fn Bitset_get(Pointer ptr, U64 size, U64 bit): S64
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

fn Bitset_set(Pointer ptr, U64 size, U64 bit): S64
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

fn Bitset_clear(Pointer ptr, U64 size, U64 bit): S64
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

fn Bitset_toggle(Pointer ptr, U64 size, U64 bit): S64
  data = Bitset_get(ptr, size, bit)
  _ = match data:
    case 0:
      ans = Bitset_set(ptr, size, bit)
    case 1:
      ans = Bitset_clear(ptr, size, bit)
    else:
      failure = S64_init(-1)

fn max(U64 a, U64 b): U64
  op = U64_compare(a, b)
  _ = match op:
    case 1:
      ans = U64_init(a)
    else:
      ans = U64_init(b)

fn mark_non_prime(Pointer primes_ptr, U64 primes_size, U64 j, U64 i): Pointer
  op = U64_compare(j, primes_size)
  _ = match op:
    case -1:
      _x = Bitset_set(primes_ptr, primes_size, j)
      k = U64_add(j, i)
      ans = mark_non_prime(primes_ptr, primes_size, k, i)
    else:
      # TODO: Fix this hack by allowing identifier assignment
      ans = Pointer_init(primes_ptr)

fn update_ans(U64 i, U64 ans): U64
  r = U64_remainder(600851475143, i)
  _ = match r:
    case 0:
      _x = max(ans, i)
    else:
      _y = U64_init(ans)

fn handle_prime(Pointer primes_ptr, U64 primes_size, U64 i, U64 ans): U64
  op = Bitset_get(primes_ptr, primes_size, i)
  _ = match op:
    case 0:
      j = U64_multiply(i, 2)
      _x = mark_non_prime(primes_ptr, primes_size, j, i)
      _y = update_ans(i, ans)
    case 1:
      _z = U64_init(ans)

fn solve(Pointer primes_ptr, U64 primes_size, U64 start, U64 ans): U64
  op = U64_compare(start, primes_size)
  _ = match op:
    case -1:
      res = handle_prime(primes_ptr, primes_size, start, ans)
      next_start = U64_add(start, 1)
      _a = solve(primes_ptr, primes_size, next_start, res)
    else:
      _b = U64_init(ans)

fn start(U8 seed): U8
  max_primes = U64_init(1000001)
  ptr = System_allocate(max_primes)

  ans = solve(ptr, max_primes, 2, 0)
  _a = System_print_U64(ans)

  _b = System_free(ptr)
  exit_success = U8_init(0)