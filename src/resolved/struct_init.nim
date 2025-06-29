import sequtils, strutils, strformat

import "../blocks"
import argument

type ResolvedStructInit* = ref object of RootObj
  struct*: Struct
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init*(struct: Struct, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(struct: struct, fields: fields)

proc c*(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.struct.name}_init({fields})"
