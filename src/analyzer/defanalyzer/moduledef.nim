## Phase-A `AnalyzedDefModule` — a resolved module + its
## fully-analyzed requires clause, optional data block, and every
## function definition (signature only, no body). Phase B looks up
## call targets against `findFunctionDefs` / `findFunctionDef` on
## this type — no signature re-analysis per call site.
##
## `requires` is derived from the data block (post the resolver's
## struct-header-requires merge). Modules without a data block carry
## an empty requires seq.

import options, results, sequtils, strformat, tables

import ./resolver
import ./genericargtype
import ./datadef
import ./function

# ---- AnalyzedDefModule ----

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

proc resolved*(m: AnalyzedDefModule): ResolvedModule = m.resolved
proc functions*(m: AnalyzedDefModule): seq[AnalyzedDefFunction] = m.functions
proc requires*(m: AnalyzedDefModule): seq[AnalyzedGenericArgumentType] = m.requires
  ## The module's generic slots in canonical order — the full set an
  ## initializer's impl map must cover, defaulting any slot a variant
  ## did not touch to itself (free).

proc dataDef*(m: AnalyzedDefModule): AnalyzedDataDef =
  ## Kind-asserted projection — phase B reaches a module through an
  ## expression type only after the resolver verified it is a data
  ## module. The block-kind asserts live on AnalyzedDataDef's accessors.
  assert(m.data.isSome, fmt"[BUG] - {m.resolved.loc} module `{m.resolved.name.asl}` has no data block")
  m.data.get
proc funcDefs*(m: AnalyzedDefModule): seq[AnalyzedFunctionDef] = m.functions.mapIt(it.def)
proc name*(m: AnalyzedDefModule): Identifier = m.resolved.name
proc loc*(m: AnalyzedDefModule): Location = m.resolved.loc

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

