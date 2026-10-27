import options, results, strformat, tables, hashes

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
# is built only once. The function is held by its concrete kind — user, extern,
# or generated — so each later stage sees exactly the shape it handles instead
# of re-casing on an AnalyzedFunction.
type
  FunctionRefKind = enum frkUser, frkExtern, frkGenerated
  FunctionRef = ref object
    module: AnalyzedModule
    impls: AnalyzedImplMap
    case kind: FunctionRefKind
    of frkUser: user: AnalyzedUserFunction
    of frkExtern: extern: AnalyzedExternFunction
    of frkGenerated: generated: AnalyzedFunctionDef

proc newFunctionRef(module: AnalyzedModule, user: AnalyzedUserFunction, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkUser, module: module, impls: impls, user: user)

proc newFunctionRef(module: AnalyzedModule, extern: AnalyzedExternFunction, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkExtern, module: module, impls: impls, extern: extern)

proc newFunctionRef(module: AnalyzedModule, generated: AnalyzedFunctionDef, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkGenerated, module: module, impls: impls, generated: generated)

proc hash(funcRef: FunctionRef): Hash =
  let functionHash =
    case funcRef.kind:
    of frkUser: funcRef.user.hash
    of frkExtern: funcRef.extern.hash
    of frkGenerated: funcRef.generated.hash
  var acc = funcRef.module.hash !& funcRef.kind.ord.hash !& functionHash
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

# A match on a value. `subject` is the value being matched; each BranchNode
# names the pattern it covers and the value it produces. The match node's own
# id is the matched result — the value of whichever branch runs.
type
  BranchNode = object
    pattern: AnalyzedCasePattern
    resultId: ValueId
  MatchNode = ref object
    subject: ValueId
    branches: seq[BranchNode]

proc newMatchNode(subject: ValueId, branches: seq[BranchNode]): MatchNode =
  MatchNode(subject: subject, branches: branches)

# A try call: like a call, but an Err result returns from the enclosing
# function. `returns` is the finalized type of the unwrapped Ok value this node
# produces; codegen emits the early return on an Err.
type TryNode = ref object
  call: FunctionCallNode
  returns: AnalyzedArgumentType

proc newTryNode(call: FunctionCallNode, returns: AnalyzedArgumentType): TryNode =
  TryNode(call: call, returns: returns)

# A literal value. `literal` is the parsed constant; `returns` is the module
# type it adopted — its finalized type.
type LiteralNode = ref object
  literal: Literal
  returns: AnalyzedArgumentType

proc newLiteralNode(literal: Literal, returns: AnalyzedArgumentType): LiteralNode =
  LiteralNode(literal: literal, returns: returns)

type
  NodeKind = enum
    nkCall, nkMatch, nkTry, nkLiteral
  Node = object
    id: ValueId
    case kind: NodeKind
    of nkCall: fncall: FunctionCallNode
    of nkMatch: match: MatchNode
    of nkTry: tryCall: TryNode
    of nkLiteral: literal: LiteralNode

proc newNode(id: ValueId, fncall: FunctionCallNode): Node =
  Node(kind: nkCall, id: id, fncall: fncall)

proc newNode(id: ValueId, match: MatchNode): Node =
  Node(kind: nkMatch, id: id, match: match)

proc newNode(id: ValueId, tryCall: TryNode): Node =
  Node(kind: nkTry, id: id, tryCall: tryCall)

proc newNode(id: ValueId, literal: LiteralNode): Node =
  Node(kind: nkLiteral, id: id, literal: literal)

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
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[ValueId, string]
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string]

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, fncall: AnalyzedFunctionCall, impls: AnalyzedImplMap): Result[ValueId, string] =
  var args: seq[ValueId]
  for arg in fncall.args:
    let argId = ? monomorphize(scope, mono, app, arg, impls)
    args.add(argId)

  var callee: FunctionId
  case fncall.localType.kind:
  of altkModule:
    let module = app.findModule(fncall.localType.module)
    let function = module.findFunction(fncall.funcDef)
    let concreteImpls = fncall.impls.calleeImpls(impls)
    let funcRef =
      case function.kind:
      of afkUser: newFunctionRef(module, function.user, concreteImpls)
      of afkExtern: newFunctionRef(module, function.extern, concreteImpls)
      of afkGenerated: newFunctionRef(module, function.generated, concreteImpls)
    callee = ? monomorphize(mono, app, funcRef)
  of altkGeneric:
    return err(fmt"{fncall.loc} todo: generic-target call")

  let id = scope.nextId()
  let node =
    case fncall.kind:
    of afckDefault:
      newNode(id, newFunctionCallNode(callee, args))
    of afckTry:
      let tryCall = newTryNode(newFunctionCallNode(callee, args), fncall.returns.concrete(impls))
      newNode(id, tryCall)

  scope.nodes.add(node)
  ok(id)


proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string] =
  case expression.kind:
  of aekFunctionCall:
    ok(? monomorphize(scope, mono, app, expression.fncall, impls))
  of aekMatchExpr:
    let subjectId = ? monomorphize(scope, mono, app, expression.match.subject, impls)
    var branches: seq[BranchNode]
    for caseBlock in expression.match.cases:
      var branchResult: ValueId
      for statement in caseBlock.statements:
        branchResult = ? monomorphize(scope, mono, app, statement, impls)
      branches.add(BranchNode(pattern: caseBlock.pattern, resultId: branchResult))
    let id = scope.nextId()
    scope.nodes.add(newNode(id, newMatchNode(subjectId, branches)))
    ok(id)
  of aekInitializer:
    case expression.init.kind:
    of aikLiteral:
      let lit = expression.init.literal
      let id = scope.nextId()
      scope.nodes.add(newNode(id, newLiteralNode(lit.literal, lit.argType.concrete(impls))))
      ok(id)
    of aikStruct: err(fmt"{expression.loc} todo: struct initializer")
    of aikUnion: err(fmt"{expression.loc} todo: union initializer")
  of aekStructGetter: err(fmt"{expression.loc} todo: struct getter")
  of aekVariable:
    # A variable is not a node — it resolves to the value its binding produced.
    let name = expression.variable.name
    assert(name in scope.argMap, "[BUG] - variable out of scope during monomorphization")
    ok(scope.argMap[name])

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[ValueId, string] =
  case statement.kind:
  of rskNone:
    monomorphize(scope, mono, app, statement.expression, impls)
  of rskVariable:
    let value = ? monomorphize(scope, mono, app, statement.expression, impls)
    let target = statement.target
    assert(target.isSome, "[BUG] - rskVariable statement has no target")
    scope.argMap[target.get] = value
    ok(value)
  of rskGetter: err(fmt"{statement.loc} todo: setter")

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, function: AnalyzedUserFunction): Result[FunctionId, string] =
  let scope = newFunctionScope()
  for arg in function.def.args:
    scope.argMap[arg.name] = scope.nextId()

  # TODO: handle function statements.
  for statement in function.statements:
    discard ? monomorphize(scope, mono, app, statement, funcRef.impls)

  err(fmt"{function.loc} todo: handle user function")

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
      case funcRef.kind:
      of frkExtern: err(fmt"{funcRef.extern.loc} todo: handle extern function monomorphization")
      of frkGenerated: err(fmt"{funcRef.generated.loc} todo: handle generated function monomorphization")
      of frkUser:
        let id = mono.nextId()
        mono.visiting[funcRef] = id

        discard ? monomorphize(mono, app, funcRef, funcRef.user)

        mono.visited[funcRef] = id
        mono.visiting.del(funcRef)

        ok(id)

proc monomorphize*(app: AnalyzedApp): Result[void, string] =
  let entry = ? app.entry
  assert(entry.function.kind == afkUser, "[BUG] - entry function must always be a user function")
  assert(entry.function.def.args.len == 0, "[BUG] - entry function should not accept any arguments")

  let funcRef = newFunctionRef(entry.module, entry.function.user, default(AnalyzedImplMap))
  discard ? monomorphize(newMonomorphizer(), app, funcRef)
  # TODO: Return a monomorphized app
  err(fmt"{entry.function.loc} todo: implement monomorphized app")