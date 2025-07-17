import strutils, options, results, strformat, sequtils

import token, function, struct

type ModuleDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc new_module_definition*(name: Token, location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

proc new_module_definition*(name: string): ModuleDefinition =
  ModuleDefinition(name: new_id_token(name))

proc `$`*(module_def: ModuleDefinition): string =
  fmt"module {module_def.name}:"

type BuiltinModule* = ref object of RootObj
  module_def*: ModuleDefinition
  functions*: seq[FunctionDefinition]

proc new_builtin_module*(name: string, defs: seq[(string, string, seq[(string,
    string)])]): BuiltinModule =
  let module_def = new_module_definition(name)
  let functions = defs.map_it(new_function_definition(it[1], it[2], it[0]))
  BuiltinModule(module_def: module_def, functions: functions)

proc location*(builtin_module: BuiltinModule): Location =
  builtin_module.module_def.location

proc name*(builtin_module: BuiltinModule): Token =
  builtin_module.module_def.name

proc `$`*(module: BuiltinModule): string = $(module.module_def.name)

proc u8_module(): BuiltinModule =
  new_builtin_module("U8", @[
    ("U8", "init", @[("U8", "a")]),
    ("U8", "from_Pointer", @[("Pointer", "p")]),
    ("U8", "lshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "rshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "and", @[("U8", "a"), ("U8", "b")]),
    ("U8", "or", @[("U8", "a"), ("U8", "b")]),
    ("U8", "not", @[("U8", "a")]),
  ])

proc u16_module(): BuiltinModule =
  new_builtin_module("U16", @[
    ("U16", "init", @[("U16", "a")]),
  ])

proc u32_module(): BuiltinModule =
  new_builtin_module("U32", @[
    ("U32", "init", @[("U32", "a")]),
  ])

proc u64_module(): BuiltinModule =
  new_builtin_module("U64", @[
    ("U64", "init", @[("U64", "a")]),
    ("S64", "compare", @[("U64", "a"), ("U64", "b")]),
    ("U64", "add", @[("U64", "a"), ("U64", "b")]),
    ("U64", "subtract", @[("U64", "a"), ("U64", "b")]),
    ("U64", "multiply", @[("U64", "a"), ("U64", "b")]),
    ("U64", "quotient", @[("U64", "a"), ("U64", "b")]),
    ("U64", "remainder", @[("U64", "a"), ("U64", "b")]),
  ])

proc s8_module(): BuiltinModule =
  new_builtin_module("S8", @[
    ("S8", "init", @[("S8", "a")]),
  ])

proc s16_module(): BuiltinModule =
  new_builtin_module("S16", @[
    ("S16", "init", @[("S16", "a")]),
  ])

proc s32_module(): BuiltinModule =
  new_builtin_module("S32", @[
    ("S32", "init", @[("S32", "a")]),
  ])

proc s64_module(): BuiltinModule =
  new_builtin_module("S64", @[
    ("S64", "init", @[("S64", "a")]),
    ("S64", "from_U8", @[("U8", "a")]),
    ("S64", "add", @[("S64", "a"), ("S64", "b")]),
    ("S64", "subtract", @[("S64", "a"), ("S64", "b")]),
    ("S64", "multiply", @[("S64", "a"), ("S64", "b")]),
    ("S64", "quotient", @[("S64", "a"), ("S64", "b")]),
    ("S64", "remainder", @[("S64", "a"), ("S64", "b")]),
    ("S64", "compare", @[("S64", "a"), ("S64", "b")]),
  ])

proc f32_module(): BuiltinModule =
  new_builtin_module("F32", @[
    ("F32", "init", @[("F32", "a")]),
  ])

proc f64_module(): BuiltinModule =
  new_builtin_module("F64", @[
    ("F64", "init", @[("F64", "a")]),
  ])

proc pointer_module(): BuiltinModule =
  new_builtin_module("Pointer", @[
    ("Pointer", "init", @[("Pointer", "a")]),
    ("Pointer", "shift", @[("Pointer", "a"), ("U64", "b")]),
    ("Pointer", "write_U8", @[("Pointer", "a"), ("U8", "b")]),
  ])

proc system_module(): BuiltinModule =
  new_builtin_module("System", @[
    ("U64", "print_S64", @[("S64", "a")]),
    ("U64", "print_U64", @[("U64", "a")]),
    ("Pointer", "allocate", @[("U64", "size")]),
    ("U64", "free", @[("Pointer", "ptr")]),
  ])

proc builtins*(): seq[BuiltinModule] =
  @[
    u8_module(),
    u16_module(),
    u32_module(),
    u64_module(),
    s8_module(),
    s16_module(),
    s32_module(),
    s64_module(),
    f32_module(),
    f64_module(),
    pointer_module(),
    system_module(),
  ]

type UserModule* = ref object of RootObj
  module_def*: ModuleDefinition
  functions*: seq[Function]
  struct*: Option[Struct]
  union*: Option[Union]

proc new_user_module*(module_def: ModuleDefinition): UserModule =
  UserModule(module_def: module_def)

proc location*(module: UserModule): Location = module.module_def.location
proc name*(module: UserModule): Token = module.module_def.name
proc is_struct*(module: UserModule): bool = module.struct.is_some
proc is_union*(module: UserModule): bool = module.union.is_some

proc find_function*(module: UserModule, func_def: FunctionDefinition): Result[
    Function, string] =
  for function in module.functions:
    if function.definition == func_def:
      return ok(function)
  return err(fmt"Function `{func_def.name}` is not defined in the module `{module.name}`")

proc `$`*(module: UserModule): string =
  let prefix = " ".repeat(module.module_def.location.column - 1)
  let child_prefix = " ".repeat(module.module_def.location.column + 1)
  var lines = @[prefix & $(module.module_def)]
  for function in module.functions:
    lines.add(child_prefix & $(function))
  return lines.join("\n")

proc add_function*(module: UserModule, function: Function): Result[void, string] =
  let maybe_found = module.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in module `{module.name}` at {predefined_location}")

  module.functions.add(function)
  ok()

proc add_struct*(module: UserModule, struct: Struct): Result[void, string] =
  if module.struct.is_some:
    let predefined_location = module.struct.get.location
    return err(fmt"{struct.location} Module `{module.name}` already contains a struct block at {predefined_location}")

  if module.union.is_some:
    let predefined_location = module.union.get.location
    return err(fmt"{struct.location} Module `{module.name}` already contains a union block at {predefined_location}")

  module.struct = some(struct)
  ok()

proc add_union*(module: UserModule, union: Union): Result[void, string] =
  if module.struct.is_some:
    let predefined_location = module.struct.get.location
    return err(fmt"{union.location} Module `{module.name}` already contains a struct block at {predefined_location}")

  if module.union.is_some:
    let predefined_location = module.union.get.location
    return err(fmt"{union.location} Module `{module.name}` already contains a union block at {predefined_location}")

  module.union = some(union)
  ok()

proc close*(module: UserModule): Result[void, string] =
  if module.functions.len == 0 and (not module.is_struct):
    return err(fmt"{module.location} Module `{module.name}` must contain at least one function.")
  ok()
