import results, strformat, tables, sets, options

import resolver
import module_ref
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

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    struct_ref: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, module_def.module,
      struct_ref.module_ref)
  case analyzed_module_ref.kind:
  of AMRK_GENERIC:
    err(fmt"1 {struct_ref.location} generic `{analyzed_module_ref.generic.name.asl}` is not a struct")
  of AMRK_MODULE:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(resolved_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = analyzed_module_def.find_struct()
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_default_struct(struct_ref.location,
            analyzed_module_def.name.asl))
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = analyzed_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_named_struct(struct_ref.location,
            analyzed_module_def.name.asl, struct_name.asl))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    struct_ref: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, struct_ref.module_ref)
  case analyzed_module_ref.kind:
  of AMRK_GENERIC:
    err(fmt"2 {struct_ref.location} generic `{analyzed_module_ref.generic.name.asl}` is not a struct")
  of AMRK_MODULE:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(resolved_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = analyzed_module_def.find_struct()
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_default_struct(struct_ref.location,
            analyzed_module_def.name.asl))
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = analyzed_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_named_struct(struct_ref.location,
            analyzed_module_def.name.asl, struct_name.asl))
