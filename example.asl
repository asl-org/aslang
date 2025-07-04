struct Bitset:
  Pointer ptr
  U64 size

module Bitset:
  fn get(Bitset bitset, U64 bit): S64
    ptr = bitset.ptr
    size = bitset.size
    op = U64.compare(bit, size)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = U8.from_Pointer(bptr)

        bdata = U8.rshift(data, offset)
        res = U8.and(bdata, 1)
        ans = S64.from_U8(res)
      else:
        failed = S64.init(-1)

  fn set(Bitset bitset, U64 bit): S64
    ptr = bitset.ptr
    size = bitset.size
    op = U64.compare(bit, size)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = U8.from_Pointer(bptr)

        mask = U8.lshift(1, offset)
        res = U8.or(data, mask)
        _x = Pointer.write_U8(bptr, res)
        ans = S64.from_U8(res)
      else:
        failed = S64.init(-1)

  fn clear(Bitset bitset, U64 bit): S64
    ptr = bitset.ptr
    size = bitset.size
    op = U64.compare(bit, size)
    _ = match op:
      case -1:
        byte = U64.quotient(bit, 8)
        offset = U64.remainder(bit, 8)

        bptr = Pointer.shift(ptr, byte)
        data = U8.from_Pointer(bptr)

        mask = U8.lshift(1, offset)
        imask = U8.not(mask)
        res = U8.and(data, imask)
        _x = Pointer.write_U8(bptr, res)
        ans = S64.from_U8(res)
      else:
        failure = S64.init(-1)

  fn toggle(Bitset bitset, U64 bit): S64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        ans = Bitset.set(bitset, bit)
      case 1:
        ans = Bitset.clear(bitset, bit)
      else:
        failure = S64.init(-1)

  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _ = match op:
      case 1:
        ans = U64.init(a)
      else:
        ans = U64.init(b)

  fn mark_non_prime(Bitset bitset, U64 j, U64 i): Pointer
    ptr = bitset.ptr
    size = bitset.size
    op = U64.compare(j, size)
    _ = match op:
      case -1:
        _x = Bitset.set(bitset, j)
        k = U64.add(j, i)
        ans = Bitset.mark_non_prime(bitset, k, i)
      else:
        # TODO: Fix this hack by allowing identifier assignment
        ans = Pointer.init(ptr)

  fn update_ans(U64 i, U64 ans): U64
    r = U64.remainder(600851475143, i)
    _ = match r:
      case 0:
        _x = Bitset.max(ans, i)
      else:
        _y = U64.init(ans)

  fn handle_prime(Bitset bitset, U64 i, U64 ans): U64
    op = Bitset.get(bitset, i)
    _ = match op:
      case 0:
        j = U64.multiply(i, 2)
        _x = Bitset.mark_non_prime(bitset, j, i)
        _y = Bitset.update_ans(i, ans)
      case 1:
        _z = U64.init(ans)

  fn solve(Bitset bitset, U64 start, U64 ans): U64
    size = bitset.size
    op = U64.compare(start, size)
    _ = match op:
      case -1:
        res = Bitset.handle_prime(bitset, start, ans)
        next_start = U64.add(start, 1)
        _a = Bitset.solve(bitset, next_start, res)
      else:
        _b = U64.init(ans)

fn start(U8 seed): U8
  size = U64.init(1000001)
  ptr = System.allocate(size)
  bitset = Bitset { ptr: ptr, size: size }

  ans = Bitset.solve(bitset, 2, 0)
  _ = System.print_U64(ans)

  # _x = Bitset_free(bitset)
  _y = System.free(ptr)

  exit_success = U8.init(0)