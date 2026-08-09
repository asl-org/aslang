## Resolved data-block cluster — the closely-coupled def types a module's
## data block resolves to. `ResolvedDataDef` is the tagged-union umbrella
## over literal (primitive) / struct / union; a union owns variants;
## struct and variant own resolved field defs.

import results, sequtils, sets, strformat, tables

import parser
import indexing
import argtype  # ResolvedGenericArgumentType lives here
import argdef

# ---- ResolvedLiteralDef ----
# The discriminator tag a literal-backed module (u8..u64, i8..i64, f32,
# f64, string, pointer) carries through resolution.

type
  ResolvedLiteralDef* = enum
    rltkU8, rltkU16, rltkU32, rltkU64
    rltkI8, rltkI16, rltkI32, rltkI64
    rltkF32, rltkF64, rltkString, rltkPointer

proc newResolvedLiteralDef*(literal: LiteralDef): Result[ResolvedLiteralDef, string] =
  case literal.content:
  of "u8": ok(rltkU8)
  of "u16": ok(rltkU16)
  of "u32": ok(rltkU32)
  of "u64": ok(rltkU64)
  of "i8": ok(rltkI8)
  of "i16": ok(rltkI16)
  of "i32": ok(rltkI32)
  of "i64": ok(rltkI64)
  of "f32": ok(rltkF32)
  of "f64": ok(rltkF64)
  of "string": ok(rltkString)
  of "pointer": ok(rltkPointer)
  else: err(fmt"{literal.loc} unsupported literal type encountered `{literal.content}`")

# Shared slot→position index over a def's (already-deduped) generic
# slots. Struct and union both use it; the assert never fires because
# both `generics` seqs are deduped first-seen upstream.
proc buildGenericTypeIndex(generics: seq[ResolvedGenericArgumentType]): Table[ResolvedGenericArgumentType, int] =
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for id, generic in generics:
    assert(generic notin genericTypeIndex, "[BUG] - Resolver dedups generic slots first-seen")
    genericTypeIndex[generic] = id
  return genericTypeIndex

# ---- ResolvedStructDef ----
# A struct definition whose fields (and required impl set) are resolved.

type ResolvedStructDef* = ref object
  parsed: StructDef
  generics: seq[ResolvedGenericArgumentType]
  fields: seq[ResolvedArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newResolvedStructDef*(parsed: StructDef, requires: seq[ResolvedGenericArgumentType], fields: seq[ResolvedArgumentDef]): Result[ResolvedStructDef, string] =
  ## Front-door: owns the explicit-vs-inferred decision. With an
  ## explicit `struct(...)` header (`requires` non-empty) no field may
  ## be generic-typed — the two declaration modes are mutually
  ## exclusive; with a plain header the generics are inferred from
  ## the fields in first-seen order. Nothing downstream needs to know
  ## which path produced the def.
  var genericFields: OrderedSet[ResolvedGenericArgumentType]
  for field in fields:
    case field.argType.kind:
    of ratkModule: discard
    of ratkGeneric: genericFields.incl(field.argType.generic)

  if requires.len > 0 and genericFields.len > 0:
    return err(fmt"{parsed.loc} struct with explicit generic requirements does not support generic fields")

  let generics = if requires.len > 0: requires else: genericFields.toSeq
  let fieldIndex = fields.indexByName()
  ok(ResolvedStructDef(parsed: parsed, generics: generics, fields: fields, fieldIndex: fieldIndex))

proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] = struct.generics

proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.generics.buildGenericTypeIndex()

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# ---- ResolvedVariantDef ----
# One branch of a resolved union: the parser VariantDef + its resolved
# fields, with the variant's own generic slots inferred from the fields.

proc buildGenerics(fields: seq[ResolvedArgumentDef]): seq[ResolvedGenericArgumentType] =
  var genericSet: HashSet[ResolvedGenericArgumentType]
  var generics: seq[ResolvedGenericArgumentType]
  for field in fields:
    case field.argType.kind:
    of ratkModule: discard
    of ratkGeneric:
      let generic = field.argType.generic
      if generic notin genericSet:
        generics.add(generic)
        genericSet.incl(generic)
  return generics

type ResolvedVariantDef* = ref object
  parsed: VariantDef
  fields: seq[ResolvedArgumentDef]
  generics: seq[ResolvedGenericArgumentType]
  fieldIndex: Table[Identifier, int]

proc newResolvedVariantDef*(parsed: VariantDef, fields: seq[ResolvedArgumentDef]): ResolvedVariantDef =
  let fieldIndex = fields.indexByName()
  let generics = buildGenerics(fields)
  ResolvedVariantDef(parsed: parsed, fields: fields, generics: generics, fieldIndex: fieldIndex)

proc name*(variant: ResolvedVariantDef): Identifier = variant.parsed.name
proc fields*(variant: ResolvedVariantDef): seq[ResolvedArgumentDef] = variant.fields
proc requires*(variant: ResolvedVariantDef): seq[ResolvedGenericArgumentType] = variant.generics

proc findField*(variant: ResolvedVariantDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# ---- ResolvedUnionDef ----
# A union definition, indexed by variant name and by required impl set.
# Its generic slots are the union of the variants' slots (first-seen).

proc buildGenerics(variants: seq[ResolvedVariantDef]): seq[ResolvedGenericArgumentType] =
  var generics: OrderedSet[ResolvedGenericArgumentType]
  for variant in variants:
    for generic in variant.requires:
      generics.incl(generic)
  return generics.toSeq

type ResolvedUnionDef* = ref object
  parsed: UnionDef
  generics: seq[ResolvedGenericArgumentType]
  variants: seq[ResolvedVariantDef]
  variantIndex: Table[Identifier, int]

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariantDef]): ResolvedUnionDef =
  let variantIndex = variants.indexByName()
  let generics = buildGenerics(variants)
  ResolvedUnionDef(parsed: parsed, variants: variants, generics: generics, variantIndex: variantIndex)

proc variants*(union: ResolvedUnionDef): seq[ResolvedVariantDef] = union.variants
proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] = union.generics
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = buildGenericTypeIndex(union.generics)

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariantDef, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc findVariant*(union: ResolvedUnionDef, variant: VariantDef): ResolvedVariantDef =
  ## Identity form — the resolver already located this variant on the
  ## parser-side union at ref-resolve time, so the resolved twin
  ## cannot miss.
  assert(variant.name in union.variantIndex, fmt"[BUG] - {variant.loc} variant `{variant.name.asl}` missing from the resolved union")
  union.variants[union.variantIndex[variant.name]]

# ---- ResolvedDataDef ----
# Tagged-union umbrella over literal / struct / union.

type
  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion

  ResolvedDataDef* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralDef
    of rdkStruct: struct: ResolvedStructDef
    of rdkUnion: union: ResolvedUnionDef

proc newResolvedDataDef*(literal: ResolvedLiteralDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkLiteral, literal: literal)

proc newResolvedDataDef*(struct: ResolvedStructDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkStruct, struct: struct)

proc newResolvedDataDef*(union: ResolvedUnionDef): ResolvedDataDef =
  ResolvedDataDef(kind: rdkUnion, union: union)

proc kind*(data: ResolvedDataDef): ResolvedDataKind = data.kind
proc literal*(data: ResolvedDataDef): ResolvedLiteralDef =
  assert data.kind == rdkLiteral,
    fmt"ResolvedDataDef.literal accessed but kind is {data.kind}"
  data.literal
proc struct*(data: ResolvedDataDef): ResolvedStructDef =
  assert data.kind == rdkStruct,
    fmt"ResolvedDataDef.struct accessed but kind is {data.kind}"
  data.struct
proc union*(data: ResolvedDataDef): ResolvedUnionDef =
  assert data.kind == rdkUnion,
    fmt"ResolvedDataDef.union accessed but kind is {data.kind}"
  data.union

proc requires*(data: ResolvedDataDef): seq[ResolvedGenericArgumentType] =
  case data.kind:
  of rdkLiteral: @[]
  of rdkStruct: data.struct.requires
  of rdkUnion: data.union.requires
