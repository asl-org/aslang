module Bitset:
  fn init(U64 size) returns Pointer:
    System.allocate(size)

  fn free(Pointer ptr) returns U8:
    System.free(ptr)

  fn get(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64.subtract(0, 1)
    op = U64.compare(bit, size)
    match op:
      case 1:
        failed
      case 0:
        failed
      else:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        S64.from_U8(res)

  fn set(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64.subtract(0, 1)
    op = U64.compare(bit, size)
    match op:
      case 1:
        failed
      case 0:
        failed
      else:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        Pointer.write_U8(bptr, res)
        S64.from_U8(res)

  fn clear(Pointer ptr, U64 size, U64 bit) returns S64:
    failed = S64.subtract(0, 1)
    op = U64.compare(bit, size)
    match op:
      case 1:
        failed
      case 0:
        failed
      else:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = Pointer.read_U8(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        Pointer.write_U8(bptr, res)
        S64.from_U8(res)

  fn toggle(Pointer ptr, U64 size, U64 bit) returns S64:
    data = MODULE.get(ptr, size, bit)
    match data:
      case 0:
        MODULE.set(ptr, size, bit)
      case 1:
        MODULE.clear(ptr, size, bit)
      else:
        data

app Example:
  fn sample(U64 bytes) returns U8:
    ptr = System.allocate(bytes)
    Pointer.print(ptr)

    Pointer.write_U8(ptr, 255)
    val = Pointer.read_U8(ptr)
    U8.print(val)

    ptr1 = Pointer.shift(ptr, 1)
    Pointer.print(ptr1)
    Pointer.write_U8(ptr1, 255)
    val1 = Pointer.read_U8(ptr1)
    U8.print(val1)

    val2 = Pointer.read_U64(ptr)
    U64.print(val2)

    System.free(ptr)

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    exit_failure = U8 1

    # MODULE.sample(64)

    max_primes = U64 1000001
    primes = Bitset.init(max_primes)

    is_prime_1 = Bitset.get(primes, max_primes, 1)
    S64.print(is_prime_1)

    Bitset.set(primes, max_primes, 1)

    is_prime_1_2 = Bitset.get(primes, max_primes, 1)
    S64.print(is_prime_1_2)

    Bitset.free(primes)
    exit_success