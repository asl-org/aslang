import sequtils, strutils, strformat, tables, sets

import arg
import function_ref

type ResolvedStructInit* = ref object of RootObj
  module*: UserModule
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init*(module: UserModule, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(module: module, fields: fields)

proc function_refs*(struct_init: ResolvedStructInit): HashSet[
    ResolvedFunctionRef] =
  var function_set: HashSet[ResolvedFunctionRef]
  for field in struct_init.fields:
    function_set.incl(field.function_refs)
  return function_set

proc generic_impls*(struct_init: ResolvedStructInit): Table[string, Table[
    string, HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  impls[$(struct_init.module.name)] = init_table[string, HashSet[string]]()
  for field in struct_init.fields:
    for (generic, concrete) in field.generic_impls.pairs:
      if generic notin impls[$(struct_init.module.name)]:
        impls[$(struct_init.module.name)][generic] = init_hashset[string]()
      impls[$(struct_init.module.name)][generic].incl(concrete)
  return impls

proc c*(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.module.name}_init({fields})"

type ResolvedUnionInit* = ref object of RootObj
  module*: UserModule
  union_field: UnionFieldDefinition
  fields: seq[ResolvedArgument]
  temp_var_start: uint

proc new_resolved_union_init*(module: UserModule,
    union_field: UnionFieldDefinition, fields: seq[
    ResolvedArgument], temp_var_start: uint): ResolvedUnionInit =
  ResolvedUnionInit(module: module, union_field: union_field, fields: fields,
      temp_var_start: temp_var_start)

proc function_refs*(union_init: ResolvedUnionInit): HashSet[
    ResolvedFunctionRef] =
  var function_set: HashSet[ResolvedFunctionRef]
  for field in union_init.fields:
    function_set.incl(field.function_refs)
  return function_set

proc generic_impls*(union_init: ResolvedUnionInit): Table[string, Table[string,
    HashSet[string]]] =
  var impls: Table[string, Table[string, HashSet[string]]]
  impls[$(union_init.module.name)] = init_table[string, HashSet[string]]()
  for field in union_init.fields:
    for (generic, concrete) in field.generic_impls.pairs:
      if generic notin impls[$(union_init.module.name)]:
        impls[$(union_init.module.name)][generic] = init_hashset[string]()
      impls[$(union_init.module.name)][generic].incl(concrete)
  return impls

proc c*(init: ResolvedUnionInit): string =
  var field_values: seq[string]
  var temp_var_count = init.temp_var_start
  var code: seq[string]

  for field in init.fields:
    case field.kind:
    of RAK_VARIABLE:
      case field.variable.kind:
      of RVK_DEFAULT:
        field_values.add($(field.value))
      of RVK_GENERIC:
        let temp_var = fmt"__asl__temp_var_{temp_var_count}"
        temp_var_count += 1
        let field_name = $(field.value)
        field_values.add(temp_var)

        let module_name = $(init.module.name)
        let generic_name = $(field.variable.generic)
        code.add(fmt"Pointer {temp_var} = {module_name}_{generic_name}_{field.variable.arg_def.typ}_init({field_name});")
    of RAK_LITERAL:
      field_values.add($(field.value))

  let fields_str = field_values.join(", ")
  code.add(fmt"{init.module.name}_{init.union_field.name}_init({fields_str})")
  return code.join("\n")
