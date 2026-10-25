import results, strformat, tables, hashes, sequtils

import parser/main as parser
import resolver/main as resolver
import defanalyzer/main as defanalyzer
import analyzer/main as analyzer

type FunctionId = distinct int
proc `==`(a, b: FunctionId): bool {.borrow.}
proc hash(a: FunctionId): Hash {.borrow.}

type ValueId = distinct int

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

# A FunctionRef is the memo key, so it needs value equality: without an
# explicit `==` a `ref object` compares by pointer identity, and since a
# fresh FunctionRef is allocated at every call site the visiting/visited
# tables would never dedup (and recursion would never terminate). Mirrors
# the hash-based `==` convention used across the analyzer/resolver layers.
proc `==`(a, b: FunctionRef): bool = a.hash == b.hash

type Monomorphizer = ref object
  counter: int
  visiting: Table[FunctionRef, FunctionId]
  visited: Table[FunctionRef, FunctionId]

proc newMonomorphizer(): Monomorphizer = Monomorphizer()

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, args: seq[ValueId]): Result[FunctionId, string]
proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, argMap: var Table[Identifier, ValueId], statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string]
proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, argMap: var Table[Identifier, ValueId], expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string]

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, argMap: var Table[Identifier, ValueId], fncall: AnalyzedFunctionCall, impls: AnalyzedImplMap): Result[ValueId, string] =
  case fncall.kind:
  of afckDefault:
    var args: seq[ValueId]
    for arg in fncall.args:
      let id = ? monomorphize(mono, app, argMap, arg, impls)
      args.add(id)

    case fncall.localType.kind:
    of altkModule:
      let module = app.findModule(fncall.localType.module)
      let function = module.findFunction(fncall.funcDef)

      var calleeImpls: AnalyzedImplMap
      for generic, impl in fncall.impls:
        calleeImpls[generic] = impl.concrete(impls)
      let funcRef = newFunctionRef(module, function, calleeImpls)
      let id = ? monomorphize(mono, app, funcRef, args)

      err(fmt"{fncall.loc} todo: default module function call")
    of altkGeneric:
      err(fmt"{fncall.loc} todo: default generic function call")
  of afckTry:
    err(fmt"{fncall.loc} todo: try function call")


proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, argMap: var Table[Identifier, ValueId], expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string] =
  case expression.kind:
  of aekFunctionCall:
    let id = ? monomorphize(mono, app, argMap, expression.fncall, impls)
    err(fmt"{expression.loc} todo: function call")
  of aekInitializer: err(fmt"{expression.loc} todo: initializer")
  of aekStructGetter: err(fmt"{expression.loc} todo: struct getter")
  of aekMatchExpr: err(fmt"{expression.loc} todo: match expression")
  of aekVariable: err(fmt"{expression.loc} todo: variable")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, argMap: var Table[Identifier, ValueId], statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string] =
  case statement.kind:
  of rskNone:
    let id = ? monomorphize(mono, app, argMap, statement.expression, impls)
    err(fmt"{statement.loc} todo: raw expression")
  of rskVariable: err(fmt"{statement.loc} todo: variable assignment")
  of rskGetter: err(fmt"{statement.loc} todo: setter")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, function: AnalyzedUserFunction, args: seq[ValueId]): Result[FunctionId, string] =
  var argMap: Table[Identifier, ValueId]
  for (id, arg) in zip(args, function.def.args):
    argMap[arg.name] = id

  # TODO: handle function statements.
  for statement in function.statements:
    ? monomorphize(mono, app, argMap, statement, funcRef.impls)

  err("todo: handle user function")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, args: seq[ValueId]): Result[FunctionId, string] =
  if funcRef in mono.visited:
    ok(mono.visited[funcRef])
  else:
    # Recursion knot: a funcRef already on the stack is a recursive call into
    # the same instantiation; return its in-progress id so the caller ties the
    # cycle. TODO(occurs-check): polymorphic recursion whose type args grow
    # (T -> List[T] -> ...) mints a fresh funcRef each level, so `visiting`
    # grows without bound — guard that here before it can run away.
    if funcRef in mono.visiting:
      ok(mono.visiting[funcRef])
    else:

      case funcRef.function.kind:
      of afkExtern: err(fmt"todo: handle extern function monomorphization")
      of afkGenerated: err(fmt"todo: handle generated function monomorphization")
      of afkUser:
        mono.visiting[funcRef] = FunctionId(mono.counter)
        mono.counter += 1

        let id = ? monomorphize(mono, app, funcRef, funcRef.function.user, args)

        mono.visited[funcRef] = mono.visiting[funcRef]
        mono.visiting.del(funcRef)
        ok(mono.visited[funcRef])

proc monomorphize*(app: AnalyzedApp): Result[void, string] =
  let entry = ? app.entry
  assert(entry.function.kind == afkUser, "[BUG] - entry function must always be a user function")
  assert(entry.function.def.args.len == 0, "[BUG] - entry function should not accept any arguments")

  let funcRef = newFunctionRef(entry.module, entry.function, default(AnalyzedImplMap))
  discard ? monomorphize(newMonomorphizer(), app, funcRef, @[])
  # TODO: Return a monomorphized app
  err("todo: implement monomorphized app")