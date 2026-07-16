## Step 13 — Worst-case execution time analysis. See plans/plan_dag_ir.md § Step 13.

import ./dag_ir_core, ./phase_07_value_domains, ./phase_12_parallelism,
       std/[tables, sets, sequtils, strutils]

type
  WcetKind* = enum
    ## Discriminator for `Wcet`: either a known cycle count or an unbounded/opaque cost.
    wkKnown, wkUnknown

  Wcet* = object
    ## Worst-case execution time for one node or aggregate.
    ## `wkKnown` carries a concrete `cycles` bound; `wkUnknown` carries a
    ## human-readable `reason` explaining why the bound could not be derived.
    case kind: WcetKind
    of wkKnown:
      cycles: int64
    of wkUnknown:
      reason: string

  CostSpecKind* = enum
    ## Discriminator for `CostSpec`: constant, formula-driven, or unannotated.
    csFixed, csParametric, csUnknown

  CostSpec* = object
    ## Cost annotation for one callee, keyed by name in `CostRegistry`.
    ## `csFixed` is a compile-time constant; `csParametric` carries a symbolic
    ## `formula` over named `params`; `csUnknown` records why no bound is known.
    fnName: string
    case kind: CostSpecKind
    of csFixed:
      fixedCycles: int64
    of csParametric:
      formula: string
      params: seq[string]
    of csUnknown:
      note: string

  CostRegistry* = Table[string, CostSpec]
    ## Lookup from callee name to its cost annotation.

  DepthMap* = Table[string, int]
    ## Maximum recursion depth per recursive function, sourced from `@depth` pragmas.

  WcetInput* = concept d
    ## Abstract DAG contract this phase reads: node table, roots, terminating
    ## return node, and reverse-edge access. Satisfied by the Step 1 DAG.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.returnId is NodeId
    d.inEdges(NodeId) is seq[NodeId]

  WcetTable* = Table[NodeId, Wcet]
    ## Per-node WCET bound produced by this phase; consumed by Step 20 kernel
    ## extraction and downstream scheduling (Step 16).

proc kind*(w: Wcet): WcetKind = w.kind
  ## Returns the discriminator of `w`.
proc cycles*(w: Wcet): int64 = w.cycles
  ## Returns the known cycle bound; only valid when `w.kind == wkKnown`.
proc reason*(w: Wcet): string = w.reason
  ## Returns the explanation string; only valid when `w.kind == wkUnknown`.
proc fnName*(s: CostSpec): string = s.fnName
  ## Returns the annotated callee name.
proc kind*(s: CostSpec): CostSpecKind = s.kind
  ## Returns the discriminator of `s`.
proc fixedCycles*(s: CostSpec): int64 = s.fixedCycles
  ## Returns the constant cycle count; only valid when `s.kind == csFixed`.
proc formula*(s: CostSpec): string = s.formula
  ## Returns the parametric cost formula; only valid when `s.kind == csParametric`.

proc known(c: int64): Wcet = Wcet(kind: wkKnown, cycles: c)
  ## Constructs a known WCET with `c` cycles.
proc unknown(r: string): Wcet = Wcet(kind: wkUnknown, reason: r)
  ## Constructs an unknown WCET carrying reason `r`.

proc combineSum(a, b: Wcet): Wcet =
  ## Sums two sequential WCETs; unknown propagates.
  if a.kind == wkUnknown: a
  elif b.kind == wkUnknown: b
  else: known(a.cycles + b.cycles)

proc combineMax(a, b: Wcet): Wcet =
  ## Takes the maximum of two alternative-branch WCETs; unknown propagates.
  if a.kind == wkUnknown: a
  elif b.kind == wkUnknown: b
  else: known(max(a.cycles, b.cycles))

proc evalParametric(spec: CostSpec, inputDoms: seq[Domain]): Wcet =
  ## Evaluates a `csParametric` `spec` against caller-side input domains.
  ## Placeholder — refine once Step 7 exposes symbolic domain substitution;
  ## for now, uses the worst-case `hi` bound of the first integer parameter.
  # TODO: refine once Step 7 exposes symbolic domain substitution;
  # for now, use the worst-case hi bound of the first parameter.
  if inputDoms.len == 0: return unknown("no parameter domains")
  let d = inputDoms[0]
  if d.kind == dkIntRange: known(d.hi * 4)
  else: unknown("non-integer parametric input")

proc callCost(n: Node, inputDoms: seq[Domain], reg: CostRegistry): Wcet =
  ## Looks up the cost of a call/extern node in `reg` and evaluates it.
  if n.callee notin reg: return unknown("no cost annotation for " & n.callee)
  let spec = reg[n.callee]
  case spec.kind
  of csFixed: known(spec.fixedCycles)
  of csParametric: evalParametric(spec, inputDoms)
  of csUnknown: unknown(spec.note)

proc gatherInputDoms(dag: WcetInput, n: Node,
                     doms: DomainTable): seq[Domain] =
  ## Collects the value-domain (from Step 7) of each argument feeding `n`.
  for a in n.argIds:
    if a in doms: result.add(doms[a])

proc nodeWcet(dag: WcetInput, id: NodeId,
              reg: CostRegistry, doms: DomainTable): Wcet =
  ## Computes the intrinsic per-node WCET before combining with successors.
  ## Data-flow nodes are zero-cost; calls/externs use `callCost`; branch is 1.
  let n = dag.nodes[id]
  case n.kind
  of nkLiteral, nkParam, nkPhi: known(0)
  of nkReturn: known(0)
  of nkCall, nkExtern:
    callCost(n, dag.gatherInputDoms(n, doms), reg)
  of nkBranch: known(1)
  of nkRecursion: known(0)

proc topoWalk(dag: WcetInput, id: NodeId,
              seen: var HashSet[NodeId], ordered: var seq[NodeId]) =
  ## Post-order DFS helper. Appends `id` to `ordered` after visiting all
  ## predecessors, producing a reverse-topological sequence.
  if id in seen: return
  seen.incl(id)
  for p in dag.inEdges(id):
    dag.topoWalk(p, seen, ordered)
  ordered.add(id)

proc ordered(dag: WcetInput): seq[NodeId] =
  ## Returns nodes in evaluation order (predecessors before successors) so
  ## `perFunctionWcet` can dynamic-program bottom up.
  var seen = initHashSet[NodeId]()
  for r in dag.roots: dag.topoWalk(r, seen, result)
  dag.topoWalk(dag.returnId, seen, result)
  for id, _ in dag.nodes: dag.topoWalk(id, seen, result)

proc combineBranchArms(dag: WcetInput, n: Node,
                       wcets: WcetTable): Wcet =
  ## Combines all arm WCETs of a branch node via max (worst-arm bound).
  var acc = known(0)
  for arm in n.arms:
    let armW = wcets.getOrDefault(arm.bodyReturn, known(0))
    acc = combineMax(acc, armW)
  acc

proc applyParallelDiscount(base: Wcet, groups: seq[ParallelGroup],
                           id: NodeId): Wcet =
  ## Reduces `base` when `id` belongs to a Step 12 parallel group whose members
  ## overlap in wall-clock time. Placeholder — refine once Step 12 emits a
  ## per-node membership index; currently a no-op.
  # TODO: refine once Step 12 emits per-node membership index.
  discard groups
  discard id
  base

proc perFunctionWcet*[D: WcetInput](dag: D, reg: CostRegistry,
                                    doms: DomainTable,
                                    par: ParallelReport,
                                    depth: DepthMap): tuple[per: WcetTable, total: Wcet] =
  ## Main entry point of Step 13. Walks `dag` in evaluation order, computing a
  ## per-node WCET table and a function-total bound.
  ##
  ## The `dag` parameter satisfies `WcetInput`. Cost annotations come from
  ## `reg`, value-range information from `doms` (Step 7), parallel groupings
  ## from `par` (Step 12), and recursion caps from `depth`. The returned table
  ## feeds Step 20 kernel extraction and Step 16 scheduling.
  var wcets = initTable[NodeId, Wcet]()
  for id in dag.ordered():
    let n = dag.nodes[id]
    var w = dag.nodeWcet(id, reg, doms)
    if n.kind == nkBranch:
      w = combineSum(w, dag.combineBranchArms(n, wcets))
    if n.kind == nkRecursion:
      let d = depth.getOrDefault(n.recCallee, 0)
      if d > 0: w = known(w.cycles * d.int64)
      else: w = unknown("no @depth for " & n.recCallee)
    wcets[id] = w.applyParallelDiscount(par.groups, id)
  var total = known(0)
  for _, w in wcets:
    total = combineSum(total, w)
  (wcets, total)
