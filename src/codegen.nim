import strformat, strutils, tables, sequtils, results, options

import resolver

# This are predefined functions that are attached to a module
# in the type checking phaze of compilation. But we only need
# definitions of function so impl has to be auto generated in
# the code generation layer and all the internal_functions_map
# functions must be implemented here.
proc module_internal_byte_size(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"U64 {prefix}_byte_size(U64 items);"],
    @[
      fmt"U64 {prefix}_byte_size(U64 items)",
      "{",
      "return Pointer_byte_size(items);",
      "}"
    ]
  )

proc module_internal_read(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"Pointer {prefix}_read(Pointer ptr, U64 offset);"],
    @[
      fmt"Pointer {prefix}_read(Pointer ptr, U64 offset)",
      "{",
      "return Pointer_read(ptr, offset);",
      "}"
    ]
  )

proc module_internal_write(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"Pointer {prefix}_write(Pointer value, Pointer ptr, U64 offset);"],
    @[
      fmt"Pointer {prefix}_write(Pointer value, Pointer ptr, U64 offset)",
      "{",
      "return Pointer_write(value, ptr, offset);",
      "}"
    ]
  )

proc module_internal_function_impls(prefix: string): (seq[string], seq[string]) =
  let (byte_size_def, byte_size_impl) = module_internal_byte_size(prefix)
  let (read_def, read_impl) = module_internal_read(prefix)
  let (write_def, write_impl) = module_internal_write(prefix)
  let defs = fmt"// {prefix} internal function definitions" & byte_size_def &
      read_def & write_def & ""
  let impl = fmt"// {prefix} internal function implementations" &
      byte_size_impl & read_impl & write_impl & ""
  return (defs, impl)

proc generic_function(
  prefix: string,
  name: string,
  args: seq[(string, string, string, bool)],
  returns: (string, bool),
  impls: seq[(uint64, string, string)]): (seq[string], seq[string]) =
  # prefix: fmt"{module}_{generic}"
  var c_code: seq[string]
  var c_defs: seq[string]

  var generic_args: seq[string]
  var arg_def_list: seq[string]
  var arg_names: seq[string]
  for (impl_name, impl_type, arg_name, is_generic) in args:
    arg_def_list.add(fmt"{impl_type} {arg_name}")
    if is_generic:
      generic_args.add(arg_name)
      arg_names.add(fmt"__asl_{arg_name}")
    else:
      arg_names.add(arg_name)

  let (return_type, returns_genreic) = returns
  let args_def_str = arg_def_list.join(", ")
  let arg_names_str = arg_names.join(", ")

  # function definition
  c_defs.add(fmt"{return_type} {prefix}_{name}(U64 __asl_impl_id, {args_def_str});")
  # inject extra generic argument to figure out impl id
  c_code.add(fmt"{return_type} {prefix}_{name}(U64 __asl_impl_id, {args_def_str})")
  c_code.add("{")
  c_code.add(fmt"switch(__asl_impl_id)")
  c_code.add("{")

  for (id, impl_name, impl_type) in impls:
    c_code.add(fmt"case {id}: // {impl_name}")
    c_code.add("{")

    for arg_name in generic_args:
      c_code.add(fmt"{impl_type} __asl_{arg_name} = {impl_type}_read({arg_name}, 0); // unbox {impl_name}")

    if returns_genreic:
      c_code.add(fmt"{impl_type} __asl_result = {impl_name}_{name}({arg_names_str}); // call {impl_name}")
      c_code.add(fmt"return System_box_{impl_type}(__asl_result); // box {impl_name}")
    else:
      c_code.add(fmt"return {impl_name}_{name}({arg_names_str}); // call {impl_name}")

    c_code.add("}") # case end
  c_code.add("}") # switch end
  c_code.add("UNREACHABLE();") # non-void return warning solution
  c_code.add("}\n") # function end

  return (c_defs, c_code)

proc generate(prefix: string, generic: ResolvedGeneric, impls: seq[
    ResolvedModuleDefinition]): (seq[string], seq[string]) =
  var impl_name_types: seq[(uint64, string, string)]
  for impl in impls:
    impl_name_types.add((impl.id, impl.c_name, impl.c_type))

  var c_code: seq[string]
  var c_defs: seq[string]
  let generic_prefix = fmt"{prefix}_{generic.name.asl}"
  for def in generic.defs:
    var arg_name_types: seq[(string, string, string, bool)]
    for arg in def.args:
      arg_name_types.add((
        arg.asl_type,
        arg.c_type,
        arg.c_name,
        arg.module_ref.kind == RMRK_GENERIC
      ))

    let return_impl = (def.returns.c_type, def.returns.kind == RMRK_GENERIC)
    let (c_def, c_impl) = generic_function(
        generic_prefix,
        def.name.asl,
        arg_name_types,
        return_impl,
        impl_name_types
      )
    c_defs.add(c_def)
    c_code.add(c_impl)
  return (c_defs, c_code)

proc field_bytes(prefix, arg_type, arg_name: string): (seq[string], seq[string]) =
  let c_defs = @[fmt"U64 {prefix}_{arg_name}_bytes();"]
  let c_code = @[
    fmt"U64 {prefix}_{arg_name}_bytes()",
    "{",
    fmt"return {arg_type}_byte_size(1);",
    "}"
  ]
  return (c_defs, c_code)

proc struct_field_bytes(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @[fmt"// {prefix} field bytes definitions"]
  var c_code = @[fmt"// {prefix} field bytes implementations"]
  for index, (arg_type, arg_name) in args.pairs:
    let (c_bytes_def, c_bytes_code) = field_bytes(prefix, arg_type, arg_name)
    c_defs.add(c_bytes_def)
    c_code.add(c_bytes_code)
  return (c_defs, c_code)

proc field_offset(prefix, arg_type, arg_name: string, last_arg: Option[
    string], default_offset: string = "0"): (seq[string], seq[string]) =
  let c_defs = @[fmt"U64 {prefix}_{arg_name}_offset();"]

  let offset =
    if last_arg.is_none: default_offset
    else: fmt"{prefix}_{last_arg.get}_offset() + {prefix}_{last_arg.get}_bytes()"

  let c_code = @[
    fmt"U64 {prefix}_{arg_name}_offset()",
    "{",
    fmt"return {offset};",
    "}",
  ]

  return (c_defs, c_code)

proc struct_field_offsets(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @[fmt"// {prefix} field offset definitions"]
  var c_code = @[fmt"// {prefix} field offset implementations"]
  for index, (arg_type, arg_name) in args.pairs:
    let last_arg = if index == 0: none(string) else: some(args[index - 1][1])
    let (c_offset_def, c_offset_code) = field_offset(prefix, arg_type, arg_name, last_arg)
    c_defs.add(c_offset_def)
    c_code.add(c_offset_code)
  return (c_defs, c_code)

proc field_getter(prefix, arg_type, arg_name: string): (seq[string], seq[string]) =
  var c_defs: seq[string]
  c_defs.add(fmt"U64 {prefix}_get_{arg_name}(Pointer __asl_ptr);")

  var c_code: seq[string]
  c_code.add(fmt"U64 {prefix}_get_{arg_name}(Pointer __asl_ptr)")
  c_code.add("{")
  c_code.add(fmt"return {arg_type}_read(__asl_ptr, {prefix}_{arg_name}_offset());")
  c_code.add("}")

  return (c_defs, c_code)

proc struct_field_getters(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @["//struct field getter definitions"]
  var c_code = @["//struct field getter implementations"]
  for index, (arg_type, arg_name) in args.pairs:
    let (c_getter_def, c_getter_code) = field_getter(prefix, arg_type, arg_name)
    c_defs.add(c_getter_def)
    c_code.add(c_getter_code)

  return (c_defs, c_code)

proc field_setter(prefix, arg_type, arg_name: string): (seq[string], seq[string]) =
  var c_defs: seq[string]
  c_defs.add(fmt"U64 {prefix}_set_{arg_name}(Pointer __asl_ptr, {arg_type} {arg_name});")

  var c_code: seq[string]
  c_code.add(fmt"U64 {prefix}_set_{arg_name}(Pointer __asl_ptr, {arg_type} {arg_name})")
  c_code.add("{")
  c_code.add(fmt"return {arg_type}_write({arg_name}, __asl_ptr, {prefix}_{arg_name}_offset());")
  c_code.add("}")

  return (c_defs, c_code)

proc struct_field_setters(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @["//struct field setter definitions"]
  var c_code = @["//struct field setter implementations"]
  for index, (arg_type, arg_name) in args.pairs:
    let (c_setter_def, c_setter_code) = field_setter(prefix, arg_type, arg_name)
    c_defs.add(c_setter_def)
    c_code.add(c_setter_code)

  return (c_defs, c_code)

proc struct_fields_init(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  # var prefix = "Error"
  # var args = @[("S32", "code"), ("String", "message")]

  var c_code: seq[string]
  var c_defs: seq[string]
  var arg_def_str = args.map_it(fmt"{it[0]} {it[1]}").join(", ")

  c_defs.add(fmt"Pointer {prefix}_default_init({arg_def_str});")
  c_code.add(fmt"Pointer {prefix}_default_init({arg_def_str})")
  c_code.add("{")

  let (_, last_arg_name) = args[^1]
  c_code.add(fmt"U64 __asl_bytes = {prefix}_{last_arg_name}_offset() + {prefix}_{last_arg_name}_bytes();")
  c_code.add(fmt"Pointer __asl_ptr = System_allocate(__asl_bytes);")

  for (arg_type, arg_name) in args:
    c_code.add(fmt"__asl_ptr = {prefix}_set_{arg_name}(__asl_ptr, {arg_name});")

  c_code.add("return __asl_ptr;")
  c_code.add("}\n")
  return (c_defs, c_code)

proc generate_struct(module: string, args: seq[(string, string)]): (seq[string],
    seq[string]) =
  var c_defs: seq[string]
  var c_code: seq[string]

  let (c_bytes_def, c_bytes_code) = struct_field_bytes(module, args)
  c_defs.add(c_bytes_def); c_defs.add("")
  c_code.add(c_bytes_code); c_code.add("")

  let (c_offset_def, c_offset_code) = struct_field_offsets(module, args)
  c_defs.add(c_offset_def); c_defs.add("")
  c_code.add(c_offset_code); c_code.add("")

  let (c_getter_def, c_getter_code) = struct_field_getters(module, args)
  c_defs.add(c_getter_def); c_defs.add("")
  c_code.add(c_getter_code); c_code.add("")

  let (c_setter_def, c_setter_code) = struct_field_setters(module, args)
  c_defs.add(c_setter_def); c_defs.add("")
  c_code.add(c_setter_code); c_code.add("")

  let (c_init_def, c_init_code) = struct_fields_init(module, args)
  c_defs.add(c_init_def); c_defs.add("")
  c_code.add(c_init_code); c_code.add("")

  return (c_defs, c_code)

proc union_field_bytes(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @[fmt"// {prefix} field bytes definitions"]
  var c_code = @[fmt"// {prefix} field bytes implementations"]
  for (arg_type, arg_name) in args:
    let (c_bytes_def, c_bytes_code) = field_bytes(prefix, arg_type, arg_name)
    c_defs.add(c_bytes_def)
    c_code.add(c_bytes_code)
  (c_defs, c_code)

proc union_field_offsets(prefix: string, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  var c_defs = @[fmt"// {prefix} field offset definitions"]
  var c_code = @[fmt"// {prefix} field offset implementations"]
  for index, (arg_type, arg_name) in args.pairs:
    let last_arg = if index == 0: none(string) else: some(args[index - 1][1])
    # default offset is "8" because of union id field prepended before fields
    let (c_offset_def, c_offset_code) = field_offset(prefix, arg_type, arg_name,
        last_arg, "8")
    c_defs.add(c_offset_def)
    c_code.add(c_offset_code)
  return (c_defs, c_code)

proc union_fields_init(prefix: string, id: uint64, args: seq[(string,
    string)]): (seq[string], seq[string]) =
  # var prefix = "Error"
  # var args = @[("S32", "code"), ("String", "message")]

  var c_code: seq[string]
  var c_defs: seq[string]
  var arg_def_str = args.map_it(fmt"{it[0]} {it[1]}").join(", ")
  c_defs.add(fmt"Pointer {prefix}_default_init({arg_def_str});")
  c_code.add(fmt"Pointer {prefix}_default_init({arg_def_str})")
  c_code.add("{")

  # id expression
  c_code.add(fmt"U64 __asl_struct_id_bytes = U64_byte_size(1);")
  c_code.add(fmt"U64 __asl_struct_id_offset = 0;")

  if args.len > 0:
    let last_arg_name = args[^1][1]
    c_code.add(fmt"U64 __asl_bytes = {prefix}_{last_arg_name}_offset() + {prefix}_{last_arg_name}_bytes();")
  else:
    c_code.add(fmt"U64 __asl_bytes = 8;")

  c_code.add(fmt"Pointer __asl_ptr = System_allocate(__asl_bytes);")

  # id value setter
  c_code.add(fmt"__asl_ptr = U64_write({id}, __asl_ptr, __asl_struct_id_offset);")
  # struct field value setter
  for (arg_type, arg_name) in args:
    c_code.add(fmt"__asl_ptr = {arg_type}_write({arg_name}, __asl_ptr, {prefix}_{arg_name}_offset());")

  c_code.add("return __asl_ptr;")
  c_code.add("}\n")
  return (c_defs, c_code)

proc union_id(prefix: string): (seq[string], seq[string]) =
  var c_defs = @[fmt"U64 {prefix}_id(Pointer __asl_ptr);"]
  var c_code = @[
    fmt"U64 {prefix}_id(Pointer __asl_ptr)",
    "{",
    "return U64_read(__asl_ptr, 0);",
    "}\n"
  ]
  return (c_defs, c_code)

proc generate_union(prefix: string, id: uint64, args: seq[(string, string)]): (
    seq[string], seq[string]) =
  var c_defs: seq[string]
  var c_code: seq[string]
  let (c_bytes_def, c_bytes_code) = union_field_bytes(prefix, args)
  c_defs.add(c_bytes_def)
  c_code.add(c_bytes_code)

  let (c_offset_def, c_offset_code) = union_field_offsets(prefix, args)
  c_defs.add(c_offset_def)
  c_code.add(c_offset_code)

  let (c_init_def, c_init_code) = union_fields_init(prefix, id, args)
  c_defs.add(c_init_def)
  c_code.add(c_init_code)

  return (c_defs, c_code)

proc generate(module: ResolvedUserModuleDefinition, generic_impls: seq[seq[
    ResolvedModuleDefinition]]): (seq[string], seq[string]) =
  var c_code: seq[string]
  var c_defs: seq[string]
  for index, generic in module.generics.pairs:
    let (c_def, c_impl) = generate(module.name.asl, generic, generic_impls[index])
    c_defs.add(c_def)
    c_code.add(c_impl)

  # data ops
  let(c_data_ops_def, c_data_ops_impl) = module_internal_function_impls(
      module.name.asl)
  c_defs.add(c_data_ops_def)
  c_code.add(c_data_ops_impl)

  if module.structs.len > 1:
    # union id
    let (c_id_def, c_id_impl) = union_id(module.name.asl)
    c_defs.add(c_id_def)
    c_code.add(c_id_impl)

    # union init generation
    for id, struct in module.structs:
      let prefix = fmt"{module.name.asl}_{struct.c_name}"
      let (c_init_def, c_init_impl) = generate_union(prefix, id.uint64, struct.c_args)
      c_defs.add(c_init_def)
      c_code.add(c_init_impl)
  else:
    # struct generation
    for struct in module.structs:
      let (c_init_def, c_init_impl) = generate_struct(module.name.asl, struct.c_args)
      c_defs.add(c_init_def)
      c_code.add(c_init_impl)
  return (c_defs, c_code)

proc generate(file: ResolvedFileDefinition, generic_impls: Table[
    TypedUserModule, seq[seq[ResolvedModuleDefinition]]]): (seq[string], seq[string]) =
  var c_code: seq[string]
  var c_defs: seq[string]
  for module in file.user_modules:
    let generics = generic_impls.get_or_default(module.module, new_seq[seq[
        ResolvedModuleDefinition]]())
    let (c_def, c_impl) = module.generate(generics)
    c_defs.add(c_def)
    c_code.add(c_impl)
  return (c_defs, c_code)

proc generate*(file: ResolvedFile): Result[string, string] =
  let generic_impls = ? file.generic_impls
  let (defs, code) = file.def.generate(generic_impls)
  let c_code = @[defs.join("\n"), code.join("\n")].join("\n\n")
  let c_file = @[
    "#include \"runtime.h\"\n",
    c_code,
    "\n",
    "int main(int argc, char** argv) {",
    "return start(argc);",
    "}"
  ].join("\n")
  return ok(c_file)
