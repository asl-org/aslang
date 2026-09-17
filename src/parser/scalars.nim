## Scalar literal leaves: the concrete string / integer / float literal
## AST nodes and their token specs. The `Literal` umbrella that unifies
## them (plus the numeric validation logic and the literal def /
## initializer) lives in literals.nim, which re-exports this module.

import results, strformat, strutils, options, strscans, parseutils, math

import parser

# True iff the syntactically-validated decimal float literal `text`
# is exactly representable as `mantissa * 2^k` for some non-negative
# integer mantissa with at most `mantissaBits` significant bits (i.e.
# `mantissa <= 2^mantissaBits`) and some integer `k`. The decision
# uses a rational-form decomposition: any literal denotes
# `M * 10^E = M * 2^E * 5^E`, so an exact binary representation
# requires that `5^E` either combine with M without overflow (E >= 0)
# or divide M cleanly (E < 0). Decimal fractions like `0.1` whose
# denominator has a 5-factor that does not cancel are rejected here.
# Used by `validate[T: SomeFloat]` to surface precision loss at the
# literal site rather than letting it slip silently into the stored value.
proc isExactlyRepresentable*(text: string, mantissaBits: int): bool =
  var s = text
  if s.len > 0 and (s[0] == '+' or s[0] == '-'):
    s = s[1..^1]

  var mantText, expText: string
  let eIdx = s.find({'e', 'E'})
  if eIdx >= 0:
    mantText = s[0..<eIdx]
    expText = s[eIdx+1..^1]
  else:
    mantText = s
    expText = "0"

  var intPart, fracPart: string
  let dotIdx = mantText.find('.')
  if dotIdx >= 0:
    intPart = mantText[0..<dotIdx]
    fracPart = mantText[dotIdx+1..^1]
  else:
    intPart = mantText
    fracPart = ""

  # Trailing zeros on the fractional part don't change the value;
  # stripping them keeps E small so `5^|E|` stays in BiggestUInt.
  while fracPart.len > 0 and fracPart[^1] == '0':
    fracPart = fracPart[0..^2]
  # Leading zeros on the integer part are also value-neutral.
  while intPart.len > 1 and intPart[0] == '0':
    intPart = intPart[1..^1]

  var combined = intPart & fracPart
  if combined.len == 0: combined = "0"
  while combined.len > 1 and combined[0] == '0':
    combined = combined[1..^1]

  var M: BiggestUInt
  try:
    M = parseBiggestUInt(combined)
  except ValueError:
    return false  # mantissa string too long for our scratch integer

  if M == 0: return true

  var E: int
  try:
    E = parseInt(expText) - fracPart.len
  except ValueError:
    return false

  let maxMantissa = 1'u64 shl mantissaBits

  if E >= 0:
    # value = M * 10^E. Multiply, watching for overflow.
    var v: BiggestUInt = M
    for _ in 0..<E:
      let next = v * 10
      if next div 10 != v: return false
      v = next
    # Strip factors of 2 — they're absorbed into the binary exponent.
    while (v and 1'u64) == 0 and v != 0:
      v = v shr 1
    return v <= maxMantissa
  else:
    # value = M / 10^|E|. 10^|E| = 2^|E| * 5^|E|. For exact binary
    # representation, 5^|E| must divide M.
    let k = -E
    var fiveK: BiggestUInt = 1
    for _ in 0..<k:
      let next = fiveK * 5
      if next div 5 != fiveK: return false
      fiveK = next
    if M mod fiveK != 0: return false
    var mant: BiggestUInt = M div fiveK
    while (mant and 1'u64) == 0 and mant != 0:
      mant = mant shr 1
    return mant <= maxMantissa

# Sibling of `parseInteger` — same `Option[T]` shape, dispatched at
# compile time on T. Only the "value cannot be reduced to a finite
# T at all" failure modes surface here as `none(T)`:
#
#   - out-of-range overflow that `parseutils.parseFloat` reports as
#     0-chars-consumed (literal text too large to fit in `float`);
#   - a finite input whose parsed value classifies as ±Inf or NaN
#     (i.e. overflow), rejected as out-of-range;
#   - float32 targets whose narrowed value overflows to ±Inf.
#
# Exact-representability (precision loss) is deliberately NOT
# checked here — `validate[T: SomeFloat]` (below) runs
# `isExactlyRepresentable` against the target type and emits a
# warning for lossy literals, so this proc returns the closest
# representable value in every finite case.
#
# Special IEEE-754 values (`nan`, `inf`, `+inf`, `-inf`) are recognized
# by name up front and returned as their float value: the tokenizer
# emits them as tkFloat tokens, and eager callers (`newFloatLiteral`)
# need a stored value for them too. Because the literal specials are
# handled here by name, the classify-based ±Inf/NaN rejection below
# applies ONLY to the finite path — where it still catches a numeric
# input that overflows to infinity or produces NaN, a genuine
# out-of-range error.
proc parseFloat*[T: SomeFloat](s: string): Option[T] =
  case s
  of "nan": return some(T(NaN))
  of "inf", "+inf": return some(T(Inf))
  of "-inf": return some(T(NegInf))
  else: discard
  var temp: float
  if parseutils.parseFloat(s, temp) == 0: return none(T)
  when T is float32:
    let narrowed = temp.float32
    if narrowed.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(narrowed)
  elif T is float64:
    if temp.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(temp)

proc genericIntScanner*[T: SomeInteger](input: string, res: var T, start: int): int =
  # 1. Compile-time branching based on whether T is signed or unsigned
  when T is SomeUnsignedInt:
    var temp: BiggestUInt
    let charsParsed = parseBiggestUInt(input, temp, start)

    # Check bounds against the exact target unsigned limits
    if charsParsed > 0 and temp <= high(T).BiggestUInt:
      res = T(temp)
      return charsParsed
  else:
    var temp: BiggestInt
    let charsParsed = parseBiggestInt(input, temp, start)

    # Check bounds against the exact target signed limits
    if charsParsed > 0 and temp >= low(T).BiggestInt and temp <= high(T).BiggestInt:
      res = T(temp)
      return charsParsed

  return 0 # Mismatch or out of bounds

# Clean generic wrapper function
proc parseInteger*[T: SomeInteger](s: string): Option[T] =
  var res: T
  if scanf(s, "${genericIntScanner}", res):
    return some(res)
  else:
    return none(T)

# ============================================================
# StringLiteral
# ============================================================

type StringLiteral* = ref object
  value: string
  loc: Location

proc newStringLiteral*(value: string, loc: Location): StringLiteral =
  StringLiteral(value: value, loc: loc)

proc newStringLiteral(token: Token): StringLiteral =
  newStringLiteral(token.value, token.loc)

proc loc*(strLit: StringLiteral): Location = strLit.loc
proc content*(strLit: StringLiteral): string = strLit.value[1..^2]
proc asl*(strLit: StringLiteral): string = "\"" & strLit.content & "\""

# The tokenizer scans a whole string literal into one `tkString` token
# whose value is the raw `"…"` slice (quotes + verbatim escapes);
# newStringLiteral keeps the raw value and strips the quotes on access.
let stringLiteralSpec* = newSpec[StringLiteral]("string", tkString, newStringLiteral)

# ============================================================
# Integer literals
# ============================================================

type UnsignedIntegerLiteral* = ref object
  value: string
  uintValue: uint64
  loc: Location

proc newUnsignedIntegerLiteral*(value: string, loc: Location): Result[UnsignedIntegerLiteral, ParserError] =
  let maybeInt = parseInteger[uint64](value)
  if maybeInt.isNone:
    err(newParserError(fmt"{loc} only 64-bit unsigned integers are supported but found `{value}`", loc, fatal = true))
  else:
    ok(UnsignedIntegerLiteral(value: value, uintValue: maybeInt.get, loc: loc))

proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

type SignedIntegerLiteral* = ref object
  value: string
  intValue: int64
  loc: Location

proc newSignedIntegerLiteral*(value: string, loc: Location): Result[SignedIntegerLiteral, ParserError] =
  let maybeInt = parseInteger[int64](value)
  if maybeInt.isNone:
    err(newParserError(fmt"{loc} only 64-bit signed integers are supported but found `{value}`", loc, fatal = true))
  else:
    ok(SignedIntegerLiteral(value: value, intValue: maybeInt.get, loc: loc))

proc asl*(signed: SignedIntegerLiteral): string = signed.value

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

proc newIntegerLiteral*(value: string, loc: Location): Result[IntegerLiteral, ParserError] =
  assert(value.len > 0, "[BUG] - {loc} integer literal can not be empty")
  if value[0] in {'+', '-'}:
    let signedInt = ? newSignedIntegerLiteral(value, loc)
    ok(newIntegerLiteral(signedInt))
  else:
    let unsignedInt = ? newUnsignedIntegerLiteral(value, loc)
    ok(newIntegerLiteral(unsignedInt))

proc newIntegerLiteral(token: Token): Result[IntegerLiteral, ParserError] =
  newIntegerLiteral(token.value, token.loc)

proc kind*(il: IntegerLiteral): IntegerLiteralKind = il.kind

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

proc value*(intLit: IntegerLiteral): string =
  ## Canonical decimal form of the parsed value. Signed (`int64`) and
  ## unsigned (`uint64`) literals share no numeric type, so the canonical
  ## decimal string is their common comparable form. Unlike `asl` (the
  ## verbatim spelling), leading zeros and a redundant `+` are normalized
  ## away, so numerically-equal literals compare equal.
  # NB: read the numeric fields (`intValue`/`uintValue`) directly — a dot
  # access to `.value` on a leaf resolves to its raw-string `value` field,
  # which would hand back the spelling again.
  case intLit.kind:
  of ilkSigned: $(intLit.signed.intValue)
  of ilkUnsigned: $(intLit.unsigned.uintValue)

proc validate*[T: SomeInteger](intLit: IntegerLiteral, expected: string): Result[void, string] =
  ## Range-checks the value parsed at construction against target type T's
  ## bounds — no re-scan of the spelling. Signed and unsigned literals are
  ## checked in the width they were stored in (int64 / uint64); an unsigned
  ## value is non-negative, so it only needs the upper bound.
  let fits =
    case intLit.kind:
    of ilkUnsigned:
      intLit.unsigned.uintValue <= high(T).uint64
    of ilkSigned:
      let v = intLit.signed.intValue
      when T is SomeUnsignedInt: v >= 0 and v.uint64 <= high(T).uint64
      else: v >= low(T).int64 and v <= high(T).int64
  if fits: ok()
  else: err(fmt"{intLit.loc} expected a valid {expected} but found `{intLit.asl}`")

# The tokenizer scans `(+|-)?digit+` into one tkInteger token;
# newIntegerLiteral splits its optional leading sign into signed/unsigned.
let integerLiteralSpec* = newSpec[IntegerLiteral]("integer", tkInteger, newIntegerLiteral)

# ============================================================
# FloatLiteral
# ============================================================

type FloatLiteral* = ref object
  value: string
  floatValue: float64
  loc: Location

proc newFloatLiteral*(value: string, loc: Location): Result[FloatLiteral, ParserError] =
  let maybeParsedFloat = parseFloat[float64](value)
  if maybeParsedFloat.isNone:
    err(newParserError(fmt"{loc} only IEEE 64-bit floats are supported but found `{value}`", loc, fatal = true))
  else:
    ok(FloatLiteral(value: value, floatValue: maybeParsedFloat.get, loc: loc))

proc newFloatLiteral(token: Token): Result[FloatLiteral, ParserError] =
  newFloatLiteral(token.value, token.loc)

proc loc*(floatLit: FloatLiteral): Location = floatLit.loc
proc value*(floatLit: FloatLiteral): float64 = floatLit.floatValue
proc asl*(floatLit: FloatLiteral): string = floatLit.value

proc validate*[T: SomeFloat](literal: FloatLiteral, expected: string): Result[void, string] =
  ## Narrows the float64 parsed at construction to target type T instead of
  ## re-scanning the spelling. A literal that was ALREADY non-finite
  ## (`nan`/`inf`) is representable in any width and passes straight through;
  ## a finite value that overflows T's range narrows to ±Inf, which classify
  ## then catches — the value's own classification distinguishes the two.
  # NB: read floatValue, not `.value` — inside this module a dot access
  # resolves to the raw-string `value` field, not the float accessor.
  let stored = literal.floatValue
  if stored.classify in {fcInf, fcNegInf, fcNan}:
    ok()
  elif T(stored).classify in {fcInf, fcNegInf, fcNan}:
    err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")
  else:
    # Exact-representability is a warning, not an error: the closest
    # approximation stored in the parsed value is still used. Emit to
    # stderr with the source location so users can find and (if they
    # choose) rewrite lossy literals as runtime quotients of exact-integer
    # literals.
    # TODO(diagnostics): thread warnings up as a collected seq rather than
    # writing to stderr from deep inside the pass.
    const mantissaBits =
      when T is float32: 24
      elif T is float64: 53
    if not isExactlyRepresentable(literal.asl, mantissaBits):
      stderr.writeLine(fmt"[WARN] {literal.loc} literal `{literal.asl}` cannot be exactly represented in {expected}; using closest approximation")
    ok()

# Every float form is a single tkFloat token: the tokenizer scans the
# numeric form `(+|-)?digit+(.digit+)?((e|E)(+|-)?digit+)?` and the special
# IEEE-754 values `nan` / `inf` / `+inf` / `-inf` (the sign folds into the
# token so downstream `analyzeFloatLiteral` can tell `+inf` from `-inf`).
# So one consumer covers them all — no per-form alternation.
let floatLiteralSpec* = newSpec("float", tkFloat, newFloatLiteral)
