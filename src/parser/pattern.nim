## Case-pattern grammar: the union-variant destructuring patterns
## (`Variant { field: binding }`) and the `CasePattern` a `case` header
## carries (integer literal, variable binding, or union variant). These
## are non-recursive leaves consumed by the match/case cluster in
## statement.nim.

import strformat, strutils, sequtils, tables, results

import parser

import identifiers
import scalars

# ============================================================
# UnionPatternField
# ============================================================

type UnionPatternField* = ref object
  name: Identifier
  binding: Identifier
  loc: Location

proc newUnionPatternField*(name: Identifier, binding: Identifier,
    loc: Location): UnionPatternField =
  UnionPatternField(name: name, binding: binding, loc: loc)

proc name*(field: UnionPatternField): Identifier = field.name
proc binding*(field: UnionPatternField): Identifier = field.binding

proc asl(field: UnionPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

proc unionExplicitPatternFieldConsumer(parser: Parser): Result[UnionPatternField, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(SPACE.optional())
  let binding = ? parser.expect(identifierSpec)
  ok(newUnionPatternField(name, binding, name.loc))

let unionExplicitPatternFieldSpec = newSpec("union explicit pattern field", unionExplicitPatternFieldConsumer)

let unionImplicitPatternFieldSpec = map(identifierSpec,
  proc(name: Identifier): UnionPatternField = newUnionPatternField(name, name, name.loc))

let unionPatternFieldSpec* = oneOf("union pattern field", @[
  unionExplicitPatternFieldSpec,
  unionImplicitPatternFieldSpec
])

# ============================================================
# UnionPattern
# ============================================================

proc validateFieldNameConflict(fields: seq[UnionPatternField]): Result[void, ParserError] =
  var nameIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in nameIndex:
      let prev = fields[nameIndex[field.name]].name
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.name.loc))
    nameIndex[field.name] = index
  ok()

proc validateFieldBindingConflict(fields: seq[UnionPatternField]): Result[void, ParserError] =
  var bindingIndex: Table[Identifier, int]
  for index, field in fields:
    if field.binding in bindingIndex:
      let prev = fields[bindingIndex[field.binding]].binding
      let msg = fmt"duplicate binding encountered, see previous binding at {prev.loc}"
      return err(newParserError(msg, field.binding.loc))
    else:
      bindingIndex[field.binding] = index
  ok()

type UnionPattern* = ref object
  variant: Identifier
  fields: seq[UnionPatternField]
  bindings: seq[Identifier]
  loc: Location

proc newUnionPattern*(variant: Identifier, fields: seq[UnionPatternField]): Result[UnionPattern, ParserError] =
  ? validateFieldNameConflict(fields)
  ? validateFieldBindingConflict(fields)
  let bindings = fields.mapIt(it.binding)
  ok(UnionPattern(variant: variant, fields: fields, bindings: bindings))

proc name*(vp: UnionPattern): Identifier = vp.variant
proc fields*(vp: UnionPattern): seq[UnionPatternField] = vp.fields
proc bindings*(vp: UnionPattern): seq[Identifier] = vp.bindings
proc loc*(vp: UnionPattern): Location = vp.name.loc

proc asl(vp: UnionPattern): string =
  var content: string
  let inner = vp.fields.mapIt(asl(it)).join(", ")
  content.add(fmt"{asl(vp.variant)} {{ {inner} }}")
  content

# Variant pattern: VariantName { field: binding, field: binding }
proc unionPatternConsumer(parser: Parser): Result[UnionPattern, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(SPACE.optional())
  let (fields, _) = ? parser.expect(unionPatternFieldSpec.curlyBracketList())
  newUnionPattern(name, fields)

let unionPatternSpec* = newSpec[UnionPattern]("union pattern", unionPatternConsumer)

# ============================================================
# CasePattern
# ============================================================

type
  CasePatternKind* = enum
    cpkInteger, cpkVariable, cpkUnion
  CasePattern* = ref object
    case kind: CasePatternKind
    of cpkInteger: intLit: IntegerLiteral
    of cpkVariable: variable: Identifier
    of cpkUnion: variant: UnionPattern

proc newCasePattern*(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkInteger, intLit: intLit)

proc newCasePattern*(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newCasePattern*(variant: UnionPattern): CasePattern =
  CasePattern(kind: cpkUnion, variant: variant)

proc kind*(cp: CasePattern): CasePatternKind = cp.kind
proc loc*(cp: CasePattern): Location =
  case cp.kind:
  of cpkInteger: cp.intLit.loc
  of cpkVariable: cp.variable.loc
  of cpkUnion: cp.variant.loc

proc intLit*(cp: CasePattern): IntegerLiteral =
  assert cp.kind == cpkInteger,
    fmt"CasePattern.intLit accessed but kind is {cp.kind}"
  cp.intLit

proc variable*(cp: CasePattern): Identifier =
  assert cp.kind == cpkVariable,
    fmt"CasePattern.variable accessed but kind is {cp.kind}"
  cp.variable

proc variant*(cp: CasePattern): UnionPattern =
  assert cp.kind == cpkUnion,
    fmt"CasePattern.variant accessed but kind is {cp.kind}"
  cp.variant

proc asl*(pattern: CasePattern): string =
  case pattern.kind:
  of cpkInteger: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkUnion: asl(pattern.variant)

let casePatternSpec* = oneOf("case pattern", @[
  map(integerLiteralSpec, newCasePattern),
  map(unionPatternSpec, newCasePattern),
  map(identifierSpec, newCasePattern),
])

proc caseHeaderConsumer(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.expect("case")
  discard ? parser.expect(SPACE)
  let pat = ? parser.expect(casePatternSpec)
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect(":")
  ok(pat)

let caseHeaderSpec* = newSpec[CasePattern]("case header", caseHeaderConsumer)
