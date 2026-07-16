## Step 6 — Codegen in topological order. See plans/plan_dag_ir.md § Step 6.

import ./dag_ir_core, ./phase_05_refcount,
       std/[tables, sets, sequtils, strutils]

type
  CodegenInput* = concept d
    ## Full DAG contract required by Step 6 codegen.
    ##
    ## Extends `RefcountInput` with predecessor edges, roots, and the return
    ## node — enough to topologically order the DAG and emit each node in a
    ## single forward pass.
    d.nodes is Table[NodeId, Node]
    d.outEdges(NodeId) is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]
    d.roots is seq[NodeId]
    d.returnId is NodeId

  ConsumerKind* = enum
    ## Classifies an external function as either a pure reader of its inputs
    ## or a producer that returns a fresh value derived from a named parameter.
    coReader, coProducer

  ConsumerSpec* = object
    ## Registry entry describing an external callee's consumption behavior.
    fn: string
    kind: ConsumerKind
    producesParam: string

  ConsumerRegistry* = Table[string, ConsumerSpec]
    ## Lookup from callee name to its `ConsumerSpec`, used to reason about
    ## last-use of arguments across extern boundaries.

  Allocation* = enum
    ## Storage strategy chosen for a node's output in the emitted C.
    ##
    ## `alBumpFresh` allocates from the bump arena; `alReuseInPlace` overwrites
    ## a linear predecessor's slot; `alCallerFrame` places the value in the
    ## caller-provided out-slot (for escaping returns); `alConstant` inlines a
    ## compile-time singleton; `alPassThrough` forwards without allocation.
    alBumpFresh, alReuseInPlace, alCallerFrame, alConstant, alPassThrough

  EmittedNode* = object
    ## Per-node codegen decision: order, allocation, and last-use inputs.
    id: NodeId
    order: int
    allocation: Allocation
    isLastUseOfInput: seq[NodeId]

  CodegenPlan* = object
    ## Whole-function emission plan: topological order plus per-node decisions.
    ## Handed to `emitFunction` to produce the C body.
    order: seq[NodeId]
    emissions: Table[NodeId, EmittedNode]

proc fn*(c: ConsumerSpec): string = c.fn
  ## Returns the callee name this spec describes.
proc kind*(c: ConsumerSpec): ConsumerKind = c.kind
  ## Returns whether this callee is a reader or a producer.
proc producesParam*(c: ConsumerSpec): string = c.producesParam
  ## Returns the name of the parameter whose value the callee returns (producer only).
proc id*(e: EmittedNode): NodeId = e.id
  ## Returns the DAG node this emission plan belongs to.
proc order*(e: EmittedNode): int = e.order
  ## Returns this node's position in the topological emission order.
proc allocation*(e: EmittedNode): Allocation = e.allocation
  ## Returns the allocation strategy chosen for this node's output.
proc isLastUseOfInput*(e: EmittedNode): seq[NodeId] = e.isLastUseOfInput
  ## Returns the input node IDs for which this emission is the final consumer.
proc order*(p: CodegenPlan): seq[NodeId] = p.order
  ## Returns the topological emission order of the whole plan.
proc emissions*(p: CodegenPlan): Table[NodeId, EmittedNode] = p.emissions
  ## Returns the per-node emission table.

proc visit(dag: CodegenInput, id: NodeId,
           seen: var HashSet[NodeId], out_ordered: var seq[NodeId]) =
  ## Post-order DFS helper for `topoSort`; appends `id` after all predecessors.
  if id in seen: return
  seen.incl(id)
  for pred in dag.inEdges(id):
    dag.visit(pred, seen, out_ordered)
  out_ordered.add(id)

proc topoSort(dag: CodegenInput): seq[NodeId] =
  ## Returns a topological ordering of `dag` nodes, visiting from roots, then
  ## the return node, then any nodes not yet reached.
  var seen = initHashSet[NodeId]()
  for r in dag.roots:
    dag.visit(r, seen, result)
  dag.visit(dag.returnId, seen, result)
  for id, _ in dag.nodes:
    dag.visit(id, seen, result)

proc lastConsumerOf(dag: CodegenInput, value: NodeId,
                    orderIndex: Table[NodeId, int]): NodeId =
  ## Returns the consumer of `value` that appears latest in the emission order.
  var lastIdx = -1
  var lastId = NodeId(0)
  for c in dag.outEdges(value):
    if c in orderIndex and orderIndex[c] > lastIdx:
      lastIdx = orderIndex[c]
      lastId = c
  lastId

proc classifyConsumer(callee: string, registry: ConsumerRegistry): ConsumerKind =
  ## Looks up `callee` in `registry`; defaults to `coReader` when unknown.
  if callee in registry: registry[callee].kind
  else: coReader

proc pickAllocation(info: RefInfo, isReturn: bool,
                    isConstDomain: bool): Allocation =
  ## Chooses an `Allocation` from Step 5's `RefInfo` and a couple of hints.
  ##
  ## Constants win first, then escaping values (caller frame), then linear
  ## values (reuse-in-place). Everything else falls back to `alBumpFresh`.
  if isConstDomain: alConstant
  elif info.class == vcEscape: alCallerFrame
  elif info.class == vcLinear: alReuseInPlace
  elif info.class == vcShared: alBumpFresh
  else: alBumpFresh

proc lastUseInputsForCall(dag: CodegenInput, n: Node,
                          orderIndex: Table[NodeId, int],
                          consumerId: NodeId): seq[NodeId] =
  ## Returns the argument IDs of call node `n` whose last consumer is `n` itself.
  for a in n.argIds:
    let last = dag.lastConsumerOf(a, orderIndex)
    if last == consumerId:
      result.add(a)

proc planEmission(dag: CodegenInput, id: NodeId, orderIdx: int,
                  refs: RefcountTable, orderIndex: Table[NodeId, int]): EmittedNode =
  ## Builds the per-node emission record: allocation + last-use inputs.
  let n = dag.nodes[id]
  let info = refs[id]
  let isReturn = id == dag.returnId
  var lastUses: seq[NodeId] = @[]
  if n.kind == nkCall or n.kind == nkExtern:
    lastUses = dag.lastUseInputsForCall(n, orderIndex, id)
  EmittedNode(id: id, order: orderIdx,
              allocation: pickAllocation(info, isReturn, false),
              isLastUseOfInput: lastUses)

proc planCodegen*[D: CodegenInput](dag: D, refs: RefcountTable): CodegenPlan =
  ## Produces a full `CodegenPlan` for `dag` using Step 5's `refs`.
  ##
  ## Topologically sorts `dag`, indexes each node by position, then decides an
  ## allocation and last-use set per node. The plan is the sole input to
  ## `emitFunction`. See § Step 6.
  let ordered = dag.topoSort()
  var orderIndex = initTable[NodeId, int]()
  for i, id in ordered:
    orderIndex[id] = i
  result = CodegenPlan(order: ordered, emissions: initTable[NodeId, EmittedNode]())
  for i, id in ordered:
    result.emissions[id] = dag.planEmission(id, i, refs, orderIndex)

proc emitBumpMarker*(plan: CodegenPlan): string =
  ## Emits the C snippet that captures the bump-arena watermark at function entry.
  "watermark = bump_ptr;\n"

proc emitRelease*(plan: CodegenPlan): string =
  ## Emits the C snippet that rewinds the bump arena back to the saved watermark.
  "bump_ptr = watermark;\n"

proc emitNode(dag: CodegenInput, id: NodeId, e: EmittedNode): string =
  ## Emits a single C line for node `id` based on its kind and allocation choice.
  let n = dag.nodes[id]
  case n.kind
  of nkLiteral:
    "$1 = $2;\n" % [$id, n.litValue]
  of nkParam:
    "/* param $1 */\n" % [n.paramName]
  of nkCall, nkExtern:
    let reuse = if e.allocation == alReuseInPlace: " /* reuse-in-place */" else: ""
    "$1 = $2(...);$3\n" % [$id, n.callee, reuse]
  of nkBranch:
    "/* branch on $1 */\n" % [$n.subject]
  of nkReturn:
    "return $1;\n" % [$n.retValue]
  of nkPhi:
    "/* phi */\n"
  of nkRecursion:
    "goto __loop_$1;\n" % [n.recCallee]

proc emitFunction*[D: CodegenInput](dag: D, plan: CodegenPlan): string =
  ## Emits the full C body for a function: watermark, ordered nodes, release.
  ##
  ## Walks `plan.order`, calling `emitNode` for each entry, and brackets the
  ## body with bump-arena save/restore. This is the final artifact Step 6
  ## hands downstream to Step 17's CPU codegen.
  result = plan.emitBumpMarker()
  for id in plan.order:
    result.add(dag.emitNode(id, plan.emissions[id]))
  result.add(plan.emitRelease())
