import results, strformat, sets

import ../parser

proc make_extern(fn_name: string, c_name: string,
    args: seq[ArgumentDefinition], returns: ModuleRef,
    location: Location): Result[Function, string] =
  let name_id = new_identifier(fn_name)
  let maybe_def = new_function_definition(name_id, args, returns, location)
  if maybe_def.is_err: return err($maybe_def.error)
  ok(new_function(new_extern_function(maybe_def.get, c_name, expanded = true)))

proc build_self_ref(module_name: string,
    generics: seq[Generic]): Result[ModuleRef, string] =
  let module_id = new_identifier(module_name)
  if generics.len == 0:
    return ok(new_module_ref(module_id))
  var children: seq[ModuleRef]
  for generic in generics:
    children.add(new_module_ref(generic.name))
  let maybe_ref = new_module_ref(module_id, children)
  if maybe_ref.is_err: return err($maybe_ref.error)
  ok(maybe_ref.get)

proc expand_struct*(struct: Struct, prefix: string,
    module_name: string, generics: seq[Generic],
    existing_names: HashSet[(string, int)]): Result[seq[Function], string] =
  var functions: seq[Function]
  let location = struct.location
  let ptr_ref = new_module_ref("Pointer")
  let u64_ref = new_module_ref("U64")
  let self_ref = ? build_self_ref(module_name, generics)

  # field(Self self) and field(Self self, FieldType value) for each field
  for field in struct.fields:
    let field_name = field.name.asl
    let field_type = field.module_ref

    if (field_name, 1) notin existing_names:
      let self_arg = new_argument_definition(self_ref,
          new_identifier("self"))
      functions.add( ? make_extern(field_name, fmt"{prefix}_get_{field_name}",
          @[self_arg], field_type, location))

    if (field_name, 2) notin existing_names:
      let self_arg = new_argument_definition(self_ref,
          new_identifier("self"))
      let val_arg = new_argument_definition(field_type,
          new_identifier(field_name))
      functions.add( ? make_extern(field_name, fmt"{prefix}_set_{field_name}",
          @[self_arg, val_arg], ptr_ref, location))

  # init(fields...) -> Pointer
  if ("init", struct.fields.len) notin existing_names:
    var init_args: seq[ArgumentDefinition]
    for field in struct.fields:
      init_args.add(new_argument_definition(field.module_ref,
          new_identifier(field.name.asl)))
    functions.add( ? make_extern("init", fmt"{prefix}_init",
        init_args, ptr_ref, location))

  # byte_size(U64 items): U64
  if ("byte_size", 1) notin existing_names:
    let items_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_items"))
    functions.add( ? make_extern("byte_size", fmt"{prefix}_byte_size",
        @[items_arg], u64_ref, location))

  # read(Pointer ptr, U64 offset): Pointer
  if ("read", 2) notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("read", fmt"{prefix}_read",
        @[ptr_arg, offset_arg], ptr_ref, location))

  # write(Pointer value, Pointer ptr, U64 offset): Pointer
  if ("write", 3) notin existing_names:
    let val_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_value"))
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("write", fmt"{prefix}_write",
        @[val_arg, ptr_arg, offset_arg], ptr_ref, location))

  ok(functions)
