import tables, strutils, strformat, sequtils, options

import "../blocks"

const ASL_PREFIX = "__asl__"

type ResolvedStruct* = ref object of RootObj
  module: UserModule
  byte_size: uint
  field_offset: Table[string, uint]

### C CODE GENERARTION UTILS START
proc getter(resolved_struct: ResolvedStruct,
    field: ArgumentDefinition): string =
  let module = resolved_struct.module
  let offset = resolved_struct.field_offset[$(field.arg_name)]

  let code = @[
    fmt"{field.native_type} {module.name}_get_{field.arg_name}(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"Pointer {ASL_PREFIX}shifted_ptr = Pointer_shift({ASL_PREFIX}ptr, {offset});",
    fmt"{field.native_type} value = {field.native_type}_from_Pointer({ASL_PREFIX}shifted_ptr);",
    "return value;",
    "}",
  ]
  return code.join("\n")

proc setter(resolved_struct: ResolvedStruct,
    field: ArgumentDefinition): string =
  let module = resolved_struct.module
  let offset = resolved_struct.field_offset[$(field.arg_name)]

  let code = @[
    fmt"Pointer {module.name}_set_{field.arg_name}(Pointer {ASL_PREFIX}ptr, {field.native_type} value)",
    "{",
    fmt"Pointer {ASL_PREFIX}shifted_ptr = Pointer_shift({ASL_PREFIX}ptr, {offset});",
    fmt"Pointer _ = Pointer_write_{field.native_type}({ASL_PREFIX}shifted_ptr, value);",
    fmt"return {ASL_PREFIX}ptr;",
    "}",
  ]
  return code.join("\n")

proc init(resolved_struct: ResolvedStruct): string =
  let module = resolved_struct.module
  let struct = module.struct.get
  let byte_size = resolved_struct.byte_size
  let fields_def = struct.fields.values.to_seq.map_it($(it)).join(", ")
  let setter_calls = struct.fields.values.to_seq.map_it(
      fmt"{ASL_PREFIX}ptr = {module.name}_set_{it.arg_name}({ASL_PREFIX}ptr, {it.arg_name});").join("\n")

  let code = @[
    fmt"Pointer {module.name}_init({fields_def})",
    "{",
    fmt"Pointer {ASL_PREFIX}ptr = System_allocate({byte_size});",
    setter_calls,
    fmt"return {ASL_PREFIX}ptr;",
    "}",
  ]
  return code.join("\n")

proc free(resolved_struct: ResolvedStruct): string =
  let module = resolved_struct.module
  @[
    fmt"U64 {module.name}_free(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"return System_free({ASL_PREFIX}ptr);",
    "}",
  ].join("\n")
### C CODE GENERARTION UTILS END

proc h*(resolved_struct: ResolvedStruct): string =
  let module = resolved_struct.module
  let struct = module.struct.get

  let args_str = struct.fields.values.to_seq.map_it($(it)).join(", ")
  let init = fmt"Pointer {module.name}_init({args_str});"
  let free = fmt"U64 {module.name}_free(Pointer);"

  var headers: seq[string] = @[init, free]
  for field in struct.fields.values:
    let native_arg_type =
      case $(field.arg_type):
      of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "F32", "F64",
          "Pointer": $(field.arg_type)
      else: "Pointer"

    let getter = fmt"{native_arg_type} {module.name}_get_{field.arg_name}(Pointer);"
    let setter = fmt"Pointer {module.name}_set_{field.arg_name}(Pointer, {native_arg_type});"
    headers.add(getter)
    headers.add(setter)

  return headers.join("\n")

proc c*(resolved_struct: ResolvedStruct): string =
  var code: seq[string]
  code.add(resolved_struct.init())
  for field in resolved_struct.module.struct.get.fields.values:
    code.add(resolved_struct.getter(field))
    code.add(resolved_struct.setter(field))
  code.add(resolved_struct.free())
  return code.join("\n\n")

proc new_resolved_struct*(module: UserModule, byte_size: uint,
    field_offset: Table[string, uint]): ResolvedStruct =
  ResolvedStruct(module: module, byte_size: byte_size,
      field_offset: field_offset)
