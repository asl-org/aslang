import strformat, results

import tokenizer
import combinators
import helpers

# ============================================================
# StringContent (used internally by string parsing)
# ============================================================

type StringContent* = ref object
  content: string
  loc: Location

proc newStringContent*(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

proc content*(sc: StringContent): string = sc.content

proc escapedSpec(character: string, charSpec: Spec[Token]): Spec[
    StringContent] =
  Spec[StringContent](
    name: "'\\" & character & "'",
    parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
    let backslash = ? parser.run(backslashSpec)
    let token = ? parser.run(charSpec)
    if token.value != character:
      return err(newParserError(
        fmt"expected '\\{character}' but found '\\{token.value}'", token.loc))
    ok(newStringContent("\\" & character, backslash.loc))
  )

let escapedBackslash = escapedSpec("\\", backslashSpec)
let escapedDoubleQuote = escapedSpec("\"", doubleQuoteSpec)
let escapedNewline = escapedSpec("n", alphabetSpec)
let escapedTab = escapedSpec("t", alphabetSpec)

let escapedStringContentSpec = oneOf("escaped_string_character", [
  escapedBackslash,
  escapedDoubleQuote,
  escapedNewline,
  escapedTab,
])

let unescapedStringContentSpec = Spec[StringContent](
  name: "unescaped_string_character",
  parseFn: proc(parser: Parser): Result[StringContent, ParserError] =
  let token = ? parser.run(anyTokenExceptNewlineSpec("unescaped string character"))
  if token.value == "\"" or token.value == "\\":
    return err(newParserError(
      fmt"expected a valid string character but found '{token.value}'", token.loc))
  ok(newStringContent(token.value, token.loc))
)

let stringContentSpec = oneOf("string_content", [
  escapedStringContentSpec,
  unescapedStringContentSpec,
])

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
proc content*(strLit: StringLiteral): string = strLit.content
proc asl*(strLit: StringLiteral): string = fmt"""{strLit.content}"""

let stringLiteralSpec* = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  let chars = ? parser.run(any(stringContentSpec))
  var content: string; for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))
)
