## Body-level statement cluster — the self-mutually-recursive
## expression / statement / initializer web that walks a function
## body. Nim requires mutually-referencing `ref object` types to share
## one `type` block, so every node in the cycle lives here:
##
##   AnalyzedFunctionCall, AnalyzedKeywordArgument,
##   AnalyzedStructRef, AnalyzedUnionRef,
##   AnalyzedStructInitializer, AnalyzedUnionInitializer,
##   AnalyzedInitializer, AnalyzedCaseBlock,
##   AnalyzedMatchExpression, AnalyzedAssignment, AnalyzedSetter,
##   AnalyzedExpression, AnalyzedStatement
##
## Leaf nodes that carry no back-reference into the cycle
## (AnalyzedVariable, AnalyzedGetter, AnalyzedLiteralInitializer) live
## in their own files and are imported here. AnalyzedBinding is a
## pure tuple alias imported from binding.nim; AnalyzedCasePattern is
## the pattern-cluster leaf imported from casepattern.nim.

import strformat, options

import ./defanalyzer
import binding
import casepattern
import variable
import literalinit
import getter

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
    argType: AnalyzedModuleArgumentType
    kwargs: seq[AnalyzedKeywordArgument]

  AnalyzedUnionInitializer* = ref object
    resolved: ResolvedUnionInitializer
    unionRef: AnalyzedUnionRef
    argType: AnalyzedModuleArgumentType
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
    aekVariable, aekFunctionCall, aekMatchExpr, aekInitializer, aekGetter
  AnalyzedExpression* = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
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

proc argType*(expression: AnalyzedExpression): AnalyzedArgumentType
proc argType*(statement: AnalyzedStatement): AnalyzedArgumentType

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

proc newAnalyzedStructInitializer*(resolved: ResolvedStructInitializer, structRef: AnalyzedStructRef, argType: AnalyzedModuleArgumentType, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedStructInitializer =
  AnalyzedStructInitializer(resolved: resolved, structRef: structRef, argType: argType, kwargs: kwargs)

proc resolved*(struct: AnalyzedStructInitializer): ResolvedStructInitializer = struct.resolved
proc loc*(init: AnalyzedStructInitializer): Location = init.resolved.loc
proc structRef*(struct: AnalyzedStructInitializer): AnalyzedStructRef = struct.structRef
proc argType*(struct: AnalyzedStructInitializer): AnalyzedModuleArgumentType = struct.argType
proc kwargs*(struct: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = struct.kwargs

proc newAnalyzedUnionInitializer*(resolved: ResolvedUnionInitializer, unionRef: AnalyzedUnionRef, argType: AnalyzedModuleArgumentType, variant: ResolvedVariant, kwargs: seq[AnalyzedKeywordArgument]): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(resolved: resolved, unionRef: unionRef, argType: argType, variant: variant, kwargs: kwargs)

proc resolved*(init: AnalyzedUnionInitializer): ResolvedUnionInitializer = init.resolved
proc loc*(init: AnalyzedUnionInitializer): Location = init.resolved.loc
proc unionRef*(init: AnalyzedUnionInitializer): AnalyzedUnionRef = init.unionRef
proc argType*(init: AnalyzedUnionInitializer): AnalyzedModuleArgumentType = init.argType
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

proc argType*(init: AnalyzedInitializer): AnalyzedModuleArgumentType =
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

proc argType*(caseBlock: AnalyzedCaseBlock): AnalyzedArgumentType =
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
proc argType*(assignment: AnalyzedAssignment): AnalyzedArgumentType = assignment.expression.argType

proc newAnalyzedSetter*(resolved: ResolvedSetter, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedSetter =
  AnalyzedSetter(resolved: resolved, getter: getter, expression: expression)

proc loc*(setter: AnalyzedSetter): Location = setter.resolved.loc
proc resolved*(setter: AnalyzedSetter): ResolvedSetter = setter.resolved
proc getter*(setter: AnalyzedSetter): AnalyzedGetter = setter.getter
proc expression*(setter: AnalyzedSetter): AnalyzedExpression = setter.expression
proc argType*(setter: AnalyzedSetter): AnalyzedArgumentType = setter.expression.argType

proc newAnalyzedExpression*(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression*(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

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
  of aekGetter: expression.getter.loc
  of aekMatchExpr: expression.match.loc
  of aekInitializer: expression.init.loc

proc argType*(expression: AnalyzedExpression): AnalyzedArgumentType =
  case expression.kind:
  of aekFunctionCall: expression.fncall.returns
  of aekVariable: expression.variable.argType
  of aekMatchExpr: expression.match.returns
  of aekInitializer: newAnalyzedArgumentType(expression.init.argType)
  of aekGetter: expression.getter.argType

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

proc argType*(statement: AnalyzedStatement): AnalyzedArgumentType =
  case statement.kind:
  of askExpr: statement.expression.argType
  of askAssignment: statement.assignment.argType
  of askSetter: statement.setter.argType

proc arg*(statement: AnalyzedStatement): Option[AnalyzedBinding] =
  # Only assignments introduce a new binding into the function scope;
  # bare-expression and setter statements return none. Post-Approach C
  # every statement's argType is concrete, so no "no-type" fallback.
  case statement.kind:
  of askExpr, askSetter: none(AnalyzedBinding)
  of askAssignment: some((name: statement.assignment.target, argType: statement.argType))
