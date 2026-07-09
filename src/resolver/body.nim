## Body-level cluster — the self-mutually-recursive expression /
## statement / initializer web that walks a function body.
##
## Reads ResolvedArgumentType from argtypes, ResolvedArgumentDef via
## resolvers of struct/union initializers, and parser types (Module,
## StructRef, UnionRef, Getter, ...) directly.

import results, strformat, options, tables, hashes, sets

import ./parser
import argtypes
import funcdefs
import data
import patterns  # ResolvedCasePattern
import literals  # ResolvedLiteralDef (unused here but consistent)

type
  ResolvedGetter* = ref object
    parsed: Getter

  ResolvedLiteralInitializer* = ref object
    parsed: LiteralInitializer
    argType: ResolvedArgumentType

  ResolvedKeywordArgument* = ref object
    parsed: KeywordArgument
    expression: ResolvedExpression

  ResolvedStructRef* = ref object
    parsed: StructRef
    module: Module
    impls: seq[ResolvedArgumentType]

  ResolvedUnionRef* = ref object
    parsed: UnionRef
    module: Module
    impls: seq[ResolvedArgumentType]

  ResolvedStructInitializer* = ref object
    parsed: StructInitializer
    structRef: ResolvedStructRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedUnionInitializer* = ref object
    parsed: UnionInitializer
    unionRef: ResolvedUnionRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedInitializerKind* = enum
    rikStruct, rikUnion, rikLiteral
  ResolvedInitializer* = ref object
    case kind: ResolvedInitializerKind
    of rikStruct: struct: ResolvedStructInitializer
    of rikUnion: union: ResolvedUnionInitializer
    of rikLiteral: literal: ResolvedLiteralInitializer

  ResolvedFunctionCall* = ref object
    parsed: FunctionCall
    args: seq[ResolvedExpression]
    # Task 7: reserved for FunctionCall receivers that carry an
    # explicit impl list. The parser currently has no impl syntax for
    # function calls (FunctionCall.root is a bare Identifier, not an
    # ArgumentType), so this stays empty for now. When impl syntax is
    # added, the arity+constraint check for these impls will run in
    # resolveFunctionCall — never in the analyzer.
    impls: seq[ResolvedArgumentType]

  ResolvedAssignment* = ref object
    parsed: Assignment
    expression: ResolvedExpression

  ResolvedSetter* = ref object
    parsed: Setter
    getter: ResolvedGetter
    expression: ResolvedExpression

  ResolvedCaseBlock* = ref object
    parsed: CaseBlock
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]

  ResolvedMatchExpression* = ref object
    parsed: MatchExpression
    subject: ResolvedExpression
    cases: seq[ResolvedCaseBlock]

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
    rskAssignment, rskExpr, rskSetter
  ResolvedStatement* = ref object
    case kind: ResolvedStatementKind
    of rskAssignment: assignment: ResolvedAssignment
    of rskExpr: expression: ResolvedExpression
    of rskSetter: setter: ResolvedSetter

# ---- forward declarations for the body-cluster cycle ----

# resolveExpression / resolveStatement form the body-cluster cycle.
proc resolveExpression*(app: App,     file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string]

proc resolveStatement*(app: App,     file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string]

# =====================================================================
# Body-level cluster
# (Getter, LiteralInitializer, KeywordArgument, StructRef, UnionRef,
#  StructInitializer, UnionInitializer, Initializer, FunctionCall,
#  Assignment, Setter, CaseBlock, MatchExpression, Expression, Statement)
#
# Every resolveX proc threads `` — the
# table allocated by apps.nim during the declare pass — down to
# `resolveArgumentType`, which uses it to attach a stable
# ResolvedModule reference to every ResolvedModuleArgumentType.
# =====================================================================

# ---- ResolvedGetter ----

proc newResolvedGetter*(parsed: Getter): ResolvedGetter =
  ResolvedGetter(parsed: parsed)

proc parsed*(getter: ResolvedGetter): Getter = getter.parsed
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

# ---- ResolvedLiteralInitializer ----

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer,
    argType: ResolvedArgumentType): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType)

proc parsed*(init: ResolvedLiteralInitializer): LiteralInitializer = init.parsed
proc argType*(init: ResolvedLiteralInitializer): ResolvedArgumentType = init.argType
proc value*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value

proc resolveLiteralInitializer(app: App, file: parser.File, fileScope: FileScope, module: Module,
    literalInit: LiteralInitializer): Result[
        ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    literalInit.argType)
  ok(newResolvedLiteralInitializer(literalInit, resolvedArgType))

# ---- ResolvedKeywordArgument ----

proc newResolvedKeywordArgument*(parsed: KeywordArgument,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(parsed: parsed, expression: expression)

proc parsed*(kwarg: ResolvedKeywordArgument): KeywordArgument = kwarg.parsed
proc expression*(kwarg: ResolvedKeywordArgument): ResolvedExpression = kwarg.expression
proc name*(kwarg: ResolvedKeywordArgument): Identifier = kwarg.parsed.name
proc loc*(kwarg: ResolvedKeywordArgument): Location = kwarg.parsed.loc

# ---- ResolvedStructRef ----

proc newResolvedStructRef*(parsed: StructRef, module: Module,
    impls: seq[ResolvedArgumentType]): ResolvedStructRef =
  ## One-shape constructor. `impls` is empty when the surface
  ## form was `Module { ... }` and non-empty (arity + constraint checked)
  ## when the surface form was `Module[Impl, ...] { ... }`.
  ResolvedStructRef(parsed: parsed, module: module, impls: impls)

proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc module*(s: ResolvedStructRef): Module = s.module
proc impls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.impls
proc loc*(s: ResolvedStructRef): Location = s.parsed.loc

# ---- ResolvedStructInitializer ----

proc newResolvedStructInitializer*(parsed: StructInitializer,
    structRef: ResolvedStructRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(parsed: parsed, structRef: structRef, kwargs: kwargs)

proc parsed*(struct: ResolvedStructInitializer): StructInitializer = struct.parsed
proc structRef*(struct: ResolvedStructInitializer): ResolvedStructRef = struct.structRef
proc kwargs*(struct: ResolvedStructInitializer): seq[ResolvedKeywordArgument] = struct.kwargs
proc loc*(struct: ResolvedStructInitializer): Location = struct.parsed.loc

proc impls*(struct: ResolvedStructInitializer): seq[ResolvedArgumentType] =
  ## Delegates to the underlying structRef. Empty === bare initializer,
  ## non-empty === explicit-impls initializer.
  ##
  ## Invariant: every entry is arity- and constraint-validated at
  ## resolve time by resolveModuleArgumentType (see the module-context
  ## overload above). Downstream consumers can treat this seq as a
  ## provably valid value — no need to re-check.
  struct.structRef.impls

# ---- ResolvedUnionRef ----

proc newResolvedUnionRef*(parsed: UnionRef, module: Module,
    impls: seq[ResolvedArgumentType]): ResolvedUnionRef =
  ## One-shape constructor. `impls` is empty when the surface
  ## form was `Module.Variant { ... }` and non-empty (arity + constraint
  ## checked) when the surface form was `Module[Impl, ...].Variant { ... }`.
  ResolvedUnionRef(parsed: parsed, module: module, impls: impls)

proc parsed*(u: ResolvedUnionRef): UnionRef = u.parsed
proc module*(u: ResolvedUnionRef): Module = u.module
proc impls*(u: ResolvedUnionRef): seq[ResolvedArgumentType] = u.impls
proc loc*(u: ResolvedUnionRef): Location = u.parsed.loc

# ---- ResolvedUnionInitializer ----

proc newResolvedUnionInitializer*(parsed: UnionInitializer,
    unionRef: ResolvedUnionRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(parsed: parsed, unionRef: unionRef, kwargs: kwargs)

proc parsed*(init: ResolvedUnionInitializer): UnionInitializer = init.parsed
proc unionRef*(init: ResolvedUnionInitializer): ResolvedUnionRef = init.unionRef
proc kwargs*(init: ResolvedUnionInitializer): seq[ResolvedKeywordArgument] = init.kwargs
proc loc*(init: ResolvedUnionInitializer): Location = init.parsed.loc
proc module*(init: ResolvedUnionInitializer): Module = module(init.unionRef)
proc variant*(init: ResolvedUnionInitializer): Identifier = init.parsed.variant

proc impls*(init: ResolvedUnionInitializer): seq[ResolvedArgumentType] =
  ## Delegates to the underlying unionRef. Empty === bare initializer,
  ## non-empty === explicit-impls initializer.
  ##
  ## Invariant: every entry is arity- and constraint-validated at
  ## resolve time by resolveModuleArgumentType. Downstream consumers
  ## can treat this seq as a provably valid value — no need to re-check.
  init.unionRef.impls

# ---- ResolvedInitializer ----

proc newResolvedInitializer*(struct: ResolvedStructInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikStruct, struct: struct)

proc newResolvedInitializer*(union: ResolvedUnionInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikUnion, union: union)

proc newResolvedInitializer*(literal: ResolvedLiteralInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikLiteral, literal: literal)

proc kind*(init: ResolvedInitializer): ResolvedInitializerKind = init.kind
proc literal*(init: ResolvedInitializer): ResolvedLiteralInitializer =
  assert init.kind == rikLiteral,
    fmt"ResolvedInitializer.literal accessed but kind is {init.kind}"
  init.literal
proc union*(init: ResolvedInitializer): ResolvedUnionInitializer =
  assert init.kind == rikUnion,
    fmt"ResolvedInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: ResolvedInitializer): ResolvedStructInitializer =
  assert init.kind == rikStruct,
    fmt"ResolvedInitializer.struct accessed but kind is {init.kind}"
  init.struct
proc loc*(init: ResolvedInitializer): Location =
  case init.kind:
  of rikLiteral: init.literal.loc
  of rikStruct: init.struct.loc
  of rikUnion: init.union.loc

# ---- ResolvedFunctionCall ----

proc newResolvedFunctionCall*(parsed: FunctionCall,
    args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(parsed: parsed, args: args)

proc parsed*(fncall: ResolvedFunctionCall): FunctionCall = fncall.parsed
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args
proc loc*(fncall: ResolvedFunctionCall): Location = fncall.parsed.loc

proc impls*(fncall: ResolvedFunctionCall): seq[ResolvedArgumentType] =
  ## Empty for the time being — the parser has no impl syntax for
  ## FunctionCall receivers. Kept as a first-class accessor so
  ## downstream code that treats StructInit/UnionInit/FunctionCall
  ## uniformly (an "impl-carrying node") can pattern-match on it.
  ##
  ## Invariant: entries would be arity- and constraint-validated at
  ## resolve time — the current always-empty seq trivially satisfies
  ## that.
  fncall.impls

# ---- ResolvedAssignment ----

proc newResolvedAssignment*(parsed: Assignment,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(parsed: parsed, expression: expression)

proc parsed*(assignment: ResolvedAssignment): Assignment = assignment.parsed
proc expression*(assignment: ResolvedAssignment): ResolvedExpression = assignment.expression
proc loc*(assignment: ResolvedAssignment): Location = assignment.parsed.loc
proc target*(assignment: ResolvedAssignment): Identifier = assignment.parsed.target

# ---- ResolvedSetter ----

proc newResolvedSetter*(parsed: Setter, getter: ResolvedGetter,
    expression: ResolvedExpression): ResolvedSetter =
  ResolvedSetter(parsed: parsed, getter: getter, expression: expression)

proc parsed*(setter: ResolvedSetter): Setter = setter.parsed
proc getter*(setter: ResolvedSetter): ResolvedGetter = setter.getter
proc expression*(setter: ResolvedSetter): ResolvedExpression = setter.expression
proc loc*(setter: ResolvedSetter): Location = setter.parsed.loc

# ---- ResolvedCaseBlock ----

proc newResolvedCaseBlock*(parsed: CaseBlock, pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(parsed: parsed, pattern: pattern, statements: statements)

proc parsed*(caseBlock: ResolvedCaseBlock): CaseBlock = caseBlock.parsed
proc pattern*(caseBlock: ResolvedCaseBlock): ResolvedCasePattern = caseBlock.pattern
proc statements*(caseBlock: ResolvedCaseBlock): seq[ResolvedStatement] = caseBlock.statements
proc loc*(caseBlock: ResolvedCaseBlock): Location = caseBlock.parsed.loc

# ---- ResolvedMatchExpression ----

proc newResolvedMatchExpression*(parsed: MatchExpression,
    subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(parsed: parsed, subject: subject, cases: cases)

proc parsed*(match: ResolvedMatchExpression): MatchExpression = match.parsed
proc subject*(match: ResolvedMatchExpression): ResolvedExpression = match.subject
proc cases*(match: ResolvedMatchExpression): seq[ResolvedCaseBlock] = match.cases
proc loc*(match: ResolvedMatchExpression): Location = match.parsed.loc

# ---- ResolvedExpression ----

proc newResolvedExpression*(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: rekFunctionCall, fncall: fncall)

proc newResolvedExpression*(initializer: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: rekInitializer, initializer: initializer)

proc newResolvedExpression*(variable: Identifier): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, variable: variable)

proc newResolvedExpression*(literal: Literal): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc newResolvedExpression*(getter: ResolvedGetter): ResolvedExpression =
  ResolvedExpression(kind: rekGetter, getter: getter)

proc newResolvedExpression*(match: ResolvedMatchExpression): ResolvedExpression =
  ResolvedExpression(kind: rekMatchExpr, match: match)

proc kind*(expression: ResolvedExpression): ResolvedExpressionKind = expression.kind
proc fncall*(expression: ResolvedExpression): ResolvedFunctionCall =
  assert expression.kind == rekFunctionCall,
    fmt"ResolvedExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc variable*(expression: ResolvedExpression): Identifier =
  assert expression.kind == rekVariable,
    fmt"ResolvedExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc literal*(expression: ResolvedExpression): Literal =
  assert expression.kind == rekLiteral,
    fmt"ResolvedExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: ResolvedExpression): ResolvedMatchExpression =
  assert expression.kind == rekMatchExpr,
    fmt"ResolvedExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: ResolvedExpression): ResolvedInitializer =
  assert expression.kind == rekInitializer,
    fmt"ResolvedExpression.init accessed but kind is {expression.kind}"
  expression.initializer
proc getter*(expression: ResolvedExpression): ResolvedGetter =
  assert expression.kind == rekGetter,
    fmt"ResolvedExpression.getter accessed but kind is {expression.kind}"
  expression.getter
proc loc*(expression: ResolvedExpression): Location =
  case expression.kind:
  of rekFunctionCall: expression.fncall.loc
  of rekGetter: expression.getter.loc
  of rekInitializer: expression.init.loc
  of rekMatchExpr: expression.match.loc
  of rekVariable: expression.variable.loc
  of rekLiteral: expression.literal.loc

# ---- ResolvedStatement ----

proc newResolvedStatement*(assignment: ResolvedAssignment): ResolvedStatement =
  ResolvedStatement(kind: rskAssignment, assignment: assignment)

proc newResolvedStatement*(expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(kind: rskExpr, expression: expression)

proc newResolvedStatement*(setter: ResolvedSetter): ResolvedStatement =
  ResolvedStatement(kind: rskSetter, setter: setter)

proc kind*(statement: ResolvedStatement): ResolvedStatementKind = statement.kind
proc expression*(statement: ResolvedStatement): ResolvedExpression =
  assert statement.kind == rskExpr,
    fmt"ResolvedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: ResolvedStatement): ResolvedAssignment =
  assert statement.kind == rskAssignment,
    fmt"ResolvedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc setter*(statement: ResolvedStatement): ResolvedSetter =
  assert statement.kind == rskSetter,
    fmt"ResolvedStatement.setter accessed but kind is {statement.kind}"
  statement.setter
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

# ---- Body resolve* procs ----

proc resolveFunctionCall(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let definedType = ? file.findType(fileScope, fncall.root)
  let funcDefs = ? definedType.findFunctionDefs(fncall.name, fncall.args.len)
  if funcDefs.len == 0:
    err(fmt"{fncall.loc} generic `{definedType.generic.name.asl}` does not have any function named `{fncall.name.asl}` with arity `{fncall.args.len}`")
  else:
    var resolvedArgs: seq[ResolvedExpression]
    for arg in fncall.args:
      let resolvedArg = ? resolveExpression(app, file, fileScope, module, scope, arg)
      resolvedArgs.add(resolvedArg)
    ok(newResolvedFunctionCall(fncall, resolvedArgs))

proc resolveStructRef(app: App, file: parser.File, fileScope: FileScope, module: Module,
    structRef: StructRef): Result[ResolvedStructRef, string] =
  ## Resolves a StructRef into the one-shape (module + impls).
  ## Validates the "receiver-declares-requires ↔ impls-provided" match
  ## and delegates to resolveModuleArgumentType so the impls
  ## seq is arity- and constraint-checked at resolve time.
  let structModule = ? file.findModule(fileScope, structRef.module)
  if structRef.impls.len == 0 and structModule.requires.isSome:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` declares requires; initializer must specify impl types as `{structModule.name.asl}[...]`")
  if structRef.impls.len > 0 and not structModule.requires.isSome:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` has no requires block; initializer must not specify impl types")
  if structRef.impls.len == 0:
    return ok(newResolvedStructRef(structRef, structModule, @[]))
  # Reuse the module-context argType resolver so arity + constraint
  # validation stays in one place. Build a synthetic ArgumentType from
  # the parser StructRef's (module, impls, loc) and unwrap its
  # impls after the check.
  let syntheticArgType = newArgumentType(structRef.module, structRef.impls, structRef.loc)
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, syntheticArgType)
  ok(newResolvedStructRef(structRef, structModule, resolvedArgType.module.impls))

proc resolveStructInitializer(app: App, file: parser.File, fileScope: FileScope, module: Module, scope: FunctionScope,
    struct: StructInitializer): Result[ResolvedStructInitializer, string] =
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

proc resolveUnionRef(app: App, file: parser.File, fileScope: FileScope, module: Module,
    unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  ## Resolves a UnionRef into the one-shape (module + impls).
  ## Empty impls drive leave-as-is inference at the analyzer; non-empty
  ## impls are arity- and constraint-checked here via
  ## resolveModuleArgumentType so the analyzer can seed its
  ## GenericImplMap from the seq directly.
  let unionModule = ? file.findModule(fileScope, unionRef.module)
  if unionRef.impls.len == 0:
    return ok(newResolvedUnionRef(unionRef, unionModule, @[]))
  let syntheticArgType = newArgumentType(unionRef.module, unionRef.impls, unionRef.loc)
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, syntheticArgType)
  ok(newResolvedUnionRef(unionRef, unionModule, resolvedArgType.module.impls))

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

proc resolveExpression*(app: App,     file: parser.File, fileScope: FileScope,
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

proc resolveStatement*(app: App,     file: parser.File, fileScope: FileScope,
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

