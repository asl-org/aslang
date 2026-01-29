import results, strformat, tables, hashes, strutils, sets

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref

type
  AnalyzedStructPatternKind* = enum
    RSPK_DEFAULT, RSPK_NAMED
  AnalyzedStructPattern* = ref object of RootObj
    original_struct: AnalyzedStruct
    args: seq[(AnalyzedArgumentDefinition, Identifier)]
    location: Location
    case kind: AnalyzedStructPatternKind
    of RSPK_DEFAULT: discard
    of RSPK_NAMED: name: Identifier

proc new_analyzed_struct_pattern(original_struct: AnalyzedStruct, args: seq[(
    AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_DEFAULT, original_struct: original_struct,
      args: args, location: location)

proc new_analyzed_struct_pattern(original_struct: AnalyzedStruct,
    name: Identifier, args: seq[(AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_NAMED, original_struct: original_struct,
      name: name, args: args, location: location)

proc kind*(pattern: AnalyzedStructPattern): AnalyzedStructPatternKind = pattern.kind
proc id*(pattern: AnalyzedStructPattern): uint64 = pattern.original_struct.id
proc args*(pattern: AnalyzedStructPattern): seq[(AnalyzedArgumentDefinition,
    Identifier)] = pattern.args
proc original_struct*(pattern: AnalyzedStructPattern): AnalyzedStruct = pattern.original_struct
proc name*(pattern: AnalyzedStructPattern): Identifier =
  do_assert pattern.kind == RSPK_NAMED, "expected named struct"
  pattern.name

proc hash*(pattern: AnalyzedStructPattern): Hash =
  case pattern.kind:
  of RSPK_DEFAULT: "".hash
  of RSPK_NAMED: pattern.name.asl.hash

proc generic_impls*(pattern: AnalyzedStructPattern): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for (argdef, _) in pattern.args: impl_set = impl_set.merge(
      argdef.generic_impls)
  return impl_set

proc asl*(struct_pattern: AnalyzedStructPattern): string =
  let prefix =
    case struct_pattern.kind:
    of RSPK_DEFAULT: ""
    of RSPK_NAMED: fmt"{struct_pattern.name.asl} "

  var args: seq[string]
  for (field, name) in struct_pattern.args:
    args.add(fmt"{name.asl}: {field.name.asl}")

  let args_str = args.join(", ")
  prefix & "{ " & args_str & " }"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, pattern: StructPattern): Result[
    AnalyzedStructPattern, string] =
  case operand.kind:
  of AMRK_GENERIC: err(fmt"{pattern.location} match expression does not support generics")
  of AMRK_MODULE:
    let module = operand.module
    let analyzed_operand_module = ? file_def.find_module_def(module)
    if analyzed_operand_module.structs.len == 0:
      return err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a module and not a union")
    if analyzed_operand_module.structs.len == 1:
      return err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a struct and not a union")

    case pattern.kind:
    of SPK_DEFAULT:
      let analyzed_struct = ? analyzed_operand_module.find_struct()
      let concrete_struct = ? analyzed_struct.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      ok(new_analyzed_struct_pattern(analyzed_struct, analyzed_fields,
          pattern.location))
    of SPK_NAMED:
      let struct_name = ? pattern.struct
      let analyzed_struct = ? analyzed_operand_module.find_struct(struct_name)
      let concrete_struct = ? analyzed_struct.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      ok(new_analyzed_struct_pattern(analyzed_struct, struct_name,
          analyzed_fields, pattern.location))
