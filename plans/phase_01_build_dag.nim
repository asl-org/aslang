## Step 1 — Build DAG from analyzer AST. See plans/plan_dag_ir.md § Step 1.

import ./dag_ir_core, std/[tables, strutils]

type
  BuildExprKind* = enum
    ## Discriminator for `BuildExpr`. Covers the four surface forms Step 1
    ## accepts from the analyzer: literal, variable reference, call, and
    ## pattern-match branch.
    bkLit, bkVar, bkCall, bkBranch

  BuildArm* = object
    ## Analyzer-side representation of one branch arm — the pattern text
    ## and the sequence of let-bindings making up its body.
    pattern: string
    body: seq[BuildStmt]

  BuildExpr* = ref object
    ## Analyzer-side expression. Tagged union whose variants (`bkLit`,
    ## `bkVar`, `bkCall`, `bkBranch`) mirror what the resolver hands to
    ## the DAG builder. Lowered to `Node` values by the `lower*` helpers.
    loc: string
    case kind: BuildExprKind
    of bkLit:
      value: string
      ty: string
    of bkVar:
      name: string
    of bkCall:
      callee: string
      isEffect: bool
      args: seq[BuildExpr]
    of bkBranch:
      subject: string
      arms: seq[BuildArm]

  BuildStmt* = object
    ## Single let-binding `binding = rhs` in the analyzer output.
    binding: string
    rhs: BuildExpr

  BuildFunc* = object
    ## Whole-function analyzer payload — name, parameter list, and body.
    ## Concrete type paired with the `BuildInput` concept.
    name: string
    params: seq[tuple[name, ty: string]]
    body: seq[BuildStmt]

  BuildInput* = concept f
    ## Minimal contract Step 1 expects from analyzer function payloads.
    ## The `fn` parameter of `buildDag` satisfies `BuildInput`; any type
    ## exposing `name`, `params`, and `body` in the expected shapes works.
    f.name is string
    f.params is seq[tuple[name, ty: string]]
    f.body is seq[BuildStmt]

proc kind*(e: BuildExpr): BuildExprKind = e.kind
  ## Returns the tagged-union discriminator for this analyzer expression.
proc loc*(e: BuildExpr): string = e.loc
  ## Returns the source-location tag for this expression.
proc value*(e: BuildExpr): string = e.value
  ## Literal payload — textual value. Valid only for `bkLit`.
proc ty*(e: BuildExpr): string = e.ty
  ## Literal payload — type name. Valid only for `bkLit`.
proc name*(e: BuildExpr): string = e.name
  ## Variable payload — referenced binding name. Valid only for `bkVar`.
proc callee*(e: BuildExpr): string = e.callee
  ## Call payload — target function name. Valid only for `bkCall`.
proc isEffect*(e: BuildExpr): bool = e.isEffect
  ## Call payload — whether the call has observable side effects.
proc args*(e: BuildExpr): seq[BuildExpr] = e.args
  ## Call payload — positional argument expressions.
proc subject*(e: BuildExpr): string = e.subject
  ## Branch payload — name of the value being matched. Valid only for `bkBranch`.
proc arms*(e: BuildExpr): seq[BuildArm] = e.arms
  ## Branch payload — arms in declaration order.

proc pattern*(a: BuildArm): string = a.pattern
  ## Returns the arm's pattern text as it appeared in source.
proc body*(a: BuildArm): seq[BuildStmt] = a.body
  ## Returns the sequence of let-bindings composing this arm's body.

proc binding*(s: BuildStmt): string = s.binding
  ## Returns the name introduced by this let-binding.
proc rhs*(s: BuildStmt): BuildExpr = s.rhs
  ## Returns the right-hand-side expression bound by this statement.

proc name*(f: BuildFunc): string = f.name
  ## Returns the function's declared name.
proc params*(f: BuildFunc): seq[tuple[name, ty: string]] = f.params
  ## Returns the ordered parameter list `(name, type)`.
proc body*(f: BuildFunc): seq[BuildStmt] = f.body
  ## Returns the function's body as a sequence of let-bindings.

proc bindParams(dag: Dag, params: seq[tuple[name, ty: string]],
                env: var Table[string, NodeId]) =
  ## Emits an `nkParam` node per declared parameter and records the
  ## resulting id in `env` under the parameter's name.
  for p in params:
    let n = dag.newParamNode(p.name, p.ty, "<param>")
    env[p.name] = n.id

proc lowerCall(dag: Dag, e: BuildExpr,
               env: Table[string, NodeId]): NodeId =
  ## Lowers a `bkCall` expression to an `nkCall` node.
  ## Assumes every argument is already a variable reference bound in
  ## `env`; wires data edges from each argument node with the correct
  ## positional slot.
  var argIds: seq[NodeId] = @[]
  for a in e.args:
    argIds.add(env[a.name])
  let n = dag.newCallNode(e.callee, argIds, e.isEffect, e.loc)
  for i, a in argIds:
    dag.addEdge(a, n.id, ekData, uint16(i))
  n.id

proc lowerLiteral(dag: Dag, e: BuildExpr): NodeId =
  ## Lowers a `bkLit` expression to a fresh `nkLiteral` node id.
  dag.newLiteralNode(e.value, e.ty, e.loc).id

proc lowerBody(dag: Dag, body: seq[BuildStmt],
               env: var Table[string, NodeId]): NodeId
  ## Forward declaration — recursive with `lowerBranch` for nested arms.

proc lowerBranch(dag: Dag, e: BuildExpr,
                 env: var Table[string, NodeId]): NodeId =
  ## Lowers a `bkBranch` expression to an `nkBranch` node.
  ## Recursively lowers each arm body in a cloned `env` so per-arm
  ## bindings do not leak. Wires a control edge from the subject and a
  ## data edge from each arm's tail into the branch node.
  let subjectId = env[e.subject]
  var armNodes: seq[BranchArm] = @[]
  for a in e.arms:
    var armEnv = env
    let armReturn = dag.lowerBody(a.body, armEnv)
    armNodes.add(BranchArm(subjectPattern: a.pattern,
                           bodyRoots: @[armReturn], bodyReturn: armReturn))
  let br = dag.newBranchNode(subjectId, armNodes, e.loc)
  dag.addEdge(subjectId, br.id, ekControl)
  for a in armNodes:
    dag.addEdge(a.bodyReturn, br.id, ekData)
  br.id

proc lowerRhs(dag: Dag, e: BuildExpr,
              env: var Table[string, NodeId]): NodeId =
  ## Dispatches to the correct `lower*` helper based on `e.kind`.
  ## A `bkVar` resolves directly through `env` without emitting a node.
  case e.kind
  of bkLit: dag.lowerLiteral(e)
  of bkVar: env[e.name]
  of bkCall: dag.lowerCall(e, env)
  of bkBranch: dag.lowerBranch(e, env)

proc lowerBody(dag: Dag, body: seq[BuildStmt],
               env: var Table[string, NodeId]): NodeId =
  ## Lowers a sequence of let-bindings, threading `env` so later
  ## bindings see earlier ones. Returns the id produced by the final
  ## statement — the tail value of the block.
  var lastId = NodeId(0)
  for stmt in body:
    let id = dag.lowerRhs(stmt.rhs, env)
    env[stmt.binding] = id
    lastId = id
  lastId

proc buildDag*[F: BuildInput](fn: F): Dag =
  ## Entry point for Step 1: lowers an analyzer function payload to a
  ## fully connected `Dag`.
  ##
  ## The `fn` parameter satisfies `BuildInput`. Parameters become root
  ## `nkParam` nodes, the body is lowered in order, and the tail value
  ## is wired into a terminating `nkReturn` node. Feeds Step 2's return
  ## identification and Step 3's escape analysis.
  result = newDag(fn.name)
  var env = initTable[string, NodeId]()
  result.bindParams(fn.params, env)
  let lastId = result.lowerBody(fn.body, env)
  let retNode = result.newReturnNode(lastId, "<return>")
  result.addEdge(lastId, retNode.id, ekData)
  result.setReturn(retNode.id)
