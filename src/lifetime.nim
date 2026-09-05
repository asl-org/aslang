import results, tables, strformat

import analyzer/index as analyzer

type
  SourceKind = enum
    skLocal, skInput
  Source = ref object
    case kind: SourceKind
    of skLocal: statement: int
    of skInput: position: int

proc newInputSource(position: int): Source =
  Source(kind: skInput, position: position)

proc newLocalSource(statement: int): Source =
  Source(kind: skLocal, statement: statement)


proc analyzeLifetime(app: AnalyzedApp, function: AnalyzedFunction): Result[void, string]
proc analyzeLifetime(app: AnalyzedApp, scope: Table[Identifier, Source], expression: AnalyzedExpression): Result[void, string]

proc analyzeLifetime(app: AnalyzedApp, scope: Table[Identifier, Source], fncall: AnalyzedFunctionCall): Result[void, string] =
  let localType = fncall.localType
  case localType.kind:
  of altkGeneric:
    err(fmt"{fncall.loc} todo: analyze lifetime of generic function call")
  of altkModule:
    let module = app.findModule(localType.module)
    let function = module.findFunction(fncall.funcDef)
    ? analyzeLifetime(app, function)
    err(fmt"{fncall.loc} todo: analyze lifetime of module function call")

proc analyzeLifetime(app: AnalyzedApp, scope: Table[Identifier, Source], match: AnalyzedMatchExpression): Result[void, string] =
  err(fmt"{match.loc} todo: analyze lifetime of match expression")

proc analyzeLifetime(app: AnalyzedApp, scope: Table[Identifier, Source], expression: AnalyzedExpression): Result[void, string] =
  case expression.kind:
  of aekFunctionCall:
    ? analyzeLifetime(app, scope, expression.fncall)
    ok()
  of aekVariable: err(fmt"{expression.loc} todo: analyze lifetime of variable")
  of aekGetter: err(fmt"{expression.loc} todo: analyze lifetime of getter")
  of aekInitializer: err(fmt"{expression.loc} todo: analyze lifetime of initializer")
  of aekMatchExpr:
    ? analyzeLifetime(app, scope, expression.match)
    ok()

proc analyzeLifetime(app: AnalyzedApp, scope: Table[Identifier, Source], statement: AnalyzedStatement): Result[void, string] =
  case statement.kind:
  of askAssignment: err(fmt"{statement.loc} todo: analyze lifetime of analyzed Assignment")
  of askExpr:
    ? analyzeLifetime(app, scope, statement.expression)
    ok()
  of askSetter: err(fmt"{statement.loc} todo: analyze lifetime of analyzed Setter")

proc analyzeLifetime(app: AnalyzedApp, function: AnalyzedFunction): Result[void, string] =
  case function.kind:
  of afkExtern:
    err(fmt"{function.loc} todo: analyze lifetime of extern function")
  of afkUser:
    let function = function.user
    let def = function.def

    var scope: Table[Identifier, Source]
    for index, arg in def.args:
      scope[arg.name] = newInputSource(index)

    for statement in function.statements:
      ? analyzeLifetime(app, scope, statement)
    ok()

proc analyzeLifetime*(app: AnalyzedApp): Result[void, string] =
  let entry = ? app.entry
  let startFunction = entry.function
  assert(startFunction.kind == afkUser, "[BUG] - extern function are not supported as the entry point")
  ? analyzeLifetime(app, startFunction)
  ok()