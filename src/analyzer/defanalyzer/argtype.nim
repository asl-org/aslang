## Analyzed argument-type cluster — the whole family in one file:
## AnalyzedGenericArgumentType, AnalyzedModuleArgumentType, and the
## outer AnalyzedArgumentType tagged union (they share a `type` block
## since the module variant's impl map references the union), plus the
## AnalyzedImplMap type and its merge/concrete operations and
## AnalyzedArgumentDef. The analyzeDef* procs live on the defanalyzer
## barrel.
##
## The resolver already validated arity + generic-constraint
## satisfaction — each ResolvedModuleArgumentType's `impls` seq is a
## provably valid value by the time the analyzer sees it.

import results, strformat, strutils, tables, hashes

import ./resolver

# Mutually-recursive cluster: AnalyzedModuleArgumentType's impls
# field references AnalyzedArgumentType, which case-dispatches back
# into AnalyzedModuleArgumentType. One `type:` block. Flat
# two-variant tagged union mirrors the resolver-side flatten —
# imported types resolve through fileCtx and surface as ordinary
# `aatkModule`/`aatkGeneric` values just like local types.
type
  # AnalyzedGenericArgumentType — a ResolvedGeneric + the use-site loc.
  # No back-reference into the union, but kept in the same type block
  # for cohesion.
  AnalyzedGenericArgumentType* = ref object
    resolved: ResolvedGeneric
    loc: Location

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

# ---- AnalyzedGenericArgumentType accessors ----
proc newAnalyzedGenericArgumentType*(resolved: ResolvedGeneric, loc: Location): AnalyzedGenericArgumentType =
  AnalyzedGenericArgumentType(resolved: resolved, loc: loc)

proc generic*(g: AnalyzedGenericArgumentType): ResolvedGeneric = g.resolved
proc loc*(g: AnalyzedGenericArgumentType): Location = g.loc
proc name*(g: AnalyzedGenericArgumentType): Identifier = g.resolved.name
proc hash*(g: AnalyzedGenericArgumentType): Hash = g.resolved.hash
proc `==`*(a, b: AnalyzedGenericArgumentType): bool = a.hash == b.hash
proc self*(argType: AnalyzedGenericArgumentType): ResolvedGenericArgumentType =
  newResolvedGenericArgumentType(argType.resolved.parsed, newLocation())
proc asl*(argType: AnalyzedGenericArgumentType): string =
  argType.resolved.name.asl

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


# ============================================================
# AnalyzedImplMap operations (merge / concrete)
# ============================================================

proc merge*(global: var AnalyzedImplMap, local: AnalyzedImplMap): Result[AnalyzedImplMap, string] =
  # TODO(union-inference): eagerly collapse substitution chains.
  # When inserting `K → u8`, also rewrite any existing values in the
  # map that mention K as a free generic (e.g. an earlier
  # `Sample → K` becomes `Sample → u8`). This keeps `concrete()` a
  # single-pass lookup and prevents free generics from getting stuck
  # half-resolved when one use site binds another generic that they
  # depend on. Also: the `!=` conflict check on the next line needs
  # to become a unification check once free generics can appear on
  # either side (a bound u8 vs a free K should not "conflict" — K
  # should unify to u8).
  for generic, impl in local:
    if generic in global and global[generic] != impl:
      return err(fmt"{impl.loc} generic `{generic.name.asl}` already bound to `{global[generic].asl}` (at {global[generic].loc}) but here resolves to `{impl.asl}` — one generic binds to one concrete type per construction; declare a second generic if you need independent types")
    else:
      global[generic] = impl
  ok(global)

proc concrete*(argType: AnalyzedArgumentType, implMap: AnalyzedImplMap): AnalyzedArgumentType =
  # TODO(union-inference): handle substitution chains. A single use
  # site can produce an implMap with both `Sample → K` and `K → u8`
  # (e.g. `func f(a: Box[u8, K], b: K)` called as
  # `f(boxFirst, u8 5)`). Today getOrDefault returns the immediate
  # map value, so `Sample` rewrites to `K`, not `u8`. Prefer eager
  # chain-collapsing in `merge` (cheaper, single pass) — see the TODO
  # there — over recursive lookup here.
  case argType.kind:
  of aatkModule:
    let moduleArgType = argType.module
    # Rebuild the ordered slot→impl map, concretizing each impl and
    # keeping the same slot keys and order.
    var concreteImpls: AnalyzedImplMap
    for generic, impl in moduleArgType.impls:
      concreteImpls[generic] = impl.concrete(implMap)
    let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
    return newAnalyzedArgumentType(concreteModuleArgType)
  of aatkGeneric:
    let genericArgType = argType.generic
    return implMap.getOrDefault(genericArgType.generic, argType)

# ============================================================
# AnalyzedArgumentDef (name + fully-analyzed argument type)
# ============================================================

type AnalyzedArgumentDef* = ref object
  resolved: ResolvedArgumentDef
  argType: AnalyzedArgumentType

proc newAnalyzedArgumentDef*(resolved: ResolvedArgumentDef, argType: AnalyzedArgumentType): AnalyzedArgumentDef =
  AnalyzedArgumentDef(resolved: resolved, argType: argType)

proc argType*(d: AnalyzedArgumentDef): AnalyzedArgumentType = d.argType
proc name*(d: AnalyzedArgumentDef): Identifier = d.resolved.name
proc loc*(d: AnalyzedArgumentDef): Location = d.resolved.name.loc

proc asl*(d: AnalyzedArgumentDef): string =
  d.name.asl & ": " & d.argType.asl
