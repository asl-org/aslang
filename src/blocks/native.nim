
let u8_module = ("U8", @[
  # binary
  ("U8_and", "U8", "and", @[("U8", "a"), ("U8", "b")]),
  ("U8_or", "U8", "or", @[("U8", "a"), ("U8", "b")]),
  ("U8_xor", "U8", "xor", @[("U8", "a"), ("U8", "b")]),
  ("U8_not", "U8", "not", @[("U8", "a")]),
  ("U8_lshift", "U8", "lshift", @[("U8", "a"), ("U64", "b")]),
  ("U8_rshift", "U8", "rshift", @[("U8", "a"), ("U64", "b")]),
  # arithematic
  ("U8_add", "U8", "add", @[("U8", "a"), ("U8", "b")]),
  ("U8_subtract", "U8", "subtract", @[("U8", "a"), ("U8", "b")]),
  ("U8_multiply", "U8", "multiply", @[("U8", "a"), ("U8", "b")]),
  ("U8_quotient", "U8", "quotient", @[("U8", "a"), ("U8", "b")]),
  ("U8_remainder", "U8", "remainder", @[("U8", "a"), ("U8", "b")]),
  # branch
  ("U8_compare", "S64", "compare", @[("U8", "a"), ("U8", "b")]),
  # cast
  ("U8_from_S8", "U8", "from", @[("S8", "value")]),
  ("U8_from_S16", "U8", "from", @[("S16", "value")]),
  ("U8_from_S32", "U8", "from", @[("S32", "value")]),
  ("U8_from_S64", "U8", "from", @[("S64", "value")]),
  ("U8_from_U16", "U8", "from", @[("U16", "value")]),
  ("U8_from_U32", "U8", "from", @[("U32", "value")]),
  ("U8_from_U64", "U8", "from", @[("U64", "value")]),
  ("U8_from_Pointer", "U8", "from", @[("Pointer", "ptr")]),
])

# U16 module
let u16_module = ("U16", @[
  # binary
  ("U16_and", "U16", "and", @[("U16", "a"), ("U16", "b")]),
  ("U16_or", "U16", "or", @[("U16", "a"), ("U16", "b")]),
  ("U16_xor", "U16", "xor", @[("U16", "a"), ("U16", "b")]),
  ("U16_not", "U16", "not", @[("U16", "a")]),
  ("U16_lshift", "U16", "lshift", @[("U16", "a"), ("U64", "b")]),
  ("U16_rshift", "U16", "rshift", @[("U16", "a"), ("U64", "b")]),
  # arithematic
  ("U16_add", "U16", "add", @[("U16", "a"), ("U16", "b")]),
  ("U16_subtract", "U16", "subtract", @[("U16", "a"), ("U16", "b")]),
  ("U16_multiply", "U16", "multiply", @[("U16", "a"), ("U16", "b")]),
  ("U16_quotient", "U16", "quotient", @[("U16", "a"), ("U16", "b")]),
  ("U16_remainder", "U16", "remainder", @[("U16", "a"), ("U16", "b")]),
  # branch
  ("U16_compare", "S64", "compare", @[("U16", "a"), ("U16", "b")]),
  # cast
  ("U16_from_S8", "U16", "from", @[("S8", "value")]),
  ("U16_from_S16", "U16", "from", @[("S16", "value")]),
  ("U16_from_S32", "U16", "from", @[("S32", "value")]),
  ("U16_from_S64", "U16", "from", @[("S64", "value")]),
  ("U16_from_U8", "U16", "from", @[("U8", "value")]),
  ("U16_from_U32", "U16", "from", @[("U32", "value")]),
  ("U16_from_U64", "U16", "from", @[("U64", "value")]),
  ("U16_from_Pointer", "U16", "from", @[("Pointer", "ptr")]),
])

# U32 module
let u32_module = ("U32", @[
  # binary
  ("U32_and", "U32", "and", @[("U32", "a"), ("U32", "b")]),
  ("U32_or", "U32", "or", @[("U32", "a"), ("U32", "b")]),
  ("U32_xor", "U32", "xor", @[("U32", "a"), ("U32", "b")]),
  ("U32_not", "U32", "not", @[("U32", "a")]),
  ("U32_lshift", "U32", "lshift", @[("U32", "a"), ("U64", "b")]),
  ("U32_rshift", "U32", "rshift", @[("U32", "a"), ("U64", "b")]),
  # arithematic
  ("U32_add", "U32", "add", @[("U32", "a"), ("U32", "b")]),
  ("U32_subtract", "U32", "subtract", @[("U32", "a"), ("U32", "b")]),
  ("U32_multiply", "U32", "multiply", @[("U32", "a"), ("U32", "b")]),
  ("U32_quotient", "U32", "quotient", @[("U32", "a"), ("U32", "b")]),
  ("U32_remainder", "U32", "remainder", @[("U32", "a"), ("U32", "b")]),
  # branch
  ("U32_compare", "S64", "compare", @[("U32", "a"), ("U32", "b")]),
  # cast
  ("U32_from_S8", "U32", "from", @[("S8", "value")]),
  ("U32_from_S16", "U32", "from", @[("S16", "value")]),
  ("U32_from_S32", "U32", "from", @[("S32", "value")]),
  ("U32_from_S64", "U32", "from", @[("S64", "value")]),
  ("U32_from_U8", "U32", "from", @[("U8", "value")]),
  ("U32_from_U16", "U32", "from", @[("U16", "value")]),
  ("U32_from_U64", "U32", "from", @[("U64", "value")]),
  ("U32_from_Pointer", "U32", "from", @[("Pointer", "ptr")]),
])


# U64 module
let u64_module = ("U64", @[
  # binary
  ("U64_and", "U64", "and", @[("U64", "a"), ("U64", "b")]),
  ("U64_or", "U64", "or", @[("U64", "a"), ("U64", "b")]),
  ("U64_xor", "U64", "xor", @[("U64", "a"), ("U64", "b")]),
  ("U64_not", "U64", "not", @[("U64", "a")]),
  ("U64_lshift", "U64", "lshift", @[("U64", "a"), ("U64", "b")]),
  ("U64_rshift", "U64", "rshift", @[("U64", "a"), ("U64", "b")]),
  # arithematic
  ("U64_add", "U64", "add", @[("U64", "a"), ("U64", "b")]),
  ("U64_subtract", "U64", "subtract", @[("U64", "a"), ("U64", "b")]),
  ("U64_multiply", "U64", "multiply", @[("U64", "a"), ("U64", "b")]),
  ("U64_quotient", "U64", "quotient", @[("U64", "a"), ("U64", "b")]),
  ("U64_remainder", "U64", "remainder", @[("U64", "a"), ("U64", "b")]),
  # branch
  ("U64_compare", "S64", "compare", @[("U64", "a"), ("U64", "b")]),
  # cast
  ("U64_from_S8", "U64", "from", @[("S8", "value")]),
  ("U64_from_S16", "U64", "from", @[("S16", "value")]),
  ("U64_from_S32", "U64", "from", @[("S32", "value")]),
  ("U64_from_S64", "U64", "from", @[("S64", "value")]),
  ("U64_from_U8", "U64", "from", @[("U8", "value")]),
  ("U64_from_U16", "U64", "from", @[("U16", "value")]),
  ("U64_from_U32", "U64", "from", @[("U32", "value")]),
  ("U64_from_Pointer", "U64", "from", @[("Pointer", "ptr")]),
])


# S8 module
let s8_module = ("S8", @[
  # binary
  ("S8_and", "S8", "and", @[("S8", "a"), ("S8", "b")]),
  ("S8_or", "S8", "or", @[("S8", "a"), ("S8", "b")]),
  ("S8_xor", "S8", "xor", @[("S8", "a"), ("S8", "b")]),
  ("S8_not", "S8", "not", @[("S8", "a")]),
  ("S8_lshift", "S8", "lshift", @[("S8", "a"), ("U64", "b")]),
  ("S8_rshift", "S8", "rshift", @[("S8", "a"), ("U64", "b")]),
  # arithematic
  ("S8_add", "S8", "add", @[("S8", "a"), ("S8", "b")]),
  ("S8_subtract", "S8", "subtract", @[("S8", "a"), ("S8", "b")]),
  ("S8_multiply", "S8", "multiply", @[("S8", "a"), ("S8", "b")]),
  ("S8_quotient", "S8", "quotient", @[("S8", "a"), ("S8", "b")]),
  ("S8_remainder", "S8", "remainder", @[("S8", "a"), ("S8", "b")]),
  # branch
  ("S8_compare", "S64", "compare", @[("S8", "a"), ("S8", "b")]),
  # cast
  ("S8_from_S16", "S8", "from", @[("S16", "value")]),
  ("S8_from_S32", "S8", "from", @[("S32", "value")]),
  ("S8_from_S64", "S8", "from", @[("S64", "value")]),
  ("S8_from_U8", "S8", "from", @[("U8", "value")]),
  ("S8_from_U16", "S8", "from", @[("U16", "value")]),
  ("S8_from_U32", "S8", "from", @[("U32", "value")]),
  ("S8_from_U64", "S8", "from", @[("U64", "value")]),
  ("S8_from_Pointer", "S8", "from", @[("Pointer", "ptr")]),
])

# S16 module
let s16_module = ("S16", @[
  # binary
  ("S16_and", "S16", "and", @[("S16", "a"), ("S16", "b")]),
  ("S16_or", "S16", "or", @[("S16", "a"), ("S16", "b")]),
  ("S16_xor", "S16", "xor", @[("S16", "a"), ("S16", "b")]),
  ("S16_not", "S16", "not", @[("S16", "a")]),
  ("S16_lshift", "S16", "lshift", @[("S16", "a"), ("U64", "b")]),
  ("S16_rshift", "S16", "rshift", @[("S16", "a"), ("U64", "b")]),
  # arithematic
  ("S16_add", "S16", "add", @[("S16", "a"), ("S16", "b")]),
  ("S16_subtract", "S16", "subtract", @[("S16", "a"), ("S16", "b")]),
  ("S16_multiply", "S16", "multiply", @[("S16", "a"), ("S16", "b")]),
  ("S16_quotient", "S16", "quotient", @[("S16", "a"), ("S16", "b")]),
  ("S16_remainder", "S16", "remainder", @[("S16", "a"), ("S16", "b")]),
  # branch
  ("S16_compare", "S64", "compare", @[("S16", "a"), ("S16", "b")]),
  # cast
  ("S16_from_S8", "S16", "from", @[("S8", "value")]),
  ("S16_from_S32", "S16", "from", @[("S32", "value")]),
  ("S16_from_S64", "S16", "from", @[("S64", "value")]),
  ("S16_from_U8", "S16", "from", @[("U8", "value")]),
  ("S16_from_U16", "S16", "from", @[("U16", "value")]),
  ("S16_from_U32", "S16", "from", @[("U32", "value")]),
  ("S16_from_U64", "S16", "from", @[("U64", "value")]),
  ("S16_from_Pointer", "S16", "from", @[("Pointer", "ptr")]),
])

# S32 module
let s32_module = ("S32", @[
  # binary
  ("S32_and", "S32", "and", @[("S32", "a"), ("S32", "b")]),
  ("S32_or", "S32", "or", @[("S32", "a"), ("S32", "b")]),
  ("S32_xor", "S32", "xor", @[("S32", "a"), ("S32", "b")]),
  ("S32_not", "S32", "not", @[("S32", "a")]),
  ("S32_lshift", "S32", "lshift", @[("S32", "a"), ("U64", "b")]),
  ("S32_rshift", "S32", "rshift", @[("S32", "a"), ("U64", "b")]),
  # arithematic
  ("S32_add", "S32", "add", @[("S32", "a"), ("S32", "b")]),
  ("S32_subtract", "S32", "subtract", @[("S32", "a"), ("S32", "b")]),
  ("S32_multiply", "S32", "multiply", @[("S32", "a"), ("S32", "b")]),
  ("S32_quotient", "S32", "quotient", @[("S32", "a"), ("S32", "b")]),
  ("S32_remainder", "S32", "remainder", @[("S32", "a"), ("S32", "b")]),
  # branch
  ("S32_compare", "S64", "compare", @[("S32", "a"), ("S32", "b")]),
  # cast
  ("S32_from_S8", "S32", "from", @[("S8", "value")]),
  ("S32_from_S16", "S32", "from", @[("S16", "value")]),
  ("S32_from_S64", "S32", "from", @[("S64", "value")]),
  ("S32_from_U8", "S32", "from", @[("U8", "value")]),
  ("S32_from_U16", "S32", "from", @[("U16", "value")]),
  ("S32_from_U32", "S32", "from", @[("U32", "value")]),
  ("S32_from_U64", "S32", "from", @[("U64", "value")]),
  ("S32_from_Pointer", "S32", "from", @[("Pointer", "ptr")]),
])


# S64 module
let s64_module = ("S64", @[
  # binary
  ("S64_and", "S64", "and", @[("S64", "a"), ("S64", "b")]),
  ("S64_or", "S64", "or", @[("S64", "a"), ("S64", "b")]),
  ("S64_xor", "S64", "xor", @[("S64", "a"), ("S64", "b")]),
  ("S64_not", "S64", "not", @[("S64", "a")]),
  ("S64_lshift", "S64", "lshift", @[("S64", "a"), ("S64", "b")]),
  ("S64_rshift", "S64", "rshift", @[("S64", "a"), ("S64", "b")]),
  # arithematic
  ("S64_add", "S64", "add", @[("S64", "a"), ("S64", "b")]),
  ("S64_subtract", "S64", "subtract", @[("S64", "a"), ("S64", "b")]),
  ("S64_multiply", "S64", "multiply", @[("S64", "a"), ("S64", "b")]),
  ("S64_quotient", "S64", "quotient", @[("S64", "a"), ("S64", "b")]),
  ("S64_remainder", "S64", "remainder", @[("S64", "a"), ("S64", "b")]),
  # branch
  ("S64_compare", "S64", "compare", @[("S64", "a"), ("S64", "b")]),
  # cast
  ("S64_from_S8", "S64", "from", @[("S8", "value")]),
  ("S64_from_S16", "S64", "from", @[("S16", "value")]),
  ("S64_from_S32", "S64", "from", @[("S32", "value")]),
  ("S64_from_U8", "S64", "from", @[("U8", "value")]),
  ("S64_from_U16", "S64", "from", @[("U16", "value")]),
  ("S64_from_U32", "S64", "from", @[("U32", "value")]),
  ("S64_from_U64", "S64", "from", @[("U64", "value")]),
  ("S64_from_Pointer", "S64", "from", @[("Pointer", "ptr")]),
])

# F32 module
let f32_module = ("F32", @[
  # arithematic
  ("F32_add", "F32", "add", @[("F32", "a"), ("F32", "b")]),
  ("F32_subtract", "F32", "subtract", @[("F32", "a"), ("F32", "b")]),
  ("F32_multiply", "F32", "multiply", @[("F32", "a"), ("F32", "b")]),
  ("F32_divide", "F32", "divide", @[("F32", "a"), ("F32", "b")]),
  # branch
  ("F32_compare", "S64", "compare", @[("F32", "a"), ("F32", "b")]),
  # cast
  ("F32_from_S8", "F32", "from", @[("S8", "value")]),
  ("F32_from_S16", "F32", "from", @[("S16", "value")]),
  ("F32_from_S32", "F32", "from", @[("S32", "value")]),
  ("F32_from_U64", "F32", "from", @[("S64", "value")]),
  ("F32_from_U8", "F32", "from", @[("U8", "value")]),
  ("F32_from_U16", "F32", "from", @[("U16", "value")]),
  ("F32_from_U32", "F32", "from", @[("U32", "value")]),
  ("F32_from_U64", "F32", "from", @[("U64", "value")]),
  ("F32_from_F64", "F32", "from", @[("F64", "value")]),
  ("F32_from_Pointer", "F32", "from", @[("Pointer", "ptr")]),
])

# F64 module
let f64_module = ("F64", @[
  # arithematic
  ("F64_add", "F64", "add", @[("F64", "a"), ("F64", "b")]),
  ("F64_subtract", "F64", "subtract", @[("F64", "a"), ("F64", "b")]),
  ("F64_multiply", "F64", "multiply", @[("F64", "a"), ("F64", "b")]),
  ("F64_divide", "F64", "divide", @[("F64", "a"), ("F64", "b")]),
  # branch
  ("F64_compare", "S64", "compare", @[("F64", "a"), ("F64", "b")]),
  # cast
  ("F64_from_S8", "F64", "from", @[("S8", "value")]),
  ("F64_from_S16", "F64", "from", @[("S16", "value")]),
  ("F64_from_S32", "F64", "from", @[("S32", "value")]),
  ("F64_from_S64", "F64", "from", @[("S64", "value")]),
  ("F64_from_U8", "F64", "from", @[("U8", "value")]),
  ("F64_from_U16", "F64", "from", @[("U16", "value")]),
  ("F64_from_U32", "F64", "from", @[("U32", "value")]),
  ("F64_from_U64", "F64", "from", @[("U64", "value")]),
  ("F64_from_F32", "F64", "from", @[("F32", "value")]),
  ("F64_from_Pointer", "F64", "from", @[("Pointer", "ptr")]),
])


let ptr_module = ("Pointer", @[
  ("Pointer_shift", "Pointer", "shift", @[("Pointer", "ptr"), ("U64",
      "offset")]),
  ("Pointer_read_Pointer", "Pointer", "read_Pointer", @[("Pointer", "ptr")]),
  ("Pointer_write_U8", "Pointer", "write", @[("Pointer", "ptr"), ("U8",
      "value")]),
  ("Pointer_write_U16", "Pointer", "write", @[("Pointer", "ptr"), ("U16",
      "value")]),
  ("Pointer_write_U32", "Pointer", "write", @[("Pointer", "ptr"), ("U32",
      "value")]),
  ("Pointer_write_U64", "Pointer", "write", @[("Pointer", "ptr"), ("U64",
      "value")]),
  ("Pointer_write_S8", "Pointer", "write", @[("Pointer", "ptr"), ("S8",
      "value")]),
  ("Pointer_write_S16", "Pointer", "write", @[("Pointer", "ptr"), ("S16",
      "value")]),
  ("Pointer_write_S32", "Pointer", "write", @[("Pointer", "ptr"), ("S32",
      "value")]),
  ("Pointer_write_S64", "Pointer", "write", @[("Pointer", "ptr"), ("S64",
      "value")]),
  ("Pointer_write_F32", "Pointer", "write", @[("Pointer", "ptr"), ("F32",
      "value")]),
  ("Pointer_write_F64", "Pointer", "write", @[("Pointer", "ptr"), ("F64",
      "value")]),
  ("Pointer_write_Pointer", "Pointer", "write", @[("Pointer", "ptr"), (
      "Pointer", "value")]),
])

# sys module
let sys_module = ("System", @[
  ("System_allocate", "Pointer", "allocate", @[("U64", "bytes")]),
  ("System_free", "U8", "free", @[("Pointer", "ptr")]),
  ("System_print_U8", "U64", "print", @[("U8", "value")]),
  ("System_print_U16", "U64", "print", @[("U16", "value")]),
  ("System_print_U32", "U64", "print", @[("U32", "value")]),
  ("System_print_U64", "U64", "print", @[("U64", "value")]),
  ("System_print_S8", "U64", "print", @[("S8", "value")]),
  ("System_print_S16", "U64", "print", @[("S16", "value")]),
  ("System_print_S32", "U64", "print", @[("S32", "value")]),
  ("System_print_S64", "U64", "print", @[("S64", "value")]),
  ("System_print_F32", "U64", "print", @[("F32", "value")]),
  ("System_print_F64", "U64", "print", @[("F64", "value")]),
  ("System_print_Pointer", "U64", "print", @[("Pointer", "ptr")]),
])


let native_module_spec* = @[
  u8_module,
  u16_module,
  u32_module,
  u64_module,
  s8_module,
  s16_module,
  s32_module,
  s64_module,
  f32_module,
  f64_module,
  ptr_module,
  sys_module,
]
