## Step 4 — Dead-code elimination. See plans/plan_dag_ir.md § Step 4.

import ./dag_ir_core, std/[tables, sets, sequtils]

type
  DceInput* = concept d
    ## Minimal contract Step 4 requires: the node table, forward
    ## (`outEdges`) adjacency for consumer counts, and in-place
    ## `removeNode` mutation. Any DAG-shaped type exposing these
    ## satisfies the concept.
    d.nodes is Table[NodeId, Node]
    d.outEdges(NodeId) is seq[NodeId]
    d.removeNode(NodeId)

  DceStats* = object
    ## Summary of a DCE run: total nodes removed and number of fixpoint
    ## passes executed before convergence.
    removedCount: int
    passes: int

proc removedCount*(s: DceStats): int = s.removedCount
  ## Returns the total number of nodes removed across all passes.
proc passes*(s: DceStats): int = s.passes
  ## Returns the number of fixpoint passes executed before convergence.

proc isSideEffecting(n: Node): bool =
  ## Returns true for nodes DCE must preserve regardless of consumers —
  ## effectful calls, externs, and the terminating return.
  case n.kind
  of nkCall, nkExtern: n.isEffect
  of nkReturn: true
  else: false

proc pickDeadNodes(dag: DceInput, escapes: HashSet[NodeId]): seq[NodeId] =
  ## Collects ids of one pass's dead nodes: not in `escapes`, not
  ## side-effecting, and with zero consumers.
  for id, n in dag.nodes:
    if id in escapes: continue
    if n.isSideEffecting: continue
    if dag.outEdges(id).len == 0:
      result.add(id)

proc dceOnce(dag: DceInput, escapes: HashSet[NodeId]): int =
  ## Runs a single DCE pass over `dag`, removing every currently-dead
  ## node. Returns the count removed so the driver can detect fixpoint.
  let dead = dag.pickDeadNodes(escapes)
  for id in dead:
    dag.removeNode(id)
  dead.len

proc eliminateDeadCode*[D: DceInput](dag: D,
                                     escapes: HashSet[NodeId]): DceStats =
  ## Iteratively removes dead nodes from `dag` until fixpoint.
  ##
  ## The `dag` parameter satisfies `DceInput`; `escapes` comes from
  ## Step 3 and pins nodes that must survive because their values leave
  ## the function. Each pass removes nodes whose consumers were pruned
  ## in the previous pass, so multiple passes may be needed for
  ## transitively dead chains. Feeds Step 5 refcount with a slimmer DAG.
  var stats = DceStats(removedCount: 0, passes: 0)
  while true:
    let removed = dag.dceOnce(escapes)
    if removed == 0: break
    stats.removedCount += removed
    stats.passes += 1
  stats
