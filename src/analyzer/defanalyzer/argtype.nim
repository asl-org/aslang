## Analyzed argument-type cluster — `AnalyzedModuleArgumentType` and
## the outer `AnalyzedArgumentType` tagged union share this file
## because Nim requires mutually-referencing `ref object` types in one
## `type` block (`impls: seq[AnalyzedArgumentType]` on the module
## variant references the outer union). The generic variant has no
## back-reference and lives in ./genericargtype. The analyzeDef*
## procs (both context overloads) live on the defanalyzer barrel.
##
## The resolver already validated arity + generic-constraint
## satisfaction — each ResolvedModuleArgumentType's `impls` seq is a
## provably valid value by the time the analyzer sees it.

import strformat, strutils, tables, hashes

import ./resolver
import ./genericargtype

# Mutually-recursive cluster: AnalyzedModuleArgumentType's impls
# field references AnalyzedArgumentType, which case-dispatches back
# into AnalyzedModuleArgumentType. One `type:` block. Flat
# two-variant tagged union mirrors the resolver-side flatten —
# imported types resolve through fileCtx and surface as ordinary
# `aatkModule`/`aatkGeneric` values just like local types.
type
  # AnalyzedImplMap lives here, in the same type block as the argument
  # types it relates, because it IS a concrete parameterized type's
  # impls: each of the module's require slots (a ResolvedGeneric) bound
  # to the impl sitting in that position, kept in slot order. Every
  # AnalyzedModuleArgumentType's `impls` IS this map — `Status[u8]` is
  # {Any: u8} — so the positional impls are its values (in order) and a
  # consumer (a match subject, say) reads the generic bindings straight
  # off the type instead of re-deriving them from a file context. The
  # `merge` / `concrete` operations live in the sibling
  # analyzedimplmap.nim. Keyed by ResolvedGeneric, so a type's require
  # slots must be distinct generics — the same invariant the resolver's
  # genericTypeIndex already relies on.
  AnalyzedImplMap* = OrderedTable[ResolvedGeneric, AnalyzedArgumentType]

  AnalyzedModuleArgumentType* = ref object
    resolved: ResolvedModuleArgumentType
    module: ResolvedModule
    impls: AnalyzedImplMap

  AnalyzedArgumentTypeKind* = enum
    aatkModule, aatkGeneric

  AnalyzedArgumentType* = ref object
    case kind: AnalyzedArgumentTypeKind
    of aatkModule: module: AnalyzedModuleArgumentType
    of aatkGeneric: generic: AnalyzedGenericArgumentType

# Forward declarations for the dual-context overloads — both arities
# of analyzeArgumentType need to be visible inside
# analyzeModuleArgumentType.
proc hash*(m: AnalyzedArgumentType): Hash
proc asl*(argType: AnalyzedArgumentType): string

# Constructors + accessors + self for the cluster.
proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule, impls: AnalyzedImplMap): AnalyzedModuleArgumentType =
  AnalyzedModuleArgumentType(resolved: resolved, module: module, impls: impls)

proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(resolved, module, default(AnalyzedImplMap))

proc newAnalyzedModuleArgumentType*(module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(module.self, module)

proc resolved*(m: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = m.resolved
  ## Exposed so the sibling analyzedimplmap.nim can rebuild a
  ## ModuleArgumentType during generic substitution. Previously the
  ## `concrete` overload lived in the same file as the type
  ## declaration and read the private field directly; the per-type
  ## split moved it out.
proc loc*(m: AnalyzedModuleArgumentType): Location = m.resolved.loc
proc module*(m: AnalyzedModuleArgumentType): ResolvedModule = m.module
proc impls*(m: AnalyzedModuleArgumentType): AnalyzedImplMap = m.impls
proc name*(m: AnalyzedModuleArgumentType): Identifier = m.module.name
proc self*(argType: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = argType.module.self
proc hash*(m: AnalyzedModuleArgumentType): Hash =
  # The impl values in slot order, on top of the module. The keys (the
  # module's require slots) are fixed by the module, already folded in
  # via module.hash — so hashing the ordered values suffices, and the
  # OrderedTable's stable iteration keeps it deterministic.
  var acc = m.module.hash
  for impl in m.impls.values:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: AnalyzedModuleArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.module.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls.values:
      impls.add(impl.asl)
    let implChildren = impls.join(", ")
    fmt"{argType.module.name.asl}[{implChildren}]"

proc newAnalyzedArgumentType*(module: AnalyzedModuleArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkModule, module: module)

proc newAnalyzedArgumentType*(generic: AnalyzedGenericArgumentType): AnalyzedArgumentType =
  AnalyzedArgumentType(kind: aatkGeneric, generic: generic)

proc newAnalyzedArgumentType*(module: ResolvedModule): AnalyzedArgumentType =
  let moduleArgType = newAnalyzedModuleArgumentType(module)
  newAnalyzedArgumentType(moduleArgType)

proc kind*(a: AnalyzedArgumentType): AnalyzedArgumentTypeKind = a.kind

proc module*(a: AnalyzedArgumentType): AnalyzedModuleArgumentType =
  assert a.kind == aatkModule,
    fmt"AnalyzedArgumentType.module accessed but kind is {a.kind}"
  a.module

proc generic*(a: AnalyzedArgumentType): AnalyzedGenericArgumentType =
  assert a.kind == aatkGeneric,
    fmt"AnalyzedArgumentType.generic accessed but kind is {a.kind}"
  a.generic

proc name*(argType: AnalyzedArgumentType): Identifier =
  case argType.kind:
  of aatkModule: argType.module.name
  of aatkGeneric: argType.generic.name

proc impls*(argType: AnalyzedArgumentType): AnalyzedImplMap =
  # A bare generic names no slots — its impls map is empty.
  case argType.kind:
  of aatkModule: argType.module.impls
  of aatkGeneric: default(AnalyzedImplMap)

proc loc*(argType: AnalyzedArgumentType): Location =
  case argType.kind:
  of aatkModule: argType.module.loc
  of aatkGeneric: argType.generic.loc

proc self*(argType: AnalyzedArgumentType): ResolvedArgumentType =
  case argType.kind:
  of aatkModule: newResolvedArgumentType(argType.module.self)
  of aatkGeneric: newResolvedArgumentType(argType.generic.self)

proc asl*(argType: AnalyzedArgumentType): string =
  case argType.kind:
  of aatkModule: argType.module.asl
  of aatkGeneric: argType.generic.asl

proc hash*(m: AnalyzedArgumentType): Hash =
  case m.kind:
  of aatkModule: m.module.hash
  of aatkGeneric: m.generic.hash

proc `==`*(a, b: AnalyzedArgumentType): bool = a.hash == b.hash

# TODO(union-inference): `==` is only correct when both sides are
# ground. Under leave-as-is, a value's type can carry free generics in
# impl positions (e.g. Box[u8, Sample]). Assignability against an
# expected type (Box[u8, MyImpl]) is unification, not equality. Audit
# every callsite of AnalyzedArgumentType `==` used for assignability
# (value-type vs expected-type matches in arg checks, return checks,
# kwarg checks) and route through analyzeValueTypeAgainstDefType
# / AnalyzedImplMap merge instead. Pure type-identity uses
# (deduplication, table keying) stay as-is.

