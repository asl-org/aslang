import strutils, options, results, strformat, sequtils, hashes, tables

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

proc find_function*(module: BuiltinModule,
    func_def: FunctionDefinition): Result[FunctionDefinition, string] =
  for mod_func_def in module.functions:
    if func_def.hash() == mod_func_def.hash():
      return ok(func_def)
  return err(fmt"{func_def.location} Builtin module `{module.name}` has no function definition matching `{func_def}`")

proc u8_module(): BuiltinModule =
  new_builtin_module("U8", @[
    ("U8", "init", @[("U8", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
    ("U8", "from_Pointer", @[("Pointer", "p")]),
    ("Pointer", "write_Pointer", @[("Pointer", "a"), ("U8", "b")]),
    ("U8", "lshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "rshift", @[("U8", "a"), ("U64", "b")]),
    ("U8", "and", @[("U8", "a"), ("U8", "b")]),
    ("U8", "or", @[("U8", "a"), ("U8", "b")]),
    ("U8", "not", @[("U8", "a")]),
  ])

proc u16_module(): BuiltinModule =
  new_builtin_module("U16", @[
    ("U16", "init", @[("U16", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc u32_module(): BuiltinModule =
  new_builtin_module("U32", @[
    ("U32", "init", @[("U32", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc u64_module(): BuiltinModule =
  new_builtin_module("U64", @[
    ("U64", "init", @[("U64", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
    ("S64", "compare", @[("U64", "a"), ("U64", "b")]),
    ("U64", "add", @[("U64", "a"), ("U64", "b")]),
    ("U64", "subtract", @[("U64", "a"), ("U64", "b")]),
    ("U64", "multiply", @[("U64", "a"), ("U64", "b")]),
    ("U64", "quotient", @[("U64", "a"), ("U64", "b")]),
    ("U64", "remainder", @[("U64", "a"), ("U64", "b")]),
    ("U64", "from_Pointer", @[("Pointer", "a")]),
    ("Pointer", "write_Pointer", @[("Pointer", "a"), ("U64", "b")]),
  ])

proc s8_module(): BuiltinModule =
  new_builtin_module("S8", @[
    ("S8", "init", @[("S8", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc s16_module(): BuiltinModule =
  new_builtin_module("S16", @[
    ("S16", "init", @[("S16", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc s32_module(): BuiltinModule =
  new_builtin_module("S32", @[
    ("S32", "init", @[("S32", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc s64_module(): BuiltinModule =
  new_builtin_module("S64", @[
    ("S64", "init", @[("S64", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
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
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc f64_module(): BuiltinModule =
  new_builtin_module("F64", @[
    ("F64", "init", @[("F64", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
  ])

proc pointer_module(): BuiltinModule =
  new_builtin_module("Pointer", @[
    ("Pointer", "init", @[("Pointer", "a")]),
    ("U64", "byte_size", @[("U64", "a")]),
    ("Pointer", "shift", @[("Pointer", "a"), ("U64", "b")]),
  ])

proc system_module(): BuiltinModule =
  new_builtin_module("System", @[
    ("U64", "print_S32", @[("S32", "a")]),
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

type
  UserModuleKind* = enum
    UMK_DEFAULT, UMK_STRUCT, UMK_UNION
  UserModule* = ref object of RootObj
    module_def*: ModuleDefinition
    function_map*: Table[Hash, int]
    functions*: seq[Function]
    generic_map*: Table[string, int]
    generics*: seq[Generic]
    case kind*: UserModuleKind
    of UMK_DEFAULT: discard
    of UMK_STRUCT: struct*: Struct
    of UMK_UNION: union*: Union

proc new_user_module*(module_def: ModuleDefinition): UserModule =
  UserModule(kind: UMK_DEFAULT, module_def: module_def)

proc new_user_module(module: UserModule, struct: Struct): UserModule =
  UserModule(kind: UMK_STRUCT, module_def: module.module_def,
      functions: module.functions, struct: struct, generics: module.generics,
      generic_map: module.generic_map)

proc new_user_module(module: UserModule, union: Union): UserModule =
  UserModule(kind: UMK_UNION, module_def: module.module_def,
      functions: module.functions, union: union, generics: module.generics,
      generic_map: module.generic_map)

proc location*(module: UserModule): Location = module.module_def.location
proc name*(module: UserModule): Token = module.module_def.name

proc find_function*(module: UserModule, func_def: FunctionDefinition): Result[
    Function, string] =
  if func_def.hash notin module.function_map:
    err(fmt"Function `{func_def.name}` is not defined in the module `{module.name}`")
  else:
    ok(module.functions[module.function_map[func_def.hash]])

proc find_generic*(module: UserModule, generic_name: Token): Result[Generic, string] =
  if $(generic_name) notin module.generic_map:
    err(fmt"Generic `{generic_name}` not defined in the module `{module.name}`")
  else:
    let gen_index = module.generic_map[$(generic_name)]
    ok(module.generics[gen_index])

proc `$`*(module: UserModule): string =
  let prefix = " ".repeat(module.module_def.location.column - 1)
  let child_prefix = " ".repeat(module.module_def.location.column + 1)
  var lines = @[prefix & $(module.module_def)]

  case module.kind:
  of UMK_DEFAULT: discard
  of UMK_STRUCT: lines.add(child_prefix & $(module.struct))
  of UMK_UNION: lines.add(child_prefix & $(module.union))

  for function in module.functions:
    lines.add(child_prefix & $(function))
  return lines.join("\n")

proc add_function*(module: UserModule, function: Function): Result[void, string] =
  let maybe_found = module.find_function(function.definition)
  if maybe_found.is_ok:
    let predefined_location = maybe_found.get.location
    return err(fmt"{function.location} Function `{function.name}` is already defined in module `{module.name}` at {predefined_location}")

  module.function_map[function.definition.hash] = module.functions.len
  module.functions.add(function)
  ok()

proc add_struct*(module: UserModule, struct: Struct): Result[UserModule, string] =
  case module.kind:
  of UMK_DEFAULT:
    ok(new_user_module(module, struct))
  of UMK_STRUCT:
    let predefined_location = module.struct.location
    err(fmt"{struct.location} Module `{module.name}` already contains a struct block at {predefined_location}")
  of UMK_UNION:
    let predefined_location = module.union.location
    err(fmt"{struct.location} Module `{module.name}` already contains a union block at {predefined_location}")

proc add_union*(module: UserModule, union: Union): Result[UserModule, string] =
  case module.kind:
  of UMK_DEFAULT:
    ok(new_user_module(module, union))
  of UMK_STRUCT:
    let predefined_location = module.struct.location
    err(fmt"{union.location} Module `{module.name}` already contains a struct block at {predefined_location}")
  of UMK_UNION:
    let predefined_location = module.union.location
    err(fmt"{union.location} Module `{module.name}` already contains a union block at {predefined_location}")

proc add_generic*(module: UserModule, generic: Generic): Result[void, string] =
  let maybe_generic = module.find_generic(generic.name)
  if maybe_generic.is_ok:
    let predefined_location = maybe_generic.get.location
    return err(fmt"Generic `{generic.name}` is already defined at {predefined_location}")
  module.generic_map[$(generic.name)] = module.generics.len
  module.generics.add(generic)
  ok()

proc close*(module: UserModule): Result[void, string] =
  case module.kind:
  of UMK_DEFAULT:
    if module.functions.len == 0:
      return err(fmt"{module.location} Module `{module.name}` must contain at least one function.")
  of UMK_STRUCT: discard
  of UMK_UNION: discard
  ok()

type
  ModuleKind* = enum
    MK_BUILTIN, MK_USER
  Module* = ref object of RootObj
    case kind*: ModuleKind
    of MK_BUILTIN: builtin_module*: BuiltinModule
    of MK_USER: user_module*: UserModule

proc new_module*(builtin_module: BuiltinModule): Module =
  Module(kind: MK_BUILTIN, builtin_module: builtin_module)

proc new_module*(user_module: UserModule): Module =
  Module(kind: MK_USER, user_module: user_module)

proc `$`*(module: Module): string =
  case module.kind:
  of MK_BUILTIN: ""
  of MK_USER: $(module.user_module)

proc location*(module: Module): Location =
  case module.kind:
  of MK_BUILTIN: module.builtin_module.location
  of MK_USER: module.user_module.location

proc name*(module: Module): Token =
  case module.kind:
  of MK_BUILTIN: module.builtin_module.name
  of MK_USER: module.user_module.name

proc find_function*(module: Module, func_def: FunctionDefinition): Result[
    FunctionDefinition, string] =
  case module.kind:
  of MK_USER:
    let function = ? module.user_module.find_function(func_def)
    ok(function.definition)
  of MK_BUILTIN:
    module.builtin_module.find_function(func_def)
