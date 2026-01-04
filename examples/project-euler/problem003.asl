module Bitset:
  struct:
    Array[U8] arr

  fn init(U64 size): Bitset
    arr_size = div_ceil(size, 8)
    arr = Array[U8].init(arr_size)
    Bitset { arr: arr }

  fn get(Bitset bitset, U64 bit): Status[U8]
    arr = bitset.arr
    arr_index = U64.quotient(bit, 8)
    status = Array[U8].get(arr, arr_index)
    match status:
      case Ok { value: value }:
        offset = U64.remainder(bit, 8)
        temp = U8.rshift(value, offset)
        res = U8.and(temp, 1)
        Status[U8].Ok { value: res }
      else:
        status

  fn set(Bitset bitset, U64 bit): Status[Bitset]
    arr = bitset.arr
    arr_index = U64.quotient(bit, 8)
    get_status = Array[U8].get(arr, arr_index)
    match get_status:
      case Ok { value: value }:
        offset = U64.remainder(bit, 8)
        mask = U8.lshift(1, offset)
        new_value = U8.or(value, mask)
        set_status = Array[U8].set(arr, arr_index, new_value)
        match set_status:
          case Ok { value: _ }:
            Status[Bitset].Ok { value: bitset }
          else:
            set_status
      else:
        get_status

  fn clear(Bitset bitset, U64 bit): Status[Bitset]
    arr = bitset.arr
    arr_index = U64.quotient(bit, 8)
    get_status = Array[U8].get(arr, arr_index)
    match get_status:
      case Ok { value: value }:
        offset = U64.remainder(bit, 8)
        mask = U8.lshift(1, offset)
        inv_mask = U8.not(mask)
        new_value = U8.and(value, inv_mask)
        set_status = Array[U8].set(arr, arr_index, new_value)
        match set_status:
          case Ok { value: _ }:
            Status[Bitset].Ok { value: bitset }
          else:
            set_status
      else:
        get_status

  fn toggle(Bitset bitset, U64 bit): Status[Bitset]
    status = Bitset.get(bitset, bit)
    match status:
      case Ok { value: value }:
        match value:
          case 0:
            Bitset.set(bitset, bit)
          else:
            Bitset.clear(bitset, bit)
      else:
        status

fn div_ceil(U64 a, U64 b): U64
  c = U64.add(a, b)
  d = U64.subtract(c, 1)
  U64.quotient(d, b)

fn max(U64 a, U64 b): U64
  op = U64.compare(a, b)
  _ = match op:
    case 1:
      a
    else:
      b

fn mark_non_prime(Bitset bitset, U64 j, U64 i): Status[U8]
  status = Bitset.get(bitset, j)
  match status:
    case Ok { value: value }:
      Bitset.set(bitset, j)
      k = U64.add(j, i)
      mark_non_prime(bitset, k, i)
    else:
      status

fn update_ans(U64 i, U64 ans): U64
  r = U64.remainder(600851475143, i)
  match r:
    case 0:
      max(ans, i)
    else:
      ans

fn solve(Bitset bitset, U64 start, U64 ans): U64
  status = Bitset.get(bitset, start)
  match status:
    case Ok { value: value }:
      next_start = U64.add(start, 1)
      match value:
        case 0:
          mark_non_prime(bitset, start, start)
          new_ans = update_ans(start, ans)
          solve(bitset, next_start, new_ans)
        else:
          solve(bitset, next_start, ans)
    else:
      ans

fn start(U8 seed): U8
  bitset = Bitset.init(1000001)

  ans = solve(bitset, 2, 0)
  System.print(ans)

  exit_success = U8 0
