import strformat

import "../blocks"

type ResolvedStructGetter* = ref object of RootObj
  module*: Module
  field*: ArgumentDefinition
  arg: Token

proc new_resolved_struct_getter*(module: Module,
    field: ArgumentDefinition, arg: Token): ResolvedStructGetter =
  ResolvedStructGetter(module: module, field: field, arg: arg)

proc c*(getter: ResolvedStructGetter): string =
  fmt"{getter.module.name}_get_{getter.field.arg_name}({getter.arg})"
