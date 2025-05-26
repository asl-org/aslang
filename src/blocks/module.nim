import strutils, results, strformat, options, sets, typetraits, parseutils

import "../rules"

import common, function, matcher

proc safe_parse*[T](input: string): Result[T, string] =
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



type
  ModuleKind* = enum
    MK_USER, MK_NATIVE
  Module* = ref object of RootObj
    kind: ModuleKind
    def: ModuleDefinition
    fns: seq[Function]
    fields: Option[Fields]
    spaces: int

proc def*(module: Module): ModuleDefinition = module.def
proc fns*(module: Module): seq[Function] = module.fns
proc fields*(module: Module): Option[Fields] = module.fields
proc spaces*(module: Module): int = module.spaces
proc kind*(module: Module): ModuleKind = module.kind

proc `$`*(module: Module): string =
  var content: seq[string] = @[prefix(module.spaces) & $(module.def)]

  case module.def.kind:
  of MDK_STRUCT: content.add($(module.fields.get))
  else: discard

  for fn in module.fns:
    content.add($(fn))
  content.join("\n")

proc new_user_module*(def: ModuleDefinition, spaces: int): Module =
  Module(kind: MK_USER, def: def, spaces: spaces)

proc new_native_module*(def: ModuleDefinition): Module =
  Module(kind: MK_NATIVE, def: def, spaces: 0)

proc find_start*(module: Module): Result[Function, string] =
  case module.def.kind:
  of MDK_APP: discard
  else: return err(fmt"Only App module is required to have a start function")

  var start_fns: seq[Function]
  for fn in module.fns:
    if $(fn.def.name) != "start": continue
    if $(fn.def.returns) != "U8": continue
    if fn.def.arg_def_list.len != 1: continue
    if $(fn.def.arg_def_list[0].module) != "U8": continue
    start_fns.add(fn)

  if start_fns.len != 1:
    return err(fmt"App module must always define a start function")

  ok(start_fns[0])

proc find_fn*(module: Module, name: Identifier, arity: int): seq[Function] =
  var matching_fns: seq[Function]
  for fn in module.fns:
    if $(fn.def.name) != $(name): continue
    if fn.def.arg_def_list.len != arity: continue
    matching_fns.add(fn)
  return matching_fns

# TODO: add duplicate block validation
proc add_fn*(module: Module, new_fn: Function): Result[void, string] =
  for fn in module.fns:
    if fn == new_fn:
      return err(fmt"Function {new_fn.def} is already defined")
  module.fns.add(new_fn)
  ok()

proc add_fields*(module: Module, fields: Fields): Result[void, string] =
  if module.fields.is_some:
    return err(fmt"Module {module.def.name} can only contain 1 fields block")
  module.fields = some(fields)
  module.def.kind = MDK_STRUCT
  ok()

# TODO: perform final validation
proc close*(module: Module): Result[void, string] =
  case module.kind:
  of MK_NATIVE:
    return err(fmt"Something went wrong because an asl module can not be used as native")
  of MK_USER:
    case module.def.kind:
    of MDK_APP:
      if module.fns.len == 0:
        return err(fmt"app block must have at least one function block")
      discard ? module.find_start()
    of MDK_MODULE:
      if module.fns.len == 0:
        return err(fmt"app block must have at least one function block")
    of MDK_STRUCT:
      if module.fields.is_none:
        return err(fmt"struct module must have exactly one fields block")
    of MDK_UNION:
      if module.fns.len == 0:
        return err(fmt"app block must have at least one function block")
  ok()

proc resolve_native_numeric*(module: Module, numeric_value: Atom): Result[
    string, string] =
  let numeric_value_str = $(numeric_value)
  case $(module.def.name):
  of "U8": ok($( ? safe_parse[uint8](numeric_value_str)))
  of "U16": ok($( ? safe_parse[uint16](numeric_value_str)))
  of "U32": ok($( ? safe_parse[uint32](numeric_value_str)))
  of "U64": ok($( ? safe_parse[uint64](numeric_value_str)))
  of "S8": ok($( ? safe_parse[int8](numeric_value_str)))
  of "S16": ok($( ? safe_parse[int16](numeric_value_str)))
  of "S32": ok($( ? safe_parse[int32](numeric_value_str)))
  of "S64": ok($( ? safe_parse[int64](numeric_value_str)))
  of "F32": ok($( ? safe_parse[float32](numeric_value_str)))
  of "F64": ok($( ? safe_parse[float64](numeric_value_str)))
  else: err(fmt"Only U8/U16/U32/U64/S8/S16/S32/S64/F32/F64 support numeric values in initializer")

proc resolve_struct_literal*(module: Module, struct: Struct): Result[seq[
    ArgumentDefinition], string] =
  case module.kind:
  of MK_NATIVE: return err(fmt"Native modules can not be struct literal")
  of MK_USER: discard

  case module.def.kind:
  of MDK_STRUCT: discard
  else: return err(fmt"{module.def.name} must be a struct")

  if module.fields.is_none:
    return err(fmt"Unexpected error there is some problem with blockification logic")
  if module.fields.get.field_defs.len != struct.kwargs.len:
    return err(fmt"{struct.location} Expected {module.fields.get.field_defs.len} fields but found {struct.kwargs.len}")

  var field_name_set: HashSet[string]
  var expected_fields: seq[ArgumentDefinition]

  for kwarg in struct.kwargs:
    if $(kwarg.name) in field_name_set:
      return err(fmt"Field {kwarg.name} is defined twice")

    field_name_set.incl($(kwarg.name))

    let field_def = ? module.fields.get.get_field_def(kwarg.name)
    expected_fields.add(field_def)

  return ok(expected_fields)
