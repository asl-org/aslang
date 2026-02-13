import results, strformat, tables, sets, options

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref
import struct_ref

type AnalyzedStructGet* = ref object of RootObj
  variable: AnalyzedArgumentDefinition
  field: AnalyzedArgumentDefinition

proc new_analyzed_struct_get(variable: AnalyzedArgumentDefinition,
    field: AnalyzedArgumentDefinition): AnalyzedStructGet =
  AnalyzedStructGet(variable: variable, field: field)

proc variable*(struct_get: AnalyzedStructGet): AnalyzedArgumentDefinition = struct_get.variable
proc field*(struct_get: AnalyzedStructGet): AnalyzedArgumentDefinition = struct_get.field

proc returns*(struct_get: AnalyzedStructGet): AnalyzedModuleRef =
  struct_get.field.module_ref

proc generic_impls*(struct_get: AnalyzedStructGet): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(struct_get.variable.generic_impls)
  impl_set = impl_set.merge(struct_get.field.generic_impls)
  return impl_set

proc asl*(struct_get: AnalyzedStructGet): string =
  fmt"{struct_get.variable.name.asl}.{struct_get.field.name.asl}"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    struct_get: ResolvedStructGet,
    module_def: Option[AnalyzedModuleDefinition] = none[
        AnalyzedModuleDefinition]()): Result[AnalyzedStructGet, string] =
  let analyzed_module_ref = ? scope.get(struct_get.variable)
  let analyzed_variable = new_analyzed_argument_definition(analyzed_module_ref,
      struct_get.variable)
  case analyzed_module_ref.kind:
  of AMRK_GENERIC: err(fmt"7 {struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of AMRK_MODULE:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(resolved_module)
    case analyzed_module_def.data.kind:
    of ADK_NONE, ADK_LITERAL: err(fmt"{struct_get.location} module `{analyzed_module_def.name.asl}` is not a struct")
    of ADK_UNION: err(fmt"{struct_get.location} module `{analyzed_module_def.name.asl}` is a union")
    of ADK_STRUCT:
      let maybe_default_struct = analyzed_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(err_no_default_struct(struct_get.location,
            analyzed_module_def.name.asl))
      else:
        let analyzed_struct = maybe_default_struct.get
        let analyzed_field_module_ref = ? analyzed_struct.find_field(
            struct_get.field)
        let analyzed_field = analyzed_field_module_ref.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_get(analyzed_variable, analyzed_field))
