## Step 15 — Data layout optimization. See plans/plan_dag_ir.md § Step 15.

import ./dag_ir_core, ./phase_14_bitwidth, std/[tables, sets, sequtils, algorithm]

type
  LayoutInput* = concept d
    ## Abstract DAG contract this phase reads: node table only. Access sites
    ## are supplied separately via `AccessLog`.
    d.nodes is Table[NodeId, Node]

  StructField* = object
    ## One named field of a struct definition, with its source type and width.
    name: string
    ty: string
    bits: int

  StructDef* = object
    ## Named struct type declared in the program; the unit of layout.
    name: string
    fields: seq[StructField]

  FieldAccess* = object
    ## One observed read/write of `fieldName` on struct `structName` at DAG
    ## node `siteId`. Feeds the co-access matrix used for hot/cold clustering.
    structName: string
    fieldName: string
    siteId: NodeId

  AccessLog* = seq[FieldAccess]
    ## Full trace of field accesses across the program, gathered by prior phases.

  LayoutKind* = enum
    ## Chosen physical layout: array-of-structs or struct-of-arrays.
    lkAoS, lkSoA

  ClusterId* = distinct int
    ## Opaque hot/cold clustering id; `distinct` so it never mixes with `int`.

  FieldLayout* = object
    ## Placement of one field: which cluster, byte offset in its cache line,
    ## and padding needed for alignment.
    field: string
    clusterId: ClusterId
    cacheLineOffset: int
    padBytes: int

  StructLayout* = object
    ## Full layout decision for one struct: the AoS/SoA choice, per-field
    ## placements, and the classified hot/cold field sets.
    structName: string
    kind: LayoutKind
    fields: seq[FieldLayout]
    hotCluster, coldCluster: seq[string]

  LayoutReport* = Table[string, StructLayout]
    ## Layout output keyed by struct name; consumed by Step 17 CPU codegen.

proc `==`*(a, b: ClusterId): bool {.borrow.}
  ## Equality on `ClusterId`, borrowed from the underlying `int`.
proc `$`*(c: ClusterId): string {.borrow.}
  ## String rendering of `ClusterId`, borrowed from the underlying `int`.

proc name*(f: StructField): string = f.name
  ## Returns the field's declared name.
proc ty*(f: StructField): string = f.ty
  ## Returns the field's source-type string.
proc bits*(f: StructField): int = f.bits
  ## Returns the field's declared bit-width.
proc name*(s: StructDef): string = s.name
  ## Returns the struct's declared name.
proc fields*(s: StructDef): seq[StructField] = s.fields
  ## Returns the struct's field list in declaration order.
proc structName*(a: FieldAccess): string = a.structName
  ## Returns the struct being accessed.
proc fieldName*(a: FieldAccess): string = a.fieldName
  ## Returns the field being accessed.
proc siteId*(a: FieldAccess): NodeId = a.siteId
  ## Returns the DAG node where the access happens.
proc field*(f: FieldLayout): string = f.field
  ## Returns the laid-out field's name.
proc clusterId*(f: FieldLayout): ClusterId = f.clusterId
  ## Returns the cluster this field was assigned to.
proc cacheLineOffset*(f: FieldLayout): int = f.cacheLineOffset
  ## Returns the field's byte offset within its cache line.
proc padBytes*(f: FieldLayout): int = f.padBytes
  ## Returns the padding bytes inserted before this field for alignment.
proc structName*(s: StructLayout): string = s.structName
  ## Returns the struct name this layout describes.
proc kind*(s: StructLayout): LayoutKind = s.kind
  ## Returns the chosen AoS/SoA layout kind.
proc fields*(s: StructLayout): seq[FieldLayout] = s.fields
  ## Returns the per-field placements.
proc hotCluster*(s: StructLayout): seq[string] = s.hotCluster
  ## Returns the set of frequently accessed field names.
proc coldCluster*(s: StructLayout): seq[string] = s.coldCluster
  ## Returns the set of rarely accessed field names.

proc coAccessMatrix(log: AccessLog, structName: string,
                    fieldNames: seq[string]): Table[(string, string), int] =
  ## Counts nodes that read both fields i and j — sites keyed by NodeId
  ## are the unit of co-access, so we bucket by siteId first. The resulting
  ## symmetric matrix (stored as sorted pairs) drives `clusterFields`.
  var bySite = initTable[NodeId, HashSet[string]]()
  for entry in log:
    if entry.structName != structName: continue
    bySite.mgetOrPut(entry.siteId, initHashSet[string]()).incl(entry.fieldName)
  for _, fields in bySite:
    let fs = toSeq(fields)
    for i in 0 ..< fs.len:
      for j in i+1 ..< fs.len:
        let key = if fs[i] < fs[j]: (fs[i], fs[j]) else: (fs[j], fs[i])
        result[key] = result.getOrDefault(key, 0) + 1

proc accessFrequency(log: AccessLog, structName: string): Table[string, int] =
  ## Counts how many times each field of `structName` appears in `log`.
  for entry in log:
    if entry.structName != structName: continue
    result[entry.fieldName] = result.getOrDefault(entry.fieldName, 0) + 1

proc classifyHotCold(freqs: Table[string, int],
                     threshold: int): tuple[hot, cold: seq[string]] =
  ## Splits fields into hot (>= `threshold` accesses) and cold sets.
  for f, c in freqs:
    if c >= threshold: result.hot.add(f)
    else: result.cold.add(f)

proc clusterFields(fields: seq[string],
                   co: Table[(string, string), int],
                   coThreshold: int): Table[string, ClusterId] =
  ## Greedy single-linkage clustering: seeds each unclustered field as a new
  ## cluster and pulls in any co-accessed peer above `coThreshold`. The result
  ## maps each field to its assigned `ClusterId`.
  var nextCluster = 0
  for f in fields:
    if f in result: continue
    result[f] = ClusterId(nextCluster)
    for g in fields:
      if g == f or g in result: continue
      let key = if f < g: (f, g) else: (g, f)
      if co.getOrDefault(key, 0) >= coThreshold:
        result[g] = ClusterId(nextCluster)
    nextCluster += 1

proc pickAoSorSoA(freqs: Table[string, int],
                  hotCount: int): LayoutKind =
  ## Chooses AoS vs SoA based on access shape. SoA when there's a single
  ## dominant hot field accessed independently; AoS when the hot cluster
  ## travels together.
  if hotCount == 1: lkSoA else: lkAoS

proc buildLayout(struct: StructDef, log: AccessLog,
                 cacheLineBytes: int, hotThreshold: int,
                 coThreshold: int): StructLayout =
  ## Assembles the full `StructLayout` for one struct by running co-access
  ## clustering, hot/cold classification, AoS/SoA selection, and simple
  ## sequential offset assignment.
  let fieldNames = struct.fields.mapIt(it.name)
  let co = coAccessMatrix(log, struct.name, fieldNames)
  let freqs = accessFrequency(log, struct.name)
  let clusters = clusterFields(fieldNames, co, coThreshold)
  let (hot, cold) = classifyHotCold(freqs, hotThreshold)
  var layouts: seq[FieldLayout] = @[]
  var offset = 0
  for f in struct.fields:
    let fl = FieldLayout(field: f.name,
                         clusterId: clusters.getOrDefault(f.name, ClusterId(-1)),
                         cacheLineOffset: offset,
                         padBytes: 0)
    layouts.add(fl)
    offset += (f.bits + 7) div 8
  StructLayout(structName: struct.name,
               kind: pickAoSorSoA(freqs, hot.len),
               fields: layouts,
               hotCluster: hot,
               coldCluster: cold)

proc pickLayouts*[D: LayoutInput](dag: D, structs: seq[StructDef],
                                  log: AccessLog,
                                  cacheLineBytes: int = 64): LayoutReport =
  ## Main entry point of Step 15. Produces a layout decision per struct using
  ## observed field accesses in `log`.
  ##
  ## The `dag` parameter satisfies `LayoutInput`. Thresholds are hard-coded
  ## for now (hot >= 4 accesses, cluster >= 2 co-accesses); refine once
  ## profile-driven tuning is available. Feeds Step 17 CPU codegen.
  for s in structs:
    result[s.name] = buildLayout(s, log, cacheLineBytes, 4, 2)
