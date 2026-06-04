public module u8:
  literal: "u8"

  # core
  @extern("u8_read")
  public func read(ptr: Pointer, offset: u64): u8

  @extern("u8_byte_size")
  public func byte_size(items: u32): u64

  @extern("u8_valid")
  public func valid(value: u8): u8

  @extern("u8_write")
  public func write(ptr: Pointer, offset: u64, item: u8): Pointer

  # binary
  @extern("u8_and_u8")
  public func and(a: u8, b: u8): u8

  @extern("u8_or_u8")
  public func or(a: u8, b: u8): u8

  @extern("u8_xor_u8")
  public func xor(a: u8, b: u8): u8

  @extern("u8_shr_u8")
  public func shr(a: u8, b: u8): u8

  @extern("u8_shl_u8")
  public func shl(a: u8, b: u8): u8

  @extern("u8_not_u8")
  public func not(a: u8): u8

  # arithematic
  @extern("u8_add_u8")
  public func add(a: u8, b: u8): Status[u8]

  @extern("u8_subtract_u8")
  public func subtract(a: u8, b: u8): Status[u8]

  @extern("u8_multiply_u8")
  public func multiply(a: u8, b: u8): Status[u8]

  @extern("u8_quotient_u8")
  public func quotient(a: u8, b: u8): Status[u8]

  @extern("u8_remainder_u8")
  public func remainder(a: u8, b: u8): Status[u8]

  # branching
  @extern("u8_compare_u8")
  public func compare(a: u8, b: u8): i8

public module u16:
  literal: "u16"

  # core
  @extern("u16_read")
  public func read(ptr: Pointer, offset: u64): u16

  @extern("u16_byte_size")
  public func byte_size(items: u32): u64

  @extern("u16_valid")
  public func valid(value: u16): u8

  @extern("u16_write")
  public func write(ptr: Pointer, offset: u64, item: u16): Pointer

  # binary
  @extern("u16_and_u16")
  public func and(a: u16, b: u16): u16

  @extern("u16_or_u16")
  public func or(a: u16, b: u16): u16

  @extern("u16_xor_u16")
  public func xor(a: u16, b: u16): u16

  @extern("u16_shr_u16")
  public func shr(a: u16, b: u16): u16

  @extern("u16_shl_u16")
  public func shl(a: u16, b: u16): u16

  @extern("u16_not_u16")
  public func not(a: u16): u16

  # arithematic
  @extern("u16_add_u16")
  public func add(a: u16, b: u16): Status[u16]

  @extern("u16_subtract_u16")
  public func subtract(a: u16, b: u16): Status[u16]

  @extern("u16_multiply_u16")
  public func multiply(a: u16, b: u16): Status[u16]

  @extern("u16_quotient_u16")
  public func quotient(a: u16, b: u16): Status[u16]

  @extern("u16_remainder_u16")
  public func remainder(a: u16, b: u16): Status[u16]

  # branching
  @extern("u16_compare_u16")
  public func compare(a: u16, b: u16): i8

public module u32:
  literal: "u32"

  # core
  @extern("u32_read")
  public func read(ptr: Pointer, offset: u64): u32

  @extern("u32_byte_size")
  public func byte_size(items: u32): u64

  @extern("u32_valid")
  public func valid(value: u32): u8

  @extern("u32_write")
  public func write(ptr: Pointer, offset: u64, item: u32): Pointer

  # binary
  @extern("u32_and_u32")
  public func and(a: u32, b: u32): u32

  @extern("u32_or_u32")
  public func or(a: u32, b: u32): u32

  @extern("u32_xor_u32")
  public func xor(a: u32, b: u32): u32

  @extern("u32_shr_u32")
  public func shr(a: u32, b: u32): u32

  @extern("u32_shl_u32")
  public func shl(a: u32, b: u32): u32

  @extern("u32_not_u32")
  public func not(a: u32): u32

  # arithematic
  @extern("u32_add_u32")
  public func add(a: u32, b: u32): Status[u32]

  @extern("u32_subtract_u32")
  public func subtract(a: u32, b: u32): Status[u32]

  @extern("u32_multiply_u32")
  public func multiply(a: u32, b: u32): Status[u32]

  @extern("u32_quotient_u32")
  public func quotient(a: u32, b: u32): Status[u32]

  @extern("u32_remainder_u32")
  public func remainder(a: u32, b: u32): Status[u32]

  # branching
  @extern("u32_compare_u32")
  public func compare(a: u32, b: u32): i8

public module u64:
  literal: "u64"

  # core
  @extern("u64_read")
  public func read(ptr: Pointer, offset: u64): u64

  @extern("u64_byte_size")
  public func byte_size(items: u32): u64

  @extern("u64_valid")
  public func valid(value: u64): u8

  @extern("u64_write")
  public func write(ptr: Pointer, offset: u64, item: u64): Pointer

  # binary
  @extern("u64_and_u64")
  public func and(a: u64, b: u64): u64

  @extern("u64_or_u64")
  public func or(a: u64, b: u64): u64

  @extern("u64_xor_u64")
  public func xor(a: u64, b: u64): u64

  @extern("u64_shr_u64")
  public func shr(a: u64, b: u64): u64

  @extern("u64_shl_u64")
  public func shl(a: u64, b: u64): u64

  @extern("u64_not_u64")
  public func not(a: u64): u64

  # arithematic
  @extern("u64_add_u64")
  public func add(a: u64, b: u64): Status[u64]

  @extern("u64_subtract_u64")
  public func subtract(a: u64, b: u64): Status[u64]

  @extern("u64_multiply_u64")
  public func multiply(a: u64, b: u64): Status[u64]

  @extern("u64_quotient_u64")
  public func quotient(a: u64, b: u64): Status[u64]

  @extern("u64_remainder_u64")
  public func remainder(a: u64, b: u64): Status[u64]

  # branching
  @extern("u64_compare_u64")
  public func compare(a: u64, b: u64): i8

  # casting
  @extern("u64_from_u8")
  public func from(a: u8): u64

  # user functions
  public func div_ceil(a: u64, b: u64): Status[u64]
    match u64.add(a, b):
      case Ok { value: val1 }:
        match u64.subtract(val1, 1):
          case Ok { value: val2 }:
            u64.quotient(val2, b)
          case Err { error: err2 }:
            Status[u64].Err { error: err2 }
      case Err { error: err1 }:
        Status[u64].Err { error: err1 }

public module i8:
  literal: "i8"

  # core
  @extern("i8_read")
  public func read(ptr: Pointer, offset: u64): i8

  @extern("i8_byte_size")
  public func byte_size(items: u32): u64

  @extern("i8_valid")
  public func valid(value: i8): u8

  @extern("i8_write")
  public func write(ptr: Pointer, offset: u64, item: i8): Pointer

  # binary
  @extern("i8_and_i8")
  public func and(a: i8, b: i8): i8

  @extern("i8_or_i8")
  public func or(a: i8, b: i8): i8

  @extern("i8_xor_i8")
  public func xor(a: i8, b: i8): i8

  @extern("i8_shr_i8")
  public func shr(a: i8, b: i8): i8

  @extern("i8_shl_i8")
  public func shl(a: i8, b: i8): i8

  @extern("i8_not_i8")
  public func not(a: i8): i8

  # arithematic
  @extern("i8_add_i8")
  public func add(a: i8, b: i8): Status[i8]

  @extern("i8_subtract_i8")
  public func subtract(a: i8, b: i8): Status[i8]

  @extern("i8_multiply_i8")
  public func multiply(a: i8, b: i8): Status[i8]

  @extern("i8_quotient_i8")
  public func quotient(a: i8, b: i8): Status[i8]

  @extern("i8_remainder_i8")
  public func remainder(a: i8, b: i8): Status[i8]

  # branching
  @extern("i8_compare_i8")
  public func compare(a: i8, b: i8): i8

public module i16:
  literal: "i16"

  # core
  @extern("i16_read")
  public func read(ptr: Pointer, offset: u64): i16

  @extern("i16_byte_size")
  public func byte_size(items: u32): u64

  @extern("i16_valid")
  public func valid(value: i16): u8

  @extern("i16_write")
  public func write(ptr: Pointer, offset: u64, item: i16): Pointer

  # binary
  @extern("i16_and_i16")
  public func and(a: i16, b: i16): i16

  @extern("i16_or_i16")
  public func or(a: i16, b: i16): i16

  @extern("i16_xor_i16")
  public func xor(a: i16, b: i16): i16

  @extern("i16_shr_i16")
  public func shr(a: i16, b: i16): i16

  @extern("i16_shl_i16")
  public func shl(a: i16, b: i16): i16

  @extern("i16_not_i16")
  public func not(a: i16): i16

  # arithematic
  @extern("i16_add_i16")
  public func add(a: i16, b: i16): Status[i16]

  @extern("i16_subtract_i16")
  public func subtract(a: i16, b: i16): Status[i16]

  @extern("i16_multiply_i16")
  public func multiply(a: i16, b: i16): Status[i16]

  @extern("i16_quotient_i16")
  public func quotient(a: i16, b: i16): Status[i16]

  @extern("i16_remainder_i16")
  public func remainder(a: i16, b: i16): Status[i16]

  # branching
  @extern("i16_compare_i16")
  public func compare(a: i16, b: i16): i8

public module i32:
  literal: "i32"

  # core
  @extern("i32_read")
  public func read(ptr: Pointer, offset: u64): i32

  @extern("i32_byte_size")
  public func byte_size(items: u32): u64

  @extern("i32_valid")
  public func valid(value: i32): u8

  @extern("i32_write")
  public func write(ptr: Pointer, offset: u64, item: i32): Pointer

  # binary
  @extern("i32_and_i32")
  public func and(a: i32, b: i32): i32

  @extern("i32_or_i32")
  public func or(a: i32, b: i32): i32

  @extern("i32_xor_i32")
  public func xor(a: i32, b: i32): i32

  @extern("i32_shr_i32")
  public func shr(a: i32, b: i32): i32

  @extern("i32_shl_i32")
  public func shl(a: i32, b: i32): i32

  @extern("i32_not_i32")
  public func not(a: i32): i32

  # arithematic
  @extern("i32_add_i32")
  public func add(a: i32, b: i32): Status[i32]

  @extern("i32_subtract_i32")
  public func subtract(a: i32, b: i32): Status[i32]

  @extern("i32_multiply_i32")
  public func multiply(a: i32, b: i32): Status[i32]

  @extern("i32_quotient_i32")
  public func quotient(a: i32, b: i32): Status[i32]

  @extern("i32_remainder_i32")
  public func remainder(a: i32, b: i32): Status[i32]

  # branching
  @extern("i32_compare_i32")
  public func compare(a: i32, b: i32): i8

public module i64:
  literal: "i64"

  # core
  @extern("i64_read")
  public func read(ptr: Pointer, offset: u64): i64

  @extern("i64_byte_size")
  public func byte_size(items: u32): u64

  @extern("i64_valid")
  public func valid(value: i64): u8

  @extern("i64_write")
  public func write(ptr: Pointer, offset: u64, item: i64): Pointer

  # binary
  @extern("i64_and_i64")
  public func and(a: i64, b: i64): i64

  @extern("i64_or_i64")
  public func or(a: i64, b: i64): i64

  @extern("i64_xor_i64")
  public func xor(a: i64, b: i64): i64

  @extern("i64_shr_i64")
  public func shr(a: i64, b: i64): i64

  @extern("i64_shl_i64")
  public func shl(a: i64, b: i64): i64

  @extern("i64_not_i64")
  public func not(a: i64): i64

  # arithematic
  @extern("i64_add_i64")
  public func add(a: i64, b: i64): Status[i64]

  @extern("i64_subtract_i64")
  public func subtract(a: i64, b: i64): Status[i64]

  @extern("i64_multiply_i64")
  public func multiply(a: i64, b: i64): Status[i64]

  @extern("i64_quotient_i64")
  public func quotient(a: i64, b: i64): Status[i64]

  @extern("i64_remainder_i64")
  public func remainder(a: i64, b: i64): Status[i64]

  # branching
  @extern("i64_compare_i64")
  public func compare(a: i64, b: i64): i8

public module f32:
  literal: "f32"

  # core
  @extern("f32_read")
  public func read(ptr: Pointer, offset: u64): f32

  @extern("f32_byte_size")
  public func byte_size(items: u32): u64

  @extern("f32_valid")
  public func valid(value: f32): u8

  @extern("f32_write")
  public func write(ptr: Pointer, offset: u64, item: f32): Pointer

  # binary
  @extern("f32_and_f32")
  public func and(a: f32, b: f32): f32

  @extern("f32_or_f32")
  public func or(a: f32, b: f32): f32

  @extern("f32_xor_f32")
  public func xor(a: f32, b: f32): f32

  @extern("f32_not_f32")
  public func not(a: f32): f32

  # arithematic
  @extern("f32_add_f32")
  public func add(a: f32, b: f32): Status[f32]

  @extern("f32_subtract_f32")
  public func subtract(a: f32, b: f32): Status[f32]

  @extern("f32_multiply_f32")
  public func multiply(a: f32, b: f32): Status[f32]

  @extern("f32_quotient_f32")
  public func quotient(a: f32, b: f32): Status[f32]

  @extern("f32_remainder_f32")
  public func remainder(a: f32, b: f32): Status[f32]

public module f64:
  literal: "f64"

  # core
  @extern("f64_read")
  public func read(ptr: Pointer, offset: u64): f64

  @extern("f64_byte_size")
  public func byte_size(items: u32): u64

  @extern("f64_valid")
  public func valid(value: f64): u8

  @extern("f64_write")
  public func write(ptr: Pointer, offset: u64, item: f64): Pointer

  # binary
  @extern("f64_and_f64")
  public func and(a: f64, b: f64): f64

  @extern("f64_or_f64")
  public func or(a: f64, b: f64): f64

  @extern("f64_xor_f64")
  public func xor(a: f64, b: f64): f64

  @extern("f64_not_f64")
  public func not(a: f64): f64

  # arithematic
  @extern("f64_add_f64")
  public func add(a: f64, b: f64): Status[f64]

  @extern("f64_subtract_f64")
  public func subtract(a: f64, b: f64): Status[f64]

  @extern("f64_multiply_f64")
  public func multiply(a: f64, b: f64): Status[f64]

  @extern("f64_quotient_f64")
  public func quotient(a: f64, b: f64): Status[f64]

  @extern("f64_remainder_f64")
  public func remainder(a: f64, b: f64): Status[f64]

module Pointer:
  literal: "pointer"

  # core
  @extern("pointer_read")
  public func read(ptr: Pointer, offset: u64): Pointer

  @extern("pointer_byte_size")
  public func byte_size(items: u32): u64

  @extern("pointer_write")
  public func write(ptr: Pointer, offset: u64, item: Pointer): Pointer

  @extern("pointer_valid")
  public func valid(ptr: Pointer): u8

public module String:
  literal: "string"

  # core
  @extern("string_init")
  public func init(value: String): String

  @extern("string_get")
  public func get(str: String, index: u32): Status[u8]

  @extern("string_from_u32")
  public func from(value: u32): String

  @extern("string_concat")
  public func concat(first: String, second: String): String

public generic Any:
  func byte_size(items: u32): u64
  func read(ptr: Pointer, offset: u64): Any
  func write(ptr: Pointer, offset: u64, item: Any): Pointer
  func valid(item: Any): u8

public module Error:
  struct:
    code: i32
    message: String

public module Status:
  union:
    Ok { value: Any }
    Err { error: Error }

public module System:
  @extern("System_allocate")
  public func allocate(size: u64): Pointer

  @extern("System_print")
  public func print(str: String): u64

  @extern("System_println")
  public func println(str: String): u64

public module Array:
  # if requires is present then it will take precedence
  # meaning user will always have to use `Array[Any]`
  requires(Any)

  struct:
    size: u32
    ptr: Pointer

  @extern("pointer_read")
  public func read(ptr: Pointer, offset: u64): Array[Any]

  @extern("pointer_byte_size")
  public func byte_size(items: u32): u64

  @extern("pointer_write")
  public func write(ptr: Pointer, offset: u64, item: Array[Any]): Pointer

  @extern("pointer_valid")
  public func valid(item: Array[Any]): u8

  public func init(size: u32): Array[Any]
    bytes = Any.byte_size(size)
    ptr = System.allocate(bytes)
    Array[Any] { size: size, ptr: ptr }

  public func get(arr: Array[Any], index: u32): Status[Any]
    match u32.compare(index, arr.size):
      case -1:
        offset = Any.byte_size(index)
        item = Any.read(arr.ptr, offset)
        match Any.valid(item):
          case 0:
            Status[Any].Ok { value: item }
          case _:
            error = Error { code: 2, message: "illegal memory access" }
            Status[Any].Err { error: error }
      case _:
        error = Error { code: 1, message: "index out of bounds" }
        Status[Any].Err { error: error }

  public func set(arr: Array[Any], index: u32, item: Any): Status[Array[Any]]
    match u32.compare(index, arr.size):
      case -1:
        offset = Any.byte_size(index)
        arr.ptr = Any.write(arr.ptr, offset, item)
        Status[Any].Ok { value: arr }
      case _:
        error = Error { code: 1, message: "index out of bounds" }
        Status[Any].Err { error: error }

public module Bitset:
  struct:
    bits: Array[u8]

  @extern("pointer_read")
  public func read(ptr: Pointer, offset: u64): Bitset

  @extern("pointer_byte_size")
  public func byte_size(items: u32): u64

  @extern("pointer_write")
  public func write(ptr: Pointer, offset: u64, item: Bitset): Pointer

  @extern("pointer_valid")
  public func valid(item: Bitset): u8

  public func init(size: u32): Bitset
    size = u32.quotient(u32.add(size, 7), 8)
    bits = Array[u8].init(size)
    Bitset { bits: bits }

  public func get(bitset: Bitset, index: u32): Status[u8]
    index = u32.quotient(index, 8)
    match Array[u8].get(bitset.bits, index):
      case Ok { value: value }:
        sub_index = u32.remainder(index, 8)
        shifted = u8.shr(value, sub_index)
        bit_value = u8.and(shifted, 1)
        Status[u8].Ok { value: bit_value }
      case Err { error: error }:
        Status[u8].Err { error: error }

  public func set(bitset: Bitset, index: u32): Status[Bitset]
    index = u32.quotient(index, 8)
    match Array[u8].get(bitset.bits, index):
      case Ok { value: value }:
        sub_index = u32.remainder(index, 8)
        shifted = u8.shl(1, sub_index)
        bit_value = u8.or(shifted, value)
        match Array[u8].set(bitset.bits, index, bit_value):
          case Ok { value: updated_bits }:
            bitset.bits = updated_bits
            Status[Bitset].Ok { value: bitset }
          case Err { error: error }:
            Status[Bitset].Err { error: error }
      case Err { error: error }:
        Status[Bitset].Err { error: error }
