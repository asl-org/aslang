## ResolvedStructRef — a parser StructRef resolved into the receiver's
## ResolvedModuleArgumentType (impls arity- and constraint-validated)
## plus its StructDef. Wrong-kind receivers are rejected at
## ref-resolve time, so downstream consumers hold a provably valid
## struct reference. Leaf node in the body cluster; reused by
## ResolvedStructInitializer.

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

proc loc*(s: ResolvedStructRef): Location = s.parsed.loc
proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc module*(s: ResolvedStructRef): Module = s.argType.module
proc impls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.argType.impls
proc struct*(s: ResolvedStructRef): StructDef = s.struct
proc argType*(s: ResolvedStructRef): ResolvedModuleArgumentType = s.argType
