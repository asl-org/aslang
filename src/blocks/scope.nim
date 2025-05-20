import results, strformat, strutils, tables, sequtils, parseutils, typetraits

import module
import function
import matcher

import "../rules/parse_result"

proc safe_parse[T](input: string): Result[T, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parseBiggestInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parseBiggestUInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parseBiggestFloat(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok(casted)
  else:
    err("safeParse only supports signed/unsigned integers and floating-point types")



proc make_native_module(name: string, fns: seq[(string, string, string, seq[(
    string, string)])]): Result[Module, string] =
  let native_module = name.new_identifier().new_module_def().new_native_module()

  for (native_fn_name, returns, fn_name, args) in fns:
    var arg_defs: seq[ArgumentDefinition]
    for (module, name) in args:
      let arg_def = new_arg_def(new_identifier(module), new_identifier(name))
      arg_defs.add(arg_def)

    let fn_def = new_fn_def(new_identifier(fn_name), new_identifier(
        returns), arg_defs)

    ? native_module.add_fn(new_native_function(fn_def, native_fn_name))

  return ok(native_module)

type Scope* = ref object of RootObj
  modules: seq[Module]
  native_modules: seq[Module]

proc spaces*(scope: Scope): int = scope.spaces

proc `$`*(scope: Scope): string =
  $(scope.modules[0])

proc find_user_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for module in scope.modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  return err(fmt"{module_name} is not defined in scope.")

proc find_native_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for module in scope.native_modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  return err(fmt"{module_name} is not defined in scope.")

proc find_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  let maybe_native_module = scope.find_native_module(module_name)
  if maybe_native_module.is_ok: return maybe_native_module

  let maybe_user_module = scope.find_user_module(module_name)
  if maybe_user_module.is_ok: return maybe_user_module

  return err(fmt"{module_name.location} {module_name} is not defined in scope")

proc add_native_module*(scope: Scope, new_module: Module): Result[void, string] =
  let maybe_native_module = scope.find_native_module(new_module.def.name)
  if maybe_native_module.is_ok:
    return err(fmt"{new_module.def.location} {new_module.def.name} is already defined in the scope")

  scope.native_modules.add(new_module)
  ok()

proc add_user_module*(scope: Scope, new_module: Module): Result[void, string] =
  let maybe_user_module = scope.find_user_module(new_module.def.name)
  if maybe_user_module.is_ok:
    return err(fmt"{new_module.def.location} Module {new_module.def.name} is already defined in the scope")

  scope.modules.add(new_module)
  ok()

proc new_scope*(): Result[Scope, string] =
  var scope = Scope()
  # U8 module
  let u8_module = ? make_native_module("U8", @[
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
    ("S64_compare", "S64", "compare", @[("U8", "a"), ("U8", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("U8", "value")]),
    # cast
    ("U8_from_S8", "U8", "from_S8", @[("S8", "value")]),
    ("U8_from_S16", "U8", "from_S16", @[("S16", "value")]),
    ("U8_from_S32", "U8", "from_S32", @[("S32", "value")]),
    ("U8_from_S64", "U8", "from_S64", @[("S64", "value")]),
    ("U8_from_U16", "U8", "from_U16", @[("U16", "value")]),
    ("U8_from_U32", "U8", "from_U32", @[("U32", "value")]),
    ("U8_from_U64", "U8", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(u8_module)

  # U16 module
  let u16_module = ? make_native_module("U16", @[
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
    ("S64_compare", "S64", "compare", @[("U16", "a"), ("U16", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("U16", "value")]),
    # cast
    ("U16_from_S8", "U16", "from_S8", @[("S8", "value")]),
    ("U16_from_S16", "U16", "from_S16", @[("S16", "value")]),
    ("U16_from_S32", "U16", "from_S32", @[("S32", "value")]),
    ("U16_from_S64", "U16", "from_S64", @[("S64", "value")]),
    ("U16_from_U8", "U16", "from_U8", @[("U8", "value")]),
    ("U16_from_U32", "U16", "from_U32", @[("U32", "value")]),
    ("U16_from_U64", "U16", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(u16_module)

  # U32 module
  let u32_module = ? make_native_module("U32", @[
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
    ("S64_compare", "S64", "compare", @[("U32", "a"), ("U32", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("U32", "value")]),
    # cast
    ("U32_from_S8", "U32", "from_S8", @[("S8", "value")]),
    ("U32_from_S16", "U32", "from_S16", @[("S16", "value")]),
    ("U32_from_S32", "U32", "from_S32", @[("S32", "value")]),
    ("U32_from_S64", "U32", "from_S64", @[("S64", "value")]),
    ("U32_from_U8", "U32", "from_U8", @[("U8", "value")]),
    ("U32_from_U16", "U32", "from_U16", @[("U16", "value")]),
    ("U32_from_U64", "U32", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(u32_module)

  # U64 module
  let u64_module = ? make_native_module("U64", @[
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
    ("S64_compare", "S64", "compare", @[("U64", "a"), ("U64", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("U64", "value")]),
    # cast
    ("U64_from_S8", "U64", "from_S8", @[("S8", "value")]),
    ("U64_from_S16", "U64", "from_S16", @[("S16", "value")]),
    ("U64_from_S32", "U64", "from_S32", @[("S32", "value")]),
    ("U64_from_S64", "U64", "from_S64", @[("S64", "value")]),
    ("U64_from_U8", "U64", "from_U8", @[("U8", "value")]),
    ("U64_from_U16", "U64", "from_U16", @[("U16", "value")]),
    ("U64_from_U32", "U64", "from_U32", @[("U32", "value")]),
  ])

  ? scope.add_native_module(u64_module)

  # S8 module
  let s8_module = ? make_native_module("S8", @[
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
    ("S64_compare", "S64", "compare", @[("S8", "a"), ("S8", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("S8", "value")]),
    # cast
    ("S8_from_S16", "S8", "from_S16", @[("S16", "value")]),
    ("S8_from_S32", "S8", "from_S32", @[("S32", "value")]),
    ("S8_from_S64", "S8", "from_S64", @[("S64", "value")]),
    ("S8_from_U8", "S8", "from_U8", @[("U8", "value")]),
    ("S8_from_U16", "S8", "from_U16", @[("U16", "value")]),
    ("S8_from_U32", "S8", "from_U32", @[("U32", "value")]),
    ("S8_from_U64", "S8", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(s8_module)

  # S16 module
  let s16_module = ? make_native_module("S16", @[
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
    ("S64_compare", "S64", "compare", @[("S16", "a"), ("S16", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("S16", "value")]),
    # cast
    ("S16_from_S8", "S16", "from_S8", @[("S8", "value")]),
    ("S16_from_S32", "S16", "from_S32", @[("S32", "value")]),
    ("S16_from_S64", "S16", "from_S64", @[("S64", "value")]),
    ("S16_from_U8", "S16", "from_U8", @[("U8", "value")]),
    ("S16_from_U16", "S16", "from_U16", @[("U16", "value")]),
    ("S16_from_U32", "S16", "from_U32", @[("U32", "value")]),
    ("S16_from_U64", "S16", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(s16_module)

  # S32 module
  let S32_module = ? make_native_module("S32", @[
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
    ("S64_compare", "S64", "compare", @[("S32", "a"), ("S32", "b")]),
    # debug
    ("U64_print", "U64", "print", @[("S32", "value")]),
    # cast
    ("S32_from_S8", "S32", "from_S8", @[("S8", "value")]),
    ("S32_from_S16", "S32", "from_S16", @[("S16", "value")]),
    ("S32_from_S64", "S32", "from_S64", @[("S64", "value")]),
    ("S32_from_U8", "S32", "from_U8", @[("U8", "value")]),
    ("S32_from_U16", "S32", "from_U16", @[("U16", "value")]),
    ("S32_from_U32", "S32", "from_U32", @[("U32", "value")]),
    ("S32_from_U64", "S32", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(S32_module)

  # S64 module
  let s64_module = ? make_native_module("S64", @[
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
    # debug
    ("U64_print", "U64", "print", @[("S64", "value")]),
    # cast
    ("S64_from_S8", "S64", "from_S8", @[("S8", "value")]),
    ("S64_from_S16", "S64", "from_S16", @[("S16", "value")]),
    ("S64_from_S32", "S64", "from_S32", @[("S32", "value")]),
    ("S64_from_U8", "S64", "from_U8", @[("U8", "value")]),
    ("S64_from_U16", "S64", "from_U16", @[("U16", "value")]),
    ("S64_from_U32", "S64", "from_U32", @[("U32", "value")]),
    ("S64_from_U64", "S64", "from_U64", @[("U64", "value")]),
  ])

  ? scope.add_native_module(s64_module)

  # Pointer module
  let ptr_module = ? make_native_module("Pointer", @[
    ("Pointer_shift", "Pointer", "shift", @[("Pointer", "ptr"), ("U64", "offset")]),
    ("Pointer_print", "U64", "print", @[("Pointer", "ptr")]),
    ("Pointer_read_U8", "U8", "read_U8", @[("Pointer", "ptr")]),
    ("Pointer_read_U64", "U64", "read_U64", @[("Pointer", "ptr")]),
    ("Pointer_read_S64", "S64", "read_S64", @[("Pointer", "ptr")]),
    ("Pointer_write_U8", "Pointer", "write_U8", @[("Pointer", "ptr"), ("U8", "value")]),
    ("Pointer_write_U64", "Pointer", "write_U64", @[("Pointer", "ptr"), ("U64", "value")]),
    ("Pointer_write_S64", "Pointer", "write_S64", @[("Pointer", "ptr"), ("S64", "value")]),
  ])
  ? scope.add_native_module(ptr_module)

  # S64 module
  let sys_module = ? make_native_module("System", @[
    ("System_allocate", "Pointer", "allocate", @[("U64", "bytes")]),
    ("System_free", "U8", "free", @[("Pointer", "ptr")]),
  ])
  ? scope.add_native_module(sys_module)

  ok(scope)

# TODO: perform final validation
proc close*(scope: Scope): Result[void, string] =
  if scope.modules.len != 1:
    return err(fmt"root block must have an app block")
  ok()

proc resolve_function_definition(scope: Scope,
    fn_def: FunctionDefinition): Result[void, string] =
  discard ? scope.find_module(fn_def.returns)
  for arg in fn_def.arg_def_list:
    discard ? scope.find_module(arg.module)
  ok()

proc resolve_initializer(scope: Scope, module: Module,
    init: Initializer): Result[Module, string] =
  let resolved_module =
    if $(init.module_name) == "MODULE": module
    else: (? scope.find_module(init.module_name))

  case init.literal.kind:
    of LTK_INTEGER:
      let numeric_value = $(init.literal.integer)
      case $(resolved_module.def.name):
      of "U8": discard ? safe_parse[uint8](numeric_value)
      of "S8": discard ? safe_parse[int8](numeric_value)

      of "U16": discard ? safe_parse[uint16](numeric_value)
      of "S16": discard ? safe_parse[int16](numeric_value)

      of "U32": discard ? safe_parse[uint32](numeric_value)
      of "S32": discard ? safe_parse[int32](numeric_value)
      of "F32": discard ? safe_parse[float32](numeric_value)

      of "U64": discard ? safe_parse[uint64](numeric_value)
      of "S64": discard ? safe_parse[int64](numeric_value)
      of "F64": discard ? safe_parse[float64](numeric_value)
      else: return err(fmt"Only U8/U16/U32/U64/S8/S16/S32/S64/F32/F64 support numeric values in initializer")
    of LTK_STRUCT:
      return err(fmt"ASL does not yet support struct literals")

  ok(resolved_module)

proc resolve_function_call_module(scope: Scope, module: Module,
    fncall: FunctionCall): Result[Module, string] =
  let resolved_module =
    if $(fncall.module_name) == "MODULE": module
    else: ? scope.find_module(fncall.module_name)

  return ok(resolved_module)

type FunctionScope* = ref object of RootObj
  mapping: Table[string, ArgumentDefinition] = initTable[string,
      ArgumentDefinition]()

proc add_arg(fn_scope: FunctionScope, arg_def: ArgumentDefinition): Result[
    void, string] =
  let arg_name = $(arg_def.name)
  if arg_name in fn_scope.mapping:
    return err(fmt"{arg_name} already exists in the scope")

  fn_scope.mapping[arg_name] = arg_def
  return ok()

proc get_arg(fn_scope: FunctionScope, arg_name: Identifier): Result[
    ArgumentDefinition, string] =
  let arg_name_str = $(arg_name)
  if not (arg_name_str in fn_scope.mapping):
    return err(fmt"{arg_name} is not present in the scope")
  ok(fn_scope.mapping[arg_name_str])

proc add_function_definition(fn_scope: FunctionScope,
    fn_def: FunctionDefinition): Result[void, string] =
  for arg in fn_def.arg_def_list:
    ? fn_scope.add_arg(arg)
  ok()

proc resolve_function_call_arg(fn_scope: FunctionScope, scope: Scope,
    arg: Argument, arg_def: ArgumentDefinition): Result[void, string] =
  case arg.kind:
  of AK_IDENTIFIER:
    let scope_arg_def = ? fn_scope.get_arg(arg.name)
    if $(arg_def.module) != $(scope_arg_def.module):
      return err(fmt"{arg.location} {arg.name} is expected to be of type {arg_def.module} but found {scope_arg_def.module}")
  of AK_LITERAL:
    # TODO: check if literal can be cast to the expected module
    let module = ? scope.find_module(arg_def.module)
    case module.kind:
    of MK_NATIVE: discard
    of MK_USER: discard
  return ok()

proc resolve_function_call_arglist(fn_scope: FunctionScope, scope: Scope,
    arg_def_list: seq[ArgumentDefinition], arglist: seq[
        Argument]): Result[void, string] =
  for (arg_def, actual_arg) in zip(arg_def_list, arglist):
    let maybe_resolved = fn_scope.resolve_function_call_arg(scope, actual_arg, arg_def)
    ? maybe_resolved
  ok()

proc resolve_function_call(scope: Scope, fn_module: Module, fn_scope: FunctionScope, fncall: FunctionCall): Result[Identifier, string] =
  for fn in fn_module.find_fn(fncall.fn_name, fncall.arglist.len):
    let maybe_resolved = fn_scope.resolve_function_call_arglist(scope,
        fn.def.arg_def_list, fncall.arglist)
    if maybe_resolved.is_ok:
      return ok(fn.def.returns)
  return err(fmt"{fncall.location} None of the functions calls matched with {fncall}")

proc generate_statement(scope: Scope, s: Statement, module: Module,
    fn: Function, fn_scope: FunctionScope, last_statement: bool): Result[
    string, string] =
  var statements_code: seq[string]
  case s.kind:
  of SK_ASSIGNMENT:
    case s.assign.value.kind:
    of VK_INIT:
      let init = s.assign.value.init
      let init_module = ? scope.resolve_initializer(module, init)
      ? fn_scope.add_arg(new_arg_def(init_module.def.name, s.assign.dest))
      statements_code.add(fmt"{init_module.def.name} {s.assign.dest} = {init.literal};")
    of VK_FNCALL:
      let fncall = s.assign.value.fncall
      let fn_module = ? scope.resolve_function_call_module(module, fncall)
      let return_type = ? scope.resolve_function_call(fn_module, fn_scope, fncall)

      var fncall_args: seq[string]
      for arg in fncall.arglist:
        fncall_args.add($(arg))
      let fncall_args_str = fncall_args.join(", ")
      # TODO: Check the return type of function call in scope, for now using work around
      statements_code.add(fmt"{return_type} {s.assign.dest} = {fn_module.def.name}_{fncall.fn_name}({fncall_args_str});")
      ? fn_scope.add_arg(new_arg_def(return_type, s.assign.dest))

    # last line must be a return
    if last_statement:
      statements_code.add(fmt"return {s.assign.dest};")
  of SK_FNCALL:
    let fncall = s.fncall

    let fn_module = ? scope.resolve_function_call_module(module, fncall)
    let return_type = ? scope.resolve_function_call(fn_module, fn_scope, fncall)

    var fncall_args: seq[string]
    for arg in fncall.arglist:
      fncall_args.add($(arg))
    let fncall_args_str = fncall_args.join(", ")

    var module_name = fn_module.def.name
    var fncall_code = fmt"{module_name}_{fncall.fn_name}({fncall_args_str});"

    # last line must be a return
    if last_statement:
      if $(return_type) != $(fn.def.returns):
        return err(fmt"{fncall.location} Expected {fncall} to return {fn.def.returns} but found {return_type}")
      fncall_code = fmt"return {fncall_code}"

    statements_code.add(fncall_code)
  of SK_IDENTIFIER:
    discard ? fn_scope.get_arg(s.identifier)
    if last_statement:
      statements_code.add(fmt"return {s.identifier};")

  return ok(statements_code.join("\n"))

proc generate_case_block(fn_scope: FunctionScope, scope: Scope,
    module: Module, fn: Function, case_block: Case): Result[string, string] =
    # TODO: Make sure literal is of appropriate kind
  var case_block_code = @[fmt"case {case_block.value}:" & "{"]
  for i, s in case_block.statements:
    let scode = ? scope.generate_statement(s, module, fn, fn_scope, i ==
        case_block.statements.len - 1)
    case_block_code.add(scode)

  case_block_code.add("}")
  return ok(case_block_code.join("\n"))

proc generate_else_block(fn_scope: FunctionScope, scope: Scope,
    module: Module, fn: Function, else_block: Else): Result[string, string] =
  var else_block_code = @[fmt"default:" & "{"]
  for i, s in else_block.statements:
    let scode = ? scope.generate_statement(s, module, fn, fn_scope, i ==
        else_block.statements.len - 1)
    else_block_code.add(scode)
  else_block_code.add("}")
  return ok(else_block_code.join("\n"))

proc generate_match_block(fn_scope: FunctionScope, scope: Scope,
    module: Module, fn: Function, match_block: Match): Result[string, string] =
  discard ? fn_scope.get_arg(match_block.value)

  var match_block_code = @[fmt"switch({match_block.value})" & "{"]
  if match_block.cases.len == 0:
    # if this error shows up something is wrong with blockification logic
    return err(fmt"Match block should at least have 1 case block")

  for case_block in match_block.cases:
    let case_block_code = ? fn_scope.generate_case_block(scope, module, fn, case_block)
    match_block_code.add(case_block_code)

  if match_block.else_blocks.len > 1:
    # if this error shows up something is wrong with blockification logic
    return err(fmt"Match block can not have more than 1 else blocks")

  for else_block in match_block.else_blocks:
    let else_block_code = ? fn_scope.generate_else_block(scope, module, fn, else_block)
    match_block_code.add(else_block_code)

  match_block_code.add("}")
  match_block_code.add("UNREACHABLE();")
  return ok(match_block_code.join("\n"))

proc generate_function*(scope: Scope, module: Module, fn: Function): Result[
    string, string] =
  var fn_code: seq[string]
  var arg_code: seq[string]
  var fn_scope = FunctionScope()

  ? scope.resolve_function_definition(fn.def)
  ? fn_scope.add_function_definition(fn.def)

  # function signature c code
  for arg in fn.def.arg_def_list:
    arg_code.add(fmt"{arg.module} {arg.name}")

  let arg_code_str = arg_code.join(", ")
  fn_code.add(fmt"{fn.def.returns} {module.def.name}_{fn.def.name}(" & arg_code_str & ") {")

  # statement c code
  var steps_code: seq[string]
  let steps = ? fn.steps
  for index, step in steps:
    let step_code =
      case step.kind:
      of FSK_STATEMENT: scope.generate_statement(step.statement, module, fn, fn_scope, index == steps.len - 1)
      of FSK_MATCHER: fn_scope.generate_match_block(scope, module, fn, step.matcher)
    steps_code.add(? step_code)

  fn_code.add(steps_code.join("\n"))
  fn_code.add("}")

  ok(fn_code.join("\n"))

proc generate_app*(scope: Scope): Result[string, string] =
  var module_code: seq[string]
  for module in scope.modules:
    var fn_code: seq[string]
    for fn in module.fns:
      let fnc = ? scope.generate_function(module, fn)
      fn_code.add(fnc)
    module_code.add(fn_code.join("\n"))

  var apps: seq[Module]
  for module in scope.modules:
    if module.def.kind == MDK_APP:
      apps.add(module)

  if apps.len == 0:
    return err(fmt"Failed to find `app` module")
  if apps.len > 1:
    var message = @[fmt"The ASL Program must contain only one app module but found {apps.len} definitions"]
    for app in apps:
      message.add($(app.def.location))
    return err(message.join("\n"))

  let code = @[
    """#include "runtime/asl.h"""",
    module_code.join("\n"),
    "int main(int argc, char** argv) {",
    fmt"return {apps[0].def.name}_start((U8)argc);",
    "}"
  ]

  ok(code.join("\n"))
