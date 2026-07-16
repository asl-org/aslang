## Step 9 — Frama-C spec generation. See plans/plan_dag_ir.md § Step 9.

import ./dag_ir_core, ./phase_07_value_domains,
       std/[tables, sets, strutils, sequtils]

type
  AcslInput* = concept d
    ## Abstract contract for a DAG that can be exported as ACSL/WP
    ## verification annotations. Requires node lookup, root list,
    ## a designated return node, and a function name for header emission.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]
    d.returnId is NodeId
    d.funcName is string

  Purity* = enum
    ## Function-level purity classification consumed by ACSL emission;
    ## `puPure` unlocks the `pure` clause and tightens `assigns \nothing`.
    puPure, puEffectful

  FunctionFacts* = object
    ## Bundle of per-function metadata sourced from Steps 5/11/13 and
    ## consumed by ACSL emission: purity plus optional WCET bound.
    isPure: Purity
    wcetCycles: int
    hasWcet: bool

  AcslClause* = object
    ## A single ACSL clause (e.g. `requires`, `ensures`, `assigns`) built
    ## from `kind` and `body`; empty `body` renders as a bare-keyword clause.
    kind: string
    body: string

  AcslBlock* = object
    ## Ordered collection of ACSL clauses that together form one
    ## `/*@ ... */` block wrapping a single function.
    clauses: seq[AcslClause]

proc isPure*(f: FunctionFacts): Purity = f.isPure
  ## Purity accessor.
proc wcetCycles*(f: FunctionFacts): int = f.wcetCycles
  ## WCET bound accessor in cycles; only meaningful when `hasWcet` is true.
proc hasWcet*(f: FunctionFacts): bool = f.hasWcet
  ## Reports whether a WCET bound is present.
proc kind*(c: AcslClause): string = c.kind
  ## Clause keyword accessor.
proc body*(c: AcslClause): string = c.body
  ## Clause body accessor.
proc clauses*(b: AcslBlock): seq[AcslClause] = b.clauses
  ## Clause-list accessor.

proc paramNodes(dag: AcslInput): seq[Node] =
  ## Extracts the parameter nodes from `dag.roots` for per-parameter
  ## precondition synthesis.
  for r in dag.roots:
    let n = dag.nodes[r]
    if n.kind == nkParam:
      result.add(n)

proc emitRequires(dag: AcslInput, doms: DomainTable): seq[AcslClause] =
  ## Emits one `requires` clause per parameter using its Step 7 value
  ## domain: integer ranges become `lo <= p <= hi`, singletons become
  ## `p == lit`; other domain kinds are skipped.
  for p in dag.paramNodes():
    let d = doms.getOrDefault(p.id)
    case d.kind
    of dkIntRange:
      result.add(AcslClause(kind: "requires",
                            body: "$1 >= $2 && $1 <= $3" %
                                  [p.paramName, $d.lo, $d.hi]))
    of dkSingleton:
      result.add(AcslClause(kind: "requires",
                            body: "$1 == $2" % [p.paramName, d.literal]))
    else: discard

proc emitEnsures(dag: AcslInput, doms: DomainTable): seq[AcslClause] =
  ## Emits an `ensures` clause describing `\result` from the Step 7 domain
  ## of the return node's feeder; skipped when the feeder has no known domain.
  let ret = dag.nodes[dag.returnId]
  let feeder = ret.retValue
  if feeder notin doms: return
  let d = doms[feeder]
  case d.kind
  of dkIntRange:
    result.add(AcslClause(kind: "ensures",
                          body: "\\result >= $1 && \\result <= $2" %
                                [$d.lo, $d.hi]))
  of dkSingleton:
    result.add(AcslClause(kind: "ensures",
                          body: "\\result == $1" % [d.literal]))
  else: discard

proc emitAssigns(escapes: HashSet[NodeId]): AcslClause =
  ## Emits the `assigns` clause using the Step 3 escape set: empty escape
  ## set means `assigns \nothing`; otherwise a placeholder `caller_frame`
  ## clause records the escape count for later refinement.
  if escapes.len == 0:
    AcslClause(kind: "assigns", body: "\\nothing")
  else:
    AcslClause(kind: "assigns",
               body: "caller_frame /* escapes: $1 */" % [$escapes.len])

proc emitPurity(f: FunctionFacts): seq[AcslClause] =
  ## Emits a bare `pure` clause when the function is classified pure.
  if f.isPure == puPure:
    result.add(AcslClause(kind: "pure", body: ""))

proc emitWcet(f: FunctionFacts): seq[AcslClause] =
  ## Emits an `ensures ExecutionTime <= N` clause when a WCET bound is
  ## available from Step 13.
  if f.hasWcet:
    result.add(AcslClause(kind: "ensures",
                          body: "ExecutionTime <= $1" % [$f.wcetCycles]))

proc generateAcsl*[D: AcslInput](dag: D, doms: DomainTable,
                                 escapes: HashSet[NodeId],
                                 facts: FunctionFacts): AcslBlock =
  ## Builds the full ACSL contract block for one function by concatenating
  ## `requires`, `ensures`, `assigns`, purity and WCET clauses.
  ##
  ## The `dag` parameter satisfies `AcslInput`. `doms` comes from Step 7
  ## value-domain analysis, `escapes` from Step 3, and `facts` aggregates
  ## Step 5/11/13 metadata. Result feeds `renderAcsl` for text emission.
  var block_ = AcslBlock(clauses: @[])
  block_.clauses.add(dag.emitRequires(doms))
  block_.clauses.add(dag.emitEnsures(doms))
  block_.clauses.add(emitAssigns(escapes))
  block_.clauses.add(emitPurity(facts))
  block_.clauses.add(emitWcet(facts))
  block_

proc renderAcsl*(b: AcslBlock): string =
  ## Renders an `AcslBlock` as a `/*@ ... */` comment ready to prepend to
  ## the C prototype emitted alongside Step 17 CPU codegen.
  result = "/*@\n"
  for c in b.clauses:
    if c.body.len == 0:
      result.add("    " & c.kind & ";\n")
    else:
      result.add("    " & c.kind & " " & c.body & ";\n")
  result.add("*/\n")

proc emitModuleInvariants*(): string =
  ## Emits compilation-unit-level ACSL axioms covering bump-allocator and
  ## watermark invariants. One-shot per compilation unit; not per function.
  "/*@ axiom bump_ok: bump_ptr <= bump_capacity;\n" &
  "    axiom watermark_ok: watermark_top >= 0; */\n"
