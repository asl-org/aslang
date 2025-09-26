import strformat

import function_ref, arg

type ResolvedStructGetter* = ref object of RootObj
  module*: UserModule
  field*: ArgumentDefinition
  resolved_field: ResolvedArgumentDefinition
  arg: Token

proc new_resolved_struct_getter*(module: UserModule,
    field: ArgumentDefinition, arg: Token,
        resolved_field: ResolvedArgumentDefinition): ResolvedStructGetter =
  ResolvedStructGetter(module: module, field: field, arg: arg,
      resolved_field: resolved_field)

proc resolved_return_type*(getter: ResolvedStructGetter): ResolvedArgumentType =
  getter.resolved_field.arg_type

proc c*(getter: ResolvedStructGetter): string =
  fmt"{getter.module.name}_get_{getter.field.name}({getter.arg})"
