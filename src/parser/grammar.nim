import strutils, strformat, results, options, os

import tokenizer, ast, combinators

proc resolveImportPath(source: string, importingFile: string): Result[string, string] =
  ## Resolves an import path relative to the importing file.
  ## Rejects paths that escape to parent directories.
  ## Normalizes the resolved path so tricks like ./sub/../../escape
  ## are caught — not just paths starting with "..".
  let dir = normalizedPath(importingFile.parentDir)
  let resolved = normalizedPath((dir / source).absolutePath)
  let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
  if not resolved.startsWith(dirPrefix):
    return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
  ok(resolved)

# Disambiguate against system File (syncio.File)
type File = ast.File

# ============================================================
# Grammar specs
# ============================================================

let spaceSpec = tokenSpec(tkSpace, "space ' '")
let newlineSpec = tokenSpec(tkNewline, "newline '\\n'")
let alphabetSpec = tokenSpec(tkAlphabet, "alphabet [a-zA-Z]")
let digitSpec = tokenSpec(tkDigit, "digit [0-9]")
let underscoreSpec = punctuationSpec("_")
let hashSpec = punctuationSpec("#")
let backslashSpec = punctuationSpec("\\")
let doubleQuoteSpec = punctuationSpec("\"")

let commentSpec = Spec[Location](
  name: "comment",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let hashtag = ? parser.run(hashSpec)
  discard parser.run(any(anyTokenExceptNewlineSpec("comment character")))
  ok(hashtag.loc)
)

# ============================================================
# Implicit separators
# ============================================================

let strictSpace = atLeastOne(spaceSpec)
let optionalSpace = any(spaceSpec)

# space* comment? newline
let ignorableLineSpec = Spec[Location](
  name: "ignorable_line",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = parser.loc
  discard ? parser.run(any(spaceSpec))
  discard ? parser.run(optional(commentSpec))
  discard ? parser.run(newlineSpec)
  ok(loc)
)

let strictLine = ignorableLineSpec
let optionalLines = any(ignorableLineSpec)

proc separatorSpec(sep: string): Spec[Token] =
  Spec[Token](
    name: "'" & sep & "'",
    parseFn: proc(parser: Parser): Result[Token, ParserError] =
    discard ? parser.run(any(spaceSpec))
    let token = ? parser.run(punctuationSpec(sep))
    discard ? parser.run(any(spaceSpec))
    ok(token)
  )

let commaWithSpacesSpec = separatorSpec(",")
let colonWithSpacesSpec = separatorSpec(":")

let identifierHeadCharSpec = oneOf("identifier_head", [
  underscoreSpec,
  alphabetSpec,
])

let identifierTailCharSpec = oneOf("identifier_tail", [
  identifierHeadCharSpec,
  digitSpec,
])

let identifierSpec = Spec[Identifier](
  name: "identifier",
  parseFn: proc(parser: Parser): Result[Identifier, ParserError] =
  let head = ? parser.run(identifierHeadCharSpec)
  let tails = ? parser.run(any(identifierTailCharSpec))
  var content = head.value
  for tail in tails: content.add(tail.value)
  newIdentifier(content, head.loc)
)

proc keywordSpec(keyword: string): Spec[Location] =
  Spec[Location](
    name: "'" & keyword & "'",
    parseFn: proc(parser: Parser): Result[Location, ParserError] =
    let ident = ? parser.run(identifierSpec)
    if ident.value != keyword:
      let msg = fmt"expected keyword '{keyword}' but found '{ident.value}'"
      return err(newParserError(msg, ident.loc))
    ok(ident.loc)
  )

let indentationSpec = Spec[Space](
  name: "indentation",
  parseFn: proc(parser: Parser): Result[Space, ParserError] =
  let loc = parser.loc
  let spaces = ? parser.run(any(spaceSpec))

  let count = spaces.len.uint32
  let expected = parser.indentWidth * parser.level
  if count != expected:
    let msg = fmt"indentation error expected {expected} but found {count} space(s)"
    err(newParserError(msg, loc))
  else:
    ok(newSpace(count, loc))
)

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

let stringLiteralSpec = Spec[StringLiteral](
  name: "string_literal",
  parseFn: proc(parser: Parser): Result[StringLiteral, ParserError] =
  let openQuote = ? parser.run(doubleQuoteSpec)
  let chars = ? parser.run(any(stringContentSpec))
  var content: string; for ch in chars: content.add(ch.content)
  discard ? parser.run(doubleQuoteSpec)
  ok(newStringLiteral(content, openQuote.loc))
)

# Forward-declared via newSpec because argumentTypeSpec is self-referential:
# type params like Map[String, List[Int]] contain nested argument types.
# The ref is created first (parseFn: nil), then filled in below so the
# closure can capture the already-existing ref for recursive calls.
let argumentTypeSpec = newSpec[ArgumentType]("argument_type")
argumentTypeSpec.parseFn = proc(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.run(identifierSpec)
  let maybeImpls = ? parser.run(optional(
    contained("type_params", "[",
      separatedBy(argumentTypeSpec, commaWithSpacesSpec), "]")))
  if maybeImpls.isSome:
    ok(newArgumentType(rootIdent, maybeImpls.get, rootIdent.loc))
  else:
    ok(newArgumentType(rootIdent, rootIdent.loc))

let argumentDefinitionSpec = Spec[ArgumentDefinition](
  name: "argument_definition",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  let argName = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let argType = ? parser.run(argumentTypeSpec)
  ok(newArgumentDefinition(argName, argType, argName.loc))
)

let argumentDefinitionListSpec = Spec[ArgumentDefinitionList](
  name: "argument_definition_list",
  parseFn: proc(parser: Parser): Result[ArgumentDefinitionList, ParserError] =
  let loc = parser.loc
  let argDefs = ? parser.run(contained("argument_definition_list", "(",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), ")"))
  newArgumentDefinitionList(argDefs, loc)
)

let functionDefinitionSpec = Spec[FunctionDefinition](
  name: "function_definition",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  let funcLoc = ? parser.run(keywordSpec("func"))
  discard ? parser.run(strictSpace)
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let argDefList = ? parser.run(argumentDefinitionListSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.run(argumentTypeSpec)
  ok(newFunctionDefinition(funcName, argDefList, returnType, funcLoc))
)

# Forward-declared because expressions appear inside argument lists
# of function calls, creating a mutual recursion:
# expression -> functionCall -> argumentList -> expression
let expressionSpec = newSpec[Expression]("expression")

let argumentListSpec = Spec[ArgumentList](
  name: "argument_list",
  parseFn: proc(parser: Parser): Result[ArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("argument_list", "(",
    separatedBy(expressionSpec, commaWithSpacesSpec), ")"))
  ok(newArgumentList(args, loc))
)

let functionCallSpec = Spec[FunctionCall](
  name: "function_call",
  parseFn: proc(parser: Parser): Result[FunctionCall, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let funcNameIdent = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let argList = ? parser.run(argumentListSpec)
  ok(newFunctionCall(argType, funcNameIdent, argList))
)

let kwargSpec = Spec[KeywordArgument](
  name: "keyword_argument",
  parseFn: proc(parser: Parser): Result[KeywordArgument, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newKeywordArgument(name, expression, name.loc))
)

let kwargListSpec = Spec[KeywordArgumentList](
  name: "keyword_argument_list",
  parseFn: proc(parser: Parser): Result[KeywordArgumentList, ParserError] =
  let loc = parser.loc
  let args = ? parser.run(contained("keyword_argument_list", "{",
    separatedBy(kwargSpec, commaWithSpacesSpec), "}"))
  newKeywordArgumentList(args, loc)
)

# digit+
let unsignedIntegerLiteralSpec = Spec[UnsignedIntegerLiteral](
  name: "unsigned_integer_literal",
  parseFn: proc(parser: Parser): Result[UnsignedIntegerLiteral, ParserError] =
  let loc = parser.loc
  let digits = ? parser.run(atLeastOne(digitSpec))
  var value: string
  for d in digits: value.add(d.value)
  ok(newUnsignedIntegerLiteral(value, loc))
)

# (+ | -) digit+
let signedIntegerLiteralSpec = Spec[SignedIntegerLiteral](
  name: "signed_integer_literal",
  parseFn: proc(parser: Parser): Result[SignedIntegerLiteral, ParserError] =
  let signToken = ? parser.run(oneOf("sign", [
    punctuationSpec("+"),
    punctuationSpec("-"),
  ]))
  let uint = ? parser.run(unsignedIntegerLiteralSpec)
  ok(newSignedIntegerLiteral(signToken.value, uint, signToken.loc))
)

let integerLiteralSpec = oneOf("integer_literal", [
  signedIntegerLiteralSpec.map("signed_int",
    proc(v: SignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
  unsignedIntegerLiteralSpec.map("unsigned_int",
    proc(v: UnsignedIntegerLiteral): IntegerLiteral = newIntegerLiteral(v)),
])

# (+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?
# Must have either decimal part or exponent to distinguish from integer
let floatLiteralSpec = Spec[FloatLiteral](
  name: "float_literal",
  parseFn: proc(parser: Parser): Result[FloatLiteral, ParserError] =
  let loc = parser.loc
  var value: string
  let signSpec = oneOf("sign", [punctuationSpec("+"), punctuationSpec("-")])
  # Optional sign
  let maybeSign = parser.run(signSpec)
  if maybeSign.isOk: value.add(maybeSign.get.value)
  # Integer part (required)
  let intDigits = ? parser.run(atLeastOne(digitSpec))
  for d in intDigits: value.add(d.value)
  # Decimal part (optional)
  var hasDecimal = false
  let maybeDot = parser.run(punctuationSpec("."))
  if maybeDot.isOk:
    hasDecimal = true
    value.add(".")
    let fracDigits = ? parser.run(atLeastOne(digitSpec))
    for d in fracDigits: value.add(d.value)
  # Exponent part (optional)
  var hasExponent = false
  let maybeE = parser.run(oneOf("exponent", [
    alphabetSpec, alphabetSpec,
  ]))
  if maybeE.isOk and (maybeE.get.value == "e" or maybeE.get.value == "E"):
    hasExponent = true
    value.add(maybeE.get.value)
    let maybeExpSign = parser.run(signSpec)
    if maybeExpSign.isOk: value.add(maybeExpSign.get.value)
    let expDigits = ? parser.run(atLeastOne(digitSpec))
    for d in expDigits: value.add(d.value)
  # Must have at least decimal or exponent to be a float
  if not hasDecimal and not hasExponent:
    return err(newParserError("expected '.' or 'e' for float literal", loc))
  ok(newFloatLiteral(value, loc))
)

let literalSpec = oneOf("literal", [
  stringLiteralSpec.map("string_literal",
    proc(v: StringLiteral): Literal = newLiteral(v)),
  floatLiteralSpec.map("float_literal",
    proc(v: FloatLiteral): Literal = newLiteral(v)),
  integerLiteralSpec.map("integer_literal",
    proc(v: IntegerLiteral): Literal = newLiteral(v)),
])

# Type.Variant { fields }
let unionInitializerSpec = Spec[UnionInitializer](
  name: "union_initializer",
  parseFn: proc(parser: Parser): Result[UnionInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard ? parser.run(punctuationSpec("."))
  let variantName = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let kwargList = ? parser.run(kwargListSpec)
  ok(newUnionInitializer(argType, variantName, kwargList, argType.loc))
)

# Type { fields }
let structInitializerSpec = Spec[StructInitializer](
  name: "struct_initializer",
  parseFn: proc(parser: Parser): Result[StructInitializer, ParserError] =
  let argType = ? parser.run(argumentTypeSpec)
  discard parser.run(optionalSpace)
  let kwargList = ? parser.run(kwargListSpec)
  ok(newStructInitializer(argType, kwargList, argType.loc))
)

# type literal
let literalInitializerSpec = Spec[LiteralInitializer](
  name: "literal_initializer",
  parseFn: proc(parser: Parser): Result[LiteralInitializer, ParserError] =
  let typeName = ? parser.run(identifierSpec)
  discard ? parser.run(strictSpace)
  let value = ? parser.run(literalSpec)
  ok(newLiteralInitializer(typeName, value, typeName.loc))
)

let initializerSpec = oneOf("initializer", [
  unionInitializerSpec.map("union",
    proc(v: UnionInitializer): Initializer = newInitializer(v)),
  structInitializerSpec.map("struct",
    proc(v: StructInitializer): Initializer = newInitializer(v)),
  literalInitializerSpec.map("literal",
    proc(v: LiteralInitializer): Initializer = newInitializer(v)),
])

let getterSpec = Spec[Getter](
  name: "getter",
  parseFn: proc(parser: Parser): Result[Getter, ParserError] =
  let source = ? parser.run(identifierSpec)
  discard ? parser.run(punctuationSpec("."))
  let property = ? parser.run(identifierSpec)
  ok(newGetter(source, property, source.loc))
)

expressionSpec.parseFn = oneOf("expression", [
  literalSpec.map("literal_expression",
    proc(v: Literal): Expression = newExpression(v)),
  initializerSpec.map("initializer_expression",
    proc(v: Initializer): Expression = newExpression(v)),
  functionCallSpec.map("fncall_expression",
    proc(v: FunctionCall): Expression = newExpression(v)),
  getterSpec.map("getter_expression",
    proc(v: Getter): Expression = newExpression(v)),
  identifierSpec.map("variable_expression",
    proc(v: Identifier): Expression = newExpression(v)),
]).parseFn

let equalsSeparatorSpec = separatorSpec("=")

let assignmentSpec = Spec[Assignment](
  name: "assignment",
  parseFn: proc(parser: Parser): Result[Assignment, ParserError] =
  let targetIdent = ? parser.run(identifierSpec)
  discard ? parser.run(equalsSeparatorSpec)
  let expression = ? parser.run(expressionSpec)
  ok(newAssignment(targetIdent, expression, targetIdent.loc))
)

let decoratorLineSpec = Spec[Decorator](
  name: "decorator_line",
  parseFn: proc(parser: Parser): Result[Decorator, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(strictLine)
  ok(newDecorator(name))
)

# Block without decorator support (case, struct, union, generic)
proc blockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    # After header succeeds, body errors are fatal — they propagate
    # through run and any without backtracking or being swallowed.
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(h, bodyResult.get))
  )

# Block without decorator support (case, struct, union, generic)
proc blockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(h: H, b: B): Result[R, ParserError]): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    # After header succeeds, body errors are fatal — they propagate
    # through run and any without backtracking or being swallowed.
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    combine(h, bodyResult.get)
  )

# Block with decorator support (module, function)
proc decoratedBlockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(decorators: seq[Decorator], h: H, b: B): R): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    let decorators = ? parser.run(any(decoratorLineSpec))
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    ok(combine(decorators, h, bodyResult.get))
  )

# Block with decorator support (module, function)
proc decoratedBlockSpec[H, B, R](name: string,
    header: Spec[H], body: Spec[B],
    combine: proc(decorators: seq[Decorator], h: H, b: B): Result[R,
        ParserError]): Spec[R] =
  Spec[R](
    name: name,
    parseFn: proc(parser: Parser): Result[R, ParserError] =
    let decorators = ? parser.run(any(decoratorLineSpec))
    discard ? parser.run(indentationSpec)
    let h = ? parser.run(header)
    discard ? parser.run(strictLine)
    parser.level += 1
    let bodyResult = body.parseFn(parser)
    parser.level -= 1
    if bodyResult.isErr:
      bodyResult.error.fatal = true
      return err(bodyResult.error)
    combine(decorators, h, bodyResult.get)
  )

# Variant pattern field: name ":" binding (both identifiers)
let variantPatternFieldSpec = Spec[VariantPatternField](
  name: "variant_pattern_field",
  parseFn: proc(parser: Parser): Result[VariantPatternField, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let binding = ? parser.run(identifierSpec)
  ok(newVariantPatternField(name, binding, name.loc))
)

# Variant pattern: VariantName { field: binding, field: binding }
let variantPatternSpec = Spec[VariantPattern](
  name: "variant_pattern",
  parseFn: proc(parser: Parser): Result[VariantPattern, ParserError] =
  let name = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let fields = ? parser.run(contained("variant_fields", "{",
    separatedBy(variantPatternFieldSpec, commaWithSpacesSpec), "}"))
  newVariantPattern(name, fields, name.loc)
)

let casePatternSpec = oneOf("case_pattern", [
  integerLiteralSpec.map("integer_pattern",
    proc(v: IntegerLiteral): CasePattern = newCasePattern(v)),
  variantPatternSpec.map("variant_pattern",
    proc(v: VariantPattern): CasePattern = newCasePattern(v)),
  identifierSpec.map("variable_pattern",
    proc(v: Identifier): CasePattern = newCasePattern(v)),
])

# Forward declare statementListSpec for mutual recursion:
# match -> caseBlock -> statementList -> statementLine -> statement -> match
let statementListSpec = newSpec[StatementList]("statement_list")

let caseHeaderSpec = Spec[CasePattern](
  name: "case_header",
  parseFn: proc(parser: Parser): Result[CasePattern, ParserError] =
  discard ? parser.run(keywordSpec("case"))
  discard ? parser.run(strictSpace)
  let pattern = ? parser.run(casePatternSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(pattern)
)

proc loc(pattern: CasePattern): Location =
  case pattern.kind:
  of cpkIntegerLiteral:
    case pattern.intLit.kind:
    of ilkSigned: pattern.intLit.signed.loc
    of ilkUnsigned: pattern.intLit.unsigned.loc
  of cpkVariable: pattern.variable.loc
  of cpkVariant: pattern.variant.loc

let caseBlockSpec = blockSpec("case", caseHeaderSpec, statementListSpec,
  proc(h: CasePattern, b: StatementList): CaseBlock =
  newCaseBlock(h, b, h.loc))

let inlineStatementSpec = oneOf("inline_statement", [
  assignmentSpec.map("assignment_statement",
    proc(v: Assignment): Statement = newStatement(v)),
  expressionSpec.map("expression_statement",
    proc(v: Expression): Statement = newStatement(v)),
])

# Match body: parses "match" keyword + subject + ":" + newline + caseBlocks
# Does NOT consume indentation — caller handles that
let matchBodySpec = Spec[MatchExpression](
  name: "match_body",
  parseFn: proc(parser: Parser): Result[MatchExpression, ParserError] =
  let loc = ? parser.run(keywordSpec("match"))
  discard ? parser.run(strictSpace)
  # Match expressions cannot be the subject of another match expression.
  # expressionSpec intentionally excludes match (match is parsed separately
  # in statementLineSpec). This check guards against future changes that
  # might add match to expressionSpec.
  let subject = ? parser.run(expressionSpec)
  if subject.kind == ekMatch:
    return err(newParserError(
      "match expression cannot be the subject of another match", loc))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  discard ? parser.run(strictLine)
  parser.level += 1
  let casesBody = atLeastOne(Spec[CaseBlock](
    name: "case_block_line",
    parseFn: proc(parser: Parser): Result[CaseBlock, ParserError] =
    discard parser.run(optionalLines)
    let cb = ? parser.run(caseBlockSpec)
    ok(cb)
  ))
  let casesResult = casesBody.parseFn(parser)
  parser.level -= 1
  if casesResult.isErr:
    casesResult.error.fatal = true
    return err(casesResult.error)
  ok(newMatchExpression(subject, casesResult.get, loc))
)

let statementLineSpec = Spec[Statement](
  name: "statement_line",
  parseFn: proc(parser: Parser): Result[Statement, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  # Try match assignment: identifier = match ...:
  let maybeMatchAssign = parser.run(Spec[Statement](
    name: "match_assignment",
    parseFn: proc(parser: Parser): Result[Statement, ParserError] =
    let target = ? parser.run(identifierSpec)
    discard ? parser.run(equalsSeparatorSpec)
    let matchExpr = ? parser.run(matchBodySpec)
    ok(newStatement(newAssignment(target, newExpression(matchExpr), target.loc)))
  ))
  if maybeMatchAssign.isOk: return ok(maybeMatchAssign.get)
  # Try standalone match: match ...:
  let maybeMatch = parser.run(matchBodySpec)
  if maybeMatch.isOk:
    return ok(newStatement(newExpression(maybeMatch.get)))
  # Inline statements: statement + newline
  let statement = ? parser.run(inlineStatementSpec)
  discard ? parser.run(strictLine)
  ok(statement)
)

statementListSpec.parseFn = atLeastOne(statementLineSpec).map("statement_list",
  proc(stmts: seq[Statement]): StatementList = newStatementList(stmts)).parseFn

let functionSpec = decoratedBlockSpec("function", functionDefinitionSpec,
  statementListSpec,
  proc(d: seq[Decorator], h: FunctionDefinition, b: StatementList): Function =
  newFunction(d, h, b))

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let funcBlockSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(optionalLines)
  let f = ? parser.run(functionSpec)
  ok(f)
)

let functionListSpec = any(funcBlockSpec).map("function_list",
  proc(fns: seq[Function]): Result[FunctionList, ParserError] = newFunctionList(fns))

type ModuleHeader = tuple[name: Identifier, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(strictSpace)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent, loc))
)

type GenericHeader = tuple[name: Identifier, loc: Location]

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(strictSpace)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok((nameIdent, loc))
)

# Function definition line: indentation + function signature + newline
let functionDefinitionLineSpec = Spec[FunctionDefinition](
  name: "function_definition_line",
  parseFn: proc(parser: Parser): Result[FunctionDefinition, ParserError] =
  discard ? parser.run(indentationSpec)
  let funcDef = ? parser.run(functionDefinitionSpec)
  discard ? parser.run(strictLine)
  ok(funcDef)
)

let functionDefinitionListSpec = atLeastOne(functionDefinitionLineSpec)

let genericSpec = blockSpec("generic", genericHeaderSpec,
  functionDefinitionListSpec,
  proc(h: GenericHeader, b: seq[FunctionDefinition]): Result[Generic, ParserError] =
  newGeneric(@[], h.name, b, h.loc))

# struct: field+ (field is identifier ":" argumentType)
let structHeaderSpec = Spec[Location](
  name: "struct_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("struct"))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

# Each field line: indentation + argumentDefinition + newline
let fieldLineSpec = Spec[ArgumentDefinition](
  name: "field_line",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  let argDef = ? parser.run(argumentDefinitionSpec)
  discard ? parser.run(strictLine)
  ok(argDef)
)

let structSpec = blockSpec("struct", structHeaderSpec,
  atLeastOne(fieldLineSpec),
  proc(h: Location, b: seq[ArgumentDefinition]): Result[Struct, ParserError] =
  newStruct(b, h))

# union: variant+ (variant is identifier space* ("{" argDef, argDef "}")?)
let variantDefinitionLineSpec = Spec[VariantDefinition](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDefinition, ParserError] =
  discard parser.run(optionalLines)
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(optionalSpace)
  let maybeFields = ? parser.run(optional(contained("variant_fields", "{",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), "}")))
  var fields: seq[ArgumentDefinition]
  if maybeFields.isSome: fields = maybeFields.get
  discard ? parser.run(strictLine)
  newVariantDefinition(name, fields, name.loc)
)

let unionHeaderSpec = Spec[Location](
  name: "union_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("union"))
  discard parser.run(optionalSpace)
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

let unionSpec = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefinitionLineSpec),
  proc(h: Location, b: seq[VariantDefinition]): Result[Union, ParserError] =
  newUnion(b, h))

let dataBlockSpec = oneOf("data_block", [
  structSpec.map("struct_data",
    proc(v: Struct): DataBlock = newDataBlock(v)),
  unionSpec.map("union_data",
    proc(v: Union): DataBlock = newDataBlock(v)),
])

# Module body: optional data block + function list
type ModuleBody = tuple[data: Option[DataBlock], funcList: FunctionList]

let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  let data = ? parser.run(optional(dataBlockSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((data, funcList))
)

let moduleSpec = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Result[Module, ParserError] =
  newModule(d, h.name, b.data, b.funcList, h.loc))

let fileItemSpec = oneOf("file_item", [
  moduleSpec.map("module_item",
    proc(v: Module): FileItem = newFileItem(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): FileItem = newFileItem(v)),
])

# import { Name, Name } from "path"
# identifier ("as" identifier)?
let importNameSpec = Spec[ImportName](
  name: "import_name",
  parseFn: proc(parser: Parser): Result[ImportName, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(strictSpace)
  if maybeAs.isErr:
    return ok(newImportName(name, none(Identifier), name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportName(name, none(Identifier), name.loc))
  discard ? parser.run(strictSpace)
  let alias = ? parser.run(identifierSpec)
  ok(newImportName(name, some(alias), name.loc))
)

let importLineSpec = Spec[Import](
  name: "import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(strictSpace)
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importNameSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(strictSpace)
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(strictSpace)
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(strictLine)
  let maybePath = resolveImportPath(source.value, parser.filepath)
  if maybePath.isOk:
    newImport(names, source.value, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

let importBlockSpec = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(optionalLines)
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)

let fileItemBlockSpec = Spec[FileItem](
  name: "file_item_block",
  parseFn: proc(parser: Parser): Result[FileItem, ParserError] =
  discard parser.run(optionalLines)
  let item = ? parser.run(fileItemSpec)
  ok(item)
)

# file: import* (module | generic)*
let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let imports = ? parser.run(any(importBlockSpec))
  let items = ? parser.run(any(fileItemBlockSpec))
  discard parser.run(optionalLines)
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(fileItemSpec)
  newFile(parser.filepath, imports, items)
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)
