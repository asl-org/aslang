## Tests for parser combinators (Spec[T] + oneOf / any / atLeastOne /
## optional / separatedBy / contained) and the Parser checkpoint
## machinery. Each combinator is exercised against a synthetic token
## stream produced via `tokenize`.

import unittest, options, results

import analyzer/defanalyzer/resolver/parser/tokenizer
import analyzer
import tutils

# A few tiny leaf specs we can compose into bigger tests without
# leaning on the full grammar.
proc digitSpec(): Spec[Token] = tokenSpec(tkDigit, "digit")
proc alphaSpec(): Spec[Token] = tokenSpec(tkAlphabet, "alphabet")
proc spaceSpec(): Spec[Token] = tokenSpec(tkSpace, "space ' '")

proc mkParser(source: string): Parser =
  let r = tokenizeStr(source, "synth.asl")
  doAssert r.isOk, "tokenize failed in test setup: " & r.error
  newParser("synth.asl", 2'u32, r.get)

suite "combinators — checkpoint / restore on failure":

  test "run rolls back parser.index when spec fails non-fatally":
    let p = mkParser("ab")
    # Try to consume a digit (will fail). Index must not advance.
    let r = p.expect(digitSpec())
    check r.isErr
    check p.index == 0

  test "run leaves index advanced on success":
    let p = mkParser("1a")
    let r = p.expect(digitSpec())
    check r.isOk
    check p.index == 1

suite "combinators — oneOf":

  test "first matching alternative wins":
    let p = mkParser("9")
    let s = oneOf(@[digitSpec(), alphaSpec()])
    let r = p.expect(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "later alternative is tried after earlier ones fail":
    let p = mkParser("a")
    let s = oneOf(@[digitSpec(), alphaSpec()])
    let r = p.expect(s)
    check r.isOk
    check r.get.kind == tkAlphabet

  test "all alternatives failing yields the deepest error":
    let p = mkParser("!")
    let s = oneOf(@[digitSpec(), alphaSpec()])
    let r = p.expect(s)
    check r.isErr

suite "combinators — any / atLeastOne":

  test "any returns empty seq when zero matches":
    let p = mkParser("!")
    let r = p.expect(any(digitSpec()))
    check r.isOk
    check r.get.len == 0
    check p.index == 0   # nothing consumed

  test "any consumes a maximal run":
    # The tokenizer batches a consecutive digit run into ONE tkDigit
    # token whose value carries the whole run. `any(digitSpec)` on
    # "123a" therefore returns a single token — but its .value is
    # the full "123" run, which is what "maximal" means at the
    # tokenizer layer.
    let p = mkParser("123a")
    let r = p.expect(any(digitSpec()))
    check r.isOk
    check r.get.len == 1
    check r.get[0].value == "123"
    check p.index == 1

  test "atLeastOne fails on zero matches":
    let p = mkParser("a")
    let r = p.expect(atLeastOne(digitSpec()))
    check r.isErr

  test "atLeastOne returns one or more":
    # Same batching note as above — "12" is one tkDigit token whose
    # value is "12", so atLeastOne succeeds with a single-token seq.
    let p = mkParser("12")
    let r = p.expect(atLeastOne(digitSpec()))
    check r.isOk
    check r.get.len == 1
    check r.get[0].value == "12"

  test "any consumes multiple tokens when the tokenizer emits multiple":
    # Punctuation is NOT batched — each punctuation rune is its own
    # token. Use commas to exercise `any` consuming multiple tokens.
    let p = mkParser(",,,a")
    let r = p.expect(any(punctuationSpec(",")))
    check r.isOk
    check r.get.len == 3
    check p.index == 3

suite "combinators — optional":

  test "optional present returns some":
    let p = mkParser("9")
    let r = p.expect(optional(digitSpec()))
    check r.isOk
    check r.get.isSome

  test "optional absent returns none and does not advance":
    let p = mkParser("a")
    let r = p.expect(optional(digitSpec()))
    check r.isOk
    check r.get.isNone
    check p.index == 0

suite "combinators — separatedBy":

  test "empty input yields empty list":
    let p = mkParser("")
    let r = p.expect(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 0

  test "single element with no separator":
    let p = mkParser("9")
    let r = p.expect(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 1

  test "multiple elements with separator":
    let p = mkParser("1 2 3")
    let r = p.expect(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 3

  test "trailing separator without element fails (atomic pair backtracks)":
    # "1 " — second pair starts with space but has no digit after.
    # The any() inside separatedBy should backtrack and accept the
    # single element without consuming the trailing space.
    let p = mkParser("1 ")
    let r = p.expect(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 1

suite "combinators — contained":

  test "wraps an inner spec in delimiters":
    let p = mkParser("(9)")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.expect(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "missing close delimiter is a fatal-ish error":
    let p = mkParser("(9")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.expect(s)
    check r.isErr

  test "container tolerates whitespace around the inner spec":
    let p = mkParser("(  9  )")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.expect(s)
    check r.isOk

suite "combinators — contained edges":

  test "missing open delimiter fails":
    let p = mkParser("9)")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.expect(s)
    check r.isErr

suite "combinators — oneOf edges":

  test "single-alternative oneOf is degenerate but valid":
    let p = mkParser("9")
    let s = oneOf(@[digitSpec()])
    let r = p.expect(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "single-alternative oneOf failure surfaces the inner error":
    let p = mkParser("a")
    let s = oneOf(@[digitSpec()])
    let r = p.expect(s)
    check r.isErr

suite "combinators — pair":

  test "pair returns both values as a tuple":
    let p = mkParser("5a")
    let s = pair(digitSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isOk
    check r.get[0].kind == tkDigit
    check r.get[1].kind == tkAlphabet

  test "pair rolls back index when the second spec fails":
    let p = mkParser("55")
    let s = pair(digitSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isErr
    check p.index == 0

suite "combinators — triple":

  test "triple returns all three values":
    let p = mkParser("5 a")
    let s = triple(digitSpec(), spaceSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isOk
    check r.get[0].kind == tkDigit
    check r.get[1].kind == tkSpace
    check r.get[2].kind == tkAlphabet

  test "triple rolls back when the last spec fails":
    let p = mkParser("5 5")
    let s = triple(digitSpec(), spaceSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isErr
    check p.index == 0

suite "combinators — separated":

  test "separated returns left and right, discarding the separator":
    let p = mkParser("5 a")
    let s = separated(digitSpec(), spaceSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isOk
    check r.get[0].kind == tkDigit
    check r.get[1].kind == tkAlphabet

  test "separated fails when the separator is missing":
    let p = mkParser("5a")
    let s = separated(digitSpec(), spaceSpec(), alphaSpec())
    let r = p.expect(s)
    check r.isErr
    check p.index == 0

  test "separated composes with punctuation as the separator":
    # Explicit-tight separator: `.` between two alpha tokens.
    let p = mkParser("a.b")
    let s = separated(alphaSpec(), punctuationSpec("."), alphaSpec())
    let r = p.expect(s)
    check r.isOk
    check r.get[0].value == "a"
    check r.get[1].value == "b"

