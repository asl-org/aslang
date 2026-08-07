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
import ./funcdef
import ./datadef
import ./function

# ---- shared name+arity indexer over analyzed funcDefs ----

proc buildAnalyzedFuncNameArityIndex*(funcDefs: seq[AnalyzedFunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

# ---- AnalyzedDefModule ----

type AnalyzedDefModule* = ref object
  resolved: ResolvedModule
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedDataDef]
  functions: seq[AnalyzedDefFunction]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[ResolvedFunctionDef, int]

proc newAnalyzedDefModule*(resolved: ResolvedModule,
    requires: seq[AnalyzedGenericArgumentType],
    data: Option[AnalyzedDataDef],
    functions: seq[AnalyzedDefFunction]): AnalyzedDefModule =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, function in functions:
    assert function.def.resolved notin funcDefIndex, "[BUG] - Duplicated function definitions encountered"
    funcDefIndex[function.def.resolved] = id
  let funcNameArityIndex = functions.mapIt(it.def).buildAnalyzedFuncNameArityIndex()
  AnalyzedDefModule(resolved: resolved, requires: requires, data: data, functions: functions, funcNameArityIndex: funcNameArityIndex, funcDefIndex: funcDefIndex)

proc resolved*(m: AnalyzedDefModule): ResolvedModule = m.resolved
proc requires*(m: AnalyzedDefModule): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedDefModule): Option[AnalyzedDataDef] = m.data
proc functions*(m: AnalyzedDefModule): seq[AnalyzedDefFunction] = m.functions

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
  ## Overload-lookup entry point — returns every AnalyzedFunctionDef
  ## that matches `name` + `arity`, filtered to what `access` may see
  ## (`faPublic` for external-call receivers). Uniqueness is left to
  ## the caller's overload-selection step.
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let defs = module.funcNameArityIndex[name][arity].mapIt(module.funcDefs[it]).filter(access)
    if defs.len > 0: ok(defs)
    else: err(fmt"{name.loc} function `{name.asl}` of module `{module.name.asl}` is not public")

