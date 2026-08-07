## Phase-A `AnalyzedArgumentDef` — a name + fully-analyzed
## argument type. Produced by phase-A `analyzeArgumentDefinition` when
## walking a function's signature, then consumed by phase-B body
## walkers for kwarg / arg validation without re-analyzing the
## underlying argument type.
##
## `concrete*` substitutes generic slots in the analyzed argument
## type positionally (via impls + genericTypeIndex), preserving the
## identifier. See argtype.nim's own `concrete*` for the semantics.

import tables

import ./resolver
import ./argtype

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

proc concrete*(d: AnalyzedArgumentDef,
    impls: seq[AnalyzedArgumentType],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedArgumentDef =
  ## Positional generic substitution via the (impls, genericTypeIndex)
  ## pair. Preserves `resolved`. See argtype.nim:concrete for semantics.
  newAnalyzedArgumentDef(
    d.resolved, d.argType.concrete(impls, genericTypeIndex))
