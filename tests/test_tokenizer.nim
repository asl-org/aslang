## Tokenizer unit tests.
##
## The tokenizer is a per-rune classifier; tests cover token kinds,
## location tracking, security validation (UTF-8 + Trojan-Source
## defense), and the trailing-newline normalization invariant.

import unittest, results, strutils

import analyzer/defanalyzer/resolver/parser/tokenizer
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
    check toks[2].kind == tkInteger
    check toks[3].kind == tkNewline
    check toks[4].kind == tkPunctuation
    check toks[5].kind == tkUtf8
    check toks[6].kind == tkNewline

  test "all defined punctuation characters are accepted":
    # `"` and `#` are omitted: they open a string literal and a comment
    # respectively, so neither is a standalone punctuation token.
    const all = "`~!@$%^&*()-_=+[]{}\\|;:',<.>/?"
    let r = tokenizeStr(all)
    check r.isOk
    let toks = r.get
    # every char + trailing newline
    check toks.len == all.len + 1
    for i in 0..<all.len:
      check toks[i].kind == tkPunctuation

  test "consecutive digits batch into a single tkInteger token":
    let r = tokenizeStr("0123456789")
    check r.isOk
    let toks = r.get
    # One batched digit token + trailing synthetic newline.
    check toks.len == 2
    check toks[0].kind == tkInteger
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

  test "consecutive spaces batch into a single tkSpace token":
    # Four spaces should produce ONE tkSpace token whose `.value.len`
    # counts the runs. Both tkSpace and tkNewline are declared as
    # collective specs (see `newCollectiveTokenSpec` in
    # `parser/tokenizer.nim`), so the batching invariant is symmetric
    # with the alphabet/digit rule tested above.
    let r = tokenizeStr("    ")
    check r.isOk
    let toks = r.get
    # One batched space token + the trailing synthetic newline.
    check toks.len == 2
    check toks[0].kind == tkSpace
    check toks[0].value == "    "
    check toks[0].value.len == 4
    check toks[1].kind == tkNewline

  test "space count is recoverable from token.value.len":
    # Verifies the explicit "value.len == number of spaces" contract
    # that indentationSpec relies on for level checks.
    for n in [1, 2, 3, 7, 16]:
      let source = ' '.repeat(n)
      let r = tokenizeStr(source)
      check r.isOk
      let toks = r.get
      check toks[0].kind == tkSpace
      check toks[0].value.len == n

  test "newline count is recoverable from token.value.len":
    # Same contract on the newline side — blank-line grammar rules
    # count how many `\n` runes a tkNewline token carries.
    for n in [1, 2, 3, 5]:
      let source = '\n'.repeat(n)
      let r = tokenizeStr(source)
      check r.isOk
      let toks = r.get
      # First token = batched literal newlines; last = trailing synthetic.
      check toks[0].kind == tkNewline
      check toks[0].value.len == n

  test "space and newline runs stay in separate tokens":
    # A space run followed by a newline run must NOT merge into a
    # single collective token — batching is per-kind. `"  \n\n"`
    # yields tkSpace("  ") then tkNewline("\n\n") then the synthetic.
    let r = tokenizeStr("  \n\n")
    check r.isOk
    let toks = r.get
    check toks.len == 3
    check toks[0].kind == tkSpace
    check toks[0].value == "  "
    check toks[1].kind == tkNewline
    check toks[1].value == "\n\n"
    check toks[2].kind == tkNewline   # synthetic trailing
    check toks[2].value == "\n"

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

  test "TAB is rejected as unsupported":
    let r = tokenizeStr("a\tb")
    check r.isErr
    check errorContains(r.error, "unsupported token")

  test "carriage return is rejected as unsupported":
    let r = tokenizeStr("a\rb")
    check r.isErr
    check errorContains(r.error, "unsupported token")

  test "vertical tab is rejected as unsupported":
    let r = tokenizeStr("a\x0Bb")
    check r.isErr
    check errorContains(r.error, "unsupported token")

  test "form feed is rejected as unsupported":
    let r = tokenizeStr("a\x0Cb")
    check r.isErr
    check errorContains(r.error, "unsupported token")

  test "NUL byte is rejected as unsupported":
    let r = tokenizeStr("a\x00b")
    check r.isErr
    check errorContains(r.error, "unsupported token")

suite "tokenizer — strings":

  test "a string literal is one tkString token carrying the raw quoted slice":
    let r = tokenizeStr("\"hello\"")
    check r.isOk
    let toks = r.get
    check toks.len == 2   # the string + trailing newline
    check toks[0].kind == tkString
    check toks[0].value == "\"hello\""

  test "escapes are kept verbatim inside the token value":
    let r = tokenizeStr("\"a\\nb\\t\\\"\\\\\"")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkString
    check toks[0].value == "\"a\\nb\\t\\\"\\\\\""

  test "empty string is a single tkString token":
    let r = tokenizeStr("\"\"")
    check r.isOk
    check r.get[0].kind == tkString
    check r.get[0].value == "\"\""

  test "a string splits cleanly from surrounding tokens":
    let r = tokenizeStr("ab\"cd\"12")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkAlphabet and toks[0].value == "ab"
    check toks[1].kind == tkString and toks[1].value == "\"cd\""
    check toks[2].kind == tkInteger and toks[2].value == "12"

  test "an unterminated string is rejected":
    let r = tokenizeStr("\"abc")
    check r.isErr
    check errorContains(r.error, "unterminated string literal")

  test "a raw newline inside a string is an unterminated string":
    let r = tokenizeStr("\"ab\ncd\"")
    check r.isErr
    check errorContains(r.error, "unterminated string literal")

  test "an invalid escape is rejected":
    let r = tokenizeStr("\"a\\xb\"")
    check r.isErr
    check errorContains(r.error, "invalid string escape")

suite "tokenizer — comments":

  test "a comment is one tkComment token from # to end of line":
    let r = tokenizeStr("# a comment\n")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkComment
    check toks[0].value == "# a comment"
    check toks[1].kind == tkNewline

  test "a comment stops at the newline, which stays a separate token":
    let r = tokenizeStr("# hi\nx")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkComment and toks[0].value == "# hi"
    check toks[1].kind == tkNewline
    check toks[2].kind == tkAlphabet and toks[2].value == "x"

  test "a comment runs to EOF when the line has no newline":
    let r = tokenizeStr("# trailing")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkComment and toks[0].value == "# trailing"
    check toks[1].kind == tkNewline   # synthetic trailing

  test "a bare # is a comment token":
    let r = tokenizeStr("#")
    check r.isOk
    check r.get[0].kind == tkComment and r.get[0].value == "#"

  test "a Trojan-Source codepoint hidden in a comment is still rejected":
    let r = tokenizeStr("# ‮evil")
    check r.isErr
    check errorContains(r.error, "bidirectional")

suite "tokenizer — integers":

  test "a bare integer is one tkInteger token":
    let r = tokenizeStr("12345")
    check r.isOk
    check r.get[0].kind == tkInteger and r.get[0].value == "12345"

  test "a leading sign is folded into the integer token":
    for s in ["-123", "+7", "-0"]:
      let r = tokenizeStr(s)
      check r.isOk
      let toks = r.get
      check toks[0].kind == tkInteger and toks[0].value == s
      check toks[1].kind == tkNewline   # nothing left over

  test "a sign not followed by digits stays punctuation":
    let r = tokenizeStr("-abc")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkPunctuation and toks[0].value == "-"
    check toks[1].kind == tkAlphabet and toks[1].value == "abc"

  test "a sign only binds the immediately following number":
    # "1-2" is 1, then a signed -2 (no infix subtraction in the grammar).
    let r = tokenizeStr("1-2")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkInteger and toks[0].value == "1"
    check toks[1].kind == tkInteger and toks[1].value == "-2"

suite "tokenizer — floats":

  test "fraction and exponent forms are single tkFloat tokens":
    for s in ["1.5", "0.1", "-1.5", "+2.0", "1e10", "1.5e3", "-1.5e-3", "1.0e400"]:
      let r = tokenizeStr(s)
      check r.isOk
      let toks = r.get
      check toks[0].kind == tkFloat and toks[0].value == s
      check toks[1].kind == tkNewline   # nothing left over

  test "a bare integer is not a float":
    let r = tokenizeStr("123")
    check r.isOk
    check r.get[0].kind == tkInteger

  test "a trailing dot with no fraction is an integer then a dot":
    let r = tokenizeStr("12.")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkInteger and toks[0].value == "12"
    check toks[1].kind == tkPunctuation and toks[1].value == "."

  test "a method call on an integer is not swallowed as a float":
    # `u32.add` — the `.add` must stay a getter/dot, not a float fraction.
    let r = tokenizeStr("u32.add")
    check r.isOk
    let toks = r.get
    check toks[0].kind == tkAlphabet and toks[0].value == "u"
    check toks[1].kind == tkInteger and toks[1].value == "32"
    check toks[2].kind == tkPunctuation and toks[2].value == "."
    check toks[3].kind == tkAlphabet and toks[3].value == "add"
