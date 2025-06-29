import strformat

import "../blocks"

type ResolvedStructGetter* = ref object of RootObj
  struct*: Struct
  field*: ArgumentDefinition
  arg: Token

proc new_resolved_struct_getter*(struct: Struct,
    field: ArgumentDefinition, arg: Token): ResolvedStructGetter =
  ResolvedStructGetter(struct: struct, field: field, arg: arg)

proc c*(getter: ResolvedStructGetter): string =
  fmt"{getter.struct.name}_get_{getter.field.arg_name}({getter.arg})"
