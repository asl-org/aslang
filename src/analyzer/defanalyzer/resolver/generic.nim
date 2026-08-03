## ResolvedGeneric — the resolver's view of a generic definition: the
## parser Generic + its resolved funcDef signatures + lookup indices.
## Every funcDef inside a generic is implicitly public (per grammar),
## so no public filter on findFunctionDefs.

import results, strformat, options, tables, hashes, sequtils

import ./parser
import argtype
import funcdef
import module  # buildFuncNameArityIndex

type ResolvedGeneric* = ref object
  parsed: Generic
  funcDefs: seq[ResolvedFunctionDef]
  funcDefIndex: Table[ResolvedFunctionDef, int]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDef]): ResolvedGeneric =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    assert(funcDef notin funcDefIndex, fmt"[BUG] - Resolver rejects duplicate input signatures ({funcDef.asl})")
    funcDefIndex[funcDef] = id
  ResolvedGeneric(parsed: parsed, funcDefs: funcDefs, funcDefIndex: funcDefIndex, funcNameArityIndex: buildFuncNameArityIndex(funcDefs))

proc parsed*(generic: ResolvedGeneric): Generic = generic.parsed
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDef] = generic.funcDefs
proc funcDefIndex*(generic: ResolvedGeneric): Table[ResolvedFunctionDef, int] = generic.funcDefIndex
proc funcNameArityIndex*(generic: ResolvedGeneric): Table[Identifier, Table[int, seq[int]]] = generic.funcNameArityIndex
proc self*(generic: ResolvedGeneric): Generic = generic.parsed
proc public*(generic: ResolvedGeneric): bool = generic.parsed.public
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed.name
proc loc*(generic: ResolvedGeneric): Location = generic.parsed.loc
proc hash*(a: ResolvedGeneric): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedGeneric): bool = a.hash == b.hash

proc concrete*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDef] =
  var concreteFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.funcDefs:
    let concreteDef = def.concrete(concrete, generic.parsed)
    concreteFuncDefs.add(concreteDef)
  return concreteFuncDefs

proc findFunctionDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin generic.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(generic.funcDefs[generic.funcDefIndex[funcDef]])

proc findImplDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDef, access: FunctionAccess): Result[ResolvedFunctionDef, string] =
  ## Does the generic declare exactly this signature, visible at
  ## `access`? Identity (hash) covers name + input types only — the
  ## probe's return type is checked explicitly on top of the index
  ## hit.
  if funcDef notin generic.funcDefIndex:
    err(fmt"{funcDef.loc} generic `{generic.name.asl}` does not have a function named `{funcDef.name.asl}` with arity `{funcDef.arity}`")
  else:
    let def = generic.funcDefs[generic.funcDefIndex[funcDef]]
    if def.returns != funcDef.returns:
      err(fmt"{def.loc} function `{def.name.asl}` of generic `{generic.name.asl}` returns `{def.returns.asl}` but `{funcDef.returns.asl}` is required")
    else:
      case access:
      of faAll: ok(def)
      of faPublic:
        if def.public: ok(def)
        else: err(fmt"{def.loc} function `{def.name.asl}` of generic `{generic.name.asl}` is not public")

proc findFunctionDefs*(generic: ResolvedGeneric, name: Identifier, arity: int): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup for generic funcDefs — every funcDef inside a
  ## generic is implicitly public (per grammar), so no public filter.
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it]))
