## ResolvedStructRef — a parser StructRef with its (arity- and
## constraint-validated) impl list. Leaf node in the body cluster.
## Reused by ResolvedStructInitializer.

import ./parser
import argtype

type ResolvedStructRef* = ref object
  parsed: StructRef
  module: Module
  impls: seq[ResolvedArgumentType]

proc newResolvedStructRef*(parsed: StructRef, module: Module,
    impls: seq[ResolvedArgumentType]): ResolvedStructRef =
  ## One-shape constructor. `impls` is empty when the surface
  ## form was `Module { ... }` and non-empty (arity + constraint checked)
  ## when the surface form was `Module[Impl, ...] { ... }`.
  ResolvedStructRef(parsed: parsed, module: module, impls: impls)

proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc module*(s: ResolvedStructRef): Module = s.module
proc impls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.impls
proc loc*(s: ResolvedStructRef): Location = s.parsed.loc
