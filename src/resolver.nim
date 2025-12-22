import results, sequtils, strformat, tables, hashes, strutils, sets, re,
    options, algorithm

import resolver/deps_analyzer
export deps_analyzer

type
  ResolvedModuleRefKind = enum
    RMRK_NATIVE, RMRK_USER, RMRK_GENERIC
  ResolvedModuleRef = ref object of RootObj
    location: Location
    case kind: ResolvedModuleRefKind
    of RMRK_NATIVE: native_module: TypedNativeModule
    of RMRK_GENERIC: generic: TypedGeneric
    of RMRK_USER:
      user_module: TypedUserModule
      children: seq[ResolvedModuleRef]
      impls: seq[seq[TypedFunctionDefinition]]
      concrete_map: Table[TypedGeneric, ResolvedModuleRef]

proc new_resolved_module_ref(native_module: TypedNativeModule,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: RMRK_NATIVE, native_module: native_module,
      location: location)

proc new_resolved_module_ref(generic: TypedGeneric,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: RMRK_GENERIC, generic: generic,
      location: location)

proc new_resolved_module_ref(user_module: TypedUserModule, children: seq[
    ResolvedModuleRef], impls: seq[seq[TypedFunctionDefinition]],
        location: Location): ResolvedModuleRef =
  var concrete_map: Table[TypedGeneric, ResolvedModuleRef]
  for (generic, child) in zip(user_module.generics, children):
    concrete_map[generic] = child
  ResolvedModuleRef(kind: RMRK_USER, user_module: user_module,
      concrete_map: concrete_map, children: children, impls: impls,
      location: location)

proc name(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.name.asl
  of RMRK_USER: module_ref.user_module.name.asl
  of RMRK_GENERIC: module_ref.generic.name.asl

proc can_be_argument(module_ref: ResolvedModuleRef): Result[void, string] =
  case module_ref.kind:
  of RMRK_NATIVE: ok() # native modules can be passed as an argument
  of RMRK_GENERIC: ok() # generic arguments can be passed as an argument too.
  of RMRK_USER:
    let module = module_ref.user_module
    if module.structs.len > 0: ok()
    else: err(fmt"{module_ref.location} module `{module.name.asl}` can not be passed as an argument")

proc find_function(module_ref: ResolvedModuleRef,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.find_function(def)
  of RMRK_GENERIC: module_ref.generic.find_function(def)
  of RMRK_USER: module_ref.user_module.find_function(def)

proc concretize(module_ref: ResolvedModuleRef, concrete_map: Table[TypedGeneric,
    ResolvedModuleRef]): ResolvedModuleRef =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref
  of RMRK_GENERIC: concrete_map[module_ref.generic]
  of RMRK_USER:
    var concretized_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      concretized_children.add(child.concretize(concrete_map))
    new_resolved_module_ref(module_ref.user_module, concretized_children,
        module_ref.impls, module_ref.location)

proc hash(module_ref: ResolvedModuleRef): Hash =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.hash
  of RMRK_GENERIC: module_ref.generic.hash
  of RMRK_USER:
    var acc = module_ref.user_module.hash
    for child in module_ref.children:
      acc = acc !& child.hash
    acc

proc `==`(self: ResolvedModuleRef, other: ResolvedModuleRef): bool =
  self.hash == other.hash

proc generic_impls(module_ref: ResolvedModuleRef): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  case module_ref.kind:
  of RMRK_NATIVE: discard
  of RMRK_GENERIC: discard
  of RMRK_USER:
    if module_ref.children.len > 0:
      var generics: seq[HashSet[TypedModule]]
      for index, child in module_ref.children.pairs:
        generics.add(init_hashset[TypedModule]())
        case child.kind:
        of RMRK_NATIVE: generics[index].incl(new_typed_module(
            child.native_module))
        of RMRK_GENERIC: discard
        of RMRK_USER: generics[index].incl(new_typed_module(
            child.user_module))
      impl_set[module_ref.user_module] = generics
  return impl_set

proc asl(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.asl
  of RMRK_GENERIC: module_ref.generic.asl
  of RMRK_USER:
    var parent_str = module_ref.user_module.asl
    if module_ref.children.len == 0:
      parent_str
    else:
      var children_args: seq[string]
      for child in module_ref.children:
        children_args.add(child.asl)
      let children_str = children_args.join(", ")
      fmt"{parent_str}[{children_str}]"

proc byte_size(module_ref: ResolvedModuleRef): uint64 =
  case module_ref.kind:
  of RMRK_NATIVE:
    case module_ref.native_module.name.asl:
    of "U8", "S8": 1
    of "U16", "S16": 2
    of "U32", "S32", "F32": 4
    else: 8
  else: 8

proc c(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.name.asl
  else: "Pointer"

proc resolve_def(file: TypedFile, module: TypedUserModule,
    generic: TypedGeneric, module_ref: TypedModuleRef): Result[
        ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    let untyped_generic = ? module_ref.generic
    let typed_generic = ? module.find_generic(untyped_generic)
    if typed_generic != generic:
      return err(fmt"{module_ref.location} expected generic `{generic.name.asl}` but found `{typed_generic.name.asl}`")

    ok(new_resolved_module_ref(typed_generic, module_ref.location))
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)
    if typed_module == module:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` can not be passed as an argument to generic constraint `{generic.name.asl}`")

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    var matching_impls: seq[seq[TypedFunctionDefinition]]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, module, generic, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      var generic_impls: seq[TypedFunctionDefinition]
      for def in typed_generic.concrete_defs(child.self()):
        generic_impls.add( ? resolved_child.find_function(def))
      matching_impls.add(generic_impls)
    ok(new_resolved_module_ref(typed_module, resolved_children, matching_impls,
        module_ref.location))

proc resolve_def(file: TypedFile, module: TypedUserModule,
    module_ref: TypedModuleRef): Result[ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    let untyped_generic = ? module_ref.generic
    let typed_generic = ? module.find_generic(untyped_generic)

    ok(new_resolved_module_ref(typed_generic, module_ref.location))
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    var matching_impls: seq[seq[TypedFunctionDefinition]]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, module, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      var generic_impls: seq[TypedFunctionDefinition]
      for def in typed_generic.concrete_defs(child.self()):
        generic_impls.add( ? resolved_child.find_function(def))
      matching_impls.add(generic_impls)
    ok(new_resolved_module_ref(typed_module, resolved_children, matching_impls,
        module_ref.location))

proc resolve_def(file: TypedFile, module_ref: TypedModuleRef): Result[
    ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    err(fmt"{module_ref.location} file level functions do not support generics")
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    var matching_impls: seq[seq[TypedFunctionDefinition]]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      var generic_impls: seq[TypedFunctionDefinition]
      for def in typed_generic.concrete_defs(child.self()):
        generic_impls.add( ? resolved_child.find_function(def))
      matching_impls.add(generic_impls)
    ok(new_resolved_module_ref(typed_module, resolved_children, matching_impls,
        module_ref.location))

type ResolvedArgumentDefinition = ref object of RootObj
  name: Identifier
  module_ref: ResolvedModuleRef
  location: Location

proc new_resolved_argument_definition(module_ref: ResolvedModuleRef,
    name: Identifier, location: Location): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, module_ref: module_ref,
      location: location)

proc new_resolved_argument_definition(module_ref: ResolvedModuleRef,
    name: Identifier): ResolvedArgumentDefinition =
  new_resolved_argument_definition(module_ref, name, module_ref.location)

proc concretize(arg: ResolvedArgumentDefinition, concrete_map: Table[
    TypedGeneric, ResolvedModuleRef]): ResolvedArgumentDefinition =
  let concretized_module_ref = arg.module_ref.concretize(concrete_map)
  new_resolved_argument_definition(concretized_module_ref, arg.name)

proc byte_size(arg: ResolvedArgumentDefinition): uint64 =
  arg.module_ref.byte_size

proc generic_impls(arg: ResolvedArgumentDefinition): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  arg.module_ref.generic_impls

proc asl(arg: ResolvedArgumentDefinition): string =
  fmt"{arg.module_ref.asl} {arg.name.asl}"

proc c(arg: ResolvedArgumentDefinition): string =
  fmt"{arg.module_ref.c} {arg.name.asl}"

proc resolve_def(file: TypedFile, module: TypedUserModule,
    generic: TypedGeneric, arg: TypedArgumentDefinition): Result[
        ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, module, generic, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

proc resolve_def(file: TypedFile, module: TypedUserModule,
    arg: TypedArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, module, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

proc resolve_def(file: TypedFile, arg: TypedArgumentDefinition): Result[
    ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

type ResolvedUserFunctionDefinition = ref object of RootObj
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedModuleRef
  prefix: string
  generics: uint64
  location: Location

proc new_resolved_function_definition(name: Identifier,
    args: seq[ResolvedArgumentDefinition], returns: ResolvedModuleRef,
    location: Location, prefix: string = "",
        generics: uint64 = 0): ResolvedUserFunctionDefinition =
  ResolvedUserFunctionDefinition(name: name, args: args,
      returns: returns, location: location, prefix: prefix, generics: generics)

proc arity(def: ResolvedUserFunctionDefinition): uint = def.args.len.uint
proc concretize(def: ResolvedUserFunctionDefinition, concrete_map: Table[
    TypedGeneric, ResolvedModuleRef]): ResolvedUserFunctionDefinition =
  var concretized_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    concretized_args.add(arg.concretize(concrete_map))
  let concretized_returns = def.returns.concretize(concrete_map)
  new_resolved_function_definition(def.name, concretized_args,
      concretized_returns, def.location)

proc generic_impls(def: ResolvedUserFunctionDefinition): Table[TypedUserModule,
    seq[HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for arg in def.args: impl_set = impl_set.merge(arg.generic_impls())
  impl_set = impl_set.merge(def.returns.generic_impls())
  return impl_set

proc asl(def: ResolvedUserFunctionDefinition): string =
  let args = def.args.map_it(it.asl).join(", ")
  fmt"fn {def.name.asl}({args}): {def.returns.asl}"

proc c_name(def: ResolvedUserFunctionDefinition): string =
  if def.prefix == "":
    fmt"{def.name.asl}_{def.location.hash.to_hex}"
  else:
    fmt"{def.prefix}_{def.name.asl}_{def.location.hash.to_hex}"

proc c(def: ResolvedUserFunctionDefinition): string =
  let generic_args = if def.generics > 0: ((0.uint64)..<(def.generics)).map_it(
      fmt"U64 __asl_impl_id_{it}") else: @[]
  let args = generic_args & def.args.map_it(it.c)
  let args_str = args.join(", ")

  fmt"{def.returns.c} {def.c_name}({args_str});"

proc resolve_def(file: TypedFile, module: TypedUserModule,
    generic: TypedGeneric, def: TypedFunctionDefinition): Result[
        ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, module, generic, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, module, generic, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args,
      resolved_returns, def.location, fmt"{module.name.asl}_{generic.name.asl}",
      module.generics.len.uint64))

proc resolve_def(file: TypedFile, module: TypedUserModule,
    def: TypedFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, module, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args,
      resolved_returns, def.location, module.name.asl,
      module.generics.len.uint64))

proc resolve_def(file: TypedFile, def: TypedFunctionDefinition): Result[
    ResolvedUserFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_returns, def.location))

type ResolvedGeneric = ref object of RootObj
  generic: TypedGeneric
  defs: seq[ResolvedUserFunctionDefinition]
  defs_map: Table[Identifier, Table[uint, seq[ResolvedUserFunctionDefinition]]]
  location: Location

proc new_resolved_generic(generic: TypedGeneric, defs: seq[
    ResolvedUserFunctionDefinition], location: Location): ResolvedGeneric =
  var defs_map: Table[Identifier, Table[uint, seq[
      ResolvedUserFunctionDefinition]]]
  for def in defs:
    if def.name notin defs_map:
      defs_map[def.name] = init_table[uint, seq[
          ResolvedUserFunctionDefinition]]()
    if def.arity notin defs_map[def.name]:
      defs_map[def.name][def.arity] = new_seq[ResolvedUserFunctionDefinition]()
    defs_map[def.name][def.arity].add(def)
  ResolvedGeneric(generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc name(generic: ResolvedGeneric): Identifier = generic.generic.name

proc generic_impls(generic: ResolvedGeneric): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for def in generic.defs: impl_set = impl_set.merge(def.generic_impls())
  return impl_set

proc asl(generic: ResolvedGeneric, indent: string): seq[string] =
  if generic.defs.len == 0:
    @[fmt"generic {generic.name.asl}"]
  else:
    var lines = @[fmt"generic {generic.name.asl}:"]
    for def in generic.defs:
      lines.add(indent & def.asl)
    lines

proc c(generic: ResolvedGeneric, prefix: string): seq[string] =
  var lines: seq[string]
  for def in generic.defs:
    lines.add(def.c)
  # TODO: provide implementation of generic calls
  return lines

proc find_function_defs(generic: ResolvedGeneric, name: Identifier,
    arity: uint): Result[seq[ResolvedUserFunctionDefinition], string] =
  if name notin generic.defs_map:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}`")
  elif arity notin generic.defs_map[name]:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.defs_map[name][arity])

proc resolve_def(file: TypedFile, module: TypedUserModule,
    generic: TypedGeneric): Result[ResolvedGeneric, string] =
  var resolved_defs: seq[ResolvedUserFunctionDefinition]
  for def in generic.defs:
    let resolved_def = ? resolve_def(file, module, generic, def)
    resolved_defs.add(resolved_def)
  ok(new_resolved_generic(generic, resolved_defs, generic.location))

type
  ResolvedStructKind = enum
    RSK_DEFAULT, RSK_NAMED
  ResolvedStruct = ref object of RootObj
    struct: TypedStruct
    location: Location
    fields: seq[ResolvedArgumentDefinition]
    fields_map: Table[Identifier, int]
    case kind: ResolvedStructKind
    of RSK_DEFAULT: discard
    of RSK_NAMED: name: Identifier

proc new_resolved_struct(struct: TypedStruct, fields: seq[
    ResolvedArgumentDefinition], location: Location): ResolvedStruct =
  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs: fields_map[field.name] = index
  ResolvedStruct(kind: RSK_DEFAULT, struct: struct, fields: fields,
      fields_map: fields_map, location: location)

proc new_resolved_struct(struct: TypedStruct, name: Identifier, fields: seq[
    ResolvedArgumentDefinition], location: Location): ResolvedStruct =
  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs: fields_map[field.name] = index
  ResolvedStruct(kind: RSK_NAMED, struct: struct, name: name, fields: fields,
      fields_map: fields_map, location: location)

proc id(struct: ResolvedStruct): uint64 = struct.struct.id

proc generic_impls(struct: ResolvedStruct): Table[TypedUserModule, seq[HashSet[
    TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for field in struct.fields: impl_set = impl_set.merge(field.generic_impls())
  return impl_set

proc asl(struct: ResolvedStruct, indent: string): seq[string] =
  var lines =
    case struct.kind:
    of RSK_DEFAULT: @["struct:"]
    of RSK_NAMED: @[fmt"struct {struct.name.asl}:"]

  for field in struct.fields:
    lines.add(indent & field.asl)

  return lines

proc c(struct: ResolvedStruct, prefix: string, default_offset: uint64 = 0): seq[string] =
  let sub_prefix =
    case struct.kind:
    of RSK_DEFAULT: fmt"{prefix}"
    of RSK_NAMED: fmt"{prefix}_{struct.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: ResolvedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  var offset: uint64 = default_offset
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str});")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")
  for field in struct.fields:
    lines.add(fmt"__asl_ptr = {sub_prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
  return lines

proc concretize(struct: ResolvedStruct, concrete_map: Table[TypedGeneric,
    ResolvedModuleRef]): ResolvedStruct =
  var concretized_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    concretized_fields.add(field.concretize(concrete_map))

  case struct.kind:
  of RSK_DEFAULT: new_resolved_struct(struct.struct, concretized_fields,
      struct.location)
  of RSK_NAMED: new_resolved_struct(struct.struct, struct.name,
      concretized_fields, struct.location)

proc find_field_index(struct: ResolvedStruct, field: Identifier): Result[int, string] =
  if field in struct.fields_map:
    ok(struct.fields_map[field])
  else:
    err(fmt"{field.location} field is not defined in the struct")

proc find_field(struct: ResolvedStruct, field: Identifier): Result[
    ResolvedArgumentDefinition, string] =
  let field_index = ? struct.find_field_index(field)
  ok(struct.fields[field_index])

proc resolve_def(file: TypedFile, module: TypedUserModule,
    struct: TypedStruct): Result[ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve_def(file, module, field)
    resolved_fields.add(resolved_field)

  case struct.kind:
  of TSK_DEFAULT:
    ok(new_resolved_struct(struct, resolved_fields, struct.location))
  of TSK_NAMED:
    let struct_name = ? struct.name
    ok(new_resolved_struct(struct, struct_name, resolved_fields,
        struct.location))

type ResolvedUserModuleDefinition = ref object of RootObj
  module: TypedUserModule
  generics: seq[ResolvedGeneric]
  generics_map: Table[TypedGeneric, ResolvedGeneric]
  structs: seq[ResolvedStruct]
  default_struct_index: int
  structs_map: Table[Identifier, ResolvedStruct]
  function_defs: seq[ResolvedUserFunctionDefinition]
  function_defs_map: Table[TypedFunctionDefinition, ResolvedUserFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedUserFunctionDefinition]]]

proc new_resolved_user_module_definition(module: TypedUserModule,
    generics: seq[(TypedGeneric, ResolvedGeneric)], structs: seq[
        ResolvedStruct],
    function_defs: seq[(TypedFunctionDefinition,
    ResolvedUserFunctionDefinition)]): ResolvedUserModuleDefinition =
  var generics_map: Table[TypedGeneric, ResolvedGeneric]
  var resolved_generics: seq[ResolvedGeneric]
  for (typed_generic, resolved_generic) in generics:
    generics_map[typed_generic] = resolved_generic
    resolved_generics.add(resolved_generic)

  var default_struct_index = -1
  var structs_map: Table[Identifier, ResolvedStruct]
  var resolved_structs: seq[ResolvedStruct]
  for index, resolved_struct in structs.pairs:
    resolved_structs.add(resolved_struct)
    case resolved_struct.kind:
    of RSK_DEFAULT: default_struct_index = index
    of RSK_NAMED: structs_map[resolved_struct.name] = resolved_struct

  var function_defs_map: Table[TypedFunctionDefinition, ResolvedUserFunctionDefinition]
  var resolved_function_defs: seq[ResolvedUserFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedUserFunctionDefinition]]]
  for (typed_function_def, resolved_function_def) in function_defs:
    function_defs_map[typed_function_def] = resolved_function_def
    resolved_function_defs.add(resolved_function_def)

    if resolved_function_def.name notin function_signatures_map:
      function_signatures_map[resolved_function_def.name] = init_table[uint,
          seq[ResolvedUserFunctionDefinition]]()
    if resolved_function_def.arity notin function_signatures_map[
        resolved_function_def.name]:
      function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity] = new_seq[
              ResolvedUserFunctionDefinition]()
    function_signatures_map[resolved_function_def.name][
        resolved_function_def.arity].add(resolved_function_def)

  ResolvedUserModuleDefinition(
    module: module, generics: resolved_generics, generics_map: generics_map,
    structs: resolved_structs, structs_map: structs_map,
    function_defs: resolved_function_defs, function_defs_map: function_defs_map,
    function_signatures_map: function_signatures_map
  )

proc id(module_def: ResolvedUserModuleDefinition): uint64 = module_def.id
proc name(module_def: ResolvedUserModuleDefinition): Identifier = module_def.module.name

proc generic_impls(def: ResolvedUserModuleDefinition): Table[TypedUserModule,
    seq[HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for generic in def.generics: impl_set = impl_set.merge(generic.generic_impls())
  for struct in def.structs: impl_set = impl_set.merge(struct.generic_impls())
  for function in def.function_defs: impl_set = impl_set.merge(
      function.generic_impls())
  return impl_set

proc asl(def: ResolvedUserModuleDefinition, indent: string): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.asl(indent))

  if def.generics.len > 0:
    lines.add("\n")

  for struct in def.structs:
    lines.add(struct.asl(indent))
  return lines

proc c(def: ResolvedUserModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  if def.structs.len > 0:
    # internal functions for structs
    # byte size
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items);")
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items)")
    lines.add("{")
    lines.add("return Pointer_byte_size(items);")
    lines.add("}")
    # read
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset);")
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset)")
    lines.add("{")
    lines.add("return Pointer_read(__asl_ptr, offset);")
    lines.add("}")
    # write
    lines.add(fmt"Pointer {def.name.asl}_write(Pointer value, Pointer __asl_ptr, U64 offset);")
    lines.add(fmt"Pointer {def.name.asl}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
    lines.add("{")
    lines.add("return Pointer_write(value, __asl_ptr, offset);")
    lines.add("}")

    # struct
    if def.structs.len == 1:
      let struct = def.structs[0]
      lines.add(struct.c(def.name.asl))
    # union
    else:
      for struct in def.structs:
        lines.add(struct.c(def.name.asl, 8))
      # union branch id getter
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr);")
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr)")
      lines.add("{")
      lines.add(fmt"return U64_read(__asl_ptr, 0);")
      lines.add("}")

      # union branch id setter
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id);")
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id)")
      lines.add("{")
      lines.add(fmt"return U64_write(id, __asl_ptr, 0);")
      lines.add("}")

      # union branch value getter
      lines.add(fmt"Pointer {def.name.asl}_get_value(Pointer __asl_ptr);")
      lines.add(fmt"Pointer {def.name.asl}_get_value(Pointer __asl_ptr)")
      lines.add("{")
      lines.add(fmt"return Pointer_read(__asl_ptr, 8);")
      lines.add("}")

      # union branch value setter
      lines.add(fmt"Pointer {def.name.asl}_set_value(Pointer __asl_ptr, Pointer value);")
      lines.add(fmt"Pointer {def.name.asl}_set_value(Pointer __asl_ptr, Pointer value)")
      lines.add("{")
      lines.add(fmt"return Pointer_write(value, __asl_ptr, 8);")
      lines.add("}")

      lines.add(fmt"Pointer {def.name.asl}_init(U64 id, Pointer value);")
      lines.add(fmt"Pointer {def.name.asl}_init(U64 id, Pointer value)")
      lines.add("{")
      lines.add("Pointer __asl_ptr = System_allocate(16);")
      lines.add(fmt"__asl_ptr = {def.name.asl}_set_id(__asl_ptr, id);")
      lines.add(fmt"__asl_ptr = {def.name.asl}_set_value(__asl_ptr, value);")
      lines.add("return __asl_ptr;")
      lines.add("}")

  # TODO: Understand that function can not have same name so use function id as prefix
  lines.add(def.function_defs.map_it(it.c))

  return lines

proc find_generic(module_def: ResolvedUserModuleDefinition,
    generic: TypedGeneric): Result[ResolvedGeneric, string] =
  if generic notin module_def.generics_map:
    err(fmt"module `{module_def.name.asl}` does not have any generic named `{generic.name.asl}`")
  else:
    ok(module_def.generics_map[generic])

proc find_struct(module_def: ResolvedUserModuleDefinition): Result[
    ResolvedStruct, string] =
  if module_def.default_struct_index == -1:
    err(fmt"module `{module_def.name.asl}` does not have a default struct")
  else:
    ok(module_def.structs[module_def.default_struct_index])

proc find_struct(module_def: ResolvedUserModuleDefinition,
    name: Identifier): Result[ResolvedStruct, string] =
  if name notin module_def.structs_map:
    err(fmt"module `{module_def.name.asl}` does not have struct named `{name.asl}`")
  else:
    ok(module_def.structs_map[name])

proc find_function_def(module_def: ResolvedUserModuleDefinition,
    function_def: TypedFunctionDefinition): Result[
        ResolvedUserFunctionDefinition, string] =
  if function_def notin module_def.function_defs_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{function_def.name.asl}`")
  else:
    ok(module_def.function_defs_map[function_def])

proc find_function_defs(module_def: ResolvedUserModuleDefinition,
    name: Identifier, arity: uint): Result[seq[
    ResolvedUserFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile, module: TypedUserModule): Result[
    ResolvedUserModuleDefinition, string] =
  var generics: seq[(TypedGeneric, ResolvedGeneric)]
  for generic in module.generics:
    let resolved_generic = ? resolve_def(file, module, generic)
    generics.add((generic, resolved_generic))

  var structs: seq[ResolvedStruct]
  for struct in module.structs:
    let resolved_struct = ? resolve_def(file, module, struct)
    structs.add(resolved_struct)

  var function_defs: seq[(TypedFunctionDefinition,
      ResolvedUserFunctionDefinition)]
  for function in module.functions:
    let resolved_def = ? resolve_def(file, module, function.def)
    function_defs.add((function.def, resolved_def))

  ok(new_resolved_user_module_definition(module, generics, structs,
      function_defs))

type ResolvedNativeFunctionDefinition = ref object of RootObj
  native: string
  def: ResolvedUserFunctionDefinition

proc new_resolved_native_function_definition(native: string,
    def: ResolvedUserFunctionDefinition): ResolvedNativeFunctionDefinition =
  ResolvedNativeFunctionDefinition(native: native, def: def)

proc name(def: ResolvedNativeFunctionDefinition): Identifier = def.def.name
proc arity(def: ResolvedNativeFunctionDefinition): uint = def.def.arity.uint
proc generic_impls(function: ResolvedNativeFunctionDefinition): Table[
    TypedUserModule, seq[HashSet[TypedModule]]] =
  function.def.generic_impls

proc resolve_def(file: TypedFile, function: TypedNativeFunction): Result[
    ResolvedNativeFunctionDefinition, string] =
  let resolved_def = ? resolve_def(file, function.def)
  ok(new_resolved_native_function_definition(function.native, resolved_def))

type ResolvedNativeModuleDefinition = ref object of RootObj
  module: TypedNativeModule
  name: Identifier
  functions: seq[ResolvedNativeFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedNativeFunctionDefinition]]]

proc new_resolved_native_module_definition(module: TypedNativeModule,
    name: Identifier, functions: seq[
    ResolvedNativeFunctionDefinition]): ResolvedNativeModuleDefinition =
  var function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedNativeFunctionDefinition]]]
  for function in functions:
    if function.name notin function_signatures_map:
      function_signatures_map[function.name] = init_table[uint, seq[
          ResolvedNativeFunctionDefinition]]()
    if function.arity notin function_signatures_map[function.name]:
      function_signatures_map[function.name][function.arity] = new_seq[
          ResolvedNativeFunctionDefinition]()
    function_signatures_map[function.name][function.arity].add(function)
  ResolvedNativeModuleDefinition(module: module, name: name,
      functions: functions, function_signatures_map: function_signatures_map)

proc id(module_def: ResolvedNativeModuleDefinition): uint64 = module_def.id

proc generic_impls(module: ResolvedNativeModuleDefinition): Table[
    TypedUserModule, seq[HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for function in module.functions: impl_set = impl_set.merge(
      function.generic_impls())
  return impl_set

proc find_function_defs(module_def: ResolvedNativeModuleDefinition,
    name: Identifier, arity: uint): Result[seq[
    ResolvedNativeFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"native module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"native module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile, def: TypedNativeModule): Result[
    ResolvedNativeModuleDefinition, string] =
  var resolved_functions: seq[ResolvedNativeFunctionDefinition]
  for function in def.functions:
    let resolved_function = ? resolve_def(file, function)
    resolved_functions.add(resolved_function)
  ok(new_resolved_native_module_definition(def, def.name, resolved_functions))

type
  ResolvedModuleDefinitionKind = enum
    RMDK_NATIVE, RMDK_USER
  ResolvedModuleDefinition = ref object of RootObj
    case kind: ResolvedModuleDefinitionKind
    of RMDK_NATIVE: native: ResolvedNativeModuleDefinition
    of RMDK_USER: user: ResolvedUserModuleDefinition

proc new_resolved_module_definition(native: ResolvedNativeModuleDefinition): ResolvedModuleDefinition =
  ResolvedModuleDefinition(kind: RMDK_NATIVE, native: native)

proc new_resolved_module_definition(user: ResolvedUserModuleDefinition): ResolvedModuleDefinition =
  ResolvedModuleDefinition(kind: RMDK_USER, user: user)

proc id(def: ResolvedModuleDefinition): uint64 =
  case def.kind:
  of RMDK_NATIVE: def.native.id
  of RMDK_USER: def.user.id

type ResolvedFileDefinition = ref object of RootObj
  file: TypedFile
  native_modules: seq[ResolvedNativeModuleDefinition]
  native_modules_map: Table[TypedNativeModule, ResolvedNativeModuleDefinition]
  user_modules: seq[ResolvedUserModuleDefinition]
  user_modules_map: Table[TypedUserModule, ResolvedUserModuleDefinition]
  function_defs: seq[ResolvedUserFunctionDefinition]
  function_defs_map: Table[TypedFunctionDefinition, ResolvedUserFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedUserFunctionDefinition]]]

proc new_resolved_file_definition(file: TypedFile, native_modules: seq[(
    TypedNativeModule, ResolvedNativeModuleDefinition)], user_modules: seq[(
    TypedUserModule, ResolvedUserModuleDefinition)], function_defs: seq[(
    TypedFunctionDefinition,
    ResolvedUserFunctionDefinition)]): ResolvedFileDefinition =
  var native_modules_map: Table[TypedNativeModule, ResolvedNativeModuleDefinition]
  var resolved_native_modules: seq[ResolvedNativeModuleDefinition]
  for (typed_module, resolved_module) in native_modules:
    native_modules_map[typed_module] = resolved_module
    resolved_native_modules.add(resolved_module)

  var user_modules_map: Table[TypedUserModule, ResolvedUserModuleDefinition]
  var resolved_user_modules: seq[ResolvedUserModuleDefinition]
  for (typed_module, resolved_user_module) in user_modules:
    user_modules_map[typed_module] = resolved_user_module
    resolved_user_modules.add(resolved_user_module)

  var function_defs_map: Table[TypedFunctionDefinition, ResolvedUserFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedUserFunctionDefinition]]]
  var resolved_function_defs: seq[ResolvedUserFunctionDefinition]
  for (typed_function_def, resolved_function_def) in function_defs:
    function_defs_map[typed_function_def] = resolved_function_def
    resolved_function_defs.add(resolved_function_def)

    if resolved_function_def.name notin function_signatures_map:
      function_signatures_map[resolved_function_def.name] = init_table[uint,
          seq[ResolvedUserFunctionDefinition]]()
    if resolved_function_def.arity notin function_signatures_map[
        resolved_function_def.name]:
      function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity] = new_seq[
              ResolvedUserFunctionDefinition]()
    function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity].add(resolved_function_def)

  ResolvedFileDefinition(file: file, native_modules: resolved_native_modules,
      native_modules_map: native_modules_map,
      user_modules: resolved_user_modules,
      user_modules_map: user_modules_map, function_defs: resolved_function_defs,
      function_defs_map: function_defs_map,
      function_signatures_map: function_signatures_map)

proc generic_impls(file: ResolvedFileDefinition): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for module in file.native_modules: impl_set = impl_set.merge(
      module.generic_impls())
  for module in file.user_modules: impl_set = impl_set.merge(
      module.generic_impls())
  for function_def in file.function_defs:
    impl_set = impl_set.merge(function_def.generic_impls())
  return impl_set

proc c(file: ResolvedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.user_modules:
    lines.add(module.c)
  for fndef in file.function_defs:
    lines.add(fndef.c)
  return lines

proc find_module_def(file_def: ResolvedFileDefinition,
    module: TypedNativeModule): Result[ResolvedNativeModuleDefinition, string] =
  if module in file_def.native_modules_map:
    ok(file_def.native_modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in resolved file definition")

proc find_module_def(file_def: ResolvedFileDefinition,
    module: TypedUserModule): Result[ResolvedUserModuleDefinition, string] =
  if module in file_def.user_modules_map:
    ok(file_def.user_modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in resolved file definition")

proc find_module_def(file_def: ResolvedFileDefinition,
    module: TypedModule): Result[ResolvedModuleDefinition, string] =
  case module.kind:
  of TMK_NATIVE:
    let typed_native_module = ? module.native
    let native_module_def = ? file_def.find_module_def(typed_native_module)
    ok(new_resolved_module_definition(native_module_def))
  of TMK_USER:
    let typed_user_module = ? module.user
    let user_module_def = ? file_def.find_module_def(typed_user_module)
    ok(new_resolved_module_definition(user_module_def))

proc find_function_def(file_def: ResolvedFileDefinition,
    def: TypedFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  if def in file_def.function_defs_map:
    ok(file_def.function_defs_map[def])
  else:
    err(fmt"def `{def.name.asl}` not found in resolved file definition")

proc find_function_defs(file_def: ResolvedFileDefinition, name: Identifier,
    arity: uint): Result[seq[ResolvedUserFunctionDefinition], string] =
  if name notin file_def.function_signatures_map:
    err(fmt"function `{name.asl}` not found in resolved file definition")
  elif arity notin file_def.function_signatures_map[name]:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in resolved file definition")
  else:
    ok(file_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile): Result[ResolvedFileDefinition, string] =
  var native_modules: seq[(TypedNativeModule, ResolvedNativeModuleDefinition)]
  for module in file.native_modules:
    let resolved_module_def = ? resolve_def(file, module)
    native_modules.add((module, resolved_module_def))

  var modules: seq[(TypedUserModule, ResolvedUserModuleDefinition)]
  for module in file.user_modules:
    let resolved_module_def = ? resolve_def(file, module)
    modules.add((module, resolved_module_def))

  var function_defs: seq[(TypedFunctionDefinition,
      ResolvedUserFunctionDefinition)]
  for function in file.functions:
    let resolved_function_def = ? resolve_def(file, function.def)
    function_defs.add((function.def, resolved_function_def))

  ok(new_resolved_file_definition(file, native_modules, modules, function_defs))

type FunctionScope = ref object of RootObj
  table: Table[Identifier, ResolvedModuleRef]

proc get(scope: FunctionScope, name: Identifier): Result[ResolvedModuleRef, string] =
  if name notin scope.table:
    return err(fmt"{name.location} argument `{name.asl}` is not present in the scope")
  ok(scope.table[name])

proc set(scope: FunctionScope, arg: ResolvedArgumentDefinition): Result[
    FunctionScope, string] =
  if arg.name in scope.table:
    return err(fmt"{arg.location} argument `{arg.name.asl}` can not be mutated")
  scope.table[arg.name] = arg.module_ref
  ok(scope)

proc clone(scope: FunctionScope): FunctionScope =
  var table: Table[Identifier, ResolvedModuleRef]
  for name, module_ref in scope.table:
    table[name] = module_ref
  FunctionScope(table: table)

type
  ResolvedFunctionDefinitionKind = enum
    RFDK_USER, RFDK_NATIVE
  ResolvedFunctionDefinition = ref object of RootObj
    case kind: ResolvedFunctionDefinitionKind
    of RFDK_USER: user: ResolvedUserFunctionDefinition
    of RFDK_NATIVE: native: ResolvedNativeFunctionDefinition

proc new_resolved_function_definition(def: ResolvedUserFunctionDefinition): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(kind: RFDK_USER, user: def)

proc new_resolved_function_definition(def: ResolvedNativeFunctionDefinition): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(kind: RFDK_NATIVE, native: def)

proc args(def: ResolvedFunctionDefinition): seq[ResolvedArgumentDefinition] =
  case def.kind:
  of RFDK_NATIVE: def.native.def.args
  of RFDK_USER: def.user.args

proc returns(def: ResolvedFunctionDefinition): ResolvedModuleRef =
  case def.kind:
  of RFDK_NATIVE: def.native.def.returns
  of RFDK_USER: def.user.returns

proc generic_impls(def: ResolvedFunctionDefinition): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  case def.kind:
  of RFDK_NATIVE: def.native.def.generic_impls
  of RFDK_USER: def.user.generic_impls

proc asl(def: ResolvedFunctionDefinition): string =
  case def.kind:
  of RFDK_NATIVE: def.native.def.asl
  of RFDK_USER: def.user.asl

proc c_name(def: ResolvedFunctionDefinition): string =
  case def.kind:
  of RFDK_NATIVE: def.native.native
  of RFDK_USER: def.user.c_name

type
  ResolvedFunctionRefKind = enum
    RFRK_LOCAL, RFRK_MODULE
  ResolvedFunctionRef = ref object of RootObj
    name: Identifier
    concrete_defs: seq[ResolvedFunctionDefinition]
    original_defs: seq[ResolvedFunctionDefinition]
    case kind: ResolvedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: module_ref: ResolvedModuleRef

proc new_resolved_function_ref(name: Identifier, original_defs: seq[
    ResolvedFunctionDefinition], concrete_defs: seq[
    ResolvedFunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_LOCAL, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc new_resolved_function_ref(module_ref: ResolvedModuleRef, name: Identifier,
    original_defs: seq[ResolvedFunctionDefinition], concrete_defs: seq[
    ResolvedFunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, module_ref: module_ref, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc location(fnref: ResolvedFunctionRef): Location =
  fnref.location

proc defs(fnref: ResolvedFunctionRef): seq[(ResolvedFunctionDefinition,
    ResolvedFunctionDefinition)] =
  zip(fnref.original_defs, fnref.concrete_defs)

proc generic_impls(fnref: ResolvedFunctionRef): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  case fnref.kind:
  of RFRK_LOCAL: discard
  of RFRK_MODULE: impl_set = impl_set.merge(fnref.module_ref.generic_impls)
  return impl_set

proc asl(fnref: ResolvedFunctionRef): string =
  case fnref.kind:
  of RFRK_LOCAL: fmt"{fnref.name.asl}"
  of RFRK_MODULE: fmt"{fnref.module_ref.asl}.{fnref.name.asl}"

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, fnref: TypedFunctionRef): Result[
    ResolvedFunctionRef, string] =
  case fnref.kind:
  of TFRK_LOCAL:
    let resolved_user_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    let resolved_function_defs = resolved_user_function_defs.map_it(
        new_resolved_function_definition(it))
    ok(new_resolved_function_ref(fnref.name, resolved_function_defs,
        resolved_function_defs))
  of TFRK_MODULE:
    let typed_module_ref = ? fnref.module_ref
    let resolved_module_ref = ? resolve_def(file_def.file, module_def.module, typed_module_ref)
    case resolved_module_ref.kind:
    of RMRK_NATIVE:
      let typed_native_module = resolved_module_ref.native_module
      let resolved_native_module_def = ? file_def.find_module_def(typed_native_module)
      let resolved_native_function_defs = ? resolved_native_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_native_function_defs.map_it(
        new_resolved_function_definition(it))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs, resolved_function_defs))
    of RMRK_GENERIC:
      let typed_generic = resolved_module_ref.generic
      let resolved_generic = ? module_def.find_generic(typed_generic)
      let resolved_user_function_defs = ? resolved_generic.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_user_function_defs.map_it(
        new_resolved_function_definition(it))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs, resolved_function_defs))
    of RMRK_USER:
      let typed_user_module = resolved_module_ref.user_module
      let resolved_user_module_def = ? file_def.find_module_def(typed_user_module)
      let resolved_user_function_defs = ? resolved_user_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_user_function_defs.map_it(
          new_resolved_function_definition(it))
      let concrete_function_defs = resolved_user_function_defs.map_it(
          it.concretize(resolved_module_ref.concrete_map))
      let resolved_concrete_function_defs = concrete_function_defs.map_it(
          new_resolved_function_definition(it))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs, resolved_concrete_function_defs))

proc resolve(file_def: ResolvedFileDefinition, fnref: TypedFunctionRef): Result[
    ResolvedFunctionRef, string] =
  case fnref.kind:
  of TFRK_LOCAL:
    let resolved_user_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    let resolved_function_defs = resolved_user_function_defs.map_it(
        new_resolved_function_definition(it))
    ok(new_resolved_function_ref(fnref.name, resolved_function_defs,
        resolved_function_defs))
  of TFRK_MODULE:
    let typed_module_ref = ? fnref.module_ref
    let resolved_module_ref = ? resolve_def(file_def.file, typed_module_ref)
    case resolved_module_ref.kind:
    of RMRK_GENERIC:
      err("{fnref.location} local function calls do not support generics")
    of RMRK_NATIVE:
      let typed_native_module = resolved_module_ref.native_module
      let resolved_native_module_def = ? file_def.find_module_def(typed_native_module)
      let resolved_native_function_defs = ? resolved_native_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_native_function_defs.map_it(
        new_resolved_function_definition(it))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs, resolved_function_defs))
    of RMRK_USER:
      let typed_user_module = resolved_module_ref.user_module
      let resolved_user_module_def = ? file_def.find_module_def(typed_user_module)
      let resolved_user_function_defs = ? resolved_user_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_user_function_defs.map_it(
          new_resolved_function_definition(it))
      var concrete_function_defs = resolved_user_function_defs.map_it(
          it.concretize(resolved_module_ref.concrete_map))
      let resolved_concrete_function_defs = concrete_function_defs.map_it(
          new_resolved_function_definition(it))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs, resolved_concrete_function_defs))

type
  ResolvedArgumentKind = enum
    RAK_VARIABLE, RAK_LITERAL
  ResolvedArgument = ref object of RootObj
    module_ref: ResolvedModuleRef
    case kind: ResolvedArgumentKind
    of RAK_LITERAL: literal: Literal
    of RAK_VARIABLE: variable: Identifier

proc new_resolved_argument(module_ref: ResolvedModuleRef,
    variable: Identifier): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, module_ref: module_ref,
      variable: variable)

proc new_resolved_argument(module_ref: ResolvedModuleRef,
    literal: Literal): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, module_ref: module_ref, literal: literal)

proc location(arg: ResolvedArgument): Location =
  case arg.kind:
  of RAK_LITERAL: arg.literal.location
  of RAK_VARIABLE: arg.variable.location

proc generic_impls(arg: ResolvedArgument): Table[TypedUserModule, seq[HashSet[
    TypedModule]]] =
  arg.module_ref.generic_impls

proc asl(arg: ResolvedArgument): string =
  case arg.kind:
  of RAK_LITERAL: arg.literal.asl
  of RAK_VARIABLE: arg.variable.asl

proc c(arg: ResolvedArgument): string = arg.asl

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope, args: seq[
    Argument], argdefs: seq[ResolvedArgumentDefinition]): Result[seq[
    ResolvedArgument], string] =
  var resolved_args: seq[ResolvedArgument]
  for (arg, def) in zip(args, argdefs):
    case arg.kind:
    of AK_VARIABLE:
      let variable = ? arg.variable
      let arg_module_ref = ? scope.get(variable)
      if arg_module_ref != def.module_ref:
        return err(fmt"{arg.location} expected `{variable.asl}` to be of type `{def.module_ref.asl}` but found `{arg_module_ref.asl}`")
      resolved_args.add(new_resolved_argument(arg_module_ref, variable))
    of AK_LITERAL:
      let literal = ? arg.literal
      case def.module_ref.kind:
      of RMRK_NATIVE:
        let native_module = def.module_ref.native_module
        ? native_module.validate(literal)
        resolved_args.add(new_resolved_argument(def.module_ref, literal))
      else:
        return err(fmt"{literal.location} module `{def.module_ref.asl}` does not support literals")
  ok(resolved_args)

type ResolvedFunctionCall = ref object of RootObj
  fnref: ResolvedFunctionRef
  concrete_def: ResolvedFunctionDefinition
  original_def: ResolvedFunctionDefinition
  args: seq[ResolvedArgument]

proc new_resolved_function_call(fnref: ResolvedFunctionRef,
    original_def: ResolvedFunctionDefinition,
        concrete_def: ResolvedFunctionDefinition,
    args: seq[ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fnref: fnref, original_def: original_def,
      concrete_def: concrete_def, args: args)

proc location(fncall: ResolvedFunctionCall): Location =
  fncall.fnref.location

proc returns(fncall: ResolvedFunctionCall): ResolvedModuleRef =
  fncall.concrete_def.returns

proc generic_impls(fncall: ResolvedFunctionCall): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(fncall.fnref.generic_impls)
  impl_set = impl_set.merge(fncall.concrete_def.generic_impls)
  for arg in fncall.args: impl_set = impl_set.merge(arg.generic_impls)
  return impl_set

proc asl(fncall: ResolvedFunctionCall): string =
  let args_str = fncall.args.map_it(it.asl).join(", ")
  fncall.fnref.asl & "(" & args_str & ")"

proc c(fncall: ResolvedFunctionCall, result_arg: string): seq[string] =
  var lines: seq[string]
  case fncall.fnref.kind:
  of RFRK_LOCAL:
    let args = fncall.args.map_it(it.c).join(", ")
    lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args});")
  of RFRK_MODULE:
    let module_ref = fncall.fnref.module_ref
    case module_ref.kind:
    of RMRK_GENERIC:
      let args = fncall.args.map_it(it.c).join(", ")
      let impl_id = fmt"__asl_impl_id_{module_ref.generic.id}"
      lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({impl_id}, {args});")
    of RMRK_NATIVE:
      let args = fncall.args.map_it(it.c).join(", ")
      lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args});")
    of RMRK_USER:
      var new_args: seq[string]
      for child in module_ref.children:
        case child.kind:
        of RMRK_GENERIC:
          new_args.add(fmt"__asl_impl_id_{child.generic.id}")
        of RMRK_NATIVE:
          let arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          lines.add(fmt"U64 {arg} = {child.native_module.id};")
          new_args.add(arg)
        of RMRK_USER:
          let arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          lines.add(fmt"U64 {arg} = {child.user_module.id};")
          new_args.add(arg)

      for index in 0..<fncall.args.len:
        let original_def = fncall.original_def.args[index]
        let concrete_def = fncall.concrete_def.args[index]
        let arg = fncall.args[index]

        case original_def.module_ref.kind:
        of RMRK_GENERIC:
          case concrete_def.module_ref.kind:
          of RMRK_GENERIC: new_args.add(arg.asl)
          else:
            let arg_name = fmt"__asl_arg_{arg.location.hash.to_hex}"
            lines.add(fmt"Pointer {arg_name} = System_box_{concrete_def.module_ref.c}({arg.c});")
            new_args.add(arg_name)
        else: new_args.add(arg.asl)

      let args_str = new_args.join(", ")
      case fncall.original_def.returns.kind:
      of RMRK_GENERIC:
        case fncall.concrete_def.returns.kind:
        of RMRK_GENERIC:
          lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args_str});")
        else:
          let arg_name = fmt"__asl_arg_{fncall.location.hash.to_hex}"
          lines.add(fmt"{fncall.original_def.returns.c} {arg_name} = {fncall.original_def.c_name}({args_str});")
          lines.add(fmt"{fncall.concrete_def.returns.c} {result_arg} = {fncall.concrete_def.returns.c}_read({arg_name}, 0);")
      else:
        lines.add(fmt"{fncall.original_def.returns.c} {result_arg} = {fncall.original_def.c_name}({args_str});")

  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    fncall: TypedFunctionCall): Result[ResolvedFunctionCall, string] =
  let resolved_function_ref = ? resolve(file_def, module_def, fncall.fnref)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for (original_def, concrete_def) in resolved_function_ref.defs:
    let maybe_resolved_args = resolve(file_def, scope,
        fncall.args, concrete_def.args)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(resolved_function_ref, original_def,
          concrete_def, maybe_resolved_args.get))
    error_message.add(concrete_def.asl)
  err(error_message.join("\n"))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    fncall: TypedFunctionCall): Result[ResolvedFunctionCall, string] =
  let resolved_function_ref = ? resolve(file_def, fncall.fnref)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for (original_def, concrete_def) in resolved_function_ref.defs:
    let maybe_resolved_args = resolve(file_def, scope, fncall.args,
        concrete_def.args)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(resolved_function_ref, original_def,
          concrete_def, maybe_resolved_args.get))
    error_message.add(concrete_def.asl)
  err(error_message.join("\n"))

type ResolvedStructRef = ref object of RootObj
  module_ref: ResolvedModuleRef
  origin: ResolvedStruct
  struct: ResolvedStruct

proc new_resolved_struct_ref(module_ref: ResolvedModuleRef,
    origin: ResolvedStruct, struct: ResolvedStruct): ResolvedStructRef =
  ResolvedStructRef(module_ref: module_ref, origin: origin, struct: struct)

proc generic_impls(struct_ref: ResolvedStructRef): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  struct_ref.module_ref.generic_impls

proc asl(struct_ref: ResolvedStructRef): string =
  let suffix =
    case struct_ref.struct.kind:
    of RSK_DEFAULT: ""
    of RSK_NAMED: fmt".{struct_ref.struct.name.asl}"
  fmt"{struct_ref.module_ref.asl}{suffix}"

proc c(struct_ref: ResolvedStructRef): string =
  case struct_ref.struct.kind:
  of RSK_DEFAULT: fmt"{struct_ref.module_ref.name}"
  of RSK_NAMED: fmt"{struct_ref.module_ref.name}_{struct_ref.struct.name.asl}"

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    struct_ref: TypedStructRef): Result[ResolvedStructRef, string] =
  let resolved_module_ref = ? resolve_def(file_def.file, module_def.module,
      struct_ref.module_ref)
  case resolved_module_ref.kind:
  of RMRK_NATIVE:
    err(fmt"{struct_ref.location} native module `{resolved_module_ref.native_module.name.asl}` is not a struct")
  of RMRK_GENERIC:
    err(fmt"{struct_ref.location} generic `{resolved_module_ref.generic.name.asl}` is not a struct")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = resolved_module_def.find_struct()
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref, resolved_struct,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a default struct")
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = resolved_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref, resolved_struct,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a struct named `{struct_name.asl}`")

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    struct_ref: TypedStructRef): Result[ResolvedStructRef, string] =
  let resolved_module_ref = ? resolve_def(file_def.file, struct_ref.module_ref)
  case resolved_module_ref.kind:
  of RMRK_NATIVE:
    err(fmt"{struct_ref.location} native module `{resolved_module_ref.native_module.name.asl}` is not a struct")
  of RMRK_GENERIC:
    err(fmt"{struct_ref.location} generic `{resolved_module_ref.generic.name.asl}` is not a struct")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = resolved_module_def.find_struct()
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref, resolved_struct,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a default struct")
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = resolved_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref, resolved_struct,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a struct named `{struct_name.asl}`")

type ResolvedStructInit = ref object of RootObj
  struct_ref: ResolvedStructRef
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init(struct_ref: ResolvedStructRef, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(struct_ref: struct_ref, fields: fields)

proc returns(struct_init: ResolvedStructInit): ResolvedModuleRef =
  struct_init.struct_ref.module_ref

proc generic_impls(struct_init: ResolvedStructInit): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(struct_init.struct_ref.generic_impls)
  for field in struct_init.fields: impl_set = impl_set.merge(
      field.generic_impls)
  return impl_set

proc asl(struct_init: ResolvedStructInit): string =
  var args: seq[string]
  for (field_def, field_arg) in zip(struct_init.struct_ref.struct.fields,
      struct_init.fields):
    args.add(fmt"{field_def.name.asl}: {field_arg.asl}")
  let args_str = args.join(", ")
  struct_init.struct_ref.asl & " { " & args_str & " }"

proc c(struct_init: ResolvedStructInit, result_arg: string): seq[string] =
  var lines: seq[string]
  var args: seq[string]
  for index in 0..<struct_init.fields.len:
    let original_field = struct_init.struct_ref.origin.fields[index]
    let concrete_field = struct_init.struct_ref.struct.fields[index]
    let arg = struct_init.fields[index]
    case original_field.module_ref.kind:
    of RMRK_GENERIC:
      case concrete_field.module_ref.kind:
      of RMRK_GENERIC: args.add(arg.c)
      else:
        let arg_name = fmt"__asl_arg_{concrete_field.location.hash.to_hex}"
        lines.add(fmt"Pointer {arg_name} = System_box_{concrete_field.module_ref.c}({arg.c});")
        args.add(arg_name)
    else: args.add(arg.c)

  let args_str = args.join(", ")
  lines.add(fmt"Pointer {result_arg} = {struct_init.struct_ref.c}_init({args_str});")
  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    init: TypedStructInit): Result[ResolvedStructInit, string] =
  let resolved_struct_ref = ? resolve(file_def, module_def, scope,
      init.struct_ref)

  var args = new_seq[Argument](resolved_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let resolved_field_index = ? resolved_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(resolved_field_index)
    args[resolved_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < resolved_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let resolved_fields = ? resolve(file_def, scope, args,
      resolved_struct_ref.struct.fields)
  ok(new_resolved_struct_init(resolved_struct_ref, resolved_fields))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    init: TypedStructInit): Result[ResolvedStructInit, string] =
  let resolved_struct_ref = ? resolve(file_def, scope, init.struct_ref)

  var args = new_seq[Argument](resolved_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let resolved_field_index = ? resolved_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(resolved_field_index)
    args[resolved_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < resolved_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let resolved_fields = ? resolve(file_def, scope, args,
      resolved_struct_ref.struct.fields)
  ok(new_resolved_struct_init(resolved_struct_ref, resolved_fields))

type ResolvedLiteral = ref object of RootObj
  module_ref: ResolvedModuleRef
  literal: Literal

proc new_resolved_literal(module_ref: ResolvedModuleRef,
    literal: Literal): ResolvedLiteral =
  ResolvedLiteral(module_ref: module_ref, literal: literal)

proc returns(literal: ResolvedLiteral): ResolvedModuleRef =
  literal.module_ref

proc generic_impls(literal: ResolvedLiteral): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  literal.module_ref.generic_impls

proc asl(literal: ResolvedLiteral): string =
  fmt"{literal.module_ref.asl} {literal.literal.asl}"

proc c(literal: ResolvedLiteral, result_arg: string): string =
  fmt"{literal.module_ref.c} {result_arg} = {literal.literal.asl};"

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
        init: TypedLiteralInit): Result[ResolvedLiteral, string] =
  let resolved_module_ref = ? resolve_def(file_def.file, module_def.module,
      init.module_ref)
  case resolved_module_ref.kind:
  of RMRK_GENERIC: err(fmt"{init.location} Generics are not supported via literal initialization")
  of RMRK_USER: err("{init.location} User modules can not be used to initialize literals")
  of RMRK_NATIVE:
    let native_module = resolved_module_ref.native_module
    ? native_module.validate(init.literal)
    ok(new_resolved_literal(resolved_module_ref, init.literal))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    init: TypedLiteralInit): Result[ResolvedLiteral, string] =
  let resolved_module_ref = ? resolve_def(file_def.file, init.module_ref)
  case resolved_module_ref.kind:
  of RMRK_GENERIC: err(fmt"{init.location} Generics are not supported via literal initialization")
  of RMRK_USER: err("{init.location} User modules can not be used to initialize literals")
  of RMRK_NATIVE:
    let native_module = resolved_module_ref.native_module
    ? native_module.validate(init.literal)
    ok(new_resolved_literal(resolved_module_ref, init.literal))

type
  ResolvedInitializerKind = enum
    RIK_LITERAL, RIK_STRUCT
  ResolvedInitializer = ref object of RootObj
    case kind: ResolvedInitializerKind
    of RIK_LITERAL: literal: ResolvedLiteral
    of RIK_STRUCT: struct: ResolvedStructInit

proc new_resolved_initializer(struct: ResolvedStructInit): ResolvedInitializer =
  ResolvedInitializer(kind: RIK_STRUCT, struct: struct)

proc new_resolved_initializer(literal: ResolvedLiteral): ResolvedInitializer =
  ResolvedInitializer(kind: RIK_LITERAL, literal: literal)

proc returns(init: ResolvedInitializer): ResolvedModuleRef =
  case init.kind:
  of RIK_STRUCT: init.struct.returns
  of RIK_LITERAL: init.literal.returns

proc generic_impls(init: ResolvedInitializer): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  case init.kind:
  of RIK_LITERAL: init.literal.generic_impls
  of RIK_STRUCT: init.struct.generic_impls

proc asl(init: ResolvedInitializer): string =
  case init.kind:
  of RIK_LITERAL: init.literal.asl
  of RIK_STRUCT: init.struct.asl

proc c(init: ResolvedInitializer, result_arg: string): seq[string] =
  case init.kind:
  of RIK_LITERAL: @[init.literal.c(result_arg)]
  of RIK_STRUCT: init.struct.c(result_arg)

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    init: TypedInitializer): Result[ResolvedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let resolved_struct_init = ? resolve(file_def, module_def, scope, struct_init)
    ok(new_resolved_initializer(resolved_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let resolved_literal = ? resolve(file_def, module_def, scope, literal_init)
    ok(new_resolved_initializer(resolved_literal))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    init: TypedInitializer): Result[ResolvedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let resolved_struct_init = ? resolve(file_def, scope, struct_init)
    ok(new_resolved_initializer(resolved_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let resolved_literal = ? resolve(file_def, scope, literal_init)
    ok(new_resolved_initializer(resolved_literal))

type ResolvedStructGet = ref object of RootObj
  variable: ResolvedArgumentDefinition
  field: ResolvedArgumentDefinition

proc new_resolved_struct_get(variable: ResolvedArgumentDefinition,
    field: ResolvedArgumentDefinition): ResolvedStructGet =
  ResolvedStructGet(variable: variable, field: field)

proc returns(struct_get: ResolvedStructGet): ResolvedModuleRef =
  struct_get.field.module_ref

proc generic_impls(struct_get: ResolvedStructGet): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(struct_get.variable.generic_impls)
  impl_set = impl_set.merge(struct_get.field.generic_impls)
  return impl_set

proc asl(struct_get: ResolvedStructGet): string =
  fmt"{struct_get.variable.name.asl}.{struct_get.field.name.asl}"

proc c(struct_get: ResolvedStructGet, result_arg: string): string =
  fmt"{struct_get.field.module_ref.c} {result_arg} = {struct_get.variable.module_ref.name}_get_{struct_get.field.name.asl}({struct_get.variable.name.asl});"

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    struct_get: TypedStructGet): Result[ResolvedStructGet, string] =
  let resolved_module_ref = ? scope.get(struct_get.variable)
  let resolved_variable = new_resolved_argument_definition(resolved_module_ref,
      struct_get.variable)
  case resolved_module_ref.kind:
  of RMRK_NATIVE: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but native module")
  of RMRK_GENERIC: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    if resolved_module_def.structs.len == 0:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is not a struct")
    elif resolved_module_def.structs.len > 1:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is a union")
    else:
      let maybe_default_struct = resolved_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` does not have a default struct")
      else:
        let resolved_struct = maybe_default_struct.get
        let resolved_field_module_ref = ? resolved_struct.find_field(
            struct_get.field)
        let resolved_field = resolved_field_module_ref.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_get(resolved_variable, resolved_field))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    struct_get: TypedStructGet): Result[ResolvedStructGet, string] =
  let resolved_module_ref = ? scope.get(struct_get.variable)
  let resolved_variable = new_resolved_argument_definition(resolved_module_ref,
      struct_get.variable)
  case resolved_module_ref.kind:
  of RMRK_NATIVE: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but native module")
  of RMRK_GENERIC: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    if resolved_module_def.structs.len == 0:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is not a struct")
    elif resolved_module_def.structs.len > 1:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is a union")
    else:
      let maybe_default_struct = resolved_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` does not have a default struct")
      else:
        let resolved_struct = maybe_default_struct.get
        let resolved_field_module_ref = ? resolved_struct.find_field(
            struct_get.field)
        let resolved_field = resolved_field_module_ref.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_get(resolved_variable, resolved_field))

type
  ResolvedStructPatternKind = enum
    RSPK_DEFAULT, RSPK_NAMED
  ResolvedStructPattern = ref object of RootObj
    original_struct: ResolvedStruct
    args: seq[(ResolvedArgumentDefinition, Identifier)]
    location: Location
    case kind: ResolvedStructPatternKind
    of RSPK_DEFAULT: discard
    of RSPK_NAMED: name: Identifier

proc new_resolved_struct_pattern(original_struct: ResolvedStruct, args: seq[(
    ResolvedArgumentDefinition, Identifier)],
    location: Location): ResolvedStructPattern =
  ResolvedStructPattern(kind: RSPK_DEFAULT, original_struct: original_struct,
      args: args, location: location)

proc new_resolved_struct_pattern(original_struct: ResolvedStruct,
    name: Identifier, args: seq[(ResolvedArgumentDefinition, Identifier)],
    location: Location): ResolvedStructPattern =
  ResolvedStructPattern(kind: RSPK_NAMED, original_struct: original_struct,
      name: name, args: args, location: location)

proc id(pattern: ResolvedStructPattern): uint64 =
  pattern.original_struct.id

proc hash(pattern: ResolvedStructPattern): Hash =
  case pattern.kind:
  of RSPK_DEFAULT: "".hash
  of RSPK_NAMED: pattern.name.asl.hash

proc generic_impls(pattern: ResolvedStructPattern): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for (argdef, _) in pattern.args: impl_set = impl_set.merge(
      argdef.generic_impls)
  return impl_set

proc asl(struct_pattern: ResolvedStructPattern): string =
  let prefix =
    case struct_pattern.kind:
    of RSPK_DEFAULT: ""
    of RSPK_NAMED: fmt"{struct_pattern.name.asl} "

  var args: seq[string]
  for (field, name) in struct_pattern.args:
    args.add(fmt"{name.asl}: {field.name.asl}")

  let args_str = args.join(", ")
  prefix & "{ " & args_str & " }"

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    operand: ResolvedModuleRef, pattern: StructPattern): Result[
    ResolvedStructPattern, string] =
  case operand.kind:
  of RMRK_GENERIC: err(fmt"{pattern.location} match expression does not support generics")
  of RMRK_NATIVE: err(fmt"{pattern.location} match expression does not support native module in struct pattern matching")
  of RMRK_USER:
    let user_module = operand.user_module
    let resolved_operand_module = ? file_def.find_module_def(user_module)
    if resolved_operand_module.structs.len == 0:
      return err(fmt"{pattern.location} module `{resolved_operand_module.name.asl}` is a module and not a union")
    if resolved_operand_module.structs.len == 1:
      return err(fmt"{pattern.location} module `{resolved_operand_module.name.asl}` is a struct and not a union")

    case pattern.kind:
    of SPK_DEFAULT:
      let resolved_struct = ? resolved_operand_module.find_struct()
      let concrete_struct = resolved_struct.concretize(operand.concrete_map)
      var resolved_fields: seq[(ResolvedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_resolved_argument_definition(field.module_ref, value)
        resolved_fields.add((value_arg, key))
      ok(new_resolved_struct_pattern(resolved_struct, resolved_fields,
          pattern.location))
    of SPK_NAMED:
      let struct_name = ? pattern.struct
      let resolved_struct = ? resolved_operand_module.find_struct(struct_name)
      let concrete_struct = resolved_struct.concretize(operand.concrete_map)
      var resolved_fields: seq[(ResolvedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_resolved_argument_definition(field.module_ref, value)
        resolved_fields.add((value_arg, key))
      ok(new_resolved_struct_pattern(resolved_struct, struct_name,
          resolved_fields, pattern.location))

type
  ResolvedCasePatternKind = enum
    RCPK_LITERAL, RCPK_STRUCT
  ResolvedCasePattern = ref object of RootObj
    location: Location
    case kind: ResolvedCasePatternKind
    of RCPK_LITERAL:
      native_module: TypedNativeModule
      literal: Literal
    of RCPK_STRUCT:
      struct: ResolvedStructPattern

proc new_resolved_case_pattern(native_module: TypedNativeModule,
    literal: Literal, location: Location): ResolvedCasePattern =
  ResolvedCasePattern(kind: RCPK_LITERAL, native_module: native_module,
      literal: literal, location: location)

proc new_resolved_case_pattern(struct: ResolvedStructPattern,
    location: Location): ResolvedCasePattern =
  ResolvedCasePattern(kind: RCPK_STRUCT, struct: struct, location: location)

proc hash(pattern: ResolvedCasePattern): Hash =
  case pattern.kind:
  of RCPK_LITERAL: pattern.literal.asl.hash
  of RCPK_STRUCT: pattern.struct.hash

proc `==`(self: ResolvedCasePattern, other: ResolvedCasePattern): bool =
  self.hash == other.hash

proc generic_impls(pattern: ResolvedCasePattern): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  case pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT: impl_set = impl_set.merge(pattern.struct.generic_impls)
  return impl_set

proc asl(case_pattern: ResolvedCasePattern): string =
  case case_pattern.kind:
  of RCPK_LITERAL: case_pattern.literal.asl
  of RCPK_STRUCT: case_pattern.struct.asl

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    operand: ResolvedModuleRef, pattern: CasePattern): Result[
    ResolvedCasePattern, string] =
  case pattern.kind:
  of CPK_LITERAL:
    let literal = ? pattern.literal
    case operand.kind:
    of RMRK_GENERIC:
      err(fmt"{pattern.location} match expression does not support generic operands")
    of RMRK_USER:
      err(fmt"{pattern.location} expected a struct pattern but found literal")
    of RMRK_NATIVE:
      let native_module = operand.native_module
      case native_module.name.asl:
      of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64":
        ? native_module.validate(literal)
        ok(new_resolved_case_pattern(native_module, literal, pattern.location))
      else:
        err(fmt"{pattern.location} only integer literals are supported in the case pattern")
  of CPK_STRUCT:
    let struct = ? pattern.struct
    let resolved_struct_pattern = ? resolve(file_def, scope, operand, struct)
    ok(new_resolved_case_pattern(resolved_struct_pattern, pattern.location))

proc resolve(scope: FunctionScope, variable: TypedVariable): Result[
    ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? scope.get(variable.name)
  ok(new_resolved_argument_definition(resolved_module_ref, variable.name,
      variable.location))

type
  ResolvedExpressionKind = enum
    REK_MATCH, REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  ResolvedExpression = ref object of RootObj
    case kind: ResolvedExpressionKind
    of REK_MATCH: match: ResolvedMatch
    of REK_FNCALL: fncall: ResolvedFunctionCall
    of REK_INIT: init: ResolvedInitializer
    of REK_STRUCT_GET: struct_get: ResolvedStructGet
    of REK_VARIABLE: variable: ResolvedArgumentDefinition
  ResolvedStatement = ref object of RootObj
    arg: ResolvedArgumentDefinition
    expression: ResolvedExpression
  ResolvedCase = ref object of RootObj
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]
    location: Location
  ResolvedElse = ref object of RootObj
    location: Location
    statements: seq[ResolvedStatement]
  ResolvedMatchKind = enum
    RMK_CASE_ONLY, RMK_COMPLETE
  ResolvedMatch = ref object of RootObj
    location: Location
    operand: ResolvedArgumentDefinition
    case_blocks: seq[ResolvedCase]
    case kind: ResolvedMatchKind
    of RMK_CASE_ONLY: discard
    of RMK_COMPLETE: else_block: ResolvedElse

proc new_resolved_expression(match: ResolvedMatch): ResolvedExpression =
  ResolvedExpression(kind: REK_MATCH, match: match)

proc new_resolved_expression(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FNCALL, fncall: fncall)

proc new_resolved_expression(init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: REK_INIT, init: init)

proc new_resolved_expression(struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GET, struct_get: struct_get)

proc new_resolved_expression(variable: ResolvedArgumentDefinition): ResolvedExpression =
  ResolvedExpression(kind: REK_VARIABLE, variable: variable)

proc returns(match: ResolvedMatch): ResolvedModuleRef

proc returns(expression: ResolvedExpression): ResolvedModuleRef =
  case expression.kind:
  of REK_MATCH: expression.match.returns
  of REK_FNCALL: expression.fncall.returns
  of REK_INIT: expression.init.returns
  of REK_STRUCT_GET: expression.struct_get.returns
  of REK_VARIABLE: expression.variable.module_ref

proc generic_impls(match: ResolvedMatch): Table[TypedUserModule, seq[HashSet[
    TypedModule]]]

proc generic_impls(expression: ResolvedExpression): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  case expression.kind:
  of REK_MATCH: expression.match.generic_impls
  of REK_FNCALL: expression.fncall.generic_impls
  of REK_INIT: expression.init.generic_impls
  of REK_STRUCT_GET: expression.struct_get.generic_impls
  of REK_VARIABLE: expression.variable.generic_impls

proc asl(match: ResolvedMatch, indent: string): seq[string]

proc asl(expression: ResolvedExpression, indent: string): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.asl(indent)
  of REK_FNCALL: @[expression.fncall.asl]
  of REK_INIT: @[expression.init.asl]
  of REK_STRUCT_GET: @[expression.struct_get.asl]
  of REK_VARIABLE: @[expression.variable.asl]

proc c(match: ResolvedMatch, result_arg: ResolvedArgumentDefinition): seq[string]

proc c(expression: ResolvedExpression, result_arg: ResolvedArgumentDefinition): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.c(result_arg)
  of REK_FNCALL: expression.fncall.c(result_arg.name.asl)
  of REK_INIT: expression.init.c(result_arg.name.asl)
  of REK_STRUCT_GET: @[expression.struct_get.c(result_arg.name.asl)]
  of REK_VARIABLE: @[fmt"{expression.variable.module_ref.c} {result_arg.name.asl} = {expression.variable.name.asl};"]

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    match: TypedMatch): Result[ResolvedMatch, string]

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    expression: TypedExpression): Result[ResolvedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let resolved_function_call = ? resolve(file_def, module_def, scope, fncall)
    ok(new_resolved_expression(resolved_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let resolved_init = ? resolve(file_def, module_def, scope, init)
    ok(new_resolved_expression(resolved_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let resolved_struct_get = ? resolve(file_def, module_def, scope, struct_get)
    ok(new_resolved_expression(resolved_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let resolved_variable = ? resolve(scope, variable)
    ok(new_resolved_expression(resolved_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let resolved_match = ? resolve(file_def, module_def, scope, match)
    ok(new_resolved_expression(resolved_match))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    match: TypedMatch): Result[ResolvedMatch, string]

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    expression: TypedExpression): Result[ResolvedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let resolved_function_call = ? resolve(file_def, scope, fncall)
    ok(new_resolved_expression(resolved_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let resolved_init = ? resolve(file_def, scope, init)
    ok(new_resolved_expression(resolved_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let resolved_struct_get = ? resolve(file_def, scope, struct_get)
    ok(new_resolved_expression(resolved_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let resolved_variable = ? resolve(scope, variable)
    ok(new_resolved_expression(resolved_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let resolved_match = ? resolve(file_def, scope, match)
    ok(new_resolved_expression(resolved_match))

# Statement
proc new_resolved_statement(arg: ResolvedArgumentDefinition,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(arg: arg, expression: expression)

proc returns(statement: ResolvedStatement): ResolvedModuleRef =
  statement.expression.returns

proc generic_impls(statement: ResolvedStatement): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] = statement.expression.generic_impls

proc asl(statement: ResolvedStatement, indent: string): seq[string] =
  var lines = statement.expression.asl(indent)
  lines[0] = fmt"{statement.arg.asl} = {lines[0]}"
  lines

proc c(statement: ResolvedStatement): seq[string] =
  statement.expression.c(statement.arg)

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    statement: TypedStatement): Result[ResolvedStatement, string] =
  let resolved_expression = ? resolve(file_def, module_def, scope,
      statement.expression)
  let resolved_arg = new_resolved_argument_definition(
      resolved_expression.returns, statement.arg)
  ok(new_resolved_statement(resolved_arg, resolved_expression))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    statement: TypedStatement): Result[ResolvedStatement, string] =
  let resolved_expression = ? resolve(file_def, scope, statement.expression)
  let resolved_arg = new_resolved_argument_definition(
      resolved_expression.returns, statement.arg)
  ok(new_resolved_statement(resolved_arg, resolved_expression))

# Case
proc new_resolved_case(pattern: ResolvedCasePattern, statements: seq[
    ResolvedStatement], location: Location): ResolvedCase =
  ResolvedCase(pattern: pattern, statements: statements, location: location)

proc returns(case_block: ResolvedCase): ResolvedModuleRef =
  case_block.statements[^1].returns

proc generic_impls(case_block: ResolvedCase): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(case_block.pattern.generic_impls)
  for statement in case_block.statements:
    impl_set = impl_set.merge(statement.generic_impls)
  return impl_set

proc asl(case_block: ResolvedCase, indent: string): seq[string] =
  var lines = @[fmt"case {case_block.pattern.asl}:"]
  for statement in case_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  lines

proc c(case_block: ResolvedCase, operand: ResolvedArgumentDefinition,
    result_arg: string, first: bool = false): seq[string] =
  var lines: seq[string]
  let conditional = if first: "if" else: "else if"
  case case_block.pattern.kind:
  of RCPK_LITERAL:
    let literal = case_block.pattern.literal
    case literal.kind:
    of LK_FLOAT: discard # UNREACHABLE
    of LK_INTEGER:
      lines.add(fmt"{conditional}({operand.name.asl} == {literal.asl})")
      lines.add("{")
    of LK_STRING:
      lines.add(fmt"{conditional}(String_compare({operand.name.asl}, {literal.asl}) == 0)")
      lines.add("{")
  of RCPK_STRUCT:
    let struct = case_block.pattern.struct
    let id_call = fmt"{operand.module_ref.name}_get_id({operand.name.asl})"
    lines.add(fmt"{conditional}({id_call} == {struct.id})")
    lines.add("{")

    let prefix =
      case struct.kind:
      of RSPK_DEFAULT: operand.module_ref.name
      of RSPK_NAMED: fmt"{operand.module_ref.name}_{struct.name.asl}"

    for index in 0..<struct.args.len:
      let field = struct.args[index][0]
      let key = struct.args[index][1]
      let original_field = struct.original_struct.fields[index]

      case original_field.module_ref.kind:
      of RMRK_GENERIC:
        case field.module_ref.kind:
        of RMRK_GENERIC:
          lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
        else:
          let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
          lines.add(fmt"{original_field.module_ref.c} {arg_name} = {prefix}_get_{key.asl}({operand.name.asl});")
          lines.add(fmt"{field.c} = {field.module_ref.c}_read({arg_name}, 0);")
      else:
        lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")

  for statement in case_block.statements:
    lines.add(statement.c)
  let last_statement = case_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_statement};")
  lines.add("}")

  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    operand: ResolvedModuleRef, case_block: TypedCase): Result[ResolvedCase, string] =
  var case_scope = scope.clone()
  let resolved_case_pattern = ? resolve(file_def, scope, operand,
      case_block.pattern)

  case resolved_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let resolved_struct_pattern = resolved_case_pattern.struct
    for (field, name) in resolved_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var resolved_statements: seq[ResolvedStatement]
  for statement in case_block.statements:
    let resolved_statement = ? resolve(file_def, module_def, case_scope, statement)
    resolved_statements.add(resolved_statement)
    case_scope = ? case_scope.set(resolved_statement.arg)
  ok(new_resolved_case(resolved_case_pattern, resolved_statements,
      case_block.location))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    operand: ResolvedModuleRef, case_block: TypedCase): Result[ResolvedCase, string] =
  var case_scope = scope.clone()
  let resolved_case_pattern = ? resolve(file_def, scope, operand,
      case_block.pattern)
  case resolved_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let resolved_struct_pattern = resolved_case_pattern.struct
    for (field, name) in resolved_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var resolved_statements: seq[ResolvedStatement]
  for statement in case_block.statements:
    let resolved_statement = ? resolve(file_def, case_scope, statement)
    resolved_statements.add(resolved_statement)
    case_scope = ? case_scope.set(resolved_statement.arg)
  ok(new_resolved_case(resolved_case_pattern, resolved_statements,
      case_block.location))

# Else
proc new_resolved_else(statements: seq[ResolvedStatement],
    location: Location): ResolvedElse =
  ResolvedElse(statements: statements, location: location)

proc returns(else_block: ResolvedElse): ResolvedModuleRef =
  else_block.statements[^1].returns

proc generic_impls(else_block: ResolvedElse): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for statement in else_block.statements: impl_set = impl_set.merge(
      statement.generic_impls)
  return impl_set

proc asl(else_block: ResolvedElse, indent: string): seq[string] =
  var lines = @["else:"]
  for statement in else_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c(else_block: ResolvedElse, result_arg: string): seq[string] =
  var lines: seq[string]
  lines.add("else {")
  for statement in else_block.statements:
    lines.add(statement.c)
  let last_arg = else_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_arg};")
  lines.add("}")
  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    else_block: TypedElse): Result[ResolvedElse, string] =
  var else_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in else_block.statements:
    let resolved_statement = ? resolve(file_def, module_def, else_scope, statement)
    resolved_statements.add(resolved_statement)
    else_scope = ? else_scope.set(resolved_statement.arg)
  ok(new_resolved_else(resolved_statements, else_block.location))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    else_block: TypedElse): Result[ResolvedElse, string] =
  var else_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in else_block.statements:
    let resolved_statement = ? resolve(file_def, else_scope, statement)
    resolved_statements.add(resolved_statement)
    else_scope = ? else_scope.set(resolved_statement.arg)
  ok(new_resolved_else(resolved_statements, else_block.location))

# Match
proc new_resolved_match(operand: ResolvedArgumentDefinition, case_blocks: seq[
    ResolvedCase], else_block: ResolvedElse,
    location: Location): ResolvedMatch =
  ResolvedMatch(kind: RMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc new_resolved_match(operand: ResolvedArgumentDefinition, case_blocks: seq[
    ResolvedCase], location: Location): ResolvedMatch =
  ResolvedMatch(kind: RMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc returns(match: ResolvedMatch): ResolvedModuleRef =
  match.case_blocks[0].returns

proc generic_impls(match: ResolvedMatch): Table[TypedUserModule, seq[HashSet[
    TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  for case_block in match.case_blocks: impl_set = impl_set.merge(
      case_block.generic_impls)

  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: impl_set = impl_set.merge(match.else_block.generic_impls)
  return impl_set

proc asl(match: ResolvedMatch, indent: string): seq[string] =
  var lines = @[fmt"match {match.operand.name.asl}:"]
  for case_block in match.case_blocks:
    for line in case_block.asl(indent):
      lines.add(indent & line)

  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE:
    for line in match.else_block.asl(indent):
      lines.add(indent & line)

  lines

proc c(match: ResolvedMatch, result_arg: ResolvedArgumentDefinition): seq[string] =
  var lines: seq[string]
  lines.add(fmt"{result_arg.c};")
  for index, case_block in match.case_blocks:
    lines.add(case_block.c(match.operand, result_arg.name.asl, index == 0))
  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: lines.add(match.else_block.c(result_arg.name.asl))
  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, scope: FunctionScope,
    match: TypedMatch): Result[ResolvedMatch, string] =
  let resolved_operand_module_ref = ? scope.get(match.operand)
  let resolved_operand = new_resolved_argument_definition(
      resolved_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file_def, module_def, scope,
          resolved_operand_module_ref, case_block)
      resolved_case_blocks.add(resolved_case_block)

    var unique_patterns: Table[ResolvedCasePattern, ResolvedCase]
    for case_block in resolved_case_blocks:
      # NOTE: Ensure all the case block returns type is same.
      if case_block.returns != resolved_case_blocks[0].returns:
        return err("{case_block.location} returns `{case_block.returns.asl}` but expected `{resolved_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case resolved_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_NATIVE:
      return err(fmt"{match.location} match expression does not cover all cases, an else block is required")
    of RMRK_USER:
      let user_module = resolved_operand_module_ref.user_module
      let resolved_operand_module = ? file_def.find_module_def(user_module)
      if unique_patterns.len < resolved_operand_module.structs.len:
        return err(fmt"{match.location} match expression does not cover all cases, an else block is required")

    ok(new_resolved_match(resolved_operand, resolved_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file_def, module_def, scope,
          resolved_operand_module_ref, case_block)
      resolved_case_blocks.add(resolved_case_block)

    let else_block = ? match.else_block
    let resolved_else_block = ? resolve(file_def, module_def, scope, else_block)

    var unique_patterns: Table[ResolvedCasePattern, ResolvedCase]
    for case_block in resolved_case_blocks:
      if case_block.returns != resolved_else_block.returns:
        return err("{case_block.location} returns `{case_block.returns.asl}` but expected `{resolved_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case resolved_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_NATIVE: discard
    of RMRK_USER:
      let user_module = resolved_operand_module_ref.user_module
      let resolved_operand_module = ? file_def.find_module_def(user_module)
      if unique_patterns.len == resolved_operand_module.structs.len:
        return err(fmt"{match.location} match expression already covers all cases, else block is not required")

    ok(new_resolved_match(resolved_operand, resolved_case_blocks,
        resolved_else_block, match.location))

proc resolve(file_def: ResolvedFileDefinition, scope: FunctionScope,
    match: TypedMatch): Result[ResolvedMatch, string] =
  let resolved_operand_module_ref = ? scope.get(match.operand)
  let resolved_operand = new_resolved_argument_definition(
      resolved_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file_def, scope,
          resolved_operand_module_ref, case_block)
      resolved_case_blocks.add(resolved_case_block)

    var unique_patterns: Table[ResolvedCasePattern, ResolvedCase]
    for case_block in resolved_case_blocks:
      if case_block.returns != resolved_case_blocks[0].returns:
        return err("{case_block.location} returns `{case_block.returns.asl}` but expected `{resolved_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case resolved_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_NATIVE:
      return err(fmt"{match.location} match expression does not cover all cases, an else block is required")
    of RMRK_USER:
      let user_module = resolved_operand_module_ref.user_module
      let resolved_operand_module = ? file_def.find_module_def(user_module)
      if unique_patterns.len < resolved_operand_module.structs.len:
        return err(fmt"{match.location} match expression does not cover all cases, an else block is required")

    ok(new_resolved_match(resolved_operand, resolved_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file_def, scope,
          resolved_operand_module_ref, case_block)
      resolved_case_blocks.add(resolved_case_block)

    let else_block = ? match.else_block
    let resolved_else_block = ? resolve(file_def, scope, else_block)

    var unique_patterns: Table[ResolvedCasePattern, ResolvedCase]
    for case_block in resolved_case_blocks:
      if case_block.returns != resolved_else_block.returns:
        return err("{case_block.location} returns `{case_block.returns.asl}` but expected `{resolved_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case resolved_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_NATIVE: discard
    of RMRK_USER:
      let user_module = resolved_operand_module_ref.user_module
      let resolved_operand_module = ? file_def.find_module_def(user_module)
      if unique_patterns.len == resolved_operand_module.structs.len:
        return err(fmt"{match.location} match expression already covers all cases, else block is not required")

    ok(new_resolved_match(resolved_operand, resolved_case_blocks,
        resolved_else_block, match.location))

type ResolvedFunction = ref object of RootObj
  def: ResolvedUserFunctionDefinition
  steps: seq[ResolvedStatement]

proc new_resolved_function(def: ResolvedUserFunctionDefinition, steps: seq[
    ResolvedStatement]): ResolvedFunction =
  ResolvedFunction(def: def, steps: steps)

proc statements(function: ResolvedFunction): seq[ResolvedStatement] =
  function.steps

proc generic_impls(function: ResolvedFunction): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(function.def.generic_impls)
  for step in function.steps: impl_set = impl_set.merge(step.generic_impls)
  return impl_set

proc asl(function: ResolvedFunction, indent: string): seq[string] =
  var lines = @[function.def.asl]
  for statement in function.steps:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c(function: ResolvedFunction): seq[string] =
  var lines: seq[string]
  lines.add(function.def.c.replace(";", ""))
  lines.add("{")
  for statement in function.statements:
    lines.add(statement.c)
  let last_arg = function.statements[^1].arg.name.asl
  lines.add(fmt"return {last_arg};")
  lines.add("}")
  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition, function: TypedFunction): Result[
    ResolvedFunction, string] =
  var scope = FunctionScope()
  let resolved_function_def = ? module_def.find_function_def(function.def)
  for arg in resolved_function_def.args: scope = ? scope.set(arg)

  var resolved_steps: seq[ResolvedStatement]
  for step in function.steps:
    let resolved_function_step = ? resolve(file_def, module_def, scope, step)
    resolved_steps.add(resolved_function_step)
    scope = ? scope.set(resolved_function_step.arg)
  ok(new_resolved_function(resolved_function_def, resolved_steps))

proc resolve(file_def: ResolvedFileDefinition, function: TypedFunction): Result[
    ResolvedFunction, string] =
  var scope = FunctionScope()
  let resolved_function_def = ? file_def.find_function_def(function.def)
  for arg in resolved_function_def.args:
    scope = ? scope.set(arg)

  var resolved_steps: seq[ResolvedStatement]
  for step in function.steps:
    let resolved_function_step = ? resolve(file_def, scope, step)
    resolved_steps.add(resolved_function_step)
    scope = ? scope.set(resolved_function_step.arg)
  ok(new_resolved_function(resolved_function_def, resolved_steps))

type ResolvedUserModule = ref object of RootObj
  def: ResolvedUserModuleDefinition
  functions: seq[ResolvedFunction]

proc new_resolved_user_module(def: ResolvedUserModuleDefinition, functions: seq[
    ResolvedFunction]): ResolvedUserModule =
  ResolvedUserModule(def: def, functions: functions)

proc generic_impls(module: ResolvedUserModule): Table[TypedUserModule, seq[
    HashSet[TypedModule]]] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(module.def.generic_impls)
  for function in module.functions: impl_set = impl_set.merge(
      function.generic_impls)
  return impl_set

proc asl(module: ResolvedUserModule, indent: string): seq[string] =
  var lines = @[fmt"module {module.def.name.asl}:"]
  for line in module.def.asl(indent):
    lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")
  return lines

proc c(module: ResolvedUserModule): seq[string] =
  var lines: seq[string]
  for function in module.functions:
    lines.add(function.c)
  return lines

proc resolve(file_def: ResolvedFileDefinition,
    module_def: ResolvedUserModuleDefinition): Result[ResolvedUserModule, string] =
  var resolved_functions: seq[ResolvedFunction]
  for function in module_def.module.functions:
    let resolved_function = ? resolve(file_def, module_def, function)
    resolved_functions.add(resolved_function)
  ok(new_resolved_user_module(module_def, resolved_functions))

type ResolvedFile* = ref object of RootObj
  def: ResolvedFileDefinition
  start_function_def: ResolvedUserFunctionDefinition
  user_modules: seq[ResolvedUserModule]
  functions: seq[ResolvedFunction]

proc new_resolved_file(def: ResolvedFileDefinition,
    start_function_def: ResolvedUserFunctionDefinition, user_modules: seq[
    ResolvedUserModule], functions: seq[ResolvedFunction]): ResolvedFile =
  ResolvedFile(def: def, start_function_def: start_function_def,
      user_modules: user_modules, functions: functions)

proc indent(file: ResolvedFile): int = file.def.file.indent

proc generic_impls*(file: ResolvedFile): Result[Table[TypedUserModule, seq[seq[
    ResolvedModuleDefinition]]], string] =
  var impl_set: Table[TypedUserModule, seq[HashSet[TypedModule]]]
  impl_set = impl_set.merge(file.def.generic_impls)
  for module in file.user_modules: impl_set = impl_set.merge(
      module.generic_impls)
  for function in file.functions: impl_set = impl_set.merge(
      function.generic_impls)

  # Assign index to module for each generic
  var impl_map: Table[TypedUserModule, seq[seq[ResolvedModuleDefinition]]]
  for module, generics in impl_set.pairs:
    var resolved_children: seq[seq[ResolvedModuleDefinition]]
    for impls in generics:
      var resolved_module_defs: seq[ResolvedModuleDefinition]
      for impl in impls:
        let resolved_module_def = ? file.def.find_module_def(impl)
        resolved_module_defs.add(resolved_module_def)
      resolved_children.add(resolved_module_defs)
    impl_map[module] = resolved_children
  return ok(impl_map)

proc asl*(file: ResolvedFile): string =
  let indent = " ".repeat(file.indent)
  var lines: seq[string]
  for module in file.user_modules:
    lines.add(module.asl(indent))
    lines.add("\n")
  for function in file.functions:
    lines.add(function.asl(indent))
    lines.add("\n")
  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")

proc c*(file: ResolvedFile): string =
  var lines: seq[string]
  lines.add(file.def.c)
  for module in file.user_modules:
    lines.add(module.c)
  for function in file.functions:
    lines.add(function.c)

  @[
    "#include \"runtime.h\"\n",
    lines.join("\n"),
    "\n",
    "int main(int argc, char** argv) {",
    fmt"return {file.start_function_def.c_name}(argc);",
    "}"
  ].join("\n")

proc resolve(file_def: ResolvedFileDefinition,
    start_function_def: ResolvedUserFunctionDefinition): Result[ResolvedFile, string] =
  var resolved_user_modules: seq[ResolvedUserModule]
  for module in file_def.file.user_modules:
    let module_def = ? file_def.find_module_def(module)
    let resolved_user_module = ? resolve(file_def, module_def)
    resolved_user_modules.add(resolved_user_module)

  var resolved_functions: seq[ResolvedFunction]
  for function in file_def.file.functions:
    let resolved_function = ? resolve(file_def, function)
    resolved_functions.add(resolved_function)
  ok(new_resolved_file(file_def, start_function_def, resolved_user_modules,
      resolved_functions))

proc resolve*(file: TypedFile): Result[ResolvedFile, string] =
  let resolved_file_def = ? resolve_def(file)
  let typed_start_function_def = ? file.start_def
  let resolved_start_function = ? resolved_file_def.find_function_def(typed_start_function_def)

  let resolved_file = ? resolve(resolved_file_def, resolved_start_function)
  ok(resolved_file)
