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
  AnalyzedModuleArgumentType* = ref object
    resolved: ResolvedModuleArgumentType
    module: ResolvedModule
    impls: seq[AnalyzedArgumentType]

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
proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule, impls: seq[AnalyzedArgumentType]): AnalyzedModuleArgumentType =
  AnalyzedModuleArgumentType(resolved: resolved, module: module, impls: impls)

proc newAnalyzedModuleArgumentType*(resolved: ResolvedModuleArgumentType, module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(resolved, module, @[])

proc newAnalyzedModuleArgumentType*(module: ResolvedModule): AnalyzedModuleArgumentType =
  newAnalyzedModuleArgumentType(module.self, module)

proc resolved*(m: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = m.resolved
  ## Exposed so the sibling genericimplmap.nim can rebuild a
  ## ModuleArgumentType during generic substitution. Previously the
  ## `concrete` overload lived in the same file as the type
  ## declaration and read the private field directly; the per-type
  ## split moved it out.
proc loc*(m: AnalyzedModuleArgumentType): Location = m.resolved.loc
proc module*(m: AnalyzedModuleArgumentType): ResolvedModule = m.module
proc impls*(m: AnalyzedModuleArgumentType): seq[AnalyzedArgumentType] = m.impls
proc name*(m: AnalyzedModuleArgumentType): Identifier = m.module.name
proc self*(argType: AnalyzedModuleArgumentType): ResolvedModuleArgumentType = argType.module.self
proc hash*(m: AnalyzedModuleArgumentType): Hash =
  var acc = m.module.hash
  for impl in m.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: AnalyzedModuleArgumentType): bool = a.hash == b.hash
proc asl*(argType: AnalyzedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.module.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
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
# / GenericImplMap merge instead. Pure type-identity uses
# (deduplication, table keying) stay as-is.

proc concrete*(argType: AnalyzedArgumentType, impls: seq[AnalyzedArgumentType], genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedArgumentType =
  ## Positional generic substitution. The `genericTypeIndex` maps each
  ## generic that a union's variant field types touch to its position
  ## in the impl list — this is a resolver-side table
  ## (`ResolvedUnionDef.genericTypeIndex`), so the analyzer-side generic
  ## argType is translated back through its underlying parser Generic
  ## to hit the same table entry (both types hash by parser Generic
  ## identity). Structs don't route through this proc — their impl
  ## substitution goes through `ResolvedStructDef.requires`, which
  ## already merges the explicit-header and inferred-from-fields cases.
  case argType.kind:
  of aatkModule:
    let moduleArgType = argType.module
    var concreteImpls: seq[AnalyzedArgumentType]
    for impl in moduleArgType.impls:
      let concreteImpl = impl.concrete(impls, genericTypeIndex)
      concreteImpls.add(concreteImpl)
    let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
    newAnalyzedArgumentType(concreteModuleArgType)
  of aatkGeneric:
    let key = newResolvedGenericArgumentType(argType.generic.generic.self, argType.generic.loc)
    if key in genericTypeIndex:
      impls[genericTypeIndex[key]]
    else:
      argType
