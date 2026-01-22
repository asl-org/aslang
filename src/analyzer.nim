import results, sequtils, strformat, tables, hashes, strutils, sets, re,
    options, algorithm

import analyzer/resolver
export resolver

# Error message helpers
proc err_no_default_struct(location: Location, module_name: string): string =
  fmt"{location} module `{module_name}` does not have a default struct"

proc err_no_named_struct(location: Location, module_name: string,
    struct_name: string): string =
  fmt"{location} module `{module_name}` does not have a struct named `{struct_name}`"

type
  AnalyzedImpl = ref object of RootObj
    module_ref: AnalyzedModuleRef
    defs: seq[ResolvedUserFunctionDefinition]
  AnalyzedModuleRefKind = enum
    RMRK_USER, RMRK_GENERIC
  AnalyzedModuleRef = ref object of RootObj
    location: Location
    case kind: AnalyzedModuleRefKind
    of RMRK_GENERIC: generic: ResolvedGeneric
    of RMRK_USER:
      module: ResolvedUserModule
      impls: seq[AnalyzedImpl]
      concrete_map: Table[ResolvedGeneric, AnalyzedModuleRef]

# AnalyzedImpl
proc new_analyzed_impl(module_ref: AnalyzedModuleRef, defs: seq[
    ResolvedUserFunctionDefinition]): AnalyzedImpl =
  AnalyzedImpl(module_ref: module_ref, defs: defs)

# NOTE: Needed due to cyclic dependency between AnalyzedModuleRef and AnalyzedImpl
proc hash(module_ref: AnalyzedModuleRef): Hash

proc hash(impl: AnalyzedImpl): Hash =
  case impl.module_ref.kind:
  of RMRK_GENERIC: impl.module_ref.generic.hash
  of RMRK_USER: impl.module_ref.module.hash

proc `==`(self: AnalyzedImpl, other: AnalyzedImpl): bool =
  self.hash == other.hash

proc merge*(
  impl_set_1: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]],
  impl_set_2: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
): Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for (module, generics) in impl_set_1.pairs:
    impl_set[module] = generics
  for (module, generics) in impl_set_2.pairs:
    if module in impl_set:
      for index, generic in generics.pairs:
        impl_set[module][index].incl(generic)
    else:
      impl_set[module] = generics
  return impl_set

# AnalyzedModuleRef

proc new_analyzed_module_ref(generic: ResolvedGeneric,
    location: Location): AnalyzedModuleRef =
  AnalyzedModuleRef(kind: RMRK_GENERIC, generic: generic,
      location: location)

proc new_analyzed_module_ref(module: ResolvedUserModule, impls: seq[
    AnalyzedImpl], location: Location): AnalyzedModuleRef =
  var concrete_map: Table[ResolvedGeneric, AnalyzedModuleRef]
  for (generic, impl) in zip(module.generics, impls):
    concrete_map[generic] = impl.module_ref
  AnalyzedModuleRef(kind: RMRK_USER, module: module,
      concrete_map: concrete_map, impls: impls, location: location)

proc name(module_ref: AnalyzedModuleRef): string =
  case module_ref.kind:
  of RMRK_USER: module_ref.module.name.asl
  of RMRK_GENERIC: module_ref.generic.name.asl

proc can_be_argument(module_ref: AnalyzedModuleRef): Result[void, string] =
  case module_ref.kind:
  of RMRK_GENERIC: ok() # generic arguments can be passed as an argument too.
  of RMRK_USER:
    let module = module_ref.module
    if module.structs.len > 0: return ok()
    case module.name.asl:
    of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64", "F32", "F64",
        "Pointer", "String": ok()
    else: err(fmt"{module_ref.location} module `{module.name.asl}` can not be passed as an argument")

proc find_function(module_ref: AnalyzedModuleRef,
    def: ResolvedUserFunctionDefinition): Result[ResolvedUserFunctionDefinition, string] =
  case module_ref.kind:
  of RMRK_GENERIC: module_ref.generic.find_function(def)
  of RMRK_USER: module_ref.module.find_function(def)

proc concretize(module_ref: AnalyzedModuleRef, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedModuleRef =
  case module_ref.kind:
  of RMRK_GENERIC:
    concrete_map[module_ref.generic]
  of RMRK_USER:
    var concretized_impls: seq[AnalyzedImpl]
    for impl in module_ref.impls:
      let concrete_module_ref = impl.module_ref.concretize(concrete_map)
      concretized_impls.add(new_analyzed_impl(concrete_module_ref, impl.defs))
    new_analyzed_module_ref(module_ref.module, concretized_impls,
        module_ref.location)

proc hash(module_ref: AnalyzedModuleRef): Hash =
  case module_ref.kind:
  of RMRK_GENERIC: module_ref.generic.hash
  of RMRK_USER:
    var acc = module_ref.module.hash
    for impl in module_ref.impls:
      acc = acc !& impl.module_ref.hash
    acc

proc `==`(self: AnalyzedModuleRef, other: AnalyzedModuleRef): bool =
  self.hash == other.hash

# Helper to create impl from analyzed child and constraints
proc create_impl_from_child(resolved_generic: ResolvedGeneric,
    child: ResolvedModuleRef, analyzed_child: AnalyzedModuleRef): Result[
        AnalyzedImpl, string] =
  var constraint_defs: seq[ResolvedUserFunctionDefinition]
  for def in resolved_generic.concrete_defs(child.self()):
    constraint_defs.add( ? analyzed_child.find_function(def))
  ok(new_analyzed_impl(analyzed_child, constraint_defs))

proc generic_impls(module_ref: AnalyzedModuleRef): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  case module_ref.kind:
  of RMRK_GENERIC: discard
  of RMRK_USER:
    if module_ref.impls.len > 0:
      var generics: seq[HashSet[AnalyzedImpl]]
      for index, impl in module_ref.impls.pairs:
        generics.add(init_hashset[AnalyzedImpl]())
        case impl.module_ref.kind:
        of RMRK_GENERIC: discard
        of RMRK_USER: generics[index].incl(impl)
      impl_set[module_ref.module] = generics
  return impl_set

proc asl(module_ref: AnalyzedModuleRef): string =
  case module_ref.kind:
  of RMRK_GENERIC: module_ref.generic.asl
  of RMRK_USER:
    var parent_str = module_ref.module.asl
    if module_ref.impls.len == 0:
      parent_str
    else:
      let children_str = module_ref.impls.map_it(it.module_ref.asl).join(", ")
      fmt"{parent_str}[{children_str}]"

proc byte_size(module_ref: AnalyzedModuleRef): uint64 =
  case module_ref.name:
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64": 4
  else: 8

proc c(module_ref: AnalyzedModuleRef): string =
  let module_name = module_ref.name
  case module_name:
  of "U8", "S8": module_name
  of "U16", "S16": module_name
  of "U32", "S32", "F32": module_name
  of "U64", "S64", "F64": module_name
  of "String", "System": module_name
  else: "Pointer"

# Helper to build impls for module_ref children against a resolved module (with generic context)
proc build_impls_for_children[T](file: ResolvedFile, module: T,
    generic: ResolvedGeneric, resolved_module: T, children: seq[
        ResolvedModuleRef],
    location: Location): Result[seq[AnalyzedImpl], string] =
  if children.len != resolved_module.generics.len:
    return err(fmt"{location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

  var impls: seq[AnalyzedImpl]
  for (resolved_generic, child) in zip(resolved_module.generics, children):
    let analyzed_child = ? analyze_def(file, module, generic, child)
    let analyzed_impl = ? create_impl_from_child(resolved_generic, child, analyzed_child)
    impls.add(analyzed_impl)
  ok(impls)

# Helper to build impls for module_ref children (no generic context)
proc build_impls_no_generic[M, T](file: ResolvedFile, module: M,
    resolved_module: T, children: seq[ResolvedModuleRef],
    location: Location): Result[seq[AnalyzedImpl], string] =
  if children.len != resolved_module.generics.len:
    return err(fmt"{location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

  var impls: seq[AnalyzedImpl]
  for (resolved_generic, child) in zip(resolved_module.generics, children):
    let analyzed_child = ? analyze_def(file, module, child)
    let analyzed_impl = ? create_impl_from_child(resolved_generic, child, analyzed_child)
    impls.add(analyzed_impl)
  ok(impls)

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    generic: ResolvedGeneric, module_ref: ResolvedModuleRef): Result[
        AnalyzedModuleRef, string] =
  case module_ref.kind:
  of TMRK_GENERIC:
    let resolved_generic = ? module.find_generic(module_ref.generic)
    if resolved_generic != generic:
      return err(fmt"{module_ref.location} expected generic `{generic.name.asl}` but found `{resolved_generic.name.asl}`")

    ok(new_analyzed_module_ref(resolved_generic, module_ref.location))
  of TMRK_USER:
    let resolved_any = ? file.find_module(module_ref.module)
    let resolved_module = ? resolved_any.user
    if resolved_module == module:
      return err(fmt"{module_ref.location} module `{resolved_module.name.asl}` can not be passed as an argument to generic constraint `{generic.name.asl}`")

    let children = ? module_ref.children
    let impls = ? build_impls_for_children(file, module, generic,
        resolved_module, children, module_ref.location)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    module_ref: ResolvedModuleRef): Result[AnalyzedModuleRef, string] =
  case module_ref.kind:
  of TMRK_GENERIC:
    let resolved_generic = ? module.find_generic(module_ref.generic)
    ok(new_analyzed_module_ref(resolved_generic, module_ref.location))
  of TMRK_USER:
    let resolved_module_any = ? file.find_module(module_ref.module)
    let resolved_module = ? resolved_module_any.user
    let children = ? module_ref.children
    let impls = ? build_impls_no_generic(file, module, resolved_module,
        children, module_ref.location)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))

proc analyze_def(file: ResolvedFile, module_ref: ResolvedModuleRef): Result[
    AnalyzedModuleRef, string]

# Helper to process module children at file level (no module context)
proc process_module_children_file_level(file: ResolvedFile,
    resolved_module: ResolvedUserModule, children: seq[
    ResolvedModuleRef], location: Location): Result[seq[AnalyzedImpl], string] =
  if children.len != resolved_module.generics.len:
    return err(fmt"{location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

  var impls: seq[AnalyzedImpl]
  for (resolved_generic, child) in zip(resolved_module.generics, children):
    let analyzed_child = ? analyze_def(file, child)
    let analyzed_impl = ? create_impl_from_child(resolved_generic, child, analyzed_child)
    impls.add(analyzed_impl)
  ok(impls)

proc analyze_def(file: ResolvedFile, module_ref: ResolvedModuleRef): Result[
    AnalyzedModuleRef, string] =
  case module_ref.kind:
  of TMRK_GENERIC:
    err(fmt"{module_ref.location} file level functions do not support generics")
  of TMRK_USER:
    let resolved_any = ? file.find_module(module_ref.module)
    let resolved_module = ? resolved_any.user
    let children = ? module_ref.children
    let impls = ? process_module_children_file_level(file, resolved_module,
        children, module_ref.location)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))

type AnalyzedArgumentDefinition = ref object of RootObj
  name: Identifier
  module_ref: AnalyzedModuleRef
  location: Location

proc new_analyzed_argument_definition(module_ref: AnalyzedModuleRef,
    name: Identifier, location: Location): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(name: name, module_ref: module_ref,
      location: location)

proc new_analyzed_argument_definition(module_ref: AnalyzedModuleRef,
    name: Identifier): AnalyzedArgumentDefinition =
  new_analyzed_argument_definition(module_ref, name, module_ref.location)

proc concretize(arg: AnalyzedArgumentDefinition, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedArgumentDefinition =
  let concretized_module_ref = arg.module_ref.concretize(concrete_map)
  new_analyzed_argument_definition(concretized_module_ref, arg.name)

proc byte_size(arg: AnalyzedArgumentDefinition): uint64 =
  arg.module_ref.byte_size

proc generic_impls(arg: AnalyzedArgumentDefinition): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  arg.module_ref.generic_impls

proc asl(arg: AnalyzedArgumentDefinition): string =
  fmt"{arg.module_ref.asl} {arg.name.asl}"

proc c(arg: AnalyzedArgumentDefinition): string =
  fmt"{arg.module_ref.c} {arg.name.asl}"

# Helper to analyze module_ref with optional generic
proc analyze_module_ref_with_generic[T](file: ResolvedFile, module: T,
    generic: Option[ResolvedGeneric], module_ref: ResolvedModuleRef): Result[
        AnalyzedModuleRef, string] =
  if generic.is_some:
    analyze_def(file, module, generic.get, module_ref)
  else:
    analyze_def(file, module, module_ref)

proc analyze_arg_with_generic[T](file: ResolvedFile, module: T,
    generic: Option[ResolvedGeneric], arg: ResolvedArgumentDefinition): Result[
        AnalyzedArgumentDefinition, string] =
  if generic.is_some:
    analyze_def(file, module, generic.get, arg)
  else:
    analyze_def(file, module, arg)

proc function_prefix(module_name: Identifier,
    generic: Option[ResolvedGeneric]): string =
  if generic.is_some:
    fmt"{module_name.asl}_{generic.get.name.asl}"
  else:
    module_name.asl

# Helper for resolving ResolvedArgumentDefinition with ResolvedUserModule
proc analyze_argument_definition_user(file: ResolvedFile,
    arg: ResolvedArgumentDefinition, module: ResolvedUserModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? analyze_module_ref_with_generic(file, module,
      generic, arg.module_ref)
  ? analyzed_module_ref.can_be_argument
  ok(new_analyzed_argument_definition(analyzed_module_ref, arg.name))

# Helper for resolving ResolvedArgumentDefinition without module
proc analyze_argument_definition_no_module(file: ResolvedFile,
    arg: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? analyze_def(file, arg.module_ref)
  ? analyzed_module_ref.can_be_argument
  ok(new_analyzed_argument_definition(analyzed_module_ref, arg.name))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    generic: ResolvedGeneric, arg: ResolvedArgumentDefinition): Result[
        AnalyzedArgumentDefinition, string] =
  analyze_argument_definition_user(file, arg, module, some(generic))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    arg: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  analyze_argument_definition_user(file, arg, module, none(ResolvedGeneric))

proc analyze_def(file: ResolvedFile, arg: ResolvedArgumentDefinition): Result[
    AnalyzedArgumentDefinition, string] =
  analyze_argument_definition_no_module(file, arg)

type AnalyzedUserFunctionDefinition = ref object of RootObj
  name: Identifier
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedModuleRef
  prefix: string
  generics: uint64
  extern: Option[string]
  location: Location

proc new_analyzed_function_definition(name: Identifier,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    location: Location, prefix: string = "",
        generics: uint64 = 0): AnalyzedUserFunctionDefinition =
  AnalyzedUserFunctionDefinition(name: name, args: args,
      returns: returns, location: location, prefix: prefix, generics: generics)

# WIP
proc new_analyzed_function_definition(name: Identifier,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    location: Location, extern: Option[string], prefix: string = "",
        generics: uint64 = 0): AnalyzedUserFunctionDefinition =
  AnalyzedUserFunctionDefinition(name: name, args: args, returns: returns,
      location: location, prefix: prefix, generics: generics, extern: extern)

proc arity(def: AnalyzedUserFunctionDefinition): uint = def.args.len.uint
proc concretize(def: AnalyzedUserFunctionDefinition, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedUserFunctionDefinition =
  var concretized_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    concretized_args.add(arg.concretize(concrete_map))
  let concretized_returns = def.returns.concretize(concrete_map)
  new_analyzed_function_definition(def.name, concretized_args,
      concretized_returns, def.location, def.extern)

proc generic_impls(def: AnalyzedUserFunctionDefinition): Table[
    ResolvedUserModule, seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for arg in def.args: impl_set = impl_set.merge(arg.generic_impls())
  impl_set = impl_set.merge(def.returns.generic_impls())
  return impl_set

proc asl(def: AnalyzedUserFunctionDefinition): string =
  let args = def.args.map_it(it.asl).join(", ")
  fmt"fn {def.name.asl}({args}): {def.returns.asl}"

proc c_name(def: AnalyzedUserFunctionDefinition): string =
  if def.extern.is_some:
    def.extern.get
  elif def.prefix == "":
    fmt"{def.name.asl}_{def.location.hash.to_hex}"
  else:
    fmt"{def.prefix}_{def.name.asl}_{def.location.hash.to_hex}"

proc h(def: AnalyzedUserFunctionDefinition): string =
  let generic_args = if def.generics > 0: ((0.uint64)..<(
      def.generics)).map_it(fmt"U64 __asl_impl_id_{it}") else: @[]
  let args = generic_args & def.args.map_it(it.c)
  let args_str = args.join(", ")
  let code = fmt"{def.returns.c} {def.c_name}({args_str});"
  if def.extern.is_some: fmt"extern {code}" else: code

# Helper for resolving ResolvedUserFunctionDefinition with ResolvedUserModule
proc analyze_function_definition_user(file: ResolvedFile,
    function: ResolvedFunction, module: ResolvedUserModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedUserFunctionDefinition, string] =
  let def = function.def
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_arg_with_generic(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_module_ref_with_generic(file, module,
      generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, function.extern_name, prefix,
        module.generics.len.uint64))
  of RFK_USER:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, prefix, module.generics.len.uint64))

proc analyze_function_definition_user(file: ResolvedFile,
    def: ResolvedUserFunctionDefinition, module: ResolvedUserModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedUserFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_arg_with_generic(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_module_ref_with_generic(file, module,
      generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  ok(new_analyzed_function_definition(def.name, analyzed_args,
      analyzed_returns, def.location, prefix, module.generics.len.uint64))

# Helper for resolving ResolvedUserFunctionDefinition without module
proc analyze_function_definition_no_module(file: ResolvedFile,
    def: ResolvedUserFunctionDefinition): Result[AnalyzedUserFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  ok(new_analyzed_function_definition(def.name, analyzed_args, analyzed_returns, def.location))

proc analyze_function_definition_no_module(file: ResolvedFile,
    function: ResolvedFunction): Result[AnalyzedUserFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  let def = function.def
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, function.extern_name))
  of RFK_USER:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    generic: ResolvedGeneric, def: ResolvedFunction): Result[
        AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_user(file, def, module, some(generic))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    generic: ResolvedGeneric, def: ResolvedUserFunctionDefinition): Result[
        AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_user(file, def, module, some(generic))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    def: ResolvedUserFunctionDefinition): Result[AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_user(file, def, module, none(ResolvedGeneric))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    function: ResolvedFunction): Result[AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_user(file, function, module, none(ResolvedGeneric))

proc analyze_def(file: ResolvedFile, def: ResolvedUserFunctionDefinition): Result[
    AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_no_module(file, def)

proc analyze_def(file: ResolvedFile, function: ResolvedFunction): Result[
    AnalyzedUserFunctionDefinition, string] =
  analyze_function_definition_no_module(file, function)

type AnalyzedGeneric = ref object of RootObj
  generic: ResolvedGeneric
  defs: seq[AnalyzedUserFunctionDefinition]
  defs_map: Table[Identifier, Table[uint, seq[AnalyzedUserFunctionDefinition]]]
  location: Location

proc new_analyzed_generic(generic: ResolvedGeneric, defs: seq[
    AnalyzedUserFunctionDefinition], location: Location): AnalyzedGeneric =
  var defs_map: Table[Identifier, Table[uint, seq[
      AnalyzedUserFunctionDefinition]]]
  for def in defs:
    if def.name notin defs_map:
      defs_map[def.name] = init_table[uint, seq[
          AnalyzedUserFunctionDefinition]]()
    if def.arity notin defs_map[def.name]:
      defs_map[def.name][def.arity] = new_seq[AnalyzedUserFunctionDefinition]()
    defs_map[def.name][def.arity].add(def)
  AnalyzedGeneric(generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc name(generic: AnalyzedGeneric): Identifier = generic.generic.name

proc generic_impls(generic: AnalyzedGeneric): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for def in generic.defs: impl_set = impl_set.merge(def.generic_impls())
  return impl_set

proc asl(generic: AnalyzedGeneric, indent: string): seq[string] =
  if generic.defs.len == 0:
    @[fmt"generic {generic.name.asl}"]
  else:
    var lines = @[fmt"generic {generic.name.asl}:"]
    for def in generic.defs:
      lines.add(indent & def.asl)
    lines

proc c(generic: AnalyzedGeneric, prefix: string): seq[string] =
  var lines: seq[string]
  for def in generic.defs:
    lines.add(def.h)
  # TODO: provide implementation of generic calls
  return lines

proc find_function_defs(generic: AnalyzedGeneric, name: Identifier,
    arity: uint): Result[seq[AnalyzedUserFunctionDefinition], string] =
  if name notin generic.defs_map:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}`")
  elif arity notin generic.defs_map[name]:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.defs_map[name][arity])

# Helper for resolving ResolvedGeneric with ResolvedUserModule
proc analyze_generic_user(file: ResolvedFile, generic: ResolvedGeneric,
    module: ResolvedUserModule): Result[AnalyzedGeneric, string] =
  var analyzed_defs: seq[AnalyzedUserFunctionDefinition]
  for def in generic.defs:
    let analyzed_def = ? analyze_def(file, module, generic, def)
    analyzed_defs.add(analyzed_def)
  ok(new_analyzed_generic(generic, analyzed_defs, generic.location))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  analyze_generic_user(file, generic, module)

type
  AnalyzedStructKind = enum
    RSK_DEFAULT, RSK_NAMED
  AnalyzedStruct = ref object of RootObj
    struct: ResolvedStruct
    location: Location
    fields: seq[AnalyzedArgumentDefinition]
    fields_map: Table[Identifier, int]
    case kind: AnalyzedStructKind
    of RSK_DEFAULT: discard
    of RSK_NAMED: name: Identifier

proc new_analyzed_struct(struct: ResolvedStruct, fields: seq[
    AnalyzedArgumentDefinition], location: Location): AnalyzedStruct =
  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs: fields_map[field.name] = index
  AnalyzedStruct(kind: RSK_DEFAULT, struct: struct, fields: fields,
      fields_map: fields_map, location: location)

proc new_analyzed_struct(struct: ResolvedStruct, name: Identifier, fields: seq[
    AnalyzedArgumentDefinition], location: Location): AnalyzedStruct =
  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs: fields_map[field.name] = index
  AnalyzedStruct(kind: RSK_NAMED, struct: struct, name: name, fields: fields,
      fields_map: fields_map, location: location)

proc id(struct: AnalyzedStruct): uint64 = struct.struct.id

proc generic_impls(struct: AnalyzedStruct): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for field in struct.fields: impl_set = impl_set.merge(field.generic_impls())
  return impl_set

proc asl(struct: AnalyzedStruct, indent: string): seq[string] =
  var lines =
    case struct.kind:
    of RSK_DEFAULT: @["struct:"]
    of RSK_NAMED: @[fmt"struct {struct.name.asl}:"]

  for field in struct.fields:
    lines.add(indent & field.asl)

  return lines

proc h(struct: AnalyzedStruct, prefix: string, id: Option[uint64] = none(
    uint64)): seq[string] =
  let sub_prefix =
    case struct.kind:
    of RSK_DEFAULT: fmt"{prefix}"
    of RSK_NAMED: fmt"{prefix}_{struct.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = if id.is_some: 8 else: 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str});")
  return lines

proc c(struct: AnalyzedStruct, prefix: string, id: Option[uint64] = none(
    uint64)): seq[string] =
  let sub_prefix =
    case struct.kind:
    of RSK_DEFAULT: fmt"{prefix}"
    of RSK_NAMED: fmt"{prefix}_{struct.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = if id.is_some: 8 else: 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")

  # NOTE: if id is some that means it is union branch initializer so add id
  # Also note that we are using `prefix` instead of `sub_prefix`
  if id.is_some:
    lines.add(fmt"__asl_ptr = {prefix}_set_id(__asl_ptr, {id.get});")

  for field in struct.fields:
    lines.add(fmt"__asl_ptr = {sub_prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
  return lines

proc concretize(struct: AnalyzedStruct, concrete_map: Table[ResolvedGeneric,
    AnalyzedModuleRef]): AnalyzedStruct =
  var concretized_fields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    concretized_fields.add(field.concretize(concrete_map))

  case struct.kind:
  of RSK_DEFAULT: new_analyzed_struct(struct.struct, concretized_fields,
      struct.location)
  of RSK_NAMED: new_analyzed_struct(struct.struct, struct.name,
      concretized_fields, struct.location)

proc find_field_index(struct: AnalyzedStruct, field: Identifier): Result[int, string] =
  if field in struct.fields_map:
    ok(struct.fields_map[field])
  else:
    err(fmt"{field.location} field is not defined in the struct")

proc find_field(struct: AnalyzedStruct, field: Identifier): Result[
    AnalyzedArgumentDefinition, string] =
  let field_index = ? struct.find_field_index(field)
  ok(struct.fields[field_index])

# Helper for resolving ResolvedStruct with either module kind
proc analyze_struct_common[T](file: ResolvedFile, struct: ResolvedStruct,
    module: T): Result[AnalyzedStruct, string] =
  var analyzed_fields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzed_field = ? analyze_def(file, module, field)
    analyzed_fields.add(analyzed_field)

  case struct.kind:
  of TSK_DEFAULT:
    ok(new_analyzed_struct(struct, analyzed_fields, struct.location))
  of TSK_NAMED:
    let struct_name = ? struct.name
    ok(new_analyzed_struct(struct, struct_name, analyzed_fields,
        struct.location))

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule,
    struct: ResolvedStruct): Result[AnalyzedStruct, string] =
  analyze_struct_common(file, struct, module)

type AnalyzedUserModuleDefinition = ref object of RootObj
  module: ResolvedUserModule
  generics: seq[AnalyzedGeneric]
  generics_map: Table[ResolvedGeneric, AnalyzedGeneric]
  structs: seq[AnalyzedStruct]
  default_struct_index: int
  structs_map: Table[Identifier, AnalyzedStruct]
  function_defs: seq[AnalyzedUserFunctionDefinition]
  function_defs_map: Table[ResolvedUserFunctionDefinition, AnalyzedUserFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      AnalyzedUserFunctionDefinition]]]

proc new_analyzed_user_module_definition(module: ResolvedUserModule,
    generics: seq[(ResolvedGeneric, AnalyzedGeneric)], structs: seq[
        AnalyzedStruct],
    function_defs: seq[(ResolvedUserFunctionDefinition,
    AnalyzedUserFunctionDefinition)]): AnalyzedUserModuleDefinition =
  var generics_map: Table[ResolvedGeneric, AnalyzedGeneric]
  var analyzed_generics: seq[AnalyzedGeneric]
  for (resolved_generic, analyzed_generic) in generics:
    generics_map[resolved_generic] = analyzed_generic
    analyzed_generics.add(analyzed_generic)

  var default_struct_index = -1
  var structs_map: Table[Identifier, AnalyzedStruct]
  var analyzed_structs: seq[AnalyzedStruct]
  for index, analyzed_struct in structs.pairs:
    analyzed_structs.add(analyzed_struct)
    case analyzed_struct.kind:
    of RSK_DEFAULT: default_struct_index = index
    of RSK_NAMED: structs_map[analyzed_struct.name] = analyzed_struct

  var function_defs_map: Table[ResolvedUserFunctionDefinition, AnalyzedUserFunctionDefinition]
  var analyzed_function_defs: seq[AnalyzedUserFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedUserFunctionDefinition]]]
  for (resolved_function_def, analyzed_function_def) in function_defs:
    function_defs_map[resolved_function_def] = analyzed_function_def
    analyzed_function_defs.add(analyzed_function_def)

    if analyzed_function_def.name notin function_signatures_map:
      function_signatures_map[analyzed_function_def.name] = init_table[uint,
          seq[AnalyzedUserFunctionDefinition]]()
    if analyzed_function_def.arity notin function_signatures_map[
        analyzed_function_def.name]:
      function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity] = new_seq[
              AnalyzedUserFunctionDefinition]()
    function_signatures_map[analyzed_function_def.name][
        analyzed_function_def.arity].add(analyzed_function_def)

  AnalyzedUserModuleDefinition(
    module: module, generics: analyzed_generics, generics_map: generics_map,
    structs: analyzed_structs, structs_map: structs_map,
    function_defs: analyzed_function_defs, function_defs_map: function_defs_map,
    function_signatures_map: function_signatures_map
  )

proc id(module_def: AnalyzedUserModuleDefinition): uint64 = module_def.id
proc name(module_def: AnalyzedUserModuleDefinition): Identifier = module_def.module.name
proc hash(module_def: AnalyzedUserModuleDefinition): Hash = module_def.module.hash
proc `==`(self: AnalyzedUserModuleDefinition,
    other: AnalyzedUserModuleDefinition): bool =
  self.hash == other.hash

proc generic_impls(def: AnalyzedUserModuleDefinition): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for generic in def.generics: impl_set = impl_set.merge(generic.generic_impls())
  for struct in def.structs: impl_set = impl_set.merge(struct.generic_impls())
  for function in def.function_defs: impl_set = impl_set.merge(
      function.generic_impls())
  return impl_set

proc asl(def: AnalyzedUserModuleDefinition, indent: string): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.asl(indent))

  if def.generics.len > 0:
    lines.add("\n")

  for struct in def.structs:
    lines.add(struct.asl(indent))
  return lines

proc h(def: AnalyzedUserModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  if def.structs.len > 0:
    # internal functions for structs
    # byte size
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items);")
    # read
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset);")
    # write
    lines.add(fmt"Pointer {def.name.asl}_write(Pointer value, Pointer __asl_ptr, U64 offset);")

    # struct
    if def.structs.len == 1:
      let struct = def.structs[0]
      lines.add(struct.h(def.name.asl))
    # union
    else:
      # union branch id getter
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr);")

      # union branch id setter
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id);")
      for index, struct in def.structs:
        lines.add(struct.h(def.name.asl, some(index.uint64)))

  # TODO: Understand that function can not have same name so use function id as prefix
  lines.add(def.function_defs.map_it(it.h))

  return lines

proc c(def: AnalyzedUserModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  if def.structs.len > 0:
    # internal functions for structs
    # byte size
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items)")
    lines.add("{")
    lines.add("return Pointer_byte_size(items);")
    lines.add("}")
    # read
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset)")
    lines.add("{")
    lines.add("return Pointer_read(__asl_ptr, offset);")
    lines.add("}")
    # write
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
      # union branch id getter
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr)")
      lines.add("{")
      lines.add(fmt"return U64_read(__asl_ptr, 0);")
      lines.add("}")

      # union branch id setter
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id)")
      lines.add("{")
      lines.add(fmt"return U64_write(id, __asl_ptr, 0);")
      lines.add("}")
      for index, struct in def.structs:
        lines.add(struct.c(def.name.asl, some(index.uint64)))

  return lines

proc find_generic(module_def: AnalyzedUserModuleDefinition,
    generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  if generic notin module_def.generics_map:
    err(fmt"module `{module_def.name.asl}` does not have any generic named `{generic.name.asl}`")
  else:
    ok(module_def.generics_map[generic])

proc find_struct(module_def: AnalyzedUserModuleDefinition): Result[
    AnalyzedStruct, string] =
  if module_def.default_struct_index == -1:
    err(fmt"module `{module_def.name.asl}` does not have a default struct")
  else:
    ok(module_def.structs[module_def.default_struct_index])

proc find_struct(module_def: AnalyzedUserModuleDefinition,
    name: Identifier): Result[AnalyzedStruct, string] =
  if name notin module_def.structs_map:
    err(fmt"module `{module_def.name.asl}` does not have struct named `{name.asl}`")
  else:
    ok(module_def.structs_map[name])

proc find_function_def(module_def: AnalyzedUserModuleDefinition,
    function_def: ResolvedUserFunctionDefinition): Result[
        AnalyzedUserFunctionDefinition, string] =
  if function_def notin module_def.function_defs_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{function_def.name.asl}`")
  else:
    ok(module_def.function_defs_map[function_def])

proc find_function_defs(module_def: AnalyzedUserModuleDefinition,
    name: Identifier, arity: uint): Result[seq[
    AnalyzedUserFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc analyze_def(file: ResolvedFile, module: ResolvedUserModule): Result[
    AnalyzedUserModuleDefinition, string] =
  var generics: seq[(ResolvedGeneric, AnalyzedGeneric)]
  for generic in module.generics:
    let analyzed_generic = ? analyze_def(file, module, generic)
    generics.add((generic, analyzed_generic))

  var structs: seq[AnalyzedStruct]
  for struct in module.structs:
    let analyzed_struct = ? analyze_def(file, module, struct)
    structs.add(analyzed_struct)

  var function_defs: seq[(ResolvedUserFunctionDefinition,
      AnalyzedUserFunctionDefinition)]
  for function in module.functions:
    let analyzed_def = ? analyze_def(file, module, function)
    function_defs.add((function.def, analyzed_def))

  ok(new_analyzed_user_module_definition(module, generics, structs,
      function_defs))

type AnalyzedNativeFunctionDefinition = ref object of RootObj
  native: string
  def: AnalyzedUserFunctionDefinition

proc new_analyzed_native_function_definition(native: string,
    def: AnalyzedUserFunctionDefinition): AnalyzedNativeFunctionDefinition =
  AnalyzedNativeFunctionDefinition(native: native, def: def)

proc name(def: AnalyzedNativeFunctionDefinition): Identifier = def.def.name
proc arity(def: AnalyzedNativeFunctionDefinition): uint = def.def.arity.uint
proc generic_impls(function: AnalyzedNativeFunctionDefinition): Table[
    ResolvedUserModule, seq[HashSet[AnalyzedImpl]]] =
  function.def.generic_impls

type
  AnalyzedModuleDefinitionKind = enum
    RMDK_USER
  AnalyzedModuleDefinition = ref object of RootObj
    case kind: AnalyzedModuleDefinitionKind
    of RMDK_USER: user: AnalyzedUserModuleDefinition

proc new_analyzed_module_definition(user: AnalyzedUserModuleDefinition): AnalyzedModuleDefinition =
  AnalyzedModuleDefinition(kind: RMDK_USER, user: user)

proc id(def: AnalyzedModuleDefinition): uint64 =
  case def.kind:
  of RMDK_USER: def.user.id

type AnalyzedFileDefinition = ref object of RootObj
  file: ResolvedFile
  native_modules: seq[AnalyzedUserModuleDefinition]
  native_modules_map: Table[ResolvedModule, AnalyzedUserModuleDefinition]
  user_modules: seq[AnalyzedUserModuleDefinition]
  user_modules_map: Table[ResolvedModule, AnalyzedUserModuleDefinition]
  function_defs: seq[AnalyzedUserFunctionDefinition]
  function_defs_map: Table[ResolvedUserFunctionDefinition, AnalyzedUserFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedUserFunctionDefinition]]]

proc new_analyzed_file_definition(file: ResolvedFile, native_modules: seq[(
    ResolvedModule, AnalyzedUserModuleDefinition)], user_modules: seq[(
    ResolvedUserModule, AnalyzedUserModuleDefinition)], function_defs: seq[(
    ResolvedUserFunctionDefinition,
    AnalyzedUserFunctionDefinition)]): AnalyzedFileDefinition =
  var native_modules_map: Table[ResolvedModule, AnalyzedUserModuleDefinition]
  var analyzed_native_modules: seq[AnalyzedUserModuleDefinition]
  for (resolved_module, analyzed_module) in native_modules:
    native_modules_map[resolved_module] = analyzed_module
    analyzed_native_modules.add(analyzed_module)

  var user_modules_map: Table[ResolvedModule, AnalyzedUserModuleDefinition]
  var analyzed_user_modules: seq[AnalyzedUserModuleDefinition]
  for (resolved_module, analyzed_user_module) in user_modules:
    user_modules_map[new_resolved_module(
        resolved_module)] = analyzed_user_module
    analyzed_user_modules.add(analyzed_user_module)

  var function_defs_map: Table[ResolvedUserFunctionDefinition, AnalyzedUserFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedUserFunctionDefinition]]]
  var analyzed_function_defs: seq[AnalyzedUserFunctionDefinition]
  for (resolved_function_def, analyzed_function_def) in function_defs:
    function_defs_map[resolved_function_def] = analyzed_function_def
    analyzed_function_defs.add(analyzed_function_def)

    if analyzed_function_def.name notin function_signatures_map:
      function_signatures_map[analyzed_function_def.name] = init_table[uint,
          seq[AnalyzedUserFunctionDefinition]]()
    if analyzed_function_def.arity notin function_signatures_map[
        analyzed_function_def.name]:
      function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity] = new_seq[
              AnalyzedUserFunctionDefinition]()
    function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity].add(analyzed_function_def)

  AnalyzedFileDefinition(file: file, native_modules: analyzed_native_modules,
      native_modules_map: native_modules_map,
      user_modules: analyzed_user_modules,
      user_modules_map: user_modules_map, function_defs: analyzed_function_defs,
      function_defs_map: function_defs_map,
      function_signatures_map: function_signatures_map)

proc generic_impls(file: AnalyzedFileDefinition): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for module in file.native_modules: impl_set = impl_set.merge(
      module.generic_impls())
  for module in file.user_modules: impl_set = impl_set.merge(
      module.generic_impls())
  for function_def in file.function_defs:
    impl_set = impl_set.merge(function_def.generic_impls())
  return impl_set

proc h(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.user_modules:
    lines.add(module.h)
  for fndef in file.function_defs:
    lines.add(fndef.h)
  return lines

proc c(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.user_modules:
    lines.add(module.c)
  return lines

proc find_module_def(file_def: AnalyzedFileDefinition,
    module: ResolvedModule): Result[AnalyzedUserModuleDefinition, string] =
  if module in file_def.native_modules_map:
    ok(file_def.native_modules_map[module])
  elif module in file_def.user_modules_map:
    ok(file_def.user_modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in analyzed file definition")

# proc find_module_def(file_def: AnalyzedFileDefinition,
#     module: ResolvedUserModule): Result[AnalyzedUserModuleDefinition, string] =
#   if module in file_def.user_modules_map:
#     ok(file_def.user_modules_map[module])
#   else:
#     err(fmt"module `{module.name.asl}` not found in analyzed file definition")

proc find_function_def(file_def: AnalyzedFileDefinition,
    def: ResolvedUserFunctionDefinition): Result[AnalyzedUserFunctionDefinition, string] =
  if def in file_def.function_defs_map:
    ok(file_def.function_defs_map[def])
  else:
    err(fmt"def `{def.name.asl}` not found in analyzed file definition")

proc find_function_defs(file_def: AnalyzedFileDefinition, name: Identifier,
    arity: uint): Result[seq[AnalyzedUserFunctionDefinition], string] =
  if name notin file_def.function_signatures_map:
    err(fmt"function `{name.asl}` not found in analyzed file definition")
  elif arity notin file_def.function_signatures_map[name]:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in analyzed file definition")
  else:
    ok(file_def.function_signatures_map[name][arity])

proc analyze_def(file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var modules: seq[(ResolvedUserModule, AnalyzedUserModuleDefinition)]
  for module in file.user_modules:
    let analyzed_module_def = ? analyze_def(file, module)
    modules.add((module, analyzed_module_def))

  var function_defs: seq[(ResolvedUserFunctionDefinition,
      AnalyzedUserFunctionDefinition)]
  for function in file.functions:
    let analyzed_function_def = ? analyze_def(file, function)
    function_defs.add((function.def, analyzed_function_def))

  ok(new_analyzed_file_definition(file, @[], modules, function_defs))

type FunctionScope = ref object of RootObj
  table: Table[Identifier, AnalyzedModuleRef]

proc get(scope: FunctionScope, name: Identifier): Result[AnalyzedModuleRef, string] =
  if name notin scope.table:
    return err(fmt"{name.location} argument `{name.asl}` is not present in the scope")
  ok(scope.table[name])

proc set(scope: FunctionScope, arg: AnalyzedArgumentDefinition): Result[
    FunctionScope, string] =
  if arg.name in scope.table:
    return err(fmt"{arg.location} argument `{arg.name.asl}` can not be mutated")
  scope.table[arg.name] = arg.module_ref
  ok(scope)

proc clone(scope: FunctionScope): FunctionScope =
  var table: Table[Identifier, AnalyzedModuleRef]
  for name, module_ref in scope.table:
    table[name] = module_ref
  FunctionScope(table: table)

type
  AnalyzedFunctionDefinitionKind = enum
    RFDK_USER, RFDK_NATIVE
  AnalyzedFunctionDefinition = ref object of RootObj
    case kind: AnalyzedFunctionDefinitionKind
    of RFDK_USER: user: AnalyzedUserFunctionDefinition
    of RFDK_NATIVE: native: AnalyzedNativeFunctionDefinition

proc new_analyzed_function_definition(def: AnalyzedUserFunctionDefinition): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(kind: RFDK_USER, user: def)

proc new_analyzed_function_definition(def: AnalyzedNativeFunctionDefinition): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(kind: RFDK_NATIVE, native: def)

proc args(def: AnalyzedFunctionDefinition): seq[AnalyzedArgumentDefinition] =
  case def.kind:
  of RFDK_NATIVE: def.native.def.args
  of RFDK_USER: def.user.args

proc returns(def: AnalyzedFunctionDefinition): AnalyzedModuleRef =
  case def.kind:
  of RFDK_NATIVE: def.native.def.returns
  of RFDK_USER: def.user.returns

proc generic_impls(def: AnalyzedFunctionDefinition): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  case def.kind:
  of RFDK_NATIVE: def.native.def.generic_impls
  of RFDK_USER: def.user.generic_impls

proc asl(def: AnalyzedFunctionDefinition): string =
  case def.kind:
  of RFDK_NATIVE: def.native.def.asl
  of RFDK_USER: def.user.asl

proc c_name(def: AnalyzedFunctionDefinition): string =
  case def.kind:
  of RFDK_NATIVE: def.native.native
  of RFDK_USER: def.user.c_name

type
  AnalyzedFunctionRefKind = enum
    RFRK_LOCAL, RFRK_MODULE
  AnalyzedFunctionRef = ref object of RootObj
    name: Identifier
    concrete_defs: seq[AnalyzedFunctionDefinition]
    original_defs: seq[AnalyzedFunctionDefinition]
    case kind: AnalyzedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: module_ref: AnalyzedModuleRef

proc new_analyzed_function_ref(name: Identifier, original_defs: seq[
    AnalyzedFunctionDefinition], concrete_defs: seq[
    AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(kind: RFRK_LOCAL, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc new_analyzed_function_ref(module_ref: AnalyzedModuleRef, name: Identifier,
    original_defs: seq[AnalyzedFunctionDefinition], concrete_defs: seq[
    AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(kind: RFRK_MODULE, module_ref: module_ref, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc location(fnref: AnalyzedFunctionRef): Location =
  fnref.location

proc defs(fnref: AnalyzedFunctionRef): seq[(AnalyzedFunctionDefinition,
    AnalyzedFunctionDefinition)] =
  zip(fnref.original_defs, fnref.concrete_defs)

proc generic_impls(fnref: AnalyzedFunctionRef): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  case fnref.kind:
  of RFRK_LOCAL: discard
  of RFRK_MODULE: impl_set = impl_set.merge(fnref.module_ref.generic_impls)
  return impl_set

proc asl(fnref: AnalyzedFunctionRef): string =
  case fnref.kind:
  of RFRK_LOCAL: fmt"{fnref.name.asl}"
  of RFRK_MODULE: fmt"{fnref.module_ref.asl}.{fnref.name.asl}"

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition,
        fnref: ResolvedUserFunctionRef): Result[
    AnalyzedFunctionRef, string] =
  case fnref.kind:
  of TFRK_LOCAL:
    let analyzed_user_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    let analyzed_function_defs = analyzed_user_function_defs.map_it(
        new_analyzed_function_definition(it))
    ok(new_analyzed_function_ref(fnref.name, analyzed_function_defs,
        analyzed_function_defs))
  of TFRK_MODULE:
    let resolved_module_ref = ? fnref.module_ref
    let analyzed_module_ref = ? analyze_def(file_def.file, module_def.module, resolved_module_ref)
    case analyzed_module_ref.kind:
    of RMRK_GENERIC:
      let resolved_generic = analyzed_module_ref.generic
      let analyzed_generic = ? module_def.find_generic(resolved_generic)
      let analyzed_user_function_defs = ? analyzed_generic.find_function_defs(
          fnref.name, fnref.arity)
      let analyzed_function_defs = analyzed_user_function_defs.map_it(
        new_analyzed_function_definition(it))
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_function_defs))
    of RMRK_USER:
      let resolved_user_module = analyzed_module_ref.module
      let analyzed_user_module_def = ? file_def.find_module_def(
          new_resolved_module(resolved_user_module))
      let analyzed_user_function_defs = ? analyzed_user_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let analyzed_function_defs = analyzed_user_function_defs.map_it(
          new_analyzed_function_definition(it))
      let concrete_function_defs = analyzed_user_function_defs.map_it(
          it.concretize(analyzed_module_ref.concrete_map))
      let analyzed_concrete_function_defs = concrete_function_defs.map_it(
          new_analyzed_function_definition(it))
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_concrete_function_defs))

proc analyze(file_def: AnalyzedFileDefinition,
    fnref: ResolvedUserFunctionRef): Result[AnalyzedFunctionRef, string] =
  case fnref.kind:
  of TFRK_LOCAL:
    let analyzed_user_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    let analyzed_function_defs = analyzed_user_function_defs.map_it(
        new_analyzed_function_definition(it))
    ok(new_analyzed_function_ref(fnref.name, analyzed_function_defs,
        analyzed_function_defs))
  of TFRK_MODULE:
    let resolved_module_ref = ? fnref.module_ref
    let analyzed_module_ref = ? analyze_def(file_def.file, resolved_module_ref)
    case analyzed_module_ref.kind:
    of RMRK_GENERIC:
      err("{fnref.location} local function calls do not support generics")
    of RMRK_USER:
      let resolved_user_module = analyzed_module_ref.module
      let analyzed_user_module_def = ? file_def.find_module_def(
          new_resolved_module(resolved_user_module))
      let analyzed_user_function_defs = ? analyzed_user_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let analyzed_function_defs = analyzed_user_function_defs.map_it(
          new_analyzed_function_definition(it))
      var concrete_function_defs = analyzed_user_function_defs.map_it(
          it.concretize(analyzed_module_ref.concrete_map))
      let analyzed_concrete_function_defs = concrete_function_defs.map_it(
          new_analyzed_function_definition(it))
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_concrete_function_defs))

type
  AnalyzedArgumentKind = enum
    RAK_VARIABLE, RAK_LITERAL
  AnalyzedArgument = ref object of RootObj
    module_ref: AnalyzedModuleRef
    case kind: AnalyzedArgumentKind
    of RAK_LITERAL: literal: Literal
    of RAK_VARIABLE: variable: Identifier

proc new_analyzed_argument(module_ref: AnalyzedModuleRef,
    variable: Identifier): AnalyzedArgument =
  AnalyzedArgument(kind: RAK_VARIABLE, module_ref: module_ref,
      variable: variable)

proc new_analyzed_argument(module_ref: AnalyzedModuleRef,
    literal: Literal): AnalyzedArgument =
  AnalyzedArgument(kind: RAK_LITERAL, module_ref: module_ref, literal: literal)

proc location(arg: AnalyzedArgument): Location =
  case arg.kind:
  of RAK_LITERAL: arg.literal.location
  of RAK_VARIABLE: arg.variable.location

proc generic_impls(arg: AnalyzedArgument): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  arg.module_ref.generic_impls

proc asl(arg: AnalyzedArgument): string =
  case arg.kind:
  of RAK_LITERAL: arg.literal.asl
  of RAK_VARIABLE: arg.variable.asl

proc c(arg: AnalyzedArgument): string = arg.asl

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope, args: seq[
    Argument], argdefs: seq[AnalyzedArgumentDefinition]): Result[seq[
    AnalyzedArgument], string] =
  var analyzed_args: seq[AnalyzedArgument]
  for (arg, def) in zip(args, argdefs):
    case arg.kind:
    of AK_VARIABLE:
      let variable = ? arg.variable
      let arg_module_ref = ? scope.get(variable)
      if arg_module_ref != def.module_ref:
        return err(fmt"{arg.location} expected `{variable.asl}` to be of type `{def.module_ref.asl}` but found `{arg_module_ref.asl}`")
      analyzed_args.add(new_analyzed_argument(arg_module_ref, variable))
    of AK_LITERAL:
      let literal = ? arg.literal
      ? def.module_ref.module.validate(literal)
      analyzed_args.add(new_analyzed_argument(def.module_ref, literal))
  ok(analyzed_args)

type AnalyzedFunctionCall = ref object of RootObj
  fnref: AnalyzedFunctionRef
  concrete_def: AnalyzedFunctionDefinition
  original_def: AnalyzedFunctionDefinition
  args: seq[AnalyzedArgument]

proc new_analyzed_function_call(fnref: AnalyzedFunctionRef,
    original_def: AnalyzedFunctionDefinition,
        concrete_def: AnalyzedFunctionDefinition,
    args: seq[AnalyzedArgument]): AnalyzedFunctionCall =
  AnalyzedFunctionCall(fnref: fnref, original_def: original_def,
      concrete_def: concrete_def, args: args)

proc location(fncall: AnalyzedFunctionCall): Location =
  fncall.fnref.location

proc returns(fncall: AnalyzedFunctionCall): AnalyzedModuleRef =
  fncall.concrete_def.returns

proc generic_impls(fncall: AnalyzedFunctionCall): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(fncall.fnref.generic_impls)
  impl_set = impl_set.merge(fncall.concrete_def.generic_impls)
  for arg in fncall.args: impl_set = impl_set.merge(arg.generic_impls)
  return impl_set

proc asl(fncall: AnalyzedFunctionCall): string =
  let args_str = fncall.args.map_it(it.asl).join(", ")
  fncall.fnref.asl & "(" & args_str & ")"

proc c(fncall: AnalyzedFunctionCall, result_arg: string): seq[string] =
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
    of RMRK_USER:
      var new_args: seq[string]
      for impl in module_ref.impls:
        let child = impl.module_ref
        case child.kind:
        of RMRK_GENERIC:
          new_args.add(fmt"__asl_impl_id_{child.generic.id}")
        of RMRK_USER:
          let arg = fmt"__asl_impl_id_{child.location.hash.to_hex}"
          lines.add(fmt"U64 {arg} = {child.module.id};")
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

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    fncall: ResolvedUserFunctionCall): Result[AnalyzedFunctionCall, string] =
  let analyzed_function_ref = ? analyze(file_def, module_def, fncall.fnref)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for (original_def, concrete_def) in analyzed_function_ref.defs:
    let maybe_analyzed_args = analyze(file_def, scope,
        fncall.args, concrete_def.args)
    if maybe_analyzed_args.is_ok:
      return ok(new_analyzed_function_call(analyzed_function_ref, original_def,
          concrete_def, maybe_analyzed_args.get))
    else:
      error_message.add(maybe_analyzed_args.error)
      error_message.add(concrete_def.asl)
  err(error_message.join("\n"))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    fncall: ResolvedUserFunctionCall): Result[AnalyzedFunctionCall, string] =
  let analyzed_function_ref = ? analyze(file_def, fncall.fnref)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for (original_def, concrete_def) in analyzed_function_ref.defs:
    let maybe_analyzed_args = analyze(file_def, scope, fncall.args,
        concrete_def.args)
    if maybe_analyzed_args.is_ok:
      return ok(new_analyzed_function_call(analyzed_function_ref, original_def,
          concrete_def, maybe_analyzed_args.get))

    error_message.add(concrete_def.asl)
  err(error_message.join("\n"))

type AnalyzedStructRef = ref object of RootObj
  module_ref: AnalyzedModuleRef
  origin: AnalyzedStruct
  struct: AnalyzedStruct

proc new_analyzed_struct_ref(module_ref: AnalyzedModuleRef,
    origin: AnalyzedStruct, struct: AnalyzedStruct): AnalyzedStructRef =
  AnalyzedStructRef(module_ref: module_ref, origin: origin, struct: struct)

proc generic_impls(struct_ref: AnalyzedStructRef): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  struct_ref.module_ref.generic_impls

proc asl(struct_ref: AnalyzedStructRef): string =
  let suffix =
    case struct_ref.struct.kind:
    of RSK_DEFAULT: ""
    of RSK_NAMED: fmt".{struct_ref.struct.name.asl}"
  fmt"{struct_ref.module_ref.asl}{suffix}"

proc c(struct_ref: AnalyzedStructRef): string =
  case struct_ref.struct.kind:
  of RSK_DEFAULT: fmt"{struct_ref.module_ref.name}"
  of RSK_NAMED: fmt"{struct_ref.module_ref.name}_{struct_ref.struct.name.asl}"

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    struct_ref: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, module_def.module,
      struct_ref.module_ref)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC:
    err(fmt"1 {struct_ref.location} generic `{analyzed_module_ref.generic.name.asl}` is not a struct")
  of RMRK_USER:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(new_resolved_module(resolved_module))
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = analyzed_module_def.find_struct()
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_default_struct(struct_ref.location,
            analyzed_module_def.name.asl))
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = analyzed_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_named_struct(struct_ref.location,
            analyzed_module_def.name.asl, struct_name.asl))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    struct_ref: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, struct_ref.module_ref)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC:
    err(fmt"2 {struct_ref.location} generic `{analyzed_module_ref.generic.name.asl}` is not a struct")
  of RMRK_USER:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(new_resolved_module(resolved_module))
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = analyzed_module_def.find_struct()
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_default_struct(struct_ref.location,
            analyzed_module_def.name.asl))
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = analyzed_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let analyzed_struct = maybe_struct.get
        let analyzed_concretized_struct = analyzed_struct.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_ref(analyzed_module_ref, analyzed_struct,
            analyzed_concretized_struct))
      else:
        err(err_no_named_struct(struct_ref.location,
            analyzed_module_def.name.asl, struct_name.asl))

type AnalyzedStructInit = ref object of RootObj
  struct_ref: AnalyzedStructRef
  fields: seq[AnalyzedArgument]

proc new_analyzed_struct_init(struct_ref: AnalyzedStructRef, fields: seq[
    AnalyzedArgument]): AnalyzedStructInit =
  AnalyzedStructInit(struct_ref: struct_ref, fields: fields)

proc returns(struct_init: AnalyzedStructInit): AnalyzedModuleRef =
  struct_init.struct_ref.module_ref

proc generic_impls(struct_init: AnalyzedStructInit): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(struct_init.struct_ref.generic_impls)
  for field in struct_init.fields: impl_set = impl_set.merge(
      field.generic_impls)
  return impl_set

proc asl(struct_init: AnalyzedStructInit): string =
  var args: seq[string]
  for (field_def, field_arg) in zip(struct_init.struct_ref.struct.fields,
      struct_init.fields):
    args.add(fmt"{field_def.name.asl}: {field_arg.asl}")
  let args_str = args.join(", ")
  struct_init.struct_ref.asl & " { " & args_str & " }"

proc c(struct_init: AnalyzedStructInit, result_arg: string): seq[string] =
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

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    init: ResolvedStructInit): Result[AnalyzedStructInit, string] =
  let analyzed_struct_ref = ? analyze(file_def, module_def, scope,
      init.struct_ref)

  var args = new_seq[Argument](analyzed_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let analyzed_field_index = ? analyzed_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(analyzed_field_index)
    args[analyzed_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < analyzed_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let analyzed_fields = ? analyze(file_def, scope, args,
      analyzed_struct_ref.struct.fields)
  ok(new_analyzed_struct_init(analyzed_struct_ref, analyzed_fields))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedStructInit): Result[AnalyzedStructInit, string] =
  let analyzed_struct_ref = ? analyze(file_def, scope, init.struct_ref)

  var args = new_seq[Argument](analyzed_struct_ref.struct.fields.len)
  var found_field_indices: Hashset[int]
  for field in init.fields:
    let analyzed_field_index = ? analyzed_struct_ref.struct.find_field_index(field.name)
    found_field_indices.incl(analyzed_field_index)
    args[analyzed_field_index] = field.value

  # NOTE: Only a subset of fields are given to initilaizer
  if found_field_indices.len < analyzed_struct_ref.struct.fields.len:
    return err(fmt"{init.location} struct initializer is missing fields")

  let analyzed_fields = ? analyze(file_def, scope, args,
      analyzed_struct_ref.struct.fields)
  ok(new_analyzed_struct_init(analyzed_struct_ref, analyzed_fields))

type AnalyzedLiteral = ref object of RootObj
  module_ref: AnalyzedModuleRef
  literal: Literal

proc new_analyzed_literal(module_ref: AnalyzedModuleRef,
    literal: Literal): AnalyzedLiteral =
  AnalyzedLiteral(module_ref: module_ref, literal: literal)

proc returns(literal: AnalyzedLiteral): AnalyzedModuleRef =
  literal.module_ref

proc generic_impls(literal: AnalyzedLiteral): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  literal.module_ref.generic_impls

proc asl(literal: AnalyzedLiteral): string =
  fmt"{literal.module_ref.asl} {literal.literal.asl}"

proc c(literal: AnalyzedLiteral, result_arg: string): string =
  fmt"{literal.module_ref.c} {result_arg} = {literal.literal.asl};"

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
        init: ResolvedLiteralInit): Result[AnalyzedLiteral, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, module_def.module,
      init.module_ref)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC: err(fmt"{init.location} Generics are not supported via literal initialization")
  of RMRK_USER:
    ? analyzed_module_ref.module.validate(init.literal)
    ok(new_analyzed_literal(analyzed_module_ref, init.literal))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedLiteralInit): Result[AnalyzedLiteral, string] =
  let analyzed_module_ref = ? analyze_def(file_def.file, init.module_ref)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC: err(fmt"{init.location} Generics are not supported via literal initialization")
  of RMRK_USER:
    ? analyzed_module_ref.module.validate(init.literal)
    ok(new_analyzed_literal(analyzed_module_ref, init.literal))

type
  AnalyzedInitializerKind = enum
    RIK_LITERAL, RIK_STRUCT
  AnalyzedInitializer = ref object of RootObj
    case kind: AnalyzedInitializerKind
    of RIK_LITERAL: literal: AnalyzedLiteral
    of RIK_STRUCT: struct: AnalyzedStructInit

proc new_analyzed_initializer(struct: AnalyzedStructInit): AnalyzedInitializer =
  AnalyzedInitializer(kind: RIK_STRUCT, struct: struct)

proc new_analyzed_initializer(literal: AnalyzedLiteral): AnalyzedInitializer =
  AnalyzedInitializer(kind: RIK_LITERAL, literal: literal)

proc returns(init: AnalyzedInitializer): AnalyzedModuleRef =
  case init.kind:
  of RIK_STRUCT: init.struct.returns
  of RIK_LITERAL: init.literal.returns

proc generic_impls(init: AnalyzedInitializer): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  case init.kind:
  of RIK_LITERAL: init.literal.generic_impls
  of RIK_STRUCT: init.struct.generic_impls

proc asl(init: AnalyzedInitializer): string =
  case init.kind:
  of RIK_LITERAL: init.literal.asl
  of RIK_STRUCT: init.struct.asl

proc c(init: AnalyzedInitializer, result_arg: string): seq[string] =
  case init.kind:
  of RIK_LITERAL: @[init.literal.c(result_arg)]
  of RIK_STRUCT: init.struct.c(result_arg)

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let analyzed_struct_init = ? analyze(file_def, module_def, scope, struct_init)
    ok(new_analyzed_initializer(analyzed_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let analyzed_literal = ? analyze(file_def, module_def, scope, literal_init)
    ok(new_analyzed_initializer(analyzed_literal))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let analyzed_struct_init = ? analyze(file_def, scope, struct_init)
    ok(new_analyzed_initializer(analyzed_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let analyzed_literal = ? analyze(file_def, scope, literal_init)
    ok(new_analyzed_initializer(analyzed_literal))

type AnalyzedStructGet = ref object of RootObj
  variable: AnalyzedArgumentDefinition
  field: AnalyzedArgumentDefinition

proc new_analyzed_struct_get(variable: AnalyzedArgumentDefinition,
    field: AnalyzedArgumentDefinition): AnalyzedStructGet =
  AnalyzedStructGet(variable: variable, field: field)

proc returns(struct_get: AnalyzedStructGet): AnalyzedModuleRef =
  struct_get.field.module_ref

proc generic_impls(struct_get: AnalyzedStructGet): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(struct_get.variable.generic_impls)
  impl_set = impl_set.merge(struct_get.field.generic_impls)
  return impl_set

proc asl(struct_get: AnalyzedStructGet): string =
  fmt"{struct_get.variable.name.asl}.{struct_get.field.name.asl}"

proc c(struct_get: AnalyzedStructGet, result_arg: string): string =
  fmt"{struct_get.field.module_ref.c} {result_arg} = {struct_get.variable.module_ref.name}_get_{struct_get.field.name.asl}({struct_get.variable.name.asl});"

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    struct_get: ResolvedStructGet): Result[AnalyzedStructGet, string] =
  let analyzed_module_ref = ? scope.get(struct_get.variable)
  let analyzed_variable = new_analyzed_argument_definition(analyzed_module_ref,
      struct_get.variable)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC: err(fmt"4 {struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of RMRK_USER:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(new_resolved_module(resolved_module))
    if analyzed_module_def.structs.len == 0:
      err(fmt"5 {struct_get.location} module `{analyzed_module_def.name.asl}` is not a struct")
    elif analyzed_module_def.structs.len > 1:
      err(fmt"{struct_get.location} module `{analyzed_module_def.name.asl}` is a union")
    else:
      let maybe_default_struct = analyzed_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(err_no_default_struct(struct_get.location,
            analyzed_module_def.name.asl))
      else:
        let analyzed_struct = maybe_default_struct.get
        let analyzed_field_module_ref = ? analyzed_struct.find_field(
            struct_get.field)
        let analyzed_field = analyzed_field_module_ref.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_get(analyzed_variable, analyzed_field))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    struct_get: ResolvedStructGet): Result[AnalyzedStructGet, string] =
  let analyzed_module_ref = ? scope.get(struct_get.variable)
  let analyzed_variable = new_analyzed_argument_definition(analyzed_module_ref,
      struct_get.variable)
  case analyzed_module_ref.kind:
  of RMRK_GENERIC: err(fmt"7 {struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of RMRK_USER:
    let resolved_module = analyzed_module_ref.module
    let analyzed_module_def = ? file_def.find_module_def(new_resolved_module(resolved_module))
    if analyzed_module_def.structs.len == 0:
      err(fmt"8 {struct_get.location} module `{analyzed_module_def.name.asl}` is not a struct")
    elif analyzed_module_def.structs.len > 1:
      err(fmt"9 {struct_get.location} module `{analyzed_module_def.name.asl}` is a union")
    else:
      let maybe_default_struct = analyzed_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(err_no_default_struct(struct_get.location,
            analyzed_module_def.name.asl))
      else:
        let analyzed_struct = maybe_default_struct.get
        let analyzed_field_module_ref = ? analyzed_struct.find_field(
            struct_get.field)
        let analyzed_field = analyzed_field_module_ref.concretize(
            analyzed_module_ref.concrete_map)
        ok(new_analyzed_struct_get(analyzed_variable, analyzed_field))

type
  AnalyzedStructPatternKind = enum
    RSPK_DEFAULT, RSPK_NAMED
  AnalyzedStructPattern = ref object of RootObj
    original_struct: AnalyzedStruct
    args: seq[(AnalyzedArgumentDefinition, Identifier)]
    location: Location
    case kind: AnalyzedStructPatternKind
    of RSPK_DEFAULT: discard
    of RSPK_NAMED: name: Identifier

proc new_analyzed_struct_pattern(original_struct: AnalyzedStruct, args: seq[(
    AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_DEFAULT, original_struct: original_struct,
      args: args, location: location)

proc new_analyzed_struct_pattern(original_struct: AnalyzedStruct,
    name: Identifier, args: seq[(AnalyzedArgumentDefinition, Identifier)],
    location: Location): AnalyzedStructPattern =
  AnalyzedStructPattern(kind: RSPK_NAMED, original_struct: original_struct,
      name: name, args: args, location: location)

proc id(pattern: AnalyzedStructPattern): uint64 =
  pattern.original_struct.id

proc hash(pattern: AnalyzedStructPattern): Hash =
  case pattern.kind:
  of RSPK_DEFAULT: "".hash
  of RSPK_NAMED: pattern.name.asl.hash

proc generic_impls(pattern: AnalyzedStructPattern): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for (argdef, _) in pattern.args: impl_set = impl_set.merge(
      argdef.generic_impls)
  return impl_set

proc asl(struct_pattern: AnalyzedStructPattern): string =
  let prefix =
    case struct_pattern.kind:
    of RSPK_DEFAULT: ""
    of RSPK_NAMED: fmt"{struct_pattern.name.asl} "

  var args: seq[string]
  for (field, name) in struct_pattern.args:
    args.add(fmt"{name.asl}: {field.name.asl}")

  let args_str = args.join(", ")
  prefix & "{ " & args_str & " }"

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, pattern: StructPattern): Result[
    AnalyzedStructPattern, string] =
  case operand.kind:
  of RMRK_GENERIC: err(fmt"{pattern.location} match expression does not support generics")
  of RMRK_USER:
    let module = operand.module
    let analyzed_operand_module = ? file_def.find_module_def(
        new_resolved_module(module))
    if analyzed_operand_module.structs.len == 0:
      return err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a module and not a union")
    if analyzed_operand_module.structs.len == 1:
      return err(fmt"{pattern.location} module `{analyzed_operand_module.name.asl}` is a struct and not a union")

    case pattern.kind:
    of SPK_DEFAULT:
      let analyzed_struct = ? analyzed_operand_module.find_struct()
      let concrete_struct = analyzed_struct.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      ok(new_analyzed_struct_pattern(analyzed_struct, analyzed_fields,
          pattern.location))
    of SPK_NAMED:
      let struct_name = ? pattern.struct
      let analyzed_struct = ? analyzed_operand_module.find_struct(struct_name)
      let concrete_struct = analyzed_struct.concretize(operand.concrete_map)
      var analyzed_fields: seq[(AnalyzedArgumentDefinition, Identifier)]
      for (key, value) in pattern.args:
        let field = ? concrete_struct.find_field(key)
        let value_arg = new_analyzed_argument_definition(field.module_ref, value)
        analyzed_fields.add((value_arg, key))
      ok(new_analyzed_struct_pattern(analyzed_struct, struct_name,
          analyzed_fields, pattern.location))

type
  AnalyzedCasePatternKind = enum
    RCPK_LITERAL, RCPK_STRUCT
  AnalyzedCasePattern = ref object of RootObj
    location: Location
    case kind: AnalyzedCasePatternKind
    of RCPK_LITERAL:
      native_module: ResolvedUserModule
      literal: Literal
    of RCPK_STRUCT:
      struct: AnalyzedStructPattern

proc new_analyzed_case_pattern(native_module: ResolvedUserModule,
    literal: Literal, location: Location): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: RCPK_LITERAL, native_module: native_module,
      literal: literal, location: location)

proc new_analyzed_case_pattern(struct: AnalyzedStructPattern,
    location: Location): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: RCPK_STRUCT, struct: struct, location: location)

proc hash(pattern: AnalyzedCasePattern): Hash =
  case pattern.kind:
  of RCPK_LITERAL: pattern.literal.asl.hash
  of RCPK_STRUCT: pattern.struct.hash

proc `==`(self: AnalyzedCasePattern, other: AnalyzedCasePattern): bool =
  self.hash == other.hash

proc generic_impls(pattern: AnalyzedCasePattern): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  case pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT: impl_set = impl_set.merge(pattern.struct.generic_impls)
  return impl_set

proc asl(case_pattern: AnalyzedCasePattern): string =
  case case_pattern.kind:
  of RCPK_LITERAL: case_pattern.literal.asl
  of RCPK_STRUCT: case_pattern.struct.asl

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, pattern: CasePattern): Result[
    AnalyzedCasePattern, string] =
  case pattern.kind:
  of CPK_LITERAL:
    let literal = ? pattern.literal
    case operand.kind:
    of RMRK_GENERIC:
      err(fmt"{pattern.location} match expression does not support generic operands")
    of RMRK_USER:
      let module = operand.module
      case module.name.asl:
      of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64":
        ? module.validate(literal)
        ok(new_analyzed_case_pattern(module, literal, pattern.location))
      else:
        err(fmt"{pattern.location} only integer literals are supported in the case pattern")
  of CPK_STRUCT:
    let struct = ? pattern.struct
    let analyzed_struct_pattern = ? analyze(file_def, scope, operand, struct)
    ok(new_analyzed_case_pattern(analyzed_struct_pattern, pattern.location))

proc analyze(scope: FunctionScope, variable: ResolvedVariable): Result[
    AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? scope.get(variable.name)
  ok(new_analyzed_argument_definition(analyzed_module_ref, variable.name,
      variable.location))

type
  AnalyzedExpressionKind = enum
    REK_MATCH, REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  AnalyzedExpression = ref object of RootObj
    case kind: AnalyzedExpressionKind
    of REK_MATCH: match: AnalyzedMatch
    of REK_FNCALL: fncall: AnalyzedFunctionCall
    of REK_INIT: init: AnalyzedInitializer
    of REK_STRUCT_GET: struct_get: AnalyzedStructGet
    of REK_VARIABLE: variable: AnalyzedArgumentDefinition
  AnalyzedStatement = ref object of RootObj
    arg: AnalyzedArgumentDefinition
    expression: AnalyzedExpression
  AnalyzedCase = ref object of RootObj
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]
    location: Location
  AnalyzedElse = ref object of RootObj
    location: Location
    statements: seq[AnalyzedStatement]
  AnalyzedMatchKind = enum
    RMK_CASE_ONLY, RMK_COMPLETE
  AnalyzedMatch = ref object of RootObj
    location: Location
    operand: AnalyzedArgumentDefinition
    case_blocks: seq[AnalyzedCase]
    case kind: AnalyzedMatchKind
    of RMK_CASE_ONLY: discard
    of RMK_COMPLETE: else_block: AnalyzedElse

proc new_analyzed_expression(match: AnalyzedMatch): AnalyzedExpression =
  AnalyzedExpression(kind: REK_MATCH, match: match)

proc new_analyzed_expression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: REK_FNCALL, fncall: fncall)

proc new_analyzed_expression(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: REK_INIT, init: init)

proc new_analyzed_expression(struct_get: AnalyzedStructGet): AnalyzedExpression =
  AnalyzedExpression(kind: REK_STRUCT_GET, struct_get: struct_get)

proc new_analyzed_expression(variable: AnalyzedArgumentDefinition): AnalyzedExpression =
  AnalyzedExpression(kind: REK_VARIABLE, variable: variable)

proc returns(match: AnalyzedMatch): AnalyzedModuleRef

proc returns(expression: AnalyzedExpression): AnalyzedModuleRef =
  case expression.kind:
  of REK_MATCH: expression.match.returns
  of REK_FNCALL: expression.fncall.returns
  of REK_INIT: expression.init.returns
  of REK_STRUCT_GET: expression.struct_get.returns
  of REK_VARIABLE: expression.variable.module_ref

proc generic_impls(match: AnalyzedMatch): Table[ResolvedUserModule, seq[HashSet[
    AnalyzedImpl]]]

proc generic_impls(expression: AnalyzedExpression): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  case expression.kind:
  of REK_MATCH: expression.match.generic_impls
  of REK_FNCALL: expression.fncall.generic_impls
  of REK_INIT: expression.init.generic_impls
  of REK_STRUCT_GET: expression.struct_get.generic_impls
  of REK_VARIABLE: expression.variable.generic_impls

proc asl(match: AnalyzedMatch, indent: string): seq[string]

proc asl(expression: AnalyzedExpression, indent: string): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.asl(indent)
  of REK_FNCALL: @[expression.fncall.asl]
  of REK_INIT: @[expression.init.asl]
  of REK_STRUCT_GET: @[expression.struct_get.asl]
  of REK_VARIABLE: @[expression.variable.asl]

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string]

proc c(expression: AnalyzedExpression, result_arg: AnalyzedArgumentDefinition): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.c(result_arg)
  of REK_FNCALL: expression.fncall.c(result_arg.name.asl)
  of REK_INIT: expression.init.c(result_arg.name.asl)
  of REK_STRUCT_GET: @[expression.struct_get.c(result_arg.name.asl)]
  of REK_VARIABLE: @[fmt"{expression.variable.module_ref.c} {result_arg.name.asl} = {expression.variable.name.asl};"]

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string]

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let analyzed_function_call = ? analyze(file_def, module_def, scope, fncall)
    ok(new_analyzed_expression(analyzed_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let analyzed_init = ? analyze(file_def, module_def, scope, init)
    ok(new_analyzed_expression(analyzed_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let analyzed_struct_get = ? analyze(file_def, module_def, scope, struct_get)
    ok(new_analyzed_expression(analyzed_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let analyzed_variable = ? analyze(scope, variable)
    ok(new_analyzed_expression(analyzed_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let analyzed_match = ? analyze(file_def, module_def, scope, match)
    ok(new_analyzed_expression(analyzed_match))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string]

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let analyzed_function_call = ? analyze(file_def, scope, fncall)
    ok(new_analyzed_expression(analyzed_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let analyzed_init = ? analyze(file_def, scope, init)
    ok(new_analyzed_expression(analyzed_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let analyzed_struct_get = ? analyze(file_def, scope, struct_get)
    ok(new_analyzed_expression(analyzed_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let analyzed_variable = ? analyze(scope, variable)
    ok(new_analyzed_expression(analyzed_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let analyzed_match = ? analyze(file_def, scope, match)
    ok(new_analyzed_expression(analyzed_match))

# Statement
proc new_analyzed_statement(arg: AnalyzedArgumentDefinition,
    expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(arg: arg, expression: expression)

proc returns(statement: AnalyzedStatement): AnalyzedModuleRef =
  statement.expression.returns

proc generic_impls(statement: AnalyzedStatement): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] = statement.expression.generic_impls

proc asl(statement: AnalyzedStatement, indent: string): seq[string] =
  var lines = statement.expression.asl(indent)
  lines[0] = fmt"{statement.arg.asl} = {lines[0]}"
  lines

proc c(statement: AnalyzedStatement): seq[string] =
  statement.expression.c(statement.arg)

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  let analyzed_expression = ? analyze(file_def, module_def, scope,
      statement.expression)
  let analyzed_arg = new_analyzed_argument_definition(
      analyzed_expression.returns, statement.arg)
  ok(new_analyzed_statement(analyzed_arg, analyzed_expression))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  let analyzed_expression = ? analyze(file_def, scope, statement.expression)
  let analyzed_arg = new_analyzed_argument_definition(
      analyzed_expression.returns, statement.arg)
  ok(new_analyzed_statement(analyzed_arg, analyzed_expression))

# Case
proc new_analyzed_case(pattern: AnalyzedCasePattern, statements: seq[
    AnalyzedStatement], location: Location): AnalyzedCase =
  AnalyzedCase(pattern: pattern, statements: statements, location: location)

proc returns(case_block: AnalyzedCase): AnalyzedModuleRef =
  case_block.statements[^1].returns

proc generic_impls(case_block: AnalyzedCase): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(case_block.pattern.generic_impls)
  for statement in case_block.statements:
    impl_set = impl_set.merge(statement.generic_impls)
  return impl_set

proc asl(case_block: AnalyzedCase, indent: string): seq[string] =
  var lines = @[fmt"case {case_block.pattern.asl}:"]
  for statement in case_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  lines

proc c(case_block: AnalyzedCase, operand: AnalyzedArgumentDefinition,
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

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, case_block: ResolvedCase): Result[AnalyzedCase, string] =
  var case_scope = scope.clone()
  let analyzed_case_pattern = ? analyze(file_def, scope, operand,
      case_block.pattern)

  case analyzed_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let analyzed_struct_pattern = analyzed_case_pattern.struct
    for (field, name) in analyzed_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var analyzed_statements: seq[AnalyzedStatement]
  for statement in case_block.statements:
    let analyzed_statement = ? analyze(file_def, module_def, case_scope, statement)
    analyzed_statements.add(analyzed_statement)
    case_scope = ? case_scope.set(analyzed_statement.arg)
  ok(new_analyzed_case(analyzed_case_pattern, analyzed_statements,
      case_block.location))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, case_block: ResolvedCase): Result[AnalyzedCase, string] =
  var case_scope = scope.clone()
  let analyzed_case_pattern = ? analyze(file_def, scope, operand,
      case_block.pattern)
  case analyzed_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let analyzed_struct_pattern = analyzed_case_pattern.struct
    for (field, name) in analyzed_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var analyzed_statements: seq[AnalyzedStatement]
  for statement in case_block.statements:
    let analyzed_statement = ? analyze(file_def, case_scope, statement)
    analyzed_statements.add(analyzed_statement)
    case_scope = ? case_scope.set(analyzed_statement.arg)
  ok(new_analyzed_case(analyzed_case_pattern, analyzed_statements,
      case_block.location))

# Else
proc new_analyzed_else(statements: seq[AnalyzedStatement],
    location: Location): AnalyzedElse =
  AnalyzedElse(statements: statements, location: location)

proc returns(else_block: AnalyzedElse): AnalyzedModuleRef =
  else_block.statements[^1].returns

proc generic_impls(else_block: AnalyzedElse): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for statement in else_block.statements: impl_set = impl_set.merge(
      statement.generic_impls)
  return impl_set

proc asl(else_block: AnalyzedElse, indent: string): seq[string] =
  var lines = @["else:"]
  for statement in else_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c(else_block: AnalyzedElse, result_arg: string): seq[string] =
  var lines: seq[string]
  lines.add("else {")
  for statement in else_block.statements:
    lines.add(statement.c)
  let last_arg = else_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_arg};")
  lines.add("}")
  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    else_block: ResolvedElse): Result[AnalyzedElse, string] =
  var else_scope = scope.clone()
  var analyzed_statements: seq[AnalyzedStatement]
  for statement in else_block.statements:
    let analyzed_statement = ? analyze(file_def, module_def, else_scope, statement)
    analyzed_statements.add(analyzed_statement)
    else_scope = ? else_scope.set(analyzed_statement.arg)
  ok(new_analyzed_else(analyzed_statements, else_block.location))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    else_block: ResolvedElse): Result[AnalyzedElse, string] =
  var else_scope = scope.clone()
  var analyzed_statements: seq[AnalyzedStatement]
  for statement in else_block.statements:
    let analyzed_statement = ? analyze(file_def, else_scope, statement)
    analyzed_statements.add(analyzed_statement)
    else_scope = ? else_scope.set(analyzed_statement.arg)
  ok(new_analyzed_else(analyzed_statements, else_block.location))

# Match
proc new_analyzed_match(operand: AnalyzedArgumentDefinition, case_blocks: seq[
    AnalyzedCase], else_block: AnalyzedElse,
    location: Location): AnalyzedMatch =
  AnalyzedMatch(kind: RMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc new_analyzed_match(operand: AnalyzedArgumentDefinition, case_blocks: seq[
    AnalyzedCase], location: Location): AnalyzedMatch =
  AnalyzedMatch(kind: RMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc returns(match: AnalyzedMatch): AnalyzedModuleRef =
  match.case_blocks[0].returns

proc generic_impls(match: AnalyzedMatch): Table[ResolvedUserModule, seq[HashSet[
    AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  for case_block in match.case_blocks: impl_set = impl_set.merge(
      case_block.generic_impls)

  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: impl_set = impl_set.merge(match.else_block.generic_impls)
  return impl_set

proc asl(match: AnalyzedMatch, indent: string): seq[string] =
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

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string] =
  var lines: seq[string]
  lines.add(fmt"{result_arg.c};")
  for index, case_block in match.case_blocks:
    lines.add(case_block.c(match.operand, result_arg.name.asl, index == 0))
  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: lines.add(match.else_block.c(result_arg.name.asl))
  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string] =
  let analyzed_operand_module_ref = ? scope.get(match.operand)
  let analyzed_operand = new_analyzed_argument_definition(
      analyzed_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, module_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      # NOTE: Ensure all the case block returns type is same.
      if case_block.returns != analyzed_case_blocks[0].returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_case_blocks[0].returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_USER:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(
          new_resolved_module(module))
      if unique_patterns.len < analyzed_operand_module.structs.len:
        return err(fmt"{match.location} match expression does not cover all cases, an else block is required")

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, module_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    let else_block = ? match.else_block
    let analyzed_else_block = ? analyze(file_def, module_def, scope, else_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_else_block.returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_USER:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(
          new_resolved_module(module))
      if unique_patterns.len == analyzed_operand_module.structs.len:
        return err(fmt"{match.location} match expression already covers all cases, else block is not required")

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        analyzed_else_block, match.location))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string] =
  let analyzed_operand_module_ref = ? scope.get(match.operand)
  let analyzed_operand = new_analyzed_argument_definition(
      analyzed_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_case_blocks[0].returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_case_blocks[0].returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_USER:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(
          new_resolved_module(module))
      if unique_patterns.len < analyzed_operand_module.structs.len:
        return err(fmt"{match.location} match expression does not cover all cases, an else block is required")

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    let else_block = ? match.else_block
    let analyzed_else_block = ? analyze(file_def, scope, else_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_else_block.returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of RMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of RMRK_USER:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(
          new_resolved_module(module))
      if unique_patterns.len == analyzed_operand_module.structs.len:
        return err(fmt"{match.location} match expression already covers all cases, else block is not required")

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        analyzed_else_block, match.location))

type AnalyzedUserFunction = ref object of RootObj
  def: AnalyzedUserFunctionDefinition
  steps: seq[AnalyzedStatement]

proc new_analyzed_user_function(def: AnalyzedUserFunctionDefinition, steps: seq[
    AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(def: def, steps: steps)

proc statements(function: AnalyzedUserFunction): seq[AnalyzedStatement] =
  function.steps

proc generic_impls(function: AnalyzedUserFunction): Table[ResolvedUserModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(function.def.generic_impls)
  for step in function.steps: impl_set = impl_set.merge(step.generic_impls)
  return impl_set

proc asl(function: AnalyzedUserFunction, indent: string): seq[string] =
  var lines = @[function.def.asl]
  for statement in function.steps:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c(function: AnalyzedUserFunction): seq[string] =
  var lines: seq[string]
  lines.add(function.def.h.replace(";", ""))
  lines.add("{")
  for statement in function.statements:
    lines.add(statement.c)
  let last_arg = function.statements[^1].arg.name.asl
  lines.add(fmt"return {last_arg};")
  lines.add("}")
  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition,
        function: ResolvedUserFunction): Result[
    AnalyzedUserFunction, string] =
  var scope = FunctionScope()
  let analyzed_function_def = ? module_def.find_function_def(function.def)
  for arg in analyzed_function_def.args: scope = ? scope.set(arg)

  var analyzed_steps: seq[AnalyzedStatement]
  for step in function.steps:
    let analyzed_function_step = ? analyze(file_def, module_def, scope, step)
    analyzed_steps.add(analyzed_function_step)
    scope = ? scope.set(analyzed_function_step.arg)
  ok(new_analyzed_user_function(analyzed_function_def, analyzed_steps))

proc analyze(file_def: AnalyzedFileDefinition,
    function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  var scope = FunctionScope()
  let analyzed_function_def = ? file_def.find_function_def(function.def)
  for arg in analyzed_function_def.args:
    scope = ? scope.set(arg)

  var analyzed_steps: seq[AnalyzedStatement]
  for step in function.steps:
    let analyzed_function_step = ? analyze(file_def, scope, step)
    analyzed_steps.add(analyzed_function_step)
    scope = ? scope.set(analyzed_function_step.arg)
  ok(new_analyzed_user_function(analyzed_function_def, analyzed_steps))

proc analyze(file_def: AnalyzedFileDefinition,
    function: ResolvedFunction): Result[AnalyzedUserFunction, string] =
  case function.kind:
  of RFK_USER: file_def.analyze(function.user)
  of RFK_EXTERN: err("UNREACHABLE")

type
  AnalyzedFunctionKind = enum
    AFK_USER, AFK_EXTERN
  AnalyzedFunction = ref object of RootObj
    case kind: AnalyzedFunctionKind
    of AFK_USER: user: AnalyzedUserFunction
    of AFK_EXTERN:
      def: AnalyzedUserFunctionDefinition
      extern: ResolvedNativeFunction

proc new_analyzed_function(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: AFK_USER, user: user)

proc new_analyzed_function(def: AnalyzedUserFunctionDefinition,
    extern: ResolvedNativeFunction): AnalyzedFunction =
  AnalyzedFunction(kind: AFK_EXTERN, def: def, extern: extern)

proc generic_impls(function: AnalyzedFunction): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  case function.kind:
  of AFK_USER: function.user.generic_impls
  of AFK_EXTERN:
    var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
    return impl_set

proc asl(function: AnalyzedFunction, indent: string): seq[string] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.asl(indent)

proc c(function: AnalyzedFunction): seq[string] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.c

type AnalyzedUserModule = ref object of RootObj
  def: AnalyzedUserModuleDefinition
  functions: seq[AnalyzedFunction]

proc new_analyzed_user_module(def: AnalyzedUserModuleDefinition, functions: seq[
    AnalyzedFunction]): AnalyzedUserModule =
  AnalyzedUserModule(def: def, functions: functions)

proc generic_impls(module: AnalyzedUserModule): Table[ResolvedUserModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(module.def.generic_impls)
  for function in module.functions: impl_set = impl_set.merge(
      function.generic_impls)
  return impl_set

proc asl(module: AnalyzedUserModule, indent: string): seq[string] =
  var lines = @[fmt"module {module.def.name.asl}:"]
  for line in module.def.asl(indent):
    lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")
  return lines

proc c(module: AnalyzedUserModule, generic_impls: seq[seq[(
    AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]): seq[string] =
  var lines: seq[string]
  for gen_index, (generic, impls) in zip(module.def.generics, generic_impls):
    for def_index, def in generic.defs:
      lines.add(def.h.replace(";", ""))
      lines.add("{")
      lines.add(fmt"switch(__asl_impl_id_{gen_index})")
      lines.add("{")

      for (impl_module, impl_functions) in impls:
        lines.add(fmt"case {impl_module.id}:")
        lines.add("{")
        let impl_fn = impl_functions[def_index]
        var new_args: seq[string]
        for arg_index, (def_arg, impl_arg) in zip(def.args, impl_fn.args):
          case def_arg.module_ref.kind:
          of RMRK_GENERIC:
            case impl_arg.module_ref.kind:
            of RMRK_GENERIC: new_args.add(def_arg.name.asl)
            else:
              let arg_name = fmt"__asl_arg_{arg_index}"
              lines.add(fmt"{impl_arg.module_ref.c} {arg_name} = {impl_arg.module_ref.c}_read({def_arg.name.asl}, 0);")
              new_args.add(arg_name)
          else:
            new_args.add(def_arg.name.asl)

        let args_str = new_args.join(", ")
        lines.add(fmt"{impl_fn.returns.c} __asl_result = {impl_fn.c_name}({args_str});")

        case def.returns.kind:
        of RMRK_GENERIC:
          lines.add(fmt"return System_box_{impl_fn.returns.c}(__asl_result);")
        else:
          lines.add("return __asl_result;")

        lines.add("}")
      lines.add("}")
      lines.add("UNREACHABLE();")
      lines.add("}")

  for function in module.functions:
    lines.add(function.c)
  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedUserModuleDefinition): Result[AnalyzedUserModule, string] =
  var analyzed_functions: seq[AnalyzedFunction]
  for function in module_def.module.functions:
    let analyzed_function =
      case function.kind:
      of RFK_USER:
        let analyzed_user_function = ? analyze(file_def, module_def, function.user)
        new_analyzed_function(analyzed_user_function)
      of RFK_EXTERN:
        let analyzed_function_def = ? module_def.find_function_def(
            function.extern.def)
        new_analyzed_function(analyzed_function_def,
            function.extern)
    analyzed_functions.add(analyzed_function)

  ok(new_analyzed_user_module(module_def, analyzed_functions))

type AnalyzedFile* = ref object of RootObj
  def: AnalyzedFileDefinition
  start_function_def: AnalyzedUserFunctionDefinition
  user_modules: seq[AnalyzedUserModule]
  functions: seq[AnalyzedUserFunction]

proc new_analyzed_file(def: AnalyzedFileDefinition,
    start_function_def: AnalyzedUserFunctionDefinition, user_modules: seq[
    AnalyzedUserModule], functions: seq[AnalyzedUserFunction]): AnalyzedFile =
  AnalyzedFile(def: def, start_function_def: start_function_def,
      user_modules: user_modules, functions: functions)

proc indent(file: AnalyzedFile): int = file.def.file.indent

proc generic_impls*(file: AnalyzedFile): Result[Table[
    AnalyzedUserModuleDefinition, seq[seq[(AnalyzedModuleDefinition, seq[
    AnalyzedFunctionDefinition])]]], string] =
  var impl_set: Table[ResolvedUserModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(file.def.generic_impls)
  for module in file.user_modules: impl_set = impl_set.merge(
      module.generic_impls)
  for function in file.functions: impl_set = impl_set.merge(
      function.generic_impls)

  # Assign index to module for each generic
  var impl_map: Table[AnalyzedUserModuleDefinition, seq[seq[(
      AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]]
  for module, children in impl_set.pairs:
    var analyzed_children: seq[seq[(AnalyzedModuleDefinition, seq[
        AnalyzedFunctionDefinition])]]
    for impls in children:
      var analyzed_impls: seq[(AnalyzedModuleDefinition, seq[
          AnalyzedFunctionDefinition])]
      for impl in impls:
        case impl.module_ref.kind:
        of RMRK_GENERIC:
          echo "[INTERNAL ERROR] - If you see this something is seriously wrong"
        of RMRK_USER:
          let user_module_def = ? file.def.find_module_def(new_resolved_module(
              impl.module_ref.module))
          var analyzed_function_defs: seq[AnalyzedFunctionDefinition]
          for def in impl.defs:
            let analyzed_function_def = ? user_module_def.find_function_def(def)
            analyzed_function_defs.add(new_analyzed_function_definition(analyzed_function_def))
          let analyzed_module_def = new_analyzed_module_definition(user_module_def)
          analyzed_impls.add((analyzed_module_def,
              analyzed_function_defs))
      analyzed_children.add(analyzed_impls)

    let analyzed_user_module_def = ? file.def.find_module_def(
        new_resolved_module(module))
    impl_map[analyzed_user_module_def] = analyzed_children
  return ok(impl_map)

proc asl*(file: AnalyzedFile): string =
  let indent = " ".repeat(file.indent)
  var lines: seq[string]
  for module in file.user_modules:
    lines.add(module.asl(indent))
    lines.add("\n")
  for function in file.functions:
    lines.add(function.asl(indent))
    lines.add("\n")
  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")

proc c*(file: AnalyzedFile): Result[string, string] =
  var lines: seq[string]
  lines.add(file.def.h)
  lines.add(file.def.c)

  let generic_impls = ? file.generic_impls
  for module in file.user_modules:
    let impls = generic_impls.get_or_default(module.def, @[])
    lines.add(module.c(impls))
  for function in file.functions:
    lines.add(function.c)

  let code = @[
    "#include \"runtime.h\"\n",
    lines.join("\n"),
    "\n",
    "int main(int argc, char** argv) {",
    fmt"return {file.start_function_def.c_name}(argc);",
    "}"
  ].join("\n")
  ok(code)

proc analyze(file_def: AnalyzedFileDefinition,
    start_function_def: AnalyzedUserFunctionDefinition): Result[AnalyzedFile, string] =
  var analyzed_user_modules: seq[AnalyzedUserModule]
  for module in file_def.file.user_modules:
    let module_def = ? file_def.find_module_def(new_resolved_module(module))
    let analyzed_user_module = ? analyze(file_def, module_def)
    analyzed_user_modules.add(analyzed_user_module)

  var analyzed_functions: seq[AnalyzedUserFunction]
  for function in file_def.file.functions:
    let analyzed_function = ? analyze(file_def, function)
    analyzed_functions.add(analyzed_function)
  ok(new_analyzed_file(file_def, start_function_def, analyzed_user_modules,
      analyzed_functions))

proc analyze*(file: ResolvedFile): Result[AnalyzedFile, string] =
  let analyzed_file_def = ? analyze_def(file)
  let resolved_start_function_def = ? file.start_def
  let analyzed_start_function = ? analyzed_file_def.find_function_def(resolved_start_function_def)

  let analyzed_file = ? analyze(analyzed_file_def, analyzed_start_function)
  ok(analyzed_file)
