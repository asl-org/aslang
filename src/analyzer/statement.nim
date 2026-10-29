## Body-level statement cluster — the self-mutually-recursive
## expression / statement / initializer web that walks a function
## body. Nim requires mutually-referencing `ref object` types to share
## one `type` block, so every node in the cycle lives here:
##
##   AnalyzedFunctionCall, AnalyzedKeywordArgument,
##   AnalyzedStructInitializer, AnalyzedUnionInitializer,
##   AnalyzedInitializer, AnalyzedCaseBlock,
##   AnalyzedMatchExpression, AnalyzedExpression, AnalyzedStatement
##
## Leaf nodes that carry no back-reference into the cycle
## (AnalyzedVariable, AnalyzedStructGetter, AnalyzedLiteralInitializer) live
## in their own files and are imported here. AnalyzedBinding and
## AnalyzedCasePattern come from the pattern cluster (pattern.nim).

import strformat, options

import ../tokenizer/main as tokenizer
import ../parser/main as parser
import ../resolver/main as resolver
import ../defanalyzer/main as defanalyzer
import pattern

# ---- AnalyzedStructGetter (resolved struct field access) ----

type AnalyzedStructGetter* = ref object
  resolved: ResolvedGetter
  source: AnalyzedModuleArgumentType
  property: AnalyzedArgumentDef

proc newAnalyzedStructGetter*(resolved: ResolvedGetter, source: AnalyzedModuleArgumentType, property: AnalyzedArgumentDef): AnalyzedStructGetter =
  AnalyzedStructGetter(resolved: resolved, source: source, property: property)

proc loc*(structGetter: AnalyzedStructGetter): Location = structGetter.resolved.loc
proc source*(structGetter: AnalyzedStructGetter): AnalyzedModuleArgumentType = structGetter.source
proc sourceName*(structGetter: AnalyzedStructGetter): Identifier = structGetter.resolved.source
proc property*(structGetter: AnalyzedStructGetter): AnalyzedArgumentDef = structGetter.property
proc argType*(structGetter: AnalyzedStructGetter): AnalyzedArgumentType =
  structGetter.property.argType.concrete(structGetter.source.impls)

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
  AnalyzedFunctionCallKind* = enum
    afckDefault, afckTry
  AnalyzedFunctionCall* = ref object
    def: AnalyzedDefFunctionCall
    localType: AnalyzedLocalType
    funcDef: AnalyzedFunctionDef
    args: seq[AnalyzedExpression]
    impls: AnalyzedImplMap
    # A plain call (afckDefault) evaluates to the callee's return type
    # concretized with `impls`. A `try f()` call (afckTry) evaluates to
    # the unwrapped `Ok` value type of the callee's `Status[Value, Error]`
    # return, carried in `tryValue` (see `returns`).
    case kind*: AnalyzedFunctionCallKind
    of afckDefault: discard
    of afckTry: tryValue: AnalyzedArgumentType

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

  AnalyzedExpressionKind* = enum
    aekVariable, aekFunctionCall, aekMatchExpr, aekInitializer, aekStructGetter
  AnalyzedExpression* = ref object
    case kind: AnalyzedExpressionKind
    of aekVariable: variable: AnalyzedVariable
    of aekFunctionCall: fncall: AnalyzedFunctionCall
    of aekMatchExpr: match: AnalyzedMatchExpression
    of aekInitializer: init: AnalyzedInitializer
    of aekStructGetter: structGetter: AnalyzedStructGetter

  AnalyzedStatementKind* = enum
    askNone, askVariable, askGetter
  AnalyzedStatement* = ref object
    def: AnalyzedDefStatement
    expression: AnalyzedExpression
    case kind: AnalyzedStatementKind
    of askNone: discard
    of askVariable: targetName: Identifier
    of askGetter: getter: AnalyzedStructGetter

proc argType*(expression: AnalyzedExpression): AnalyzedArgumentType
proc argType*(statement: AnalyzedStatement): AnalyzedArgumentType

proc newAnalyzedFunctionCall*(def: AnalyzedDefFunctionCall, localType: AnalyzedLocalType, funcDef: AnalyzedFunctionDef, args: seq[AnalyzedExpression], impls: AnalyzedImplMap): AnalyzedFunctionCall =
  AnalyzedFunctionCall(kind: afckDefault, def: def, localType: localType, funcDef: funcDef, args: args, impls: impls)

proc newAnalyzedTryFunctionCall*(def: AnalyzedDefFunctionCall, localType: AnalyzedLocalType, funcDef: AnalyzedFunctionDef, args: seq[AnalyzedExpression], impls: AnalyzedImplMap, tryValue: AnalyzedArgumentType): AnalyzedFunctionCall =
  ## A `try f()` call: `tryValue` is the callee's `Status` value type,
  ## which becomes this call's result type (see `returns`).
  AnalyzedFunctionCall(kind: afckTry, def: def, localType: localType, funcDef: funcDef, args: args, impls: impls, tryValue: tryValue)

proc loc*(fncall: AnalyzedFunctionCall): Location = fncall.def.resolved.loc
proc localType*(fncall: AnalyzedFunctionCall): AnalyzedLocalType = fncall.localType
proc funcDef*(fncall: AnalyzedFunctionCall): AnalyzedFunctionDef = fncall.funcDef
proc impls*(fncall: AnalyzedFunctionCall): AnalyzedImplMap = fncall.impls
proc args*(fncall: AnalyzedFunctionCall): seq[AnalyzedExpression] = fncall.args
proc returns*(fncall: AnalyzedFunctionCall): AnalyzedArgumentType =
  case fncall.kind:
  of afckDefault: fncall.funcDef.returns.concrete(fncall.impls)
  # `try f()` yields the unwrapped Ok value; analyzeFunctionCall proved
  # the callee returns a Status and stashed that value type here.
  of afckTry: fncall.tryValue

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

proc newAnalyzedStatement*(def: AnalyzedDefStatement, expression: AnalyzedExpression): AnalyzedStatement =
  ## For rskNone / rskVariable; a setter (rskGetter) uses the getter overload.
  case def.kind:
  of rskNone: AnalyzedStatement(kind: askNone, def: def, expression: expression)
  of rskVariable:
    assert(def.target.isSome, fmt"{def.loc} [BUG] - rskVariable statement has no target")
    AnalyzedStatement(kind: askVariable, def: def, expression: expression, targetName: def.target.get)
  of rskGetter:
    raise newException(Defect, fmt"{def.loc} [BUG] - a setter statement must be built with its getter")

proc newAnalyzedStatement*(def: AnalyzedDefStatement, expression: AnalyzedExpression, getter: AnalyzedStructGetter): AnalyzedStatement =
  AnalyzedStatement(kind: askGetter, def: def, expression: expression, getter: getter)

proc loc*(statement: AnalyzedStatement): Location = statement.def.loc
proc kind*(statement: AnalyzedStatement): AnalyzedStatementKind = statement.kind
proc target*(statement: AnalyzedStatement): Option[Identifier] =
  case statement.kind:
  of askVariable: some(statement.targetName)
  of askNone, askGetter: none(Identifier)
proc getter*(statement: AnalyzedStatement): AnalyzedStructGetter =
  assert(statement.kind == askGetter, fmt"{statement.loc} [BUG] - getter accessed on a non-setter statement")
  statement.getter
proc argType*(statement: AnalyzedStatement): AnalyzedArgumentType = statement.expression.argType
proc expression*(statement: AnalyzedStatement): AnalyzedExpression = statement.expression
proc arg*(statement: AnalyzedStatement): Option[AnalyzedBinding] =
  # Only a targeted assignment introduces a new binding into the function
  # scope; a targetless one (bare expression / field mutation) returns
  # none. Post-Approach C every statement's argType is concrete, so no
  # "no-type" fallback.
  let maybeTarget = statement.target
  if maybeTarget.isSome: some(newAnalyzedBinding(maybeTarget.get, statement.argType))
  else: none(AnalyzedBinding)


proc newAnalyzedExpression*(variable: AnalyzedVariable): AnalyzedExpression =
  AnalyzedExpression(kind: aekVariable, variable: variable)

proc newAnalyzedExpression*(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: aekFunctionCall, fncall: fncall)

proc newAnalyzedExpression*(match: AnalyzedMatchExpression): AnalyzedExpression =
  AnalyzedExpression(kind: aekMatchExpr, match: match)

proc newAnalyzedExpression*(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: aekInitializer, init: init)

proc newAnalyzedExpression*(structGetter: AnalyzedStructGetter): AnalyzedExpression =
  AnalyzedExpression(kind: aekStructGetter, structGetter: structGetter)

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
proc structGetter*(expression: AnalyzedExpression): AnalyzedStructGetter =
  assert expression.kind == aekStructGetter,
    fmt"AnalyzedExpression.structGetter accessed but kind is {expression.kind}"
  expression.structGetter

proc loc*(expression: AnalyzedExpression): Location =
  case expression.kind:
  of aekFunctionCall: expression.fncall.loc
  of aekVariable: expression.variable.loc
  of aekStructGetter: expression.structGetter.loc
  of aekMatchExpr: expression.match.loc
  of aekInitializer: expression.init.loc

proc argType*(expression: AnalyzedExpression): AnalyzedArgumentType =
  case expression.kind:
  of aekFunctionCall: expression.fncall.returns
  of aekVariable: expression.variable.argType
  of aekMatchExpr: expression.match.returns
  of aekInitializer: newAnalyzedArgumentType(expression.init.argType)
  of aekStructGetter: expression.structGetter.argType

# The generic bindings the expression carries for its result type —
# the map a match/case pattern uses to concretize a variant field
# pulled from the subject. It is simply the result type's own impl map:
# every AnalyzedModuleArgumentType carries the slot→impl bindings of its
# instantiation (`Status[u8, Error]` → {Any: u8, Failure: Error}), so the map a consumer needs
# is intrinsic to the type, whatever expression produced it.
proc impls*(expression: AnalyzedExpression): AnalyzedImplMap =
  expression.argType.impls
