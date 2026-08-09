## Resolved ref wrappers — `ResolvedStructRef` / `ResolvedUnionRef`
## resolve a parser StructRef / UnionRef into the receiver's
## ResolvedModuleArgumentType (impls arity- and constraint-validated)
## plus the StructDef / referenced VariantDef. Wrong-kind receivers and
## unknown variants are rejected at ref-resolve time, so downstream
## consumers hold provably valid references. The parser-level UnionDef is
## deliberately NOT stored — the def analyzer re-derives the RESOLVED
## union from the module (the cycle constraint forbids storing resolved
## defs of possibly-mid-resolution modules). Leaf nodes in the body
## cluster; reused by the struct/union initializers.

import results, strformat

import ./parser
import argtype

type ResolvedStructRef* = ref object
  parsed: StructRef
  argType: ResolvedModuleArgumentType
  struct: StructDef

proc newResolvedStructRef*(parsed: StructRef, argType: ResolvedModuleArgumentType, struct: StructDef): ResolvedStructRef =
  ResolvedStructRef(parsed: parsed, argType: argType, struct: struct)

proc newResolvedStructRef*(parsed: StructRef, module: Module, struct: StructDef): Result[ResolvedStructRef, string] =
  ## Bare (impl-less) ref front-door: only legal when the struct has
  ## no explicit header params — explicit-header structs (Array/Map)
  ## carry phantom params that cannot be inferred from kwargs, so a
  ## bare ref to one is rejected here. Inferred-generic structs
  ## accept bare refs (leave-as-is inference fills the positions).
  if struct.header.requires.len > 0:
    return err(fmt"{parsed.loc} module `{parsed.module.asl}` expects {struct.header.requires.len} impls")
  let syntheticArgType = newResolvedModuleArgumentType(module, parsed.loc)
  ok(newResolvedStructRef(parsed, syntheticArgType, struct))

proc module*(s: ResolvedStructRef): Module = s.argType.module
proc struct*(s: ResolvedStructRef): StructDef = s.struct
proc argType*(s: ResolvedStructRef): ResolvedModuleArgumentType = s.argType

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
