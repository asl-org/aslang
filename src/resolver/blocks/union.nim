import tables, strutils, strformat, sequtils, sets

import function_ref
import struct

const ASL_PREFIX = "__asl__"
const ASL_UNION_ID = "__asl_union_id__"

### C CODE GENERARTION UTILS START

proc getter_h(return_type: string, function_name: string): string =
  fmt"{return_type} {function_name}(Pointer);"

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
  fmt"Pointer {function_name}(Pointer, {field_type});"

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
  module: UserModule
  union: Union
  generic_impls: Table[string, HashSet[string]]

proc new_resolved_union*(module: UserModule, union: Union): ResolvedUnion =
  ResolvedUnion(module: module, union: union)

proc new_resolved_union*(module: UserModule, union: Union,
    generic_impls: Table[string, HashSet[string]]): ResolvedUnion =
  ResolvedUnion(module: module, union: union,
      generic_impls: generic_impls)

proc getter_h(module_name: string, union_name: string,
    field: ArgumentDefinition): string =
  getter_h(field.native_type, fmt"{module_name}_{union_name}_get_{field.name}")

proc getter_c(module_name: string, union_name: string,
    field: ArgumentDefinition, offset: uint): string =
  getter_c(
    field.native_type,
    fmt"{module_name}_{union_name}_get_{field.name}",
    offset
  )

proc setter_h(module_name: string, union_name: string,
    field: ArgumentDefinition): string =
  setter_h(fmt"{module_name}_{union_name}_set_{field.name}",
      field.native_type)

proc setter_c(module_name: string, union_name: string,
    field: ArgumentDefinition, offset: uint): string =
  setter_c(fmt"{module_name}_{union_name}_set_{field.name}",
      field.native_type, offset)

proc init_h(module_name: string, union_field_def: UnionFieldDefinition): string =
  let union_name = union_field_def.name
  let fields_def = union_field_def.fields.map_it(it.native_type).join(", ")
  fmt"Pointer {module_name}_{union_name}_init({fields_def});"

proc init_c(module_name: string, union_field_def: UnionFieldDefinition,
    id: int, byte_size: uint): string =
  let union_name = union_field_def.name
  let fields_def = union_field_def.fields.map_it(it.c).join(", ")
  let id_setter = fmt"{ASL_PREFIX}ptr = {module_name}_set_{ASL_UNION_ID}({ASL_PREFIX}ptr, {id});"
  let setter_calls = union_field_def.fields.map_it(
    fmt"{ASL_PREFIX}ptr = {module_name}_{union_name}_set_{it.name}({ASL_PREFIX}ptr, {it.name});").join("\n")

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
  fmt"U64 {module_name}_{union_name}_free(Pointer);"

proc free_c(module_name: string, union_name: string): string =
  @[
    fmt"U64 {module_name}_{union_name}_free(Pointer {ASL_PREFIX}ptr)",
    "{",
    fmt"return System_free({ASL_PREFIX}ptr);",
    "}",
  ].join("\n")

proc id_h(module_name: string): string =
  @[
    fmt"U8 {module_name}_get_{ASL_UNION_ID}(Pointer);",
    fmt"Pointer {module_name}_set_{ASL_UNION_ID}(Pointer, U8);",
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
  let module = resolved_union.module
  let generic_impls = resolved_union.generic_impls
  let module_name = $(module.name)
  var headers = @[id_h(module_name)]
  let union = resolved_union.union
  for union_field_def in union.fields:
    let union_name = $(union_field_def.name)
    for field in union_field_def.fields:
      headers.add(getter_h(module_name, union_name, field))
      headers.add(setter_h(module_name, union_name, field))

      # in case of generic types there will be concrete impls
      if $(field.typ) in generic_impls:
        # generic id
        # headers.add(fmt"Pointer {module_name}_{field.typ}_get_{ASL_UNION_ID}(Pointer);")
        headers.add(fmt"Pointer {module_name}_{field.typ}_set_{ASL_UNION_ID}(Pointer, U8);")
        for concrete in generic_impls[$(field.typ)]:
          let concrete_field = new_argument_definition(concrete, $(field.name))
          # generic getters
          headers.add(fmt"{concrete_field.native_type} {module_name}_{field.typ}_{concrete}_get_{field.name}(Pointer);")
          # generic setters
          headers.add(fmt"Pointer {module_name}_{field.typ}_{concrete}_set_{field.name}(Pointer, {concrete_field.native_type});")
          # generic init
          headers.add(fmt"Pointer {module_name}_{field.typ}_{concrete}_init({concrete_field.native_type});")

        # generic free
        headers.add(fmt"U64 {module_name}_{field.typ}_free(Pointer);")

        let generic_constraints = module.generics[module.generic_map[$(
            field.typ)]].constraints
        for constraint in generic_constraints:
          let args_str = constraint.arg_def_list.map_it(it.native_type).join(", ")
          let return_arg = new_argument_definition($(constraint.return_type), "temp_arg_name")
          headers.add(fmt"{return_arg.native_type} {module_name}_{field.typ}_{constraint.name}({args_str});")

    headers.add(init_h(module_name, union_field_def))
    headers.add(free_h(module_name, union_name))
  headers.join("\n")

proc c*(resolved_union: ResolvedUnion): string =
  let module = resolved_union.module
  let module_name = $(module.name)
  let generic_impls = resolved_union.generic_impls
  let union = resolved_union.union
  var impl = @[id_c(module_name)]
  for (id, union_field_def) in union.fields.pairs:
    # offset: 0 is for `id` (1 byte) field in unions
    var offset: uint = 1
    let union_name = $(union_field_def.name)
    for field in union_field_def.fields:
      impl.add(getter_c(module_name, union_name, field, offset))
      impl.add(setter_c(module_name, union_name, field, offset))
      offset += field.byte_size()

      # in case of generic types there will be concrete impls
      if $(field.typ) in generic_impls:
        # generic id
        impl.add(@[
          fmt"U8 {module_name}_{field.typ}_get_{ASL_UNION_ID}(Pointer ptr)",
          "{",
          fmt"return U8_from_Pointer(ptr);",
          "}"
        ].join("\n"))
        impl.add(@[
          fmt"Pointer {module_name}_{field.typ}_set_{ASL_UNION_ID}(Pointer ptr, U8 id)",
          "{",
          fmt"Pointer _ = Pointer_write_U8(ptr, id);",
          fmt"return ptr;",
          "}"
        ].join("\n"))
        for (gen_index, concrete) in generic_impls[$(field.typ)].to_seq.pairs:
          let concrete_field = new_argument_definition(concrete, $(field.name))
          # generic getters
          impl.add(@[
            fmt"{concrete_field.native_type} {module_name}_{field.typ}_{concrete}_get_{field.name}(Pointer ptr)",
            "{",
            fmt"Pointer shifted_ptr = Pointer_shift(ptr, 1);",
            fmt"{concrete_field.native_type} value = {concrete_field.native_type}_from_Pointer(shifted_ptr);",
            "return value;",
            "}"
          ].join("\n"))
          # generic setters
          impl.add(@[
            fmt"Pointer {module_name}_{field.typ}_{concrete}_set_{field.name}(Pointer ptr, {concrete_field.native_type} value)",
            "{",
            fmt"Pointer shifted_ptr = Pointer_shift(ptr, 1);",
            fmt"Pointer _ = Pointer_write_{concrete_field.native_type}(shifted_ptr, value);",
            fmt"return ptr;",
            "}"
          ].join("\n"))
          # generic init
          impl.add(@[
            fmt"Pointer {module_name}_{field.typ}_{concrete}_init({concrete_field.native_type} value)",
            "{",
            fmt"Pointer ptr = System_allocate(1 + {concrete_field.byte_size});",
            fmt"Pointer _1 = {module_name}_{field.typ}_set_{ASL_UNION_ID}(ptr, {gen_index});",
            fmt"Pointer _2 = {module_name}_{field.typ}_{concrete}_set_{field.name}(ptr, value);",
            fmt"return ptr;",
            "}"
          ].join("\n"))

        # generic free
        impl.add(@[
          fmt"U64 {module_name}_{field.typ}_free(Pointer ptr)",
          "{",
          fmt"return System_free(ptr);",
          "}",
        ].join("\n"))

        let constraints = module.generics[module.generic_map[$(
              field.typ)]].constraints
        for constraint in constraints:
          let constraint_return_field = new_argument_definition($(
              constraint.return_type), fmt"{ASL_PREFIX}gen_ret_type")
          var generic_indices: seq[int]
          for index, arg_def in constraint.arg_def_list.pairs:
            if $(arg_def.typ) == $(field.typ):
              generic_indices.add(index)
          if generic_indices.len == 0:
            # The function accepts any generic type, it means that there was a
            # resolution error since function does not utilize generics.
            echo("ERROR: Generic Resolution is failing")

          var generic_code: seq[string]
          let args_str = constraint.arg_def_list.map_it(it.c).join(", ")
          generic_code.add(fmt"{constraint_return_field.native_type} {module_name}_{field.typ}_{constraint.name}({args_str})") # function
          generic_code.add("{") # switch case

          let gen_arg_name = constraint.arg_def_list[generic_indices[0]].name
          generic_code.add(fmt"switch({module_name}_{field.typ}_get_{ASL_UNION_ID}({gen_arg_name}))")
          generic_code.add("{")

          for (id_index, concrete) in generic_impls[$(field.typ)].to_seq.pairs:
            var case_code: seq[string]
            case_code.add(fmt"case {id_index}:")
            case_code.add("{")
            var concrete_args: seq[string]
            var concrete_arg_index: uint = 0
            for arg_index, arg_def in constraint.arg_def_list.pairs:
              if $(arg_def.typ) == $(field.typ):
                let arg_name = fmt"concrete_arg_{concrete_arg_index}"
                concrete_arg_index += 1

                let concrete_field = new_argument_definition($(concrete), arg_name)
                case_code.add(fmt"{concrete_field.native_type} {arg_name} = {module_name}_{field.typ}_{concrete}_get_{field.name}({arg_def.name});")
                concrete_args.add(arg_name)
              else:
                concrete_args.add($(field.name))
            let args_str = concrete_args.join(", ")
            if $(constraint.return_type) == $(field.typ):
              case_code.add(fmt"return {concrete}_{constraint.name}({args_str});")
            else:
              case_code.add(fmt"return {concrete}_{constraint.name}({args_str});")
            case_code.add("}")
            generic_code.add(case_code.join("\n"))
          generic_code.add("}") # switch case end
          generic_code.add("UNREACHABLE();")
          generic_code.add("}") # function end
          impl.add(generic_code.join("\n"))

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
