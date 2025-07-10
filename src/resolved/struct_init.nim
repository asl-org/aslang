import sequtils, strutils, strformat

import "../blocks"
import expression

type ResolvedStructInit* = ref object of RootObj
  struct*: NamedStruct
  fields: seq[ResolvedExpression]

proc new_resolved_struct_init*(struct: NamedStruct, fields: seq[
    ResolvedExpression]): ResolvedStructInit =
  ResolvedStructInit(struct: struct, fields: fields)

proc c*(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.struct.name}_init({fields})"
