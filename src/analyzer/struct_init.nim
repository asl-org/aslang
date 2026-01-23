import results, sequtils, strformat, tables, hashes, strutils, sets

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref
import arg
import struct_ref


type AnalyzedStructInit* = ref object of RootObj
  struct_ref: AnalyzedStructRef
  fields: seq[AnalyzedArgument]

proc new_analyzed_struct_init(struct_ref: AnalyzedStructRef, fields: seq[
    AnalyzedArgument]): AnalyzedStructInit =
  AnalyzedStructInit(struct_ref: struct_ref, fields: fields)

proc returns*(struct_init: AnalyzedStructInit): AnalyzedModuleRef =
  struct_init.struct_ref.module_ref

proc generic_impls*(struct_init: AnalyzedStructInit): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(struct_init.struct_ref.generic_impls)
  for field in struct_init.fields: impl_set = impl_set.merge(
      field.generic_impls)
  return impl_set

proc asl*(struct_init: AnalyzedStructInit): string =
  var args: seq[string]
  for (field_def, field_arg) in zip(struct_init.struct_ref.struct.fields,
      struct_init.fields):
    args.add(fmt"{field_def.name.asl}: {field_arg.asl}")
  let args_str = args.join(", ")
  struct_init.struct_ref.asl & " { " & args_str & " }"

proc c*(struct_init: AnalyzedStructInit, result_arg: string): seq[string] =
  var lines: seq[string]
  var args: seq[string]
  for index in 0..<struct_init.fields.len:
    let original_field = struct_init.struct_ref.origin.fields[index]
    let concrete_field = struct_init.struct_ref.struct.fields[index]
    let arg = struct_init.fields[index]
    case original_field.module_ref.kind:
    of AMRK_GENERIC:
      case concrete_field.module_ref.kind:
      of AMRK_GENERIC: args.add(arg.c)
      else:
        let arg_name = fmt"__asl_arg_{concrete_field.location.hash.to_hex}"
        lines.add(fmt"Pointer {arg_name} = System_box_{concrete_field.module_ref.c}({arg.c});")
        args.add(arg_name)
    else: args.add(arg.c)

  let args_str = args.join(", ")
  lines.add(fmt"Pointer {result_arg} = {struct_init.struct_ref.c}_init({args_str});")
  return lines

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    init: ResolvedStructInit): Result[AnalyzedStructInit, string] =
  let analyzed_struct_ref = ? analyze(file_def, module_def, scope,
      init.struct_ref)

  var args = new_seq[Argument](analyzed_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let analyzed_field_index = ? analyzed_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(analyzed_field_index)
    args[analyzed_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < analyzed_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let analyzed_fields = ? analyze(file_def, scope, args,
      analyzed_struct_ref.struct.fields)
  ok(new_analyzed_struct_init(analyzed_struct_ref, analyzed_fields))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedStructInit): Result[AnalyzedStructInit, string] =
  let analyzed_struct_ref = ? analyze(file_def, scope, init.struct_ref)

  var args = new_seq[Argument](analyzed_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let analyzed_field_index = ? analyzed_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(analyzed_field_index)
    args[analyzed_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < analyzed_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let analyzed_fields = ? analyze(file_def, scope, args,
      analyzed_struct_ref.struct.fields)
  ok(new_analyzed_struct_init(analyzed_struct_ref, analyzed_fields))

