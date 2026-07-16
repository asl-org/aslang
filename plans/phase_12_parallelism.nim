## Step 12 — Parallelism identification. See plans/plan_dag_ir.md § Step 12.

import ./dag_ir_core, std/[tables, sets, sequtils, algorithm]

type
  ParallelInput* = concept d
    ## Abstract contract for a DAG that can be scanned for parallel
    ## groups: node lookup, root list, and edges in both directions.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]
    d.outEdges(NodeId) is seq[NodeId]

  ParallelGroup* = object
    ## A set of independent nodes sharing the same dependency level and
    ## therefore safe to dispatch concurrently. `id` is the group index,
    ## `level` its topological depth, `members` the node cohort.
    id: int
    level: int
    members: seq[NodeId]

  ParallelReport* = object
    ## Aggregate result: barrier nodes that break parallel regions, the
    ## detected `ParallelGroup`s, and the per-node topological levels
    ## used to build them.
    barriers: seq[NodeId]
    groups: seq[ParallelGroup]
    levels: Table[NodeId, int]

proc id*(g: ParallelGroup): int = g.id
  ## Group index accessor.
proc level*(g: ParallelGroup): int = g.level
  ## Group level accessor.
proc members*(g: ParallelGroup): seq[NodeId] = g.members
  ## Group members accessor.
proc barriers*(r: ParallelReport): seq[NodeId] = r.barriers
  ## Barrier list accessor.
proc groups*(r: ParallelReport): seq[ParallelGroup] = r.groups
  ## Group list accessor.
proc levels*(r: ParallelReport): Table[NodeId, int] = r.levels
  ## Per-node level accessor.

proc isBarrier(n: Node): bool =
  ## Reports whether a node acts as a barrier: effectful calls and
  ## recursion nodes cannot participate in parallel groups.
  case n.kind
  of nkCall, nkExtern: n.isEffect
  of nkRecursion: true
  else: false

proc collectBarriers(dag: ParallelInput): seq[NodeId] =
  ## Walks `dag` and returns every barrier node; used to exclude these
  ## nodes from candidate groups.
  for id, n in dag.nodes:
    if n.isBarrier: result.add(id)

proc computeLevel(dag: ParallelInput, id: NodeId,
                  memo: var Table[NodeId, int]): int =
  ## Memoised longest-path-from-root computation: a node's level is
  ## `1 + max(parent levels)`, `0` at the roots.
  if id in memo: return memo[id]
  var maxParent = -1
  for p in dag.inEdges(id):
    let plevel = dag.computeLevel(p, memo)
    if plevel > maxParent: maxParent = plevel
  memo[id] = maxParent + 1
  memo[id]

proc computeAllLevels(dag: ParallelInput): Table[NodeId, int] =
  ## Fills a `NodeId -> level` map by invoking `computeLevel` for every
  ## node; result is retained in the report for downstream schedulers.
  for id, _ in dag.nodes:
    discard dag.computeLevel(id, result)

proc isPurePartitionable(n: Node): bool =
  ## Reports whether a node is a legal group member: pure/effect-free
  ## calls plus literals and parameters. Anything else is skipped.
  case n.kind
  of nkCall, nkExtern: n.isPure and not n.isEffect
  of nkLiteral, nkParam: true
  else: false

proc groupByLevel(dag: ParallelInput, levels: Table[NodeId, int],
                  barriers: HashSet[NodeId]): Table[int, seq[NodeId]] =
  ## Buckets partitionable non-barrier nodes by their topological level;
  ## each bucket is a potential parallel group.
  for id, n in dag.nodes:
    if id in barriers: continue
    if not n.isPurePartitionable: continue
    let lvl = levels.getOrDefault(id, -1)
    if lvl < 0: continue
    result.mgetOrPut(lvl, @[]).add(id)

proc buildGroups(byLevel: Table[int, seq[NodeId]]): seq[ParallelGroup] =
  ## Emits one `ParallelGroup` per level with two or more members,
  ## sorted by level so the report's order matches execution order.
  var groupId = 0
  var sortedLevels: seq[int] = @[]
  for l, _ in byLevel: sortedLevels.add(l)
  sortedLevels.sort()
  for lvl in sortedLevels:
    let members = byLevel[lvl]
    if members.len < 2: continue
    result.add(ParallelGroup(id: groupId, level: lvl, members: members))
    groupId += 1

proc identifyParallelism*[D: ParallelInput](dag: D): ParallelReport =
  ## Top-level Step 12 driver: locates barriers, computes topological
  ## levels, and builds parallel groups of level-siblings.
  ##
  ## The `dag` parameter satisfies `ParallelInput`. Consumes the effect
  ## flag propagated by Step 10 to decide barriers. Result feeds Step 16
  ## scheduling and Step 17 CPU codegen (dispatch annotations).
  let barrierSeq = dag.collectBarriers()
  var barrierSet = initHashSet[NodeId]()
  for b in barrierSeq: barrierSet.incl(b)
  let levels = dag.computeAllLevels()
  let byLevel = dag.groupByLevel(levels, barrierSet)
  ParallelReport(barriers: barrierSeq,
                 groups: buildGroups(byLevel),
                 levels: levels)

proc annotationFor*(g: ParallelGroup): string =
  ## Renders a `@parallel_candidate(...)` annotation string for `g`,
  ## consumed by Step 17 codegen when emitting dispatch metadata.
  "@parallel_candidate(group_id=" & $g.id & ", n=" & $g.members.len & ")"
