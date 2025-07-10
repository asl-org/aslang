import sequtils, strutils, strformat

import "../blocks"
import expression

type ResolvedStructInit* = ref object of RootObj
  module*: Module
  fields: seq[ResolvedExpression]

proc new_resolved_struct_init*(module: Module, fields: seq[
    ResolvedExpression]): ResolvedStructInit =
  ResolvedStructInit(module: module, fields: fields)

proc c*(init: ResolvedStructInit): string =
  let fields = init.fields.map_it($(it.value)).join(", ")
  fmt"{init.module.name}_init({fields})"
