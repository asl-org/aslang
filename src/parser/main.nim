import strformat, sequtils, strutils, unicode, results, options, tables, os

# The parser consumes Location (every AST node carries one) from the
# tokenizer, a sibling package. It is NOT re-exported: downstream
# layers that need Location import `tokenizer/main` directly.
import ../tokenizer/main as tokenizer

# combinators.nim (Spec[T] + oneOf / any / optional / ...) is
# imported but NOT re-exported. It's parser-internal scaffolding.
# Downstream layers (resolver, analyzer, cli, asl.nim) consume the
# parser through the AST types + `parse*` entry point below; the
# combinator machinery has no callers outside the parser layer.
# Parser tests that need it import `./combinators` directly.

import identifiers
export identifiers

import literals
export literals

import imports
export imports

import argtype
export argtype

import refs
export refs

import datadef
export datadef

import statement
export statement

import function
export function

import types
export types

import app
export app

# import ./combinators
# export combinators
import error
import decorator
import utils

type File = app.File

# ============================================================
# Parser
# ============================================================

type
  Parser* = ref object
    filepath*: string
    indentWidth*: uint32
    tokens: seq[Token]
    index*: int
    level*: uint32

proc newParser*(filepath: string, indentWidth: uint32, tokens: seq[
    Token]): Parser =
  Parser(filepath: filepath, indentWidth: indentWidth, tokens: tokens, index: 0, level: 0)

proc done(parser: Parser): bool =
  parser.index == parser.tokens.len

proc loc(parser: Parser): Location =
  if parser.done(): parser.tokens[^1].loc
  else: parser.tokens[parser.index].loc

proc peek(parser: Parser, tokenRepr: string): Result[Token, ParserError] =
  if parser.done():
    let msg = fmt"expected {tokenRepr} but reached end of token stream"
    err(newParserError(msg, parser.loc))
  else:
    ok(parser.tokens[parser.index])

# ============================================================
# Spec[T] — named, typed parser combinator
# ============================================================

type
  Consumer[T] = proc(parser: Parser): Result[T, ParserError]
  Matcher = proc(token: Token): bool
  ResultMapper[T, U] = proc(value: T): Result[U, ParserError]
  Mapper[T, U] = proc(value: T): U
  SpecKind = enum skDefault, skToken
  Spec*[T] = ref object
    name: string
    case kind: SpecKind
    of skDefault: consumer: Consumer[T]
    of skToken: matcher: Matcher

proc newSpec[T](name: string, consumer: Consumer[T]): Spec[T] =
  Spec[T](kind: skDefault, name: name, consumer: consumer)

proc newSpec(name: string, matcher: Matcher): Spec[Token] =
  Spec[Token](kind: skToken, name: name, matcher: matcher)

proc newSpec*(name: string, kind: TokenKind): Spec[Token] =
  newSpec(name, proc(t: Token): bool = t.kind == kind)

proc newSpec*(value: string): Spec[Token] =
  newSpec("'" & value & "'", proc(t: Token): bool = t.value == value)

# TODO: Remove it after fixing tokenizer
proc expect*[T](parser: Parser, spec: Spec[T]): Result[T, ParserError] =
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  let maybeValue =
    case spec.kind:
    of skDefault:
      spec.consumer(parser)
    of skToken:
      # A skToken spec is only ever constructed as Spec[Token], so the
      # token-matching arm is compiled only for that instantiation; the
      # generic `expect[T]` (e.g. T = seq[Token] via `any`) never reaches
      # skToken at runtime.
      when T is Token:
        let token = ? parser.peek(spec.name)
        if not spec.matcher(token):
          let msg = fmt"expected {spec.name} but found {token.repr}"
          err(newParserError(msg, parser.loc))
        else:
          parser.index += 1
          ok(token)
      else:
        raiseAssert("[BUG] - skToken spec must be Spec[Token]")

  if maybeValue.isErr:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
  return maybeValue

proc expectOptional[T](parser: Parser, spec: Spec[T]): Result[Option[T], ParserError] =
  let maybeItem = parser.expect(spec)
  if maybeItem.isErr:
    if maybeItem.error.fatal:
      err(maybeItem.error)
    else:
      ok(none(T))
  else:
    ok(some(maybeItem.get))

proc expectAny[T](parser: Parser, spec: Spec[T]): Result[seq[T], ParserError] =
  var items: seq[T]
  var maybeItem = ? parser.expectOptional(spec)
  while maybeItem.isSome:
    items.add(maybeItem.get)
    maybeItem = ? parser.expectOptional(spec)
  ok(items)

proc expectAtLeastOne[T](parser: Parser, spec: Spec[T]): Result[seq[T], ParserError] =
  let first = ? parser.expect(spec)
  var items = @[first]
  let rest = ? parser.expectAny(spec)
  items.add(rest)
  ok(items)

proc expectOneOf[T](parser: Parser, specs: seq[Spec[T]]): Result[T, ParserError] =
  assert(specs.len > 0, "`oneOf` combinator expects at least one spec")
  var errors: seq[ParserError]
  for spec in specs:
    let maybeValue = parser.expect(spec)
    if maybeValue.isOk: return maybeValue
    errors.add(maybeValue.error)
  err(max(errors))

proc any*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAny(spec)
  newSpec[seq[T]](spec.name & "*", consumer)

proc atLeastOne*[T](spec: Spec[T]): Spec[seq[T]] =
  let consumer = proc(parser: Parser): Result[seq[T], ParserError] = parser.expectAtLeastOne(spec)
  newSpec[seq[T]](spec.name & "+", consumer)

proc optional*[T](spec: Spec[T]): Spec[Option[T]] =
  let consumer = proc(parser: Parser): Result[Option[T], ParserError] = parser.expectOptional(spec)
  newSpec[Option[T]](spec.name & "?", consumer)

proc oneOf*[T](name: string, specs: seq[Spec[T]]): Spec[T] =
  let variants = specs.mapIt(it.name).join(" | ")
  let consumer = proc(parser: Parser): Result[T, ParserError] = parser.expectOneOf(specs)
  newSpec[T](name & ": " & variants, consumer)

proc map*[T, U](spec: Spec[T], name: string, mapper: ResultMapper[T, U]): Spec[U] =
  let consumer = proc(parser: Parser): Result[U, ParserError] = mapper(? parser.expect(spec))
  newSpec[U](spec.name, consumer)

proc map*[T, U](spec: Spec[T], mapper: Mapper[T, U]): Spec[U] =
  let consumer = proc(parser: Parser): Result[U, ParserError] = ok(mapper(? parser.expect(spec)))
  newSpec[U](spec.name, consumer)

# ============================================================
# Static leaf specs (token-kind + common punctuation)
# ============================================================
#
# Named singletons for grammar files, each a skToken `Spec` built via
# `newSpec`; kept named because grammar code reads better as
# `parser.expect(spaceSpec)` than `parser.expect(newSpec("space ' '", tkSpace))`.

let spaceSpec* = newSpec("space ' '", tkSpace)
let newlineSpec* = newSpec("newline '\\n'", tkNewline)
let commentSpec = newSpec("comment", tkComment)

let bangSpec* = newSpec("!")
let atSpec* = newSpec("@")
let dotSpec* = newSpec(".")
let colonSpec* = newSpec(":")
let leftParenthesisSpec* = newSpec("(")
let rightParenthesisSpec* = newSpec(")")
let leftCurlyBracketSpec* = newSpec("{")
let rightCurlyBracketSpec* = newSpec("}")
let leftSquareBracketSpec* = newSpec("[")
let rightSquareBracketSpec* = newSpec("]")

# space* comment? newline
proc emptyLineConsumer(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(commentSpec.optional())
  discard ? parser.expect(newlineSpec)
  ok(loc)

let emptyLineSpec = newSpec("empty line", emptyLineConsumer)

proc indentationConsumer(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  let maybeSpace = ? parser.expect(spaceSpec.optional())
  let count: uint32 = if maybeSpace.isSome: maybeSpace.get.value.len.uint32 else: 0
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(loc)

let indentationSpec = newSpec("indentation", indentationConsumer)

proc identifierConsumer(parser: Parser): Result[Identifier, ParserError] =
  # The tokenizer scans `[A-Za-z_][A-Za-z0-9_]*` into one tkIdentifier
  # token; newIdentifier enforces the naming rules (length, reserved
  # prefixes). Keywords are ordinary identifiers matched later by value.
  let token = ? parser.expect(newSpec("identifier", tkIdentifier))
  newIdentifier(token.value, token.loc)

let identifierSpec = newSpec("identifier", identifierConsumer)

# `identifierSpec` is a named Spec because several consumers loop over
# it directly via `parser.expect(identifierSpec)` (struct requires,
# argument-type impls, and other comma-separated identifier lists).

proc decoratorConsumer(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.expect(indentationSpec)
  discard ? parser.expect(atSpec)
  let ident = ? parser.expect(identifierSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(newDecorator(ident))

let decoratorSpec = newSpec("decorator", decoratorConsumer)

proc stringLiteralConsumer(parser: Parser): Result[StringLiteral, ParserError] =
  # The tokenizer scans a whole string literal into one `tkString` token
  # whose value is the raw `"…"` slice (quotes + verbatim escapes); strip
  # the surrounding quotes to get the content.
  let token = ? parser.expect(newSpec("string literal", tkString))
  ok(newStringLiteral(token.value, token.loc))

# Spec adapter for stringLiteralSpec — still consumed by remaining
# combinator chains (import specs, literalDefSpec, etc.).
let stringLiteralSpec* = newSpec("string_literal", stringLiteralConsumer)

# The tokenizer scans `(+|-)?digit+` into one tkInteger token;
# newIntegerLiteral splits its optional leading sign into signed/unsigned.
proc integerLiteralConsumer(parser: Parser): Result[IntegerLiteral, ParserError] =
  let token = ? parser.expect(newSpec("integer", tkInteger))
  ok(newIntegerLiteral(token.value, token.loc))

let integerLiteralSpec = newSpec("integer literal", integerLiteralConsumer)

# Every float form is a single tkFloat token: the tokenizer scans the
# numeric form `(+|-)?digit+(.digit+)?((e|E)(+|-)?digit+)?` and the special
# IEEE-754 values `nan` / `inf` / `+inf` / `-inf` (the sign folds into the
# token so downstream `analyzeFloatLiteral` can tell `+inf` from `-inf`).
# So one consumer covers them all — no per-form alternation.
proc floatLiteralConsumer(parser: Parser): Result[FloatLiteral, ParserError] =
  let token = ? parser.expect(newSpec("float", tkFloat))
  ok(newFloatLiteral(token.value, token.loc))

let floatLiteralSpec = newSpec("float literal", floatLiteralConsumer)

let literalSpec = oneOf("literal", @[
  map(stringLiteralSpec, newLiteral),
  map(floatLiteralSpec, newLiteral),
  map(integerLiteralSpec, newLiteral),
])

proc literalTypeConsumer(parser: Parser): Result[LiteralDef, ParserError] =
  discard ? parser.expect(indentationSpec)
  let literalKeyword = ? parser.expect(newSpec("literal"))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec(":"))
  discard ? parser.expect(spaceSpec.optional())
  let strLit = ? parser.expect(stringLiteralSpec)
  ok(newLiteralDef(strLit, literalKeyword.loc))

let literalDefSpec = newSpec[LiteralDef]("literal def", literalTypeConsumer)

# Argument-type sugar: a trailing `!` on an argument type expands to
# `Status[<argType>]`. Parsed uniformly here so every argument-type
# position picks it up — function args, return types, kwarg field
# types, and the initializer type prefix all route through this parser.
#
# Nesting binds tight: `!` attaches to the type it immediately follows.
#   T!            -> Status[T]
#   Array[u32]!   -> Status[Array[u32]]
#   Array[u32!]   -> Array[Status[u32]]
#   Status[u32]!  -> Status[Status[u32]]     (syntactically legal)
#
# The sugar collapses at parse time. Downstream (resolver, analyzer)
# sees a plain `Status[...]` ArgumentType — no distinct AST variant,
# no separate handling.
#
# When updating this sugar (different suffix, different wrapper type,
# arity checks, additional post-fix operators, etc.), touch:
#   - The `maybeBanged` block below.
#   - grammar.md — the ArgumentType production.
#   - validations.md — §4.8 (argument-type shorthand).
#   - tests/test_grammar.nim — the "argument type shorthand" suite.
#   - tests/test_analyzer.nim — end-to-end sugar tests.
#
# `argumentTypeConsumer` is self-referential: type params like
# `Map[String, List[Int]]` contain nested argument types. Nim's
# `proc` declarations handle recursion natively (a proc body can call
# the enclosing proc by name).

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError]
let argumentTypeSpec = newSpec[ArgumentType]("argument type", argumentTypeConsumer)

proc argumentImplListConsumer(parser: Parser): Result[seq[ArgumentType], ParserError] =
  discard ? parser.expect(leftSquareBracketSpec)
  discard ? parser.expect(spaceSpec.optional())
  var impls: seq[ArgumentType]

  let firstImpl = ? parser.expect(argumentTypeSpec)
  impls.add(firstImpl)
  discard ? parser.expect(spaceSpec.optional())
  var maybeComma = parser.expect(newSpec(","))
  while maybeComma.isOk:
    discard ? parser.expect(spaceSpec.optional())
    let impl = ? parser.expect(argumentTypeSpec)
    impls.add(impl)
    discard ? parser.expect(spaceSpec.optional())
    maybeComma = parser.expect(newSpec(","))

  discard ? parser.expect(rightSquareBracketSpec)
  ok(impls)

let argumentImplListSpec = newSpec("argument impl list", argumentImplListConsumer)

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.expect(identifierSpec)
  # Optional `[T, U, ...]` type params — argumentTypeConsumer recurses
  # into itself for each element. A leading `[` commits to the bracketed
  # list; absence of `[` means no type params.
  let maybeImpls = ? parser.expect(argumentImplListSpec.optional())
  let maybeBanged = ? parser.expect(bangSpec.optional())

  let argType =
    if maybeImpls.isSome:
      newArgumentType(rootIdent, maybeImpls.get)
    else:
      newArgumentType(rootIdent)

  if maybeBanged.isSome:
    let statusIdent = ? newIdentifier("Status", maybeBanged.get.loc)
    ok(newArgumentType(statusIdent, @[argType]))
  else:
    ok(argType)

proc argumentDefConsumer(parser: Parser): Result[ArgumentDef, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec(":"))
  discard ? parser.expect(spaceSpec.optional())
  let argType = ? parser.expect(argumentTypeSpec)
  ok(newArgumentDef(name, argType))

let argumentDefSpec* = newSpec[ArgumentDef]("argument_definition", argumentDefConsumer)

proc argumentDefListConsumer(parser: Parser): Result[ArgumentDefList, ParserError] =
  let loc = parser.loc
  discard ? parser.expect(leftParenthesisSpec)
  discard ? parser.expect(spaceSpec.optional())
  var argDefs: seq[ArgumentDef]
  let first = parser.expect(argumentDefSpec)
  if first.isOk:
    argDefs.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      argDefs.add(? parser.expect(argumentDefSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightParenthesisSpec)
  newArgumentDefList(argDefs, loc)

let argumentDefListSpec = newSpec[ArgumentDefList]("argument definition list", argumentDefListConsumer)


# Variant pattern field: name [":" binding] — bare `name` is sugar for
# `name: name`, mirroring the initializer kwarg shorthand. When the
# binding suffix is absent the parser synthesizes a binding with the
# same identifier (and the same source location).
proc unionPatternFieldConsumer(parser: Parser): Result[UnionPatternField, ParserError] =
  let name = ? parser.expect(identifierSpec)

  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  discard ? parser.expect(spaceSpec.optional())
  let maybeColon = parser.expect(newSpec(":"))
  if maybeColon.isOk:
    discard ? parser.expect(spaceSpec.optional())
    let binding = ? parser.expect(identifierSpec)
    ok(newUnionPatternField(name, binding, name.loc))
  else:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
    ok(newUnionPatternField(name, name, name.loc))

# Spec adapter.
let unionPatternFieldSpec* = newSpec[UnionPatternField]("variant_pattern_field", unionPatternFieldConsumer)

# Variant pattern: VariantName { field: binding, field: binding }
proc unionPatternConsumer(parser: Parser): Result[UnionPattern, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(leftCurlyBracketSpec)
  discard ? parser.expect(spaceSpec.optional())
  var fields: seq[UnionPatternField]
  let first = parser.expect(unionPatternFieldSpec)
  if first.isOk:
    fields.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      fields.add(? parser.expect(unionPatternFieldSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightCurlyBracketSpec)
  newUnionPattern(name, fields)

let unionPatternSpec = newSpec[UnionPattern]("union pattern", unionPatternConsumer)

let casePatternSpec = oneOf("case pattern", @[
  map(integerLiteralSpec, newCasePattern),
  map(unionPatternSpec, newCasePattern),
  map(identifierSpec, newCasePattern),
])

# import { Name, Name } from "path"
# identifier ("as" identifier)?
proc importedTypeConsumer(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.expect(identifierSpec)
  let maybeAs = parser.expect(spaceSpec.atLeastOne())
  if maybeAs.isOk:
    let maybeAsKeyword = parser.expect(newSpec("as"))
    if maybeAsKeyword.isOk:
      discard ? parser.expect(spaceSpec.atLeastOne())
      let alias = ? parser.expect(identifierSpec)
      ok(newImportedType(name, alias))
    else:
      ok(newImportedType(name))
  else:
    ok(newImportedType(name))

# Spec adapter.
let importedTypeSpec* = newSpec[ImportedType]("import_name", importedTypeConsumer)

proc toImportPath*(source: string, loc: Location): Result[ImportPath, ParserError] =
  ## Converts a raw quoted-string source (the body of an `import "..."`
  ## clause) into a typed ImportPath. Sources starting with `@` are
  ## vendor references; the remainder is validated as an ASL
  ## identifier (head: letter or underscore; tail: letter, digit, or
  ## underscore). Anything else is treated as a relative path —
  ## extension and parent-escape checks happen later in
  ## toAbsPath.
  if not source.startsWith("@"):
    return ok(newRelativeImportPath(source))
  let name = source[1..^1]
  if name.len == 0:
    return err(newParserError("vendor import path '@' is missing a vendor name", loc))
  if not (name[0].isAlphaAscii or name[0] == '_'):
    return err(newParserError(fmt"vendor name '{name}' must start with a letter or underscore", loc))
  for c in name[1..^1]:
    if not (c.isAlphaNumeric or c == '_'):
      return err(newParserError(fmt"vendor name '{name}' contains invalid character '{c}' (allowed: letters, digits, underscore)", loc))
  ok(newVendorImportPath(name))

proc toAbsPath*(parsedPath: ImportPath, importingFile: string,
    vendorRoots: VendorRoots): Result[string, string] =
  ## Resolves an import path to an absolute file path.
  ##
  ## - `ipkRelative`: resolves the relative source against the
  ##   importing file's directory. Rejects paths that escape to a
  ##   parent directory (normalized so tricks like
  ##   `./sub/../../escape` are caught). The `.asl` / `.aslr`
  ##   suffix is *optional* on the source: if the source ends in
  ##   `.asl` or `.aslr` the resolved path is used as-is; otherwise
  ##   the compiler tries the resolved path as typed, then falls
  ##   back to `<source>.asl` and finally `<source>.aslr`. `.asl`
  ##   is tried before `.aslr` because user code overwhelmingly
  ##   imports other user code; the runtime-interface case is a
  ##   belt-and-braces last attempt (most runtime imports flow
  ##   through `@<vendor>` paths anyway). Only if none of the
  ##   candidates exist is an error raised.
  ## - `ipkVendor`: looks up the vendor name in `vendorRoots` (the
  ##   table populated from `--vendor="<name>:<path>"` CLI flags
  ##   plus the default `std`). The registered target path is
  ##   already absolute. Missing vendor → diagnostic listing the
  ##   known ones.
  case parsedPath.kind:
  of ipkRelative:
    let source = parsedPath.relativeSource
    let (_, _, ext) = source.splitFile()
    let dir = normalizedPath(importingFile.parentDir)
    let baseResolved = normalizedPath((dir / source).absolutePath)
    let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
    if not baseResolved.startsWith(dirPrefix):
      return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
    if ext == ".asl" or ext == ".aslr":
      # Explicit extension — defer file-existence to the loader
      # (matching prior behaviour for typed paths).
      return ok(baseResolved)
    # Extensionless (or unrecognized-extension) source: try the bare
    # path first, then `<source>.asl`, then `<source>.aslr`. Loader
    # emits the natural "file not found" if none exist.
    if fileExists(baseResolved):
      return ok(baseResolved)
    let withAsl = baseResolved & ".asl"
    if fileExists(withAsl):
      return ok(withAsl)
    let withAslr = baseResolved & ".aslr"
    if fileExists(withAslr):
      return ok(withAslr)
    err(fmt"{importingFile}: import path '{source}' not found (also tried '{source}.asl' and '{source}.aslr')")
  of ipkVendor:
    let name = parsedPath.vendorName
    if name in vendorRoots:
      return ok(vendorRoots[name])
    var knownNames: seq[string]
    for vendorName in vendorRoots.keys:
      knownNames.add(vendorName)
    let knownDesc = if knownNames.len == 0: "(no vendors registered)" else: knownNames.join(", ")
    err(fmt"{importingFile}: unknown vendor '@{name}' — known vendors: {knownDesc}")

# Explicit form: `import { Name, Name as Alias } from "path"`.
proc explicitImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect(newSpec("import"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  discard ? parser.expect(leftCurlyBracketSpec)
  discard ? parser.expect(spaceSpec.optional())
  var names: seq[ImportedType]
  let first = parser.expect(importedTypeSpec)
  if first.isOk:
    names.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      names.add(? parser.expect(importedTypeSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightCurlyBracketSpec)
  discard ? parser.expect(spaceSpec.atLeastOne())
  discard ? parser.expect(newSpec("from"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let explicitImportLineSpec = newSpec[Import]("explicit import", explicitImportLineConsumer)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver once the
# target file's types are resolved.
proc shorthandImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect(newSpec("import"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let shorthandImportLineSpec = newSpec[Import]("implicit import", shorthandImportLineConsumer)

let importLineSpec =
  oneOf("import line", @[
    explicitImportLineSpec,
    shorthandImportLineSpec,
  ])

proc importConsumer(parser: Parser): Result[Import, ParserError] =
  ## Skips leading blank / comment lines, then parses one import line
  ## (either explicit `import { A, B } from "path"` or shorthand
  ## `import "path"`).
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(importLineSpec)

let importSpec = newSpec[Import]("import", importConsumer)

proc getterConsumer(parser: Parser): Result[Getter, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(dotSpec)
  let field = ? parser.expect(identifierSpec)
  ok(newGetter(target, field, target.loc))

let getterSpec = newSpec[Getter]("getter", getterConsumer)

# type literal
proc literalInitializerConsumer(parser: Parser): Result[LiteralInitializer, ParserError] =
  let argType = ? parser.expect(argumentTypeSpec)
  discard ? parser.expect(spaceSpec.atLeastOne())
  let lit = ? parser.expect(literalSpec)
  ok(newLiteralInitializer(argType, lit))

let literalInitSpec = newSpec[LiteralInitializer]("literal initializer", literalInitializerConsumer)

# ============================================================
# Body cluster — mutually recursive
# ============================================================
#
# Expression → FunctionCall → ArgumentList → Expression, and
# Match → CaseBlock → StatementList → StatementLine → Statement → Match.
# Nim's forward declarations resolve the cycle; each proc below is
# implemented later in this section.
proc expressionConsumer(parser: Parser): Result[Expression, ParserError]
proc statementListConsumer(parser: Parser): Result[StatementList, ParserError]
proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError]
proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError]
proc kwargConsumer(parser: Parser): Result[KeywordArgument, ParserError]
proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError]
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError]
proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError]
proc initializerConsumer(parser: Parser): Result[Initializer, ParserError]
proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError]
proc setterConsumer(parser: Parser): Result[Setter, ParserError]
proc inlineStatementConsumer(parser: Parser): Result[Statement, ParserError]
proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError]
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError]
proc statementLineConsumer(parser: Parser): Result[Statement, ParserError]

# `expressionSpec` is a named Spec because argumentListConsumer loops
# over it directly via `parser.expect(expressionSpec)`.
let expressionSpec* = newSpec[Expression]("expression", expressionConsumer)

proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  discard ? parser.expect(leftParenthesisSpec)
  discard ? parser.expect(spaceSpec.optional())
  var args: seq[Expression]
  let first = parser.expect(expressionSpec)
  if first.isOk:
    args.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      args.add(? parser.expect(expressionSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightParenthesisSpec)
  ok(newArgumentList(args, loc))

let argumentListSpec = newSpec[ArgumentList]("argument list", argumentListConsumer)

proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(dotSpec)
  let method0 = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  let args = ? parser.expect(argumentListSpec)
  ok(newFunctionCall(target, method0, args))

let fncallSpec = newSpec[FunctionCall]("function call", functionCallConsumer)


proc kwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.expect(identifierSpec)
  let indexCheckpoint = parser.index
  let levelCheckpoint = parser.level
  discard ? parser.expect(spaceSpec.optional())
  let maybeColon = parser.expect(newSpec(":"))
  if maybeColon.isOk:
    discard ? parser.expect(spaceSpec.optional())
    let expression = ? parser.expect(expressionSpec)
    ok(newKeywordArgument(name, expression, name.loc))
  else:
    parser.index = indexCheckpoint
    parser.level = levelCheckpoint
    ok(newKeywordArgument(name, newExpression(name), name.loc))

# `kwargSpec` is a named Spec because kwargListConsumer loops over it
# directly via `parser.expect(kwargSpec)`.
let kwargSpec* = newSpec[KeywordArgument]("keyword_argument", kwargConsumer)

proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  discard ? parser.expect(leftCurlyBracketSpec)
  discard ? parser.expect(spaceSpec.optional())
  var args: seq[KeywordArgument]
  let first = parser.expect(kwargSpec)
  if first.isOk:
    args.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      args.add(? parser.expect(kwargSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightCurlyBracketSpec)
  newKeywordArgumentList(args, loc)

let kwargListSpec = newSpec[KeywordArgumentList]("keyword argument list", kwargListConsumer)

proc parseUnionRef(parser: Parser): Result[UnionRef, ParserError] =
  let typeRef = ? parser.expect(argumentTypeSpec)
  discard ? parser.expect(dotSpec)
  let variant = ? parser.expect(identifierSpec)
  ok(newUnionRef(typeRef, variant))

let unionRefSpec = newSpec[UnionRef]("union ref", parseUnionRef)

# LocalType.Variant { fields } (bare — drives leave-as-is inference) or
# LocalType[Impls].Variant { fields } (explicit-impls — escape hatch when
# leave-as-is can't produce a fully-bound type). Both productions land
# on the same UnionRef shape carrying an impls seq; empty means bare.
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError] =
  let unionRef = ? parser.expect(unionRefSpec)
  discard ? parser.expect(spaceSpec.optional())
  let fields = ? parser.expect(kwargListSpec)
  ok(newUnionInitializer(unionRef, fields))

let unionInitSpec = newSpec[UnionInitializer]("union initializer", unionInitializerConsumer)

# Either `LocalType { fields }` (bare) or `LocalType[Impls] { fields }` (explicit
# impls, used for phantom-typed structs whose module declares a
# `struct(A):` header). Both productions land on the same StructRef
# shape carrying an impls seq; empty means bare.
proc parseStructRef(parser: Parser): Result[StructRef, ParserError] =
  let argType = ? parser.expect(argumentTypeSpec)
  ok(newStructRef(argType))

let structRefSpec = newSpec[StructRef]("struct ref", parseStructRef)

proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError] =
  let structRef = ? parser.expect(structRefSpec)
  discard ? parser.expect(spaceSpec.optional())
  let fields = ? parser.expect(kwargListSpec)
  ok(newStructInitializer(structRef, fields))

let structInitSpec = newSpec[StructInitializer]("struct initializer", structInitializerConsumer)

proc initializerConsumer(parser: Parser): Result[Initializer, ParserError] =
  var errors: seq[ParserError]
  let maybeUnion = parser.expect(unionInitSpec)
  if maybeUnion.isOk: return ok(newInitializer(maybeUnion.get))
  errors.add(maybeUnion.error)
  let maybeStruct = parser.expect(structInitSpec)
  if maybeStruct.isOk: return ok(newInitializer(maybeStruct.get))
  errors.add(maybeStruct.error)
  let maybeLit = parser.expect(literalInitSpec)
  if maybeLit.isOk: return ok(newInitializer(maybeLit.get))
  errors.add(maybeLit.error)
  err(max(errors))

let initSpec = newSpec[Initializer]("initializer spec", initializerConsumer)

proc expressionConsumer(parser: Parser): Result[Expression, ParserError] =
  var errors: seq[ParserError]
  let maybeLit = parser.expect(literalSpec)
  if maybeLit.isOk: return ok(newExpression(maybeLit.get))
  errors.add(maybeLit.error)
  let maybeInit = parser.expect(initSpec)
  if maybeInit.isOk: return ok(newExpression(maybeInit.get))
  errors.add(maybeInit.error)
  let maybeCall = parser.expect(fncallSpec)
  if maybeCall.isOk: return ok(newExpression(maybeCall.get))
  errors.add(maybeCall.error)
  let maybeGetter = parser.expect(getterSpec)
  if maybeGetter.isOk: return ok(newExpression(maybeGetter.get))
  errors.add(maybeGetter.error)
  let maybeIdent = parser.expect(identifierSpec)
  if maybeIdent.isOk: return ok(newExpression(maybeIdent.get))
  errors.add(maybeIdent.error)
  err(max(errors))

proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec("="))
  discard ? parser.expect(spaceSpec.optional())
  let expr = ? parser.expect(expressionSpec)
  ok(newAssignment(target, expr, target.loc))

let assignmentSpec = newSpec[Assignment]("assignment", assignmentConsumer)

proc setterConsumer(parser: Parser): Result[Setter, ParserError] =
  let target = ? parser.expect(getterSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec("="))
  discard ? parser.expect(spaceSpec.optional())
  let expr = ? parser.expect(expressionSpec)
  ok(newSetter(target, expr, target.loc))

let setterSpec = newSpec[Setter]("setter", setterConsumer)

proc inlineStatementConsumer(parser: Parser): Result[Statement, ParserError] =
  var errors: seq[ParserError]
  let maybeSet = parser.expect(setterSpec)
  if maybeSet.isOk: return ok(newStatement(maybeSet.get))
  errors.add(maybeSet.error)
  let maybeAssign = parser.expect(assignmentSpec)
  if maybeAssign.isOk: return ok(newStatement(maybeAssign.get))
  errors.add(maybeAssign.error)
  let maybeExpr = parser.expect(expressionSpec)
  if maybeExpr.isOk: return ok(newStatement(maybeExpr.get))
  errors.add(maybeExpr.error)
  err(max(errors))

let statementSpec = newSpec[Statement]("statement", inlineStatementConsumer)

proc parseCaseLine(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.expect(newSpec("case"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let pat = ? parser.expect(casePatternSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  ok(pat)

let caseLineSpec = newSpec[CasePattern]("case line", parseCaseLine)

proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError] =
  discard ? parser.expect(indentationSpec)
  let pat = ? parser.expect(caseLineSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = statementListConsumer(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newCaseBlock(pat, bodyResult.get, pat.loc))

let caseBlockSpec = newSpec[CaseBlock]("case block", caseConsumer)

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError] =
  let matchKeyword = ? parser.expect(newSpec("match"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  # Match expressions cannot be the subject of another match expression.
  # expressionConsumer intentionally excludes match (match is parsed separately
  # in statementLineConsumer). This check guards against future changes that
  # might add match to expressionConsumer.
  let subject = ? parser.expect(expressionSpec)
  case subject.kind:
  of ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", matchKeyword.loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable: discard
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  var cases: seq[CaseBlock]
  let firstCaseResult = block:
    discard parser.expect(any(emptyLineSpec))
    parser.expect(caseBlockSpec)
  if firstCaseResult.isErr:
    parser.level -= 1
    firstCaseResult.error.fatal = true
    return err(firstCaseResult.error)
  cases.add(firstCaseResult.get)
  while true:
    discard parser.expect(any(emptyLineSpec))
    let nextCase = parser.expect(caseBlockSpec)
    if nextCase.isErr:
      if nextCase.error.fatal:
        parser.level -= 1
        return err(nextCase.error)
      break
    cases.add(nextCase.get)
  parser.level -= 1
  ok(newMatchExpression(subject, cases, matchKeyword.loc))

let matchSpec = newSpec[MatchExpression]("match", matchConsumer)

# identifier = match ...: — parsed atomically so a non-match assignment
# (`x = expr`) or a bare expression statement backtracks cleanly instead
# of committing to the match path on the leading identifier.
proc parseMatchAssignment(parser: Parser): Result[Statement, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec("="))
  discard ? parser.expect(spaceSpec.optional())
  let matchExpr = ? parser.expect(matchSpec)
  ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))

let matchAssignmentSpec = newSpec[Statement]("match assignment", parseMatchAssignment)

proc statementLineConsumer(parser: Parser): Result[Statement, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  discard ? parser.expect(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.expect(matchAssignmentSpec)
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.expect(matchSpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.expect(statementSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(statement)

let statementLineSpec = newSpec[Statement]("statement line", statementLineConsumer)

proc statementListConsumer(parser: Parser): Result[StatementList, ParserError] =
  var stmts: seq[Statement]
  let first = ? parser.expect(statementLineSpec)
  stmts.add(first)
  while true:
    let maybeNext = parser.expect(statementLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    stmts.add(maybeNext.get)
  ok(newStatementList(stmts))

# TODO(post-analysis-expander): re-wire expansion after the analyzer once the
# post-analysis expander lands (see plans/plan_post_analysis_expansion.md).
# The expand* procs above (lines 540-748) are kept as reference for that move.


proc parseFunctionDef(parser: Parser): Result[FunctionDef, ParserError] =
  let public = parser.expect(newSpec("public")).isOk
  if public: discard ? parser.expect(spaceSpec.atLeastOne())

  let funcKeyword = ? parser.expect(newSpec("func"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let funcName = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  let argDefList = ? parser.expect(argumentDefListSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec(":"))
  discard ? parser.expect(spaceSpec.optional())
  let returnType = ? parser.expect(argumentTypeSpec)
  ok(newFunctionDef(public, funcName, argDefList, returnType, funcKeyword.loc))

let functionDefSpec = newSpec[FunctionDef]("function def", parseFunctionDef)

proc parseFunctionDefLine(parser: Parser): Result[FunctionDef, ParserError] =
  ## Indented single-line variant used by `parseFunctionDefs`.
  discard ? parser.expect(indentationSpec)
  let def = ? parser.expect(functionDefSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(def)

let funcDefLineSpec = newSpec[FunctionDef]("function def line", parseFunctionDefLine)

proc parseFunctionDefs(parser: Parser): Result[seq[FunctionDef], ParserError] =
  ## Parses one-or-more function-definition lines. Used inside a
  ## `generic` block, which only carries signatures — no bodies.
  var defs: seq[FunctionDef]
  let first = ? parser.expect(funcDefLineSpec)
  defs.add(first)
  while true:
    let maybeNext = parser.expect(funcDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    defs.add(maybeNext.get)
  ok(defs)

proc parseUserFunction(parser: Parser): Result[UserFunction, ParserError] =
  ## Parses a user function block: optional decorator lines, then the
  ## function signature, then an indented statement-list body. Body
  ## failures are marked fatal — once past the header, the block can't
  ## be backtracked out of.
  let decorators = ? parser.expect(any(decoratorSpec))
  discard ? parser.expect(indentationSpec)
  let h = ? parser.expect(functionDefSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = statementListConsumer(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newUserFunction(decorators, h, bodyResult.get))

let userFuncSpec = newSpec[UserFunction]("user function", parseUserFunction)

# @extern("symbol")
# public func name(args): ReturnType
proc parseExternFunction(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.expect(indentationSpec)
  discard ? parser.expect(atSpec)
  discard ? parser.expect(newSpec("extern"))
  discard parser.expect(spaceSpec.optional())
  let loc = parser.loc
  discard ? parser.expect(leftParenthesisSpec)
  discard ? parser.expect(spaceSpec.optional())
  let symbol = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightParenthesisSpec)
  discard ? parser.expect(emptyLineSpec)
  discard ? parser.expect(indentationSpec)
  let def = ? parser.expect(functionDefSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(newExternFunction(symbol.content, def, loc))

let externFuncSpec = newSpec[ExternFunction]("extern function", parseExternFunction)

proc parseFunction(parser: Parser): Result[Function, ParserError] =
  ## Parses one function block — skips leading blank lines, then tries
  ## the extern form; falls back to user function on non-fatal failure.
  discard parser.expect(any(emptyLineSpec))
  let f = parser.expect(externFuncSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.expect(userFuncSpec)
  ok(newFunction(u))

let funcSpec = newSpec[Function]("function", parseFunction)

proc parseFunctionList(parser: Parser): Result[FunctionList, ParserError] =
  ## Parses zero-or-more function blocks (extern or user), then wraps
  ## them into a FunctionList (which enforces name+arity uniqueness).
  var funcs: seq[Function]
  while true:
    let maybeFn = parser.expect(funcSpec)
    if maybeFn.isErr:
      if maybeFn.error.fatal: return err(maybeFn.error)
      break
    funcs.add(maybeFn.get)
  newFunctionList(funcs)

let functionListSpec = newSpec[FunctionList]("function list", parseFunctionList)

proc parseStructRequires(parser: Parser): Result[seq[Identifier], ParserError] =
  ## Parses the `(A, B, C)` clause of a `struct(A, B, C):` header —
  ## a parenthesised comma-separated identifier list naming the
  ## struct's required generic impls.
  discard ? parser.expect(leftParenthesisSpec)
  discard ? parser.expect(spaceSpec.optional())
  var generics: seq[Identifier]
  let first = parser.expect(identifierSpec)
  if first.isOk:
    generics.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      generics.add(? parser.expect(identifierSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightParenthesisSpec)
  ok(generics)

let requiredStructGenerics = newSpec[seq[Identifier]]("required struct generics", parseStructRequires)

# struct: field+ (field is identifier ":" argumentType)
proc parseStructHeader(parser: Parser): Result[StructDefHeader, ParserError] =
  let structKeyword = ? parser.expect(newSpec("struct"))
  let maybeRequires = ? parser.expect(requiredStructGenerics.optional())
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  let requires = if maybeRequires.isSome: maybeRequires.get else: @[]
  # newStructDefHeader validation errors (duplicate generic in header)
  # must be fatal — we're past `struct(...)` so an outer expectOptional
  # shouldn't swallow the failure and treat the whole struct as absent.
  let headerResult = newStructDefHeader(requires, structKeyword.loc)
  if headerResult.isErr:
    headerResult.error.fatal = true
  headerResult

let structHeaderSpec = newSpec[StructDefHeader]("struct def header", parseStructHeader)

# Each field line: (blank lines) + indentation + argumentDef + newline
proc parseArgumentDefLine(parser: Parser): Result[ArgumentDef, ParserError] =
  discard ? parser.expect(any(emptyLineSpec))
  discard ? parser.expect(indentationSpec)
  let def = ? parser.expect(argumentDefSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(def)

let argDefLineSpec = newSpec[ArgumentDef]("argument def", parseArgumentDefLine)

proc parseStructBody(parser: Parser): Result[seq[ArgumentDef], ParserError] =
  var fields: seq[ArgumentDef]
  let first = ? parser.expect(argDefLineSpec)
  fields.add(first)
  while true:
    let maybeNext = parser.expect(argDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    fields.add(maybeNext.get)
  ok(fields)

proc parseStruct(parser: Parser): Result[StructDef, ParserError] =
  discard ? parser.expect(indentationSpec)
  let header = ? parser.expect(structHeaderSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseStructBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  # newStructDef validation errors (duplicate generic in header,
  # duplicate field name) must also be fatal — we're past the header,
  # so an outer expectOptional shouldn't swallow the failure and treat
  # the whole struct as absent.
  let structResult = newStructDef(header, bodyResult.get)
  if structResult.isErr:
    structResult.error.fatal = true
  structResult

let structDefSpec = newSpec[StructDef]("struct def", parseStruct)

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
proc parseVariantDefLine(parser: Parser): Result[VariantDef, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  discard ? parser.expect(indentationSpec)
  let name = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(leftCurlyBracketSpec)
  discard ? parser.expect(spaceSpec.optional())
  var fields: seq[ArgumentDef]
  let first = parser.expect(argumentDefSpec)
  if first.isOk:
    fields.add(first.get)
    while true:
      let indexCheckpoint = parser.index
      let levelCheckpoint = parser.level
      discard ? parser.expect(spaceSpec.optional())
      if parser.expect(newSpec(",")).isErr:
        parser.index = indexCheckpoint
        parser.level = levelCheckpoint
        break
      discard ? parser.expect(spaceSpec.optional())
      fields.add(? parser.expect(argumentDefSpec))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightCurlyBracketSpec)
  discard ? parser.expect(emptyLineSpec)
  newVariantDef(name, fields, name.loc)

let variantDefLineSpec = newSpec[VariantDef]("variant def line", parseVariantDefLine)

proc parseUnionHeader(parser: Parser): Result[Location, ParserError] =
  let unionKeyword = ? parser.expect(newSpec("union"))
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  ok(unionKeyword.loc)

let unionHeaderSpec = newSpec[Location]("union header", parseUnionHeader)

proc parseUnionBody(parser: Parser): Result[seq[VariantDef], ParserError] =
  var variants: seq[VariantDef]
  let first = ? parser.expect(variantDefLineSpec)
  variants.add(first)
  while true:
    let maybeNext = parser.expect(variantDefLineSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    variants.add(maybeNext.get)
  ok(variants)

proc parseUnion(parser: Parser): Result[UnionDef, ParserError] =
  discard ? parser.expect(indentationSpec)
  let loc = ? parser.expect(unionHeaderSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseUnionBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  newUnionDef(bodyResult.get, loc)

let unionDefSpec = newSpec[UnionDef]("union def", parseUnion)

proc parseData(parser: Parser): Result[DataDef, ParserError] =
  ## Parses a module's data block: literal, struct, or union. Tries
  ## each in order; returns the error from whichever candidate
  ## reached farthest into the token stream. A fatal error from any
  ## branch short-circuits — once a branch has committed past the
  ## point of no-return, its error must propagate rather than being
  ## swallowed by trying the next branch.
  var errors: seq[ParserError]
  let maybeLiteral = parser.expect(literalDefSpec)
  if maybeLiteral.isOk: return ok(newDataDef(maybeLiteral.get))
  if maybeLiteral.error.fatal: return err(maybeLiteral.error)
  errors.add(maybeLiteral.error)
  let maybeStruct = parser.expect(structDefSpec)
  if maybeStruct.isOk: return ok(newDataDef(maybeStruct.get))
  if maybeStruct.error.fatal: return err(maybeStruct.error)
  errors.add(maybeStruct.error)
  let maybeUnion = parser.expect(unionDefSpec)
  if maybeUnion.isOk: return ok(newDataDef(maybeUnion.get))
  if maybeUnion.error.fatal: return err(maybeUnion.error)
  errors.add(maybeUnion.error)
  err(max(errors))

let dataDefSpec = newSpec[DataDef]("data def", parseData)

proc parseGenericHeader(parser: Parser): Result[GenericHeader, ParserError] =
  let public = parser.expect(newSpec("public")).isOk
  if public: discard ? parser.expect(spaceSpec.atLeastOne())
  let genericKeyword = ? parser.expect(newSpec("generic"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  ok(newGenericHeader(public, nameIdent, genericKeyword.loc))

let genericHeaderSpec = newSpec[GenericHeader]("generic header", parseGenericHeader)

proc parseGeneric(parser: Parser): Result[Generic, ParserError] =
  ## Parses a `[public] generic Name:` block followed by its function
  ## definitions. Body failures are marked fatal — once past the
  ## header, the block cannot be backtracked out of.
  discard ? parser.expect(indentationSpec)
  let h = ? parser.expect(genericHeaderSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseFunctionDefs(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  ok(newGeneric(@[], h.public, h.name, bodyResult.get, h.loc))

let genericSpec = newSpec[Generic]("generic", parseGeneric)

proc parseModuleHeader(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = parser.expect(newSpec("public")).isOk
  if public: discard ? parser.expect(spaceSpec.atLeastOne())

  let moduleKeyword = ? parser.expect(newSpec("module"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(colonSpec)
  ok(newModuleHeader(public, nameIdent, moduleKeyword.loc))

let moduleHeaderSpec = newSpec[ModuleHeader]("module header", parseModuleHeader)

proc parseModuleBody(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  let data = ? parser.expect(dataDefSpec.optional())
  let funcList = ? parser.expect(functionListSpec)
  ok(newModuleBody(data, funcList))

let moduleBodySpec = newSpec[ModuleBody]("module body", parseModuleBody)

proc parseModule(parser: Parser): Result[Module, ParserError] =
  ## Parses a `[public] module Name:` block with optional decorator
  ## lines. Body failures are marked fatal — once past the header,
  ## the block cannot be backtracked out of.
  let decorators = ? parser.expect(any(decoratorSpec))
  discard ? parser.expect(indentationSpec)
  let h = ? parser.expect(moduleHeaderSpec)
  discard ? parser.expect(emptyLineSpec)
  parser.level += 1
  let bodyResult = parseModuleBody(parser)
  parser.level -= 1
  if bodyResult.isErr:
    bodyResult.error.fatal = true
    return err(bodyResult.error)
  let b = bodyResult.get
  newModule(decorators, h.public, h.name, b.data, b.funcList, h.loc)

let moduleSpec = newSpec[Module]("module", parseModule)


proc parseType(parser: Parser): Result[LocalType, ParserError] =
  ## Parses either a module or a generic block and wraps it as `LocalType`.
  ## Tries module first; if that fails non-fatally, tries generic;
  ## returns whichever error carried further into the token stream.
  ## Fatal errors short-circuit — once a branch has committed past
  ## the point of no-return, its error must propagate rather than
  ## being swallowed by trying the next branch.
  var errors: seq[ParserError]
  let maybeModule = parser.expect(moduleSpec)
  if maybeModule.isOk: return ok(newLocalType(maybeModule.get))
  if maybeModule.error.fatal: return err(maybeModule.error)
  errors.add(maybeModule.error)
  let maybeGeneric = parser.expect(genericSpec)
  if maybeGeneric.isOk: return ok(newLocalType(maybeGeneric.get))
  if maybeGeneric.error.fatal: return err(maybeGeneric.error)
  errors.add(maybeGeneric.error)
  err(max(errors))

let typeSpec = newSpec[LocalType]("type", parseType)

proc parseDefinedType(parser: Parser): Result[LocalType, ParserError] =
  ## Skips leading blank / comment lines, then parses a module or
  ## generic block. Used at file level between top-level type blocks.
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(typeSpec)

let localTypeSpec = newSpec[LocalType]("local type", parseDefinedType)

proc parseDefinedTypes(parser: Parser): Result[seq[LocalType], ParserError] =
  ## Parses one-or-more top-level `LocalType` blocks (module / generic),
  ## skipping blank lines between them. Fails if the first attempt
  ## does not yield a type.
  var items: seq[LocalType]
  let first = ? parser.expect(localTypeSpec)
  items.add(first)
  while true:
    let maybeNext = parser.expect(localTypeSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    items.add(maybeNext.get)
  ok(items)

let definedTypesSpec = newSpec[seq[LocalType]]("defined types", parseDefinedTypes)

# aslFile: import* (module | generic)*  — user-authored source files.
proc parseAslFile(parser: Parser, vendorRoots: VendorRoots): Result[File, ParserError] =
  let imports = ? parser.expect(any(importSpec))
  let items = ? parser.expect(definedTypesSpec)
  discard parser.expect(any(emptyLineSpec))
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  let items = ? parser.expect(definedTypesSpec)
  discard parser.expect(any(emptyLineSpec))
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslrFile(parser.filepath, items, @[])

proc toStringErr(r: Result[File, ParserError]): Result[File, string] =
  if r.isOk: ok(r.get) else: err(fmt"{r.error}")

proc parseFile*(parser: Parser, vendorRoots: VendorRoots): Result[File, string] =
  ## Runs the grammar against `parser` and returns the parsed `File`.
  ## Dispatches on the filepath extension: `.asl` files parse imports
  ## plus modules/generics; `.aslr` files parse modules/generics only
  ## (runtime interface — no imports allowed).
  let (_, _, ext) = parser.filepath.splitFile()
  case ext:
  of ".asl": parseAslFile(parser, vendorRoots).toStringErr
  of ".aslr": parseAslrFile(parser).toStringErr
  else: err(fmt"{parser.filepath}: unrecognized file extension '{ext}' — expected '.asl' or '.aslr'")

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  if not fileExists(filepath):
    return err(fmt"{filepath}: file not found")
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"{filepath} file exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      let source = readFile(filepath)
      let pos = validateUtf8(source)
      if pos == -1: ok(source)
      else: err(fmt"{filepath} invalid UTF-8 byte at position {pos}.")
  except CatchableError:
    err(fmt"{filepath} failed to read file.")

proc dump(filepath: string, tokens: seq[Token]): string =
  var content: seq[string]
  content.add(fmt"--- // START {filepath} tokens ({tokens.len}) ---")
  for token in tokens:
    content.add($(token))
  content.add(fmt"--- // END {filepath} ---")
  return content.join("\n")

proc loadFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool, vendorRoots: VendorRoots): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath)
  if dumpTokens: echo filepath.dump(tokens)
  let parser = newParser(filepath, indentWidth, tokens)
  parser.parseFile(vendorRoots)

proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool, vendorRoots: VendorRoots): Result[App, string] =
  ## BFS through imports, tokenize + parse each file.
  ## Returns App with files in topological order: leaves first, root last.
  ## `vendorRoots` threads through every `parseFile` call so the
  ## per-file `aslFileSpec` can hand it to `newAslFile` (which uses
  ## it to auto-inject `import "@std"` in W10).
  ##
  ## `imp.absPath` was already resolved when the importing file was
  ## parsed (toAbsPath ran inside the import-line spec).
  ## Both the BFS walk and the topoSort reuse it directly through
  ## `importPaths` — re-resolving would produce the same value and
  ## slow down parsing unnecessarily.
  let parsed = ? bfs(
    rootPath,
    proc(path: string): Result[File, string] =
      loadFile(path, indentWidth, dumpTokens, vendorRoots),
    importPaths)

  # Topological sort with cycle detection (leaves first, root last)
  let sortedPaths = ? topoSort(rootPath, proc(path: string): seq[string] =
    if parsed.hasKey(path): importPaths(parsed[path])
    else: @[])

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(newApp(files))
