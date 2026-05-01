import { u8, u64, Array } from "base.asl"

# Project Euler #3 style exercise — heavy union-variant matching.
# Exercises struct data block (Bitset holding Array[u8]), union
# initializers via Status[u8].Ok / Status[Bitset].Err, variant
# patterns with field bindings (case Ok { value: value }), nested
# match expressions, and generic type parameters on method calls.
module Bitset:
  struct:
    arr: Array[u8]

  func init(size: u64): Bitset
    arr_size = u64.div_ceil(size, 8)
    arr = Array[u8].init(arr_size)
    Bitset { arr: arr }

  func get(bitset: Bitset, bit: u64): Status[u8]
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
        _

  func set(bitset: Bitset, bit: u64): Status[Bitset]
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

  func mark_non_prime(bitset: Bitset, j: u64, i: u64): Status[u8]
    status = Bitset.get(bitset, j)
    match status:
      case Ok { value: value }:
        Bitset.set(bitset, j)
        k = u64.add(j, i)
        Solver.mark_non_prime(bitset, k, i)
      case _:
        status

  func update_ans(i: u64, ans: u64): u64
    r = u64.remainder(600851475143, i)
    match r:
      case 0:
        Solver.max(ans, i)
      case _:
        ans

  func solve(bitset: Bitset, start: u64, ans: u64): u64
    status = Bitset.get(bitset, start)
    match status:
      case Ok { value: value }:
        next_start = u64.add(start, 1)
        match value:
          case 0:
            Solver.mark_non_prime(bitset, start, start)
            new_ans = Solver.update_ans(start, ans)
            Solver.solve(bitset, next_start, new_ans)
          case _:
            Solver.solve(bitset, next_start, ans)
      case _:
        ans

  func start(sys: System): u8
    bitset = Bitset.init(1000001)

    ans = Solver.solve(bitset, 2, 0)
    System.print(ans)

    exit_success = u8 0
