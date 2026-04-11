# Project Euler #10 style exercise — sum of primes via sieve.
# The largest single-file example: three top-level modules (Utils,
# Bitset, Solver) in one file, struct with generic Array[u8] field,
# deeply nested union-variant patterns, cross-module function calls
# (Bitset.get from Solver), and Error struct-initializer literals
# embedded inside union variants.
module Utils:
  func div_ceil(a: u64, b: u64): u64
    c = u64.add(a, b)
    d = u64.subtract(c, 1)
    u64.quotient(d, b)

  func max(a: u64, b: u64): u64
    op = u64.compare(a, b)
    _ = match op:
      case 1:
        a
      case _:
        b

module Bitset:
  struct:
    arr: Array[u8]
    size: u64

  func init(size: u64): Bitset
    arr_size = Utils.div_ceil(size, 8)
    arr = Array[u8].init(arr_size)
    Bitset { arr: arr, size: size }

  func get(bitset: Bitset, bit: u64): Status[u8]
    bitset_size = bitset.size
    cmp = u64.compare(bit, bitset_size)
    match cmp:
      case -1:
        arr = bitset.arr
        arr_index = u64.quotient(bit, 8)
        status = Array[u8].get(arr, arr_index)
        match status:
          case Ok { value: value }:
            offset = u64.remainder(bit, 8)
            temp = u8.rshift(value, offset)
            res = u8.and(temp, 1)
            Status[u8].Ok { value: res }
          case _:
            status
      case _:
        error = Error { code: 1, message: "Index out of bound" }
        Status[u8].Err { error: error }

  func set(bitset: Bitset, bit: u64): Status[Bitset]
    bitset_size = bitset.size
    cmp = u64.compare(bit, bitset_size)
    match cmp:
      case -1:
        arr = bitset.arr
        arr_index = u64.quotient(bit, 8)
        get_status = Array[u8].get(arr, arr_index)
        match get_status:
          case Ok { value: value }:
            offset = u64.remainder(bit, 8)
            mask = u8.lshift(1, offset)
            new_value = u8.or(value, mask)
            set_status = Array[u8].set(arr, arr_index, new_value)
            match set_status:
              case Ok { value: _ }:
                Status[Bitset].Ok { value: bitset }
              case Err { error: temp }:
                Status[Bitset].Err { error: temp }
          case Err { error: temp }:
            Status[Bitset].Err { error: temp }
      case _:
        error = Error { code: 1, message: "Index out of bound" }
        Status[Bitset].Err { error: error }

  func clear(bitset: Bitset, bit: u64): Status[Bitset]
    arr = bitset.arr
    arr_index = u64.quotient(bit, 8)
    get_status = Array[u8].get(arr, arr_index)
    match get_status:
      case Ok { value: value }:
        offset = u64.remainder(bit, 8)
        mask = u8.lshift(1, offset)
        inv_mask = u8.not(mask)
        new_value = u8.and(value, inv_mask)
        set_status = Array[u8].set(arr, arr_index, new_value)
        match set_status:
          case Ok { value: _ }:
            Status[Bitset].Ok { value: bitset }
          case Err { error: temp }:
            Status[Bitset].Err { error: temp }
      case Err { error: temp1 }:
        Status[Bitset].Err { error: temp1 }

  func toggle(bitset: Bitset, bit: u64): Status[Bitset]
    status = Bitset.get(bitset, bit)
    match status:
      case Ok { value: value }:
        match value:
          case 0:
            Bitset.set(bitset, bit)
          case _:
            Bitset.clear(bitset, bit)
      case Err { error: temp }:
        Status[Bitset].Err { error: temp }

module Solver:
  func mark_non_prime(bitset: Bitset, j: u64, i: u64): Status[u8]
    status = Bitset.get(bitset, j)
    match status:
      case Ok { value: value }:
        Bitset.set(bitset, j)
        k = u64.add(j, i)
        Solver.mark_non_prime(bitset, k, i)
      case _:
        status

  func solve(bitset: Bitset, start: u64, ans: u64): u64
    status = Bitset.get(bitset, start)
    match status:
      case Ok { value: value }:
        next_start = u64.add(start, 1)
        match value:
          case 0:
            Solver.mark_non_prime(bitset, start, start)
            new_ans = u64.add(ans, start)
            Solver.solve(bitset, next_start, new_ans)
          case _:
            Solver.solve(bitset, next_start, ans)
      case _:
        ans

  func start(sys: System): u8
    bitset = Bitset.init(2000001)

    ans = Solver.solve(bitset, 2, 0)
    System.print(ans)

    exit_success = u8 0
