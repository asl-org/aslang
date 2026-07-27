## Phase-A `AnalyzedModuleDefinition` — a resolved module + its
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
import ./argtype
import ./funcdef
import ./datadef

# ---- shared name+arity indexer over analyzed funcDefs ----

proc buildAnalyzedFuncNameArityIndex*(funcDefs: seq[AnalyzedFunctionDefinition]): Table[Identifier, Table[int, seq[int]]] =
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

# ---- AnalyzedModuleDefinition ----

type AnalyzedModuleDefinition* = ref object
  resolved: ResolvedModule
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedData]
  funcDefs: seq[AnalyzedFunctionDefinition]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[ResolvedFunctionDef, int]

proc newAnalyzedModuleDefinition*(resolved: ResolvedModule,
    requires: seq[AnalyzedGenericArgumentType],
    data: Option[AnalyzedData],
    funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedModuleDefinition =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    assert funcDef.resolved notin funcDefIndex, "[BUG] - Duplicated function definitions encountered"
    funcDefIndex[funcDef.resolved] = id
  AnalyzedModuleDefinition(resolved: resolved, requires: requires,
    data: data, funcDefs: funcDefs,
    funcNameArityIndex: buildAnalyzedFuncNameArityIndex(funcDefs),
    funcDefIndex: funcDefIndex)

proc resolved*(m: AnalyzedModuleDefinition): ResolvedModule = m.resolved
proc requires*(m: AnalyzedModuleDefinition): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedModuleDefinition): Option[AnalyzedData] = m.data
proc funcDefs*(m: AnalyzedModuleDefinition): seq[AnalyzedFunctionDefinition] = m.funcDefs
proc name*(m: AnalyzedModuleDefinition): Identifier = m.resolved.name
proc loc*(m: AnalyzedModuleDefinition): Location = m.resolved.loc

proc findFunctionDef*(module: AnalyzedModuleDefinition, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  if funcDef notin module.funcDefIndex:
    err(fmt"{funcDef.loc} module `{module.name.asl}` does not have a function with name `{funcDef.name.asl}`")
  else:
    ok(module.funcDefs[module.funcDefIndex[funcDef]])

proc findFunctionDefs*(module: AnalyzedModuleDefinition, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  ## Overload-lookup entry point — returns every AnalyzedFunctionDefinition
  ## that matches `name` + `arity`, optionally filtered to `public` only
  ## (for external-call receivers). Uniqueness is left to the caller's
  ## overload-selection step.
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.funcDefs[it])
    ok(if public: funcDefs.filterIt(it.public) else: funcDefs)
