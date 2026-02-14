# Compute FunctionMetadata for codegen-generated struct/union functions.
#
# For each struct/union, gen_struct.nim generates C functions:
#   _init        → allocates, returns_allocated, consumes_args
#   _get_*       → reads_only (defaults)
#   _set_*       → mutates_args
#   _byte_size   → reads_only (defaults)
#   _read        → reads_only (defaults)
#   _write       → mutates_args
#
# This module mirrors that logic at the analyzer level so the optimizer
# can use pre-populated metadata instead of inferring from C IR strings.

import strformat, tables

import resolver
import struct
import arg_def
import ../metadata

proc alloc_metadata(): FunctionMetadata =
  FunctionMetadata(allocates: true, mutates_args: false,
      reads_only: false, returns_allocated: true,
      alloc_kind: AK_PLAIN, consumes_args: true)

proc mutate_metadata(): FunctionMetadata =
  FunctionMetadata(allocates: false, mutates_args: true,
      reads_only: false, returns_allocated: false,
      alloc_kind: AK_PLAIN, consumes_args: false)

proc compute_struct_metadata*(struct: AnalyzedStruct,
    prefix: string): Table[string, FunctionMetadata] =
  var meta: Table[string, FunctionMetadata]

  meta[fmt"{prefix}_byte_size"] = new_function_metadata()
  meta[fmt"{prefix}_read"] = new_function_metadata()
  meta[fmt"{prefix}_write"] = mutate_metadata()

  for field in struct.fields:
    meta[fmt"{prefix}_get_{field.name.asl}"] = new_function_metadata()
    meta[fmt"{prefix}_set_{field.name.asl}"] = mutate_metadata()

  meta[fmt"{prefix}_init"] = alloc_metadata()
  return meta

proc compute_branch_metadata*(branch: AnalyzedUnionBranch,
    prefix: string, id: uint64): Table[string, FunctionMetadata] =
  var meta: Table[string, FunctionMetadata]
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"

  for field in branch.fields:
    meta[fmt"{sub_prefix}_get_{field.name.asl}"] = new_function_metadata()
    meta[fmt"{sub_prefix}_set_{field.name.asl}"] = mutate_metadata()

  meta[fmt"{sub_prefix}_init"] = alloc_metadata()
  return meta

proc compute_union_metadata*(union: AnalyzedUnion,
    prefix: string): Table[string, FunctionMetadata] =
  var meta: Table[string, FunctionMetadata]

  meta[fmt"{prefix}_byte_size"] = new_function_metadata()
  meta[fmt"{prefix}_read"] = new_function_metadata()
  meta[fmt"{prefix}_write"] = mutate_metadata()

  meta[fmt"{prefix}_get_id"] = new_function_metadata()
  meta[fmt"{prefix}_set_id"] = mutate_metadata()

  for index, branch in union.branches:
    for name, m in compute_branch_metadata(branch, prefix, index.uint64):
      meta[name] = m

  return meta

proc compute_data_metadata*(data: AnalyzedData,
    prefix: string): Table[string, FunctionMetadata] =
  case data.kind:
  of ADK_NONE, ADK_LITERAL:
    return initTable[string, FunctionMetadata]()
  of ADK_STRUCT:
    return compute_struct_metadata(data.struct, prefix)
  of ADK_UNION:
    return compute_union_metadata(data.union, prefix)
