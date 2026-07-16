## Step 19 — SystemVerilog emitter. See plans/plan_dag_ir.md § Step 19.

import ./dag_ir_core, ./phase_14_bitwidth, ./phase_15_layout,
       ./phase_16_scheduling, ./phase_18_fpga_estimate, ./phase_20_kernel_extraction,
       std/[tables, sets, sequtils, strutils]

type
  SvInput* = concept d
    ## Abstract contract for DAGs consumable by the SystemVerilog emitter:
    ## only a node table is required.
    d.nodes is Table[NodeId, Node]

  SvContext* = object
    ## Bundle of upstream analyses the SV emitter reads: bitwidths
    ## (Step 14), byte layouts (Step 15), scheduling (Step 16), FPGA
    ## estimates (Step 18), and extracted kernels (Step 20).
    widths: WidthTable
    layouts: LayoutReport
    schedule: Schedule
    fpga: FpgaReport
    kernels: KernelReport

  SvModule* = object
    ## Single emitted SystemVerilog module: name, port declarations,
    ## internal wire/logic signals, module body, and a stub testbench.
    name: string
    ports: seq[string]
    signals: seq[string]
    body: string
    testbench: string

  SvProgram* = object
    ## Complete SV program: one module per kernel plus propagated FPGA
    ## resource-budget violations from Step 18.
    modules: seq[SvModule]
    resourceErrors: seq[string]

proc widths*(c: SvContext): WidthTable = c.widths
  ## Returns the Step 14 bitwidth table.
proc layouts*(c: SvContext): LayoutReport = c.layouts
  ## Returns the Step 15 layout report.
proc schedule*(c: SvContext): Schedule = c.schedule
  ## Returns the Step 16 schedule.
proc fpga*(c: SvContext): FpgaReport = c.fpga
  ## Returns the Step 18 FPGA estimation report.
proc kernels*(c: SvContext): KernelReport = c.kernels
  ## Returns the Step 20 kernel report.
proc name*(m: SvModule): string = m.name
  ## Returns the SV module identifier.
proc ports*(m: SvModule): seq[string] = m.ports
  ## Returns the port declarations.
proc signals*(m: SvModule): seq[string] = m.signals
  ## Returns the internal signal declarations.
proc body*(m: SvModule): string = m.body
  ## Returns the module body source.
proc testbench*(m: SvModule): string = m.testbench
  ## Returns the stub testbench source paired with this module.
proc modules*(p: SvProgram): seq[SvModule] = p.modules
  ## Returns the emitted SV modules.
proc resourceErrors*(p: SvProgram): seq[string] = p.resourceErrors
  ## Returns FPGA resource-budget violation messages forwarded from Step 18.

proc svBits(w: WidthAnnotation): string =
  ## Returns the SV packed-array range `[N-1:0] ` for a width, or empty
  ## string for single-bit signals.
  if w.bits <= 1: "" else: "[" & $(w.bits - 1) & ":0] "

proc svSignal(id: NodeId, w: WidthAnnotation): string =
  ## Emits an internal `logic [...] v<id>;` declaration.
  "logic " & svBits(w) & "v" & $id & ";"

proc emitPort(dir: string, id: NodeId, ctx: SvContext): string =
  ## Emits a single `input`/`output` port declaration for node `id`.
  let w = ctx.widths.getOrDefault(id, WidthAnnotation(class: scOpaque, bits: 32))
  dir & " logic " & svBits(w) & "v" & $id

proc emitModuleHeader(k: Kernel, ctx: SvContext): tuple[decl: string, ports: seq[string]] =
  ## Builds the `module kernel_<id> (...)` header with mandatory `clk`/
  ## `rst_n` plus one port per kernel input/output. Returns both the
  ## header string and the raw port list for later reuse.
  var ports: seq[string] = @["input logic clk", "input logic rst_n"]
  for i in k.signature.inputs: ports.add(emitPort("input", i, ctx))
  for o in k.signature.outputs: ports.add(emitPort("output", o, ctx))
  ("module kernel_" & $k.id & " (\n    " & ports.join(",\n    ") & "\n);\n",
   ports)

proc emitCombOp(id: NodeId, n: Node): string =
  ## Emits a combinational `assign` for recognised add/mul/and callees; any
  ## other callee is instantiated as an extern IP module reference.
  case n.callee
  of "u32_add", "add", "u8_add", "u16_add":
    "assign v" & $id & " = v" & $n.argIds[0] & " + v" & $n.argIds[1] & ";\n"
  of "u32_mul", "mul":
    "assign v" & $id & " = v" & $n.argIds[0] & " * v" & $n.argIds[1] & ";\n"
  of "u32_and", "and":
    "assign v" & $id & " = v" & $n.argIds[0] & " & v" & $n.argIds[1] & ";\n"
  else:
    let argStr = n.argIds.mapIt("v" & $it).join(", ")
    "// extern IP: " & n.callee & "\n" &
    n.callee & " u_" & n.callee & "_" & $id & " (" & argStr & ", v" & $id & ");\n"

proc emitBranchMux(id: NodeId, n: Node): string =
  ## Emits a ternary mux for 2-arm branches. Placeholder — refine
  ## multi-arm mux emission when Step 15 lands.
  if n.arms.len == 2:
    "assign v" & $id & " = v" & $n.subject & " ? v" &
      $n.arms[0].bodyReturn & " : v" & $n.arms[1].bodyReturn & ";\n"
  else:
    "// TODO: refine multi-arm mux emission when Step 15 lands.\n"

proc emitRecursionFsm(id: NodeId, n: Node): string =
  ## Emits a placeholder state-enum stub for a recursion node; real
  ## `always_ff` FSM lowering is deferred.
  "// opaque recursion node — needs always_ff FSM\n" &
  "typedef enum {S_COND_" & $id & ", S_ARM_" & $id & "} state_" & $id & "_t;\n"

proc emitNode(id: NodeId, n: Node, ctx: SvContext): string =
  ## Dispatches to the per-kind SV emitter for a single node.
  case n.kind
  of nkLiteral: "assign v" & $id & " = " & n.litValue & ";\n"
  of nkParam: ""
  of nkCall, nkExtern: emitCombOp(id, n)
  of nkBranch: emitBranchMux(id, n)
  of nkReturn: "// return handled at module port level\n"
  of nkRecursion: emitRecursionFsm(id, n)
  of nkPhi: "// phi\n"

proc emitPipelineRegisters(schedule: Schedule): string =
  ## Emits a comment placeholder per non-zero schedule level where a
  ## pipeline register bank will eventually be inserted.
  var sortedLevels: seq[int] = @[]
  for l, _ in schedule.perLevel: sortedLevels.add(l)
  for lvl in sortedLevels:
    if lvl == 0: continue
    result.add("// pipe reg for level " & $lvl & "\n")

proc emitTestbench(k: Kernel): string =
  ## Emits a minimal clock/reset testbench skeleton for kernel `k`;
  ## stimulus generation is left as a follow-up.
  "module kernel_" & $k.id & "_tb;\n" &
  "  logic clk = 0; always #5 clk = ~clk;\n" &
  "  logic rst_n = 0; initial #20 rst_n = 1;\n" &
  "  // TODO: refine when stimulus generators land.\n" &
  "endmodule\n"

proc emitKernelModule(dag: SvInput, ctx: SvContext, k: Kernel): SvModule =
  ## Assembles a full `SvModule` for kernel `k`: header, per-member signal
  ## declarations, per-node body statements walked in schedule order,
  ## pipeline-register hints, and a paired testbench.
  let (header, ports) = emitModuleHeader(k, ctx)
  var signals: seq[string] = @[]
  var body = header
  for id in ctx.schedule.order:
    if id notin k.members: continue
    let w = ctx.widths.getOrDefault(id, WidthAnnotation(class: scOpaque, bits: 32))
    signals.add(svSignal(id, w))
  for s in signals: body.add("    " & s & "\n")
  for id in ctx.schedule.order:
    if id notin k.members: continue
    body.add("    " & emitNode(id, dag.nodes[id], ctx))
  body.add(emitPipelineRegisters(ctx.schedule))
  body.add("endmodule\n")
  SvModule(name: "kernel_" & $k.id, ports: ports, signals: signals,
           body: body, testbench: emitTestbench(k))

proc emitProgram*[D: SvInput](dag: D, ctx: SvContext): SvProgram =
  ## Entry point for Step 19. Emits one SV module per Step 20 kernel and
  ## forwards Step 18's over-budget list as `resourceErrors`. The `dag`
  ## parameter satisfies `SvInput`. Consumes all upstream analyses via `ctx`.
  var modules: seq[SvModule] = @[]
  for k in ctx.kernels.kernels:
    modules.add(dag.emitKernelModule(ctx, k))
  SvProgram(modules: modules,
            resourceErrors: ctx.fpga.overBudget)
