## ResolvedGeneric — the resolver's view of a generic definition: the
## parser Generic + its resolved funcDef signatures + lookup indices.
## Every funcDef inside a generic is implicitly public (per grammar),
## so no public filter on findFunctionDefs.

import results, strformat, tables, hashes, sequtils

import parser
import argtype
import function
import module

type ResolvedGeneric* = ref object
  parsed: Generic
  funcDefs: seq[ResolvedFunctionDef]
  funcDefIndex: Table[ResolvedFunctionDef, int]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDef]): Result[ResolvedGeneric, string] =
  ## Front-door: owns input-signature uniqueness for the generic's
  ## funcDefs (same rule as newResolvedModule), then computes the
  ## lookup indices.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    if funcDef in funcDefIndex:
      let prevLoc = funcDefs[funcDefIndex[funcDef]].loc
      return err(fmt"{funcDef.loc} duplicate function `{funcDef.name.asl}` with the same input signature encountered, see previous declaration at {prevLoc}")
    funcDefIndex[funcDef] = id
  ok(ResolvedGeneric(parsed: parsed, funcDefs: funcDefs, funcDefIndex: funcDefIndex, funcNameArityIndex: buildFuncNameArityIndex(funcDefs)))

proc parsed*(generic: ResolvedGeneric): Generic = generic.parsed
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDef] = generic.funcDefs
proc self*(generic: ResolvedGeneric): Generic = generic.parsed
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed.name
proc loc*(generic: ResolvedGeneric): Location = generic.parsed.loc
proc hash*(a: ResolvedGeneric): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedGeneric): bool = a.hash == b.hash

proc concrete*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDef] =
  # A generic block has one type parameter, so grounding its contract is
  # a single substitution — expressed as a one-entry map to keep the
  # engine map-based (mirrors the analyzer's `concrete`).
  var subst: ResolvedImplMap
  subst[generic.parsed] = concrete
  var concreteFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.funcDefs:
    concreteFuncDefs.add(def.concrete(subst))
  return concreteFuncDefs

proc concrete*(generic: ResolvedGeneric, concrete: ResolvedGenericArgumentType): seq[ResolvedFunctionDef] =
  generic.concrete(newResolvedArgumentType(concrete))

proc concrete*(generic: ResolvedGeneric, concrete: ResolvedModuleArgumentType): seq[ResolvedFunctionDef] =
  generic.concrete(newResolvedArgumentType(concrete))

proc findFunctionDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): ResolvedFunctionDef =
  ## Identity membership — the generic was indexed over exactly these
  ## funcDefs, so a miss is a compiler bug (mirrors the analyzed twin).
  assert(funcDef in generic.funcDefIndex, fmt"[BUG] - {funcDef.loc} function `{funcDef.name.asl}` missing from generic `{generic.name.asl}`")
  generic.funcDefs[generic.funcDefIndex[funcDef]]

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
