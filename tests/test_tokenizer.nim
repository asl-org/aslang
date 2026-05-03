## Tokenizer unit tests.
##
## The tokenizer is a per-rune classifier; tests cover token kinds,
## location tracking, security validation (UTF-8 + Trojan-Source
## defense), and the trailing-newline normalization invariant.

import unittest, results

import tokenizer
import tutils

suite "tokenizer — happy paths":

  test "empty source still gets a trailing newline":
    let r = tokenizeStr("")
    check r.isOk
    let toks = r.get
    check toks.len == 1
    check toks[0].kind == tkNewline

  test "single ASCII identifier":
    let r = tokenizeStr("abc")
    check r.isOk
    let toks = r.get
    # 3 alphabet tokens + trailing newline
    check toks.len == 4
    for i in 0..2:
      check toks[i].kind == tkAlphabet
    check toks[^1].kind == tkNewline
    check toks[0].value == "a"
    check toks[1].value == "b"
    check toks[2].value == "c"

  test "every TokenKind appears in mixed input":
    let r = tokenizeStr("a 1\n!é")
    check r.isOk
    let toks = r.get
    # a, space, 1, newline, !, é (utf8), trailing newline
    check toks.len == 7
    check toks[0].kind == tkAlphabet
    check toks[1].kind == tkSpace
    check toks[2].kind == tkDigit
    check toks[3].kind == tkNewline
    check toks[4].kind == tkPunctuation
    check toks[5].kind == tkUtf8
    check toks[6].kind == tkNewline

  test "all defined punctuation characters are accepted":
    const all = "`~!@#$%^&*()-_=+[]{}\\|;:'\",<.>/?"
    let r = tokenizeStr(all)
    check r.isOk
    let toks = r.get
    # every char + trailing newline
    check toks.len == all.len + 1
    for i in 0..<all.len:
      check toks[i].kind == tkPunctuation

  test "digits 0..9 each tokenize as tkDigit":
    let r = tokenizeStr("0123456789")
    check r.isOk
    let toks = r.get
    check toks.len == 11
    for i in 0..9:
      check toks[i].kind == tkDigit
      check toks[i].value == $i

  test "trailing newline is appended even when source ends with one":
    # Two literal newlines in source -> three tkNewline tokens
    # (two from the source, one synthetic).
    let r = tokenizeStr("\n\n")
    check r.isOk
    let toks = r.get
    check toks.len == 3
    for t in toks:
      check t.kind == tkNewline

suite "tokenizer — locations":

  test "column advances on each rune in a line":
    let r = tokenizeStr("ab")
    check r.isOk
    let toks = r.get
    # Just confirm the locations are distinct and ordered.
    check toks[0].loc < toks[1].loc

  test "newline resets column on the next token":
    let r = tokenizeStr("a\nb")
    check r.isOk
    let toks = r.get
    # tokens: a, \n, b, trailing\n
    check toks.len == 4
    # 'a' on line 1, 'b' on line 2 -> 'a' < 'b' lex order
    check toks[0].loc < toks[2].loc
    # 'b' is on a new line: cannot share location with 'a'
    check not (toks[2].loc == toks[0].loc)

suite "tokenizer — Trojan Source defense":

  test "BOM (U+FEFF) is rejected as zero-width":
    let r = tokenizeStr("﻿x")
    check r.isErr
    check errorContains(r.error, "zero-width")

  test "zero-width space U+200B is rejected":
    let r = tokenizeStr("a​b")
    check r.isErr
    check errorContains(r.error, "zero-width")

  test "right-to-left override U+202E is rejected":
    let r = tokenizeStr("‮text")
    check r.isErr
    check errorContains(r.error, "bidirectional")

  test "soft hyphen U+00AD is rejected as invisible":
    let r = tokenizeStr("a­b")
    check r.isErr
    check errorContains(r.error, "invisible")

  test "every bidi codepoint is rejected":
    let bidis = ["‎", "‏", "‪", "‫", "‬",
                 "‭", "‮", "⁦", "⁧", "⁨",
                 "⁩"]
    for c in bidis:
      let r = tokenizeStr("a" & c & "b")
      check r.isErr
      check errorContains(r.error, "bidirectional")

  test "every zero-width codepoint is rejected":
    let zws = ["​", "‌", "‍", "﻿"]
    for c in zws:
      let r = tokenizeStr("a" & c & "b")
      check r.isErr
      check errorContains(r.error, "zero-width")

suite "tokenizer — error reporting":

  test "filepath is included in the error message":
    let r = tokenizeStr("a​b", "evil.asl")
    check r.isErr
    check errorContains(r.error, "evil.asl")

  test "control characters in the ASCII range are rejected as unknown":
    # Tab is not in the punctuation set and not whitespace handled
    # by the tokenizer -> falls into the `unknown token` else branch.
    let r = tokenizeStr("a\tb")
    check r.isErr
    check errorContains(r.error, "unknown token")
