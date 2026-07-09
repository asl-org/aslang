## Body-level analysis: variables, getters, function calls,
## initializers, match/case blocks, expressions, statements,
## assignments, mutations — the mutually-recursive cluster that
## walks function bodies.
##
## Every type that participates in the cycle (Initializer <->
## FunctionCall <-> Expression <-> Match/CaseBlock <-> Statement <->
## Assignment/Setter/KeywordArgument) lives in a single type block —
## Nim only resolves cross-references inside one block.
## Constructors, accessors, and analyze* procs follow the type block
## in per-concept order (matching the original funcs.nim layout).

import results, tables, strformat, sequtils, options, strutils

import resolver
import argtypes
import funcrefs
import patterns

proc analyzeIntegerLiteral[T: SomeInteger](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid {expected} but found float")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkInteger:
    let maybeParsedInt = parseInteger[T](literal.asl)
    if maybeParsedInt.isSome: ok()
    else: err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")

proc analyzeStringLiteral(literal: Literal): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid string literal but found float")
  of lkInteger: err(fmt"{literal.loc} expected a valid string literal but found integer")
  of lkString: ok()

proc analyzeFloatLiteral[T: SomeFloat](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkInteger: err(fmt"{literal.loc} expected a valid {expected} but found integer")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkFloat:
    let maybeParsedFloat = parseFloat[T](literal.asl)
    if maybeParsedFloat.isNone:
      return err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")
    # Exact-representability is a warning, not an error: the closest
    # approximation stored in the parsed value is still returned as
    # the literal's value. Emit to stderr with the source location
    # so users can find and (if they choose) rewrite lossy literals
    # as runtime quotients of exact-integer literals.
    # TODO(diagnostics): thread warnings through the analyzer as a
    # collected seq rather than writing to stderr from deep inside
    # the pass.
    const mantissaBits =
      when T is float32: 24
      elif T is float64: 53
    if not isExactlyRepresentable(literal.asl, mantissaBits):
      stderr.writeLine(fmt"[WARN] {literal.loc} literal `{literal.asl}` cannot be exactly represented in {expected}; using closest approximation")
    ok()

proc analyzeLiteral(literalDef: ResolvedLiteralDef, literal: Literal): Result[void, string] =
  case literalDef:
  of rltkF32: analyzeFloatLiteral[float32](literal, "32-bit float")
  of rltkF64: analyzeFloatLiteral[float64](literal, "64-bit float")
  of rltkPointer: err(fmt"{literal.loc} todo: analyze literal Pointer literal argument")
  of rltkU8: analyzeIntegerLiteral[uint8](literal, "8-bit unsigned integer")
  of rltkU16: analyzeIntegerLiteral[uint16](literal, "16-bit unsigned integer")
  of rltkU32: analyzeIntegerLiteral[uint32](literal, "32-bit unsigned integer")
  of rltkU64: analyzeIntegerLiteral[uint64](literal, "64-bit unsigned integer")
  of rltkI8: analyzeIntegerLiteral[int8](literal, "8-bit signed integer")
  of rltkI16: analyzeIntegerLiteral[int16](literal, "16-bit signed integer")
  of rltkI32: analyzeIntegerLiteral[int32](literal, "32-bit signed integer")
  of rltkI64: analyzeIntegerLiteral[int64](literal, "64-bit signed integer")
  of rltkString: literal.analyzeStringLiteral()

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

type AnalyzedLiteralInitializer = ref object
  resolved: ResolvedLiteralInitializer
  argType: AnalyzedArgumentType

proc newAnalyzedLiteralInitializer(resolved: ResolvedLiteralInitializer, argType: AnalyzedArgumentType): AnalyzedLiteralInitializer =
  AnalyzedLiteralInitializer(resolved: resolved, argType: argType)

proc loc*(init: AnalyzedLiteralInitializer): Location = init.resolved.loc
proc argType*(init: AnalyzedLiteralInitializer): AnalyzedArgumentType = init.argType

proc analyzeLiteralInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let argDefModule = ? fileScope.findModuleDef(analyzedArgType, init.loc)
  let argDefData = ? fileScope.extractDataDef(argDefModule, init.loc)
  case argDefData.kind:
  of rdkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of rdkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of rdkLiteral:
    let maybeValidLiteral = analyzeLiteral(argDefData.literal, init.literal)
    if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init, analyzedArgType))
    else: err(maybeValidLiteral.error)

# AnalyzedGetter — independent of the big cluster.
type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedArgumentType
  property: ResolvedArgumentDef
  propertyArgType: AnalyzedArgumentType

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedArgumentType, property: ResolvedArgumentDef, propertyArgType: AnalyzedArgumentType): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property, propertyArgType: propertyArgType)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc resolved*(getter: AnalyzedGetter): ResolvedGetter = getter.resolved
proc source*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.source
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType = getter.propertyArgType
proc property*(getter: AnalyzedGetter): ResolvedArgumentDef = getter.property

proc analyzeGetter*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    let struct = ? fileScope.extractStructFor(analyzedSourceArgType, getter.loc)
    let resolvedProperty = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    let analyzedPropertyArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedProperty.argType)
    ok(newAnalyzedGetter(getter, analyzedSourceArgType, resolvedProperty, analyzedPropertyArgType))

# Mutually-recursive body-level cluster — every type that cycles
# back to AnalyzedExpression / AnalyzedStatement must live here.
type
  AnalyzedFunctionCall* = ref object
    resolved: ResolvedFunctionCall
    def: ResolvedFunctionDef
    args: seq[AnalyzedExpression]
    returns: AnalyzedArgumentType

  AnalyzedKeywordArgument* = ref object
    # todo: add a concrete type
    resolved: ResolvedKeywordArgument
    field: ResolvedArgumentDef
    expression: AnalyzedExpression

  AnalyzedStructRef* = ref object
    resolved: ResolvedStructRef
    module: ResolvedModule
    analyzedImpls: seq[AnalyzedArgumentType]

  AnalyzedUnionRef* = ref object
    resolved: ResolvedUnionRef
    module: ResolvedModule
    analyzedImpls: seq[AnalyzedArgumentType]

  AnalyzedStructInitializer* = ref object
    resolved: ResolvedStructInitializer
    structRef: AnalyzedStructRef
    argType: AnalyzedArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    unionRef: AnalyzedUnionRef
    argType: AnalyzedArgumentType
    variant: ResolvedVariant
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedInitializerKind* = enum
    aikUnion, aikStruct, aikLiteral
  AnalyzedInitializer* = ref object
    case kind: AnalyzedInitializerKind
    of aikLiteral: literal: AnalyzedLiteralInitializer
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

  AnalyzedSetter* = ref object
    resolved: ResolvedSetter
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
    askExpr, askAssignment, askSetter
  AnalyzedStatement* = ref object
    case kind: AnalyzedStatementKind
    of askExpr: expression: AnalyzedExpression
    of askAssignment: assignment: AnalyzedAssignment
    of askSetter: setter: AnalyzedSetter

proc argType*(expression: AnalyzedExpression): Option[AnalyzedArgumentType]
proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType]

proc newAnalyzedFunctionCall*(resolved: ResolvedFunctionCall, def: ResolvedFunctionDef, args: seq[AnalyzedExpression], returns: AnalyzedArgumentType): AnalyzedFunctionCall =
  AnalyzedFunctionCall(resolved: resolved, def: def, args: args, returns: returns)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.resolved.loc
proc resolved*(fncall: AnalyzedFunctionCall): ResolvedFunctionCall = fncall.resolved
proc def*(fncall: AnalyzedFunctionCall): ResolvedFunctionDef = fncall.def
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType = fncall.returns

proc newAnalyzedKeywordArgument*(resolved: ResolvedKeywordArgument, field: ResolvedArgumentDef, expression: AnalyzedExpression): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(resolved: resolved, field: field, expression: expression)

proc resolved*(kwarg: AnalyzedKeywordArgument): ResolvedKeywordArgument = kwarg.resolved
proc field*(kwarg: AnalyzedKeywordArgument): ResolvedArgumentDef = kwarg.field
proc expression*(kwarg: AnalyzedKeywordArgument): AnalyzedExpression = kwarg.expression

proc newAnalyzedStructRef*(resolved: ResolvedStructRef,
    module: ResolvedModule,
    analyzedImpls: seq[AnalyzedArgumentType]): AnalyzedStructRef =
  ## One-shape constructor. `analyzedImpls` mirrors the resolver's
  ## `impls` seq: empty when the surface form was bare,
  ## non-empty (arity + constraint validated at resolve time) when the
  ## surface form supplied explicit impls.
  AnalyzedStructRef(resolved: resolved, module: module, analyzedImpls: analyzedImpls)

proc resolved*(s: AnalyzedStructRef): ResolvedStructRef = s.resolved
proc module*(s: AnalyzedStructRef): ResolvedModule = s.module
proc analyzedImpls*(s: AnalyzedStructRef): seq[AnalyzedArgumentType] = s.analyzedImpls
proc loc*(s: AnalyzedStructRef): Location = s.resolved.loc

proc newAnalyzedUnionRef*(resolved: ResolvedUnionRef,
    module: ResolvedModule,
    analyzedImpls: seq[AnalyzedArgumentType]): AnalyzedUnionRef =
  ## One-shape constructor. See `newAnalyzedStructRef` for shape rules.
  AnalyzedUnionRef(resolved: resolved, module: module, analyzedImpls: analyzedImpls)

proc resolved*(u: AnalyzedUnionRef): ResolvedUnionRef = u.resolved
proc module*(u: AnalyzedUnionRef): ResolvedModule = u.module
proc analyzedImpls*(u: AnalyzedUnionRef): seq[AnalyzedArgumentType] = u.analyzedImpls
proc loc*(u: AnalyzedUnionRef): Location = u.resolved.loc

proc newAnalyzedStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedStructRef, argType: AnalyzedArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, structRef: structRef, argType: argType, kwargs: kwargs)

proc resolved*(struct: AnalyzedStructInitializer): ResolvedStructInitializer = struct.resolved
proc loc*(init: AnalyzedStructInitializer): Location = init.resolved.loc
proc structRef*(struct: AnalyzedStructInitializer): AnalyzedStructRef = struct.structRef
proc argType*(struct: AnalyzedStructInitializer): AnalyzedArgumentType = struct.argType
proc kwargs*(struct: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = struct.kwargs

proc newAnalyzedUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedUnionRef, argType: AnalyzedArgumentType, variant: ResolvedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, unionRef: unionRef, argType: argType, variant: variant, kwargs: kwargs)

proc resolved*(init: AnalyzedUnionInitializer): ResolvedUnionInitializer = init.resolved
proc loc*(init: AnalyzedUnionInitializer): Location = init.resolved.loc
proc unionRef*(init: AnalyzedUnionInitializer): AnalyzedUnionRef = init.unionRef
proc module*(init: AnalyzedUnionInitializer): Module = init.resolved.module
proc argType*(init: AnalyzedUnionInitializer): AnalyzedArgumentType = init.argType
proc variant*(init: AnalyzedUnionInitializer): ResolvedVariant = init.variant
proc kwargs*(init: AnalyzedUnionInitializer): seq[AnalyzedKeywordArgument] = init.kwargs

proc newAnalyzedInitializer*(literal: AnalyzedLiteralInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikLiteral, literal: literal)

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
  of aikLiteral: init.literal.argType
  of aikUnion: init.union.argType
  of aikStruct: init.struct.argType

proc loc*(init: AnalyzedInitializer): Location =
  case init.kind:
  of aikLiteral: init.literal.loc
  of aikUnion: init.union.loc
  of aikStruct: init.struct.loc

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

proc newAnalyzedSetter*(resolved: ResolvedSetter, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedSetter =
  AnalyzedSetter(resolved: resolved, getter: getter, expression: expression)

proc loc*(setter: AnalyzedSetter): Location = setter.resolved.loc
proc resolved*(setter: AnalyzedSetter): ResolvedSetter = setter.resolved
proc getter*(setter: AnalyzedSetter): AnalyzedGetter = setter.getter
proc expression*(setter: AnalyzedSetter): AnalyzedExpression = setter.expression
proc argType*(setter: AnalyzedSetter): Option[AnalyzedArgumentType] = setter.expression.argType

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

proc newAnalyzedStatement*(setter: AnalyzedSetter): AnalyzedStatement =
  AnalyzedStatement(kind: askSetter, setter: setter)

proc kind*(statement: AnalyzedStatement): AnalyzedStatementKind = statement.kind
proc expression*(statement: AnalyzedStatement): AnalyzedExpression =
  assert statement.kind == askExpr,
    fmt"AnalyzedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: AnalyzedStatement): AnalyzedAssignment =
  assert statement.kind == askAssignment,
    fmt"AnalyzedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc setter*(statement: AnalyzedStatement): AnalyzedSetter =
  assert statement.kind == askSetter,
    fmt"AnalyzedStatement.setter accessed but kind is {statement.kind}"
  statement.setter

proc loc*(statement: AnalyzedStatement): Location =
  case statement.kind:
  of askExpr: statement.expression.loc
  of askAssignment: statement.assignment.loc
  of askSetter: statement.setter.loc

proc argType*(statement: AnalyzedStatement): Option[AnalyzedArgumentType] =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType
  of askSetter: statement.setter.argType

proc arg*(statement: AnalyzedStatement): Option[AnalyzedBinding] =
  let maybeArgType = statement.argType
  if maybeArgType.isNone:
    assert(maybeArgType.isSome, fmt"{statement.loc} todo: support argType for statement")
  else:
    case statement.kind:
    of askExpr: return none(AnalyzedBinding)
    of askSetter: return none(AnalyzedBinding)
    of askAssignment: return some((name: statement.assignment.target, argType: maybeArgType.get))

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string]

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefType(app, file, fileScope, defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of aatkModule:
    analyzeValueTypeAgainstDefType(app, file, fileScope, defType, valType.module, loc)

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkGeneric:
      let maybeConcreteFuncDef = valType.generic.resolved.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
    of aatkModule:
      let maybeConcreteFuncDef = valType.module.module.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  var genericImplMap: GenericImplMap
  genericImplMap[defType.resolved] = valType
  ok(genericImplMap)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkModule: analyzeValueTypeAgainstDefType(app, file, fileScope, defType.module, valType, loc)
  of aatkGeneric: analyzeValueTypeAgainstDefType(app, file, fileScope, defType.generic, valType, loc)

proc analyzeArgumentList*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], funcDef: ResolvedFunctionDef): Result[GenericImplMap, string] =
  # BUG: `zip` below silently truncates to the shorter sequence — if
  # funcDef.args.len != argValues.len the type-check walks only the common
  # prefix and reports success. Today the resolver's arity check prevents
  # this from being reachable, but the defensive assert traps the mismatch
  # if overload selection is ever wired wrong upstream.
  assert(funcDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {funcDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (argDef, argValue) in zip(funcDef.args, argValues):
    let argDefAnalyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
    if argValue.argType.isNone:
      let argDefModule = ? fileScope.findModuleDef(argDefAnalyzedArgType, argValue.loc)
      let argDefData = ? fileScope.extractDataDef(argDefModule, argValue.loc)
      case argDefData.kind:
      of rdkStruct: return err(fmt"{argValue.loc} function call expects a struct initializer `{argDefModule.name.asl}`")
      of rdkUnion: return err(fmt"{argValue.loc} function call expects a union initializer `{argDefModule.name.asl}`")
      of rdkLiteral:
        let maybeValidLiteral = analyzeLiteral(argDefData.literal, argValue.literal)
        if maybeValidLiteral.isOk: return ok(genericImplMap)
        else: return err(maybeValidLiteral.error)
    else:
      let argGenericImplMap = ? analyzeValueTypeAgainstDefType(app, file, fileScope, argDefAnalyzedArgType, argValue.argType.get, argValue.loc)
      genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[ResolvedFunctionDef], analyzedArgs: seq[AnalyzedExpression]): Result[(ResolvedFunctionDef, GenericImplMap), string] =
  var matches: seq[(ResolvedFunctionDef, GenericImplMap)]
  var errors: seq[string]
  for index, funcDef in funcDefs:
    let maybeGenericImplMap = analyzeArgumentList(app, file, fileScope, module, funcScope, analyzedArgs, funcDef)
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

proc analyzeFunctionCall*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let definedType = ? fileScope.findType(fncall.parsed.root, fncall.loc)
  let public =
    case definedType.kind:
    of rdtkModule: (module != definedType.module)
    of rdtkGeneric: true # generic func defs are not required to be explicitly marked public
  let funcDefs =
    case definedType.kind:
    of rdtkModule: ? definedType.module.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)
    of rdtkGeneric: ? definedType.generic.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len)

  var analyzedArgs: seq[AnalyzedExpression]
  for arg in fncall.args:
    let analyzedArg = ? analyzeExpression(app, file, fileScope, module, funcScope, arg)
    analyzedArgs.add(analyzedArg)

  let (matchingFuncDef, genericImpls) = ? analyzeArgumentList(app, file, fileScope, module, funcScope, fncall, funcDefs, analyzedArgs)
  # NOTE: compute concrete return type from the inferred implementation types
  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, matchingFuncDef.returns)
  let concreteReturns = analyzedReturns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, funcScope, caseBlock.pattern, subjectType, union, subjectImpls)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(app, file, fileScope, module, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(app, file, fileScope, module, caseScope, statement)
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

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType], loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, funcScope, caseBlock, subjectType, union, subjectImpls)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: ResolvedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(app, file, fileScope, module, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(app, file, fileScope, module, funcScope, match.subject)
  if analyzedSubjectExpr.argType.isNone:
    err(fmt"{analyzedSubjectExpr.loc} todo: analyze case blocks for literal expression")
  else:
    let analyzedSubjectDataType = ? fileScope.extractDataDef(analyzedSubjectExpr.argType.get, analyzedSubjectExpr.loc)
    case analyzedSubjectDataType.kind:
    of rdkStruct:
      let moduleName = analyzedSubjectExpr.argType.get.name
      err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{moduleName.asl}` a struct type")
    of rdkLiteral:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        let analyzedCases = ? analyzeCases(app, file, fileScope, module, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.literal, match.loc)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))
    of rdkUnion:
      if match.cases.len == 0:
        err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
      else:
        case analyzedSubjectExpr.argType.get.kind:
        of aatkGeneric:
          err(fmt"{match.loc} UNREACHABLE: match block does not support generic types in subject expression")
        of aatkModule:
          let impls = analyzedSubjectExpr.argType.get.module.impls
          let analyzedCases = ? analyzeCases(app, file, fileScope, module, funcScope, match.cases, analyzedSubjectExpr.argType.get, analyzedSubjectDataType.union, impls, match.loc)
          ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType.get))

proc analyzeKeywordArgument*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: ResolvedArgumentDef, analyzedFieldArgType: AnalyzedArgumentType): Result[AnalyzedKeywordArgument, string] =
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, funcScope, kwarg.expression)
  if analyzedExpression.argType.isNone:
    let fieldModule = ? fileScope.findModuleDef(analyzedFieldArgType, kwarg.expression.loc)
    let fieldModuleData = ? fileScope.extractDataDef(fieldModule, kwarg.expression.loc)
    case fieldModuleData.kind:
    of rdkStruct:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a struct value but found literal")
    of rdkUnion:
      err(fmt"{kwarg.expression.loc} field `{kwarg.name.asl}` expected a union value but found literal")
    of rdkLiteral:
      let maybeAnalyzedLiteral = analyzeLiteral(fieldModuleData.literal, kwarg.expression.literal)
      if maybeAnalyzedLiteral.isErr: err(maybeAnalyzedLiteral.error)
      else: ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))
  else:
    # TODO: Utilize the returned generic impl map
    discard ? analyzeValueTypeAgainstDefType(app, file, fileScope, analyzedFieldArgType, analyzedExpression.argType.get, analyzedExpression.loc)
    ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc receiverArgType(receiver: ResolvedModule): AnalyzedArgumentType =
  ## Builds an AnalyzedArgumentType pointing at the receiver module with
  ## no impls. Used for default-kind struct initializers and union
  ## initializers (where impls live in the analyzer's deferred-inference
  ## thread, not at the call site).
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver)
  newAnalyzedArgumentType(analyzedModuleArg)

proc analyzeUnionRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## See `analyzeStructRef` for the parser-Module -> ResolvedModule lookup.
  let resolvedModule = ? fileScope.findModuleDef(unionRef.module.name, unionRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](unionRef.impls.len)
  for i, resolvedImpl in unionRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(app, file, fileScope, module, resolvedImpl)
  ok(newAnalyzedUnionRef(unionRef, resolvedModule, analyzedImpls))

proc analyzeUnionInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Single code path over the union initializer:
  ## - If the surface form supplied explicit impls, the resolver has
  ##   already threaded them into `analyzedImpls`. We seed implMap
  ##   positionally from that seq up front, then skip the merge-from-
  ##   kwarg step so no inference happens.
  ## - If the surface form was bare, `analyzedImpls` is empty. The seed
  ##   loop is a no-op and the kwarg walk accumulates the implMap via
  ##   value-vs-field type matches (leave-as-is).
  ## Result-type construction is a single loop over the union's
  ## genericTypeIndex: fill bound positions from implMap, leave uncovered
  ## positions as free generics for downstream unification.
  let analyzedUnionRef = ? analyzeUnionRef(app, file, fileScope, module, init.unionRef)
  let receiver = analyzedUnionRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a union")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: return err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkStruct: return err(fmt"{init.loc} module `{receiver.name.asl}` is a struct")
  of rdkUnion: discard
  let resolvedUnion = dataDef.union
  let resolvedVariant = ? resolvedUnion.findVariant(init.variant)
  let analyzedImpls = analyzedUnionRef.analyzedImpls
  let hasExplicitImpls = analyzedImpls.len > 0

  # Seed implMap positionally from the resolver-checked explicit impls
  # (empty seq → no-op, preserving the bare/leave-as-is path).
  var implMap: GenericImplMap
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    if position < analyzedImpls.len:
      # `genericArgType.parsed` is the parser-side Generic;
      # GenericImplMap keys on ResolvedGeneric. Translate through
      # analyzeArgumentType so the resolved generic is looked up via
      # the file scope.
      let analyzedGeneric = ? analyzeArgumentType(app, file, fileScope, module, newResolvedArgumentType(genericArgType))
      implMap[analyzedGeneric.generic.resolved] = analyzedImpls[position]

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on the bare path
  # (implMap seeded from kwargs), full concretization on the explicit-
  # impls path (implMap already seeded, merge-from-kwarg skipped so no
  # inference happens).
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let resolvedField = ? resolvedVariant.findField(kwarg.name)
    let analyzedFieldArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedField.argType)
    let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, funcScope, kwarg.expression)
    if analyzedExpression.argType.isNone:
      return err(fmt"{kwarg.expression.loc} todo: literal-typed kwarg in union initializer")
    let fieldType = analyzedFieldArgType.concrete(implMap)
    let local = ? analyzeValueTypeAgainstDefType(app, file, fileScope, fieldType, analyzedExpression.argType.get, analyzedExpression.loc)
    if not hasExplicitImpls:
      implMap = ? implMap.merge(local)
    analyzedKwargs.add(newAnalyzedKeywordArgument(kwarg, resolvedField, analyzedExpression))

  # Build the result type. One loop over the union's genericTypeIndex
  # positions: bound positions read from implMap (seeded from explicit
  # impls or accumulated via kwargs), free positions get a fresh
  # AnalyzedGenericArgumentType for downstream unification.
  var impls = newSeq[AnalyzedArgumentType](resolvedUnion.genericTypeIndex.len)
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    let analyzedGeneric = ? analyzeArgumentType(app, file, fileScope, module, newResolvedArgumentType(genericArgType))
    if analyzedGeneric.generic.resolved in implMap:
      impls[position] = implMap[analyzedGeneric.generic.resolved]
    else:
      impls[position] = analyzedGeneric
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, impls)
  let argType = newAnalyzedArgumentType(analyzedModuleArg)

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, resolvedVariant, analyzedKwargs))

proc analyzeStructRef(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## The parser Module carried on `structRef.module` is looked up here
  ## into a ResolvedModule via `fileScope.findModuleDef` — the resolver
  ## keeps struct/union refs parser-level to break the ref cycle;
  ## analyzer types can hold the resolved view freely.
  let resolvedModule = ? fileScope.findModuleDef(structRef.module.name, structRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](structRef.impls.len)
  for i, resolvedImpl in structRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(app, file, fileScope, module, resolvedImpl)
  ok(newAnalyzedStructRef(structRef, resolvedModule, analyzedImpls))

proc analyzeStructInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Single code path over the struct initializer. Receiver is the
  ## resolver's already-resolved module; result argType wraps the
  ## analyzedImpls seq (empty when the surface form was bare — matches
  ## the receiverArgType() no-impls shape; non-empty when explicit
  ## impls were supplied and arity+constraint-checked at resolve time).
  ## TODO: Inference for uncovered generic positions on the bare path
  ## still lives with the caller of receiverArgType — folded into the
  ## same seq-based build here.
  let analyzedStructRef = ? analyzeStructRef(app, file, fileScope, module, init.structRef)
  let receiver = analyzedStructRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a struct")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkUnion: err(fmt"{init.loc} module `{receiver.name.asl}` is a union")
  of rdkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let resolvedField = ? dataDef.struct.findField(kwarg.name)
      let analyzedFieldArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedField.argType)
      let analyzedKwarg = ? analyzeKeywordArgument(app, file, fileScope, module, funcScope, kwarg, resolvedField, analyzedFieldArgType)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      if analyzedStructRef.analyzedImpls.len == 0:
        receiverArgType(receiver)
      else:
        let resolvedSelfArg = receiver.self
        let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, analyzedStructRef.analyzedImpls)
        newAnalyzedArgumentType(analyzedModuleArg)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    let analyzedLiteralInit = ? analyzeLiteralInitializer(app, file, fileScope, module, funcScope, init.literal)
    ok(newAnalyzedInitializer(analyzedLiteralInit))
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(app, file, fileScope, module, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(app, file, fileScope, module, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc analyzeExpression*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral: ok(newAnalyzedExpression(expression.literal))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(app, file, fileScope, module, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(app, file, fileScope, module, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(app, file, fileScope, module, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, funcScope, assignment.expression)
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeSetter*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, setter: ResolvedSetter): Result[AnalyzedSetter, string] =
  let analyzedGetter = ? analyzeGetter(app, file, fileScope, module, funcScope, setter.getter)
  let analyzedExpression = ? analyzeExpression(app, file, fileScope, module, funcScope, setter.expression)
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedSetter(setter, analyzedGetter, analyzedExpression))

proc analyzeStatement*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(app, file, fileScope, module, funcScope, statement.expression)
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(app, file, fileScope, module, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskSetter:
    let analyzedMutation = ? analyzeSetter(app, file, fileScope, module, funcScope, statement.setter)
    ok(newAnalyzedStatement(analyzedMutation))
