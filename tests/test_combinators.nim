## Tests for parser combinators (Spec[T] + oneOf / any / atLeastOne /
## optional / separatedBy / contained) and the Parser checkpoint
## machinery. Each combinator is exercised against a synthetic token
## stream produced via `tokenize`.

import unittest, options, results

import tokenizer
import parser
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
    let r = p.run(digitSpec())
    check r.isErr
    check p.index == 0

  test "run leaves index advanced on success":
    let p = mkParser("1a")
    let r = p.run(digitSpec())
    check r.isOk
    check p.index == 1

suite "combinators — oneOf":

  test "first matching alternative wins":
    let p = mkParser("9")
    let s = oneOf("d_or_a", [digitSpec(), alphaSpec()])
    let r = p.run(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "later alternative is tried after earlier ones fail":
    let p = mkParser("a")
    let s = oneOf("d_or_a", [digitSpec(), alphaSpec()])
    let r = p.run(s)
    check r.isOk
    check r.get.kind == tkAlphabet

  test "all alternatives failing yields the deepest error":
    let p = mkParser("!")
    let s = oneOf("d_or_a", [digitSpec(), alphaSpec()])
    let r = p.run(s)
    check r.isErr

suite "combinators — any / atLeastOne":

  test "any returns empty seq when zero matches":
    let p = mkParser("!")
    let r = p.run(any(digitSpec()))
    check r.isOk
    check r.get.len == 0
    check p.index == 0   # nothing consumed

  test "any consumes a maximal run":
    let p = mkParser("123a")
    let r = p.run(any(digitSpec()))
    check r.isOk
    check r.get.len == 3
    check p.index == 3

  test "atLeastOne fails on zero matches":
    let p = mkParser("a")
    let r = p.run(atLeastOne(digitSpec()))
    check r.isErr

  test "atLeastOne returns one or more":
    let p = mkParser("12")
    let r = p.run(atLeastOne(digitSpec()))
    check r.isOk
    check r.get.len == 2

suite "combinators — optional":

  test "optional present returns some":
    let p = mkParser("9")
    let r = p.run(optional(digitSpec()))
    check r.isOk
    check r.get.isSome

  test "optional absent returns none and does not advance":
    let p = mkParser("a")
    let r = p.run(optional(digitSpec()))
    check r.isOk
    check r.get.isNone
    check p.index == 0

suite "combinators — separatedBy":

  test "empty input yields empty list":
    let p = mkParser("")
    let r = p.run(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 0

  test "single element with no separator":
    let p = mkParser("9")
    let r = p.run(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 1

  test "multiple elements with separator":
    let p = mkParser("1 2 3")
    let r = p.run(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 3

  test "trailing separator without element fails (atomic pair backtracks)":
    # "1 " — second pair starts with space but has no digit after.
    # The any() inside separatedBy should backtrack and accept the
    # single element without consuming the trailing space.
    let p = mkParser("1 ")
    let r = p.run(separatedBy(digitSpec(), spaceSpec()))
    check r.isOk
    check r.get.len == 1

suite "combinators — contained":

  test "wraps an inner spec in delimiters":
    let p = mkParser("(9)")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.run(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "missing close delimiter is a fatal-ish error":
    let p = mkParser("(9")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.run(s)
    check r.isErr

  test "container tolerates whitespace around the inner spec":
    let p = mkParser("(  9  )")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.run(s)
    check r.isOk

suite "combinators — contained edges":

  test "missing open delimiter fails":
    let p = mkParser("9)")
    let s = contained("paren_digit", "(", digitSpec(), ")")
    let r = p.run(s)
    check r.isErr

suite "combinators — oneOf edges":

  test "single-alternative oneOf is degenerate but valid":
    let p = mkParser("9")
    let s = oneOf("only_digit", [digitSpec()])
    let r = p.run(s)
    check r.isOk
    check r.get.kind == tkDigit

  test "single-alternative oneOf failure surfaces the inner error":
    let p = mkParser("a")
    let s = oneOf("only_digit", [digitSpec()])
    let r = p.run(s)
    check r.isErr

suite "combinators — map":

  test "map transforms a parsed value":
    let p = mkParser("9")
    let s = digitSpec().map("digit_str", proc(t: Token): string = t.value)
    let r = p.run(s)
    check r.isOk
    check r.get == "9"

  test "map propagates the inner spec's error":
    let p = mkParser("a")
    let s = digitSpec().map("digit_str", proc(t: Token): string = t.value)
    let r = p.run(s)
    check r.isErr
