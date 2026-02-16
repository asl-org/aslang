import results, strformat, sets

import ../parser

proc make_extern(fn_name: string, c_name: string,
    args: seq[ArgumentDefinition], returns: ModuleRef,
    location: Location): Result[Function, string] =
  let name_id = new_identifier(fn_name)
  let maybe_def = new_function_definition(name_id, args, returns, location)
  if maybe_def.is_err: return err($maybe_def.error)
  ok(new_function(new_extern_function(maybe_def.get, c_name)))

proc expand_branch(branch: UnionBranch, prefix: string,
    existing_names: HashSet[string],
    location: Location): Result[seq[Function], string] =
  var functions: seq[Function]
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"
  let ptr_ref = new_module_ref("Pointer")

  # Branch_get_<field> and Branch_set_<field>
  for field in branch.fields:
    let field_name = field.name.asl
    let field_type = field.module_ref

    let get_name = fmt"{branch.name.asl}_get_{field_name}"
    if get_name notin existing_names:
      let ptr_arg = new_argument_definition(ptr_ref,
          new_identifier("__asl_ptr"))
      functions.add( ? make_extern(get_name, fmt"{sub_prefix}_get_{field_name}",
          @[ptr_arg], field_type, location))

    let set_name = fmt"{branch.name.asl}_set_{field_name}"
    if set_name notin existing_names:
      let ptr_arg = new_argument_definition(ptr_ref,
          new_identifier("__asl_ptr"))
      let val_arg = new_argument_definition(field_type,
          new_identifier(field_name))
      functions.add( ? make_extern(set_name, fmt"{sub_prefix}_set_{field_name}",
          @[ptr_arg, val_arg], ptr_ref, location))

  # Branch_init(fields...) -> Pointer
  let init_name = fmt"{branch.name.asl}_init"
  if init_name notin existing_names:
    var init_args: seq[ArgumentDefinition]
    for field in branch.fields:
      init_args.add(new_argument_definition(field.module_ref,
          new_identifier(field.name.asl)))
    functions.add( ? make_extern(init_name, fmt"{sub_prefix}_init",
        init_args, ptr_ref, location))

  ok(functions)

proc expand_union*(union: Union, prefix: string,
    existing_names: HashSet[string]): Result[seq[Function], string] =
  var functions: seq[Function]
  let location = union.location
  let ptr_ref = new_module_ref("Pointer")
  let u64_ref = new_module_ref("U64")

  # get_id(Pointer ptr): U64
  if "get_id" notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    functions.add( ? make_extern("get_id", fmt"{prefix}_get_id",
        @[ptr_arg], u64_ref, location))

  # set_id(Pointer ptr, U64 id): Pointer
  if "set_id" notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let id_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_id"))
    functions.add( ? make_extern("set_id", fmt"{prefix}_set_id",
        @[ptr_arg, id_arg], ptr_ref, location))

  # byte_size, read, write
  if "byte_size" notin existing_names:
    let items_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_items"))
    functions.add( ? make_extern("byte_size", fmt"{prefix}_byte_size",
        @[items_arg], u64_ref, location))

  if "read" notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("read", fmt"{prefix}_read",
        @[ptr_arg, offset_arg], ptr_ref, location))

  if "write" notin existing_names:
    let val_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_value"))
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("write", fmt"{prefix}_write",
        @[val_arg, ptr_arg, offset_arg], ptr_ref, location))

  # Branch-specific functions
  for branch in union.branches:
    functions.add( ? expand_branch(branch, prefix, existing_names, location))

  ok(functions)
