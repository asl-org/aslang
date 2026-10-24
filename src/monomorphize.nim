import options, results, strformat, tables, sets, hashes, sequtils

import parser/main as parser
import resolver/main as resolver
import defanalyzer/main as defanalyzer
import analyzer/main as analyzer
import lsp/main as lsp

type FunctionRef = ref object
  module: AnalyzedModule
  function: AnalyzedFunction
  impls: AnalyzedImplMap

proc newFunctionRef(module: AnalyzedModule, function: AnalyzedFunction, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(module: module, function: function, impls: impls)

proc hash(funcRef: FunctionRef): Hash =
  var acc = funcRef.module.hash !& funcRef.function.hash
  for _, impl in funcRef.impls:
    acc = acc !& impl.hash
  return acc

type State = ref object
  counter: int
  visiting: Table[FunctionRef, int]
  visited: Table[FunctionRef, int]

proc newState(): State = State()

proc monomorphize(state: State, app: AnalyzedApp, funcRef: FunctionRef, args: seq[int]): Result[int, string]
proc monomorphize(state: State, app: AnalyzedApp, argMap: var Table[Identifier, int], statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string]
proc monomorphize(state: State, app: AnalyzedApp, argMap: var Table[Identifier, int], expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[int, string]

proc monomorphize(state: State, app: AnalyzedApp, argMap: var Table[Identifier, int], fncall: AnalyzedFunctionCall, impls: AnalyzedImplMap): Result[int, string] =
  case fncall.kind:
  of afckDefault:
    var args: seq[int]
    for arg in fncall.args:
      let id = ? monomorphize(state, app, argMap, arg, impls)
      args.add(id)

    case fncall.localType.kind:
    of altkModule:
      let module = app.findModule(fncall.localType.module)
      let function = module.findFunction(fncall.funcDef)
      let funcRef = newFunctionRef(module, function, fncall.impls)
      let id = ? monomorphize(state, app, funcRef, args)

      err(fmt"{fncall.loc} todo: default module function call")
    of altkGeneric:
      err(fmt"{fncall.loc} todo: default generic function call")
  of afckTry:
    err(fmt"{fncall.loc} todo: try function call")


proc monomorphize(state: State, app: AnalyzedApp, argMap: var Table[Identifier, int], expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[int, string] =
  case expression.kind:
  of aekFunctionCall:
    let id = ? monomorphize(state, app, argMap, expression.fncall, impls)
    err(fmt"{expression.loc} todo: function call")
  of aekInitializer: err(fmt"{expression.loc} todo: initializer")
  of aekStructGetter: err(fmt"{expression.loc} todo: struct getter")
  of aekMatchExpr: err(fmt"{expression.loc} todo: match expression")
  of aekVariable: err(fmt"{expression.loc} todo: variable")

proc monomorphize(state: State, app: AnalyzedApp, argMap: var Table[Identifier, int], statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string] =
  case statement.kind:
  of rskNone:
    let id = ? monomorphize(state, app, argMap, statement.expression, impls)
    err(fmt"{statement.loc} todo: raw expression")
  of rskVariable: err(fmt"{statement.loc} todo: variable assignment")
  of rskGetter: err(fmt"{statement.loc} todo: setter")

proc monomorphize(state: State, app: AnalyzedApp, funcRef: FunctionRef, function: AnalyzedUserFunction, args: seq[int]): Result[int, string] =
  var argMap: Table[Identifier, int]
  for (id, arg) in zip(args, function.def.args):
    argMap[arg.name] = id

  # TODO: handle function statements.
  for statement in function.statements:
    ? monomorphize(state, app, argMap, statement, funcRef.impls)

  err("todo: handle user function")

proc monomorphize(state: State, app: AnalyzedApp, funcRef: FunctionRef, args: seq[int]): Result[int, string] =
  if funcRef in state.visited:
    ok(state.visited[funcRef])
  else:
    if funcRef in state.visiting:
      ok(state.visiting[funcRef])
    else:

      case funcRef.function.kind:
      of afkExtern: err(fmt"todo: handle extern function monomorphization")
      of afkGenerated: err(fmt"todo: handle generated function monomorphization")
      of afkUser:
        state.visiting[funcRef] = state.counter
        state.counter += 1

        let id = ? monomorphize(state, app, funcRef, funcRef.function.user, args)

        state.visited[funcRef] = state.visiting[funcRef]
        state.visiting.del(funcRef)
        ok(state.visited[funcRef])

proc monomorphize*(app: AnalyzedApp): Result[void, string] =
  let entry = ? app.entry
  assert(entry.function.kind == afkUser, "[BUG] - entry function must always be a user function")
  assert(entry.function.def.args.len == 0, "[BUG] - entry function should not accept any arguments")

  let funcRef = newFunctionRef(entry.module, entry.function, default(AnalyzedImplMap))
  discard ? monomorphize(newState(), app, funcRef, @[])
  # TODO: Return a monomorphized app
  err("todo: implement monomorphized app")