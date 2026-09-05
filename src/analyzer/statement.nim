## Body-level statement cluster — the self-mutually-recursive
## expression / statement / initializer web that walks a function
## body. Nim requires mutually-referencing `ref object` types to share
## one `type` block, so every node in the cycle lives here:
##
##   AnalyzedFunctionCall, AnalyzedKeywordArgument,
##   AnalyzedStructInitializer, AnalyzedUnionInitializer,
##   AnalyzedInitializer, AnalyzedCaseBlock,
##   AnalyzedMatchExpression, AnalyzedAssignment, AnalyzedSetter,
##   AnalyzedExpression, AnalyzedStatement
##
## Leaf nodes that carry no back-reference into the cycle
## (AnalyzedVariable, AnalyzedGetter, AnalyzedLiteralInitializer) live
## in their own files and are imported here. AnalyzedBinding and
## AnalyzedCasePattern come from the pattern cluster (pattern.nim).

import strformat, options

import ./defanalyzer/index as defanalyzer
import pattern

# ---- AnalyzedGetter (resolved struct field access) ----

type AnalyzedGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedModuleArgumentType
  property: AnalyzedArgumentDef

proc newAnalyzedGetter*(resolved: ResolvedGetter, source: AnalyzedModuleArgumentType, property: AnalyzedArgumentDef): AnalyzedGetter =
  AnalyzedGetter(resolved: resolved, source: source, property: property)

proc loc*(getter: AnalyzedGetter): Location = getter.resolved.loc
proc source*(getter: AnalyzedGetter): AnalyzedModuleArgumentType = getter.source
proc argType*(getter: AnalyzedGetter): AnalyzedArgumentType =
  getter.property.argType.concrete(getter.source.impls)

# ---- AnalyzedLiteralInitializer (a literal + the argtype it adopts) ----

type AnalyzedLiteralInitializer* = ref object
  literal: Literal
  argType: AnalyzedModuleArgumentType

proc newAnalyzedLiteralInitializer*(literal: Literal, argType: AnalyzedModuleArgumentType): AnalyzedLiteralInitializer =
  AnalyzedLiteralInitializer(literal: literal, argType: argType)

proc loc*(init: AnalyzedLiteralInitializer): Location = init.literal.loc
proc argType*(init: AnalyzedLiteralInitializer): AnalyzedArgumentType = newAnalyzedArgumentType(init.argType)
proc literal*(init: AnalyzedLiteralInitializer): Literal = init.literal

# Mutually-recursive body-level cluster — every type that cycles
# back to AnalyzedExpression / AnalyzedStatement must live here.
type
  AnalyzedFunctionCall* = ref object
    def: AnalyzedDefFunctionCall
    localType: AnalyzedLocalType
    funcDef: AnalyzedFunctionDef
    args: seq[AnalyzedExpression]
    impls: AnalyzedImplMap

  AnalyzedKeywordArgument* = ref object
    def: AnalyzedDefKeywordArgument
    field: AnalyzedArgumentDef
    expression: AnalyzedExpression
    impls: AnalyzedImplMap

  AnalyzedStructInitializer* = ref object
    def: AnalyzedDefStructInitializer
    kwargs: seq[AnalyzedKeywordArgument]
    impls: AnalyzedImplMap

  AnalyzedUnionInitializer* = ref object
    def: AnalyzedDefUnionInitializer
    kwargs: seq[AnalyzedKeywordArgument]
    impls: AnalyzedImplMap

  AnalyzedInitializerKind* = enum
    aikUnion, aikStruct, aikLiteral
  AnalyzedInitializer* = ref object
    case kind: AnalyzedInitializerKind
    of aikLiteral: literal: AnalyzedLiteralInitializer
    of aikUnion: union: AnalyzedUnionInitializer
    of aikStruct: struct: AnalyzedStructInitializer

  AnalyzedCaseBlock* = ref object
    def: AnalyzedDefCase
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]

  AnalyzedMatchExpression* = ref object
    def: AnalyzedDefMatch
    subject: AnalyzedExpression
    cases: seq[AnalyzedCaseBlock]

  AnalyzedAssignment* = ref object
    def: AnalyzedDefAssignment
    expression: AnalyzedExpression

  AnalyzedSetter* = ref object
    def: AnalyzedDefSetter
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

proc newAnalyzedFunctionCall*(def: AnalyzedDefFunctionCall, localType: AnalyzedLocalType, funcDef: AnalyzedFunctionDef, args: seq[AnalyzedExpression], impls: AnalyzedImplMap): AnalyzedFunctionCall =
  AnalyzedFunctionCall(def: def, localType: localType, funcDef: funcDef, args: args, impls: impls)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.def.resolved.loc
proc localType*(fncall: AnalyzedFunctionCall): AnalyzedLocalType = fncall.localType
proc funcDef*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDef = fncall.funcDef
proc impls*(fncall: AnalyzedFunctionCall): AnalyzedImplMap = fncall.impls
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType =
  fncall.funcDef.returns.concrete(fncall.impls)

proc newAnalyzedKeywordArgument*(def: AnalyzedDefKeywordArgument, field: AnalyzedArgumentDef, expression: AnalyzedExpression, impls: AnalyzedImplMap): AnalyzedKeywordArgument =
  AnalyzedKeywordArgument(def: def, field: field, expression: expression, impls: impls)

# The generic bindings this kwarg contributes (a field typed by a free
# generic + a concrete value binds that generic; a concrete field →
# empty map). The initializer merges these across fields.
proc impls*(kwarg: AnalyzedKeywordArgument): AnalyzedImplMap = kwarg.impls
proc expression*(kwarg: AnalyzedKeywordArgument): AnalyzedExpression = kwarg.expression
proc field*(kwarg: AnalyzedKeywordArgument): AnalyzedArgumentDef = kwarg.field


proc newAnalyzedStructInitializer*(def: AnalyzedDefStructInitializer, kwargs: seq[AnalyzedKeywordArgument], impls: AnalyzedImplMap): AnalyzedStructInitializer =
  AnalyzedStructInitializer(def: def, kwargs: kwargs, impls: impls)

proc loc*(init: AnalyzedStructInitializer): Location = init.def.loc
proc kwargs*(init: AnalyzedStructInitializer): seq[AnalyzedKeywordArgument] = init.kwargs
proc argType*(init: AnalyzedStructInitializer): AnalyzedModuleArgumentType =
  newAnalyzedArgumentType(init.def.structRef.argType).concrete(init.impls).module

proc newAnalyzedUnionInitializer*(def: AnalyzedDefUnionInitializer, kwargs: seq[AnalyzedKeywordArgument], impls: AnalyzedImplMap): AnalyzedUnionInitializer =
  AnalyzedUnionInitializer(def: def, kwargs: kwargs, impls: impls)

proc loc*(init: AnalyzedUnionInitializer): Location = init.def.loc
proc variant*(init: AnalyzedUnionInitializer): Identifier = init.def.variant
proc kwargs*(init: AnalyzedUnionInitializer): seq[AnalyzedKeywordArgument] = init.kwargs
proc argType*(init: AnalyzedUnionInitializer): AnalyzedModuleArgumentType =
  let refArgType = init.def.unionRef.argType
  newAnalyzedModuleArgumentType(refArgType.resolved, refArgType.module, init.impls)

proc newAnalyzedInitializer*(literal: AnalyzedLiteralInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikLiteral, literal: literal)

proc newAnalyzedInitializer*(union: AnalyzedUnionInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikUnion, union: union)

proc newAnalyzedInitializer*(struct: AnalyzedStructInitializer): AnalyzedInitializer =
  AnalyzedInitializer(kind: aikStruct, struct: struct)

proc kind*(init: AnalyzedInitializer): AnalyzedInitializerKind = init.kind
proc literal*(init: AnalyzedInitializer): AnalyzedLiteralInitializer =
  assert init.kind == aikLiteral,
    fmt"AnalyzedInitializer.literal accessed but kind is {init.kind}"
  init.literal
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

proc newAnalyzedCaseBlock*(def: AnalyzedDefCase, pattern: AnalyzedCasePattern, statements: seq[AnalyzedStatement]): AnalyzedCaseBlock =
  AnalyzedCaseBlock(def: def, pattern: pattern, statements: statements)

proc loc*(caseBlock: AnalyzedCaseBlock): Location = caseBlock.def.resolved.loc
proc pattern*(caseBlock: AnalyzedCaseBlock): AnalyzedCasePattern = caseBlock.pattern
proc statements*(caseBlock: AnalyzedCaseBlock): seq[AnalyzedStatement] = caseBlock.statements

proc argType*(caseBlock: AnalyzedCaseBlock): AnalyzedArgumentType =
  assert(caseBlock.statements.len > 0, "UNREACHABLE: should have been caught by resolver")
  caseBlock.statements[^1].argType

proc newAnalyzedMatchExpression*(def: AnalyzedDefMatch, subject: AnalyzedExpression, cases: seq[AnalyzedCaseBlock]): AnalyzedMatchExpression =
  AnalyzedMatchExpression(def: def, subject: subject, cases: cases)

proc loc*(m: AnalyzedMatchExpression): Location = m.def.resolved.loc
proc returns*(m: AnalyzedMatchExpression): AnalyzedArgumentType = m.cases[0].argType
proc subject*(m: AnalyzedMatchExpression): AnalyzedExpression = m.subject
proc cases*(m: AnalyzedMatchExpression): seq[AnalyzedCaseBlock] = m.cases

proc newAnalyzedAssignment*(def: AnalyzedDefAssignment, expression: AnalyzedExpression): AnalyzedAssignment =
  AnalyzedAssignment(def: def, expression: expression)

proc loc*(assignment: AnalyzedAssignment): Location = assignment.def.loc
proc target*(assignment: AnalyzedAssignment): Identifier = assignment.def.target
proc argType*(assignment: AnalyzedAssignment): AnalyzedArgumentType = assignment.expression.argType
proc expression*(assignment: AnalyzedAssignment): AnalyzedExpression= assignment.expression

proc newAnalyzedSetter*(def: AnalyzedDefSetter, getter: AnalyzedGetter, expression: AnalyzedExpression): AnalyzedSetter =
  AnalyzedSetter(def: def, getter: getter, expression: expression)

proc loc*(setter: AnalyzedSetter): Location = setter.def.loc
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

# The generic bindings the expression carries for its result type —
# the map a match/case pattern uses to concretize a variant field
# pulled from the subject. It is simply the result type's own impl map:
# every AnalyzedModuleArgumentType carries the slot→impl bindings of its
# instantiation (`Status[u8]` → {Any: u8}), so the map a consumer needs
# is intrinsic to the type, whatever expression produced it.
proc impls*(expression: AnalyzedExpression): AnalyzedImplMap =
  expression.argType.impls

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
  of askAssignment: some(newAnalyzedBinding(statement.assignment.target, statement.argType))
