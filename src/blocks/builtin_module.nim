import sequtils

import function

type BuiltinModule* = ref object of RootObj
  name*: string
  functions*: seq[FunctionDefinition]

proc new_builtin_module(name: string, defs: seq[(string, string, seq[(string,
    string)])]): BuiltinModule =
  let functions = defs.map_it(new_function_definition(it[1], it[2], it[0]))
  BuiltinModule(name: name, functions: functions)

proc `$`*(module: BuiltinModule): string = module.name

proc builtins*(): seq[BuiltinModule] =
  let u8_module = new_builtin_module("U8", @[
    ("U8", "init", @[("U8", "a")]),
    ("U8", "from_Pointer", @[("Pointer", "p")]),
    ("U8", "lshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "rshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "and", @[("U8", "a"), ("U8", "b")]),
    ("U8", "or", @[("U8", "a"), ("U8", "b")]),
    ("U8", "not", @[("U8", "a")]),
  ])

  let u16_module = new_builtin_module("U16", @[
    ("U16", "init", @[("U16", "a")]),
  ])

  let u32_module = new_builtin_module("U32", @[
    ("U32", "init", @[("U32", "a")]),
  ])

  let u64_module = new_builtin_module("U64", @[
    ("U64", "init", @[("U64", "a")]),
    ("S64", "compare", @[("U64", "a"), ("U64", "b")]),
    ("U64", "add", @[("U64", "a"), ("U64", "b")]),
    ("U64", "subtract", @[("U64", "a"), ("U64", "b")]),
    ("U64", "multiply", @[("U64", "a"), ("U64", "b")]),
    ("U64", "quotient", @[("U64", "a"), ("U64", "b")]),
    ("U64", "remainder", @[("U64", "a"), ("U64", "b")]),
  ])

  let s8_module = new_builtin_module("S8", @[
    ("S8", "init", @[("S8", "a")]),
  ])

  let s16_module = new_builtin_module("S16", @[
    ("S16", "init", @[("S16", "a")]),
  ])

  let s32_module = new_builtin_module("S32", @[
    ("S32", "init", @[("S32", "a")]),
  ])

  let s64_module = new_builtin_module("S64", @[
    ("S64", "init", @[("S64", "a")]),
    ("S64", "from_U8", @[("U8", "a")]),
    ("S64", "add", @[("S64", "a"), ("S64", "b")]),
    ("S64", "subtract", @[("S64", "a"), ("S64", "b")]),
    ("S64", "multiply", @[("S64", "a"), ("S64", "b")]),
    ("S64", "quotient", @[("S64", "a"), ("S64", "b")]),
    ("S64", "remainder", @[("S64", "a"), ("S64", "b")]),
    ("S64", "compare", @[("S64", "a"), ("S64", "b")]),
  ])


  let f32_module = new_builtin_module("F32", @[
    ("F32", "init", @[("F32", "a")]),
  ])

  let f64_module = new_builtin_module("F64", @[
    ("F64", "init", @[("F64", "a")]),
  ])

  let pointer_module = new_builtin_module("Pointer", @[
    ("Pointer", "init", @[("Pointer", "a")]),
    ("Pointer", "shift", @[("Pointer", "a"), ("U64", "b")]),
    ("Pointer", "write_U8", @[("Pointer", "a"), ("U8", "b")]),
  ])

  let system_module = new_builtin_module("System", @[
    ("U64", "print_S64", @[("S64", "a")]),
    ("U64", "print_U64", @[("U64", "a")]),
    ("Pointer", "allocate", @[("U64", "size")]),
    ("U64", "free", @[("Pointer", "ptr")]),
  ])

  return @[
    s8_module, s16_module, s32_module, s64_module,
    u8_module, u16_module, u32_module, u64_module,
    f32_module, f64_module,
    pointer_module,
    system_module,
  ]
