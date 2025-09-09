import strutils, strformat, sequtils, tables, sets

import "../blocks"

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

type ResolvedStruct* = ref object of RootObj
  module: UserModule
  struct: Struct
  generic_impls: Table[string, HashSet[string]]

proc new_resolved_struct*(module: UserModule, struct: Struct): ResolvedStruct =
  ResolvedStruct(module: module, struct: struct)

proc new_resolved_struct*(module: UserModule, struct: Struct,
    generic_impls: Table[string, HashSet[string]]): ResolvedStruct =
  ResolvedStruct(module: module, struct: struct,
      generic_impls: generic_impls)

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
  let args_str = fields.map_it($(it.native_type)).join(", ")
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
    module = resolved_struct.module
    module_name = module.name
    fields = resolved_struct.struct.fields
    generic_impls = resolved_struct.generic_impls

  var headers: seq[string]
  for field in fields:
    headers.add(getter_h(module_name, field))
    headers.add(setter_h(module_name, field))

  headers.add(init_h(module_name, fields))
  headers.add(free_h(module_name))

  for generic in module.generics:
    # in case of generic types there will be concrete impls
    if $(generic.name) in generic_impls:
      # generic id
      headers.add(fmt"Pointer {module_name}_{generic.name}_get_{ASL_UNION_ID}(Pointer);")
      headers.add(fmt"Pointer {module_name}_{generic.name}_set_{ASL_UNION_ID}(Pointer, U8);")
      for concrete in generic_impls[$(generic.name)]:
        let concrete_field = new_argument_definition(concrete, "temp_arg_name")
        # generic init
        headers.add(fmt"Pointer {module_name}_{generic.name}_{concrete}_init({concrete_field.native_type});")
      let generic_constraints = module.generics[module.generic_map[$(
          generic.name)]].constraints
      for constraint in generic_constraints:
        let args_str = constraint.arg_def_list.map_it(it.native_type).join(", ")
        let return_arg = new_argument_definition($(constraint.return_type), "temp_arg_name")
        headers.add(fmt"{return_arg.native_type} {module_name}_{generic.name}_{constraint.name}({args_str});")

  return headers.join("\n")

proc c*(resolved_struct: ResolvedStruct): string =
  let
    module = resolved_struct.module
    module_name = module.name
    fields = resolved_struct.struct.fields
    generic_impls = resolved_struct.generic_impls

  var
    offset: uint = 0
    impl: seq[string]

  for field in fields:
    impl.add(getter_c(module_name, field, offset))
    impl.add(setter_c(module_name, field, offset))
    offset += field.byte_size

  for generic in module.generics:
    # in case of generic types there will be concrete impls
    if $(generic.name) in generic_impls:
      # generic id
      impl.add([
        fmt"Pointer {module_name}_{generic.name}_get_{ASL_UNION_ID}(Pointer ptr)",
        "{",
        fmt"return U8_from_Pointer(ptr);",
        "}",
      ])

      impl.add(@[
        fmt"Pointer {module_name}_{generic.name}_set_{ASL_UNION_ID}(Pointer ptr, U8 id)",
        "{",
        fmt"Pointer _ = Pointer_write_U8(ptr, id);",
        fmt"return ptr;",
        "}",
      ])
      for (gen_index, concrete) in generic_impls[$(generic.name)].to_seq.pairs:
        let concrete_field = new_argument_definition(concrete, "temp_arg_name")
        # generic init
        impl.add(@[
          fmt"Pointer {module_name}_{generic.name}_{concrete}_init({concrete_field.native_type} value)",
          "{",
          fmt"Pointer ptr = System_allocate(1 + {concrete_field.byte_size});",
            fmt"Pointer _1 = {module_name}_{generic.name}_set_{ASL_UNION_ID}(ptr, {gen_index});",
            fmt"Pointer _2 = {module_name}_{generic.name}_{concrete}_set(ptr, value);",
            fmt"return ptr;",
          "}"
        ])
      let generic_constraints = module.generics[module.generic_map[$(
          generic.name)]].constraints
      for constraint in generic_constraints:
        var args: seq[string]
        var generic_args: seq[ArgumentDefinition]
        for arg_def in constraint.arg_def_list:
          if $(arg_def.typ) == $(generic.name):
            args.add(arg_def.native_type)
            generic_args.add(arg_def)
          else:
            args.add(arg_def.native_type)

        if generic_args.len == 0:
          if $(constraint.return_type) != $(generic.name):
            echo "WARNING: it should never occur"
          else:
            discard
        else:
          discard
        let args_str = args.join(", ")
        let return_arg = new_argument_definition($(constraint.return_type), "temp_arg_name")
        impl.add(fmt"{return_arg.native_type} {module_name}_{generic.name}_{constraint.name}({args_str});")

  impl.add(init_c(module_name, fields, offset))
  impl.add(free_c(module_name))
  return impl.join("\n\n")
