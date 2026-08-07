## Phase-A `AnalyzedGeneric` — a resolved generic + every funcDef
## signature fully analyzed. Generics have no data block; a generic
## block declares only signatures.
##
## Note: generic function defs are treated as implicitly public
## (a generic's whole point is to declare an interface for external
## callers) — `findFunctionDefs` has no `public` parameter.

import results, sequtils, strformat, tables, hashes

import ./resolver
import ./funcdef
import ./moduledef  # buildAnalyzedFuncNameArityIndex

type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDef]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric,
    funcDefs: seq[AnalyzedFunctionDef]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs,
    funcNameArityIndex: buildAnalyzedFuncNameArityIndex(funcDefs))

proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc loc*(g: AnalyzedGeneric): Location = g.resolved.loc

# Identity is the underlying resolved generic — so an AnalyzedGeneric
# keys a GenericImplMap by the same identity a ResolvedGeneric would.
proc hash*(g: AnalyzedGeneric): Hash = g.resolved.hash
proc `==`*(a, b: AnalyzedGeneric): bool = a.resolved == b.resolved

proc findFunctionDefs*(generic: AnalyzedGeneric, name: Identifier, arity: int): Result[seq[AnalyzedFunctionDef], string] =
  ## No public filter — every generic funcDef is implicitly public.
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it]))
