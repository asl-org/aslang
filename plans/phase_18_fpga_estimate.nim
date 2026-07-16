## Step 18 — FPGA resource estimation. See plans/plan_dag_ir.md § Step 18.

import ./dag_ir_core, ./phase_14_bitwidth, ./phase_12_parallelism,
       std/[tables, sets, sequtils, strutils]

type
  FpgaInput* = concept d
    ## Abstract contract for DAGs consumable by the FPGA estimator: a node
    ## table plus in-edge accessor.
    d.nodes is Table[NodeId, Node]
    d.inEdges(NodeId) is seq[NodeId]

  ResourceKind* = enum
    ## Whether a resource value has concrete numbers (`rkKnown`) or is a
    ## bailout with a human-readable reason (`rkOpaque`).
    rkKnown, rkOpaque

  Resource* = object
    ## Tagged union carrying either LUT/BRAM/DSP counts (`rkKnown`) or an
    ## opacity reason string (`rkOpaque`). Opacity is contagious under sum
    ## and max, so any unknown cost forces the aggregate to be opaque.
    case kind: ResourceKind
    of rkKnown:
      luts, brams, dsps: int
    of rkOpaque:
      reason: string

  FpgaCost* = Resource
    ## Alias: per-callee cost entries in the registry are just `Resource`.

  FpgaRegistry* = Table[string, FpgaCost]
    ## Callee-name to hardware-cost mapping, sourced from `@fpga_cost`
    ## annotations on extern IP declarations.

  FpgaBudget* = object
    ## Target device budgets checked by `checkBudget`; totals exceeding any
    ## budget surface in the report's `overBudget` list.
    lutBudget, bramBudget, dspBudget: int

  ResourceTable* = Table[NodeId, Resource]
    ## Per-node estimated resources.

  FpgaReport* = object
    ## Output of Step 18: per-node costs, aggregate total, and any budget
    ## violation strings. Consumed by Step 19 as `resourceErrors`.
    perNode: ResourceTable
    total: Resource
    overBudget: seq[string]

proc kind*(r: Resource): ResourceKind = r.kind
  ## Returns whether the resource is known or opaque.
proc luts*(r: Resource): int = r.luts
  ## Returns the LUT count; valid only when `kind == rkKnown`.
proc brams*(r: Resource): int = r.brams
  ## Returns the BRAM count; valid only when `kind == rkKnown`.
proc dsps*(r: Resource): int = r.dsps
  ## Returns the DSP-block count; valid only when `kind == rkKnown`.
proc reason*(r: Resource): string = r.reason
  ## Returns the opacity reason; valid only when `kind == rkOpaque`.
proc lutBudget*(b: FpgaBudget): int = b.lutBudget
  ## Returns the LUT budget for the target device.
proc bramBudget*(b: FpgaBudget): int = b.bramBudget
  ## Returns the BRAM budget for the target device.
proc dspBudget*(b: FpgaBudget): int = b.dspBudget
  ## Returns the DSP-block budget for the target device.
proc perNode*(r: FpgaReport): ResourceTable = r.perNode
  ## Returns the per-node cost breakdown.
proc total*(r: FpgaReport): Resource = r.total
  ## Returns the aggregate resource cost.
proc overBudget*(r: FpgaReport): seq[string] = r.overBudget
  ## Returns human-readable budget-violation messages.

proc known(luts, brams, dsps: int): Resource =
  ## Builds a concrete `rkKnown` resource with the given counts.
  Resource(kind: rkKnown, luts: luts, brams: brams, dsps: dsps)

proc opaque(reason: string): Resource =
  ## Builds an `rkOpaque` resource tagged with `reason`.
  Resource(kind: rkOpaque, reason: reason)

proc sumResource(a, b: Resource): Resource =
  ## Component-wise sum of two resources; opaque is contagious.
  if a.kind == rkOpaque: a
  elif b.kind == rkOpaque: b
  else: known(a.luts + b.luts, a.brams + b.brams, a.dsps + b.dsps)

proc maxResource(a, b: Resource): Resource =
  ## Component-wise max of two resources; opaque is contagious. Used to
  ## upper-bound mutually exclusive branch arms.
  if a.kind == rkOpaque: a
  elif b.kind == rkOpaque: b
  else: known(max(a.luts, b.luts), max(a.brams, b.brams), max(a.dsps, b.dsps))

proc lutForWidth(width: int): int =
  ## Rough per-bit LUT count for a basic arithmetic op; guards against
  ## non-positive widths by returning 1.
  # Rough per-bit LUT count for a basic arithmetic op.
  if width <= 0: 1 else: width

proc costOfCall(n: Node, widths: WidthTable, reg: FpgaRegistry): Resource =
  ## Looks up `n.callee` in the registry and scales its known LUT count by
  ## the actual operand bitwidth relative to a 32-bit baseline. Returns
  ## opaque if the callee has no `@fpga_cost` annotation.
  if n.callee in reg:
    let base = reg[n.callee]
    if base.kind == rkKnown:
      let w = widths.getOrDefault(n.id, WidthAnnotation(class: scOpaque, bits: 32))
      return known(base.luts * lutForWidth(w.bits) div 32, base.brams, base.dsps)
    return base
  opaque("no @fpga_cost for " & n.callee)

proc costOfNode(dag: FpgaInput, id: NodeId, widths: WidthTable,
                reg: FpgaRegistry, memo: ResourceTable): Resource =
  ## Per-node cost: literals/params/returns/recursion/phi are free, calls
  ## use `costOfCall`, and branches take the max across arms (mutually
  ## exclusive hardware paths).
  let n = dag.nodes[id]
  case n.kind
  of nkLiteral, nkParam: known(0, 0, 0)
  of nkCall, nkExtern: costOfCall(n, widths, reg)
  of nkBranch:
    var acc = known(0, 0, 0)
    for arm in n.arms:
      acc = maxResource(acc, memo.getOrDefault(arm.bodyReturn, known(0, 0, 0)))
    acc
  of nkReturn: known(0, 0, 0)
  of nkRecursion: known(0, 0, 0)
  of nkPhi: known(0, 0, 0)

proc applyParallelDiscount(base: Resource,
                           par: ParallelReport, id: NodeId): Resource =
  ## Placeholder — refine once Step 12 emits per-node group membership so
  ## parallel groups can be summed (physical replication) instead of maxed.
  # Parallel groups run as physical hardware — sum instead of max.
  # TODO: refine once Step 12 emits per-node group membership.
  discard par
  discard id
  base

proc totalCost(table: ResourceTable): Resource =
  ## Sums every per-node resource entry via `sumResource`.
  var acc = known(0, 0, 0)
  for _, r in table:
    acc = sumResource(acc, r)
  acc

proc checkBudget(total: Resource, budget: FpgaBudget): seq[string] =
  ## Emits one message per exceeded budget dimension; a single opaque total
  ## short-circuits with an opacity-notice message.
  if total.kind == rkOpaque:
    result.add("total cost opaque: " & total.reason)
    return
  if total.luts > budget.lutBudget:
    result.add("LUTs " & $total.luts & " > budget " & $budget.lutBudget)
  if total.brams > budget.bramBudget:
    result.add("BRAMs " & $total.brams & " > budget " & $budget.bramBudget)
  if total.dsps > budget.dspBudget:
    result.add("DSPs " & $total.dsps & " > budget " & $budget.dspBudget)

proc estimateFpga*[D: FpgaInput](dag: D, widths: WidthTable,
                                reg: FpgaRegistry, par: ParallelReport,
                                budget: FpgaBudget): FpgaReport =
  ## Entry point for Step 18. Estimates per-node hardware cost, applies
  ## parallelism discounts, aggregates the total, and flags budget
  ## overruns. The `dag` parameter satisfies `FpgaInput`. Consumes Step 14
  ## widths and Step 12 parallelism; produces the report consumed by Step 19.
  var per = initTable[NodeId, Resource]()
  for id, _ in dag.nodes:
    let base = dag.costOfNode(id, widths, reg, per)
    per[id] = applyParallelDiscount(base, par, id)
  let total = totalCost(per)
  FpgaReport(perNode: per, total: total,
             overBudget: checkBudget(total, budget))
