## ResolvedModule — the resolver's view of a module: parser module +
## required generic-arg impls + optional resolved data block + the
## module's fully-resolved function set with lookup indices.

import results, strformat, options, tables, hashes, sequtils

import ./parser
import argtype
import funcdef
import datadef
import function

type ResolvedModule* = ref object
  parsed: Module
  data: Option[ResolvedData]
  funcDefIndex: Table[ResolvedFunctionDef, int]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  functions: seq[ResolvedFunction]

# ---- shared name+arity indexer ----

proc buildFuncNameArityIndex*(funcDefs: seq[ResolvedFunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  ## Positions of function definitions indexed by name then arity —
  ## drives overload lookup at call sites. Also used by ResolvedGeneric
  ## (see ./generic).
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

proc newResolvedModule*(parsed: Module, data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ## Front-door: compute the funcDef/funcNameArity indices from the
  ## resolved functions and construct the ResolvedModule. Used by
  ## `resolveModule` and by tests that construct modules directly.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  var funcDefs: seq[ResolvedFunctionDef]
  for id, function in functions:
    assert(function.def notin funcDefIndex, fmt"[BUG] - Resolver rejects duplicate input signatures ({function.def.asl})")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)
  ResolvedModule(parsed: parsed, data: data, funcDefIndex: funcDefIndex, funcNameArityIndex: buildFuncNameArityIndex(funcDefs), functions: functions)

proc parsed*(module: ResolvedModule): Module = module.parsed
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc funcDefIndex*(module: ResolvedModule): Table[ResolvedFunctionDef, int] = module.funcDefIndex
proc funcNameArityIndex*(module: ResolvedModule): Table[Identifier, Table[int, seq[int]]] = module.funcNameArityIndex
proc name*(module: ResolvedModule): Identifier = module.parsed.name
proc loc*(module: ResolvedModule): Location = module.parsed.loc
proc self*(module: ResolvedModule): ResolvedModuleArgumentType =
  if module.data.isNone:
    newResolvedModuleArgumentType(module.parsed, newLocation())
  else:
    var impls: seq[ResolvedArgumentType]
    for generic in module.data.get.requires:
      impls.add(newResolvedArgumentType(generic))
    newResolvedModuleArgumentType(module.parsed, impls, newLocation())

proc hash*(a: ResolvedModule): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedModule): bool = a.hash == b.hash

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin module.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(module.functions[module.funcDefIndex[funcDef]].def)

proc findImplDef*(module: ResolvedModule, funcDef: ResolvedFunctionDef, access: FunctionAccess): Result[ResolvedFunctionDef, string] =
  ## Does the module provide exactly this signature, visible at
  ## `access`? Identity (hash) covers name + input types only — the
  ## uniqueness rule — so the probe's return type is checked
  ## explicitly on top of the index hit.
  if funcDef notin module.funcDefIndex:
    err(fmt"{funcDef.loc} module `{module.name.asl}` does not have a function named `{funcDef.name.asl}` with arity `{funcDef.arity}`")
  else:
    let def = module.functions[module.funcDefIndex[funcDef]].def
    if def.returns != funcDef.returns:
      err(fmt"{def.loc} function `{def.name.asl}` of module `{module.name.asl}` returns `{def.returns.asl}` but `{funcDef.returns.asl}` is required")
    else:
      case access:
      of faAll: ok(def)
      of faPublic:
        if def.public: ok(def)
        else: err(fmt"{def.loc} function `{def.name.asl}` of module `{module.name.asl}` is not public")

proc findFunctionDefs*(module: ResolvedModule, name: Identifier, arity: int, access: FunctionAccess): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup entry point — returns every function definition
  ## that matches `name` + `arity`, filtered to what `access` may see
  ## (`faPublic` for external-call receivers). Uniqueness is left to
  ## the caller's overload-selection step (see `analyzeFunctionCall`
  ## on the analyzer facade).
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.functions[it].def)
    case access:
    of faAll: ok(funcDefs)
    of faPublic:
      let publicDefs = funcDefs.filterIt(it.public)
      if publicDefs.len == 0:
        err(fmt"{name.loc} function `{name.asl}` of module `{module.name.asl}` is not public")
      else:
        ok(publicDefs)
