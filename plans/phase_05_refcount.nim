## Step 5 — Compute reference counts. See plans/plan_dag_ir.md § Step 5.

import ./dag_ir_core, std/[tables, sets]

type
  RefcountInput* = concept d
    ## Minimal DAG contract required by the refcount phase.
    ##
    ## A satisfying type exposes a `nodes` table and an `outEdges` accessor,
    ## which together let Step 5 count consumers per node without depending
    ## on the full DAG API surface.
    d.nodes is Table[NodeId, Node]
    d.outEdges(NodeId) is seq[NodeId]

  ValueClass* = enum
    ## Classification of a DAG value by how many downstream consumers it has.
    ##
    ## `vcLinear` (exactly one consumer) is the reuse-in-place candidate;
    ## `vcShared` (multiple consumers) forces a fresh allocation; `vcDead`
    ## (zero consumers) can be dropped by Step 4 DCE; `vcEscape` marks values
    ## in the Step 3 escape set that must outlive the current function frame.
    vcLinear, vcShared, vcEscape, vcDead

  RefInfo* = object
    ## Per-node refcount record: raw consumer count plus derived class.
    count: int
    class: ValueClass

  RefcountTable* = Table[NodeId, RefInfo]
    ## Result of the refcount phase, keyed by `NodeId`. Consumed by Step 6.

proc count*(r: RefInfo): int = r.count
  ## Returns the raw number of consumers for this node.
proc class*(r: RefInfo): ValueClass = r.class
  ## Returns the derived value classification for this node.

proc classifyOne(count: int, isEscape: bool): ValueClass =
  ## Maps a `(count, isEscape)` pair to its `ValueClass`; escape wins over count.
  if isEscape: vcEscape
  elif count == 0: vcDead
  elif count == 1: vcLinear
  else: vcShared

proc computeRefcounts*[D: RefcountInput](dag: D,
                                        escapes: HashSet[NodeId]): RefcountTable =
  ## Computes reference counts for every node in `dag`.
  ##
  ## The `dag` parameter satisfies `RefcountInput`; `escapes` is the Step 3
  ## escape set. For each node, records the out-edge count and classifies it
  ## as `vcLinear`, `vcShared`, `vcDead`, or `vcEscape`. Feeds Step 6 codegen:
  ## `vcLinear` values trigger reuse-in-place, `vcEscape` values are placed in
  ## the caller frame. See § Step 5.
  result = initTable[NodeId, RefInfo]()
  for id, n in dag.nodes:
    let outCount = dag.outEdges(id).len
    let isEscape = id in escapes
    result[id] = RefInfo(count: outCount,
                         class: classifyOne(outCount, isEscape))
