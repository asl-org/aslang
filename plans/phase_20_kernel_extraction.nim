## Step 20 — Pure kernel extraction. See plans/plan_dag_ir.md § Step 20.

import ./dag_ir_core, ./phase_13_wcet, std/[tables, sets, sequtils, strutils]

type
  KernelInput* = concept d
    ## Abstract DAG contract for kernel extraction: node table plus forward and
    ## reverse edge access. Satisfied by the Step 1 DAG.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]
    d.outEdges(NodeId) is seq[NodeId]

  BoundaryRole* = enum
    ## Direction of data flow across an effectful boundary: `brInput` produces
    ## into pure regions, `brOutput` consumes from them, `brBoth` does both.
    brInput, brOutput, brBoth

  Boundary* = object
    ## One effectful call or extern node that separates pure kernel regions.
    id: NodeId
    externName: string
    role: BoundaryRole

  KernelSignature* = object
    ## External-facing input/output ports for one kernel; refers back into DAG.
    inputs: seq[NodeId]
    outputs: seq[NodeId]

  Kernel* = object
    ## One extracted pure subgraph — a candidate for FPGA or accelerator offload.
    ## `members` is the closed set of node ids; `scratchBytes` and `wcetCycles`
    ## feed the Step 18 FPGA estimator and Step 16 scheduler.
    id: int
    members: HashSet[NodeId]
    signature: KernelSignature
    scratchBytes: int
    wcetCycles: Wcet

  DispatchEntry* = object
    ## Runtime routing: when `eventBoundary` fires, launch kernel `kernelId`.
    eventBoundary: NodeId
    kernelId: int

  KernelReport* = object
    ## Full output of Step 20: the boundary set, extracted kernels, and their
    ## event-driven dispatch table. Feeds Step 14 bitwidth and later phases.
    boundaries: seq[Boundary]
    kernels: seq[Kernel]
    dispatch: seq[DispatchEntry]

proc id*(b: Boundary): NodeId = b.id
  ## Returns the DAG node id of boundary `b`.
proc externName*(b: Boundary): string = b.externName
  ## Returns the callee/extern name of the boundary node.
proc role*(b: Boundary): BoundaryRole = b.role
  ## Returns the data-flow direction across the boundary.
proc inputs*(s: KernelSignature): seq[NodeId] = s.inputs
  ## Returns the input port nodes of a kernel signature.
proc outputs*(s: KernelSignature): seq[NodeId] = s.outputs
  ## Returns the output port nodes of a kernel signature.
proc id*(k: Kernel): int = k.id
  ## Returns the kernel's index within the report.
proc members*(k: Kernel): HashSet[NodeId] = k.members
  ## Returns the set of DAG nodes belonging to kernel `k`.
proc signature*(k: Kernel): KernelSignature = k.signature
  ## Returns the input/output port signature of `k`.
proc scratchBytes*(k: Kernel): int = k.scratchBytes
  ## Returns the scratch-memory footprint of the kernel in bytes (cache-line aligned).
proc wcetCycles*(k: Kernel): Wcet = k.wcetCycles
  ## Returns the aggregated Step-13 WCET bound over the kernel's members.
proc eventBoundary*(e: DispatchEntry): NodeId = e.eventBoundary
  ## Returns the boundary that triggers the dispatch.
proc kernelId*(e: DispatchEntry): int = e.kernelId
  ## Returns the kernel to be launched when the boundary fires.
proc boundaries*(r: KernelReport): seq[Boundary] = r.boundaries
  ## Returns all boundary nodes discovered in the DAG.
proc kernels*(r: KernelReport): seq[Kernel] = r.kernels
  ## Returns all extracted kernels.
proc dispatch*(r: KernelReport): seq[DispatchEntry] = r.dispatch
  ## Returns the boundary-to-kernel dispatch table.

proc classifyBoundary(dag: KernelInput, id: NodeId): BoundaryRole =
  ## Classifies a boundary as input, output, or bidirectional based on its
  ## edge connectivity within `dag`.
  let n = dag.nodes[id]
  let hasProducers = dag.outEdges(id).len > 0
  let hasConsumers = dag.inEdges(id).len > 0
  if hasProducers and hasConsumers: brBoth
  elif hasProducers: brInput
  else: brOutput

proc locateBoundaries(dag: KernelInput): seq[Boundary] =
  ## Finds every effectful call/extern node in `dag`; these separate the pure
  ## regions that will become kernels.
  for id, n in dag.nodes:
    if n.kind notin {nkCall, nkExtern}: continue
    if not n.isEffect: continue
    result.add(Boundary(id: id, externName: n.callee,
                       role: dag.classifyBoundary(id)))

proc buildBoundarySet(bs: seq[Boundary]): HashSet[NodeId] =
  ## Collects boundary node ids into a set for fast membership tests.
  for b in bs: result.incl(b.id)

proc floodFrom(dag: KernelInput, seed: NodeId,
               skip: HashSet[NodeId],
               visited: var HashSet[NodeId], component: var HashSet[NodeId]) =
  ## Undirected connected-component flood fill that refuses to cross nodes in
  ## `skip`. Grows `component` with reachable non-boundary nodes.
  if seed in visited or seed in skip: return
  visited.incl(seed)
  component.incl(seed)
  for p in dag.inEdges(seed):
    dag.floodFrom(p, skip, visited, component)
  for c in dag.outEdges(seed):
    dag.floodFrom(c, skip, visited, component)

proc partitionIntoRegions(dag: KernelInput,
                          skip: HashSet[NodeId]): seq[HashSet[NodeId]] =
  ## Splits `dag` into pure connected regions separated by boundary nodes.
  ## Each region becomes one kernel candidate.
  var visited = initHashSet[NodeId]()
  for id, _ in dag.nodes:
    if id in skip or id in visited: continue
    var comp = initHashSet[NodeId]()
    dag.floodFrom(id, skip, visited, comp)
    if comp.len > 0: result.add(comp)

proc kernelInputsFromBoundaries(dag: KernelInput, comp: HashSet[NodeId],
                                boundaries: HashSet[NodeId]): seq[NodeId] =
  ## Returns boundary nodes that feed into the region `comp`; they become the
  ## kernel's input ports.
  for id in comp:
    for p in dag.inEdges(id):
      if p in boundaries: result.add(p)

proc kernelOutputsToBoundaries(dag: KernelInput, comp: HashSet[NodeId],
                               boundaries: HashSet[NodeId]): seq[NodeId] =
  ## Returns region-internal nodes that feed a boundary consumer; they become
  ## the kernel's output ports.
  for id in comp:
    for c in dag.outEdges(id):
      if c in boundaries: result.add(id)

proc widthBytesFor(n: Node): int =
  ## Approximates the storage footprint of `n` in bytes.
  ## Placeholder — refine once Step 14 attaches narrowed_width metadata.
  # TODO: refine once Step 14 attaches narrowed_width metadata.
  case n.kind
  of nkLiteral, nkCall, nkExtern: 4
  else: 0

proc computeScratchBytes(dag: KernelInput, comp: HashSet[NodeId]): int =
  ## Sums per-node byte widths across `comp` and rounds up to a 64-byte cache line.
  var total = 0
  for id in comp:
    total += widthBytesFor(dag.nodes[id])
  ((total + 63) div 64) * 64

proc computeKernelWcet(comp: HashSet[NodeId],
                       wcets: WcetTable): Wcet =
  ## Aggregates Step-13 per-node WCETs across `comp` via summation.
  ## Any `wkUnknown` member forces the kernel bound to `wkUnknown`.
  var acc: Wcet = Wcet(kind: wkKnown, cycles: 0)
  for id in comp:
    let w = wcets.getOrDefault(id, Wcet(kind: wkKnown, cycles: 0))
    if w.kind == wkUnknown: return w
    acc = Wcet(kind: wkKnown, cycles: acc.cycles + w.cycles)
  acc

proc buildKernels(dag: KernelInput, regions: seq[HashSet[NodeId]],
                  boundaries: HashSet[NodeId], wcets: WcetTable): seq[Kernel] =
  ## Constructs a `Kernel` value for each pure region, wiring signature,
  ## scratch footprint, and WCET.
  var kid = 0
  for comp in regions:
    result.add(Kernel(
      id: kid,
      members: comp,
      signature: KernelSignature(
        inputs: dag.kernelInputsFromBoundaries(comp, boundaries),
        outputs: dag.kernelOutputsToBoundaries(comp, boundaries)),
      scratchBytes: dag.computeScratchBytes(comp),
      wcetCycles: computeKernelWcet(comp, wcets)))
    kid += 1

proc buildDispatch(bs: seq[Boundary], ks: seq[Kernel]): seq[DispatchEntry] =
  ## Emits one dispatch entry per (input-boundary, kernel) pair whose input
  ## signature includes that boundary — the runtime routing table.
  for b in bs:
    if b.role notin {brInput, brBoth}: continue
    for k in ks:
      for i in k.signature.inputs:
        if i == b.id:
          result.add(DispatchEntry(eventBoundary: b.id, kernelId: k.id))
          break

proc extractKernels*[D: KernelInput](dag: D,
                                     wcets: WcetTable): KernelReport =
  ## Main entry point of Step 20. Locates effectful boundaries, floods pure
  ## regions between them, and packages each region as a `Kernel`.
  ##
  ## The `dag` parameter satisfies `KernelInput`; `wcets` is the Step-13 result.
  ## The report feeds Step 14 bitwidth (per-kernel scope), Step 18 FPGA
  ## estimation, and Step 19 SystemVerilog emission.
  let bs = dag.locateBoundaries()
  let boundarySet = buildBoundarySet(bs)
  let regions = dag.partitionIntoRegions(boundarySet)
  let ks = dag.buildKernels(regions, boundarySet, wcets)
  KernelReport(boundaries: bs, kernels: ks,
               dispatch: buildDispatch(bs, ks))
