## Step 14 — Bit-width narrowing. See plans/plan_dag_ir.md § Step 14.

import ./dag_ir_core, ./phase_07_value_domains, std/[tables, sets]

type
  BitwidthInput* = concept d
    ## Minimal DAG contract this phase reads: just the node table, since
    ## widths are picked node-locally from the Step-7 `DomainTable`.
    d.nodes is Table[NodeId, Node]

  StorageClass* = enum
    ## High-level bucket for storage: compile-time constant, unsigned/signed
    ## integer, IEEE float, or opaque (bag-of-bits, fall back to native word).
    scConstant, scUnsigned, scSigned, scFloat, scOpaque

  WidthAnnotation* = object
    ## Per-node narrowing decision: storage class plus the smallest bit-width
    ## that safely holds the Step-7 value domain. `isConstant`+`literal` short-
    ## circuit codegen when the value is a compile-time singleton.
    class: StorageClass
    bits: int
    isConstant: bool
    literal: string

  WidthTable* = Table[NodeId, WidthAnnotation]
    ## Per-node width annotations produced by this phase; consumed by Step 15
    ## layout, Step 17 CPU codegen, and Step 19 SystemVerilog emission.

proc class*(w: WidthAnnotation): StorageClass = w.class
  ## Returns the storage class of `w`.
proc bits*(w: WidthAnnotation): int = w.bits
  ## Returns the narrowed bit-width of `w`.
proc isConstant*(w: WidthAnnotation): bool = w.isConstant
  ## Returns true when the value is a compile-time constant.
proc literal*(w: WidthAnnotation): string = w.literal
  ## Returns the constant literal text; only meaningful when `isConstant`.

proc pickUnsignedWidth(hi: int64): int =
  ## Returns the smallest unsigned power-of-two width (8/16/32/64) holding `hi`.
  if hi < 256: 8
  elif hi < 65536: 16
  elif hi < 4294967296'i64: 32
  else: 64

proc pickSignedWidth(lo, hi: int64): int =
  ## Returns the smallest signed two's-complement width holding `[lo, hi]`.
  if lo >= -128 and hi < 128: 8
  elif lo >= -32768 and hi < 32768: 16
  elif lo >= -2147483648'i64 and hi < 2147483648'i64: 32
  else: 64

proc classifyType(ty: string): StorageClass =
  ## Maps a source-type prefix (`u`/`i`/`f`) to the corresponding storage class.
  if ty.startsWith("u"): scUnsigned
  elif ty.startsWith("i"): scSigned
  elif ty.startsWith("f"): scFloat
  else: scOpaque

proc annotateFromDomain(n: Node, d: Domain): WidthAnnotation =
  ## Picks a `WidthAnnotation` for node `n` given its Step-7 value domain `d`.
  ## Singletons become constants; integer ranges narrow by class; floats and
  ## unknowns fall back to sensible defaults (32-bit float, 64-bit opaque).
  case d.kind
  of dkSingleton:
    WidthAnnotation(class: scConstant, bits: 0,
                    isConstant: true, literal: d.literal)
  of dkIntRange:
    let sourceType =
      case n.kind
      of nkLiteral: n.litType
      of nkParam: n.paramType
      else: "u32"
    let cls = classifyType(sourceType)
    case cls
    of scUnsigned:
      WidthAnnotation(class: cls, bits: pickUnsignedWidth(d.hi),
                      isConstant: false, literal: "")
    of scSigned:
      WidthAnnotation(class: cls, bits: pickSignedWidth(d.lo, d.hi),
                      isConstant: false, literal: "")
    else:
      WidthAnnotation(class: scOpaque, bits: 64, isConstant: false, literal: "")
  of dkFloatRange:
    WidthAnnotation(class: scFloat, bits: 32, isConstant: false, literal: "")
  else:
    WidthAnnotation(class: scOpaque, bits: 64, isConstant: false, literal: "")

proc narrowWidths*[D: BitwidthInput](dag: D, doms: DomainTable): WidthTable =
  ## Main entry point of Step 14. Assigns each node in `dag` the narrowest safe
  ## bit-width derived from its Step-7 domain in `doms`.
  ##
  ## The `dag` parameter satisfies `BitwidthInput`. Nodes missing a domain get
  ## `dkFull` (opaque 64-bit). Output feeds Step 15 layout and Step 17 codegen.
  for id, n in dag.nodes:
    let d = doms.getOrDefault(id, Domain(kind: dkFull))
    result[id] = annotateFromDomain(n, d)

proc totalBytes*(w: WidthTable): int =
  ## Sums non-constant storage across `w`, rounded up to whole bytes. Useful
  ## for reporting the aggregate memory savings of narrowing.
  for _, a in w:
    if a.isConstant: continue
    result += (a.bits + 7) div 8
