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
import ./moduledef  # buildAnalyzedFuncNameArityIndex

type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDefinition]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric,
    funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs,
    funcNameArityIndex: buildAnalyzedFuncNameArityIndex(funcDefs))

proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc funcDefs*(g: AnalyzedGeneric): seq[AnalyzedFunctionDefinition] = g.funcDefs
proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc loc*(g: AnalyzedGeneric): Location = g.resolved.loc

proc findFunctionDefs*(generic: AnalyzedGeneric, name: Identifier, arity: int): Result[seq[AnalyzedFunctionDefinition], string] =
  ## No public filter — every generic funcDef is implicitly public.
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it]))
