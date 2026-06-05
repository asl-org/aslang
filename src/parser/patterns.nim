import strformat, tables, results

import tokenizer
import combinators
import helpers
import identifiers
import numbers

# ============================================================
# VariantPatternField
# ============================================================

type VariantPatternField* = ref object
  name: Identifier
  binding: Identifier
  loc: Location

proc newVariantPatternField*(name: Identifier, binding: Identifier,
    loc: Location): VariantPatternField =
  VariantPatternField(name: name, binding: binding, loc: loc)

proc name*(field: VariantPatternField): Identifier = field.name
proc binding*(field: VariantPatternField): Identifier = field.binding
proc loc*(field: VariantPatternField): Location = field.loc

proc asl(field: VariantPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

# Variant pattern field: name ":" binding (both identifiers)
let variantPatternFieldSpec* = Spec[VariantPatternField](
  name: "variant_pattern_field",
  parseFn: proc(parser: Parser): Result[VariantPatternField, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let binding = ? parser.run(identifierSpec)
  ok(newVariantPatternField(name, binding, name.loc))
)

# ============================================================
# VariantPattern
# ============================================================

type VariantPattern* = ref object
  variant: Identifier
  fields: seq[VariantPatternField]
  bindings: seq[Identifier]
  loc: Location

proc newVariantPattern*(variant: Identifier, fields: seq[VariantPatternField]): Result[VariantPattern, ParserError] =
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

  ok(VariantPattern(variant: variant, fields: fields, bindings: bindings))

proc name*(vp: VariantPattern): Identifier = vp.variant
proc fields*(vp: VariantPattern): seq[VariantPatternField] = vp.fields
proc bindings*(vp: VariantPattern): seq[Identifier] = vp.bindings
proc loc*(vp: VariantPattern): Location = vp.name.loc

proc asl(vp: VariantPattern): string =
  result = fmt"{asl(vp.variant)} " & "{"
  for i, field in vp.fields:
    if i > 0: result.add(", ")
    result.add(asl(field))
  result.add(" }")

# Variant pattern: VariantName { field: binding, field: binding }
let variantPatternSpec* = Spec[VariantPattern](
  name: "variant_pattern",
  parseFn: proc(parser: Parser): Result[VariantPattern, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(variantPatternFieldSpec, commaWithSpacesSpec), "}"))
  newVariantPattern(name, fields)
)

# ============================================================
# CasePattern
# ============================================================

type
  CasePatternKind* = enum
    cpkIntegerLiteral, cpkVariable, cpkVariant
  CasePattern* = ref object
    case kind: CasePatternKind
    of cpkIntegerLiteral: intLit: IntegerLiteral
    of cpkVariable: variable: Identifier
    of cpkVariant: variant: VariantPattern

proc newCasePattern*(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkIntegerLiteral, intLit: intLit)

proc newCasePattern*(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newCasePattern*(variant: VariantPattern): CasePattern =
  CasePattern(kind: cpkVariant, variant: variant)

proc kind*(cp: CasePattern): CasePatternKind = cp.kind
proc loc*(cp: CasePattern): Location =
  case cp.kind:
  of cpkIntegerLiteral: cp.intLit.loc
  of cpkVariable: cp.variable.loc
  of cpkVariant: cp.variant.loc

proc bindings*(cp: CasePattern): seq[Identifier] =
  var bindings: seq[Identifier]
  case cp.kind:
  of cpkIntegerLiteral: discard
  of cpkVariable: bindings.add(cp.variable)
  of cpkVariant: bindings.add(cp.variant.bindings)

  return bindings

proc intLit*(cp: CasePattern): IntegerLiteral =
  assert cp.kind == cpkIntegerLiteral,
    fmt"CasePattern.intLit accessed but kind is {cp.kind}"
  cp.intLit

proc variable*(cp: CasePattern): Identifier =
  assert cp.kind == cpkVariable,
    fmt"CasePattern.variable accessed but kind is {cp.kind}"
  cp.variable

proc variant*(cp: CasePattern): VariantPattern =
  assert cp.kind == cpkVariant,
    fmt"CasePattern.variant accessed but kind is {cp.kind}"
  cp.variant

proc asl*(pattern: CasePattern): string =
  case pattern.kind:
  of cpkIntegerLiteral: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkVariant: asl(pattern.variant)

let casePatternSpec* = oneOf("case_pattern", [
  integerLiteralSpec.map("integer_pattern",
    proc(v: IntegerLiteral): CasePattern = newCasePattern(v)),
  variantPatternSpec.map("variant_pattern",
    proc(v: VariantPattern): CasePattern = newCasePattern(v)),
  identifierSpec.map("variable_pattern",
    proc(v: Identifier): CasePattern = newCasePattern(v)),
])
