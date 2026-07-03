## Body-level resolution: variables, getters, case patterns,
## initializers, function calls, expressions, statements, and the
## mutually-recursive cluster they form.
##
## The `Resolved*` types, their constructors, and direct-field
## accessors live in `types.nim`. This file owns the computed
## helpers (loc, source, property, name, target, ...) and the
## resolveX procs.

import results, options, sets, strformat

import tokenizer
import parser
import types
import argtypes
import patterns

# ---- ResolvedGetter helpers ----

proc source*(getter: ResolvedGetter): Identifier = getter.parsed.source
proc property*(getter: ResolvedGetter): Identifier = getter.parsed.property
proc loc*(getter: ResolvedGetter): Location = getter.parsed.loc

proc resolveVariable*(file: parser.File, scope: FunctionScope,
    variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter*(file: parser.File, scope: FunctionScope,
    getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(file, scope, getter.source)
  ok(newResolvedGetter(getter))

# ---- ResolvedLiteralInitializer helpers ----

proc value*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value

proc resolveLiteralInitializer(app: App, file: parser.File,
    fileScope: FileScope, module: Module,
    literalInit: LiteralInitializer): Result[
        ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    literalInit.argType)
  ok(newResolvedLiteralInitializer(literalInit, resolvedArgType))

# ---- Body-cluster computed helpers ----

proc name*(kwarg: ResolvedKeywordArgument): Identifier = kwarg.parsed.name
proc loc*(kwarg: ResolvedKeywordArgument): Location = kwarg.parsed.loc

proc loc*(s: ResolvedStructRef): Location = s.parsed.loc
proc loc*(u: ResolvedUnionRef): Location = u.parsed.loc
proc loc*(struct: ResolvedStructInitializer): Location = struct.parsed.loc
proc loc*(init: ResolvedUnionInitializer): Location = init.parsed.loc
proc module*(init: ResolvedUnionInitializer): Module = module(init.unionRef)
proc variant*(init: ResolvedUnionInitializer): Identifier = init.parsed.variant

proc loc*(init: ResolvedInitializer): Location =
  case init.kind:
  of rikLiteral: init.literal.loc
  of rikStruct: init.struct.loc
  of rikUnion: init.union.loc

proc loc*(fncall: ResolvedFunctionCall): Location = fncall.parsed.loc

proc loc*(assignment: ResolvedAssignment): Location = assignment.parsed.loc
proc target*(assignment: ResolvedAssignment): Identifier = assignment.parsed.target

proc loc*(setter: ResolvedSetter): Location = setter.parsed.loc

proc loc*(caseBlock: ResolvedCaseBlock): Location = caseBlock.parsed.loc

proc loc*(match: ResolvedMatchExpression): Location = match.parsed.loc

proc loc*(expression: ResolvedExpression): Location =
  case expression.kind:
  of rekFunctionCall: expression.fncall.loc
  of rekGetter: expression.getter.loc
  of rekInitializer: expression.init.loc
  of rekMatchExpr: expression.match.loc
  of rekVariable: expression.variable.loc
  of rekLiteral: expression.literal.loc

proc loc*(statement: ResolvedStatement): Location =
  case statement.kind:
  of rskAssignment: statement.assignment.loc
  of rskExpr: statement.expression.loc
  of rskSetter: statement.setter.loc

# Accessor used by callers to thread bindings into scope.
proc variable*(statement: ResolvedStatement): Option[Identifier] =
  ## Returns the new binding introduced by this statement (if any).
  case statement.kind:
  of rskAssignment: some(statement.assignment.target)
  of rskExpr: none(Identifier)
  of rskSetter: none(Identifier)

# ---- Forward declarations for the resolveX procs in the cluster ----

proc resolveExpression*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string]

proc resolveStatement*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let definedType = ? file.findDefinedType(fileScope, fncall.root)
  let funcDefs = ? definedType.findFunctionDefs(fncall.name, fncall.args.len)
  if funcDefs.len == 0:
    err(fmt"{fncall.loc} generic `{definedType.generic.name.asl}` does not have any function named `{fncall.name.asl}` with arity `{fncall.args.len}`")
  else:
    var resolvedArgs: seq[ResolvedExpression]
    for arg in fncall.args:
      let resolvedArg = ? resolveExpression(app, file, fileScope, module, scope, arg)
      resolvedArgs.add(resolvedArg)
    ok(newResolvedFunctionCall(fncall, resolvedArgs))

proc resolveStructRef(app: App, file: parser.File, fileScope: FileScope, module: Module, structRef: StructRef): Result[ResolvedStructRef, string] =
  ## Resolves a StructRef and validates the kind ↔ requires match.
  ## Looks up the receiver module via findModule (which handles local
  ## and imported types alike) and stores it on the default arm.
  let structModule = ? file.findModule(fileScope, structRef.module)
  case structRef.kind:
  of srkDefault:
    if structModule.requires.isSome:
      err(fmt"{structRef.loc} module `{structModule.name.asl}` declares requires; initializer must specify impl types as `{structModule.name.asl}[...]`")
    else:
      ok(newResolvedStructRef(structRef, structModule))
  of srkImpl:
    if not structModule.requires.isSome:
      err(fmt"{structRef.loc} module `{structModule.name.asl}` has no requires block; initializer must not specify impl types")
    else:
      let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, structRef.argType)
      ok(newResolvedStructRef(structRef, resolvedArgType))

proc resolveStructInitializer(app: App, file: parser.File, fileScope: FileScope, module: Module, scope: FunctionScope, struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(app, file, fileScope, module, struct.structRef)
  let structModule = module(resolvedStructRef)
  var structBlock = ? structModule.struct(struct.loc)
  if struct.kwargs.len != structBlock.fields.len:
    err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
  else:
    var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](structBlock.fields.len)
    for kwarg in struct.kwargs:
      let fieldId = ? structBlock.findFieldId(kwarg.name)
      let resolvedExpression = ? resolveExpression(app, file, fileScope,
        module, scope, kwarg.expression)
      resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
        resolvedExpression)
    ok(newResolvedStructInitializer(struct, resolvedStructRef, resolvedKeywordArgs))

proc resolveUnionRef(app: App, file: parser.File, fileScope: FileScope, module: Module, unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  ## Default arm stores the resolved receiver module — drives leave-as-is
  ## inference at the analyzer. Impl arm resolves the explicit argType;
  ## arity against the union's deduped requires list is checked downstream
  ## once the resolved union (and its position-indexed requires) is in hand.
  let unionModule = ? file.findModule(fileScope, unionRef.module)
  case unionRef.kind:
  of urkDefault:
    ok(newResolvedUnionRef(unionRef, unionModule))
  of urkImpl:
    let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, unionRef.argType)
    ok(newResolvedUnionRef(unionRef, resolvedArgType))

proc resolveUnionInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(app, file, fileScope, module, unionInit.unionRef)
  let initModule = module(resolvedUnionRef)
  let union = ? initModule.union(unionInit.loc)
  let variant = ? union.findVariant(unionInit.variant)
  if unionInit.kwargs.len != variant.fields.len:
    return err(fmt"{unionInit.loc} union `{initModule.name.asl}` expects `{variant.fields.len}` but `{unionInit.kwargs.len}` were given")
  var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](
    variant.fields.len)
  for kwarg in unionInit.kwargs:
    let fieldId = ? variant.findFieldId(kwarg.name)
    let resolvedExpression = ? resolveExpression(app, file, fileScope,
      module, scope, kwarg.expression)
    resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
      resolvedExpression)
  ok(newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs))

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
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

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
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

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
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(file, scope, setter.target)
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
    scope, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

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
  of skSetter:
    let resolvedMutation = ? resolveSetter(app, file, fileScope, module, scope,
      statement.setter)
    ok(newResolvedStatement(resolvedMutation))
