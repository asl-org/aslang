## Step 11 — Cross-function CSE / const-fold / DCE / fusion. See plans/plan_dag_ir.md § Step 11.

import ./dag_ir_core, ./phase_04_dce, ./phase_05_refcount,
       ./phase_07_value_domains, std/[tables, sets, hashes, sequtils]

type
  CrossOptInput* = concept d
    ## Abstract contract for a DAG mutable enough to support the Step 11
    ## rewrite passes: node lookup, edge queries in both directions, and
    ## node removal.
    d.nodes is Table[NodeId, Node]
    d.outEdges(NodeId) is seq[NodeId]
    d.inEdges(NodeId) is seq[NodeId]
    d.removeNode(NodeId)

  FusionRegistry* = Table[string, bool]
    ## Registry mapping callee name to a fusibility flag; declared by
    ## the platform layer so runtime primitives can opt into pipeline
    ## fusion.

  CrossOptStats* = object
    ## Counters returned by Step 11: per-pass CSE merges, folded nodes,
    ## DCE removals, fused pipelines, and total fixed-point iterations.
    cseMerges: int
    foldedNodes: int
    dceRemoved: int
    fusedPipelines: int
    passes: int

proc cseMerges*(s: CrossOptStats): int = s.cseMerges
  ## CSE merge count accessor.
proc foldedNodes*(s: CrossOptStats): int = s.foldedNodes
  ## Constant-folded node count accessor.
proc dceRemoved*(s: CrossOptStats): int = s.dceRemoved
  ## DCE removal count accessor.
proc fusedPipelines*(s: CrossOptStats): int = s.fusedPipelines
  ## Fused-pipeline count accessor.
proc passes*(s: CrossOptStats): int = s.passes
  ## Fixed-point iteration count accessor.

proc canonicalCallHash(n: Node): Hash =
  ## Hashes a call node by callee name plus argument NodeIds, giving a
  ## structural key that groups equivalent pure calls for CSE.
  var h: Hash = 0
  h = h !& hash(n.callee)
  for a in n.argIds: h = h !& hash(a)
  !$h

proc isEligibleForCse(n: Node): bool =
  ## Reports whether a node is a pure, effect-free call safe to merge
  ## with structurally identical siblings.
  n.kind in {nkCall, nkExtern} and n.isPure and not n.isEffect

proc groupByStructure(dag: CrossOptInput): Table[Hash, seq[NodeId]] =
  ## Buckets CSE-eligible nodes by their canonical call hash; each
  ## bucket with more than one member is a merge candidate.
  for id, n in dag.nodes:
    if not n.isEligibleForCse: continue
    let key = n.canonicalCallHash
    result.mgetOrPut(key, @[]).add(id)

proc mergeGroup(dag: CrossOptInput, group: seq[NodeId]): int =
  ## Merges every node in `group` into its first member, rewiring
  ## consumers and removing the duplicates. Returns the count merged.
  if group.len < 2: return 0
  let keep = group[0]
  for id in group[1..^1]:
    for consumer in dag.outEdges(id):
      dag.addEdge(keep, consumer, ekData)
    dag.removeNode(id)
  group.len - 1

proc runCse(dag: CrossOptInput): int =
  ## Performs one whole-DAG common-subexpression elimination pass and
  ## returns the total number of nodes merged.
  var merged = 0
  for _, group in dag.groupByStructure():
    merged += dag.mergeGroup(group)
  merged

proc allInputsConstant(dag: CrossOptInput, n: Node,
                       doms: DomainTable): bool =
  ## Reports whether every argument of `n` has a Step 7 singleton
  ## domain, meaning the call could in principle be folded.
  for a in n.argIds:
    if a notin doms: return false
    if doms[a].kind != dkSingleton: return false
  true

proc runConstFold(dag: CrossOptInput, doms: DomainTable): int =
  ## Counts pure calls whose arguments are all singletons.
  ## Placeholder — refine when Step 7's transfer registry exposes an
  ## evaluate-at-compile-time hook that can actually replace the node.
  # TODO: refine when Step 7's transfer registry exposes an
  # evaluate-at-compile-time hook.
  var folded = 0
  for id, n in dag.nodes:
    if n.kind notin {nkCall, nkExtern}: continue
    if not n.isPure: continue
    if not dag.allInputsConstant(n, doms): continue
    folded += 1
  folded

proc isFusibleChain(dag: CrossOptInput, id: NodeId,
                    fusible: FusionRegistry): bool =
  ## Reports whether the node at `id` is a call to a callee flagged
  ## fusible by the platform registry.
  let n = dag.nodes[id]
  if n.kind notin {nkCall, nkExtern}: return false
  fusible.getOrDefault(n.callee, false)

proc runFusion(dag: CrossOptInput, fusible: FusionRegistry): int =
  ## Counts producer-consumer pairs where both endpoints are fusible;
  ## drives the pipeline-fusion opportunities recorded in the stats.
  var fused = 0
  for id, n in dag.nodes:
    if not dag.isFusibleChain(id, fusible): continue
    for consumer in dag.outEdges(id):
      if dag.isFusibleChain(consumer, fusible):
        fused += 1
  fused

proc runPassOnce(dag: CrossOptInput, doms: DomainTable,
                 escapes: HashSet[NodeId],
                 fusible: FusionRegistry,
                 stats: var CrossOptStats): bool =
  ## Runs one round of CSE, constant folding, DCE and fusion, accruing
  ## per-pass counts into `stats`. Returns true iff any pass made a
  ## change, driving the outer fixed-point loop.
  let cse = dag.runCse()
  let folded = dag.runConstFold(doms)
  let dceRes = dag.eliminateDeadCode(escapes)
  let fused = dag.runFusion(fusible)
  stats.cseMerges += cse
  stats.foldedNodes += folded
  stats.dceRemoved += dceRes.removedCount
  stats.fusedPipelines += fused
  cse + folded + dceRes.removedCount + fused > 0

proc runCrossFunctionOpt*[D: CrossOptInput](dag: D,
                                            doms: DomainTable,
                                            escapes: HashSet[NodeId],
                                            fusible: FusionRegistry): CrossOptStats =
  ## Top-level Step 11 driver: iterates CSE/const-fold/DCE/fusion until
  ## fixpoint and returns aggregate statistics.
  ##
  ## The `dag` parameter satisfies `CrossOptInput` and is mutated in
  ## place. `doms` comes from Step 7, `escapes` from Step 3, and
  ## `fusible` from the platform layer. Runs after Step 10 inlining so
  ## intra-function CSE and cross-function CSE share one pass.
  var stats = CrossOptStats()
  while true:
    stats.passes += 1
    let changed = dag.runPassOnce(doms, escapes, fusible, stats)
    if not changed: break
  stats
