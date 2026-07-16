## Step 7 — Value domain tracking. See plans/plan_dag_ir.md § Step 7.

import ./dag_ir_core, std/[tables, sets, sequtils]

type
  DomainKind* = enum
    ## Tag for the `Domain` tagged union — the shape of an abstract value.
    ##
    ## Ranges lattice from `dkEmpty` (unreachable) upward through concrete
    ## refinements (`dkSingleton`, `dkIntRange`, `dkFloatRange`, `dkBoolSet`,
    ## `dkEnumSet`) to `dkFull` (top / no information).
    dkEmpty, dkSingleton, dkIntRange, dkFloatRange, dkBoolSet, dkEnumSet, dkFull

  Domain* = object
    ## Abstract value inhabiting a lattice element identified by `kind`.
    ##
    ## Per-variant payload: `dkSingleton` carries a literal string; `dkIntRange`
    ## a closed `[lo, hi]` interval; `dkFloatRange` a closed float interval;
    ## `dkBoolSet` a pair of `trueOk`/`falseOk` flags; `dkEnumSet` a set of
    ## variant names. `dkEmpty` and `dkFull` are payload-free.
    case kind: DomainKind
    of dkEmpty, dkFull:
      discard
    of dkSingleton:
      literal: string
    of dkIntRange:
      lo, hi: int64
    of dkFloatRange:
      floLo, floHi: float64
    of dkBoolSet:
      trueOk, falseOk: bool
    of dkEnumSet:
      variants: HashSet[string]

  TransferFn* = proc(inputs: seq[Domain]): Domain {.nimcall.}
    ## Abstract-interpretation transfer function for one callee: maps input
    ## argument domains to the output domain.

  TransferRegistry* = Table[string, TransferFn]
    ## Lookup from callee name to its `TransferFn`. Unknown callees are
    ## conservatively treated as returning `dkFull`.

  DomainInput* = concept d
    ## DAG contract required by the domain phase — nodes plus edge structure.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]
    d.outEdges(NodeId) is seq[NodeId]

  DomainTable* = Table[NodeId, Domain]
    ## Result of the domain phase: one `Domain` per node. Consumed by Step 8
    ## for termination reasoning and by Step 14 for bitwidth selection.

proc kind*(d: Domain): DomainKind = d.kind
  ## Returns the lattice-element tag of this domain.
proc literal*(d: Domain): string = d.literal
  ## Returns the singleton literal (valid only when `kind == dkSingleton`).
proc lo*(d: Domain): int64 = d.lo
  ## Returns the inclusive lower bound (valid only when `kind == dkIntRange`).
proc hi*(d: Domain): int64 = d.hi
  ## Returns the inclusive upper bound (valid only when `kind == dkIntRange`).

proc fullFor(ty: string): Domain =
  ## Returns the widest domain that any value of type `ty` can inhabit.
  ##
  ## Fixed-width integer types map to their full `dkIntRange`; `i64`/`u64`
  ## fall back to `dkFull` since they exceed the interval representation.
  ## Unknown types conservatively return `dkFull`.
  case ty
  of "u8": Domain(kind: dkIntRange, lo: 0, hi: 255)
  of "u16": Domain(kind: dkIntRange, lo: 0, hi: 65535)
  of "u32": Domain(kind: dkIntRange, lo: 0, hi: 4294967295'i64)
  of "u64": Domain(kind: dkFull)
  of "i8": Domain(kind: dkIntRange, lo: -128, hi: 127)
  of "i16": Domain(kind: dkIntRange, lo: -32768, hi: 32767)
  of "i32": Domain(kind: dkIntRange, lo: -2147483648'i64, hi: 2147483647'i64)
  of "i64": Domain(kind: dkFull)
  of "f32", "f64": Domain(kind: dkFloatRange, floLo: -Inf, floHi: Inf)
  of "bool": Domain(kind: dkBoolSet, trueOk: true, falseOk: true)
  else: Domain(kind: dkFull)

proc singleton(literal: string): Domain =
  ## Constructs a `dkSingleton` domain holding exactly `literal`.
  Domain(kind: dkSingleton, literal: literal)

proc isSingleton*(d: Domain): bool = d.kind == dkSingleton
  ## Returns true when `d` is a `dkSingleton` — i.e. a constant-foldable value.

proc seedInitialDomains(dag: DomainInput, doms: var DomainTable) =
  ## Populates `doms` with a starting domain per node before iteration.
  ##
  ## Literals seed to their singleton; params seed to `fullFor(paramType)`;
  ## everything else seeds to `dkFull` and is later refined by transfer.
  for id, n in dag.nodes:
    case n.kind
    of nkLiteral: doms[id] = singleton(n.litValue)
    of nkParam: doms[id] = fullFor(n.paramType)
    else: doms[id] = fullFor("")

proc topoWalk(dag: DomainInput, id: NodeId,
              seen: var HashSet[NodeId], ordered: var seq[NodeId]) =
  ## Post-order DFS helper for `orderedNodes`; appends `id` after predecessors.
  if id in seen: return
  seen.incl(id)
  for p in dag.inEdges(id):
    dag.topoWalk(p, seen, ordered)
  ordered.add(id)

proc orderedNodes(dag: DomainInput): seq[NodeId] =
  ## Returns nodes in topological order so transfer sees predecessors first.
  var seen = initHashSet[NodeId]()
  for r in dag.roots: dag.topoWalk(r, seen, result)
  for id, _ in dag.nodes: dag.topoWalk(id, seen, result)

proc transferCall(dag: DomainInput, n: Node,
                  doms: DomainTable, reg: TransferRegistry): Domain =
  ## Applies the registered `TransferFn` for callee `n.callee`, or returns
  ## `dkFull` when no transfer is registered.
  if n.callee notin reg:
    return fullFor("")
  var inputs: seq[Domain] = @[]
  for a in n.argIds:
    inputs.add(doms[a])
  reg[n.callee](inputs)

proc constrainSubject(subj: Domain, pattern: string): Domain =
  ## Narrows `subj` by a branch-arm pattern; `_` is identity, exact-literal
  ## match preserves the singleton, anything else widens to `dkFull`.
  if pattern == "_": subj
  elif subj.kind == dkSingleton and subj.literal == pattern: subj
  else: Domain(kind: dkFull)

proc unionDomains(a, b: Domain): Domain =
  ## Lattice join of two domains — currently only exact for int-range pairs.
  if a.kind == dkEmpty: b
  elif b.kind == dkEmpty: a
  elif a.kind == dkIntRange and b.kind == dkIntRange:
    Domain(kind: dkIntRange, lo: min(a.lo, b.lo), hi: max(a.hi, b.hi))
  else: Domain(kind: dkFull)

proc transferBranch(dag: DomainInput, n: Node,
                    doms: DomainTable, reg: TransferRegistry): Domain =
  ## Computes a branch node's domain by unioning the reachable arm returns.
  ##
  ## Arms whose pattern makes the subject `dkEmpty` are skipped as unreachable.
  var acc = Domain(kind: dkEmpty)
  let subj = doms[n.subject]
  for arm in n.arms:
    let constrained = constrainSubject(subj, arm.subjectPattern)
    if constrained.kind == dkEmpty: continue
    acc = unionDomains(acc, doms[arm.bodyReturn])
  acc

proc computeDomains*[D: DomainInput](dag: D,
                                     reg: TransferRegistry): DomainTable =
  ## Computes an abstract domain for every node in `dag`.
  ##
  ## Seeds literals and params, then walks the DAG in topological order and
  ## applies the appropriate transfer per node kind. `reg` supplies transfer
  ## functions for known callees. The resulting table drives constant folding,
  ## dead-arm pruning, and Step 8's termination proofs. See § Step 7.
  result = initTable[NodeId, Domain]()
  dag.seedInitialDomains(result)
  for id in dag.orderedNodes():
    let n = dag.nodes[id]
    case n.kind
    of nkCall, nkExtern: result[id] = dag.transferCall(n, result, reg)
    of nkBranch: result[id] = dag.transferBranch(n, result, reg)
    of nkReturn: result[id] = result[n.retValue]
    else: discard

proc constantFoldableNodes*(doms: DomainTable): seq[NodeId] =
  ## Returns node IDs whose domain narrowed to a singleton — candidates for
  ## constant folding by Step 6 codegen.
  for id, d in doms:
    if d.isSingleton: result.add(id)

proc unreachableArms*[D: DomainInput](dag: D,
                                     doms: DomainTable): seq[tuple[branch: NodeId, arm: int]] =
  ## Returns `(branch, armIndex)` pairs whose subject-narrowing yields `dkEmpty`
  ## — arms that Step 4 DCE can safely delete.
  for id, n in dag.nodes:
    if n.kind != nkBranch: continue
    let subj = doms[n.subject]
    for i, arm in n.arms:
      let constrained = constrainSubject(subj, arm.subjectPattern)
      if constrained.kind == dkEmpty:
        result.add((id, i))

proc overflowSuspects*[D: DomainInput](dag: D,
                                      doms: DomainTable): seq[NodeId] =
  ## Returns call nodes whose result range provably exceeds `u32` — a coarse
  ## overflow gate for downstream diagnostics.
  ##
  ## Placeholder — refine once Step 14's per-type width table lands.
  # TODO: refine when Step 14's per-type width table lands.
  for id, n in dag.nodes:
    if n.kind notin {nkCall, nkExtern}: continue
    let d = doms[id]
    if d.kind == dkIntRange and d.hi > 4294967295'i64:
      result.add(id)
