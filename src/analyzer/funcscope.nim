## Body-level scopes and the helpers the body walker consumes:
##   - AnalyzedFunctionScope    (variable -> AnalyzedArgumentType)
## plus `findModuleDef`, `extractDataDef`, `extractStructFor`,
## `extractUnionFor`, `clone`.
##
## Defined-type lookup by Identifier lives directly on
## `ResolvedFileScope` (see argtypes.nim) — post-6c retirement there is
## no separate `AnalyzedTypeScope`, since every defined type
## carried by the scope is already a `ResolvedType`.

import tables

import ./resolver
import argtype

type AnalyzedFunctionScope* = Table[Identifier, AnalyzedArgumentType]

proc clone*(scope: AnalyzedFunctionScope): AnalyzedFunctionScope =
  var updated: AnalyzedFunctionScope
  for key, value in scope: updated[key] = value
  return updated
