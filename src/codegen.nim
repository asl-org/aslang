import strformat, strutils, tables, sequtils

import resolver


proc module_data_byte_size(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"U64 {prefix}_byte_size(U64 items);"],
    @[
      fmt"U64 {prefix}_byte_size(U64 items)",
      "{",
      "return Pointer_byte_size(items);",
      "}"
    ]
  )

proc module_data_read(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"Pointer {prefix}_read(Pointer ptr, U64 offset);"],
    @[
      fmt"Pointer {prefix}_read(Pointer ptr, U64 offset)",
      "{",
      "return Pointer_read(ptr, offset);",
      "}"
    ]
  )

proc module_data_write(prefix: string): (seq[string], seq[string]) =
  (
    @[fmt"Pointer {prefix}_write(Pointer value, Pointer ptr, U64 offset);"],
    @[
      fmt"Pointer {prefix}_write(Pointer value, Pointer ptr, U64 offset)",
      "{",
      "return Pointer_write(value, ptr, offset);",
      "}"
    ]
  )

proc module_data_ops(prefix: string): (seq[string], seq[string]) =
  let (byte_size_def, byte_size_impl) = module_data_byte_size(prefix)
  let (read_def, read_impl) = module_data_read(prefix)
  let (write_def, write_impl) = module_data_write(prefix)
  let defs = byte_size_def & read_def & write_def
  let impl = byte_size_impl & read_impl & write_impl
  return (defs, impl)

proc generic_function(
  prefix: string,
  name: string,
  args: seq[(string, string, string, bool)],
  returns: (string, bool),
  impls: seq[(string, string)]): (seq[string], seq[string]) =
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

  for id, (impl_name, impl_type) in impls.pairs:
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
    TypedModule]): (seq[string], seq[string]) =
  var impl_name_types: seq[(string, string)]
  for impl in impls:
    let impl_type =
      case impl.kind:
      of TMK_NATIVE: impl.name.asl
      of TMK_USER: "Pointer"
    impl_name_types.add((impl.name.asl, impl_type))

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

proc struct_init(prefix: string, args: seq[(string, string)]): (seq[string],
    seq[string]) =
  # var prefix = "Error"
  # var args = @[("S32", "code"), ("String", "message")]

  var c_code: seq[string]
  var c_defs: seq[string]
  var arg_def_str = args.map_it(fmt"{it[0]} {it[1]}").join(", ")
  c_defs.add(fmt"Pointer {prefix}_default({arg_def_str});")
  c_code.add(fmt"Pointer {prefix}_default({arg_def_str})")
  c_code.add("{")

  var offset_expr = "0";
  for (arg_type, arg_name) in args:
    c_code.add(fmt"U64 __asl_{arg_name}_bytes = {arg_type}_byte_size(1);")
    c_code.add(fmt"U64 __asl_{arg_name}_offset = {offset_expr};")
    offset_expr = fmt"__asl_{arg_name}_offset + __asl_{arg_name}_bytes"

  c_code.add(fmt"U64 __asl_bytes = {offset_expr};")
  c_code.add(fmt"Pointer __asl_ptr = System_allocate(__asl_bytes);")

  for (arg_type, arg_name) in args:
    c_code.add(fmt"__asl_ptr = {arg_type}_write({arg_name}, __asl_ptr, __asl_{arg_name}_offset);")

  c_code.add("return __asl_ptr;")
  c_code.add("}\n")
  return (c_defs, c_code)

proc union_init(prefix: string, id: uint64, args: seq[(string, string)]): (seq[
    string], seq[string]) =
  # var prefix = "Error"
  # var args = @[("S32", "code"), ("String", "message")]

  var c_code: seq[string]
  var c_defs: seq[string]
  var arg_def_str = args.map_it(fmt"{it[0]} {it[1]}").join(", ")
  c_defs.add(fmt"Pointer {prefix}_default({arg_def_str});")
  c_code.add(fmt"Pointer {prefix}_default({arg_def_str})")
  c_code.add("{")

  var offset_expr = "0";

  # id expression
  c_code.add(fmt"U64 __asl_struct_id_bytes = U64_byte_size(1);")
  c_code.add(fmt"U64 __asl_struct_id_offset = {offset_expr};")
  offset_expr = fmt"__asl_struct_id_offset + __asl_struct_id_bytes"

  # struct field expression
  for (arg_type, arg_name) in args:
    c_code.add(fmt"U64 __asl_{arg_name}_bytes = {arg_type}_byte_size(1);")
    c_code.add(fmt"U64 __asl_{arg_name}_offset = {offset_expr};")
    offset_expr = fmt"__asl_{arg_name}_offset + __asl_{arg_name}_bytes"

  c_code.add(fmt"U64 __asl_bytes = {offset_expr};")
  c_code.add(fmt"Pointer __asl_ptr = System_allocate(__asl_bytes);")

  # id value setter
  c_code.add(fmt"__asl_ptr = U64_write({id}, __asl_ptr, __asl_struct_id_offset);")
  # struct field value setter
  for (arg_type, arg_name) in args:
    c_code.add(fmt"__asl_ptr = {arg_type}_write({arg_name}, __asl_ptr, __asl_{arg_name}_offset);")

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

proc generate(struct: ResolvedStruct, module: string): (seq[string], seq[string]) =
  var args: seq[(string, string)]
  for field in struct.fields:
    args.add((field.c_type, field.c_name))
  struct_init(module, args)

proc generate(struct: ResolvedStruct, module: string, id: uint64): (seq[string],
    seq[string]) =
  var args: seq[(string, string)]
  for field in struct.fields:
    args.add((field.c_type, field.c_name))
  let prefix =
    case struct.kind:
    of RSK_DEFAULT: module
    of RSK_NAMED: fmt"{module}_{struct.name.asl}"
  union_init(prefix, id, args)

proc generate(module: ResolvedUserModuleDefinition, generic_impls: seq[seq[
    TypedModule]]): (seq[string], seq[string]) =
  var c_code: seq[string]
  var c_defs: seq[string]
  for index, generic in module.generics.pairs:
    let (c_def, c_impl) = generate(module.name.asl, generic, generic_impls[index])
    c_defs.add(c_def)
    c_code.add(c_impl)

  if module.structs.len > 1:
    # data ops
    let(c_data_ops_def, c_data_ops_impl) = module_data_ops(module.name.asl)
    c_defs.add(c_data_ops_def)
    c_code.add(c_data_ops_impl)

    # union id
    let (c_id_def, c_id_impl) = union_id(module.name.asl)
    c_defs.add(c_id_def)
    c_code.add(c_id_impl)

    # union init generation
    for id, struct in module.structs:
      let (c_init_def, c_init_impl) = struct.generate(module.name.asl, id.uint64)
      c_defs.add(c_init_def)
      c_code.add(c_init_impl)
  else:
    let(c_data_ops_def, c_data_ops_impl) = module_data_ops(module.name.asl)
    c_defs.add(c_data_ops_def)
    c_code.add(c_data_ops_impl)
    # struct generation
    for struct in module.structs:
      let (c_init_def, c_init_impl) = struct.generate(module.name.asl)
      c_defs.add(c_init_def)
      c_code.add(c_init_impl)
  return (c_defs, c_code)

proc generate(file: ResolvedFileDefinition, generic_impls: Table[
    TypedUserModule, seq[seq[TypedModule]]]): (seq[string], seq[string]) =
  var c_code: seq[string]
  var c_defs: seq[string]
  for module in file.user_modules:
    let generics = generic_impls.get_or_default(module.module, new_seq[seq[
        TypedModule]]())
    let (c_def, c_impl) = module.generate(generics)
    c_defs.add(c_def)
    c_code.add(c_impl)
  return (c_defs, c_code)

proc generate*(file: ResolvedFile): string =
  let (defs, code) = file.def.generate(file.generic_impls)
  let c_code = @[defs.join("\n"), code.join("\n")].join("\n\n")
  let c_file = @[
    "#include \"runtime.h\"",
    c_code,
    "\n",
    "int main(int argc, char** argv) {",
    "return start(argc);",
    "}"
  ].join("\n")
  return c_file
