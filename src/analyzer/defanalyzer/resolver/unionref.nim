## ResolvedUnionRef — a parser UnionRef with its (arity- and
## constraint-validated) impl list. Leaf node in the body cluster.
## Reused by ResolvedUnionInitializer.

import ./parser
import argtype

type ResolvedUnionRef* = ref object
  parsed: UnionRef
  argType: ResolvedModuleArgumentType
  union: UnionDef
  variant: VariantDef

proc newResolvedUnionRef*(parsed: UnionRef, argType: ResolvedModuleArgumentType, union: UnionDef, variant: VariantDef): ResolvedUnionRef =
  ResolvedUnionRef(parsed: parsed, argType: argType, union: union, variant: variant)

proc newResolvedUnionRef*(parsed: UnionRef, module: Module, union: UnionDef, variant: VariantDef): ResolvedUnionRef =
  let moduleArgType = newResolvedModuleArgumentType(module, parsed.loc)
  newResolvedUnionRef(parsed, moduleArgType, union, variant)

proc loc*(u: ResolvedUnionRef): Location = u.parsed.loc
proc parsed*(u: ResolvedUnionRef): UnionRef = u.parsed
proc module*(u: ResolvedUnionRef): Module = u.argType.module
proc impls*(u: ResolvedUnionRef): seq[ResolvedArgumentType] = u.argType.impls
proc argType*(u: ResolvedUnionRef): ResolvedModuleArgumentType = u.argType
proc union*(u: ResolvedUnionRef): UnionDef = u.union
proc variant*(u: ResolvedUnionRef): VariantDef = u.variant