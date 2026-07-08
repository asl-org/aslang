import strformat, strutils, options, tables, results

import ./tokenizer
import ./combinators
import ./identifiers
import ./literals
import ./argtypes

# ============================================================
# StructDef
# ============================================================

type StructDef* = ref object
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc fields*(s: StructDef): seq[ArgumentDef] = s.fields
proc loc*(s: StructDef): Location = s.loc

proc newStructDef*(fields: seq[ArgumentDef], loc: Location): Result[StructDef, ParserError] =
  if fields.len == 0:
    return err(newParserError("struct must have at least one field", loc))
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(StructDef(fields: fields, fieldIndex: fieldIndex, loc: loc))

proc asl(s: StructDef, indentWidth: uint32): seq[string] =
  result.add("struct:")
  let indent = " ".repeat(indentWidth)
  for field in s.fields:
    result.add(fmt"{indent}{asl(field)}")

proc findFieldId*(struct: StructDef, name: Identifier): Result[int, string] =
  if name notin struct.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` is not present in the struct")
  else:
    ok(struct.fieldIndex[name])

# struct: field+ (field is identifier ":" argumentType)
let structHeaderSpec = suffixed(keywordSpec("struct"),
  pair(ws0, punctuationSpec(":")))

# Each field line: (blank lines) + indentation + argumentDef + newline
let argumentDefLineSpec = prefixed(blankLines, indentedLine(argumentDefSpec))

let structSpec* = blockSpec("struct", structHeaderSpec,
  atLeastOne(argumentDefLineSpec),
  proc(h: Location, b: seq[ArgumentDef]): Result[StructDef, ParserError] =
  newStructDef(b, h))

# ============================================================
# VariantDef
# ============================================================

type VariantDef* = ref object
  name: Identifier
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc newVariantDef*(name: Identifier, fields: seq[ArgumentDef],
    loc: Location): Result[VariantDef, ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(VariantDef(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc name*(v: VariantDef): Identifier = v.name
proc fields*(v: VariantDef): seq[ArgumentDef] = v.fields
proc loc*(v: VariantDef): Location = v.loc

proc asl(varDef: VariantDef): string =
  result = asl(varDef.name)
  if varDef.fields.len > 0:
    result.add(" { ")
    for i, field in varDef.fields:
      if i > 0: result.add(", ")
      result.add(asl(field))
    result.add(" }")

proc findFieldId*(variant: VariantDef, name: Identifier): Result[int, string] =
  if name notin variant.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` does not exist in union variant `{variant.name.asl}`")
  else:
    ok(variant.fieldIndex[name])

# union: variant+ (variant is identifier space* ("{" argDef, argDef "}")?)
let variantDefLineSpec = Spec[VariantDef](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDef, ParserError] =
  discard parser.run(blankLines)
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  let maybeFields = ? parser.run(optional(contained("variant_fields", "{",
    separatedBy(argumentDefSpec, commaWithSpacesSpec), "}")))
  var fields: seq[ArgumentDef]
  if maybeFields.isSome: fields = maybeFields.get
  discard ? parser.run(ignorableLineSpec)
  newVariantDef(name, fields, name.loc)
)

# ============================================================
# UnionDef
# ============================================================

type UnionDef* = ref object
  variants: seq[VariantDef]
  variantIndex: Table[Identifier, int]
  loc: Location

proc newUnionDef*(variants: seq[VariantDef], loc: Location): Result[UnionDef, ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(UnionDef(variants: variants, variantIndex: variantIndex, loc: loc))

proc variants*(u: UnionDef): seq[VariantDef] = u.variants
proc loc*(u: UnionDef): Location = u.loc

proc asl(u: UnionDef, indentWidth: uint32): seq[string] =
  result.add("union:")
  let indent = " ".repeat(indentWidth)
  for variant in u.variants:
    result.add(fmt"{indent}{asl(variant)}")

proc findVariantId(union: UnionDef, variant: Identifier): Result[int, string] =
  if variant notin union.variantIndex:
    err(fmt"{variant.loc} variant `{variant.asl}` does not exist in union")
  else:
    ok(union.variantIndex[variant])

proc findVariant*(union: UnionDef, variant: Identifier): Result[VariantDef, string] =
  let variantId = ? union.findVariantId(variant)
  ok(union.variants[variantId])

let unionHeaderSpec = suffixed(keywordSpec("union"),
  pair(ws0, punctuationSpec(":")))

let unionSpec* = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefLineSpec),
  proc(h: Location, b: seq[VariantDef]): Result[UnionDef, ParserError] =
  newUnionDef(b, h))

# ============================================================
# DataDef
# ============================================================

type
  DataDefKind* = enum
    ddkLiteral, ddkStruct, ddkUnion
  DataDef* = ref object
    case kind: DataDefKind
    of ddkLiteral: literal: LiteralDef
    of ddkStruct: struct: StructDef
    of ddkUnion: union: UnionDef

proc newDataDef*(l: LiteralDef): DataDef =
  DataDef(kind: ddkLiteral, literal: l)

proc newDataDef*(s: StructDef): DataDef =
  DataDef(kind: ddkStruct, struct: s)

proc newDataDef*(u: UnionDef): DataDef =
  DataDef(kind: ddkUnion, union: u)

proc kind*(db: DataDef): DataDefKind = db.kind
proc literal*(db: DataDef): LiteralDef =
  assert db.kind == ddkLiteral,
    fmt"DataDef.literal accessed but kind is {db.kind}"
  db.literal
proc struct*(db: DataDef): StructDef =
  assert db.kind == ddkStruct,
    fmt"DataDef.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataDef): UnionDef =
  assert db.kind == ddkUnion,
    fmt"DataDef.union accessed but kind is {db.kind}"
  db.union

proc loc*(db: DataDef): Location =
  case db.kind:
  of ddkLiteral: db.literal.loc
  of ddkStruct: db.struct.loc
  of ddkUnion: db.union.loc

proc asl*(db: DataDef, indentWidth: uint32): seq[string] =
  case db.kind:
  of ddkLiteral: asl(db.literal)
  of ddkStruct: asl(db.struct, indentWidth)
  of ddkUnion: asl(db.union, indentWidth)

proc struct*(db: DataDef, module: Identifier): Result[StructDef, string] =
  case db.kind:
  of ddkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of ddkUnion: err(fmt"{db.loc} module `{module.asl}` is a union")
  of ddkStruct: ok(db.struct)

proc union*(db: DataDef, module: Identifier): Result[UnionDef, string] =
  case db.kind:
  of ddkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of ddkStruct: err(fmt"{db.loc} module `{module.asl}` is a struct")
  of ddkUnion: ok(db.union)

let dataSpec* = oneOf("data_block", [
  literalTypeSpec.map("literal_data",
    proc(v: LiteralDef): DataDef = newDataDef(v)),
  structSpec.map("struct_data",
    proc(v: StructDef): DataDef = newDataDef(v)),
  unionSpec.map("union_data",
    proc(v: UnionDef): DataDef = newDataDef(v)),
])
