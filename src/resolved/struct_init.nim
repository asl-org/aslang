import sequtils, strutils, strformat

import "../blocks"
import arg

type ResolvedStructInit* = ref object of RootObj
  module*: UserModule
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init*(module: UserModule, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(module: module, fields: fields)

proc c*(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.module.name}_init({fields})"

type ResolvedUnionInit* = ref object of RootObj
  module*: UserModule
  union_field: UnionFieldDefinition
  fields: seq[ResolvedArgument]

proc new_resolved_union_init*(module: UserModule,
    union_field: UnionFieldDefinition, fields: seq[
    ResolvedArgument]): ResolvedUnionInit =
  ResolvedUnionInit(module: module, union_field: union_field, fields: fields)

proc c*(init: ResolvedUnionInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.module.name}_{init.union_field.name}_init({fields})"
