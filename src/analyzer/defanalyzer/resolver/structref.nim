## ResolvedStructRef — a parser StructRef resolved into the receiver's
## ResolvedModuleArgumentType (impls arity- and constraint-validated)
## plus its StructDef. Wrong-kind receivers are rejected at
## ref-resolve time, so downstream consumers hold a provably valid
## struct reference. Leaf node in the body cluster; reused by
## ResolvedStructInitializer.

import ./parser
import argtype

type ResolvedStructRef* = ref object
  parsed: StructRef
  argType: ResolvedModuleArgumentType
  struct: StructDef

proc newResolvedStructRef*(parsed: StructRef, argType: ResolvedModuleArgumentType, struct: StructDef): ResolvedStructRef =
  ResolvedStructRef(parsed: parsed, argType: argType, struct: struct)

proc newResolvedStructRef*(parsed: StructRef, module: Module, struct: StructDef): ResolvedStructRef =
  let syntheticArgType = newResolvedModuleArgumentType(module, parsed.loc)
  newResolvedStructRef(parsed, syntheticArgType, struct)

proc loc*(s: ResolvedStructRef): Location = s.parsed.loc
proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc module*(s: ResolvedStructRef): Module = s.argType.module
proc impls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.argType.impls
proc struct*(s: ResolvedStructRef): StructDef = s.struct
