import results, strformat, sets

import ../parser

proc make_extern(fn_name: string, c_name: string,
    args: seq[ArgumentDefinition], returns: ModuleRef,
    location: Location): Result[Function, string] =
  let name_id = new_identifier(fn_name)
  let maybe_def = new_function_definition(name_id, args, returns, location)
  if maybe_def.is_err: return err($maybe_def.error)
  ok(new_function(new_extern_function(maybe_def.get, c_name)))

proc expand_struct*(struct: Struct, prefix: string,
    existing_names: HashSet[string]): Result[seq[Function], string] =
  var functions: seq[Function]
  let location = struct.location
  let ptr_ref = new_module_ref("Pointer")
  let u64_ref = new_module_ref("U64")

  # get_<field> and set_<field> for each field
  for field in struct.fields:
    let field_name = field.name.asl
    let field_type = field.module_ref

    let get_name = fmt"get_{field_name}"
    if get_name notin existing_names:
      let ptr_arg = new_argument_definition(ptr_ref,
          new_identifier("__asl_ptr"))
      functions.add( ? make_extern(get_name, fmt"{prefix}_{get_name}",
          @[ptr_arg], field_type, location))

    let set_name = fmt"set_{field_name}"
    if set_name notin existing_names:
      let ptr_arg = new_argument_definition(ptr_ref,
          new_identifier("__asl_ptr"))
      let val_arg = new_argument_definition(field_type,
          new_identifier(field_name))
      functions.add( ? make_extern(set_name, fmt"{prefix}_{set_name}",
          @[ptr_arg, val_arg], ptr_ref, location))

  # init(fields...) -> Pointer
  if "init" notin existing_names:
    var init_args: seq[ArgumentDefinition]
    for field in struct.fields:
      init_args.add(new_argument_definition(field.module_ref,
          new_identifier(field.name.asl)))
    functions.add( ? make_extern("init", fmt"{prefix}_init",
        init_args, ptr_ref, location))

  # byte_size(U64 items): U64
  if "byte_size" notin existing_names:
    let items_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_items"))
    functions.add( ? make_extern("byte_size", fmt"{prefix}_byte_size",
        @[items_arg], u64_ref, location))

  # read(Pointer ptr, U64 offset): Pointer
  if "read" notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("read", fmt"{prefix}_read",
        @[ptr_arg, offset_arg], ptr_ref, location))

  # write(Pointer value, Pointer ptr, U64 offset): Pointer
  if "write" notin existing_names:
    let val_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_value"))
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("write", fmt"{prefix}_write",
        @[val_arg, ptr_arg, offset_arg], ptr_ref, location))

  ok(functions)
