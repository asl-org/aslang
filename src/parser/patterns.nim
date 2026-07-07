import strformat, tables, results

import tokenizer
import combinators
import identifiers
import literals

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
proc loc*(field: UnionPatternField): Location = field.loc

proc asl(field: UnionPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

# Variant pattern field: name ":" binding (both identifiers)
let unionPatternFieldSpec* = Spec[UnionPatternField](
  name: "variant_pattern_field",
  parseFn: proc(parser: Parser): Result[UnionPatternField, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let binding = ? parser.run(identifierSpec)
  ok(newUnionPatternField(name, binding, name.loc))
)

# ============================================================
# UnionPattern
# ============================================================

type UnionPattern* = ref object
  variant: Identifier
  fields: seq[UnionPatternField]
  bindings: seq[Identifier]
  loc: Location

proc newUnionPattern*(variant: Identifier, fields: seq[UnionPatternField]): Result[UnionPattern, ParserError] =
  var nameIndex: Table[Identifier, int]
  var bindingIndex: Table[Identifier, int]
  var bindings: seq[Identifier]

  for index, field in fields:
    if field.name in nameIndex:
      let prev = fields[nameIndex[field.name]].name
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.name.loc))
    else:
      nameIndex[field.name] = index

    if field.binding in bindingIndex:
      let prev = fields[bindingIndex[field.binding]].binding
      let msg = fmt"duplicate binding encountered, see previous binding at {prev.loc}"
      return err(newParserError(msg, field.binding.loc))
    else:
      bindings.add(field.binding)
      bindingIndex[field.binding] = index

  ok(UnionPattern(variant: variant, fields: fields, bindings: bindings))

proc name*(vp: UnionPattern): Identifier = vp.variant
proc fields*(vp: UnionPattern): seq[UnionPatternField] = vp.fields
proc bindings*(vp: UnionPattern): seq[Identifier] = vp.bindings
proc loc*(vp: UnionPattern): Location = vp.name.loc

proc asl(vp: UnionPattern): string =
  result = fmt"{asl(vp.variant)} " & "{"
  for i, field in vp.fields:
    if i > 0: result.add(", ")
    result.add(asl(field))
  result.add(" }")

# Variant pattern: VariantName { field: binding, field: binding }
let unionPatternSpec* = Spec[UnionPattern](
  name: "variant_pattern",
  parseFn: proc(parser: Parser): Result[UnionPattern, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(unionPatternFieldSpec, commaWithSpacesSpec), "}"))
  newUnionPattern(name, fields)
)

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

proc bindings*(cp: CasePattern): seq[Identifier] =
  var bindings: seq[Identifier]
  case cp.kind:
  of cpkInteger: discard
  of cpkVariable: bindings.add(cp.variable)
  of cpkUnion: bindings.add(cp.variant.bindings)

  return bindings

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

let casePatternSpec* = oneOf("case_pattern", [
  integerLiteralSpec.map("integer_pattern",
    proc(v: IntegerLiteral): CasePattern = newCasePattern(v)),
  unionPatternSpec.map("variant_pattern",
    proc(v: UnionPattern): CasePattern = newCasePattern(v)),
  identifierSpec.map("variable_pattern",
    proc(v: Identifier): CasePattern = newCasePattern(v)),
])
