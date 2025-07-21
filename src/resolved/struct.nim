import tables, strutils, strformat, sequtils, options

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
  module: UserModule
  byte_size: uint
  field_offset: Table[string, uint]

proc getter_h(module_name: string, field: ArgumentDefinition): string =
  getter_h(field.native_type, fmt"{module_name}_get_{field.arg_name}")

proc getter_c(resolved_struct: ResolvedStruct,
    field: ArgumentDefinition): string =
  getter_c(
    field.native_type,
    fmt"{resolved_struct.module.name}_get_{field.arg_name}",
    resolved_struct.field_offset[$(field.arg_name)]
  )

proc setter_h(module_name: string, field: ArgumentDefinition): string =
  setter_h(fmt"{module_name}_set_{field.arg_name}", field.native_type)

proc setter_c(resolved_struct: ResolvedStruct,
    field: ArgumentDefinition): string =
  setter_c(
    fmt"{resolved_struct.module.name}_set_{field.arg_name}",
    field.native_type,
    resolved_struct.field_offset[$(field.arg_name)]
  )

proc init_h(module: UserModule): string =
  let struct = module.struct.get
  let args_str = struct.fields.values.to_seq.map_it($(it)).join(", ")
  fmt"Pointer {module.name}_init({args_str});"

proc init_c(resolved_struct: ResolvedStruct): string =
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

proc free_h(module: UserModule): string =
  fmt"U64 {module.name}_free(Pointer);"

proc free_c(resolved_struct: ResolvedStruct): string =
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
  var headers: seq[string]
  for field in struct.fields.values:
    headers.add(getter_h($(module.name), field))
    headers.add(setter_h($(module.name), field))
  headers.add(init_h(module))
  headers.add(free_h(module))
  return headers.join("\n")

proc c*(resolved_struct: ResolvedStruct): string =
  var code: seq[string]
  code.add(resolved_struct.init_c())
  for field in resolved_struct.module.struct.get.fields.values:
    code.add(resolved_struct.getter_c(field))
    code.add(resolved_struct.setter_c(field))
  code.add(resolved_struct.free_c())
  return code.join("\n\n")

proc new_resolved_struct*(module: UserModule, byte_size: uint,
    field_offset: Table[string, uint]): ResolvedStruct =
  ResolvedStruct(module: module, byte_size: byte_size,
      field_offset: field_offset)
