## Step 2 — Identify the return node. See plans/plan_dag_ir.md § Step 2.

import ./dag_ir_core, std/[tables, sets]

type
  ReturnedSetInput* = concept d
    ## Minimal contract Step 2 requires from a DAG: the terminating
    ## `returnId` and access to the node table. A satisfying type is
    ## passed as `dag` to `identifyReturn` and `collectAllReturnRoots`.
    d.returnId is NodeId
    d.nodes is Table[NodeId, Node]

  ReturnedInfo* = object
    ## Result of `identifyReturn`. `root` is the id of the value that
    ## flows into the return; `isTailBranch` is true when that value is
    ## itself a branch, meaning each arm produces a distinct return.
    root: NodeId
    isTailBranch: bool

proc root*(r: ReturnedInfo): NodeId = r.root
  ## Returns the id of the value feeding the function return.
proc isTailBranch*(r: ReturnedInfo): bool = r.isTailBranch
  ## Returns true when the return value is produced by a branch node.

proc collectBranchReturns(node: Node, acc: var HashSet[NodeId]) =
  ## Adds each arm's `bodyReturn` id to `acc` when `node` is a branch.
  ## No-op for other node kinds.
  case node.kind
  of nkBranch:
    for arm in node.arms:
      acc.incl(arm.bodyReturn)
  else:
    discard

proc identifyReturn*[D: ReturnedSetInput](dag: D): ReturnedInfo =
  ## Locates the value node feeding `dag.returnId` and reports whether
  ## it is a tail branch.
  ##
  ## The `dag` parameter satisfies `ReturnedSetInput`. Feeds Step 3's
  ## escape analysis, which seeds its backward walk from every returned
  ## root.
  let retId = dag.returnId
  let retNode = dag.nodes[retId]
  let feederId =
    if retNode.kind == nkReturn: retNode.retValue
    else: retId
  let feeder = dag.nodes[feederId]
  result = ReturnedInfo(root: feederId,
                        isTailBranch: feeder.kind == nkBranch)

proc collectAllReturnRoots*[D: ReturnedSetInput](dag: D): HashSet[NodeId] =
  ## Includes every arm's tail node when the outer return is a branch —
  ## each arm produces a distinct returnable value that must be tracked.
  ##
  ## The `dag` parameter satisfies `ReturnedSetInput`. The returned set
  ## is the seed for Step 3's `computeEscapeSet` backward walk.
  var roots = initHashSet[NodeId]()
  let info = dag.identifyReturn()
  roots.incl(info.root)
  if info.isTailBranch:
    let br = dag.nodes[info.root]
    br.collectBranchReturns(roots)
  roots
