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
import modules
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
  source: AnalyzedArgumentType
  property: AnalyzedArgumentDefinition

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedArgumentType, property: AnalyzedArgumentDefinition): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc resolved*(getter: AnalyzedGetter): ResolvedGetter = getter.resolved
proc source*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.source
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.property.argType
proc property*(getter: AnalyzedGetter): AnalyzedArgumentDefinition = getter.property

proc analyzeGetter*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    let struct = ? defScope.extractStructFor(analyzedSourceArgType, getter.loc)
    let analyzedProperty = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedSourceArgType, analyzedProperty))

# Mutually-recursive body-level cluster — every type that cycles
# back to AnalyzedExpression / AnalyzedStatement must live here.
type
  AnalyzedFunctionCall* = ref object
    resolved: ResolvedFunctionCall
    def: AnalyzedFunctionDefinition
    args: seq[AnalyzedExpression]
    returns: AnalyzedArgumentType

  AnalyzedKeywordArgument* = ref object
    # todo: add a concrete type
    resolved: ResolvedKeywordArgument
    field: AnalyzedArgumentDefinition
    expression: AnalyzedExpression

  AnalyzedStructRefKind* = enum
    asrkDefault, asrkImpl
  AnalyzedStructRef* = ref object
    resolved: ResolvedStructRef
    case kind: AnalyzedStructRefKind
    of asrkDefault: discard
    of asrkImpl: argType: AnalyzedArgumentType

  AnalyzedUnionRefKind* = enum
    aurkDefault, aurkImpl
  AnalyzedUnionRef* = ref object
    resolved: ResolvedUnionRef
    case kind: AnalyzedUnionRefKind
    of aurkDefault: discard
    of aurkImpl: argType: AnalyzedArgumentType

  AnalyzedStructInitializer* = ref object
    resolved: ResolvedStructInitializer
    structRef: AnalyzedStructRef
    argType: AnalyzedArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    unionRef: AnalyzedUnionRef
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

proc newAnalyzedFunctionCall*(resolved: ResolvedFunctionCall, def: AnalyzedFunctionDefinition, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, def: def, args: args, returns: returns)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc
proc resolved*(fncall: AnalyzedFunctionCall): ResolvedFunctionCall = fncall.resolved
proc def*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDefinition = fncall.def
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType = fncall.returns

proc newAnalyzedKeywordArgument*(resolved: ResolvedKeywordArgument, field: AnalyzedArgumentDefinition, expression: AnalyzedExpression): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(resolved: resolved, field: field, expression: expression)

proc resolved*(kwarg: AnalyzedKeywordArgument): ResolvedKeywordArgument = kwarg.resolved
proc field*(kwarg: AnalyzedKeywordArgument): AnalyzedArgumentDefinition = kwarg.field
proc expression*(kwarg: AnalyzedKeywordArgument): AnalyzedExpression = kwarg.expression

proc newAnalyzedStructRef*(resolved: ResolvedStructRef): AnalyzedStructRef =
  AnalyzedStructRef(resolved: resolved, kind: asrkDefault)

proc newAnalyzedStructRef*(resolved: ResolvedStructRef, argType: AnalyzedArgumentType): AnalyzedStructRef =
  AnalyzedStructRef(resolved: resolved, kind: asrkImpl, argType: argType)

proc resolved*(s: AnalyzedStructRef): ResolvedStructRef = s.resolved
proc kind*(s: AnalyzedStructRef): AnalyzedStructRefKind = s.kind
proc module*(s: AnalyzedStructRef): Identifier = s.resolved.module
proc argType*(s: AnalyzedStructRef): AnalyzedArgumentType =
  assert s.kind == asrkImpl,
    fmt"AnalyzedStructRef.argType accessed but kind is {s.kind}"
  s.argType
proc loc*(s: AnalyzedStructRef): Location = s.resolved.loc

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef): AnalyzedUnionRef =
  AnalyzedUnionRef(resolved: resolved, kind: aurkDefault)

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef, argType: AnalyzedArgumentType): AnalyzedUnionRef =
  AnalyzedUnionRef(resolved: resolved, kind: aurkImpl, argType: argType)

proc resolved*(u: AnalyzedUnionRef): ResolvedUnionRef = u.resolved
proc kind*(u: AnalyzedUnionRef): AnalyzedUnionRefKind = u.kind
proc module*(u: AnalyzedUnionRef): Identifier = u.resolved.module
proc argType*(u: AnalyzedUnionRef): AnalyzedArgumentType =
  assert u.kind == aurkImpl,
    fmt"AnalyzedUnionRef.argType accessed but kind is {u.kind}"
  u.argType
proc loc*(u: AnalyzedUnionRef): Location = u.resolved.loc

proc newAnalyzedStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedStructRef, argType: AnalyzedArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, structRef: structRef, argType: argType, kwargs: kwargs)

proc resolved*(struct: AnalyzedStructInitializer): ResolvedStructInitializer = struct.resolved
proc structRef*(struct: AnalyzedStructInitializer): AnalyzedStructRef = struct.structRef
proc argType*(struct: AnalyzedStructInitializer): AnalyzedArgumentType = struct.argType
proc kwargs*(struct: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = struct.kwargs

proc newAnalyzedUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedUnionRef, argType: AnalyzedArgumentType, variant: AnalyzedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, unionRef: unionRef, argType: argType, variant: variant, kwargs: kwargs)

proc resolved*(init: AnalyzedUnionInitializer): ResolvedUnionInitializer = init.resolved
proc unionRef*(init: AnalyzedUnionInitializer): AnalyzedUnionRef = init.unionRef
proc module*(init: AnalyzedUnionInitializer): Identifier = init.resolved.module
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
  of aekFunctionCall: expression.fncall.loc
  of aekVariable: expression.variable.loc
  of aekLiteral: expression.literal.loc
  of aekGetter: expression.getter.loc
  of aekMatchExpr: expression.match.loc
  of aekInitializer: expression.init.loc

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType] =
  case expression.kind:
  of aekLiteral: none(AnalyzedArgumentType)
  of aekFunctionCall: some(expression.fncall.returns)
  of aekVariable: some(expression.variable.argType)
  of aekMatchExpr: some(expression.match.returns)
  of aekInitializer: some(expression.init.argType)
  of aekGetter: some(expression.getter.argType)

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
proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedDefinedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of adatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of adatkModule:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.module, loc)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze imported value type against module argument type")
  of aatkDefined:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType, valType.definedType, loc)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkImported:
      return err(fmt"{loc} todo: analyze imported impl type")
    of aatkDefined:
      case valType.definedType.kind:
      of adatkGeneric:
        let maybeConcreteFuncDef = valType.definedType.generic.resolved.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
      of adatkModule:
        let maybeConcreteFuncDef = valType.definedType.module.module.findFunctionDef(funcDef)
        if maybeConcreteFuncDef.isNone:
          return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  var genericImplMap: GenericImplMap
  genericImplMap[defType.resolved] = valType
  ok(genericImplMap)

proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedDefinedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of adatkModule: analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.module, valType, loc)
  of adatkGeneric: analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.generic, valType, loc)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefinitionType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkImported:
    err(fmt"{loc} todo: analyze value type against imported argument type")
  of aatkDefined:
    analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, defType.definedType, valType, loc)

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: AnalyzedFunctionDefinition): Result[GenericImplMap, string] =
  # BUG: `zip` below silently truncates to the shorter sequence — if
  # funcDef.args.len != argValues.len the type-check walks only the common
  # prefix and reports success. Today the resolver's arity check prevents
  # this from being reachable, but the defensive assert traps the mismatch
  # if overload selection is ever wired wrong upstream.
  assert(funcDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {funcDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (argDef, argValue) in zip(funcDef.args, argValues):
    if argValue.argType.isNone:
      let argDefModule = ? defScope.findModuleDef(argDef.argType, argValue.loc)
      let argDefData = ? defScope.extractDataBlock(argDefModule, argValue.loc)
      case argDefData.kind:
      of adkStruct: return err(fmt"{argValue.loc} funtion call expects a struct initializer `{argDefModule.name.asl}`")
      of adkUnion: return err(fmt"{argValue.loc} funtion call expects a union initializer `{argDefModule.name.asl}`")
      of adkLiteral:
        let literalField = argDefData.literal
        case literalField.resolved:
        of rltkU16: return err(fmt"{argValue.loc} todo: analyze union initializer U16 literal argument")
        of rltkI8: return err(fmt"{argValue.loc} todo: analyze union initializer I8 literal argument")
        of rltkI16: return err(fmt"{argValue.loc} todo: analyze union initializer I16 literal argument")
        of rltkI64: return err(fmt"{argValue.loc} todo: analyze union initializer I64 literal argument")
        of rltkF32: return err(fmt"{argValue.loc} todo: analyze union initializer F32 literal argument")
        of rltkF64: return err(fmt"{argValue.loc} todo: analyze union initializer F64 literal argument")
        of rltkPointer: return err(fmt"{argValue.loc} todo: analyze union initializer Pointer literal argument")
        of rltkU8:
          case argValue.literal.kind:
          of lkFloat: return err(fmt"{argValue.loc} expected a valid 8-bit unsigned integer but found float")
          of lkString: return err(fmt"{argValue.loc} expected a valid 8-bit unsigned integer but found string")
          of lkInteger:
            let maybeParsedInt = parseInteger[uint8](argValue.literal.asl)
            if maybeParsedInt.isNone:
              return err(fmt"{argValue.loc} expected a valid 8-bit unsigned integer but found `{argValue.literal.asl}`")
            else:
              return ok(genericImplMap)
        of rltkU32:
          case argValue.literal.kind:
          of lkFloat: return err(fmt"{argValue.loc} expected a valid 32-bit unsigned integer but found float")
          of lkString: return err(fmt"{argValue.loc} expected a valid 32-bit unsigned integer but found string")
          of lkInteger:
            let maybeParsedInt = parseInteger[uint32](argValue.literal.asl)
            if maybeParsedInt.isNone:
              return err(fmt"{argValue.loc} expected a valid 32-bit unsigned integer but found `{argValue.literal.asl}`")
            else:
              return ok(genericImplMap)
        of rltkU64:
          case argValue.literal.kind:
          of lkFloat: return err(fmt"{argValue.loc} expected a valid 64-bit unsigned integer but found float")
          of lkString: return err(fmt"{argValue.loc} expected a valid 64-bit unsigned integer but found string")
          of lkInteger:
            let maybeParsedInt = parseInteger[uint64](argValue.literal.asl)
            if maybeParsedInt.isNone:
              return err(fmt"{argValue.loc} expected a valid 64-bit unsigned integer but found `{argValue.literal.asl}`")
            else:
              return ok(genericImplMap)
        of rltkI32:
          case argValue.literal.kind:
          of lkFloat: return err(fmt"{argValue.loc} expected a valid 32-bit signed integer but found float")
          of lkString: return err(fmt"{argValue.loc} expected a valid 32-bit signed integer but found string")
          of lkInteger:
            let maybeParsedInt = parseInteger[int32](argValue.literal.asl)
            if maybeParsedInt.isNone:
              return err(fmt"{argValue.loc} expected a valid 32-bit signed integer but found `{argValue.literal.asl}`")
            else:
              return ok(genericImplMap)
        of rltkString:
          case argValue.literal.kind:
          of lkFloat: return err(fmt"{argValue.loc} expected a valid string literal but found float")
          of lkInteger: return err(fmt"{argValue.loc} expected a valid string literal but found integer")
          of lkString: return ok(genericImplMap)
    else:
      let argGenericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, argDef.argType, argValue.argType.get, argValue.loc)
      genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[AnalyzedFunctionDefinition], analyzedArgs: seq[AnalyzedExpression]): Result[(AnalyzedFunctionDefinition, GenericImplMap), string] =
  var matches: seq[(AnalyzedFunctionDefinition, GenericImplMap)]
  var errors: seq[string]
  for index, funcDef in funcDefs:
    let maybeGenericImplMap = analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, analyzedArgs, funcDef)
    if maybeGenericImplMap.isOk:
      matches.add((funcDef, maybeGenericImplMap.get))
    else:
      errors.add(fmt"[{index + 1}] - " & maybeGenericImplMap.error)
      errors.add("\t" & fmt"{funcDef.loc}: {funcDef.asl}")

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
    message.add(errors)
    err(message.join("\n"))

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let definedType = ? defScope.findDefinedType(fncall.parsed.root, fncall.loc)
  let public =
    case definedType.kind:
    of adtkModule: (module != definedType.module.resolved)
    of adtkGeneric: true # generic func defs are not required to be explicitly marked public
  let funcDefs = ? definedType.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)

  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  let (matchingFuncDef, genericImpls) = ? analyzeArgumentList(app, file, fileScope, module, defScope, funcScope, fncall, funcDefs, analyzedArgs)
  # NOTE: compute concrete return type from the inferred implementation types
  let concreteReturns = matchingFuncDef.returns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, union: AnalyzedUnion): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, union)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    # echo fmt"SET {binding.name.asl} {binding.argType.asl}"
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, moduleDef, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    # echo module.loc, " ", analyzedStatement.argType.get.asl
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      # echo fmt"SET {newArg.name.asl} {newArg.argType.asl}"
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, defScope, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    # echo fmt"SET {binding.name.asl} {binding.argType.asl}"
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, moduleDef, defScope, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    # echo module.loc, " ", analyzedStatement.argType.get.asl
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      # echo fmt"SET {newArg.name.asl} {newArg.argType.asl}"
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

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], union: AnalyzedUnion): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedVariantPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, moduleDef, defScope, funcScope, caseBlock, union)
    analyzedCaseBlocks.add(analyzedCaseBlock)
    # echo analyzedCaseBlock.argType.get.asl
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: AnalyzedLiteralBlock): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal.resolved, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, moduleDef, defScope, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, match.subject)
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
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, moduleDef, defScope, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.literal)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))
    of adkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        case analyzedSubjectExpr.argType.get.kind:
        of aatkImported:
          err(fmt"{match.loc} todo: handle analyzed imported type in match expression analysis for concrete union module")
        of aatkDefined:
          case analyzedSubjectExpr.argType.get.definedType.kind:
          of adatkGeneric:
            err(fmt"{match.loc} UNREACHABLE: match block does not support generic types in subject expression")
          of adatkModule:
            let impls = analyzedSubjectExpr.argType.get.definedType.module.impls
            let concreteUnion = analyzedSubjectDataType.union.concrete(impls)
            let analyzedCases = ? analyzeCases(app, file, fileScope, module, moduleDef, defScope, funcScope, match.cases, concreteUnion)
            ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: AnalyzedArgumentDefinition): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, kwarg.expression)
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
    # TODO: Utilize genericImplMap
    let genericImplMap = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, analyzedField.argType, analyzedExpression.argType.get, analyzedExpression.loc)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc receiverArgType(receiver: AnalyzedModuleDefinition): AnalyzedArgumentType =
  ## Builds an AnalyzedArgumentType pointing at the receiver module with
  ## no impls. Used for default-kind struct initializers and union
  ## initializers (where impls live in the analyzer's deferred-inference
  ## thread, not at the call site).
  let resolvedSelfArg = receiver.resolved.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver.resolved)
  newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(analyzedModuleArg))

proc analyzeUnionRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  case unionRef.kind:
  of rurkDefault: ok(newAnalyzedUnionRef(unionRef))
  of rurkImpl:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, unionRef.argType)
    ok(newAnalyzedUnionRef(unionRef, analyzedArgType))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Dispatches on UnionRef kind. urkImpl substitutes the user-supplied
  ## impls into the variant's field types via concrete() and type-checks
  ## each kwarg against the substituted type — no inference. urkDefault
  ## walks the kwargs, accumulates a GenericImplMap from value-vs-field
  ## type matches, and builds the result type with bound concretes at
  ## positions the variant touched + free generics at uncovered positions
  ## (leave-as-is — unification at downstream use sites fills the rest).
  let analyzedUnionRef = ? analyzeUnionRef(app, file, fileScope, module, init.unionRef)
  let receiver = ? defScope.findModuleDef(init.module, init.loc)
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a union")
  let dataBlock = receiver.data.get
  case dataBlock.kind:
  of adkLiteral: return err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of adkStruct: return err(fmt"{init.loc} module `{receiver.name.asl}` is a struct")
  of adkUnion: discard
  let analyzedUnion = dataBlock.union
  let analyzedVariant = ? analyzedUnion.findVariant(init.variant)

  # Seed implMap from explicit impls (urkImpl path) so substitution
  # works without inference. urkDefault leaves the map empty and
  # accumulates from each kwarg below.
  var implMap: GenericImplMap
  case analyzedUnionRef.kind:
  of aurkImpl:
    case analyzedUnionRef.argType.kind:
    of aatkImported:
      return err(fmt"{analyzedUnionRef.loc} todo: explicit-impl union initializer with imported receiver type")
    of aatkDefined:
      case analyzedUnionRef.argType.definedType.kind:
      of adatkGeneric:
        return err(fmt"{analyzedUnionRef.loc} union receiver `{analyzedUnionRef.module.asl}` cannot be a generic")
      of adatkModule:
        let explicitImpls = analyzedUnionRef.argType.definedType.module.impls
        for genericArgType, position in analyzedUnion.genericTypeIndex:
          implMap[genericArgType.resolved] = explicitImpls[position]
  of aurkDefault: discard

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on urkDefault (implMap
  # is empty there), full concretization on urkImpl. Accumulate bindings
  # into implMap only on the urkDefault path.
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedField: AnalyzedArgumentDefinition = ? analyzedVariant.findField(kwarg.name)
    let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, kwarg.expression)
    if analyzedExpression.argType.isNone:
      return err(fmt"{kwarg.expression.loc} todo: literal-typed kwarg in union initializer")
    let fieldType = analyzedField.argType.concrete(implMap)
    let local = ? analyzeValueTypeAgainstDefinitionType(app, file, fileScope, module, defScope, fieldType, analyzedExpression.argType.get, analyzedExpression.loc)
    case analyzedUnionRef.kind:
    of aurkImpl: discard
    of aurkDefault: implMap = ? implMap.merge(local)
    analyzedKwargs.add(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

  # Build the result type. urkImpl already carries the fully-bound
  # argType from the user. urkDefault fills impls positionally from
  # the accumulated implMap, leaving uncovered positions as free
  # generics (the leave-as-is shape).
  let argType =
    case analyzedUnionRef.kind:
    of aurkImpl: analyzedUnionRef.argType
    of aurkDefault:
      var impls = newSeq[AnalyzedArgumentType](analyzedUnion.genericTypeIndex.len)
      for genericArgType, position in analyzedUnion.genericTypeIndex:
        if genericArgType.resolved in implMap:
          impls[position] = implMap[genericArgType.resolved]
        else:
          impls[position] = newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(genericArgType))
      let resolvedSelfArg = receiver.resolved.self
      let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver.resolved, impls)
      newAnalyzedArgumentType(newAnalyzedDefinedArgumentType(analyzedModuleArg))

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, analyzedVariant, analyzedKwargs))

proc analyzeStructRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  case structRef.kind:
  of rsrkDefault: ok(newAnalyzedStructRef(structRef))
  of rsrkImpl:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, structRef.argType)
    ok(newAnalyzedStructRef(structRef, analyzedArgType))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  let analyzedStructRef = ? analyzeStructRef(app, file, fileScope, module, init.structRef)
  let receiver = ? defScope.findModuleDef(init.structRef.module, init.loc)
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a struct")
  let dataBlock = receiver.data.get
  case dataBlock.kind:
  of adkLiteral: err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of adkUnion: err(fmt"{init.loc} module `{receiver.name.asl}` is a union")
  of adkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let analyzedField = ? dataBlock.struct.findField(kwarg.name)
      let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, moduleDef, defScope, funcScope, kwarg, analyzedField)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      case analyzedStructRef.kind:
      of asrkImpl: analyzedStructRef.argType
      of asrkDefault:
        # TODO: In case the fully qualified impls are not provided in struct initializer we need to infer the generic types ourselves
        receiverArgType(receiver)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    err(fmt"{init.loc} todo: analyze literal initializer")
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(app, file, fileScope, module, moduleDef, defScope, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(app, file, fileScope, module, moduleDef, defScope, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(app, file, fileScope, defScope, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, module, moduleDef, defScope, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, moduleDef, defScope, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeMutation*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, mutation: ResolvedMutation): Result[AnalyzedMutation, string] =
  let analyzedGetter = ? analyzeGetter(app, file, fileScope, defScope, funcScope, mutation.getter)
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, mutation.expression)
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedMutation(mutation, analyzedGetter, analyzedExpression))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, moduleDef: AnalyzedModuleDefinition, defScope: AnalyzedDefinedTypeScope, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, moduleDef, defScope, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, module, moduleDef, defScope, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskMutation:
    let analyzedMutation = ? analyzeMutation(app, file, fileScope, module, moduleDef, defScope, funcScope, statement.mutation)
    ok(newAnalyzedStatement(analyzedMutation))
