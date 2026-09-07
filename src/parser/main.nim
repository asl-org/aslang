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
proc expressionConsumer(parser: Parser): Result[Expression, ParserError]
proc statementListConsumer(parser: Parser): Result[StatementList, ParserError]
proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError]
proc functionCallConsumer(parser: Parser): Result[FunctionCall, ParserError]
proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError]
proc unionInitializerConsumer(parser: Parser): Result[UnionInitializer, ParserError]
proc structInitializerConsumer(parser: Parser): Result[StructInitializer, ParserError]
proc assignmentConsumer(parser: Parser): Result[Assignment, ParserError]
proc setterConsumer(parser: Parser): Result[Setter, ParserError]
proc caseConsumer(parser: Parser): Result[CaseBlock, ParserError]
proc matchConsumer(parser: Parser): Result[MatchExpression, ParserError]
proc statementLineConsumer(parser: Parser): Result[Statement, ParserError]

# `expressionSpec` is a named Spec because argumentListConsumer loops
# over it directly via `parser.expect(expressionSpec)`.
let expressionSpec* = newSpec[Expression]("expression", expressionConsumer)

proc argumentListConsumer(parser: Parser): Result[ArgumentList, ParserError] =
  let (args, loc) = ? parser.expect(expressionSpec.parenthesisList())
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

proc explicitKwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(newSpec(":"))
  discard ? parser.expect(spaceSpec.optional())
  let expression = ? parser.expect(expressionSpec)
  ok(newKeywordArgument(name, expression, name.loc))

let explicitKwargSpec = newSpec("explicit keyword argument", explicitKwargConsumer)

proc implicitKwargConsumer(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.expect(identifierSpec)
  ok(newKeywordArgument(name, newExpression(name), name.loc))

let implicitKwargSpec = newSpec("implicit keyword argument", implicitKwargConsumer)

# `kwargSpec` is a named Spec because kwargListConsumer loops over it
# directly via `parser.expect(kwargSpec)`.
let kwargSpec* = oneOf("keyword_argument", @[
  explicitKwargSpec,
  implicitKwargSpec,
])

proc kwargListConsumer(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let (args, loc) = ? parser.expect(kwargSpec.curlyBracketList())
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


let initSpec = oneOf("initializer spec", @[
  map(unionInitSpec, newInitializer),
  map(structInitSpec, newInitializer),
  map(literalInitSpec, newInitializer),
])

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

let statementSpec = oneOf("statement", @[
  map(setterSpec, newStatement),
  map(assignmentSpec, newStatement),
  map(expressionSpec, newStatement),
])

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
  # A FATAL error means the match committed (keyword + subject + `:`) but its
  # body is malformed — propagate it rather than masking it with the
  # plain-statement fallback below, which would report a misleading location.
  let maybeMatchAssign = parser.expect(matchAssignmentSpec)
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  if maybeMatchAssign.error.fatal: return err(maybeMatchAssign.error)
  # Try standalone match: match ...:
  let maybeMatch = parser.expect(matchSpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  if maybeMatch.error.fatal: return err(maybeMatch.error)
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
  let (generics, _) = ? parser.expect(identifierSpec.parenthesisList(allowEmpty = false))
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
  let (fields, _) = ? parser.expect(argumentDefSpec.curlyBracketList())
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
