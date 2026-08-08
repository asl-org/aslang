## Phase-A `AnalyzedGeneric` — a resolved generic + every funcDef
## signature fully analyzed. Generics have no data block; a generic
## block declares only signatures.
##
## Note: generic function defs are treated as implicitly public
## (a generic's whole point is to declare an interface for external
## callers) — `findFunctionDefs` has no `public` parameter.

import results, sequtils, strformat, tables

import ./resolver
import ./funcdef

type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDef]
  funcDefIndex: Table[ResolvedFunctionDef, int]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric,
    funcDefs: seq[AnalyzedFunctionDef]): AnalyzedGeneric =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    funcDefIndex[funcDef.resolved] = id
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs, funcDefIndex: funcDefIndex)

proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc loc*(g: AnalyzedGeneric): Location = g.resolved.loc

proc findFunctionDef*(generic: AnalyzedGeneric, funcDef: ResolvedFunctionDef): AnalyzedFunctionDef =
  ## Identity lookup — phase A indexed every resolver funcDef of this
  ## generic, so a miss is a compiler bug.
  assert(funcDef in generic.funcDefIndex, fmt"[BUG] - {funcDef.loc} function `{funcDef.name.asl}` missing from generic `{generic.name.asl}`")
  generic.funcDefs[generic.funcDefIndex[funcDef]]

proc findFunctionDefs*(generic: AnalyzedGeneric, name: Identifier, arity: int): Result[seq[AnalyzedFunctionDef], string] =
  ## No public filter — every generic funcDef is implicitly public. The
  ## name/arity rules are the resolver twin's, so delegate to it and map
  ## each surviving ResolvedFunctionDef back to its analyzed def.
  let resolvedDefs = ? generic.resolved.findFunctionDefs(name, arity)
  ok(resolvedDefs.mapIt(generic.findFunctionDef(it)))
