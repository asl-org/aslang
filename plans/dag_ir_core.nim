## Shared DAG vocabulary. See plans/plan_dag_ir.md § Input / Output.

import std/[tables, sets, hashes]

type
  NodeId* = distinct uint32
    ## Stable identifier for a DAG node. Allocated monotonically by `Dag.freshId`.

  NodeKind* = enum
    ## Discriminator for `Node`. Covers every kind of value or control
    ## construct produced during Step 1 lowering: literals, function
    ## parameters, pure/effectful calls, external calls, pattern-match
    ## branches, phi merges, the function return, and self-recursion.
    nkLiteral, nkParam, nkCall, nkExtern, nkBranch, nkPhi, nkReturn,
    nkRecursion

  EdgeKind* = enum
    ## Edge classification. `ekData` carries a value between nodes,
    ## `ekControl` sequences non-data dependencies (e.g. branch subject),
    ## `ekLoopBack` marks a back-edge used by later loop analyses.
    ekData, ekControl, ekLoopBack

  Edge* = object
    ## Directed producer-to-consumer edge with a positional `slot` used to
    ## reconstruct argument order at consumers such as call nodes.
    src: NodeId
    dst: NodeId
    kind: EdgeKind
    slot: uint16

  BranchArm* = object
    ## One arm of a pattern-match. Owns its own sub-DAG rooted at
    ## `bodyRoots` and terminates at `bodyReturn`, the value the arm
    ## contributes back to the enclosing branch node.
    subjectPattern: string
    bodyRoots: seq[NodeId]
    bodyReturn: NodeId

  Node* = ref object
    ## Tagged-union node in the DAG. `kind` selects which payload fields
    ## are live; shared fields (`id`, `loc`, `label`) apply to all
    ## variants. Reference semantics keep edge lookups cheap.
    id: NodeId
    loc: string
    label: string
    case kind: NodeKind
    of nkLiteral:
      litValue: string
      litType: string
    of nkParam:
      paramName: string
      paramType: string
    of nkCall, nkExtern:
      callee: string
      isEffect: bool
      isPure: bool
      argIds: seq[NodeId]
    of nkBranch:
      subject: NodeId
      arms: seq[BranchArm]
    of nkPhi:
      phiInputs: seq[NodeId]
    of nkReturn:
      retValue: NodeId
    of nkRecursion:
      recCallee: string
      recArgs: seq[NodeId]

  Dag* = ref object
    ## Whole-function DAG. Holds nodes keyed by id, the edge list, and
    ## dual adjacency indexes (`outAdj`, `inAdj`) so both producer and
    ## consumer traversal are O(1). `roots` tracks parameter nodes;
    ## `returnId` is set once Step 1 emits the terminating return.
    nodes: Table[NodeId, Node]
    edges: seq[Edge]
    outAdj: Table[NodeId, seq[NodeId]]
    inAdj: Table[NodeId, seq[NodeId]]
    roots: seq[NodeId]
    returnId: NodeId
    nextId: uint32
    funcName: string

  DagNodeLike* = concept n
    ## Minimal contract for a DAG node value: exposes a `NodeId` identity
    ## and a `NodeKind` discriminator. Lets downstream phases accept any
    ## node-shaped type without depending on the concrete `Node` layout.
    n.id is NodeId
    n.kind is NodeKind

  DagLike* = concept d
    ## Minimal contract for a DAG container consumed by later phases.
    ## A satisfying type exposes the node table, the parameter roots,
    ## the return node id, and both edge lookups.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.returnId is NodeId
    d.outEdges(NodeId) is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]

proc `==`*(a, b: NodeId): bool {.borrow.}
  ## Structural equality on `NodeId`, borrowed from the underlying `uint32`.
proc hash*(id: NodeId): Hash {.borrow.}
  ## Hashes a `NodeId` for use in `Table` / `HashSet` keys.
proc `$`*(id: NodeId): string {.borrow.}
  ## Renders a `NodeId` as its decimal string form for debug output.

proc id*(n: Node): NodeId = n.id
  ## Returns the stable identifier of this node.
proc loc*(n: Node): string = n.loc
  ## Returns the source-location tag attached to this node.
proc label*(n: Node): string = n.label
  ## Returns the human-readable debug label of this node.
proc kind*(n: Node): NodeKind = n.kind
  ## Returns the tagged-union discriminator for this node.

proc litValue*(n: Node): string = n.litValue
  ## Literal payload — textual value. Valid only for `nkLiteral`.
proc litType*(n: Node): string = n.litType
  ## Literal payload — type name. Valid only for `nkLiteral`.
proc paramName*(n: Node): string = n.paramName
  ## Parameter payload — declared parameter name. Valid only for `nkParam`.
proc paramType*(n: Node): string = n.paramType
  ## Parameter payload — declared parameter type. Valid only for `nkParam`.
proc callee*(n: Node): string = n.callee
  ## Call payload — target function name. Valid for `nkCall` and `nkExtern`.
proc isEffect*(n: Node): bool = n.isEffect
  ## Call payload — whether the call has observable side effects.
proc isPure*(n: Node): bool = n.isPure
  ## Call payload — whether the call is pure (complement of `isEffect`).
proc argIds*(n: Node): seq[NodeId] = n.argIds
  ## Call payload — positional argument node ids.
proc subject*(n: Node): NodeId = n.subject
  ## Branch payload — id of the value being matched. Valid only for `nkBranch`.
proc arms*(n: Node): seq[BranchArm] = n.arms
  ## Branch payload — pattern arms in declaration order.
proc phiInputs*(n: Node): seq[NodeId] = n.phiInputs
  ## Phi payload — merged input ids. Valid only for `nkPhi`.
proc retValue*(n: Node): NodeId = n.retValue
  ## Return payload — id of the value being returned. Valid only for `nkReturn`.
proc recCallee*(n: Node): string = n.recCallee
  ## Recursion payload — self-call target name. Valid only for `nkRecursion`.
proc recArgs*(n: Node): seq[NodeId] = n.recArgs
  ## Recursion payload — self-call argument ids.

proc src*(e: Edge): NodeId = e.src
  ## Returns the producer end of the edge.
proc dst*(e: Edge): NodeId = e.dst
  ## Returns the consumer end of the edge.
proc kind*(e: Edge): EdgeKind = e.kind
  ## Returns the edge classification (data / control / loop-back).
proc slot*(e: Edge): uint16 = e.slot
  ## Returns the positional slot (e.g. argument index) at the consumer.

proc subjectPattern*(a: BranchArm): string = a.subjectPattern
  ## Returns the arm's pattern text as it appeared in source.
proc bodyRoots*(a: BranchArm): seq[NodeId] = a.bodyRoots
  ## Returns the roots of the sub-DAG built for this arm's body.
proc bodyReturn*(a: BranchArm): NodeId = a.bodyReturn
  ## Returns the tail node whose value the arm contributes to the branch.

proc nodes*(d: Dag): Table[NodeId, Node] = d.nodes
  ## Returns the id-keyed node table of the DAG.
proc edges*(d: Dag): seq[Edge] = d.edges
  ## Returns the full edge list of the DAG in insertion order.
proc roots*(d: Dag): seq[NodeId] = d.roots
  ## Returns the parameter-root ids seeded by `newParamNode`.
proc returnId*(d: Dag): NodeId = d.returnId
  ## Returns the id of the terminating `nkReturn` node.
proc funcName*(d: Dag): string = d.funcName
  ## Returns the name of the function this DAG represents.

proc outEdges*(d: Dag, id: NodeId): seq[NodeId] =
  ## Returns downstream (consumer) node ids reachable in one hop from `id`.
  if id in d.outAdj: d.outAdj[id] else: @[]

proc inEdges*(d: Dag, id: NodeId): seq[NodeId] =
  ## Returns upstream (producer) node ids that feed `id` directly.
  if id in d.inAdj: d.inAdj[id] else: @[]

proc outDegree*(d: Dag, id: NodeId): int = d.outEdges(id).len
  ## Returns the number of consumers of `id`.
proc inDegree*(d: Dag, id: NodeId): int = d.inEdges(id).len
  ## Returns the number of producers of `id`.

proc newDag*(funcName: string): Dag =
  ## Creates an empty DAG for `funcName` with id allocation seeded at 1.
  ## Id 0 is reserved as a sentinel for "unset return".
  Dag(
    nodes: initTable[NodeId, Node](),
    edges: @[],
    outAdj: initTable[NodeId, seq[NodeId]](),
    inAdj: initTable[NodeId, seq[NodeId]](),
    roots: @[],
    returnId: NodeId(0),
    nextId: 1,
    funcName: funcName,
  )

proc freshId(d: Dag): NodeId =
  ## Allocates and returns the next monotonic `NodeId` for `d`.
  result = NodeId(d.nextId)
  d.nextId += 1

proc registerNode(d: Dag, n: Node) =
  ## Inserts `n` into the node table and primes empty adjacency buckets.
  d.nodes[n.id] = n
  d.outAdj[n.id] = @[]
  d.inAdj[n.id] = @[]

proc newLiteralNode*(d: Dag, value: string, ty: string, loc: string): Node =
  ## Creates an `nkLiteral` node and registers it in the DAG.
  ## Not automatically added to roots or wired with edges.
  result = Node(kind: nkLiteral, id: d.freshId(), loc: loc,
                label: "lit_" & value, litValue: value, litType: ty)
  d.registerNode(result)

proc newParamNode*(d: Dag, name: string, ty: string, loc: string): Node =
  ## Creates an `nkParam` node, registers it, and appends it to `roots`.
  ## Parameter nodes are the entry seeds for backward escape analysis.
  result = Node(kind: nkParam, id: d.freshId(), loc: loc,
                label: "param_" & name, paramName: name, paramType: ty)
  d.registerNode(result)
  d.roots.add(result.id)

proc newCallNode*(d: Dag, callee: string, args: seq[NodeId],
                  isEffect: bool, loc: string): Node =
  ## Creates an `nkCall` node and registers it. `isPure` is set to the
  ## complement of `isEffect`. Caller must add per-arg data edges.
  result = Node(kind: nkCall, id: d.freshId(), loc: loc,
                label: "call_" & callee, callee: callee, argIds: args,
                isEffect: isEffect, isPure: not isEffect)
  d.registerNode(result)

proc newExternNode*(d: Dag, callee: string, args: seq[NodeId],
                    isEffect: bool, loc: string): Node =
  ## Creates an `nkExtern` node for a call into an external / foreign
  ## function. Registered but not automatically edge-wired.
  result = Node(kind: nkExtern, id: d.freshId(), loc: loc,
                label: "extern_" & callee, callee: callee, argIds: args,
                isEffect: isEffect, isPure: not isEffect)
  d.registerNode(result)

proc newBranchNode*(d: Dag, subject: NodeId, arms: seq[BranchArm],
                    loc: string): Node =
  ## Creates an `nkBranch` node from the given `subject` and `arms`.
  ## Registered only — Step 1 adds the control edge from `subject` and
  ## data edges from each arm's `bodyReturn`.
  result = Node(kind: nkBranch, id: d.freshId(), loc: loc,
                label: "branch", subject: subject, arms: arms)
  d.registerNode(result)

proc newReturnNode*(d: Dag, value: NodeId, loc: string): Node =
  ## Creates the terminating `nkReturn` node, registers it, and records
  ## its id as `d.returnId`. Feeds Step 2's return identification.
  result = Node(kind: nkReturn, id: d.freshId(), loc: loc,
                label: "return", retValue: value)
  d.registerNode(result)
  d.returnId = result.id

proc newRecursionNode*(d: Dag, callee: string, args: seq[NodeId],
                       loc: string): Node =
  ## Creates an `nkRecursion` node representing a self-call site.
  ## Consumed by Step 8 tail-call analysis.
  result = Node(kind: nkRecursion, id: d.freshId(), loc: loc,
                label: "recur_" & callee, recCallee: callee, recArgs: args)
  d.registerNode(result)

proc addEdge*(d: Dag, src, dst: NodeId, kind: EdgeKind = ekData,
              slot: uint16 = 0) =
  ## Records an edge from `src` to `dst` and updates both adjacency
  ## indexes. Default kind is `ekData` with slot 0.
  d.edges.add(Edge(src: src, dst: dst, kind: kind, slot: slot))
  d.outAdj.mgetOrPut(src, @[]).add(dst)
  d.inAdj.mgetOrPut(dst, @[]).add(src)

proc setReturn*(d: Dag, id: NodeId) = d.returnId = id
  ## Overrides the DAG's return node id. Used when the return is wired
  ## after node construction.

proc removeNode*(d: Dag, id: NodeId) =
  ## Removes `id` and every edge that touches it from the DAG.
  ## Used by Step 4 DCE to prune dead nodes. Adjacency indexes are
  ## rebuilt in place so subsequent traversals stay consistent.
  d.nodes.del(id)
  d.outAdj.del(id)
  d.inAdj.del(id)
  d.edges.keepItIf(it.src != id and it.dst != id)
  for k, v in d.outAdj.mpairs:
    v.keepItIf(it != id)
  for k, v in d.inAdj.mpairs:
    v.keepItIf(it != id)
