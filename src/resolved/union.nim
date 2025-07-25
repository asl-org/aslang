import tables, strutils, strformat, sequtils

import "../blocks"
import struct

const ASL_PREFIX = "__asl__"
const ASL_UNION_ID = "__asl_union_id__"

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

type ResolvedUnion* = ref object of RootObj
  module_name: Token
  union: Union

proc new_resolved_union*(module_name: Token, union: Union): ResolvedUnion =
  ResolvedUnion(module_name: module_name, union: union)

proc getter_h(module_name: string, union_name: string,
    field: ArgumentDefinition): string =
  getter_h(field.native_type, fmt"{module_name}_{union_name}_get_{field.arg_name}")

proc getter_c(module_name: string, union_name: string,
    field: ArgumentDefinition, offset: uint): string =
  getter_c(
    field.native_type,
    fmt"{module_name}_{union_name}_get_{field.arg_name}",
    offset
  )

proc setter_h(module_name: string, union_name: string,
    field: ArgumentDefinition): string =
  setter_h(fmt"{module_name}_{union_name}_set_{field.arg_name}",
      field.native_type)

proc setter_c(module_name: string, union_name: string,
    field: ArgumentDefinition, offset: uint): string =
  setter_c(fmt"{module_name}_{union_name}_set_{field.arg_name}",
      field.native_type, offset)

proc init_h(module_name: string, union_field_def: UnionFieldDefinition): string =
  let union_name = union_field_def.name
  let fields_def = union_field_def.fields.values.to_seq.map_it($(it)).join(", ")
  fmt"Pointer {module_name}_{union_name}_init({fields_def});"

proc init_c(module_name: string, union_field_def: UnionFieldDefinition,
    id: int, byte_size: uint): string =
  let union_name = union_field_def.name
  let fields_def = union_field_def.fields.values.to_seq.map_it($(it)).join(", ")
  let id_setter = fmt"{ASL_PREFIX}ptr = {module_name}_set_{ASL_UNION_ID}({ASL_PREFIX}ptr, {id});"
  let setter_calls = union_field_def.fields.values.to_seq.map_it(
    fmt"{ASL_PREFIX}ptr = {module_name}_{union_name}_set_{it.arg_name}({ASL_PREFIX}ptr, {it.arg_name});").join("\n")

  @[
    fmt"Pointer {module_name}_{union_name}_init({fields_def})",
    "{",
    fmt"Pointer {ASL_PREFIX}ptr = System_allocate({byte_size});",
    id_setter,
    setter_calls,
    fmt"return {ASL_PREFIX}ptr;",
    "}",
  ].join("\n")

proc free_h(module_name: string, union_name: string): string =
  fmt"U64 {module_name}_{union_name}_free(Pointer {ASL_PREFIX}ptr);"

proc free_c(module_name: string, union_name: string): string =
  @[
    fmt"U64 {module_name}_{union_name}_free(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"return System_free({ASL_PREFIX}ptr);",
    "}",
  ].join("\n")

proc id_h(module_name: string): string =
  @[
    fmt"U8 {module_name}_get_{ASL_UNION_ID}(Pointer ptr);",
    fmt"Pointer {module_name}_set_{ASL_UNION_ID}(Pointer ptr, U8 id);",
  ].join("\n")

proc id_c(module_name: string): string =
  let getter = @[
    fmt"U8 {module_name}_get_{ASL_UNION_ID}(Pointer ptr)",
    "{",
    fmt"return U8_from_Pointer(ptr);",
    "}"
  ].join("\n")

  let setter = @[
    fmt"Pointer {module_name}_set_{ASL_UNION_ID}(Pointer ptr, U8 id)",
    "{",
    fmt"Pointer _ = Pointer_write_U8(ptr, id);",
    fmt"return ptr;",
    "}"
  ].join("\n")

  @[getter, setter].join("\n")

proc h*(resolved_union: ResolvedUnion): string =
  let module_name = $(resolved_union.module_name)
  var headers = @[id_h(module_name)]
  let union = resolved_union.union
  for union_field_def in union.fields:
    let union_name = $(union_field_def.name)
    for field in union_field_def.fields.values:
      headers.add(getter_h(module_name, union_name, field))
      headers.add(setter_h(module_name, union_name, field))
    headers.add(init_h(module_name, union_field_def))
    headers.add(free_h(module_name, union_name))
  headers.join("\n")

proc c*(resolved_union: ResolvedUnion): string =
  let module_name = $(resolved_union.module_name)
  let union = resolved_union.union
  var impl = @[id_c(module_name)]
  for (id, union_field_def) in union.fields.pairs:
    # offset: 0 is for `id` (1 byte) field in unions
    var offset: uint = 1
    let union_name = $(union_field_def.name)
    for field in union_field_def.fields.values:
      impl.add(getter_c(module_name, union_name, field, offset))
      impl.add(setter_c(module_name, union_name, field, offset))
      offset += field.byte_size()
    impl.add(init_c(module_name, union_field_def, id, offset))
    impl.add(free_c(module_name, union_name))
  impl.join("\n")

type
  ResolvedUserModuleKind* = enum
    RUMK_STRUCT, RUMK_UNION
  ResolvedUserModule* = ref object of RootObj
    case kind*: ResolvedUserModuleKind
    of RUMK_STRUCT: struct*: ResolvedStruct
    of RUMK_UNION: union*: ResolvedUnion

proc new_resolved_user_module*(struct: ResolvedStruct): ResolvedUserModule =
  ResolvedUserModule(kind: RUMK_STRUCT, struct: struct)

proc new_resolved_user_module*(union: ResolvedUnion): ResolvedUserModule =
  ResolvedUserModule(kind: RUMK_UNION, union: union)

proc h*(resolved_user_module: ResolvedUserModule): string =
  case resolved_user_module.kind:
  of RUMK_STRUCT: resolved_user_module.struct.h
  of RUMK_UNION: resolved_user_module.union.h

proc c*(resolved_user_module: ResolvedUserModule): string =
  case resolved_user_module.kind:
  of RUMK_STRUCT: resolved_user_module.struct.c
  of RUMK_UNION: resolved_user_module.union.c
