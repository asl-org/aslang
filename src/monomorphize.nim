import results, strformat, tables, hashes

import parser/main as parser
import resolver/main as resolver
import defanalyzer/main as defanalyzer
import analyzer/main as analyzer

# Works out the concrete types for a call's target. A call records the types
# it passes (`fncallImpls`), but inside a generic function those can still
# mention the function's own type parameters. `funcImpls` says what this copy
# of the function set them to, so filling it in gives the fully concrete types
# that name the exact callee copy.
proc calleeImpls(fncallImpls: AnalyzedImplMap, funcImpls: AnalyzedImplMap): AnalyzedImplMap =
  var concreteImpls: AnalyzedImplMap
  for generic, impl in fncallImpls:
    concreteImpls[generic] = impl.concrete(funcImpls)
  concreteImpls

# Names one fully-typed copy of a function. A generic function used with
# different concrete types becomes several copies, and each copy has its own
# number. These numbers are unique across the whole program.
type FunctionId = distinct int
proc `==`(a, b: FunctionId): bool {.borrow.}
proc hash(a: FunctionId): Hash {.borrow.}

# Names one value computed inside a single function copy. Each copy numbers
# its own values from zero, so a ValueId means nothing on its own — only
# together with the function copy it belongs to.
type ValueId = distinct int

# Says which function copy we mean: the module it is in, the function itself,
# and the concrete types chosen for its generics (`impls`). Two calls that pick
# the same module, function, and types give an equal FunctionRef, so each copy
# is built only once.
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

proc `==`(a, b: FunctionRef): bool = a.hash == b.hash

# One step inside a function copy's body that produces a value. For now the
# only kind is a call: `callee` is the function copy being called and `args`
# are the values passed to it; the node's own `id` is the value it returns.
type FunctionCallNode = ref object
  callee: FunctionId
  args: seq[ValueId]

proc newFunctionCallNode(callee: FunctionId, args: seq[ValueId]): FunctionCallNode =
  FunctionCallNode(callee: callee, args: args)

type
  NodeKind = enum
    nkCall
  Node = object
    id: ValueId
    case kind: NodeKind
    of nkCall: fncall: FunctionCallNode

proc newNode(id: ValueId, fncall: FunctionCallNode): Node =
  Node(kind: nkCall, id: id, fncall: fncall)

# The work area for building one function copy. It hands out that copy's own
# ValueIds (`counter`), remembers for each variable name in scope the value it
# currently stands for (`argMap`), and collects the body's nodes as it goes
# (`nodes`).
type FunctionScope = ref object
  counter: int
  argMap: Table[Identifier, ValueId]
  nodes: seq[Node]

proc newFunctionScope(): FunctionScope = FunctionScope()

proc nextId(scope: FunctionScope): ValueId =
  let id = ValueId(scope.counter)
  scope.counter += 1
  id

# Drives the whole pass. It tracks which function copies are finished
# (`visited`) and which are still being built (`visiting`), and gives out the
# next free FunctionId (`counter`). There is one for the entire program.
type Monomorphizer = ref object
  counter: int
  visiting: Table[FunctionRef, FunctionId]
  visited: Table[FunctionRef, FunctionId]

proc newMonomorphizer(): Monomorphizer = Monomorphizer()

proc nextId(mono: Monomorphizer): FunctionId =
  let id = FunctionId(mono.counter)
  mono.counter += 1
  id

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef): Result[FunctionId, string]
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string]
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string]

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, fncall: AnalyzedFunctionCall, impls: AnalyzedImplMap): Result[ValueId, string] =
  case fncall.kind:
  of afckDefault:
    var args: seq[ValueId]
    for arg in fncall.args:
      let id = ? monomorphize(scope, mono, app, arg, impls)
      args.add(id)

    case fncall.localType.kind:
    of altkModule:
      let module = app.findModule(fncall.localType.module)
      let function = module.findFunction(fncall.funcDef)

      let funcRef = newFunctionRef(module, function, fncall.impls.calleeImpls(impls))
      let callee = ? monomorphize(mono, app, funcRef)

      let fncallNode = newFunctionCallNode(callee, args)
      let id = scope.nextId()
      scope.nodes.add(newNode(id, fncallNode))
      ok(id)
    of altkGeneric:
      err(fmt"{fncall.loc} todo: default generic function call")
  of afckTry:
    err(fmt"{fncall.loc} todo: try function call")


proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string] =
  case expression.kind:
  of aekFunctionCall:
    let id = ? monomorphize(scope, mono, app, expression.fncall, impls)
    err(fmt"{expression.loc} todo: function call")
  of aekInitializer: err(fmt"{expression.loc} todo: initializer")
  of aekStructGetter: err(fmt"{expression.loc} todo: struct getter")
  of aekMatchExpr: err(fmt"{expression.loc} todo: match expression")
  of aekVariable: err(fmt"{expression.loc} todo: variable")

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[void, string] =
  case statement.kind:
  of rskNone:
    let id = ? monomorphize(scope, mono, app, statement.expression, impls)
    err(fmt"{statement.loc} todo: raw expression")
  of rskVariable: err(fmt"{statement.loc} todo: variable assignment")
  of rskGetter: err(fmt"{statement.loc} todo: setter")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, function: AnalyzedUserFunction): Result[FunctionId, string] =
  let scope = newFunctionScope()
  for arg in function.def.args:
    scope.argMap[arg.name] = scope.nextId()

  # TODO: handle function statements.
  for statement in function.statements:
    ? monomorphize(scope, mono, app, statement, funcRef.impls)

  err("todo: handle user function")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef): Result[FunctionId, string] =
  if funcRef in mono.visited:
    ok(mono.visited[funcRef])
  else:
    # Recursion is handled here: if we reach a function copy that is still
    # being built, this is a recursive call back into it, so return the id we
    # already gave it and let the cycle close instead of looping forever.
    # TODO(occurs-check): if a recursive function keeps calling itself with
    # ever-bigger types (T, then List[T], then List[List[T]]...), each call is
    # a new copy and `visiting` never stops growing — guard against that here.
    if funcRef in mono.visiting:
      ok(mono.visiting[funcRef])
    else:
      case funcRef.function.kind:
      of afkExtern: err(fmt"todo: handle extern function monomorphization")
      of afkGenerated: err(fmt"todo: handle generated function monomorphization")
      of afkUser:
        let id = mono.nextId()
        mono.visiting[funcRef] = id

        discard ? monomorphize(mono, app, funcRef, funcRef.function.user)

        mono.visited[funcRef] = id
        mono.visiting.del(funcRef)

        ok(id)

proc monomorphize*(app: AnalyzedApp): Result[void, string] =
  let entry = ? app.entry
  assert(entry.function.kind == afkUser, "[BUG] - entry function must always be a user function")
  assert(entry.function.def.args.len == 0, "[BUG] - entry function should not accept any arguments")

  let funcRef = newFunctionRef(entry.module, entry.function, default(AnalyzedImplMap))
  discard ? monomorphize(newMonomorphizer(), app, funcRef)
  # TODO: Return a monomorphized app
  err("todo: implement monomorphized app")