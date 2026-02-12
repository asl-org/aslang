import results, sequtils, strformat, tables, strutils, sets, options

import resolver
import module_ref
import arg_def
# import struct
import module_def
import file_def
import func_ref
import arg
import struct_ref


type AnalyzedStructInit* = ref object of RootObj
  data_ref: AnalyzedDataRef
  fields: seq[AnalyzedArgument]

proc new_analyzed_struct_init(data_ref: AnalyzedDataRef, fields: seq[
    AnalyzedArgument]): AnalyzedStructInit =
  AnalyzedStructInit(data_ref: data_ref, fields: fields)

proc data_ref*(struct_init: AnalyzedStructInit): AnalyzedDataRef = struct_init.data_ref
proc fields*(struct_init: AnalyzedStructInit): seq[AnalyzedArgument] = struct_init.fields

proc returns*(struct_init: AnalyzedStructInit): AnalyzedModuleRef =
  struct_init.data_ref.module_ref

proc generic_impls*(struct_init: AnalyzedStructInit): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(struct_init.data_ref.generic_impls)
  for field in struct_init.fields: impl_set = impl_set.merge(
      field.generic_impls)
  return impl_set

proc asl*(struct_init: AnalyzedStructInit): string =
  var args: seq[string]
  for (field_def, field_arg) in zip(struct_init.data_ref.fields,
      struct_init.fields):
    args.add(fmt"{field_def.name.asl}: {field_arg.asl}")
  let args_str = args.join(", ")
  struct_init.data_ref.asl & " { " & args_str & " }"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedStructInit,
    module_def: Option[AnalyzedModuleDefinition] = none[AnalyzedModuleDefinition]()): Result[AnalyzedStructInit, string] =
  let analyzed_data_ref = ? analyze(file_def, scope, init.struct_ref, module_def)

  var args = new_seq[Argument](analyzed_data_ref.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let analyzed_field_index = ? analyzed_data_ref.find_field_index(field.name)
    found_field_indices.incl(analyzed_field_index)
    args[analyzed_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < analyzed_data_ref.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let analyzed_fields = ? analyze(file_def, scope, args,
      analyzed_data_ref.fields)
  ok(new_analyzed_struct_init(analyzed_data_ref, analyzed_fields))

