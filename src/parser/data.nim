import strformat, strutils, options, tables, results

import tokenizer
import combinators
import helpers
import identifiers
import literals
import argtypes

# ============================================================
# StructDef
# ============================================================

type StructDef* = ref object
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc fields*(s: StructDef): seq[ArgumentDefinition] = s.fields
proc loc*(s: StructDef): Location = s.loc

proc newStructDef*(fields: seq[ArgumentDefinition], loc: Location): Result[StructDef, ParserError] =
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
let structHeaderSpec = Spec[Location](
  name: "struct_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("struct"))
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

# Each field line: indentation + argumentDefinition + newline
let fieldLineSpec = Spec[ArgumentDefinition](
  name: "field_line",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  discard ? parser.run(indentationSpec)
  let argDef = ? parser.run(argumentDefinitionSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(argDef)
)

let structSpec* = blockSpec("struct", structHeaderSpec,
  atLeastOne(fieldLineSpec),
  proc(h: Location, b: seq[ArgumentDefinition]): Result[StructDef, ParserError] =
  newStructDef(b, h))

# ============================================================
# VariantDefinition
# ============================================================

type VariantDefinition* = ref object
  name: Identifier
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc newVariantDefinition*(name: Identifier, fields: seq[ArgumentDefinition],
    loc: Location): Result[VariantDefinition, ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(VariantDefinition(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc name*(v: VariantDefinition): Identifier = v.name
proc fields*(v: VariantDefinition): seq[ArgumentDefinition] = v.fields
proc loc*(v: VariantDefinition): Location = v.loc

proc asl(varDef: VariantDefinition): string =
  result = asl(varDef.name)
  if varDef.fields.len > 0:
    result.add(" { ")
    for i, field in varDef.fields:
      if i > 0: result.add(", ")
      result.add(asl(field))
    result.add(" }")

proc findFieldId*(variant: VariantDefinition, name: Identifier): Result[int, string] =
  if name notin variant.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` does not exist in union variant `{variant.name.asl}`")
  else:
    ok(variant.fieldIndex[name])

# union: variant+ (variant is identifier space* ("{" argDef, argDef "}")?)
let variantDefinitionLineSpec = Spec[VariantDefinition](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDefinition, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let maybeFields = ? parser.run(optional(contained("variant_fields", "{",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), "}")))
  var fields: seq[ArgumentDefinition]
  if maybeFields.isSome: fields = maybeFields.get
  discard ? parser.run(ignorableLineSpec)
  newVariantDefinition(name, fields, name.loc)
)

# ============================================================
# UnionDef
# ============================================================

type UnionDef* = ref object
  variants: seq[VariantDefinition]
  variantIndex: Table[Identifier, int]
  loc: Location

proc newUnionDef*(variants: seq[VariantDefinition], loc: Location): Result[UnionDef, ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(UnionDef(variants: variants, variantIndex: variantIndex, loc: loc))

proc variants*(u: UnionDef): seq[VariantDefinition] = u.variants
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

proc findVariant*(union: UnionDef, variant: Identifier): Result[VariantDefinition, string] =
  let variantId = ? union.findVariantId(variant)
  ok(union.variants[variantId])

let unionHeaderSpec = Spec[Location](
  name: "union_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("union"))
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

let unionSpec* = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefinitionLineSpec),
  proc(h: Location, b: seq[VariantDefinition]): Result[UnionDef, ParserError] =
  newUnionDef(b, h))

# ============================================================
# DataBlock
# ============================================================

type
  DataBlockKind* = enum
    dbkLiteral, dbkStruct, dbkUnion
  DataBlock* = ref object
    case kind: DataBlockKind
    of dbkLiteral: literal: LiteralDef
    of dbkStruct: struct: StructDef
    of dbkUnion: union: UnionDef

proc newDataBlock*(l: LiteralDef): DataBlock =
  DataBlock(kind: dbkLiteral, literal: l)

proc newDataBlock*(s: StructDef): DataBlock =
  DataBlock(kind: dbkStruct, struct: s)

proc newDataBlock*(u: UnionDef): DataBlock =
  DataBlock(kind: dbkUnion, union: u)

proc kind*(db: DataBlock): DataBlockKind = db.kind
proc literal*(db: DataBlock): LiteralDef =
  assert db.kind == dbkLiteral,
    fmt"DataBlock.literal accessed but kind is {db.kind}"
  db.literal
proc struct*(db: DataBlock): StructDef =
  assert db.kind == dbkStruct,
    fmt"DataBlock.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataBlock): UnionDef =
  assert db.kind == dbkUnion,
    fmt"DataBlock.union accessed but kind is {db.kind}"
  db.union

proc loc*(db: DataBlock): Location =
  case db.kind:
  of dbkLiteral: db.literal.loc
  of dbkStruct: db.struct.loc
  of dbkUnion: db.union.loc

proc asl*(db: DataBlock, indentWidth: uint32): seq[string] =
  case db.kind:
  of dbkLiteral: asl(db.literal)
  of dbkStruct: asl(db.struct, indentWidth)
  of dbkUnion: asl(db.union, indentWidth)

proc struct*(db: DataBlock, module: Identifier): Result[StructDef, string] =
  case db.kind:
  of dbkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of dbkUnion: err(fmt"{db.loc} module `{module.asl}` is a union")
  of dbkStruct: ok(db.struct)

proc union*(db: DataBlock, module: Identifier): Result[UnionDef, string] =
  case db.kind:
  of dbkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of dbkStruct: err(fmt"{db.loc} module `{module.asl}` is a struct")
  of dbkUnion: ok(db.union)

let dataBlockSpec* = oneOf("data_block", [
  literalTypeSpec.map("literal_data",
    proc(v: LiteralDef): DataBlock = newDataBlock(v)),
  structSpec.map("struct_data",
    proc(v: StructDef): DataBlock = newDataBlock(v)),
  unionSpec.map("union_data",
    proc(v: UnionDef): DataBlock = newDataBlock(v)),
])
