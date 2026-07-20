## ResolvedUnionRef — a parser UnionRef with its (arity- and
## constraint-validated) impl list. Leaf node in the body cluster.
## Reused by ResolvedUnionInitializer.

import ./parser
import argtype

type ResolvedUnionRef* = ref object
  parsed: UnionRef
  module: Module
  impls: seq[ResolvedArgumentType]

proc newResolvedUnionRef*(parsed: UnionRef, module: Module,
    impls: seq[ResolvedArgumentType]): ResolvedUnionRef =
  ## One-shape constructor. `impls` is empty when the surface
  ## form was `Module.Variant { ... }` and non-empty (arity + constraint
  ## checked) when the surface form was `Module[Impl, ...].Variant { ... }`.
  ResolvedUnionRef(parsed: parsed, module: module, impls: impls)

proc parsed*(u: ResolvedUnionRef): UnionRef = u.parsed
proc module*(u: ResolvedUnionRef): Module = u.module
proc impls*(u: ResolvedUnionRef): seq[ResolvedArgumentType] = u.impls
proc loc*(u: ResolvedUnionRef): Location = u.parsed.loc
