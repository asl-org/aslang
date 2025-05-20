
module Bitset:
  fn init(U64 size) returns Pointer:
    System.allocate(size)

  fn free(Pointer ptr) returns U8:
    System.free(ptr)

  fn get(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        S64.from(res)
      else:
        failed

  fn set(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn clear(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64 -1
    op = U64.compare(bit, size)
    match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        Pointer.write(bptr, res)
        S64.from(res)
      else:
        failed

  fn toggle(Pointer ptr, U64 size, U64 bit) returns S64:
    data = Bitset.get(ptr, size, bit)
    match data:
      case 0:
        Bitset.set(ptr, size, bit)
      case 1:
        Bitset.clear(ptr, size, bit)
      else:
        data

app Example:
  fn max(U64 a, U64 b) returns U64:
    op = U64.compare(a, b)
    match op:
      case 1:
        a
      else:
        b

  fn mark_non_prime(Pointer primes, U64 j, U64 max_primes, U64 i) returns Pointer:
    op = U64.compare(j, max_primes)
    match op:
      case -1:
        Bitset.set(primes, max_primes, j)
        k = U64.add(j, i)
        Example.mark_non_prime(primes, k, max_primes, i)
      else:
        primes

  fn check_count(Pointer primes, U64 max_primes, U64 i, U64 c) returns U64:
    r = U64.compare(c, 10000)
    match r:
      case 0:
        i
      else:
        next_c = U64.add(c, 1)
        next_i = U64.add(i, 1)
        Example.solve(primes, max_primes, next_i, next_c)

  fn handle_prime(Pointer primes, U64 max_primes, U64 i, U64 c) returns U64:
    op = Bitset.get(primes, max_primes, i)
    match op:
      case 0:
        j = U64.multiply(i, 2)
        Example.mark_non_prime(primes, j, max_primes, i)
        Example.check_count(primes, max_primes, i, c)
      case 1:
        next_i = U64.add(i, 1)
        Example.solve(primes, max_primes, next_i, c)

  fn solve(Pointer primes, U64 max_primes, U64 i, U64 c) returns U64:
    failed = U64 0
    op = U64.compare(i, max_primes)
    match op:
      case -1:
        Example.handle_prime(primes, max_primes, i, c)
      else:
        failed

  fn start(U8 seed) returns U8:
    exit_success = U8 0

    max_primes = U64 1000001
    primes = Bitset.init(max_primes)
    ans = Example.solve(primes, max_primes, 2, 0)
    U64.print(ans)

    exit_success

# int *remove_non_primes(int primes[], int max_primes, int i, int j)
# {
#   if (j >= max_primes)
#     return primes;
#   primes[j] = 1;
#   return remove_non_primes(primes, max_primes, i, j + i);
# }

# int solve_recur(int primes[], int max_primes, int i, int c)
# {
#   if (i >= max_primes)
#     return 0;

#   if (!primes[i])
#   {
#     if (c == 10000)
#       return i;
#     c += 1;
#     primes = remove_non_primes(primes, max_primes, i, 2 * i);
#   }
#   return solve_recur(primes, max_primes, i + 1, c);
# }