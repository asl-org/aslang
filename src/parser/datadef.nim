## Parser data-block cluster — the closely-coupled AST types a module's
## data block parses to. `DataDef` is a tagged union over literal /
## struct / union; a union owns variants; struct and variant own field
## defs. (`LiteralDef` itself lives with the literal value types in
## ./literals.)

import strformat, strutils, sequtils, tables, results, options

import ../tokenizer/main as tokenizer
import parser
import error

import identifiers
import argtype
import literals

# Shared field name→position index with duplicate detection — used by
# both StructDef and VariantDef.
proc buildNameIndex(fields: seq[ArgumentDef]): Result[Table[Identifier, int], ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc, fatal = true))
    fieldIndex[field.name] = index
  ok(fieldIndex)

# ============================================================
# StructDefHeader
# ============================================================

proc validateRequiresNameConflict(requires: seq[Identifier]): Result[void, ParserError] =
  var requiresIndex: Table[Identifier, int]
  for index, required in requires:
    if required in requiresIndex:
      let prev = requires[requiresIndex[required]]
      let msg = fmt"duplicate generic encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, required.loc, fatal = true))
    requiresIndex[required] = index
  ok()

type
  StructDefHeader* = ref object
    loc: Location
    requires: seq[Identifier]

proc newStructDefHeader*(requires: seq[Identifier], loc: Location): Result[StructDefHeader, ParserError] =
  ? validateRequiresNameConflict(requires)
  ok(StructDefHeader(loc: loc, requires: requires))

proc requires*(header: StructDefHeader): seq[Identifier] = header.requires
proc asl*(s: StructDefHeader): string =
  if s.requires.len == 0:
    "struct:"
  else:
    let impls = s.requires.mapIt(it.asl).join(", ")
    fmt"struct({impls}):"

proc structRequiresConsumer(parser: Parser): Result[seq[Identifier], ParserError] =
  let (generics, _) = ? parser.expect(identifierSpec.parenthesisList(allowEmpty = false))
  ok(generics)

let requiredStructGenerics* = newSpec[seq[Identifier]]("required struct generics", structRequiresConsumer)

# struct: field+ (field is identifier ":" argumentType)
proc structHeaderConsumer(parser: Parser): Result[StructDefHeader, ParserError] =
  let structKeyword = ? parser.expect("struct")

  let maybeRequires = ? parser.expect(requiredStructGenerics.optional())
  let requires = if maybeRequires.isSome: maybeRequires.get else: @[]

  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  newStructDefHeader(requires, structKeyword.loc)

let structHeaderSpec* = newSpec[StructDefHeader]("struct def header", structHeaderConsumer)

# ============================================================
# StructDef
# ============================================================

type StructDef* = ref object
  header: StructDefHeader
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]

proc newStructDef*(header: StructDefHeader, fields: seq[ArgumentDef]): Result[StructDef, ParserError] =
  if fields.len == 0:
    err(newParserError("struct must have at least one field", header.loc, fatal = true))
  else:
    let fieldIndex = ? buildNameIndex(fields)
    ok(StructDef(header: header, fields: fields, fieldIndex: fieldIndex))

proc loc*(s: StructDef): Location = s.header.loc
proc header*(s: StructDef): StructDefHeader = s.header
proc fields*(s: StructDef): seq[ArgumentDef] = s.fields

proc asl*(s: StructDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}{s.header.asl}")

  for field in s.fields:
    lines.add(fmt"{inner}{field.asl}")
  lines

proc findFieldId*(struct: StructDef, name: Identifier): Result[int, string] =
  if name notin struct.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` is not present in the struct")
  else:
    ok(struct.fieldIndex[name])

# Each field line: (blank lines) + indentation + argumentDef + newline
proc indentedArgumentDefConsumer(parser: Parser): Result[ArgumentDef, ParserError] =
  discard ? parser.expect(any(emptyLineSpec))
  let def = ? parser.expect(argumentDefSpec.indentedLine())
  ok(def)

let argDefLineSpec* = newSpec[ArgumentDef]("argument def", indentedArgumentDefConsumer)

proc structDefConsumer(parser: Parser): Result[StructDef, ParserError] =
  let (header, body) = ? parser.indentedBlock(structHeaderSpec, argumentDefSpec.indentedLine().atLeastOne())
  newStructDef(header, body)

let structDefSpec* = newSpec[StructDef]("struct def", structDefConsumer)

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
  let fieldIndex = ? buildNameIndex(fields)
  ok(VariantDef(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc name*(v: VariantDef): Identifier = v.name
proc fields*(v: VariantDef): seq[ArgumentDef] = v.fields
proc loc*(v: VariantDef): Location = v.loc

proc asl*(varDef: VariantDef): string =
  var content: string
  content.add(asl(varDef.name))
  if varDef.fields.len > 0:
    let inner = varDef.fields.mapIt(asl(it)).join(", ")
    content.add(fmt" {{ {inner} }}")
  content

proc findFieldId*(variant: VariantDef, name: Identifier): Result[int, string] =
  if name notin variant.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` does not exist in union variant `{variant.name.asl}`")
  else:
    ok(variant.fieldIndex[name])

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
proc variantDefConsumer(parser: Parser): Result[VariantDef, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  let (fields, _) = ? parser.expect(argumentDefSpec.curlyBracketList())
  newVariantDef(name, fields, name.loc)

let variantDefSpec* = newSpec[VariantDef]("variant def line", variantDefConsumer)

# ============================================================
# UnionDef
# ============================================================

proc buildNameIndex(variants: seq[VariantDef]): Result[Table[Identifier, int], ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(variantIndex)

type UnionDef* = ref object
  variants: seq[VariantDef]
  variantIndex: Table[Identifier, int]
  loc: Location

proc newUnionDef*(variants: seq[VariantDef], loc: Location): Result[UnionDef, ParserError] =
  let variantIndex = ? buildNameIndex(variants)
  ok(UnionDef(variants: variants, variantIndex: variantIndex, loc: loc))

proc variants*(u: UnionDef): seq[VariantDef] = u.variants
proc loc*(u: UnionDef): Location = u.loc

proc asl*(u: UnionDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}union:")
  for variant in u.variants:
    lines.add(fmt"{inner}{asl(variant)}")
  lines

proc findVariant*(union: UnionDef, variant: Identifier): Result[VariantDef, string] =
  if variant notin union.variantIndex:
    err(fmt"{variant.loc} variant `{variant.asl}` does not exist in union")
  else:
    ok(union.variants[union.variantIndex[variant]])

proc unionDefHeaderConsumer(parser: Parser): Result[Location, ParserError] =
  let unionKeyword = ? parser.expect("union")
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(unionKeyword.loc)

let unionDefHeaderSpec* = newSpec[Location]("union header", unionDefHeaderConsumer)

proc unionDefConsumer(parser: Parser): Result[UnionDef, ParserError] =
  let (loc, body) = ? parser.indentedBlock(unionDefHeaderSpec, variantDefSpec.indentedLine().atLeastOne())
  newUnionDef(body, loc)

let unionDefSpec* = newSpec[UnionDef]("union def", unionDefConsumer)

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
  assert(db.kind == ddkLiteral, fmt"DataDef.literal accessed but kind is {db.kind}")
  db.literal
proc struct*(db: DataDef): StructDef =
  assert(db.kind == ddkStruct, fmt"DataDef.struct accessed but kind is {db.kind}")
  db.struct
proc union*(db: DataDef): UnionDef =
  assert(db.kind == ddkUnion, fmt"DataDef.union accessed but kind is {db.kind}")
  db.union

proc loc*(db: DataDef): Location =
  case db.kind:
  of ddkLiteral: db.literal.loc
  of ddkStruct: db.struct.loc
  of ddkUnion: db.union.loc

proc asl*(db: DataDef, level: int, indentWidth: uint32): seq[string] =
  case db.kind:
  of ddkLiteral: db.literal.asl(level, indentWidth)
  of ddkStruct: db.struct.asl(level, indentWidth)
  of ddkUnion: db.union.asl(level, indentWidth)

let dataDefSpec* = oneOf("data block", @[
  literalDefSpec.map(newDataDef),
  structDefSpec.map(newDataDef),
  unionDefSpec.map(newDataDef),
])
