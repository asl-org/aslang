import results, sequtils, strformat, tables, hashes, strutils, sets

import resolver

type
  AnalyzedImpl* = ref object of RootObj
    module_ref: AnalyzedModuleRef
    defs: seq[ResolvedFunctionDefinition]
  AnalyzedModuleRefKind* = enum
    AMRK_MODULE, AMRK_GENERIC
  AnalyzedModuleRef* = ref object of RootObj
    location: Location
    case kind: AnalyzedModuleRefKind
    of AMRK_GENERIC: generic: ResolvedGeneric
    of AMRK_MODULE:
      module: ResolvedModule
      impls: seq[AnalyzedImpl]
      concrete_map: Table[ResolvedGeneric, AnalyzedModuleRef]

# AnalyzedImpl
proc new_analyzed_impl(module_ref: AnalyzedModuleRef, defs: seq[
    ResolvedFunctionDefinition]): AnalyzedImpl =
  AnalyzedImpl(module_ref: module_ref, defs: defs)

proc module_ref*(impl: AnalyzedImpl): AnalyzedModuleRef = impl.module_ref
proc defs*(impl: AnalyzedImpl): seq[ResolvedFunctionDefinition] = impl.defs

# NOTE: Needed due to cyclic dependency between AnalyzedModuleRef and AnalyzedImpl
proc hash(module_ref: AnalyzedModuleRef): Hash

proc hash(impl: AnalyzedImpl): Hash =
  case impl.module_ref.kind:
  of AMRK_GENERIC: impl.module_ref.generic.hash
  of AMRK_MODULE: impl.module_ref.module.hash

proc `==`(self: AnalyzedImpl, other: AnalyzedImpl): bool =
  self.hash == other.hash

proc merge*(
  impl_set_1: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]],
  impl_set_2: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
): Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
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
  AnalyzedModuleRef(kind: AMRK_GENERIC, generic: generic,
      location: location)

proc new_analyzed_module_ref(module: ResolvedModule, impls: seq[
    AnalyzedImpl], location: Location): AnalyzedModuleRef =
  var concrete_map: Table[ResolvedGeneric, AnalyzedModuleRef]
  for (generic, impl) in zip(module.generics, impls):
    concrete_map[generic] = impl.module_ref
  AnalyzedModuleRef(kind: AMRK_MODULE, module: module,
      concrete_map: concrete_map, impls: impls, location: location)

proc location*(module_ref: AnalyzedModuleRef): Location = module_ref.location
proc kind*(module_ref: AnalyzedModuleRef): AnalyzedModuleRefKind = module_ref.kind
proc generic*(module_ref: AnalyzedModuleRef): ResolvedGeneric =
  do_assert module_ref.kind == AMRK_GENERIC, "expected a generic"
  module_ref.generic
proc module*(module_ref: AnalyzedModuleRef): ResolvedModule =
  do_assert module_ref.kind == AMRK_MODULE, "expected a module"
  module_ref.module
proc concrete_map*(module_ref: AnalyzedModuleRef): Table[ResolvedGeneric,
    AnalyzedModuleRef] =
  do_assert module_ref.kind == AMRK_MODULE, "expected a module"
  module_ref.concrete_map
proc impls*(module_ref: AnalyzedModuleRef): seq[AnalyzedImpl] =
  do_assert module_ref.kind == AMRK_MODULE, "expected a module"
  module_ref.impls

proc name*(module_ref: AnalyzedModuleRef): string =
  case module_ref.kind:
  of AMRK_MODULE: module_ref.module.name.asl
  of AMRK_GENERIC: module_ref.generic.name.asl

proc can_be_argument*(module_ref: AnalyzedModuleRef): Result[void, string] =
  case module_ref.kind:
  of AMRK_GENERIC: ok() # generic arguments can be passed as an argument too.
  of AMRK_MODULE:
    let module = module_ref.module
    if module.structs.len > 0: return ok()
    case module.name.asl:
    of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64", "F32", "F64",
        "Pointer", "String": ok()
    else: err(fmt"{module_ref.location} module `{module.name.asl}` can not be passed as an argument")

proc find_function(module_ref: AnalyzedModuleRef,
    def: ResolvedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  case module_ref.kind:
  of AMRK_GENERIC: module_ref.generic.find_function(def)
  of AMRK_MODULE: module_ref.module.find_function(def)

proc concretize*(module_ref: AnalyzedModuleRef, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedModuleRef =
  case module_ref.kind:
  of AMRK_GENERIC:
    concrete_map[module_ref.generic]
  of AMRK_MODULE:
    var concretized_impls: seq[AnalyzedImpl]
    for impl in module_ref.impls:
      let concrete_module_ref = impl.module_ref.concretize(concrete_map)
      concretized_impls.add(new_analyzed_impl(concrete_module_ref, impl.defs))
    new_analyzed_module_ref(module_ref.module, concretized_impls,
        module_ref.location)

proc hash(module_ref: AnalyzedModuleRef): Hash =
  case module_ref.kind:
  of AMRK_GENERIC: module_ref.generic.hash
  of AMRK_MODULE:
    var acc = module_ref.module.hash
    for impl in module_ref.impls:
      acc = acc !& impl.module_ref.hash
    acc

proc `==`*(self: AnalyzedModuleRef, other: AnalyzedModuleRef): bool =
  self.hash == other.hash

# Helper to create impl from analyzed child and constraints
proc analyze_def(resolved_generic: ResolvedGeneric,
    child: ResolvedModuleRef, analyzed_child: AnalyzedModuleRef): Result[
        AnalyzedImpl, string] =
  var constraint_defs: seq[ResolvedFunctionDefinition]
  for def in resolved_generic.concrete_defs(child.self()):
    constraint_defs.add( ? analyzed_child.find_function(def))
  ok(new_analyzed_impl(analyzed_child, constraint_defs))

proc generic_impls*(module_ref: AnalyzedModuleRef): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  case module_ref.kind:
  of AMRK_GENERIC: discard
  of AMRK_MODULE:
    if module_ref.impls.len > 0:
      var generics: seq[HashSet[AnalyzedImpl]]
      for index, impl in module_ref.impls.pairs:
        generics.add(init_hashset[AnalyzedImpl]())
        case impl.module_ref.kind:
        of AMRK_GENERIC: discard
        of AMRK_MODULE: generics[index].incl(impl)
      impl_set[module_ref.module] = generics
  return impl_set

proc asl*(module_ref: AnalyzedModuleRef): string =
  case module_ref.kind:
  of AMRK_GENERIC: module_ref.generic.asl
  of AMRK_MODULE:
    var parent_str = module_ref.module.asl
    if module_ref.impls.len == 0:
      parent_str
    else:
      let children_str = module_ref.impls.map_it(it.module_ref.asl).join(", ")
      fmt"{parent_str}[{children_str}]"

proc byte_size*(module_ref: AnalyzedModuleRef): uint64 =
  case module_ref.name:
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64": 4
  else: 8

proc c*(module_ref: AnalyzedModuleRef): string =
  let module_name = module_ref.name
  case module_name:
  of "U8", "S8": module_name
  of "U16", "S16": module_name
  of "U32", "S32", "F32": module_name
  of "U64", "S64", "F64": module_name
  of "String", "System": module_name
  else: "Pointer"

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: ResolvedGeneric, module_ref: ResolvedModuleRef): Result[
        AnalyzedModuleRef, string] =
  case module_ref.kind:
  of AMRK_GENERIC:
    let resolved_generic = ? module.find_generic(module_ref.generic)
    if resolved_generic != generic:
      return err(fmt"{module_ref.location} expected generic `{generic.name.asl}` but found `{resolved_generic.name.asl}`")

    ok(new_analyzed_module_ref(resolved_generic, module_ref.location))
  of RMRK_MODULE:
    let resolved_module = ? file.find_module(module_ref.module)
    if resolved_module == module:
      return err(fmt"{module_ref.location} module `{resolved_module.name.asl}` can not be passed as an argument to generic constraint `{generic.name.asl}`")

    let children = ? module_ref.children
    if children.len != resolved_module.generics.len:
      return err(fmt"{module_ref.location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

    var impls: seq[AnalyzedImpl]
    for (resolved_generic, child) in zip(resolved_module.generics, children):
      let analyzed_child = ? analyze_def(file, module, generic, child)
      let analyzed_impl = ? analyze_def(resolved_generic, child, analyzed_child)
      impls.add(analyzed_impl)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    module_ref: ResolvedModuleRef): Result[AnalyzedModuleRef, string] =
  case module_ref.kind:
  of AMRK_GENERIC:
    let resolved_generic = ? module.find_generic(module_ref.generic)
    ok(new_analyzed_module_ref(resolved_generic, module_ref.location))
  of RMRK_MODULE:
    let resolved_module = ? file.find_module(module_ref.module)
    let children = ? module_ref.children
    if children.len != resolved_module.generics.len:
      return err(fmt"{module_ref.location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

    var impls: seq[AnalyzedImpl]
    for (resolved_generic, child) in zip(resolved_module.generics, children):
      let analyzed_child = ? analyze_def(file, module, child)
      let analyzed_impl = ? analyze_def(resolved_generic, child, analyzed_child)
      impls.add(analyzed_impl)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))

proc analyze_def*(file: ResolvedFile, module_ref: ResolvedModuleRef): Result[
    AnalyzedModuleRef, string] =
  case module_ref.kind:
  of AMRK_GENERIC:
    err(fmt"{module_ref.location} file level functions do not support generics")
  of RMRK_MODULE:
    let resolved_module = ? file.find_module(module_ref.module)
    let children = ? module_ref.children
    if children.len != resolved_module.generics.len:
      return err(fmt"{module_ref.location} module `{resolved_module.name.asl}` expects `{resolved_module.generics.len}` generics but found `{children.len}`")

    var impls: seq[AnalyzedImpl]
    for (resolved_generic, child) in zip(resolved_module.generics, children):
      let analyzed_child = ? analyze_def(file, child)
      let analyzed_impl = ? analyze_def(resolved_generic, child, analyzed_child)
      impls.add(analyzed_impl)
    ok(new_analyzed_module_ref(resolved_module, impls, module_ref.location))
