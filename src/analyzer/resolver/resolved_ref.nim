# ResolvedModuleRef - foundational reference type for resolved modules
import results, strformat, tables, strutils, sets, hashes

import parser
export parser

# Helper function to accumulate module dependencies from a sequence
proc accumulate_module_deps*[T](items: seq[T]): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
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
      children: seq[ResolvedModuleRef]
    of TMRK_GENERIC:
      generic: Generic

proc new_resolved_module_ref*(native_module: NativeModule,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_NATIVE, native_module: native_module,
      location: location)

proc new_resolved_module_ref*(user_module: UserModule,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_USER, user_module: user_module,
      location: location)

proc new_resolved_module_ref*(user_module: UserModule, children: seq[
    ResolvedModuleRef], location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: TMRK_USER, user_module: user_module,
      children: children, location: location)

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
    for child in module_ref.children:
      let concrete_child = child.concretize(generic, concrete_module_ref)
      concrete_children.add(concrete_child)
    new_resolved_module_ref(module_ref.user_module, concrete_children,
        module_ref.location)

proc module_deps*(module_ref: ResolvedModuleRef): HashSet[UserModule] =
  case module_ref.kind:
  of TMRK_NATIVE, TMRK_GENERIC: init_hashset[UserModule]()
  of TMRK_USER:
    var module_set: HashSet[UserModule]
    module_set.incl(module_ref.user_module)
    module_set.incl(accumulate_module_deps(module_ref.children))
    module_set

proc hash*(module_ref: ResolvedModuleRef): Hash =
  case module_ref.kind:
  of TMRK_NATIVE:
    module_ref.native_module.hash
  of TMRK_GENERIC:
    module_ref.generic.hash
  of TMRK_USER:
    var acc = module_ref.user_module.hash
    for child in module_ref.children:
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
    for child in module_ref.children:
      children.add(child.asl)
    let children_str = children.join(", ")
    if children.len == 0: module_name
    else: fmt"{module_name}[{children_str}]"

proc location*(module_ref: ResolvedModuleRef): Location = module_ref.location
proc kind*(module_ref: ResolvedModuleRef): ResolvedModuleRefKind = module_ref.kind

proc native_module*(module_ref: ResolvedModuleRef): Result[NativeModule, string] =
  case module_ref.kind:
  of TMRK_NATIVE: ok(module_ref.native_module)
  else: err(fmt"{module_ref.location} expected a native module")

proc user_module*(module_ref: ResolvedModuleRef): Result[UserModule, string] =
  case module_ref.kind:
  of TMRK_USER: ok(module_ref.user_module)
  of TMRK_GENERIC: err(fmt"{module_ref.location} expected a user module")
  else: err(fmt"{module_ref.location} expected a user module")

proc children*(module_ref: ResolvedModuleRef): Result[seq[ResolvedModuleRef], string] =
  case module_ref.kind:
  of TMRK_USER: ok(module_ref.children)
  of TMRK_NATIVE: ok(module_ref.native_children)
  else: err(fmt"{module_ref.location} expected a nested module ref")

proc generic*(module_ref: ResolvedModuleRef): Result[Generic, string] =
  case module_ref.kind:
  of TMRK_GENERIC: ok(module_ref.generic)
  else: err(fmt"{module_ref.location} expected a generic")
