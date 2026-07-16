## Step 16 — Instruction scheduling + register allocation. See plans/plan_dag_ir.md § Step 16.

import ./dag_ir_core, ./phase_05_refcount, ./phase_12_parallelism, ./phase_13_wcet,
       std/[tables, sets, sequtils, algorithm]

type
  ScheduleInput* = concept d
    ## Abstract contract for DAGs consumable by the scheduler: node table,
    ## roots, return node, and in/out edge accessors.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.returnId is NodeId
    d.inEdges(NodeId) is seq[NodeId]
    d.outEdges(NodeId) is seq[NodeId]

  RegisterId* = distinct int
    ## Opaque register identifier assigned by the allocator; `-1` sentinel
    ## denotes no register (spill or inline constant).

  Location* = enum
    ## Where an SSA value physically lives after allocation: a register,
    ## a spill slot, or inlined at each use site as a constant.
    locReg, locSpill, locConstInline

  Assignment* = object
    ## Per-node allocation decision produced by the register allocator.
    node: NodeId
    location: Location
    regId: RegisterId

  LiveRange* = object
    ## Half-open live interval expressed as scheduling-order indices:
    ## `defAt` is the definition index, `lastUseAt` the final-use index.
    defAt: int
    lastUseAt: int

  Schedule* = object
    ## Full scheduling output consumed by Step 17 (CPU codegen) and Step 19
    ## (SystemVerilog): linear order, level buckets, liveness, register
    ## assignments, and SIMD group hints from Step 12.
    order: seq[NodeId]
    perLevel: Table[int, seq[NodeId]]
    liveRanges: Table[NodeId, LiveRange]
    assignments: Table[NodeId, Assignment]
    simdGroups: seq[seq[NodeId]]

proc `==`*(a, b: RegisterId): bool {.borrow.}
  ## Equality on register identifiers, borrowed from the underlying `int`.
proc `$`*(r: RegisterId): string {.borrow.}
  ## String rendering of a register identifier, borrowed from `int`.

proc node*(a: Assignment): NodeId = a.node
  ## Returns the node this assignment targets.
proc location*(a: Assignment): Location = a.location
  ## Returns the physical location class chosen for the node.
proc regId*(a: Assignment): RegisterId = a.regId
  ## Returns the register identifier; meaningful only when `location == locReg`.
proc defAt*(l: LiveRange): int = l.defAt
  ## Returns the definition index of a live range in scheduling order.
proc lastUseAt*(l: LiveRange): int = l.lastUseAt
  ## Returns the final-use index of a live range in scheduling order.
proc order*(s: Schedule): seq[NodeId] = s.order
  ## Returns the linear topological execution order.
proc perLevel*(s: Schedule): Table[int, seq[NodeId]] = s.perLevel
  ## Returns nodes grouped by dependency depth level.
proc liveRanges*(s: Schedule): Table[NodeId, LiveRange] = s.liveRanges
  ## Returns the per-node live-range map.
proc assignments*(s: Schedule): Table[NodeId, Assignment] = s.assignments
  ## Returns the per-node register/spill/inline assignments.
proc simdGroups*(s: Schedule): seq[seq[NodeId]] = s.simdGroups
  ## Returns SIMD-vectorizable node groups carried from Step 12.

proc topoVisit(dag: ScheduleInput, id: NodeId,
               seen: var HashSet[NodeId], out_ordered: var seq[NodeId]) =
  ## Recursive DFS helper for `topoOrder`; appends `id` in post-order.

  if id in seen: return
  seen.incl(id)
  for p in dag.inEdges(id): dag.topoVisit(p, seen, out_ordered)
  out_ordered.add(id)

proc topoOrder(dag: ScheduleInput): seq[NodeId] =
  ## Produces a topological order over the DAG starting from roots and the
  ## return node, then sweeps any remaining nodes. Every dependency precedes
  ## its dependents in the returned sequence.
  var seen = initHashSet[NodeId]()
  for r in dag.roots: dag.topoVisit(r, seen, result)
  dag.topoVisit(dag.returnId, seen, result)
  for id, _ in dag.nodes: dag.topoVisit(id, seen, result)

proc computeLiveRanges(dag: ScheduleInput, order: seq[NodeId]): Table[NodeId, LiveRange] =
  ## Computes each node's live interval expressed in `order` indices: the
  ## range spans from its definition position to the maximum position of any
  ## consumer. Feeds `allocateRegisters` for freeing dead registers.
  var index = initTable[NodeId, int]()
  for i, id in order: index[id] = i
  for i, id in order:
    var lastUse = i
    for c in dag.outEdges(id):
      if c in index and index[c] > lastUse: lastUse = index[c]
    result[id] = LiveRange(defAt: i, lastUseAt: lastUse)

proc groupByLevel(dag: ScheduleInput, order: seq[NodeId]): Table[int, seq[NodeId]] =
  ## Buckets nodes by dependency depth: level 0 has no scheduled predecessors,
  ## level N is one past its deepest input. Downstream backends use levels for
  ## pipeline-register placement (Step 19) and per-cycle emission.
  var level = initTable[NodeId, int]()
  for id in order:
    var lvl = 0
    for p in dag.inEdges(id):
      let plvl = level.getOrDefault(p, -1)
      if plvl + 1 > lvl: lvl = plvl + 1
    level[id] = lvl
    result.mgetOrPut(lvl, @[]).add(id)

proc pickRegisterOrSpill(id: NodeId, live: LiveRange, refs: RefcountTable,
                         regBudget: int, inUse: var HashSet[RegisterId],
                         nextReg: var int): Assignment =
  ## Chooses a location for `id`: inline if dead per Step 5 refcounts, spill
  ## if the budget is exhausted, otherwise grab the next fresh register.
  let info = refs.getOrDefault(id, RefInfo(count: 0, class: vcDead))
  if info.class == vcDead:
    return Assignment(node: id, location: locConstInline, regId: RegisterId(-1))
  if inUse.len >= regBudget:
    return Assignment(node: id, location: locSpill, regId: RegisterId(-1))
  let r = RegisterId(nextReg)
  nextReg += 1
  inUse.incl(r)
  Assignment(node: id, location: locReg, regId: r)

proc releaseDeadRegisters(currentIdx: int, live: Table[NodeId, LiveRange],
                          assignments: Table[NodeId, Assignment],
                          inUse: var HashSet[RegisterId]) =
  ## Frees any register whose last use ended at `currentIdx - 1`, so it can be
  ## reassigned by the next `pickRegisterOrSpill` call.
  for id, lr in live:
    if lr.lastUseAt == currentIdx - 1:
      let a = assignments.getOrDefault(id)
      if a.location == locReg: inUse.excl(a.regId)

proc allocateRegisters(order: seq[NodeId], live: Table[NodeId, LiveRange],
                       refs: RefcountTable, regBudget: int): Table[NodeId, Assignment] =
  ## Linear-scan allocator that walks `order`, releasing dead registers before
  ## assigning each node. Bounded by `regBudget`; spills once exhausted.
  var inUse = initHashSet[RegisterId]()
  var nextReg = 0
  for i, id in order:
    releaseDeadRegisters(i, live, result, inUse)
    result[id] = pickRegisterOrSpill(id, live[id], refs, regBudget, inUse, nextReg)

proc findSimdGroups(par: ParallelReport): seq[seq[NodeId]] =
  ## Flattens Step 12's parallel groups into raw member sequences for the
  ## schedule's SIMD hint field.
  for g in par.groups:
    result.add(g.members)

proc scheduleFunction*[D: ScheduleInput](dag: D, refs: RefcountTable,
                                        par: ParallelReport,
                                        wcets: WcetTable,
                                        regBudget: int = 16): Schedule =
  ## Entry point for Step 16. Topologically orders `dag`, computes liveness,
  ## buckets nodes by level, allocates registers within `regBudget`, and
  ## attaches SIMD groups from `par`. The `dag` parameter satisfies
  ## `ScheduleInput`. Consumes Step 5 refcounts, Step 12 parallelism, and
  ## Step 13 WCETs (currently only refs and par are wired). The resulting
  ## `Schedule` is consumed by Step 17 (CPU) and Step 19 (SystemVerilog).
  let order = dag.topoOrder()
  let live = dag.computeLiveRanges(order)
  let perLevel = dag.groupByLevel(order)
  let assignments = allocateRegisters(order, live, refs, regBudget)
  Schedule(order: order, perLevel: perLevel, liveRanges: live,
           assignments: assignments,
           simdGroups: findSimdGroups(par))
