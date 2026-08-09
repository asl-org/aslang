import results, strformat, strutils

import ./tokenizer
import ./identifiers
import ./argtype

# ============================================================
# StringContent (internal — one character of a string literal)
# ============================================================

type StringContent* = ref object
  content: string
  loc: Location

proc newStringContent*(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

proc content*(sc: StringContent): string = sc.content

# ============================================================
# StringLiteral
# ============================================================

type StringLiteral* = ref object
  content: string
  loc: Location

proc newStringLiteral*(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc loc*(strLit: StringLiteral): Location = strLit.loc
proc value*(strLit: StringLiteral): string = strLit.content
proc asl*(strLit: StringLiteral): string = fmt"""{strLit.content}"""

# ============================================================
# Integer literals
# ============================================================

type UnsignedIntegerLiteral* = ref object
  value: string
  loc: Location

proc newUnsignedIntegerLiteral*(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

type SignedIntegerLiteral* = ref object
  sign: string
  value: UnsignedIntegerLiteral
  loc: Location

proc newSignedIntegerLiteral*(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)


proc asl*(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

type
  IntegerLiteralKind* = enum
    ilkSigned, ilkUnsigned
  IntegerLiteral* = ref object
    case kind: IntegerLiteralKind
    of ilkSigned: signed: SignedIntegerLiteral
    of ilkUnsigned: unsigned: UnsignedIntegerLiteral

proc newIntegerLiteral*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkSigned, signed: signed)

proc newIntegerLiteral*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkUnsigned, unsigned: unsigned)


proc signed*(il: IntegerLiteral): SignedIntegerLiteral =
  assert il.kind == ilkSigned,
    fmt"IntegerLiteral.signed accessed but kind is {il.kind}"
  il.signed

proc unsigned*(il: IntegerLiteral): UnsignedIntegerLiteral =
  assert il.kind == ilkUnsigned,
    fmt"IntegerLiteral.unsigned accessed but kind is {il.kind}"
  il.unsigned

proc loc*(intLit: IntegerLiteral): Location =
  case intLit.kind:
  of ilkSigned: intLit.signed.loc
  of ilkUnsigned: intLit.unsigned.loc

proc asl*(intLit: IntegerLiteral): string =
  case intLit.kind:
  of ilkSigned: asl(intLit.signed)
  of ilkUnsigned: asl(intLit.unsigned)

# ============================================================
# FloatLiteral
# ============================================================

type FloatLiteral* = ref object
  value: string
  loc: Location

proc newFloatLiteral*(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc asl*(floatLit: FloatLiteral): string = floatLit.value

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
      of lkString: "String"
  let maybeId = newIdentifier(module, literal.loc)
  assert(maybeId.isOk, fmt"BUG: default literal type name `{module}` should always be a valid identifier")
  return maybeId.get


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
