import results, strformat, tables, sets, options

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref

# Error message helpers
proc err_no_default_struct*(location: Location, module_name: string): string =
  fmt"{location} module `{module_name}` does not have a default struct"

proc err_no_named_struct*(location: Location, module_name: string,
    struct_name: string): string =
  fmt"{location} module `{module_name}` does not have a struct named `{struct_name}`"

type AnalyzedStructRef* = ref object of RootObj
  module_ref: AnalyzedModuleRef
  origin: AnalyzedStruct
  struct: AnalyzedStruct

proc new_analyzed_struct_ref(module_ref: AnalyzedModuleRef,
    origin: AnalyzedStruct, struct: AnalyzedStruct): AnalyzedStructRef =
  AnalyzedStructRef(module_ref: module_ref, origin: origin, struct: struct)

proc module_ref*(struct_ref: AnalyzedStructRef): AnalyzedModuleRef =
  struct_ref.module_ref

proc origin*(struct_ref: AnalyzedStructRef): AnalyzedStruct =
  struct_ref.origin

proc struct*(struct_ref: AnalyzedStructRef): AnalyzedStruct =
  struct_ref.struct

proc generic_impls*(struct_ref: AnalyzedStructRef): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  struct_ref.module_ref.generic_impls

proc asl*(struct_ref: AnalyzedStructRef): string =
  let suffix =
    case struct_ref.struct.kind:
    of RSK_DEFAULT: ""
    of RSK_NAMED: fmt".{struct_ref.struct.name.asl}"
  fmt"{struct_ref.module_ref.asl}{suffix}"

proc c*(struct_ref: AnalyzedStructRef): string =
  case struct_ref.struct.kind:
  of RSK_DEFAULT: fmt"{struct_ref.module_ref.name}"
  of RSK_NAMED: fmt"{struct_ref.module_ref.name}_{struct_ref.struct.name.asl}"

type AnalyzedUnionRef* = ref object of RootObj
  module_ref: AnalyzedModuleRef
  origin: AnalyzedUnionBranch
  branch: AnalyzedUnionBranch

proc new_analyzed_union_ref(module_ref: AnalyzedModuleRef,
    origin: AnalyzedUnionBranch, branch: AnalyzedUnionBranch): AnalyzedUnionRef =
  AnalyzedUnionRef(module_ref: module_ref, origin: origin, branch: branch)

proc module_ref*(union_ref: AnalyzedUnionRef): AnalyzedModuleRef = union_ref.module_ref

proc generic_impls*(union_ref: AnalyzedUnionRef): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  union_ref.module_ref.generic_impls

proc asl*(union_ref: AnalyzedUnionRef): string =
  fmt"{union_ref.module_ref.asl}.{union_ref.branch.name.asl}"

proc c*(union_ref: AnalyzedUnionRef): string =
  fmt"{union_ref.module_ref.name}_{union_ref.branch.name.asl}"

type
  AnalyzedDataRefKind* = enum
    ADRK_STRUCT, ADRK_UNION
  AnalyzedDataRef* = ref object of RootObj
    case kind: AnalyzedDataRefKind
    of ADRK_STRUCT: struct: AnalyzedStructRef
    of ADRK_UNION: union: AnalyzedUnionRef

proc new_analyzed_data_ref(struct: AnalyzedStructRef): AnalyzedDataRef =
  AnalyzedDataRef(kind: ADRK_STRUCT, struct: struct)

proc new_analyzed_data_ref(union: AnalyzedUnionRef): AnalyzedDataRef =
  AnalyzedDataRef(kind: ADRK_UNION, union: union)

proc original_fields*(data_ref: AnalyzedDataRef): seq[
    AnalyzedArgumentDefinition] =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.origin.fields
  of ADRK_UNION: data_ref.union.origin.fields

proc fields*(data_ref: AnalyzedDataRef): seq[AnalyzedArgumentDefinition] =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.struct.fields
  of ADRK_UNION: data_ref.union.branch.fields

proc module_ref*(data_ref: AnalyzedDataRef): AnalyzedModuleRef =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.module_ref
  of ADRK_UNION: data_ref.union.module_ref

proc generic_impls*(data_ref: AnalyzedDataRef): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.generic_impls
  of ADRK_UNION: data_ref.union.generic_impls

proc asl*(data_ref: AnalyzedDataRef): string =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.asl
  of ADRK_UNION: data_ref.union.asl

proc c*(data_ref: AnalyzedDataRef): string =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.c
  of ADRK_UNION: data_ref.union.c

proc find_field_index*(data_ref: AnalyzedDataRef, name: Identifier): Result[int, string] =
  case data_ref.kind:
  of ADRK_STRUCT: data_ref.struct.struct.find_field_index(name)
  of ADRK_UNION: data_ref.union.branch.find_field_index(name)

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    struct_ref: ResolvedStructRef,
    module_def: Option[AnalyzedModuleDefinition] = none[AnalyzedModuleDefinition]()): Result[AnalyzedDataRef, string] =
  let analyzed_module_ref = if module_def.isSome:
    ? analyze_def(file_def.file, module_def.get.resolved_module, struct_ref.module_ref)
  else:
    ? analyze_def(file_def.file, struct_ref.module_ref)
  case analyzed_module_ref.kind:
  of AMRK_GENERIC:
    err(fmt"{struct_ref.location} generic `{analyzed_module_ref.generic.name.asl}` is not a struct")
  of AMRK_MODULE:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(resolved_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = analyzed_module_def.find_struct()
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = ? analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        let analyzed_struct_ref = new_analyzed_struct_ref(analyzed_module_ref,
            analyzed_struct,
            analyzed_concretized_struct)
        ok(new_analyzed_data_ref(analyzed_struct_ref))
      else:
        err(err_no_default_struct(struct_ref.location,
            analyzed_module_def.name.asl))
    of TSRK_NAMED:
      let branch_name = ? struct_ref.name
      let maybe_branch = analyzed_module_def.find_branch(branch_name)
      if maybe_branch.is_ok:
        let analyzed_branch = maybe_branch.get
        let analyzed_concretized_branch = ? analyzed_branch.concretize(
            analyzed_module_ref.concrete_map)
        let analyzed_union_ref = new_analyzed_union_ref(analyzed_module_ref,
            analyzed_branch, analyzed_concretized_branch)
        ok(new_analyzed_data_ref(analyzed_union_ref))
      else:
        err(err_no_named_struct(struct_ref.location,
            analyzed_module_def.name.asl, branch_name.asl))
