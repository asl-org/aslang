## Phase-A `AnalyzedArgumentDefinition` — a name + fully-analyzed
## argument type. Produced by phase-A `analyzeArgumentDefinition` when
## walking a function's signature, then consumed by phase-B body
## walkers for kwarg / arg validation without re-analyzing the
## underlying argument type.
##
## `concrete*` overloads substitute generic slots in the analyzed
## argument type, preserving the identifier. See argtype.nim's own
## `concrete*` for the substitution semantics.

import tables

import ./resolver
import ./argtype
import ./genericimplmap

type AnalyzedArgumentDefinition* = ref object
  argType: AnalyzedArgumentType
  name: Identifier

proc newAnalyzedArgumentDefinition*(argType: AnalyzedArgumentType, name: Identifier): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(argType: argType, name: name)

proc argType*(d: AnalyzedArgumentDefinition): AnalyzedArgumentType = d.argType
proc name*(d: AnalyzedArgumentDefinition): Identifier = d.name
proc loc*(d: AnalyzedArgumentDefinition): Location = d.name.loc

proc asl*(d: AnalyzedArgumentDefinition): string =
  d.name.asl & ": " & d.argType.asl

proc concrete*(d: AnalyzedArgumentDefinition, implMap: GenericImplMap): AnalyzedArgumentDefinition =
  ## Substitute generic slots via the implMap, preserving `name`.
  newAnalyzedArgumentDefinition(d.argType.concrete(implMap), d.name)

proc concrete*(d: AnalyzedArgumentDefinition,
    impls: seq[AnalyzedArgumentType],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): AnalyzedArgumentDefinition =
  ## Positional generic substitution via the (impls, genericTypeIndex)
  ## pair. Preserves `name`. See argtype.nim:concrete for semantics.
  newAnalyzedArgumentDefinition(
    d.argType.concrete(impls, genericTypeIndex), d.name)
