module Bitset:
  struct:
    Pointer ptr
    U64 size

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
        S64.from_U8(res)
      else:
        S64.init(-1)

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
        Pointer.write_U8(bptr, res)
        S64.from_U8(res)
      else:
        S64.init(-1)

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
        Pointer.write_U8(bptr, res)
        S64.from_U8(res)
      else:
        S64.init(-1)

  fn toggle(Bitset bitset, U64 bit): S64
    data = Bitset.get(bitset, bit)
    _ = match data:
      case 0:
        Bitset.set(bitset, bit)
      case 1:
        Bitset.clear(bitset, bit)
      else:
        S64.init(-1)

  fn max(U64 a, U64 b): U64
    op = U64.compare(a, b)
    _ = match op:
      case 1:
        U64.init(a)
      else:
        U64.init(b)

  fn mark_non_prime(Bitset bitset, U64 j, U64 i): Pointer
    ptr = bitset.ptr
    size = bitset.size
    op = U64.compare(j, size)
    _ = match op:
      case -1:
        Bitset.set(bitset, j)
        k = U64.add(j, i)
        Bitset.mark_non_prime(bitset, k, i)
      else:
        # TODO: Fix this hack by allowing identifier assignment
        Pointer.init(ptr)

  fn update_ans(U64 i, U64 ans): U64
    r = U64.remainder(600851475143, i)
    _ = match r:
      case 0:
        Bitset.max(ans, i)
      else:
        U64.init(ans)

  fn handle_prime(Bitset bitset, U64 i, U64 ans): U64
    op = Bitset.get(bitset, i)
    _ = match op:
      case 0:
        j = U64.multiply(i, 2)
        Bitset.mark_non_prime(bitset, j, i)
        Bitset.update_ans(i, ans)
      case 1:
        U64.init(ans)

  fn solve(Bitset bitset, U64 start, U64 ans): U64
    size = bitset.size
    op = U64.compare(start, size)
    _ = match op:
      case -1:
        res = Bitset.handle_prime(bitset, start, ans)
        next_start = U64.add(start, 1)
        Bitset.solve(bitset, next_start, res)
      else:
        U64.init(ans)

fn start(U8 seed): U8
  size = U64.init(1000001)
  ptr = System.allocate(size)
  bitset = Bitset { ptr: ptr, size: size }

  ans = Bitset.solve(bitset, 2, 0)
  System.print_U64(ans)

  # _x = Bitset_free(bitset)
  System.free(ptr)

  exit_success = U8.init(0)