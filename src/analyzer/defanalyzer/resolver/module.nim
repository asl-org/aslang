## ResolvedModule — the resolver's view of a module: parser module +
## required generic-arg impls + optional resolved data block + the
## module's fully-resolved function set with lookup indices.

import results, strformat, options, tables, hashes, sequtils

import ./parser
import argtype
import datadef
import function

type ResolvedModule* = ref object
  parsed: Module
  data: Option[ResolvedDataDef]
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

proc validatePublicRequires(parsed: Module, data: ResolvedDataDef): Result[void, string] =
  ## A public module's require slots are part of its public
  ## interface. A non-public generic there is broken-by-construction
  ## for every importer — the importing file must have the constraint
  ## generic in scope to use the module, and a private generic cannot
  ## be imported. Rejected here, at the definition, instead of
  ## surfacing as a missing-type mystery in every consumer.
  for requirement in data.requires:
    if not requirement.generic.public:
      return err(fmt"{requirement.loc} public module `{parsed.name.asl}` requires non-public generic `{requirement.generic.name.asl}` — a generic named in a public module's type parameters must be public")
  ok()

proc newResolvedModule*(parsed: Module, data: Option[ResolvedDataDef], functions: seq[ResolvedFunction]): Result[ResolvedModule, string] =
  ## Front-door: owns the module's construction invariants —
  ## input-signature uniqueness (two functions may not share name +
  ## input types; ResolvedFunctionDef hashes by exactly that, returns
  ## deliberately excluded since call sites could never disambiguate)
  ## and the public-interface rule (validatePublicRequires) — then
  ## computes the funcDef/funcNameArity indices.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  var funcDefs: seq[ResolvedFunctionDef]
  for id, function in functions:
    if function.def in funcDefIndex:
      let prevLoc = funcDefs[funcDefIndex[function.def]].loc
      return err(fmt"{function.def.loc} duplicate function `{function.def.name.asl}` with the same input signature encountered, see previous declaration at {prevLoc}")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)

  if parsed.public and data.isSome:
    ? validatePublicRequires(parsed, data.get)

  ok(ResolvedModule(parsed: parsed, data: data, funcDefIndex: funcDefIndex, funcNameArityIndex: buildFuncNameArityIndex(funcDefs), functions: functions))

proc parsed*(module: ResolvedModule): Module = module.parsed
proc data*(module: ResolvedModule): Option[ResolvedDataDef] = module.data

# Kind-asserted data projections — callers reach a module through an
# argument type, ref, or literal binding only after the resolver
# verified it is a data module (of the right kind), so absence is a
# compiler bug. The block-kind asserts live on ResolvedDataDef's own
# accessors.
proc dataDef*(module: ResolvedModule): ResolvedDataDef =
  assert(module.data.isSome, fmt"[BUG] - {module.parsed.loc} module `{module.parsed.name.asl}` has no data block")
  module.data.get

proc structDef*(module: ResolvedModule): ResolvedStructDef = module.dataDef.struct
proc unionDef*(module: ResolvedModule): ResolvedUnionDef = module.dataDef.union
proc literalDef*(module: ResolvedModule): ResolvedLiteralDef = module.dataDef.literal
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
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

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDef): ResolvedFunctionDef =
  ## Identity membership — the module was indexed over exactly these
  ## funcDefs, so a miss is a compiler bug (mirrors the analyzed twin).
  assert(funcDef in module.funcDefIndex, fmt"[BUG] - {funcDef.loc} function `{funcDef.name.asl}` missing from module `{module.name.asl}`")
  module.functions[module.funcDefIndex[funcDef]].def

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
