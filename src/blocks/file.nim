import sequtils, strutils, results, strformat

import token, function, struct, arg_def, module_def

type BuiltinModule* = ref object of RootObj
  name*: string

proc `$`*(module: BuiltinModule): string = module.name

type File* = ref object of RootObj
  location*: Location
  builtin_modules*: seq[BuiltinModule]
  modules*: seq[Module]
  functions*: seq[Function]
  structs*: seq[Struct]
  builtins*: seq[FunctionDefinition]

proc name*(file: File): string =
  file.location.filename

proc new_file*(filename: string): File =
  let modules = @["U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "S64",
      "F32", "F64", "Pointer"].map_it(BuiltinModule(name: it))
  let builtins = @[
    new_function_definition("U8_init", @[("U8", "a")], "U8"),
    new_function_definition("U8_from_Pointer", @[("Pointer", "p")], "U8"),
    new_function_definition("U8_lshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_rshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_and", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U8_or", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U8_not", @[("U8", "a")], "U8"),
    new_function_definition("U16_init", @[("U16", "a")], "U16"),
    new_function_definition("U32_init", @[("U32", "a")], "U32"),
    # U64
    new_function_definition("U64_init", @[("U64", "a")], "U64"),
    new_function_definition("U64_compare", @[("U64", "a"), ("U64", "b")],
        "S64"),
    new_function_definition("U64_add", @[("U64", "a"), ("U64", "b")], "U64"),
    new_function_definition("U64_subtract", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_multiply", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_quotient", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_remainder", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("System_print_U64", @[("U64", "a")], "U64"),
    new_function_definition("S8_init", @[("S8", "a")], "S8"),
    new_function_definition("S16_init", @[("S16", "a")], "S16"),
    new_function_definition("S32_init", @[("S32", "a")], "S32"),
    # S64
    new_function_definition("S64_init", @[("S64", "a")], "S64"),
    new_function_definition("S64_from_U8", @[("U8", "a")], "S64"),
    new_function_definition("S64_add", @[("S64", "a"), ("S64", "b")], "S64"),
    new_function_definition("S64_subtract", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_multiply", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_quotient", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_remainder", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_compare", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("System_print_S64", @[("S64", "a")], "U64"),
    new_function_definition("System_print_U64", @[("U64", "a")], "U64"),
    new_function_definition("F32_init", @[("F32", "a")], "F32"),
    new_function_definition("F64_init", @[("F64", "a")], "F64"),
    new_function_definition("Pointer_init", @[("Pointer", "a")], "Pointer"),
    new_function_definition("Pointer_shift", @[("Pointer", "a"), ("U64", "b")],
        "Pointer"),
    new_function_definition("Pointer_write_U8", @[("Pointer", "a"), ("U8",
        "b")], "Pointer"),
    new_function_definition("System_allocate", @[("U64", "size")], "Pointer"),
    new_function_definition("System_free", @[("Pointer", "ptr")], "U64"),
  ]
  File(builtin_modules: modules, builtins: builtins,
      location: new_file_location(filename))

proc `$`*(file: File): string =
  @[
    file.structs.map_it($(it)).join("\n\n"),
    file.functions.map_it($(it)).join("\n\n")
  ].join("\n\n")

proc find_builtin_module*(file: File, module_name: Token): Result[BuiltinModule, string] =
  for module in file.builtin_modules:
    if $(module) == $(module_name):
      return ok(module)
  err(fmt"{module_name} does not exist in the scope")

proc find_struct*(file: File, struct_name: Token): Result[Struct, string] =
  for struct in file.structs:
    if $(struct.name) == $(struct_name):
      return ok(struct)
  err(fmt"{struct_name} does not exist in the scope")

proc find_module*(file: File, module_name: Token): Result[void, string] =
  var maybe_found = file.find_builtin_module(module_name)
  if maybe_found.is_ok: return ok()

  discard ? file.find_struct(module_name)
  ok()

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc check_if_duplicate(file: File, fn: Function): Result[void, string] =
  for function in file.functions:
    if function.name != fn.name: continue
    if function.arity != fn.arity: continue

    var matched = true
    for (function_arg, fn_arg) in zip(function.arg_def_list, fn.arg_def_list):
      if $(function_arg.arg_type) != $(fn_arg.arg_type):
        matched = false
    if matched:
      return err(fmt"{fn.location} {fn.name} is already defined in {function.location}")
  ok()

proc check_if_duplicate(file: File, module: Module): Result[void, string] =
  for pre_defined_module in file.modules:
    if $(pre_defined_module.name) == $(module.name):
      return err(fmt"{module.location} {module.name} is already defined in {pre_defined_module.location}")
  ok()

proc check_if_duplicate(file: File, struct: Struct): Result[void, string] =
  for pre_defined_struct in file.structs:
    if $(pre_defined_struct.name) == $(struct.name):
      return err(fmt"{struct.location} {struct.name} is already defined in {pre_defined_struct.location}")
  ok()

proc add_module*(file: File, module: Module): Result[void, string] =
  ? file.check_if_duplicate(module)
  file.modules.add(module)
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  ? file.check_if_duplicate(function)
  file.functions.add(function)
  ok()

proc add_struct*(file: File, struct: Struct): Result[void, string] =
  ? file.check_if_duplicate(struct)
  file.structs.add(struct)
  ok()
