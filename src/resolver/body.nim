## Body-level resolution: variables, getters, case patterns,
## initializers, function calls, expressions, statements, and the
## mutually-recursive cluster they form.
##
## Every type that participates in the cycle (Initializer ↔
## FunctionCall ↔ Expression ↔ Match/CaseBlock ↔ Statement ↔
## Assignment/Mutation/KeywordArgument) lives in a single type block
## — Nim only resolves cross-references inside one block.
## Constructors and resolveX procs follow the type block in
## per-concept order (matching resolver.nim's original layout).

import results, options, sets, strformat, tables

import tokenizer
import parser
import argtypes
import funcrefs
import patterns

# ResolvedGetter — independent of the big cluster.
type ResolvedGetter* = ref object
  source: Identifier
  property: Identifier

proc newResolvedGetter*(source, property: Identifier): ResolvedGetter =
  ResolvedGetter(source: source, property: property)

proc loc*(getter: ResolvedGetter): Location =
  getter.source.loc

proc resolveVariable*(file: parser.File, scope: FunctionScope,
    variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter*(file: parser.File, scope: FunctionScope,
    getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(file, scope, getter.source)
  ok(newResolvedGetter(getter.source, getter.property))

# ResolvedLiteralInitializer — needs ResolvedArgumentType but no
# ResolvedExpression dependency (literal value is parser AST).
type ResolvedLiteralInitializer* = ref object
  argType: ResolvedArgumentType
  value: Literal

proc newResolvedLiteralInitializer*(argType: ResolvedArgumentType,
    value: Literal): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(argType: argType, value: value)

proc loc*(init: ResolvedLiteralInitializer): Location = init.argType.loc

proc resolveLiteralInitializer(app: App, file: parser.File,
    fileScope: FileScope, module: Module,
    literalInit: LiteralInitializer): Result[
        ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    literalInit.argType)
  ok(newResolvedLiteralInitializer(resolvedArgType, literalInit.value))

# Mutually-recursive body-level cluster — every type that cycles
# back to ResolvedExpression / ResolvedStatement must live here.
type
  ResolvedKeywordArgument* = ref object
    name: Identifier
    expression: ResolvedExpression

  ResolvedStructInitializer* = ref object
    argType: ResolvedArgumentType
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedUnionInitializer* = ref object
    argType: ResolvedArgumentType
    variant: Identifier
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedInitializerKind* = enum
    rikStruct, rikUnion, rikLiteral
  ResolvedInitializer* = ref object
    case kind: ResolvedInitializerKind
    of rikStruct: struct: ResolvedStructInitializer
    of rikUnion: union: ResolvedUnionInitializer
    of rikLiteral: literal: ResolvedLiteralInitializer

  ResolvedFunctionCall* = ref object
    funcRef: ResolvedFunctionRef
    args: seq[ResolvedExpression]

  ResolvedAssignment* = ref object
    target: Identifier
    expression: ResolvedExpression

  ResolvedMutation* = ref object
    getter: ResolvedGetter
    expression: ResolvedExpression

  ResolvedCaseBlock* = ref object
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]

  ResolvedMatchExpression* = ref object
    subject: ResolvedExpression
    cases: seq[ResolvedCaseBlock]
    loc: Location

  ResolvedExpressionKind* = enum
    rekFunctionCall, rekVariable, rekLiteral, rekInitializer,
    rekGetter, rekMatchExpr
  ResolvedExpression* = ref object
    case kind: ResolvedExpressionKind
    of rekFunctionCall: fncall: ResolvedFunctionCall
    of rekVariable: variable: Identifier
    of rekLiteral: literal: Literal
    of rekInitializer: initializer: ResolvedInitializer
    of rekGetter: getter: ResolvedGetter
    of rekMatchExpr: match: ResolvedMatchExpression

  ResolvedStatementKind* = enum
    rskAssignment, rskExpr, rskMutation
  ResolvedStatement* = ref object
    case kind: ResolvedStatementKind
    of rskAssignment: assignment: ResolvedAssignment
    of rskExpr: expression: ResolvedExpression
    of rskMutation: mutation: ResolvedMutation

# Constructors for every type in the cluster.
proc newResolvedKeywordArgument*(name: Identifier,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(name: name, expression: expression)

proc newResolvedStructInitializer*(argType: ResolvedArgumentType,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(argType: argType, kwargs: kwargs)

proc loc*(struct: ResolvedStructInitializer): Location = struct.argType.loc

proc newResolvedUnionInitializer*(argType: ResolvedArgumentType,
    variant: Identifier,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(argType: argType, variant: variant, kwargs: kwargs)

proc loc*(init: ResolvedUnionInitializer): Location = init.argType.loc

proc newResolvedInitializer*(
    struct: ResolvedStructInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikStruct, struct: struct)

proc newResolvedInitializer*(
    union: ResolvedUnionInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikUnion, union: union)

proc newResolvedInitializer*(
    literal: ResolvedLiteralInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikLiteral, literal: literal)

proc loc*(init: ResolvedInitializer): Location =
  case init.kind:
  of rikLiteral: init.literal.loc
  of rikStruct: init.struct.loc
  of rikUnion: init.union.loc

proc newResolvedFunctionCall*(funcRef: ResolvedFunctionRef,
    args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(funcRef: funcRef, args: args)

proc loc*(fncall: ResolvedFunctionCall): Location = fncall.funcRef.loc
proc funcRef*(fncall: ResolvedFunctionCall): ResolvedFunctionRef = fncall.funcRef
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args

proc newResolvedAssignment*(target: Identifier,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(target: target, expression: expression)

proc loc*(assignment: ResolvedAssignment): Location =
  assignment.target.loc

proc newResolvedMutation*(getter: ResolvedGetter,
    expression: ResolvedExpression): ResolvedMutation =
  ResolvedMutation(getter: getter, expression: expression)

proc loc*(mutation: ResolvedMutation): Location =
  mutation.getter.loc

proc newResolvedCaseBlock*(pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(pattern: pattern, statements: statements)

proc newResolvedMatchExpression*(subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock], loc: Location): ResolvedMatchExpression =
  ResolvedMatchExpression(subject: subject, cases: cases, loc: loc)

proc newResolvedExpression*(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: rekFunctionCall, fncall: fncall)

proc newResolvedExpression*(
    initializer: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: rekInitializer, initializer: initializer)

proc newResolvedExpression*(variable: Identifier): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, variable: variable)

proc newResolvedExpression*(literal: Literal): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc newResolvedExpression*(getter: ResolvedGetter): ResolvedExpression =
  ResolvedExpression(kind: rekGetter, getter: getter)

proc newResolvedExpression*(
    match: ResolvedMatchExpression): ResolvedExpression =
  ResolvedExpression(kind: rekMatchExpr, match: match)

proc kind*(expression: ResolvedExpression): ResolvedExpressionKind = expression.kind
proc fncall*(expression: ResolvedExpression): ResolvedFunctionCall = expression.fncall
proc variable*(expression: ResolvedExpression): Identifier = expression.variable
proc literal*(expression: ResolvedExpression): Literal = expression.literal

proc loc*(expression: ResolvedExpression): Location =
  case expression.kind:
  of rekFunctionCall: expression.fncall.loc
  of rekGetter: expression.getter.loc
  of rekInitializer: expression.initializer.loc
  of rekMatchExpr: expression.match.loc
  of rekVariable: expression.variable.loc
  of rekLiteral: expression.literal.loc

proc newResolvedStatement*(assignment: ResolvedAssignment): ResolvedStatement =
  ResolvedStatement(kind: rskAssignment, assignment: assignment)

proc newResolvedStatement*(expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(kind: rskExpr, expression: expression)

proc newResolvedStatement*(mutation: ResolvedMutation): ResolvedStatement =
  ResolvedStatement(kind: rskMutation, mutation: mutation)

proc kind*(statement: ResolvedStatement): ResolvedStatementKind = statement.kind
proc expression*(statement: ResolvedStatement): ResolvedExpression = statement.expression

proc loc*(statement: ResolvedStatement): Location =
  case statement.kind:
  of rskAssignment: statement.assignment.loc
  of rskExpr: statement.expression.loc
  of rskMutation: statement.mutation.loc

# Accessor used by callers to thread bindings into scope.
proc variable*(statement: ResolvedStatement): Option[Identifier] =
  ## Returns the new binding introduced by this statement (if any).
  case statement.kind:
  of rskAssignment: some(statement.assignment.target)
  of rskExpr: none(Identifier)
  of rskMutation: none(Identifier)

# Forward declarations for the resolveX procs in the cluster.
proc resolveExpression*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string]

proc resolveStatement*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let resolvedFunctionRef = ? resolveFunctionRef(app, file, fileScope, module,
    scope, fncall.argType, fncall.name, fncall.args.len, fncall.loc)
  var resolvedArgs: seq[ResolvedExpression]
  for arg in fncall.args:
    let resolvedArg = ? resolveExpression(app, file, fileScope, module, scope,
      arg)
    resolvedArgs.add(resolvedArg)
  ok(newResolvedFunctionCall(resolvedFunctionRef, resolvedArgs))

proc resolveStructInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    struct.argType)
  let structType = ? file.findType(struct.argType.root)
  let definedType =
    case structType.kind:
    of tkDefined:
      structType.definedType
    of tkImported:
      let importedType = structType.imported
      if importedType.name notin fileScope:
        return err(fmt"{importedType.loc} type `{importedType.name.asl}` does not exist in the file scope. 3")

      fileScope[importedType.name]
  case definedType.kind:
  of dtkGeneric: err(fmt"{struct.loc} type `{definedType.name.asl}` is a generic and not struct")
  of dtkModule:
    let structModule = definedType.module
    if structModule.data.isNone:
      err(fmt"{struct.loc} module `{structModule.name.asl}` is not a struct")
    else:
      let dataBlock = structModule.data.get
      case dataBlock.kind:
      of dbkLiteral: err(fmt"{dataBlock.loc} module `{structModule.name.asl}` is a literal")
      of dbkUnion: err(fmt"{dataBlock.loc} module `{structModule.name.asl}` is a union")
      of dbkStruct:
        let structBlock = dataBlock.struct
        if struct.kwargs.len != structBlock.fields.len:
          err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
        else:
          var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](
            structBlock.fields.len)
          for kwarg in struct.kwargs:
            let fieldId = ? structBlock.findFieldId(kwarg.name)
            let resolvedExpression = ? resolveExpression(app, file, fileScope,
              module, scope, kwarg.expression)
            resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg.name,
              resolvedExpression)
          ok(newResolvedStructInitializer(resolvedArgType, resolvedKeywordArgs))

proc resolveUnionInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    unionInit.argType)
  let unionType = ? file.findType(unionInit.argType.root)
  let unionDefinedType =
    case unionType.kind:
    of tkDefined:
      unionType.definedType
    of tkImported:
      let importedType = unionType.imported
      if importedType.name notin fileScope:
        return err(fmt"{importedType.loc} type `{importedType.name.asl}` does not exist in the file scope. 4")

      fileScope[importedType.name]

  case unionDefinedType.kind:
  of dtkGeneric: err(fmt"{unionInit.loc} type `{unionDefinedType.name.asl}` is a generic and not union")
  of dtkModule:
    let unionModule = unionDefinedType.module
    if unionModule.data.isNone:
      err(fmt"{unionInit.loc} module `{unionModule.name.asl}` is not a union")
    else:
      let dataBlock = unionModule.data.get
      case dataBlock.kind:
      of dbkLiteral: err(fmt"{dataBlock.loc} module `{unionModule.name.asl}` is a literal")
      of dbkStruct: err(fmt"{dataBlock.loc} module `{unionModule.name.asl}` is a struct")
      of dbkUnion:
        let union = dataBlock.union
        let variant = ? union.findVariant(unionInit.variant)
        if unionInit.kwargs.len != variant.fields.len:
          err(fmt"{unionInit.loc} union `{unionModule.name.asl}` expects `{variant.fields.len}` but `{unionInit.kwargs.len}` were given")
        else:
          var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](
            variant.fields.len)
          for kwarg in unionInit.kwargs:
            let fieldId = ? variant.findFieldId(kwarg.name)
            let resolvedExpression = ? resolveExpression(app, file, fileScope,
              module, scope, kwarg.expression)
            resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg.name,
              resolvedExpression)
          ok(newResolvedUnionInitializer(resolvedArgType, variant.name,
            resolvedKeywordArgs))

proc resolveInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(app, file, fileScope,
      module, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(app, file, fileScope,
      module, scope, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(app, file, fileScope,
      module, scope, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCaseBlock(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  var resolvedStatements: seq[ResolvedStatement]
  var childScope = scope # create a child scope to enable shadowing

  for binding in caseBlock.pattern.bindings:
    childScope.incl(binding)

  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      childScope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      childScope.incl(resolvedStatement.variable.get)
  ok(newResolvedCaseBlock(resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(app, file, fileScope, module, scope,
    match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(app, file, fileScope, module,
      scope, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(resolvedSubject, resolvedCaseBlocks, match.loc))

proc resolveExpression*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    ok(newResolvedExpression(expression.literal))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(file, scope, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(file, scope, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(app, file, fileScope,
      module, scope, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(app, file, fileScope, module,
      scope, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(app, file, fileScope,
      module, scope, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
    scope, assignment.expression)
  ok(newResolvedAssignment(assignment.target, resolvedExpression))

proc resolveMutation(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    mutation: Mutation): Result[ResolvedMutation, string] =
  let resolvedGetter = ? resolveGetter(file, scope, mutation.target)
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
    scope, mutation.expression)
  ok(newResolvedMutation(resolvedGetter, resolvedExpression))

proc resolveStatement*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
      scope, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(app, file, fileScope, module,
      scope, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skMutation:
    let resolvedMutation = ? resolveMutation(app, file, fileScope, module, scope,
      statement.mutation)
    ok(newResolvedStatement(resolvedMutation))
