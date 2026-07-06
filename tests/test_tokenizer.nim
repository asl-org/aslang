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
    # Consecutive alphabet runes batch into ONE tkAlphabet token
    # (whole run in .value) + the trailing synthetic newline.
    check toks.len == 2
    check toks[0].kind == tkAlphabet
    check toks[0].value == "abc"
    check toks[1].kind == tkNewline

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

  test "consecutive digits batch into a single tkDigit token":
    let r = tokenizeStr("0123456789")
    check r.isOk
    let toks = r.get
    # One batched digit token + trailing synthetic newline.
    check toks.len == 2
    check toks[0].kind == tkDigit
    check toks[0].value == "0123456789"
    check toks[1].kind == tkNewline

  test "trailing newline is appended even when source ends with one":
    # Two literal newlines in source batch into a single tkNewline
    # token with value "\n\n"; the trailing synthetic newline is
    # appended as a separate token.
    let r = tokenizeStr("\n\n")
    check r.isOk
    let toks = r.get
    check toks.len == 2
    for t in toks:
      check t.kind == tkNewline
    check toks[0].value == "\n\n"
    check toks[1].value == "\n"

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

suite "tokenizer — invisible codepoints":

  test "every invisible codepoint is rejected":
    # Sweep every entry in InvisibleCodepoints to confirm none slips
    # through. Each is wrapped between two ASCII chars so the
    # tokenizer encounters a non-trivial location.
    let invisibles = [
      "­",                                    # SOFT HYPHEN
      "͏",                                    # COMBINING GRAPHEME JOINER
      "؜",                                    # ARABIC LETTER MARK
      "ᅟ",                                    # HANGUL CHOSEONG FILLER
      "ᅠ",                                    # HANGUL JUNGSEONG FILLER
      "឴",                                    # KHMER VOWEL INHERENT AQ
      "឵",                                    # KHMER VOWEL INHERENT AA
      "⁠",                                    # WORD JOINER
      "⁡", "⁢", "⁣", "⁤",      # INVISIBLE MATH OPS
      "⁪", "⁫", "⁬", "⁭",
      "⁮", "⁯",                          # DEPRECATED FORMATTING
    ]
    for c in invisibles:
      let r = tokenizeStr("a" & c & "b")
      check r.isErr
      check errorContains(r.error, "invisible")

suite "tokenizer — UTF-8 happy path":

  test "non-dangerous multi-byte UTF-8 produces tkUtf8 tokens":
    # 文 is U+6587, well outside any danger list. Should pass.
    let r = tokenizeStr("a文b")
    check r.isOk
    let toks = r.get
    check toks.len == 4   # a, 文, b, trailing \n
    check toks[0].kind == tkAlphabet
    check toks[1].kind == tkUtf8
    check toks[2].kind == tkAlphabet
    check toks[3].kind == tkNewline

  test "high-codepoint UTF-8 is accepted (BMP supplemental)":
    # Hiragana あ (U+3042) — clearly safe.
    let r = tokenizeStr("あ")
    check r.isOk
    check r.get[0].kind == tkUtf8

suite "tokenizer — locations across multiple lines":

  test "tokens on later lines have line >= the first":
    let r = tokenizeStr("a\nb\nc")
    check r.isOk
    let toks = r.get
    # tokens: a, \n, b, \n, c, trailing\n
    check toks.len == 6
    check toks[0].loc < toks[2].loc   # 'a' before 'b'
    check toks[2].loc < toks[4].loc   # 'b' before 'c'

  test "column resets after each newline":
    let r = tokenizeStr("xx\nx")
    check r.isOk
    let toks = r.get
    # The third 'x' (toks[3]) comes after a newline, so its location
    # must NOT compare lexicographically equal to the first 'x'.
    check not (toks[3].loc == toks[0].loc)

suite "tokenizer — error reporting":

  test "filepath is included in the error message":
    let r = tokenizeStr("a​b", "evil.asl")
    check r.isErr
    check errorContains(r.error, "evil.asl")

  test "TAB is rejected as unknown":
    let r = tokenizeStr("a\tb")
    check r.isErr
    check errorContains(r.error, "unknown token")

  test "carriage return is rejected as unknown":
    let r = tokenizeStr("a\rb")
    check r.isErr
    check errorContains(r.error, "unknown token")

  test "vertical tab is rejected as unknown":
    let r = tokenizeStr("a\x0Bb")
    check r.isErr
    check errorContains(r.error, "unknown token")

  test "form feed is rejected as unknown":
    let r = tokenizeStr("a\x0Cb")
    check r.isErr
    check errorContains(r.error, "unknown token")

  test "NUL byte is rejected as unknown":
    let r = tokenizeStr("a\x00b")
    check r.isErr
    check errorContains(r.error, "unknown token")
