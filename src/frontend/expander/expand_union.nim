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

proc expand_branch(branch: UnionBranch, prefix: string,
    self_ref: ModuleRef,
    existing_names: HashSet[(string, int)],
    location: Location): Result[seq[Function], string] =
  var functions: seq[Function]
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"
  let ptr_ref = new_module_ref("Pointer")

  # Branch_field(Self self) and Branch_field(Self self, FieldType value)
  for field in branch.fields:
    let field_name = field.name.asl
    let field_type = field.module_ref
    let asl_name = fmt"{branch.name.asl}_{field_name}"

    if (asl_name, 1) notin existing_names:
      let self_arg = new_argument_definition(self_ref,
          new_identifier("self"))
      functions.add( ? make_extern(asl_name, fmt"{sub_prefix}_get_{field_name}",
          @[self_arg], field_type, location))

    if (asl_name, 2) notin existing_names:
      let self_arg = new_argument_definition(self_ref,
          new_identifier("self"))
      let val_arg = new_argument_definition(field_type,
          new_identifier(field_name))
      functions.add( ? make_extern(asl_name, fmt"{sub_prefix}_set_{field_name}",
          @[self_arg, val_arg], ptr_ref, location))

  # Branch_init(fields...) -> Pointer
  let init_name = fmt"{branch.name.asl}_init"
  if (init_name, branch.fields.len) notin existing_names:
    var init_args: seq[ArgumentDefinition]
    for field in branch.fields:
      init_args.add(new_argument_definition(field.module_ref,
          new_identifier(field.name.asl)))
    functions.add( ? make_extern(init_name, fmt"{sub_prefix}_init",
        init_args, ptr_ref, location))

  ok(functions)

proc expand_union*(union: Union, prefix: string,
    module_name: string, generics: seq[Generic],
    existing_names: HashSet[(string, int)]): Result[seq[Function], string] =
  var functions: seq[Function]
  let location = union.location
  let ptr_ref = new_module_ref("Pointer")
  let u64_ref = new_module_ref("U64")
  let self_ref = ? build_self_ref(module_name, generics)

  # id(Self self): U64
  if ("id", 1) notin existing_names:
    let self_arg = new_argument_definition(self_ref,
        new_identifier("self"))
    functions.add( ? make_extern("id", fmt"{prefix}_get_id",
        @[self_arg], u64_ref, location))

  # id(Self self, U64 id): Pointer
  if ("id", 2) notin existing_names:
    let self_arg = new_argument_definition(self_ref,
        new_identifier("self"))
    let id_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_id"))
    functions.add( ? make_extern("id", fmt"{prefix}_set_id",
        @[self_arg, id_arg], ptr_ref, location))

  # byte_size, read, write
  if ("byte_size", 1) notin existing_names:
    let items_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_items"))
    functions.add( ? make_extern("byte_size", fmt"{prefix}_byte_size",
        @[items_arg], u64_ref, location))

  if ("read", 2) notin existing_names:
    let ptr_arg = new_argument_definition(ptr_ref,
        new_identifier("__asl_ptr"))
    let offset_arg = new_argument_definition(u64_ref,
        new_identifier("__asl_offset"))
    functions.add( ? make_extern("read", fmt"{prefix}_read",
        @[ptr_arg, offset_arg], ptr_ref, location))

  if ("write", 3) notin existing_names:
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
    functions.add( ? expand_branch(branch, prefix, self_ref,
        existing_names, location))

  ok(functions)
