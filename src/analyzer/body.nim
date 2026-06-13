## Body-level analysis: variables, getters, function calls,
## initializers, match/case blocks, expressions, statements,
## assignments, mutations — the mutually-recursive cluster that
## walks function bodies.
##
## Every type that participates in the cycle (Initializer <->
## FunctionCall <-> Expression <-> Match/CaseBlock <-> Statement <->
## Assignment/Mutation/KeywordArgument) lives in a single type block —
## Nim only resolves cross-references inside one block.
## Constructors, accessors, and analyze* procs follow the type block
## in per-concept order (matching the original funcs.nim layout).

import results, tables, strformat, sequtils, options, strutils

import tokenizer
import parser
import resolver
import argtypes
import literals
import data
import funcdefs
import funcrefs
import patterns

# AnalyzedVariable — independent of the big cluster.
type AnalyzedVariable* = ref object
  name: Identifier
  argType: AnalyzedArgumentType

proc newAnalyzedVariable*(name: Identifier, argType: AnalyzedArgumentType): AnalyzedVariable =
  AnalyzedVariable(name: name, argType: argType)

proc loc*(variable: AnalyzedVariable): Location = variable.name.loc
proc name*(variable: AnalyzedVariable): Identifier = variable.name
proc argType*(variable: AnalyzedVariable): AnalyzedArgumentType = variable.argType

proc analyzeVariable*(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

# AnalyzedGetter — independent of the big cluster.
type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  argType: AnalyzedArgumentType
  property: AnalyzedArgumentDefinition

proc newAnalyzedGetter*(resolved: ResolvedGetter, argType: AnalyzedArgumentType, property: AnalyzedArgumentDefinition): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, argType: argType, property: property)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc resolved*(getter: AnalyzedGetter): ResolvedGetter = getter.resolved
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.argType
proc property*(getter: AnalyzedGetter): AnalyzedArgumentDefinition = getter.property

proc analyzeGetter*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedArgType = funcScope[getter.source]
    let struct = ? defScope.extractStructFor(analyzedArgType, getter.loc)
    let analyzedProperty = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedArgType, analyzedProperty))

# Mutually-recursive body-level cluster — every type that cycles
# back to AnalyzedExpression / AnalyzedStatement must live here.
type
  AnalyzedFunctionCall* = ref object
    resolved: ResolvedFunctionCall
    fnref: AnalyzedFunctionRef
    args: seq[AnalyzedExpression]
    returns: AnalyzedArgumentType

  AnalyzedKeywordArgument* = ref object
    # todo: add a concrete type
    resolved: ResolvedKeywordArgument
    field: AnalyzedArgumentDefinition
    expression: AnalyzedExpression

  AnalyzedStructInitializer* = ref object
    resolved: ResolvedStructInitializer
    argType: AnalyzedArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    argType: AnalyzedArgumentType
    variant: AnalyzedVariant
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedInitializerKind* = enum
    aikUnion, aikStruct
  AnalyzedInitializer* = ref object
    case kind: AnalyzedInitializerKind
    of aikUnion: union: AnalyzedUnionInitializer
    of aikStruct: struct: AnalyzedStructInitializer

  AnalyzedCaseBlock* = ref object
    resolved: ResolvedCaseBlock
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]

  AnalyzedMatchExpression* = ref object
    resolved: ResolvedMatchExpression
    subject: AnalyzedExpression
    cases: seq[AnalyzedCaseBlock]
    returns: AnalyzedArgumentType

  AnalyzedAssignment* = ref object
    resolved: ResolvedAssignment
    expression: AnalyzedExpression

  AnalyzedMutation* = ref object
    resolved: ResolvedMutation
    getter: AnalyzedGetter
    expression: AnalyzedExpression

  AnalyzedExpressionKind* = enum
    aekVariable, aekFunctionCall, aekLiteral, aekMatchExpr, aekInitializer, aekGetter
  AnalyzedExpression* = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekLiteral: literal: Literal
    of aekMatchExpr: match: AnalyzedMatchExpression
    of aekInitializer: init: AnalyzedInitializer
    of aekGetter: getter: AnalyzedGetter

  AnalyzedStatementKind* = enum
    askExpr, askAssignment, askMutation
  AnalyzedStatement* = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression
    of askAssignment: assignment: AnalyzedAssignment
    of askMutation: mutation: AnalyzedMutation

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType]
proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType]

# TODO: accepts returns field once function call resolution is complete
proc newAnalyzedFunctionCall*(resolved: ResolvedFunctionCall, fnref: AnalyzedFunctionRef, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, fnref: fnref, args: args, returns: returns)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc
proc resolved*(fncall: AnalyzedFunctionCall): ResolvedFunctionCall = fncall.resolved
proc fnref*(fncall: AnalyzedFunctionCall): AnalyzedFunctionRef = fncall.fnref
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType = fncall.returns

proc newAnalyzedKeywordArgument*(resolved: ResolvedKeywordArgument, field: AnalyzedArgumentDefinition, expression: AnalyzedExpression): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(resolved: resolved, field: field, expression: expression)

proc resolved*(kwarg: AnalyzedKeywordArgument): ResolvedKeywordArgument = kwarg.resolved
proc field*(kwarg: AnalyzedKeywordArgument): AnalyzedArgumentDefinition = kwarg.field
proc expression*(kwarg: AnalyzedKeywordArgument): AnalyzedExpression = kwarg.expression

proc newAnalyzedStructInitializer*(resolved: ResolvedStructInitializer, argType: AnalyzedArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, argType: argType, kwargs: kwargs)

proc resolved*(struct: AnalyzedStructInitializer): ResolvedStructInitializer = struct.resolved
proc argType*(struct: AnalyzedStructInitializer): AnalyzedArgumentType = struct.argType
proc kwargs*(struct: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = struct.kwargs

proc newAnalyzedUnionInitializer*(resolved: ResolvedUnionInitializer, argType: AnalyzedArgumentType, variant: AnalyzedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, argType: argType, variant: variant, kwargs: kwargs)

proc resolved*(init: AnalyzedUnionInitializer): ResolvedUnionInitializer = init.resolved
proc argType*(init: AnalyzedUnionInitializer): AnalyzedArgumentType = init.argType
proc variant*(init: AnalyzedUnionInitializer): AnalyzedVariant = init.variant
proc kwargs*(init: AnalyzedUnionInitializer): seq[AnalyzedKeywordArgument] = init.kwargs

proc newAnalyzedInitializer*(union: AnalyzedUnionInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikUnion, union: union)

proc newAnalyzedInitializer*(struct: AnalyzedStructInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikStruct, struct: struct)

proc kind*(init: AnalyzedInitializer): AnalyzedInitializerKind = init.kind
proc union*(init: AnalyzedInitializer): AnalyzedUnionInitializer =
  assert init.kind == aikUnion,
    fmt"AnalyzedInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: AnalyzedInitializer): AnalyzedStructInitializer =
  assert init.kind == aikStruct,
    fmt"AnalyzedInitializer.struct accessed but kind is {init.kind}"
  init.struct

proc argType*(init: AnalyzedInitializer): AnalyzedArgumentType =
  case init.kind:
  of aikUnion: init.union.argType
  of aikStruct: init.struct.argType

proc loc*(init: AnalyzedInitializer): Location =
  case init.kind:
  of aikUnion: init.union.resolved.loc
  of aikStruct: init.struct.resolved.loc

proc newAnalyzedCaseBlock*(resolved: ResolvedCaseBlock, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(resolved: resolved, pattern: pattern, statements: statements)

proc loc*(caseBlock: AnalyzedCaseBlock): Location = caseBlock.resolved.loc
proc resolved*(caseBlock: AnalyzedCaseBlock): ResolvedCaseBlock = caseBlock.resolved
proc pattern*(caseBlock: AnalyzedCaseBlock): AnalyzedCasePattern = caseBlock.pattern
proc statements*(caseBlock: AnalyzedCaseBlock): seq[AnalyzedStatement] = caseBlock.statements

proc argType*(caseBlock: AnalyzedCaseBlock): Option[AnalyzedArgumentType] =
  assert(caseBlock.statements.len > 0, "UNREACHABLE: should have been caught by resolver")
  caseBlock.statements[^1].argType

proc newAnalyzedMatchExpression*(resolved: ResolvedMatchExpression, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock], returns: AnalyzedArgumentType): AnalyzedMatchExpression =
  AnalyzedMatchExpression(resolved: resolved, subject: subject, cases: cases, returns: returns)

proc loc*(m: AnalyzedMatchExpression): Location = m.resolved.loc
proc resolved*(m: AnalyzedMatchExpression): ResolvedMatchExpression = m.resolved
proc subject*(m: AnalyzedMatchExpression): AnalyzedExpression = m.subject
proc cases*(m: AnalyzedMatchExpression): seq[AnalyzedCaseBlock] = m.cases
proc returns*(m: AnalyzedMatchExpression): AnalyzedArgumentType = m.returns

proc newAnalyzedAssignment*(resolved: ResolvedAssignment, expression: AnalyzedExpression): AnalyzedAssignment =
  AnalyzedAssignment(resolved: resolved, expression: expression)

proc loc*(assignment: AnalyzedAssignment): Location = assignment.resolved.loc
proc resolved*(assignment: AnalyzedAssignment): ResolvedAssignment = assignment.resolved
proc target*(assignment: AnalyzedAssignment): Identifier = assignment.resolved.target
proc expression*(assignment: AnalyzedAssignment): AnalyzedExpression = assignment.expression
proc argType*(assignment: AnalyzedAssignment): Option[AnalyzedArgumentType] = assignment.expression.argType

proc newAnalyzedMutation*(resolved: ResolvedMutation, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedMutation =
  AnalyzedMutation(resolved: resolved, getter: getter, expression: expression)

proc loc*(mutation: AnalyzedMutation): Location = mutation.resolved.loc
proc resolved*(mutation: AnalyzedMutation): ResolvedMutation = mutation.resolved
proc getter*(mutation: AnalyzedMutation): AnalyzedGetter = mutation.getter
proc expression*(mutation: AnalyzedMutation): AnalyzedExpression = mutation.expression
proc argType*(mutation: AnalyzedMutation): Option[AnalyzedArgumentType] = mutation.expression.argType

proc newAnalyzedExpression*(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression*(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression*(literal: Literal): AnalyzedExpression =
  AnalyzedExpression(kind: aekLiteral, literal: literal)

proc newAnalyzedExpression*(match: AnalyzedMatchExpression): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr, match: match)

proc newAnalyzedExpression*(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: aekInitializer, init: init)

proc newAnalyzedExpression*(getter: AnalyzedGetter): AnalyzedExpression =
  AnalyzedExpression(kind: aekGetter, getter: getter)

proc kind*(expression: AnalyzedExpression): AnalyzedExpressionKind = expression.kind
proc variable*(expression: AnalyzedExpression): AnalyzedVariable =
  assert expression.kind == aekVariable,
    fmt"AnalyzedExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc fncall*(expression: AnalyzedExpression): AnalyzedFunctionCall =
  assert expression.kind == aekFunctionCall,
    fmt"AnalyzedExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc literal*(expression: AnalyzedExpression): Literal =
  assert expression.kind == aekLiteral,
    fmt"AnalyzedExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: AnalyzedExpression): AnalyzedMatchExpression =
  assert expression.kind == aekMatchExpr,
    fmt"AnalyzedExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: AnalyzedExpression): AnalyzedInitializer =
  assert expression.kind == aekInitializer,
    fmt"AnalyzedExpression.init accessed but kind is {expression.kind}"
  expression.init
proc getter*(expression: AnalyzedExpression): AnalyzedGetter =
  assert expression.kind == aekGetter,
    fmt"AnalyzedExpression.getter accessed but kind is {expression.kind}"
  expression.getter

proc loc*(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: return expression.fncall.loc
  of aekVariable: return expression.variable.loc
  of aekLiteral: return expression.literal.loc
  of aekGetter: return expression.getter.loc
  of aekMatchExpr: return expression.match.loc
  of aekInitializer: return expression.init.loc

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekLiteral: return none(AnalyzedArgumentType)
  of aekFunctionCall: return some(expression.fncall.returns)
  of aekVariable: return some(expression.variable.argType)
  of aekMatchExpr: return some(expression.match.returns)
  of aekInitializer: return some(expression.init.argType)
  of aekGetter: return some(expression.getter.argType)

proc newAnalyzedStatement*(expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(kind: askExpr, expression: expression)

proc newAnalyzedStatement*(assignment: AnalyzedAssignment): AnalyzedStatement =
  AnalyzedStatement(kind: askAssignment, assignment: assignment)

proc newAnalyzedStatement*(mutation: AnalyzedMutation): AnalyzedStatement =
  AnalyzedStatement(kind: askMutation, mutation: mutation)

proc kind*(statement: AnalyzedStatement): AnalyzedStatementKind = statement.kind
proc expression*(statement: AnalyzedStatement): AnalyzedExpression =
  assert statement.kind == askExpr,
    fmt"AnalyzedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: AnalyzedStatement): AnalyzedAssignment =
  assert statement.kind == askAssignment,
    fmt"AnalyzedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc mutation*(statement: AnalyzedStatement): AnalyzedMutation =
  assert statement.kind == askMutation,
    fmt"AnalyzedStatement.mutation accessed but kind is {statement.kind}"
  statement.mutation

proc loc*(statement: AnalyzedStatement): Location =
  case statement.kind:
  of askExpr: statement.expression.loc
  of askAssignment: statement.assignment.loc
  of askMutation: statement.mutation.loc

proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType] =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType
  of askMutation: statement.mutation.argType

proc arg*(statement: AnalyzedStatement): Option[AnalyzedArgumentDefinition] =
  let maybeArgType = statement.argType
  if maybeArgType.isNone:
    assert(maybeArgType.isSome, fmt"{statement.loc} todo: support argType for statement")
  else:
    case statement.kind:
    of askExpr: return none(AnalyzedArgumentDefinition)
    of askMutation: return none(AnalyzedArgumentDefinition)
    of askAssignment: return some(newAnalyzedArgumentDefinition(maybeArgType.get, statement.assignment.target))

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType): Result[void, string] =
  if defType.module != valType.module:
    err(fmt"{valType.loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defImpl, valImpl)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedDefinedArgumentType): Result[void, string] =
  case valType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.module)
    ok()
  of adatkGeneric:
    err(fmt"{valType.loc} todo: analyze generic value type against module argument type")

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case valType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze imported value type against module argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.definedType)
    ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkImported:
      return err(fmt"{valType.loc} todo: analyze imported impl type")
    of aatkDefined:
      case valType.definedType.kind:
      of adatkGeneric:
        let maybeConcreteFuncDef = valType.definedType.generic.resolved.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{valType.loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
      of adatkModule:
        let maybeConcreteFuncDef = valType.definedType.module.module.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{valType.loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  ok()

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of adatkModule:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.module, valType)
    ok()
  of adatkGeneric:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.generic, valType)
    ok()

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType): Result[void, string] =
  case defType.kind:
  of aatkImported:
    err(fmt"{valType.loc} todo: analyze value type against imported argument type")
  of aatkDefined:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.definedType, valType)
    ok()

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[void, string] =
  # BUG: `zip` below silently truncates to the shorter sequence — if
  # funcDef.args.len != argValues.len the type-check walks only the common
  # prefix and reports success. Today the resolver's arity check prevents
  # this from being reachable, but the defensive assert traps the mismatch
  # if overload selection is ever wired wrong upstream.
  assert(funcDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {funcDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  for (argDef, argValue) in zip(funcDef.args, argValues):
    if argValue.argType.isNone:
      return err(fmt"{argValue.loc} todo: analyze function call literal argument")
    else:
      ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, argDef.argType, argValue.argType.get)
  ok()

proc analyzeArgumentList(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcRef: AnalyzedFunctionRef, analyzedArgs: seq[AnalyzedExpression]): Result[AnalyzedFunctionDefinition, string] =
  var matches: seq[AnalyzedFunctionDefinition]
  for funcDef in funcRef.funcDefs:
    if analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, analyzedArgs, funcDef).isOk:
      matches.add(funcDef)

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
      for funcDef in funcRef.funcDefs:
        message.add("\t" & fmt"{funcDef.loc}")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
      for funcDef in matches:
        message.add("\t" & fmt"{funcDef.loc}")
    err(message.join("\n"))

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let funcRef = ? analyzeFunctionRef(app, file, fileScope, module, defScope, fncall.funcRef)
  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  let matchingFuncDef = ? analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, fncall, funcRef, analyzedArgs)
  # TODO: find a way to compute concrete return type for now just passing along the funcDef.returns
  ok(newAnalyzedFunctionCall(fncall, funcRef, analyzedArgs, matchingFuncDef.returns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  if expected.isNone:
    return err(fmt"{cases[0].loc} todo: handle case block returning literal type")
  for c in cases:
    if c.argType.isNone:
      return err(fmt"{c.loc} todo: handle case block returning literal type")
    if c.argType.get != expected.get:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralBlock): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal.resolved, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, defScope, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, match.subject)
  if analyzedSubjectExpr.argType.isNone:
    err(fmt"{analyzedSubjectExpr.loc} todo: analyze case blocks for literal expression")
  else:
    let analyzedSubjectDataType = ? defScope.extractDataBlock(analyzedSubjectExpr.argType.get, analyzedSubjectExpr.loc)
    case analyzedSubjectDataType.kind:
    of adkStruct:
      let moduleName = analyzedSubjectExpr.argType.get.name
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{moduleName.asl}` a struct type")
    of adkLiteral:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.literal)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, defScope, funcScope, match.cases, analyzedSubjectDataType.union)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: AnalyzedArgumentDefinition): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, kwarg.expression)
  if analyzedExpression.argType.isNone:
    let fieldModule = ? defScope.findModuleDef(analyzedField.argType, kwarg.expression.loc)
    let fieldModuleData = ? defScope.extractDataBlock(fieldModule, kwarg.expression.loc)
    case fieldModuleData.kind:
    of adkStruct:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a struct value but found literal")
    of adkUnion:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a union value but found literal")
    of adkLiteral:
      let literalField = fieldModuleData.literal
      case literalField.resolved:
      of rltkU8: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U8 literal argument")
      of rltkU16: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U16 literal argument")
      of rltkU32: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U32 literal argument")
      of rltkU64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer U64 literal argument")
      of rltkI8: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I8 literal argument")
      of rltkI16: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I16 literal argument")
      of rltkI64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer I64 literal argument")
      of rltkF32: err(fmt"{kwarg.expression.loc} todo: analyze union initializer F32 literal argument")
      of rltkF64: err(fmt"{kwarg.expression.loc} todo: analyze union initializer F64 literal argument")
      of rltkPointer: err(fmt"{kwarg.expression.loc} todo: analyze union initializer Pointer literal argument")
      of rltkString:
        case analyzedExpression.literal.kind:
        of lkFloat: err(fmt"{kwarg.expression.loc} expected a valid string literal but found float")
        of lkInteger: err(fmt"{kwarg.expression.loc} expected a valid string literal but found integer")
        of lkString: ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
      of rltkI32:
        case analyzedExpression.literal.kind:
        of lkFloat: err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found float")
        of lkString: err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found string")
        of lkInteger:
          let maybeParsedInt = parseInteger[int32](analyzedExpression.literal.asl)
          if maybeParsedInt.isNone:
            err(fmt"{kwarg.expression.loc} expected a valid 32-bit signed integer but found `{analyzedExpression.literal.asl}`")
          else:
            ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
  else:
    ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, analyzedField.argType, analyzedExpression.argType.get)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let union = ? defScope.extractUnionFor(analyzedArgType, init.loc)
  let analyzedVariant = ? union.findVariant(init.variant)
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField: AnalyzedArgumentDefinition = ? analyzedVariant.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, defScope, funcScope, kwarg, analyzedField)
    analyzedKwargs.add(analyzedKwarg)
  ok(newAnalyzedUnionInitializer(init, analyzedArgType, analyzedVariant, analyzedKwargs))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let struct = ? defScope.extractStructFor(analyzedArgType, init.loc)
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField = ? struct.findField(kwarg.name)
    let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, defScope, funcScope, kwarg, analyzedField)
    analyzedKwargs.add(analyzedKwarg)
  ok(newAnalyzedStructInitializer(init, analyzedArgType, analyzedKwargs))

proc analyzeInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    err(fmt"{init.loc} todo: analyze literal initializer")
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(app, file, fileScope, module, defScope, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(app, file, fileScope, module, defScope, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, defScope, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, module, defScope, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, module, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeMutation*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, mutation: ResolvedMutation): Result[AnalyzedMutation, string] =
  let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, defScope, funcScope, mutation.getter)
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, mutation.expression)
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedMutation(mutation, analyzedGetter, analyzedExpression))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, module, defScope, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskMutation:
    let analyzedMutation = ? analyzeMutation(app, file, fileScope, module, defScope, funcScope, statement.mutation)
    ok(newAnalyzedStatement(analyzedMutation))
