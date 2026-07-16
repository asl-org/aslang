## Step 3 — Compute the escape set. See plans/plan_dag_ir.md § Step 3.

import ./dag_ir_core, ./phase_02_returned_set, std/[tables, sets]

type
  EscapeInput* = concept d
    ## Minimal contract Step 3 requires: the return id, the node table,
    ## and reverse (`inEdges`) adjacency for backward traversal.
    ## Any DAG-shaped type exposing these satisfies the concept.
    d.returnId is NodeId
    d.nodes is Table[NodeId, Node]
    d.inEdges(NodeId) is seq[NodeId]

proc walkBackFrom(dag: EscapeInput, seed: NodeId,
                  visited: var HashSet[NodeId]) =
  ## Depth-first backward traversal from `seed`, accumulating every
  ## producer transitively reachable through `inEdges` into `visited`.
  if seed in visited: return
  visited.incl(seed)
  for producer in dag.inEdges(seed):
    dag.walkBackFrom(producer, visited)

proc collectSubDagInputs(dag: EscapeInput, br: Node,
                         acc: var HashSet[NodeId]) =
  ## Adds every arm root and arm-return of the branch `br` into `acc`.
  ## Used to identify sub-DAG entry points that may need re-walking when
  ## already-escaped values flow through them.
  for arm in br.arms:
    acc.incl(arm.bodyReturn)
    for r in arm.bodyRoots:
      acc.incl(r)

proc computeEscapeSet*[D: EscapeInput](dag: D): HashSet[NodeId] =
  ## Computes the set of nodes whose values escape the function.
  ##
  ## The `dag` parameter satisfies `EscapeInput`. Seeds a backward walk
  ## from every returned root (see `collectAllReturnRoots` in Step 2)
  ## and then extends the walk through any branch whose sub-DAG shares
  ## nodes with the already-escaped set. Feeds Step 4 DCE (nodes NOT in
  ## the set are candidates for removal) and Step 5 refcount (escaped
  ## nodes are classified `vcEscape`).
  var visited = initHashSet[NodeId]()
  let returnRoots = dag.collectAllReturnRoots()
  for r in returnRoots:
    dag.walkBackFrom(r, visited)
  for id, n in dag.nodes:
    if n.kind == nkBranch:
      var subInputs = initHashSet[NodeId]()
      dag.collectSubDagInputs(n, subInputs)
      for s in subInputs:
        if s in visited:
          dag.walkBackFrom(s, visited)
  visited
