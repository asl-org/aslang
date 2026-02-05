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
    args: seq[(AnalyzedArgumentDefinition, Identifier)]
    location: Location
    case kind: AnalyzedStructPatternKind
    of RSPK_DEFAULT: struct: AnalyzedStruct
    of RSPK_NAMED: branch: AnalyzedUnionBranch

proc new_analyzed_struct_pattern(struct: AnalyzedStruct, args: seq[(
    AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_DEFAULT, struct: struct, args: args,
      location: location)

proc new_analyzed_struct_pattern(branch: AnalyzedUnionBranch,
    name: Identifier, args: seq[(AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_NAMED, branch: branch, args: args,
      location: location)

proc kind*(pattern: AnalyzedStructPattern): AnalyzedStructPatternKind = pattern.kind
proc id*(pattern: AnalyzedStructPattern): uint64 =
  do_assert pattern.kind == RSPK_NAMED, "expected a union branch pattern"
  pattern.branch.id
proc args*(pattern: AnalyzedStructPattern): seq[(AnalyzedArgumentDefinition,
    Identifier)] = pattern.args
proc struct*(pattern: AnalyzedStructPattern): AnalyzedStruct =
  do_assert pattern.kind == RSPK_DEFAULT, "expected struct"
  pattern.struct
proc branch*(pattern: AnalyzedStructPattern): AnalyzedUnionBranch =
  do_assert pattern.kind == RSPK_NAMED, "expected branch"
  pattern.branch
proc name*(pattern: AnalyzedStructPattern): Identifier =
  do_assert pattern.kind == RSPK_NAMED, "expected union"
  pattern.branch.name

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
    case analyzed_operand_module.data.kind:
    of ADK_NONE, ADK_LITERAL: err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a module and not a union")
    of ADK_UNION:
      let struct_name = ? pattern.struct
      let analyzed_branch = ? analyzed_operand_module.find_branch(struct_name)
      let concrete_branch = ? analyzed_branch.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_branch.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      return ok(new_analyzed_struct_pattern(analyzed_branch, struct_name,
          analyzed_fields, pattern.location))
      # return err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a struct and not a union")
    of ADK_STRUCT:
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
        let analyzed_branch = ? analyzed_operand_module.find_branch(struct_name)
        let concrete_branch = ? analyzed_branch.concretize(operand.concrete_map)
        var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
        for (key, value) in pattern.args:
          let field = ? concrete_branch.find_field(key)
          let value_arg = new_analyzed_argument_definition(field.module_ref, value)
          analyzed_fields.add((value_arg, key))
        ok(new_analyzed_struct_pattern(analyzed_branch, struct_name,
            analyzed_fields, pattern.location))
