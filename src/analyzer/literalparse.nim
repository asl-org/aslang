## Bounds-checked integer + float literal parsers shared by
## `analyzer.nim`'s literal analysis and `AnalyzedLiteralPatternScope`'s
## per-kind duplicate check.
##
## Both parsers return `Option[T]` and use compile-time dispatch on T
## to pick the right underlying parse — `SomeUnsignedInt` uses
## `parseBiggestUInt`, `SomeSignedInt` uses `parseBiggestInt`, floats
## dispatch through `parseutils.parseFloat` + a narrow/classify step.
##
## `isExactlyRepresentable` is the warning helper for float literals:
## a rational-form decomposition tells us whether the literal denotes
## an exact `mantissa * 2^k` value, which lets the analyzer surface a
## warning (not an error) at the literal site for lossy decimals.

import options, strscans, parseutils, strutils, math

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

# True iff the syntactically-validated decimal float literal `text`
# is exactly representable as `mantissa * 2^k` for some non-negative
# integer mantissa with at most `mantissaBits` significant bits (i.e.
# `mantissa <= 2^mantissaBits`) and some integer `k`. The decision
# uses a rational-form decomposition: any literal denotes
# `M * 10^E = M * 2^E * 5^E`, so an exact binary representation
# requires that `5^E` either combine with M without overflow (E >= 0)
# or divide M cleanly (E < 0). Decimal fractions like `0.1` whose
# denominator has a 5-factor that does not cancel are rejected here.
# Used by `parseFloat[T]` to surface precision loss at the literal
# site rather than letting it slip silently into the analyzer's
# stored value.
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
#   - the parsed value classifies as ±Inf or NaN — currently always
#     rejected (see TODO below);
#   - float32 targets whose narrowed value overflows to ±Inf.
#
# Exact-representability (precision loss) is deliberately NOT
# checked here — the caller (`analyzeFloatLiteral` in analyzer.nim)
# runs `isExactlyRepresentable` after a successful parse and emits
# a warning for lossy literals, so this proc returns the closest
# representable value in every finite case.
#
# Numeric float parse only. Special IEEE-754 values (`nan`, `inf`,
# `+inf`, `-inf`) are handled upstream: the parser accepts them via
# `specialFloatSpec` in `parser/literals.nim`, and the analyzer's
# `analyzeFloatLiteral` short-circuits them before reaching this proc.
# So the inf/nan rejection here catches ONLY the case a numeric input
# overflows to infinity or produces NaN — which is a genuine
# out-of-range error and stays rejected.
proc parseFloat*[T: SomeFloat](s: string): Option[T] =
  var temp: float
  if parseutils.parseFloat(s, temp) == 0: return none(T)
  when T is float32:
    let narrowed = temp.float32
    if narrowed.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(narrowed)
  elif T is float64:
    if temp.classify in {fcInf, fcNegInf, fcNan}: return none(T)
    some(temp)
