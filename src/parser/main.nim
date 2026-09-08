import strformat, sequtils, strutils, unicode, results, options, tables, os

# The parser consumes Location (every AST node carries one) from the
# tokenizer, a sibling package. It is NOT re-exported: downstream
# layers that need Location import `tokenizer/main` directly.
import ../tokenizer/main as tokenizer

# parser.nim (Parser + Spec[T] + oneOf / any / optional / ...) holds the
# combinator scaffolding. It is re-exported so the parser tests can drive
# the machinery (newParser, newSpec, expect, …) through the `parser/main`
# barrel; downstream layers consume the parser through the AST types +
# `parse*` entry point below and simply ignore it.
import parser
export parser

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
# Body cluster — mutually recursive
# ============================================================
#
# Expression → FunctionCall → ArgumentList → Expression, and
# Match → CaseBlock → StatementList → StatementLine → Statement → Match.
# Nim's forward declarations resolve the cycle; each proc below is
# implemented later in this section.

# `expressionSpec` is a named Spec because argumentListSpec references it
# directly via `expressionSpec.parenthesisList()` (and the body cluster
# recurses back through it).
var expressionSpec*: Spec[Expression]

proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError] =
  let (args, loc) = ? parser.expect(expressionSpec.parenthesisList())
  ok(newArgumentList(args, loc))
let argumentListSpec = newSpec("argument list", argumentListConsumer)

proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(".")
  let function = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  let args = ? parser.expect(argumentListSpec)
  ok(newFunctionCall(target, function, args))

let fncallSpec = newSpec[FunctionCall]("function call", functionCallConsumer)

proc explicitKwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(spaceSpec.optional())
  let expression = ? parser.expect(expressionSpec)
  ok(newKeywordArgument(name, expression, name.loc))

let explicitKwargSpec = newSpec("explicit keyword argument", explicitKwargConsumer)
let implicitKwargSpec = identifierSpec.map(newKeywordArgument)

let kwargSpec* = oneOf("keyword_argument", @[
  explicitKwargSpec,
  implicitKwargSpec,
])

let kwargListSpec = kwargSpec.curlyBracketList().map(newKeywordArgumentList)

proc parseUnionRef(parser: Parser): Result[UnionRef, ParserError] =
  let typeRef = ? parser.expect(argumentTypeSpec)
  discard ? parser.expect(".")
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
let structRefSpec = map(argumentTypeSpec, newStructRef)

proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError] =
  let structRef = ? parser.expect(structRefSpec)
  discard ? parser.expect(spaceSpec.optional())
  let fields = ? parser.expect(kwargListSpec)
  ok(newStructInitializer(structRef, fields))

let structInitSpec = newSpec[StructInitializer]("struct initializer", structInitializerConsumer)


let initSpec = oneOf("initializer spec", @[
  map(unionInitSpec, newInitializer),
  map(structInitSpec, newInitializer),
  map(literalInitSpec, newInitializer),
])

expressionSpec = oneOf("expression", @[
  literalSpec.map(newExpression),
  initSpec.map(newExpression),
  fncallSpec.map(newExpression),
  getterSpec.map(newExpression),
  identifierSpec.map(newExpression),
])

proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(spaceSpec.optional())
  let expression = ? parser.expect(expressionSpec)
  ok(newAssignment(target, expression, target.loc))

let assignmentSpec = newSpec[Assignment]("assignment", assignmentConsumer)

proc setterConsumer(parser: Parser): Result[Setter, ParserError] =
  let target = ? parser.expect(getterSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(spaceSpec.optional())
  let expr = ? parser.expect(expressionSpec)
  ok(newSetter(target, expr, target.loc))

let setterSpec = newSpec[Setter]("setter", setterConsumer)

let statementSpec = oneOf("statement", @[
  map(setterSpec, newStatement),
  map(assignmentSpec, newStatement),
  map(expressionSpec, newStatement),
])

proc caseHeaderConsumer(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.expect("case")
  discard ? parser.expect(spaceSpec)
  let pat = ? parser.expect(casePatternSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(pat)

let caseLineSpec = newSpec[CasePattern]("case line", caseHeaderConsumer)

var statementListSpec*: Spec[StatementList]

proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError] =
  let (pat, body) = ? parser.indentedBlock(caseLineSpec, statementListSpec)
  ok(newCaseBlock(pat, body, pat.loc))

let caseBlockSpec = newSpec[CaseBlock]("case block", caseConsumer)

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = parser.loc
  discard ? parser.expect("match")
  discard ? parser.expect(spaceSpec)
  # Match expressions cannot be the subject of another match expression.
  # expressionConsumer intentionally excludes match (match is parsed separately
  # in statementLineConsumer). This check guards against future changes that
  # might add match to expressionConsumer.
  let subject = ? parser.expect(expressionSpec)
  case subject.kind:
  of ekMatch: err(newParserError("match expression cannot be the subject of another match", loc))
  of ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable:
    discard parser.expect(spaceSpec.optional())
    discard ? parser.expect(":")
    discard ? parser.expect(emptyLineSpec)
    parser.level += 1
    let cases = ? parser.expect(caseBlockSpec.atLeastOne())
    parser.level -= 1
    ok(newMatchExpression(subject, cases, loc))

let matchSpec = newSpec[MatchExpression]("match", matchConsumer)

# identifier = match ...: — parsed atomically so a non-match assignment
# (`x = expr`) or a bare expression statement backtracks cleanly instead
# of committing to the match path on the leading identifier.
proc assignedMatchConsumer(parser: Parser): Result[Statement, ParserError] =
  let target = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect("=")
  discard ? parser.expect(spaceSpec.optional())
  let matchExpr = ? parser.expect(matchSpec)
  ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))

let matchAssignmentSpec = newSpec[Statement]("match assignment", assignedMatchConsumer)

proc statementLineConsumer(parser: Parser): Result[Statement, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  discard ? parser.expect(indentationSpec)
  # Try match assignment: identifier = match ...:
  # A FATAL error means the match committed (keyword + subject + `:`) but its
  # body is malformed — propagate it rather than masking it with the
  # plain-statement fallback below, which would report a misleading location.
  let maybeMatchAssign = parser.expect(matchAssignmentSpec)
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  if maybeMatchAssign.error.fatal: return err(maybeMatchAssign.error)
  # Try standalone match: match ...:
  let maybeMatch = parser.expect(matchSpec)
  if maybeMatch.isOk: return ok(newStatement(newExpression(maybeMatch.get)))
  if maybeMatch.error.fatal: return err(maybeMatch.error)
  # Inline statements: statement + newline
  let statement = ? parser.expect(statementSpec)
  discard ? parser.expect(emptyLineSpec)
  ok(statement)

let statementLineSpec = newSpec[Statement]("statement line", statementLineConsumer)
statementListSpec = statementLineSpec.atLeastOne().map(newStatementList)

# TODO(post-analysis-expander): re-wire expansion after the analyzer once the
# post-analysis expander lands (see plans/plan_post_analysis_expansion.md).
# The expand* procs above (lines 540-748) are kept as reference for that move.


proc functionDefConsumer(parser: Parser): Result[FunctionDef, ParserError] =
  let public = parser.expect("public").isOk
  if public: discard ? parser.expect(spaceSpec)

  let funcKeyword = ? parser.expect("func")
  discard ? parser.expect(spaceSpec)
  let funcName = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  let argDefList = ? parser.expect(argumentDefListSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(spaceSpec.optional())
  let returnType = ? parser.expect(argumentTypeSpec)
  ok(newFunctionDef(public, funcName, argDefList, returnType, funcKeyword.loc))

let functionDefSpec = newSpec[FunctionDef]("function def", functionDefConsumer)

proc userFunctionConsumer(parser: Parser): Result[UserFunction, ParserError] =
  ## Parses a user function block: optional decorator lines, then the
  ## function signature, then an indented statement-list body. Body
  ## failures are marked fatal — once past the header, the block can't
  ## be backtracked out of.
  let decorators = ? parser.expect(decoratorSpec.any())
  let (h, body) = ? parser.indentedBlock(functionDefSpec, statementListSpec)
  ok(newUserFunction(decorators, h, body))

let userFuncSpec = newSpec[UserFunction]("user function", userFunctionConsumer)

# @extern("symbol")
# public func name(args): ReturnType
proc externFunctionConsumer(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.expect(indentationSpec)
  discard ? parser.expect("@")
  discard ? parser.expect("extern")
  discard parser.expect(spaceSpec.optional())
  let loc = parser.loc
  discard ? parser.expect(leftParenthesisSpec)
  discard ? parser.expect(spaceSpec.optional())
  let symbol = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(rightParenthesisSpec)
  discard ? parser.expect(emptyLineSpec)
  let def = ? parser.expect(functionDefSpec.indentedLine())
  ok(newExternFunction(symbol.content, def, loc))

let externFuncSpec = newSpec[ExternFunction]("extern function", externFunctionConsumer)

proc functionConsumer(parser: Parser): Result[Function, ParserError] =
  ## Parses one function block — skips leading blank lines, then tries
  ## the extern form; falls back to user function on non-fatal failure.
  discard parser.expect(any(emptyLineSpec))
  let f = parser.expect(externFuncSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.expect(userFuncSpec)
  ok(newFunction(u))

let funcSpec = newSpec[Function]("function", functionConsumer)

proc functionListConsumer(parser: Parser): Result[FunctionList, ParserError] =
  let funcs = ? parser.expect(funcSpec.any())
  newFunctionList(funcs)

let functionListSpec = newSpec[FunctionList]("function list", functionListConsumer)

proc structRequiresConsumer(parser: Parser): Result[seq[Identifier], ParserError] =
  let (generics, _) = ? parser.expect(identifierSpec.parenthesisList(allowEmpty = false))
  ok(generics)

let requiredStructGenerics = newSpec[seq[Identifier]]("required struct generics", structRequiresConsumer)

# struct: field+ (field is identifier ":" argumentType)
proc structHeaderConsumer(parser: Parser): Result[StructDefHeader, ParserError] =
  let structKeyword = ? parser.expect("struct")

  let maybeRequires = ? parser.expect(requiredStructGenerics.optional())
  let requires = if maybeRequires.isSome: maybeRequires.get else: @[]

  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  newStructDefHeader(requires, structKeyword.loc)

let structHeaderSpec = newSpec[StructDefHeader]("struct def header", structHeaderConsumer)

# Each field line: (blank lines) + indentation + argumentDef + newline
proc indentedArgumentDefConsumer(parser: Parser): Result[ArgumentDef, ParserError] =
  discard ? parser.expect(any(emptyLineSpec))
  let def = ? parser.expect(argumentDefSpec.indentedLine())
  ok(def)

let argDefLineSpec = newSpec[ArgumentDef]("argument def", indentedArgumentDefConsumer)

proc structDefConsumer(parser: Parser): Result[StructDef, ParserError] =
  let (header, body) = ? parser.indentedBlock(structHeaderSpec, argDefLineSpec.atLeastOne())
  newStructDef(header, body)

let structDefSpec = newSpec[StructDef]("struct def", structDefConsumer)

# union: variant+ (variant is identifier space* "{" (argDef, argDef)* "}")
# Braces are required — empty variants must be written `Timeout { }`. This
# mirrors the case-pattern side (`case Timeout { }:`) so the two shapes
# stay visually consistent and there's no bare `Timeout` form to confuse
# with a variable-binding case pattern.
proc variantDefConsumer(parser: Parser): Result[VariantDef, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  let (fields, _) = ? parser.expect(argumentDefSpec.curlyBracketList())
  newVariantDef(name, fields, name.loc)

let variantDefSpec = newSpec[VariantDef]("variant def line", variantDefConsumer)

proc unionDefHeaderConsumer(parser: Parser): Result[Location, ParserError] =
  let unionKeyword = ? parser.expect("union")
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(unionKeyword.loc)

let unionDefHeaderSpec = newSpec[Location]("union header", unionDefHeaderConsumer)

proc unionDefConsumer(parser: Parser): Result[UnionDef, ParserError] =
  let (loc, body) = ? parser.indentedBlock(unionDefHeaderSpec, variantDefSpec.indentedLine().atLeastOne())
  newUnionDef(body, loc)

let unionDefSpec = newSpec[UnionDef]("union def", unionDefConsumer)

let dataDefSpec = oneOf("data block", @[
  literalDefSpec.map(newDataDef),
  structDefSpec.map(newDataDef),
  unionDefSpec.map(newDataDef),
])

proc genericHeaderConsumer(parser: Parser): Result[GenericHeader, ParserError] =
  let public = parser.expect("public").isOk
  if public: discard ? parser.expect(spaceSpec)
  let genericKeyword = ? parser.expect("generic")
  discard ? parser.expect(spaceSpec)
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(newGenericHeader(public, nameIdent, genericKeyword.loc))

let genericHeaderSpec = newSpec[GenericHeader]("generic header", genericHeaderConsumer)

proc genericConsumer(parser: Parser): Result[Generic, ParserError] =
  ## Parses a `[public] generic Name:` block followed by its function
  ## definitions. Body failures are marked fatal — once past the
  ## header, the block cannot be backtracked out of.
  let (h, body) = ? parser.indentedBlock(genericHeaderSpec, functionDefSpec.indentedLine().atLeastOne())
  ok(newGeneric(@[], h.public, h.name, body, h.loc))

let genericSpec = newSpec[Generic]("generic", genericConsumer)

proc moduleHeaderConsumer(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = parser.expect("public").isOk
  if public: discard ? parser.expect(spaceSpec)

  let moduleKeyword = ? parser.expect("module")
  discard ? parser.expect(spaceSpec)
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(newModuleHeader(public, nameIdent, moduleKeyword.loc))

let moduleHeaderSpec = newSpec[ModuleHeader]("module header", moduleHeaderConsumer)

proc moduleBodyConsumer(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  let data = ? parser.expect(dataDefSpec.optional())
  let funcList = ? parser.expect(functionListSpec)
  ok(newModuleBody(data, funcList))

let moduleBodySpec = newSpec[ModuleBody]("module body", moduleBodyConsumer)

proc moduleConsumer(parser: Parser): Result[Module, ParserError] =
  ## Parses a `[public] module Name:` block with optional decorator
  ## lines. Body failures are marked fatal — once past the header,
  ## the block cannot be backtracked out of.
  let decorators = ? parser.expect(any(decoratorSpec))
  let (h, b) = ? parser.indentedBlock(moduleHeaderSpec, moduleBodySpec)
  newModule(decorators, h.public, h.name, b.data, b.funcList, h.loc)

let moduleSpec = newSpec[Module]("module", moduleConsumer)

let typeSpec = oneOf("type", @[
  moduleSpec.map(newLocalType),
  genericSpec.map(newLocalType),
])

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
  discard ? parser.expect(emptyLineSpec.any())
  let imports = ? parser.expect(importSpec.any())
  discard ? parser.expect(emptyLineSpec.any())
  let items = ? parser.expect(localTypeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  discard ? parser.expect(emptyLineSpec.any())
  let items = ? parser.expect(localTypeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
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
