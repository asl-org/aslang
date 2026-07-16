## Step 8 — Tail call optimization. See plans/plan_dag_ir.md § Step 8.

import ./dag_ir_core, ./phase_07_value_domains,
       std/[tables, sets, strutils, options]

type
  TailKind* = enum
    ## Classifies the return-position recursion pattern of a function.
    ##
    ## `tkSelfTailCall` — direct tail call to the same function (loop candidate);
    ## `tkSiblingTailCall` — tail call to a different function (musttail candidate);
    ## `tkNonTailRecursion` — recursive call not in tail position; `tkNotACall`
    ## — no recursion detected in tail position.
    tkSelfTailCall, tkSiblingTailCall, tkNonTailRecursion, tkNotACall

  TailInfo* = object
    ## Per-function tail-position summary: kind, node, and callee name.
    kind: TailKind
    at: NodeId
    callee: string

  OpAlgebra* = object
    ## Algebraic properties of an operator used to rewrite non-tail recursion
    ## into tail form (e.g. associative fold via accumulator).
    name: string
    associative: bool
    commutative: bool
    identity: string

  OpRegistry* = Table[string, OpAlgebra]
    ## Lookup from operator name to its `OpAlgebra`.

  TerminationProof* = enum
    ## Strength of the argument that a recursive call terminates.
    ##
    ## `tpStructural` — recursion on a strictly smaller structural argument;
    ## `tpMeasure` — a numeric measure strictly decreases; `tpLexicographic`
    ## — a lex-ordered tuple decreases; `tpUnprovable` — no proof succeeded.
    tpStructural, tpMeasure, tpLexicographic, tpUnprovable

  DepthAnnotation* = object
    ## User-supplied `@depth(N)` annotation, when present, capping recursion.
    present: bool
    n: int

  TailInput* = concept d
    ## DAG contract required by Step 8 — enough to walk from the return node
    ## and identify recursive calls back to the current function.
    d.nodes is Table[NodeId, Node]
    d.returnId is NodeId
    d.funcName is string
    d.inEdges(NodeId) is seq[NodeId]

  TailReport* = object
    ## Aggregate result of the tail-call phase, consumed by codegen and by the
    ## diagnostics layer to warn on unprovable non-tail recursion.
    tail: TailInfo
    proof: Option[TerminationProof]
    conversionSuggested: bool
    conversionOp: string
    warning: string

proc kind*(t: TailInfo): TailKind = t.kind
  ## Returns the classification of this tail position.
proc at*(t: TailInfo): NodeId = t.at
  ## Returns the node ID where the tail classification was made.
proc callee*(t: TailInfo): string = t.callee
  ## Returns the callee name at the tail position (empty when not a call).
proc name*(o: OpAlgebra): string = o.name
  ## Returns the operator name this algebra describes.
proc associative*(o: OpAlgebra): bool = o.associative
  ## Returns true when the operator is associative — the key property for
  ## rewriting non-tail recursion into an accumulator loop.
proc commutative*(o: OpAlgebra): bool = o.commutative
  ## Returns true when the operator is commutative.
proc identity*(o: OpAlgebra): string = o.identity
  ## Returns the operator's identity element as a literal string.
proc present*(d: DepthAnnotation): bool = d.present
  ## Returns true when the user supplied a `@depth(N)` annotation.
proc n*(d: DepthAnnotation): int = d.n
  ## Returns the annotated recursion depth cap.
proc tail*(r: TailReport): TailInfo = r.tail
  ## Returns the underlying tail-position classification.
proc proof*(r: TailReport): Option[TerminationProof] = r.proof
  ## Returns the termination proof, if one was found.
proc conversionSuggested*(r: TailReport): bool = r.conversionSuggested
  ## Returns true when the phase found a way to rewrite non-tail recursion
  ## into an accumulator form.
proc conversionOp*(r: TailReport): string = r.conversionOp
  ## Returns the operator name driving the suggested conversion.
proc warning*(r: TailReport): string = r.warning
  ## Returns a human-readable warning when recursion could not be proved safe.

proc classifyTailAt(dag: TailInput, id: NodeId): TailInfo =
  ## Recursively classifies the tail position rooted at `id`.
  ##
  ## Branches recurse into each arm, preferring self tail calls over sibling
  ## ones; `nkRecursion` nodes are treated as self tail calls; everything else
  ## is `tkNotACall`.
  let n = dag.nodes[id]
  case n.kind
  of nkCall, nkExtern:
    if n.callee == dag.funcName:
      TailInfo(kind: tkSelfTailCall, at: id, callee: n.callee)
    else:
      TailInfo(kind: tkSiblingTailCall, at: id, callee: n.callee)
  of nkBranch:
    var acc = TailInfo(kind: tkNotACall, at: id, callee: "")
    for arm in n.arms:
      let sub = dag.classifyTailAt(arm.bodyReturn)
      if sub.kind == tkSelfTailCall: return sub
      if sub.kind == tkSiblingTailCall: acc = sub
    acc
  of nkRecursion:
    TailInfo(kind: tkSelfTailCall, at: id, callee: n.recCallee)
  else:
    TailInfo(kind: tkNotACall, at: id, callee: "")

proc findRecursiveCalls(dag: TailInput): seq[NodeId] =
  ## Returns every node in `dag` that calls the current function by name.
  for id, n in dag.nodes:
    case n.kind
    of nkCall, nkExtern:
      if n.callee == dag.funcName: result.add(id)
    of nkRecursion:
      if n.recCallee == dag.funcName: result.add(id)
    else: discard

proc isTailPosition(dag: TailInput, id: NodeId): bool =
  ## Returns true when node `id` is the node classified as the tail position.
  let info = dag.classifyTailAt(dag.returnId)
  info.at == id

proc consumerOp(dag: TailInput, recCall: NodeId): string =
  ## Returns the callee name that consumes `recCall`'s result, if any — the
  ## outer operator wrapping a non-tail recursive call.
  let downstream = dag.nodes.getOrDefault(recCall)
  if downstream.isNil: return ""
  for _, n in dag.nodes:
    if n.kind in {nkCall, nkExtern}:
      if recCall in n.argIds: return n.callee
  ""

proc tryConvert(dag: TailInput, recCall: NodeId,
                ops: OpRegistry): tuple[ok: bool, op: string] =
  ## Attempts an accumulator-rewrite of `recCall` using an associative
  ## consumer op registered in `ops`. Returns `(true, opName)` on success.
  let opName = dag.consumerOp(recCall)
  if opName.len == 0: return (false, "")
  if opName notin ops: return (false, opName)
  let algebra = ops[opName]
  (algebra.associative, opName)

proc tryProveTermination(dag: TailInput, recCall: NodeId,
                         doms: DomainTable): TerminationProof =
  ## Attempts a termination proof for `recCall` using Step 7's domains.
  ##
  ## Placeholder — refine once Step 7 exposes per-arm subject narrowing.
  ## Currently returns `tpMeasure` whenever any argument has an int-range
  ## domain and `tpUnprovable` otherwise.
  # TODO: refine once Step 7 exposes per-arm subject narrowing.
  let n = dag.nodes[recCall]
  for a in n.argIds:
    if a in doms and doms[a].kind == dkIntRange:
      return tpMeasure
  tpUnprovable

proc analyzeTailCalls*[D: TailInput](dag: D, ops: OpRegistry,
                                     doms: DomainTable,
                                     depth: DepthAnnotation): TailReport =
  ## Produces a `TailReport` for `dag`, driving Step 17's loop lowering.
  ##
  ## First classifies the tail position; short-circuits when the function is
  ## already a self- or sibling-tail call. Otherwise gathers all recursive
  ## calls and, for each non-tail one, tries an accumulator rewrite via `ops`,
  ## then a termination proof via `doms`, and finally emits a warning if
  ## `depth` was not annotated. Consumes Step 7's domain table. See § Step 8.
  let info = dag.classifyTailAt(dag.returnId)
  var report = TailReport(tail: info, proof: none(TerminationProof),
                          conversionSuggested: false, conversionOp: "",
                          warning: "")
  if info.kind == tkSelfTailCall or info.kind == tkSiblingTailCall:
    return report
  let recCalls = dag.findRecursiveCalls()
  if recCalls.len == 0:
    report.tail = TailInfo(kind: tkNotACall, at: dag.returnId, callee: "")
    return report
  for r in recCalls:
    if dag.isTailPosition(r): continue
    let (ok, op) = dag.tryConvert(r, ops)
    if ok:
      report.conversionSuggested = true
      report.conversionOp = op
      return report
    let proof = dag.tryProveTermination(r, doms)
    if proof != tpUnprovable:
      report.proof = some(proof)
      return report
    if not depth.present:
      report.warning = "non-tail recursion at " & $r &
                       " could not be proved terminating; add @depth(N)"
  report

proc emitSelfTailLoop*(fnName: string): string =
  ## Emits a C skeleton lowering a self tail call to a labelled `goto` loop.
  ## Illustrative — real emission happens in Step 17.
  "$1_start:\n  /* body */\n  goto $1_start;\n" % [fnName]

proc emitSiblingTailJump*(callee: string): string =
  ## Emits a C `[[clang::musttail]]` return for a sibling tail call to `callee`.
  "[[clang::musttail]] return $1(...);\n" % [callee]
