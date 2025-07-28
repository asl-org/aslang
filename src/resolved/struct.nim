import tables, strutils, strformat, sequtils

import "../blocks"

const ASL_PREFIX = "__asl__"

### C CODE GENERARTION UTILS START

proc getter_h(return_type: string, function_name: string): string =
  fmt"{return_type} {function_name}(Pointer {ASL_PREFIX}ptr);"

proc getter_c(return_type: string, function_name: string,
    offset: uint): string =
  @[
    fmt"{return_type} {function_name}(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"Pointer {ASL_PREFIX}shifted_ptr = Pointer_shift({ASL_PREFIX}ptr, {offset});",
    fmt"{return_type} value = {return_type}_from_Pointer({ASL_PREFIX}shifted_ptr);",
    "return value;",
    "}",
  ].join("\n")

proc setter_h(function_name: string, field_type: string): string =
  fmt"Pointer {function_name}(Pointer {ASL_PREFIX}ptr, {field_type} value);"

proc setter_c(function_name: string, field_type: string,
    offset: uint): string =
  @[
    fmt"Pointer {function_name}(Pointer {ASL_PREFIX}ptr, {field_type} value)",
    "{",
    fmt"Pointer {ASL_PREFIX}shifted_ptr = Pointer_shift({ASL_PREFIX}ptr, {offset});",
    fmt"Pointer _ = Pointer_write_{field_type}({ASL_PREFIX}shifted_ptr, value);",
    fmt"return {ASL_PREFIX}ptr;",
    "}",
  ].join("\n")

### C CODE GENERARTION UTILS END

type ResolvedStruct* = ref object of RootObj
  module_name: Token
  struct: Struct

proc new_resolved_struct*(module_name: Token, struct: Struct): ResolvedStruct =
  ResolvedStruct(module_name: module_name, struct: struct)

proc getter_h(module_name: Token, field: ArgumentDefinition): string =
  getter_h(field.native_type, fmt"{module_name}_get_{field.name}")

proc getter_c(module_name: Token,
    field: ArgumentDefinition, offset: uint): string =
  getter_c(field.native_type, fmt"{module_name}_get_{field.name}", offset)

proc setter_h(module_name: Token, field: ArgumentDefinition): string =
  setter_h(fmt"{module_name}_set_{field.name}", field.native_type)

proc setter_c(module_name: Token, field: ArgumentDefinition,
    offset: uint): string =
  setter_c(fmt"{module_name}_set_{field.name}", field.native_type, offset)

proc init_h(module_name: Token, fields: seq[ArgumentDefinition]): string =
  let args_str = fields.map_it($(it)).join(", ")
  fmt"Pointer {module_name}_init({args_str});"

proc init_c(module_name: Token, fields: seq[ArgumentDefinition],
    byte_size: uint): string =
  let fields_def = fields.map_it($(it)).join(", ")
  let setter_calls = fields.map_it(fmt"{ASL_PREFIX}ptr = {module_name}_set_{it.name}({ASL_PREFIX}ptr, {it.name});").join("\n")

  let code = @[
    fmt"Pointer {module_name}_init({fields_def})",
    "{",
    fmt"Pointer {ASL_PREFIX}ptr = System_allocate({byte_size});",
    setter_calls,
    fmt"return {ASL_PREFIX}ptr;",
    "}",
  ]
  return code.join("\n")

proc free_h(module_name: Token): string =
  fmt"U64 {module_name}_free(Pointer);"

proc free_c(module_name: Token): string =
  @[
    fmt"U64 {module_name}_free(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"return System_free({ASL_PREFIX}ptr);",
    "}",
  ].join("\n")
### C CODE GENERARTION UTILS END

proc h*(resolved_struct: ResolvedStruct): string =
  let
    module_name = resolved_struct.module_name
    fields = resolved_struct.struct.fields.values.to_seq

  var headers: seq[string]
  for field in fields:
    headers.add(getter_h(module_name, field))
    headers.add(setter_h(module_name, field))

  headers.add(init_h(module_name, fields))
  headers.add(free_h(module_name))

  return headers.join("\n")

proc c*(resolved_struct: ResolvedStruct): string =
  let
    module_name = resolved_struct.module_name
    fields = resolved_struct.struct.fields.values.to_seq

  var
    offset: uint = 0
    code: seq[string]

  for field in fields:
    code.add(getter_c(module_name, field, offset))
    code.add(setter_c(module_name, field, offset))
    offset += field.byte_size

  code.add(init_c(module_name, fields, offset))
  code.add(free_c(module_name))
  return code.join("\n\n")
