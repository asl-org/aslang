# ResolvedModuleRef - foundational reference type for resolved modules
import results, strformat, tables, strutils, sets, hashes, options

import parser
export parser

# Helper function to accumulate module dependencies from a sequence
proc accumulate_module_deps*[T](items: seq[T]): HashSet[Module] =
  var module_set: HashSet[Module]
  for item in items:
    module_set.incl(item.module_deps)
  module_set

# =============================================================================
# ResolvedModuleRef
# =============================================================================

type
  ResolvedModuleRefKind* = enum
    TMRK_NATIVE, TMRK_USER, TMRK_GENERIC
  ResolvedModuleRef* = ref object of RootObj
    location: Location
    case kind: ResolvedModuleRefKind
    of TMRK_NATIVE:
      native_module: NativeModule
      native_children: seq[ResolvedModuleRef]
    of TMRK_USER:
      user_module: UserModule
      user_children: seq[ResolvedModuleRef]
    of TMRK_GENERIC:
      generic: Generic

proc new_resolved_module_ref*(user_module: UserModule, children: seq[
    ResolvedModuleRef], location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_USER, user_module: user_module,
      user_children: children, location: location)

proc new_resolved_module_ref*(native_module: NativeModule, children: seq[
    ResolvedModuleRef], location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_NATIVE, native_module: native_module,
      native_children: children, location: location)

proc new_resolved_module_ref*(generic: Generic,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_GENERIC, generic: generic,
      location: location)

proc concretize*(module_ref: ResolvedModuleRef, generic: Generic,
    concrete_module_ref: ResolvedModuleRef): ResolvedModuleRef =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref
  of TMRK_GENERIC:
    if module_ref.generic == generic: concrete_module_ref
    else: module_ref
  of TMRK_USER:
    var concrete_children: seq[ResolvedModuleRef]
    for child in module_ref.user_children:
      let concrete_child = child.concretize(generic, concrete_module_ref)
      concrete_children.add(concrete_child)
    new_resolved_module_ref(module_ref.user_module, concrete_children,
        module_ref.location)

proc module_deps*(module_ref: ResolvedModuleRef): HashSet[Module] =
  case module_ref.kind:
  of TMRK_NATIVE, TMRK_GENERIC: init_hashset[Module]()
  of TMRK_USER:
    var module_set: HashSet[Module]
    module_set.incl(new_module(module_ref.user_module))
    module_set.incl(accumulate_module_deps(module_ref.user_children))
    module_set

proc hash*(module_ref: ResolvedModuleRef): Hash =
  case module_ref.kind:
  of TMRK_NATIVE:
    module_ref.native_module.hash
  of TMRK_GENERIC:
    module_ref.generic.hash
  of TMRK_USER:
    var acc = module_ref.user_module.hash
    for child in module_ref.user_children:
      acc = acc !& child.hash
    acc

proc self*(module_ref: ResolvedModuleRef): ResolvedModuleRef =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref
  of TMRK_GENERIC: module_ref
  of TMRK_USER:
    var child_module_refs: seq[ResolvedModuleRef]
    for generic in module_ref.user_module.generics:
      let child_module_ref = new_resolved_module_ref(generic,
          module_ref.location)
      child_module_refs.add(child_module_ref)
    new_resolved_module_ref(module_ref.user_module, child_module_refs,
        module_ref.location)

proc asl*(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref.native_module.name.asl
  of TMRK_GENERIC: module_ref.generic.name.asl
  of TMRK_USER:
    let module_name = module_ref.user_module.name.asl
    var children: seq[string]
    for child in module_ref.user_children:
      children.add(child.asl)
    let children_str = children.join(", ")
    if children.len == 0: module_name
    else: fmt"{module_name}[{children_str}]"

proc location*(module_ref: ResolvedModuleRef): Location = module_ref.location
proc kind*(module_ref: ResolvedModuleRef): ResolvedModuleRefKind = module_ref.kind

proc native_module*(module_ref: ResolvedModuleRef): NativeModule =
  doAssert module_ref.kind == TMRK_NATIVE, "expected a native module"
  module_ref.native_module

proc user_module*(module_ref: ResolvedModuleRef): UserModule =
  doAssert module_ref.kind == TMRK_USER, "expected a user module"
  module_ref.user_module

proc generic*(module_ref: ResolvedModuleRef): Generic =
  doAssert module_ref.kind == TMRK_GENERIC, "expected a generic"
  module_ref.generic

proc children*(module_ref: ResolvedModuleRef): Result[seq[ResolvedModuleRef], string] =
  case module_ref.kind:
  of TMRK_USER: ok(module_ref.user_children)
  of TMRK_NATIVE: ok(module_ref.native_children)
  else: err(fmt"{module_ref.location} expected a nested module ref")

proc resolve(file: parser.File, module_name: Identifier, children: seq[
    ResolvedModuleRef], location: Location): Result[ResolvedModuleRef, string] =
  let arg_module = ? file.find_module(module_name)
  case arg_module.kind:
  of MK_NATIVE:
    ok(new_resolved_module_ref(arg_module.native_module, children, location))
  of MK_USER:
    ok(new_resolved_module_ref(arg_module.user_module, children, location))

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

