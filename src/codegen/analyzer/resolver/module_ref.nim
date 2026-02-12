# ResolvedModuleRef - foundational reference type for resolved modules
import results, strformat, strutils, sets, hashes, options

import parser


# =============================================================================
# ResolvedModuleRef
# =============================================================================

type
  ResolvedModuleRefKind* = enum
    RMRK_MODULE, AMRK_GENERIC
  ResolvedModuleRef* = ref object of RootObj
    location: Location
    case kind: ResolvedModuleRefKind
    of RMRK_MODULE:
      module: Module
      children: seq[ResolvedModuleRef]
    of AMRK_GENERIC:
      generic: Generic

proc new_resolved_module_ref*(module: Module, children: seq[
    ResolvedModuleRef], location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: RMRK_MODULE, module: module,
      children: children, location: location)

proc new_resolved_module_ref*(generic: Generic,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: AMRK_GENERIC, generic: generic,
      location: location)

proc concretize*(module_ref: ResolvedModuleRef, generic: Generic,
    concrete_module_ref: ResolvedModuleRef): ResolvedModuleRef =
  case module_ref.kind:
  of AMRK_GENERIC:
    if module_ref.generic == generic: concrete_module_ref
    else: module_ref
  of RMRK_MODULE:
    var concrete_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let concrete_child = child.concretize(generic, concrete_module_ref)
      concrete_children.add(concrete_child)
    new_resolved_module_ref(module_ref.module, concrete_children,
        module_ref.location)

proc module_deps*(module_ref: ResolvedModuleRef): HashSet[Module] =
  case module_ref.kind:
  of AMRK_GENERIC: init_hashset[Module]()
  of RMRK_MODULE:
    var module_set: HashSet[Module]
    module_set.incl(module_ref.module)
    for child in module_ref.children:
      module_set.incl(child.module_deps)
    module_set

proc hash*(module_ref: ResolvedModuleRef): Hash =
  case module_ref.kind:
  of AMRK_GENERIC:
    module_ref.generic.hash
  of RMRK_MODULE:
    var acc = module_ref.module.hash
    for child in module_ref.children:
      acc = acc !& child.hash
    acc

proc self*(module_ref: ResolvedModuleRef): ResolvedModuleRef =
  case module_ref.kind:
  of AMRK_GENERIC: module_ref
  of RMRK_MODULE:
    var child_module_refs: seq[ResolvedModuleRef]
    for generic in module_ref.module.generics:
      let child_module_ref = new_resolved_module_ref(generic,
          module_ref.location)
      child_module_refs.add(child_module_ref)
    new_resolved_module_ref(module_ref.module, child_module_refs,
        module_ref.location)

proc asl*(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of AMRK_GENERIC: module_ref.generic.name.asl
  of RMRK_MODULE:
    let module_name = module_ref.module.name.asl
    var children: seq[string]
    for child in module_ref.children:
      children.add(child.asl)
    let children_str = children.join(", ")
    if children.len == 0: module_name
    else: fmt"{module_name}[{children_str}]"

proc location*(module_ref: ResolvedModuleRef): Location = module_ref.location
proc kind*(module_ref: ResolvedModuleRef): ResolvedModuleRefKind = module_ref.kind

proc module*(module_ref: ResolvedModuleRef): Module =
  do_assert module_ref.kind == RMRK_MODULE, "expected a module"
  module_ref.module

proc generic*(module_ref: ResolvedModuleRef): Generic =
  do_assert module_ref.kind == AMRK_GENERIC, "expected a generic"
  module_ref.generic

proc children*(module_ref: ResolvedModuleRef): Result[seq[ResolvedModuleRef], string] =
  case module_ref.kind:
  of RMRK_MODULE: ok(module_ref.children)
  else: err(fmt"{module_ref.location} expected a nested module ref")

proc resolve(file: parser.File, module_name: Identifier, children: seq[
    ResolvedModuleRef], location: Location): Result[ResolvedModuleRef, string] =
  let arg_module = ? file.find_module(module_name)
  ok(new_resolved_module_ref(arg_module, children, location))

proc resolve*(file: parser.File, module: Option[parser.Module],
    module_ref: ModuleRef): Result[ResolvedModuleRef, string] =
  let module_name = module_ref.module
  var resolved_children: seq[ResolvedModuleRef]

  case module_ref.kind:
  of MRK_SIMPLE:
    if module.is_some:
      let maybe_generic = module.get.find_generic(module_name)
      if maybe_generic.is_ok:
        let generic = maybe_generic.get
        return ok(new_resolved_module_ref(generic, module_name.location))
  of MRK_NESTED:
    if module.is_some:
      for child in module_ref.children:
        let resolved_child = ? resolve(file, module, child)
        resolved_children.add(resolved_child)
    else:
      for child in module_ref.children:
        let resolved_child = ? resolve(file, module, child)
        resolved_children.add(resolved_child)

  file.resolve(module_name, resolved_children, module_name.location)

