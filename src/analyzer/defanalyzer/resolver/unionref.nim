## ResolvedUnionRef — a parser UnionRef resolved into the receiver's
## ResolvedModuleArgumentType (impls arity- and constraint-validated)
## plus the referenced VariantDef. Wrong-kind receivers and unknown
## variants are rejected at ref-resolve time, so downstream consumers
## hold a provably valid union reference. The parser-level UnionDef
## is deliberately NOT stored — the def analyzer needs the RESOLVED
## union, which it re-derives from the module (the cycle constraint
## forbids storing resolved defs of possibly-mid-resolution modules).
## Leaf node in the body cluster; reused by ResolvedUnionInitializer.

import ./parser
import argtype

type ResolvedUnionRef* = ref object
  parsed: UnionRef
  argType: ResolvedModuleArgumentType
  variant: VariantDef

proc newResolvedUnionRef*(parsed: UnionRef, argType: ResolvedModuleArgumentType, variant: VariantDef): ResolvedUnionRef =
  ResolvedUnionRef(parsed: parsed, argType: argType, variant: variant)

proc newResolvedUnionRef*(parsed: UnionRef, module: Module, variant: VariantDef): ResolvedUnionRef =
  let moduleArgType = newResolvedModuleArgumentType(module, parsed.loc)
  newResolvedUnionRef(parsed, moduleArgType, variant)

proc module*(u: ResolvedUnionRef): Module = u.argType.module
proc argType*(u: ResolvedUnionRef): ResolvedModuleArgumentType = u.argType
proc variant*(u: ResolvedUnionRef): VariantDef = u.variant