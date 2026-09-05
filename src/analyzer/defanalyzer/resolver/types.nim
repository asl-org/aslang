## Resolved local-type cluster — a file's declared types: ResolvedModule
## and ResolvedGeneric, unified by the ResolvedLocalType tagged union.
## The module/generic defs and the umbrella over them live together
## since the umbrella dispatches to both and generic reuses the module's
## name+arity indexer.

import results, strformat, options, tables, hashes, sequtils

import ../parser/index as parser
import argtype
import datadef
import function

# ============================================================
# ResolvedModule
# ============================================================
# The resolver's view of a module: parser module + optional resolved
# data block + the module's fully-resolved function set with indices.

type ResolvedModule* = ref object
  parsed: Module
  data: Option[ResolvedDataDef]
  funcDefIndex: Table[ResolvedFunctionDef, int]
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  functions: seq[ResolvedFunction]

# ---- shared name+arity indexer (reused by ResolvedGeneric below) ----

proc buildFuncNameArityIndex*(funcDefs: seq[ResolvedFunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  ## Positions of function definitions indexed by name then arity —
  ## drives overload lookup at call sites.
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

proc public*(module: ResolvedModule): bool = module.parsed.public
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

# ============================================================
# ResolvedGeneric
# ============================================================
# The resolver's view of a generic definition: parser Generic + its
# resolved funcDef signatures + lookup indices. Every funcDef inside a
# generic is implicitly public (per grammar), so no public filter.

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

proc public*(generic: ResolvedGeneric): bool = generic.parsed.public
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

# ============================================================
# ResolvedLocalType
# ============================================================
# File-scope umbrella over ResolvedModule + ResolvedGeneric.

type
  ResolvedLocalTypeKind* = enum
    rltkModule, rltkGeneric
  ResolvedLocalType* = ref object
    case kind: ResolvedLocalTypeKind
    of rltkModule: module: ResolvedModule
    of rltkGeneric: generic: ResolvedGeneric

proc newResolvedLocalType*(module: ResolvedModule): ResolvedLocalType =
  ResolvedLocalType(kind: rltkModule, module: module)

proc newResolvedLocalType*(generic: ResolvedGeneric): ResolvedLocalType =
  ResolvedLocalType(kind: rltkGeneric, generic: generic)

proc kind*(typ: ResolvedLocalType): ResolvedLocalTypeKind = typ.kind
proc module*(typ: ResolvedLocalType): ResolvedModule =
  assert typ.kind == rltkModule,
    fmt"ResolvedLocalType.module accessed but kind is {typ.kind}"
  typ.module
proc generic*(typ: ResolvedLocalType): ResolvedGeneric =
  assert typ.kind == rltkGeneric,
    fmt"ResolvedLocalType.generic accessed but kind is {typ.kind}"
  typ.generic

proc public*(typ: ResolvedLocalType): bool =
  case typ.kind:
  of rltkModule: typ.module.public
  of rltkGeneric: typ.generic.public

proc name*(typ: ResolvedLocalType): Identifier =
  case typ.kind:
  of rltkModule: typ.module.name
  of rltkGeneric: typ.generic.name

proc loc*(typ: ResolvedLocalType): Location =
  case typ.kind:
  of rltkModule: typ.module.loc
  of rltkGeneric: typ.generic.loc

proc parsed*(typ: ResolvedLocalType): parser.LocalType =
  ## Underlying parser LocalType for identity-keyed scope lookups. See
  ## plans/plan_identity_based_lookups.md — scope tables downstream
  ## of name resolution key on `parser.LocalType` (hash-by-loc), not on
  ## `Identifier` (hash-by-string).
  case typ.kind:
  of rltkModule: newLocalType(typ.module.parsed)
  of rltkGeneric: newLocalType(typ.generic.parsed)

proc hash*(typ: ResolvedLocalType): Hash =
  case typ.kind:
  of rltkModule: typ.module.hash
  of rltkGeneric: typ.generic.hash

proc `==`*(a, b: ResolvedLocalType): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of rltkModule: a.module == b.module
    of rltkGeneric: a.generic == b.generic
