import results, strformat, strutils, options

import parser

import identifiers
import argtype

# The scalar literal leaves (string / integer / float AST nodes + their
# specs) were extracted to scalars.nim; re-exported so `import literals`
# still surfaces StringLiteral / IntegerLiteral / FloatLiteral and their
# constructors.
import scalars

# ============================================================
# Literal (umbrella over string / integer / float)
# ============================================================

type
  LiteralKind* = enum
    lkString, lkInteger, lkFloat
  Literal* = ref object
    case kind: LiteralKind
    of lkString: strLit: StringLiteral
    of lkInteger: intLit: IntegerLiteral
    of lkFloat: floatLit: FloatLiteral

proc newLiteral*(strLit: StringLiteral): Literal =
  Literal(kind: lkString, strLit: strLit)

proc newLiteral*(intLit: IntegerLiteral): Literal =
  Literal(kind: lkInteger, intLit: intLit)

proc newLiteral*(floatLit: FloatLiteral): Literal =
  Literal(kind: lkFloat, floatLit: floatLit)

proc kind*(l: Literal): LiteralKind = l.kind

proc strLit*(l: Literal): StringLiteral =
  assert l.kind == lkString,
    fmt"Literal.strLit accessed but kind is {l.kind}"
  l.strLit

proc intLit*(l: Literal): IntegerLiteral =
  assert l.kind == lkInteger,
    fmt"Literal.intLit accessed but kind is {l.kind}"
  l.intLit

proc floatLit*(l: Literal): FloatLiteral =
  assert l.kind == lkFloat,
    fmt"Literal.floatLit accessed but kind is {l.kind}"
  l.floatLit

proc loc*(literal: Literal): Location =
  case literal.kind:
  of lkString: literal.strLit.loc
  of lkInteger: literal.intLit.loc
  of lkFloat: literal.floatLit.loc

proc asl*(literal: Literal): string =
  case literal.kind:
  of lkString: asl(literal.strLit)
  of lkInteger: asl(literal.intLit)
  of lkFloat: asl(literal.floatLit)

proc defaultType*(literal: Literal): Identifier =
  let module =
    case literal.kind:
      of lkInteger: "i32"
      of lkFloat: "f32"
      of lkString: "string"
  let maybeId = newIdentifier(module, literal.loc)
  assert(maybeId.isOk, fmt"BUG: default literal type name `{module}` should always be a valid identifier")
  return maybeId.get

let literalSpec* = oneOf("literal", @[
  map(stringLiteralSpec, newLiteral),
  map(floatLiteralSpec, newLiteral),
  map(integerLiteralSpec, newLiteral),
])

proc validateString*(literal: Literal): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid string literal but found float")
  of lkInteger: err(fmt"{literal.loc} expected a valid string literal but found integer")
  of lkString: ok()

proc validateInteger*[T: SomeInteger](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid {expected} but found float")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkInteger: validate[T](literal.intLit, expected)

proc validateFloat*[T: SomeFloat](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkInteger: err(fmt"{literal.loc} expected a valid {expected} but found integer")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkFloat: validate[T](literal.floatLit, expected)

# ============================================================
# LiteralDef (data block: `literal: "..."`)
# ============================================================

type LiteralDef* = ref object
  value: StringLiteral
  loc: Location

proc newLiteralDef*(value: StringLiteral, loc: Location): LiteralDef =
  LiteralDef(value: value, loc: loc)

proc content*(literalType: LiteralDef): string = literalType.value.content
proc loc*(literalType: LiteralDef): Location = literalType.loc

proc asl*(l: LiteralDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  @[fmt"{indent}literal: {asl(l.value)}"]

proc literalDefConsumer(parser: Parser): Result[LiteralDef, ParserError] =
  discard ? parser.expect(indentationSpec)
  let literalKeyword = ? parser.expect("literal")
  discard ? parser.expect(SPACE.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(SPACE.optional())
  let strLit = ? parser.expect(stringLiteralSpec)
  ok(newLiteralDef(strLit, literalKeyword.loc))

let literalDefSpec* = newSpec[LiteralDef]("literal def", literalDefConsumer)

# ============================================================
# LiteralInitializer
# ============================================================

type LiteralInitializer* = ref object
  argType: ArgumentType
  value: Literal

proc newLiteralInitializer*(argType: ArgumentType, value: Literal): LiteralInitializer =
  LiteralInitializer(argType: argType, value: value)

proc loc*(init: LiteralInitializer): Location = init.argType.loc
proc module*(init: LiteralInitializer): Identifier = init.argType.root
proc argType*(init: LiteralInitializer): ArgumentType = init.argType
proc value*(init: LiteralInitializer): Literal = init.value

proc asl*(init: LiteralInitializer): string =
  fmt"{init.argType.asl} {init.value.asl}"

proc literalInitializerConsumer(parser: Parser): Result[LiteralInitializer, ParserError] =
  let argType = ? parser.expect(argumentTypeSpec)
  discard ? parser.expect(SPACE)
  let lit = ? parser.expect(literalSpec)
  ok(newLiteralInitializer(argType, lit))

let literalInitSpec* = newSpec[LiteralInitializer]("literal initializer", literalInitializerConsumer)
