## Phase-A `AnalyzedDataDef` — tagged union over the three data-block
## kinds (literal / struct / union). Produced by `analyzeData` on
## the facade; consumed by `AnalyzedDefModule` as the
## module's optional data field.

import strformat

import ./literaldef
import ./structdef
import ./uniondef

type
  AnalyzedDataKind* = enum
    adkLiteral, adkStruct, adkUnion
  AnalyzedDataDef* = ref object
    case kind: AnalyzedDataKind
    of adkLiteral: literal: AnalyzedLiteralDef
    of adkStruct: struct: AnalyzedStructDef
    of adkUnion: union: AnalyzedUnionDef

proc newAnalyzedDataDef*(literal: AnalyzedLiteralDef): AnalyzedDataDef =
  AnalyzedDataDef(kind: adkLiteral, literal: literal)

proc newAnalyzedDataDef*(struct: AnalyzedStructDef): AnalyzedDataDef =
  AnalyzedDataDef(kind: adkStruct, struct: struct)

proc newAnalyzedDataDef*(union: AnalyzedUnionDef): AnalyzedDataDef =
  AnalyzedDataDef(kind: adkUnion, union: union)

proc kind*(d: AnalyzedDataDef): AnalyzedDataKind = d.kind
proc literal*(d: AnalyzedDataDef): AnalyzedLiteralDef =
  assert d.kind == adkLiteral,
    fmt"AnalyzedDataDef.literal accessed but kind is {d.kind}"
  d.literal
proc struct*(d: AnalyzedDataDef): AnalyzedStructDef =
  assert d.kind == adkStruct,
    fmt"AnalyzedDataDef.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: AnalyzedDataDef): AnalyzedUnionDef =
  assert d.kind == adkUnion,
    fmt"AnalyzedDataDef.union accessed but kind is {d.kind}"
  d.union
