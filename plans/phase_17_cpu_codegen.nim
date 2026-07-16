## Step 17 — CPU C codegen. See plans/plan_dag_ir.md § Step 17.

import ./dag_ir_core, ./phase_14_bitwidth, ./phase_15_layout,
       ./phase_16_scheduling, ./phase_20_kernel_extraction, ./phase_09_frama_c,
       std/[tables, sets, strutils, sequtils]

type
  CpuInput* = concept d
    ## Abstract contract for DAGs consumable by the CPU emitter: a node
    ## table plus a roots list.
    d.nodes is Table[NodeId, Node]
    d.roots is seq[NodeId]

  EmitContext* = object
    ## Bundle of upstream analyses the CPU emitter reads: bitwidths
    ## (Step 14), byte layouts (Step 15), scheduling (Step 16), extracted
    ## kernels (Step 20), and ACSL frame contracts (Step 9).
    widths: WidthTable
    layouts: LayoutReport
    schedule: Schedule
    kernels: KernelReport
    acsl: AcslBlock

  EmittedFunction* = object
    ## Single emitted C function: name, C signature, body, and
    ## Frama-C/ACSL contract prologue.
    name: string
    signature: string
    body: string
    acsl: string

  EmittedProgram* = object
    ## Complete CPU program: static scratch buffers, kernel function
    ## definitions, and an event-driven dispatch loop.
    scratchBuffers: seq[string]
    kernelFunctions: seq[EmittedFunction]
    dispatchLoop: string

proc widths*(c: EmitContext): WidthTable = c.widths
  ## Returns the Step 14 bitwidth table.
proc layouts*(c: EmitContext): LayoutReport = c.layouts
  ## Returns the Step 15 layout report.
proc schedule*(c: EmitContext): Schedule = c.schedule
  ## Returns the Step 16 schedule.
proc kernels*(c: EmitContext): KernelReport = c.kernels
  ## Returns the Step 20 kernel report.
proc acsl*(c: EmitContext): AcslBlock = c.acsl
  ## Returns the Step 9 ACSL contract block.
proc name*(f: EmittedFunction): string = f.name
  ## Returns the C identifier of an emitted function.
proc signature*(f: EmittedFunction): string = f.signature
  ## Returns the C-language signature line.
proc body*(f: EmittedFunction): string = f.body
  ## Returns the C-language function body.
proc acsl*(f: EmittedFunction): string = f.acsl
  ## Returns the rendered ACSL contract prologue.
proc scratchBuffers*(p: EmittedProgram): seq[string] = p.scratchBuffers
  ## Returns the per-kernel static scratch declarations.
proc kernelFunctions*(p: EmittedProgram): seq[EmittedFunction] = p.kernelFunctions
  ## Returns the emitted C kernel functions.
proc dispatchLoop*(p: EmittedProgram): string = p.dispatchLoop
  ## Returns the top-level event-dispatch loop source.

proc cTypeFor(w: WidthAnnotation): string =
  ## Maps a Step 14 width annotation to its C type spelling.
  case w.class
  of scConstant: "/* inline */"
  of scUnsigned: "uint" & $w.bits & "_t"
  of scSigned: "int" & $w.bits & "_t"
  of scFloat: (if w.bits == 32: "float" else: "double")
  of scOpaque: "uint64_t"

proc valueName(id: NodeId): string = "v" & $id
  ## Returns the C identifier used for the SSA value of `id`.

proc emitParamList(dag: CpuInput, ctx: EmitContext,
                   params: seq[NodeId]): string =
  ## Renders a comma-separated C parameter list from a sequence of param
  ## node ids, using each node's declared name and width.
  var parts: seq[string] = @[]
  for p in params:
    let n = dag.nodes[p]
    let w = ctx.widths.getOrDefault(p, WidthAnnotation(class: scOpaque, bits: 64))
    parts.add(cTypeFor(w) & " " & n.paramName)
  parts.join(", ")

proc emitSignature(dag: CpuInput, ctx: EmitContext, k: Kernel): string =
  ## Builds the C function signature for kernel `k`, appending a trailing
  ## `void* scratch` for its scratch-buffer pointer.
  let outType =
    if k.signature.outputs.len == 0: "void"
    else: cTypeFor(ctx.widths.getOrDefault(k.signature.outputs[0],
                                          WidthAnnotation(class: scOpaque, bits: 64)))
  outType & " kernel_" & $k.id & "(" &
    dag.emitParamList(ctx, k.signature.inputs) & ", void* scratch)"

proc emitLiteral(id: NodeId, n: Node, ctx: EmitContext): string =
  ## Emits `T v<id> = <literal>;` for an `nkLiteral` node.
  let w = ctx.widths.getOrDefault(id)
  cTypeFor(w) & " " & valueName(id) & " = " & n.litValue & ";\n"

proc emitCall(id: NodeId, n: Node, ctx: EmitContext): string =
  ## Emits `T v<id> = callee(args...);` for an `nkCall` or `nkExtern` node.
  let argStr = n.argIds.mapIt(valueName(it)).join(", ")
  let w = ctx.widths.getOrDefault(id)
  cTypeFor(w) & " " & valueName(id) & " = " & n.callee & "(" & argStr & ");\n"

proc emitBranch(id: NodeId, n: Node, ctx: EmitContext): string =
  ## Placeholder branch emitter — refine once branch codegen picks per-arm
  ## hot/cold reordering.
  # TODO: refine once branch codegen picks per-arm hot/cold reordering.
  "/* branch on " & valueName(n.subject) & " (arms: " & $n.arms.len & ") */\n"

proc emitReturn(n: Node): string =
  ## Emits `return v<retValue>;` for an `nkReturn` node.
  "return " & valueName(n.retValue) & ";\n"

proc emitOneNode(dag: CpuInput, ctx: EmitContext, id: NodeId): string =
  ## Dispatches to the per-kind emit helper for a single node.
  let n = dag.nodes[id]
  case n.kind
  of nkLiteral: emitLiteral(id, n, ctx)
  of nkParam: ""
  of nkCall, nkExtern: emitCall(id, n, ctx)
  of nkBranch: emitBranch(id, n, ctx)
  of nkReturn: emitReturn(n)
  of nkRecursion: "goto __loop_" & n.recCallee & ";\n"
  of nkPhi: "/* phi collapsed */\n"

proc emitKernelBody(dag: CpuInput, ctx: EmitContext,
                    k: Kernel): string =
  ## Walks the schedule in order, emitting only nodes belonging to `k`. The
  ## global schedule guarantees per-kernel topological ordering.
  for id in ctx.schedule.order:
    if id in k.members:
      result.add(dag.emitOneNode(ctx, id))

proc emitKernelScratch(k: Kernel): string =
  ## Emits the static byte-array scratch buffer declaration for kernel `k`.
  "static uint8_t kernel_" & $k.id & "_scratch[" & $k.scratchBytes & "];\n"

proc emitKernelFunction(dag: CpuInput, ctx: EmitContext,
                        k: Kernel): EmittedFunction =
  ## Assembles one `EmittedFunction` for kernel `k` — name, signature, body,
  ## and rendered ACSL contract.
  EmittedFunction(
    name: "kernel_" & $k.id,
    signature: dag.emitSignature(ctx, k),
    body: dag.emitKernelBody(ctx, k),
    acsl: renderAcsl(ctx.acsl))

proc emitDispatchLoop(kernels: KernelReport): string =
  ## Emits a `while (true) { switch (event.type) ... }` dispatcher that
  ## invokes each kernel with its scratch pointer on the matching event.
  result = "while (true) {\n  event = wait_for_event();\n  switch (event.type) {\n"
  for e in kernels.dispatch:
    result.add("  case E_" & $e.eventBoundary & ": kernel_" & $e.kernelId &
               "(event.data, kernel_" & $e.kernelId & "_scratch); break;\n")
  result.add("  }\n}\n")

proc emitProgram*[D: CpuInput](dag: D, ctx: EmitContext): EmittedProgram =
  ## Entry point for Step 17. Emits every kernel in `ctx.kernels` as a C
  ## function plus its scratch buffer, then assembles the top-level dispatch
  ## loop. The `dag` parameter satisfies `CpuInput`. Consumes all upstream
  ## analyses via `ctx`.
  var funcs: seq[EmittedFunction] = @[]
  var scratches: seq[string] = @[]
  for k in ctx.kernels.kernels:
    scratches.add(emitKernelScratch(k))
    funcs.add(dag.emitKernelFunction(ctx, k))
  EmittedProgram(scratchBuffers: scratches,
                 kernelFunctions: funcs,
                 dispatchLoop: emitDispatchLoop(ctx.kernels))

proc renderFullFunction*(f: EmittedFunction): string =
  ## Concatenates ACSL contract, signature, and body into a single C
  ## function definition ready for output.
  f.acsl & f.signature & " {\n" & f.body & "}\n"
