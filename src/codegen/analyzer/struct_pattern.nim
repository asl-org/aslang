import results, strformat, tables, hashes, strutils, sets

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref

type
  AnalyzedUnionPattern* = ref object of RootObj
    branch: AnalyzedUnionBranch
    args: seq[(AnalyzedArgumentDefinition, Identifier)]
    location: Location

proc new_analyzed_union_pattern*(branch: AnalyzedUnionBranch,
    name: Identifier, args: seq[(AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedUnionPattern =
  AnalyzedUnionPattern(branch: branch, args: args, location: location)

proc id*(pattern: AnalyzedUnionPattern): uint64 = pattern.branch.id
proc args*(pattern: AnalyzedUnionPattern): seq[(AnalyzedArgumentDefinition,
    Identifier)] = pattern.args
proc branch*(pattern: AnalyzedUnionPattern): AnalyzedUnionBranch =
    pattern.branch
proc name*(pattern: AnalyzedUnionPattern): Identifier = pattern.branch.name

proc hash*(pattern: AnalyzedUnionPattern): Hash =
  pattern.name.asl.hash

proc generic_impls*(pattern: AnalyzedUnionPattern): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for (argdef, _) in pattern.args: impl_set = impl_set.merge(
      argdef.generic_impls)
  return impl_set

proc asl*(union_pattern: AnalyzedUnionPattern): string =
  var args: seq[string]
  for (field, name) in union_pattern.args:
    args.add(fmt"{name.asl}: {field.name.asl}")

  let args_str = args.join(", ")
  fmt"{union_pattern.name.asl} " & "{ " & args_str & " }"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, pattern: StructPattern): Result[
    AnalyzedUnionPattern, string] =
  case operand.kind:
  of AMRK_GENERIC: err(fmt"{pattern.location} match expression does not support generics")
  of AMRK_MODULE:
    let module = operand.module
    let analyzed_operand_module = ? file_def.find_module_def(module)
    case analyzed_operand_module.data.kind:
    of ADK_NONE, ADK_LITERAL, ADK_STRUCT: err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is not a union")
    of ADK_UNION:
      let branch_name = pattern.struct
      let analyzed_branch = ? analyzed_operand_module.find_branch(branch_name)
      let concrete_branch = ? analyzed_branch.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_branch.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      ok(new_analyzed_union_pattern(analyzed_branch, branch_name,
          analyzed_fields, pattern.location))
