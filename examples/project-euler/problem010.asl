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

module U8:
  extern U8_byte_size:
    fn byte_size(U64 items): U64

  extern U8_read:
    fn read(Pointer ptr, U64 offset): U8

  extern U8_write:
    fn write(U8 value, Pointer ptr, U64 offset): Pointer

  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8

  extern U8_rshift_U8:
    fn rshift(U8 value, U64 offset): U8

  extern U8_and_U8:
    fn and(U8 a, U8 b): U8

  extern U8_or_U8:
    fn or(U8 a, U8 b): U8

  extern U8_not:
    fn not(U8 a): U8

  extern U8_from_U64:
    fn from(U64 value): U8

  extern U8_subtract_U8:
    fn subtract(U8 a, U8 b): U8

module U16:
  extern U16_byte_size:
    fn byte_size(U64 items): U64

  extern U16_read:
    fn read(Pointer ptr, U64 offset): U16

  extern U16_write:
    fn write(U16 value, Pointer ptr, U64 offset): Pointer

module U32:
  extern U32_byte_size:
    fn byte_size(U64 items): U64

  extern U32_read:
    fn read(Pointer ptr, U64 offset): U32

  extern U32_write:
    fn write(U32 value, Pointer ptr, U64 offset): Pointer

  extern U32_add_U32:
    fn add(U32 a, U32 b): U32

  extern U32_subtract_U32:
    fn subtract(U32 a, U32 b): U32

  extern U32_multiply_U32:
    fn multiply(U32 a, U32 b): U32

  extern U32_compare_U32:
    fn compare(U32 a, U32 b): S8

module U64:
  extern U64_byte_size:
    fn byte_size(U64 items): U64

  extern U64_read:
    fn read(Pointer ptr, U64 offset): U64

  extern U64_write:
    fn write(U64 value, Pointer ptr, U64 offset): Pointer

  extern U64_add_U64:
    fn add(U64 a, U64 b): U64

  extern U64_subtract_U64:
    fn subtract(U64 a, U64 b): U64

  extern U64_multiply_U64:
    fn multiply(U64 a, U64 b): U64

  extern U64_quotient_U64:
    fn quotient(U64 a, U64 b): U64

  extern U64_remainder_U64:
    fn remainder(U64 a, U64 b): U64

  extern U64_compare_U64:
    fn compare(U64 a, U64 b): S8

  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8

  extern U64_rshift_U64:
    fn rshift(U64 value, U64 offset): U64

  extern U64_and_U64:
    fn and(U64 a, U64 b): U64

  extern U64_or_U64:
    fn or(U64 a, U64 b): U64

  extern U64_not:
    fn not(U64 a): U64

  extern U64_from_U8:
    fn from(U8 value): U64

module F32:
  extern F32_byte_size:
    fn byte_size(U64 items): U64

  extern F32_read:
    fn read(Pointer ptr, U64 offset): F32

  extern F32_write:
    fn write(F32 value, Pointer ptr, U64 offset): Pointer

module F64:
  extern F64_byte_size:
    fn byte_size(U64 items): U64

  extern F64_read:
    fn read(Pointer ptr, U64 offset): F64

  extern F64_write:
    fn write(F64 value, Pointer ptr, U64 offset): Pointer

module String:
  extern String_byte_size:
    fn byte_size(U64 items): U64

  extern String_read:
    fn read(Pointer ptr, U64 offset): String

  extern String_write:
    fn write(String value, Pointer ptr, U64 offset): Pointer

  extern String_get:
    fn get(String value, U64 index): Status[U8]

module Pointer:
  extern Pointer_byte_size:
    fn byte_size(U64 items): U64

  extern Pointer_read:
    fn read(Pointer ptr, U64 offset): Pointer

  extern Pointer_write:
    fn write(Pointer value, Pointer ptr, U64 offset): Pointer

module Error:
  struct:
    S32 code
    String message

module Status:
  generic Value
  struct Ok:
    Value value
  struct Err:
    Error error

module Array:
  generic Item
  struct:
    U64 size

  extern Array_init:
    fn init(U64 size): Array[Item]

  extern Array_set:
    fn set(Array[Item] arr, U64 index, Item value): Status[Array[Item]]

  extern Array_get:
    fn get(Array[Item] arr, U64 index): Status[Item]

module System:
  extern System_allocate:
    fn allocate(U64 bytes): Pointer

  extern System_free:
    fn free(Pointer ptr): U64

  extern System_box_U8:
    fn box(U8 value): Pointer

  extern System_box_U64:
    fn box(U64 value): Pointer

  extern System_box_S32:
    fn box(S32 value): Pointer

  extern System_box_S64:
    fn box(S64 value): Pointer

  extern System_box_Pointer:
    fn box(Pointer value): Pointer

  extern System_print_U8:
    fn print(U8 value): U64

  extern System_print_U16:
    fn print(U16 value): U64

  extern System_print_U32:
    fn print(U32 value): U64

  extern System_print_U64:
    fn print(U64 value): U64

  extern System_print_S8:
    fn print(S8 value): U64

  extern System_print_S16:
    fn print(S16 value): U64

  extern System_print_S32:
    fn print(S32 value): U64

  extern System_print_S64:
    fn print(S64 value): U64

  extern System_print_F32:
    fn print(F32 value): U64

  extern System_print_F64:
    fn print(F64 value): U64

  extern System_print_String:
    fn print(String value): U64

fn div_ceil(U64 a, U64 b): U64
  c = U64.add(a, b)
  d = U64.subtract(c, 1)
  U64.quotient(d, b)

module Bitset:
  struct:
    Array[U8] arr
    U64 size

  fn init(U64 size): Bitset
    arr_size = div_ceil(size, 8)
    arr = Array[U8].init(arr_size)
    Bitset { arr: arr, size: size }

  fn get(Bitset bitset, U64 bit): Status[U8]
    bitset_size = bitset.size
    cmp = U64.compare(bit, bitset_size)
    match cmp:
      case -1:
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
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status[U8].Err { error: error }

  fn set(Bitset bitset, U64 bit): Status[Bitset]
    bitset_size = bitset.size
    cmp = U64.compare(bit, bitset_size)
    match cmp:
      case -1:
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
              case Err { error: temp }:
                Status[Bitset].Err { error: temp }
          case Err { error: temp }:
            Status[Bitset].Err { error: temp }
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status[Bitset].Err { error: error }

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
          case Err { error: temp }:
            Status[Bitset].Err { error: temp }
      case Err { error: temp1 }:
        Status[Bitset].Err { error: temp1 }

  fn toggle(Bitset bitset, U64 bit): Status[Bitset]
    status = Bitset.get(bitset, bit)
    match status:
      case Ok { value: value }:
        match value:
          case 0:
            Bitset.set(bitset, bit)
          else:
            Bitset.clear(bitset, bit)
      case Err { error: temp }:
        Status[Bitset].Err { error: temp }

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

fn solve(Bitset bitset, U64 start, U64 ans): U64
  status = Bitset.get(bitset, start)
  match status:
    case Ok { value: value }:
      next_start = U64.add(start, 1)
      match value:
        case 0:
          mark_non_prime(bitset, start, start)
          new_ans = U64.add(ans, start)
          solve(bitset, next_start, new_ans)
        else:
          solve(bitset, next_start, ans)
    else:
      ans

fn start(U8 seed): U8
  bitset = Bitset.init(2000001)

  ans = solve(bitset, 2, 0)
  System.print(ans)

  exit_success = U8 0
