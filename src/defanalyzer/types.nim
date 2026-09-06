## Phase-A local-type cluster — AnalyzedDefModule and AnalyzedGeneric
## (a file's defined types) unified by the AnalyzedLocalType tagged
## union over them. Phase-B module/generic lookups go through
## `AnalyzedFileContext.findType(ResolvedLocalType)` or the local-only
## `AnalyzedDefFile.findType`; this file owns the defs, the umbrella,
## and the per-defined-type overload accessors.

import options, results, sequtils, strformat, tables, hashes

import ../tokenizer/main as tokenizer
import ../parser/main as parser
import ../resolver/main as resolver
import argtype
import datadef
import function

# ============================================================
# AnalyzedDefModule
# ============================================================
# A resolved module + its fully-analyzed requires clause, optional data
# block, and every function definition (signature only, no body).

type AnalyzedDefModule* = ref object
  resolved: ResolvedModule
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedDataDef]
  functions: seq[AnalyzedDefFunction]
  funcDefIndex: Table[ResolvedFunctionDef, int]

proc newAnalyzedDefModule*(resolved: ResolvedModule,
    requires: seq[AnalyzedGenericArgumentType],
    data: Option[AnalyzedDataDef],
    functions: seq[AnalyzedDefFunction]): AnalyzedDefModule =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, function in functions:
    assert function.def.resolved notin funcDefIndex, "[BUG] - Duplicated function definitions encountered"
    funcDefIndex[function.def.resolved] = id
  AnalyzedDefModule(resolved: resolved, requires: requires, data: data, functions: functions, funcDefIndex: funcDefIndex)

proc public*(m: AnalyzedDefModule): bool = m.resolved.public
proc resolved*(m: AnalyzedDefModule): ResolvedModule = m.resolved
proc functions*(m: AnalyzedDefModule): seq[AnalyzedDefFunction] = m.functions
proc requires*(m: AnalyzedDefModule): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedDefModule): Option[AnalyzedDataDef] = m.data
  ## The module's generic slots in canonical order — the full set an
  ## initializer's impl map must cover, defaulting any slot a variant
  ## did not touch to itself (free).

proc dataOrFail*(m: AnalyzedDefModule): AnalyzedDataDef =
  ## Kind-asserted projection — phase B reaches a module through an
  ## expression type only after the resolver verified it is a data
  ## module. The block-kind asserts live on AnalyzedDataDef's accessors.
  assert(m.data.isSome, fmt"[BUG] - {m.resolved.loc} module `{m.resolved.name.asl}` has no data block")
  m.data.get
proc funcDefs*(m: AnalyzedDefModule): seq[AnalyzedFunctionDef] = m.functions.mapIt(it.def)
proc name*(m: AnalyzedDefModule): Identifier = m.resolved.name
proc loc*(m: AnalyzedDefModule): Location = m.resolved.loc
proc hash*(m: AnalyzedDefModule): Hash = m.resolved.hash
proc `==`*(a, b: AnalyzedDefModule): bool = a.hash == b.hash

proc findFunctionDef*(module: AnalyzedDefModule, funcDef: ResolvedFunctionDef): AnalyzedFunctionDef =
  ## Identity lookup — phase A indexed every resolver function
  ## definition of this module, so a miss is a compiler bug.
  assert(funcDef in module.funcDefIndex, fmt"[BUG] - {funcDef.loc} function `{funcDef.name.asl}` missing from module `{module.name.asl}`")
  module.functions[module.funcDefIndex[funcDef]].def

proc findFunctionDefs*(module: AnalyzedDefModule, name: Identifier, arity: int, access: FunctionAccess): Result[seq[AnalyzedFunctionDef], string] =
  ## Overload-lookup entry point. The name/arity/visibility rules are
  ## the resolver twin's, so delegate to it (single source of truth)
  ## and map each surviving ResolvedFunctionDef back to its analyzed
  ## def by identity. Uniqueness is left to the caller's overload step.
  let resolvedDefs = ? module.resolved.findFunctionDefs(name, arity, access)
  ok(resolvedDefs.mapIt(module.findFunctionDef(it)))

# ============================================================
# AnalyzedGeneric
# ============================================================
# A resolved generic + every funcDef signature fully analyzed. Generic
# funcDefs are implicitly public (a generic block is an interface
# declaration), so findFunctionDefs has no `public` parameter.

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

# ============================================================
# AnalyzedLocalType (module | generic)
# ============================================================

type
  AnalyzedLocalTypeKind* = enum
    altkModule, altkGeneric
  AnalyzedLocalType* = ref object
    case kind: AnalyzedLocalTypeKind
    of altkModule: module: AnalyzedDefModule
    of altkGeneric: generic: AnalyzedGeneric

proc newAnalyzedLocalType*(module: AnalyzedDefModule): AnalyzedLocalType =
  AnalyzedLocalType(kind: altkModule, module: module)

proc newAnalyzedLocalType*(generic: AnalyzedGeneric): AnalyzedLocalType =
  AnalyzedLocalType(kind: altkGeneric, generic: generic)

proc kind*(d: AnalyzedLocalType): AnalyzedLocalTypeKind = d.kind
proc module*(d: AnalyzedLocalType): AnalyzedDefModule =
  assert d.kind == altkModule,
    fmt"AnalyzedLocalType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedLocalType): AnalyzedGeneric =
  assert d.kind == altkGeneric,
    fmt"AnalyzedLocalType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedLocalType): Identifier =
  case d.kind:
  of altkModule: d.module.name
  of altkGeneric: d.generic.name
proc loc*(d: AnalyzedLocalType): Location =
  case d.kind:
  of altkModule: d.module.loc
  of altkGeneric: d.generic.loc

proc resolved*(definedType: AnalyzedLocalType): ResolvedLocalType =
  case definedType.kind:
  of altkModule: newResolvedLocalType(definedType.module.resolved)
  of altkGeneric: newResolvedLocalType(definedType.generic.resolved)

proc findFunctionDefs*(definedType: AnalyzedLocalType, name: Identifier, arity: int, access: FunctionAccess): Result[seq[AnalyzedFunctionDef], string] =
  ## Uniform overload lookup regardless of definedType.kind. `access`
  ## is honored by modules and ignored by generics (their funcDefs
  ## are implicitly public — a generic block is an interface
  ## declaration).
  case definedType.kind:
  of altkModule: definedType.module.findFunctionDefs(name, arity, access)
  of altkGeneric: definedType.generic.findFunctionDefs(name, arity)
