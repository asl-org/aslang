## Phase-A data-block cluster — the five closely-coupled def types a
## module's data block resolves to. `AnalyzedDataDef` is a tagged union
## over literal / struct / union; a union owns variants; struct and
## variant own analyzed field defs. Produced by `analyzeData` on the
## facade; `AnalyzedDataDef` is `AnalyzedDefModule`'s optional data field.

import results, strformat, tables

import ./resolver
import ./argtype

# ---- AnalyzedLiteralDef ----
# Thin wrapper around a ResolvedLiteralDef. Literal blocks carry no
# field types, so analysis is a no-op — the wrapper exists so
# AnalyzedDataDef can discriminate uniformly over literal/struct/union.

type AnalyzedLiteralDef* = ref object
  resolved: ResolvedLiteralDef

proc newAnalyzedLiteralDef*(resolved: ResolvedLiteralDef): AnalyzedLiteralDef =
  AnalyzedLiteralDef(resolved: resolved)

proc resolved*(b: AnalyzedLiteralDef): ResolvedLiteralDef = b.resolved

# ---- AnalyzedStructDef ----
# A resolved struct + its fully-analyzed field defs. Delegates
# genericTypeIndex to the resolver's already-computed table.

type AnalyzedStructDef* = ref object
  resolved: ResolvedStructDef
  fields: seq[AnalyzedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedStructDef*(resolved: ResolvedStructDef,
    fields: seq[AnalyzedArgumentDef]): AnalyzedStructDef =
  AnalyzedStructDef(resolved: resolved, fields: fields, fieldIndex: fields.indexByName())

proc genericTypeIndex(s: AnalyzedStructDef): Table[ResolvedGenericArgumentType, int] = s.resolved.genericTypeIndex

proc findField*(s: AnalyzedStructDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in s.fieldIndex: ok(s.fields[s.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# ---- AnalyzedVariantDef ----
# A resolved union variant + its fully-analyzed field defs. The
# enclosing union shares one genericTypeIndex across variants.

type AnalyzedVariantDef* = ref object
  resolved: ResolvedVariantDef
  fields: seq[AnalyzedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newAnalyzedVariantDef*(resolved: ResolvedVariantDef,
    fields: seq[AnalyzedArgumentDef]): AnalyzedVariantDef =
  AnalyzedVariantDef(resolved: resolved, fields: fields, fieldIndex: fields.indexByName())

proc name*(v: AnalyzedVariantDef): Identifier = v.resolved.name

proc findField*(v: AnalyzedVariantDef, name: Identifier): Result[AnalyzedArgumentDef, string] =
  if name in v.fieldIndex: ok(v.fields[v.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# ---- AnalyzedUnionDef ----
# A resolved union + its fully-analyzed variants. Delegates
# genericTypeIndex to the resolver's already-computed table (Rust-style
# dedup across variants happens in the resolver).

type AnalyzedUnionDef* = ref object
  resolved: ResolvedUnionDef
  variants: seq[AnalyzedVariantDef]
  variantIndex: Table[Identifier, int]

proc newAnalyzedUnionDef*(resolved: ResolvedUnionDef, variants: seq[AnalyzedVariantDef]): AnalyzedUnionDef =
  AnalyzedUnionDef(resolved: resolved, variants: variants, variantIndex: variants.indexByName())

proc variants*(u: AnalyzedUnionDef): seq[AnalyzedVariantDef] = u.variants
proc genericTypeIndex*(u: AnalyzedUnionDef): Table[ResolvedGenericArgumentType, int] =
  u.resolved.genericTypeIndex

proc findVariant*(union: AnalyzedUnionDef, name: Identifier): AnalyzedVariantDef =
  assert(name in union.variantIndex, "UNREACHABLE: duplicate variant name must have been caught by resolver")
  union.variants[union.variantIndex[name]]

# ---- AnalyzedDataDef ----
# Tagged union over the three data-block kinds.

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
