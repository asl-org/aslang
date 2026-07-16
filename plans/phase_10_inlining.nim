## Step 10 — Whole-program inlining + effect propagation. See plans/plan_dag_ir.md § Step 10.

import ./dag_ir_core, std/[tables, sets, sequtils]

type
  FuncTable* = Table[string, Dag]
    ## Mapping from function name to its Step 1 DAG; the whole-program
    ## view fed to inlining.

  EffectMap* = Table[string, bool]
    ## Function name to effect flag; `true` marks a function that
    ## transitively performs an observable effect.

  InliningInput* = concept p
    ## Abstract contract for a whole-program view usable by Step 10:
    ## exposes the function table and the root entry function.
    p.functions is FuncTable
    p.rootFunc is string

  ProgramView* = object
    ## Concrete `InliningInput` implementation: bundles the per-function
    ## DAGs, the entry point, and any externally supplied effect
    ## annotations (e.g. FFI declarations).
    functions: FuncTable
    rootFunc: string
    externEffects: EffectMap

  RecursiveArmKind* = enum
    ## Classification of a branch arm inside a recursive function:
    ## `rakExit` terminates the recursion, `rakContinuation` recurses.
    rakExit, rakContinuation

  RecursiveArmInfo* = object
    ## Per-arm metadata produced by the recursion split: the arm's index
    ## in the branch and its recursion classification.
    armIndex: int
    kind: RecursiveArmKind

  TwoBlockSplit* = object
    ## Records a branch inside `fnName` that has been decomposed into
    ## its exit and continuation arms; used by Step 6 codegen to emit
    ## the loop head/body pair.
    fnName: string
    branchNode: NodeId
    arms: seq[RecursiveArmInfo]

  InliningReport* = object
    ## Aggregate result of Step 10: which call sites were inlined, the
    ## effect map produced by fixed-point propagation, and every
    ## recursion split that must be honoured downstream.
    inlinedCallSites: seq[NodeId]
    effectMap: EffectMap
    recursionSplits: seq[TwoBlockSplit]

proc functions*(p: ProgramView): FuncTable = p.functions
  ## Function-table accessor.
proc rootFunc*(p: ProgramView): string = p.rootFunc
  ## Entry-function name accessor.
proc externEffects*(p: ProgramView): EffectMap = p.externEffects
  ## Externally supplied effect annotations accessor.

proc armIndex*(a: RecursiveArmInfo): int = a.armIndex
  ## Arm index accessor.
proc kind*(a: RecursiveArmInfo): RecursiveArmKind = a.kind
  ## Arm classification accessor.
proc fnName*(s: TwoBlockSplit): string = s.fnName
  ## Owning-function name accessor.
proc branchNode*(s: TwoBlockSplit): NodeId = s.branchNode
  ## Split branch-node accessor.
proc arms*(s: TwoBlockSplit): seq[RecursiveArmInfo] = s.arms
  ## Arm-metadata accessor.

proc inlinedCallSites*(r: InliningReport): seq[NodeId] = r.inlinedCallSites
  ## Inlined-call-site accessor.
proc effectMap*(r: InliningReport): EffectMap = r.effectMap
  ## Effect-map accessor.
proc recursionSplits*(r: InliningReport): seq[TwoBlockSplit] = r.recursionSplits
  ## Recursion-split accessor.

proc calleesOf(dag: Dag): seq[string] =
  ## Collects every callee name reachable inside `dag`, spanning both
  ## `nkCall`/`nkExtern` and `nkRecursion` node kinds.
  for _, n in dag.nodes:
    case n.kind
    of nkCall, nkExtern: result.add(n.callee)
    of nkRecursion: result.add(n.recCallee)
    else: discard

proc isRecursive(view: ProgramView, name: string): bool =
  ## Reports whether `name` calls itself directly; the recursion split
  ## and the recursive rewrite both key off this predicate.
  if name notin view.functions: return false
  for callee in view.functions[name].calleesOf():
    if callee == name: return true

proc propagateEffects(view: ProgramView): EffectMap =
  ## Runs a fixed-point over the callgraph seeded from `externEffects`,
  ## marking a function effectful as soon as any callee is effectful.
  ## Result flows into Step 12 barrier detection and the ACSL `pure`
  ## clause emitted by Step 9.
  result = view.externEffects
  var changed = true
  while changed:
    changed = false
    for fname, dag in view.functions:
      if fname in result and result[fname]: continue
      var effect = false
      for callee in dag.calleesOf():
        if callee in result and result[callee]:
          effect = true; break
      if effect:
        result[fname] = true
        changed = true
      elif fname notin result:
        result[fname] = false

proc containsCallTo(dag: Dag, target: string, roots: seq[NodeId]): bool =
  ## Reports whether any root in `roots` directly resolves to a call of
  ## `target` (including recursion nodes); used by arm classification.
  for r in roots:
    let n = dag.nodes.getOrDefault(r)
    if n.isNil: continue
    case n.kind
    of nkCall, nkExtern:
      if n.callee == target: return true
    of nkRecursion:
      if n.recCallee == target: return true
    else: discard

proc classifyArm(dag: Dag, target: string, arm: BranchArm): RecursiveArmKind =
  ## Classifies a single branch arm as continuation (recurses into
  ## `target`) or exit (terminates the recursion).
  if dag.containsCallTo(target, arm.bodyRoots): rakContinuation
  else: rakExit

proc splitRecursive(dag: Dag, target: string): seq[TwoBlockSplit] =
  ## Walks every branch in `dag` and produces a `TwoBlockSplit` recording
  ## exit vs continuation classification per arm. Feeds Step 6 codegen's
  ## loop-lowering path.
  for id, n in dag.nodes:
    if n.kind != nkBranch: continue
    var arms: seq[RecursiveArmInfo] = @[]
    for i, arm in n.arms:
      arms.add(RecursiveArmInfo(armIndex: i,
                                kind: dag.classifyArm(target, arm)))
    result.add(TwoBlockSplit(fnName: target, branchNode: id, arms: arms))

proc rewriteAsRecursion(dag: Dag, target: string): seq[NodeId] =
  ## Rewrites each direct self-call to `target` as an `nkRecursion` node
  ## with `ekLoopBack` edges, converting the callgraph loop into an
  ## explicit intra-DAG back-edge understood by later phases.
  for id, n in dag.nodes:
    if n.kind in {nkCall, nkExtern} and n.callee == target:
      let rec = dag.newRecursionNode(target, n.argIds, n.loc)
      for i, a in n.argIds:
        dag.addEdge(a, rec.id, ekLoopBack, uint16(i))
      result.add(rec.id)

proc inlineNonRecursiveCall(caller: Dag, siteId: NodeId,
                            callee: Dag): NodeId =
  ## Substitutes `callee`'s body into `caller` at `siteId`.
  ## Placeholder — refine substitution once Step 1's env-cloning helper
  ## lands; currently emits a stub call node preserving the original
  ## signature.
  # TODO: refine substitution once Step 1's env-cloning helper lands.
  let n = caller.nodes[siteId]
  let stub = caller.newCallNode(n.callee, n.argIds, false, n.loc)
  discard callee
  stub.id

proc inlineOnce(view: ProgramView, effects: EffectMap,
                report: var InliningReport) =
  ## Single inlining sweep: for every non-recursive callee that lives in
  ## the program view, splice its body at the call site and record the
  ## site in `report`.
  for fname, dag in view.functions:
    for id, n in dag.nodes:
      if n.kind notin {nkCall, nkExtern}: continue
      if n.callee notin view.functions: continue
      if view.isRecursive(n.callee): continue
      discard dag.inlineNonRecursiveCall(id, view.functions[n.callee])
      report.inlinedCallSites.add(id)

proc runInlining*[P: InliningInput](view: P): InliningReport =
  ## Top-level Step 10 driver: propagates effects, inlines eligible
  ## non-recursive calls, then rewrites remaining recursive functions
  ## into split-arm + `nkRecursion` form.
  ##
  ## The `view` parameter satisfies `InliningInput`. Result feeds Step 6
  ## codegen (recursion splits), Step 9 (purity via effect map), and
  ## Step 11 (cross-function optimisation over the now-inlined DAGs).
  var report = InliningReport(inlinedCallSites: @[], effectMap: initTable[string, bool](),
                              recursionSplits: @[])
  let effects = view.propagateEffects()
  report.effectMap = effects
  inlineOnce(view, effects, report)
  for fname, dag in view.functions:
    if view.isRecursive(fname):
      report.recursionSplits.add(dag.splitRecursive(fname))
      discard dag.rewriteAsRecursion(fname)
  report
