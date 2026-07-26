## Phase-A `AnalyzedData` — tagged union over the three data-block
## kinds (literal / struct / union). Produced by `analyzeData` on
## the facade; consumed by `AnalyzedModuleDefinition` as the
## module's optional data field.

import strformat

import ./literaldef
import ./structdef
import ./uniondef

type
  AnalyzedDataKind* = enum
    adkLiteral, adkStruct, adkUnion
  AnalyzedData* = ref object
    case kind: AnalyzedDataKind
    of adkLiteral: literal: AnalyzedLiteralBlock
    of adkStruct: struct: AnalyzedStruct
    of adkUnion: union: AnalyzedUnion

proc newAnalyzedData*(literal: AnalyzedLiteralBlock): AnalyzedData =
  AnalyzedData(kind: adkLiteral, literal: literal)

proc newAnalyzedData*(struct: AnalyzedStruct): AnalyzedData =
  AnalyzedData(kind: adkStruct, struct: struct)

proc newAnalyzedData*(union: AnalyzedUnion): AnalyzedData =
  AnalyzedData(kind: adkUnion, union: union)

proc kind*(d: AnalyzedData): AnalyzedDataKind = d.kind
proc literal*(d: AnalyzedData): AnalyzedLiteralBlock =
  assert d.kind == adkLiteral,
    fmt"AnalyzedData.literal accessed but kind is {d.kind}"
  d.literal
proc struct*(d: AnalyzedData): AnalyzedStruct =
  assert d.kind == adkStruct,
    fmt"AnalyzedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: AnalyzedData): AnalyzedUnion =
  assert d.kind == adkUnion,
    fmt"AnalyzedData.union accessed but kind is {d.kind}"
  d.union
