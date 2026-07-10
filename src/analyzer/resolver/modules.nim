## Module + Generic + Type — top of the resolver's dependency chain.
## Reads argument types, data blocks, and functions from earlier
## layers; `ResolvedType` is the file-scope umbrella over module +
## generic.

import results, strformat, strutils, options, tables, hashes, sequtils, sets

import ./parser
import argtypes
import funcdefs
import data
import funcs

type
  ResolvedModule* = ref object
    parsed: Module
    requires: seq[ResolvedGenericArgumentType]
    data: Option[ResolvedData]
    funcDefIndex: Table[ResolvedFunctionDef, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
    functions: seq[ResolvedFunction]

  ResolvedGeneric* = ref object
    parsed: Generic
    funcDefs: seq[ResolvedFunctionDef]
    funcDefIndex: Table[ResolvedFunctionDef, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

  # ==== Type umbrella ====

  ResolvedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedType* = ref object
    id: int
    case kind: ResolvedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

# =====================================================================
# Module + Generic
# =====================================================================

# ---- Module: raw ctor + front-door ----

proc newResolvedModuleInternal(parsed: Module,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    funcDefIndex: Table[ResolvedFunctionDef, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]],
    functions: seq[ResolvedFunction]): ResolvedModule =
  ## Raw constructor used by the front-door `newResolvedModule`, which
  ## computes the two indices from the function list.
  ResolvedModule(parsed: parsed, requires: requires, data: data,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex,
    functions: functions)

proc buildFuncNameArityIndex(funcDefs: seq[ResolvedFunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  ## Positions of function definitions indexed by name then arity —
  ## drives overload lookup at call sites. Used by both ResolvedModule
  ## and ResolvedGeneric (see below).
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

# ---- ResolvedModule front-door constructor + helpers ----

proc newResolvedModule*(parsed: Module, requires: seq[ResolvedGenericArgumentType], data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ## Front-door: compute the funcDef/funcNameArity indices from the
  ## resolved functions and construct the ResolvedModule. Used by
  ## `resolveModule` and by tests that construct modules directly.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  var funcDefs: seq[ResolvedFunctionDef]
  for id, function in functions:
    assert(function.def notin funcDefIndex, fmt"NOTE: should be unreachable {function.def.asl}")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)
  newResolvedModuleInternal(parsed, requires, data, funcDefIndex,
    buildFuncNameArityIndex(funcDefs), functions)

proc parsed*(module: ResolvedModule): Module = module.parsed
proc requires*(module: ResolvedModule): seq[ResolvedGenericArgumentType] = module.requires
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc funcDefIndex*(module: ResolvedModule): Table[ResolvedFunctionDef, int] = module.funcDefIndex
proc funcNameArityIndex*(module: ResolvedModule): Table[Identifier, Table[int, seq[int]]] = module.funcNameArityIndex
proc name*(module: ResolvedModule): Identifier = module.parsed.name
proc loc*(module: ResolvedModule): Location = module.parsed.loc
proc self*(module: ResolvedModule): ResolvedModuleArgumentType =
  var impls: seq[ResolvedArgumentType]
  for generic in module.requires:
    let argType = newResolvedArgumentType(generic)
    impls.add(argType)
  newResolvedModuleArgumentType(module.parsed, impls, newLocation())

proc hash*(a: ResolvedModule): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedModule): bool = a.hash == b.hash

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin module.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(module.functions[module.funcDefIndex[funcDef]].def)

proc findFunctionDefs*(module: ResolvedModule, name: Identifier, arity: int, public: bool): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup entry point — returns every function definition
  ## that matches `name` + `arity`, optionally filtered to `public` only
  ## (for external-call receivers). Uniqueness is left to the caller's
  ## overload-selection step (see analyzer/body.nim's analyzeFunctionCall).
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.functions[it].def)
    ok(if public: funcDefs.filterIt(it.public) else: funcDefs)

proc validateRequiresConstraints(module: Module): Result[void, string] =
  ## Enforces the two structural requires-block constraints:
  ##   1. Generic names inside `requires(...)` must be unique.
  ##   2. `requires` pairs with a `struct` data block — not literal, not union,
  ##      not absent. The no-generic-fields constraint is enforced
  ##      post-resolution.
  ##
  ## `requires` is an internal feature — undocumented and not promoted to
  ## end users — but no name whitelist is enforced here: any module that
  ## declares `requires` and satisfies these structural rules is accepted,
  ## so future internal types (List, dynamic containers, etc.) can adopt
  ## the same phantom-type machinery without editing this proc.
  if module.requires.isNone: return ok()
  let requires = module.requires.get
  var seen: HashSet[Identifier]
  for generic in requires.generics:
    if generic in seen:
      return err(fmt"{generic.loc} duplicate generic `{generic.asl}` in requires block")
    seen.incl(generic)
  if module.data.isNone:
    return err(fmt"{requires.loc} module `{module.name.asl}` declares requires but has no data block; requires must pair with a struct")
  case module.data.get.kind:
  of ddkStruct: ok()
  of ddkLiteral, ddkUnion:
    err(fmt"{module.data.get.loc} module `{module.name.asl}` declares requires but data block is not a struct")

proc resolveModule*(app: App, file: parser.File,
    fileScope: FileScope, module: Module): Result[ResolvedModule, string] =
  ## Resolve every part of the parser Module and construct the
  ## `ResolvedModule` in one pass. Argument types along the way carry
  ## parser `Module` back-refs, so there's no need for a two-pass
  ## shell/populate structure.
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  ? validateRequiresConstraints(module)

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let typ = ? file.findType(fileScope, generic)
      case typ.kind:
      of tkModule:
        return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
      of tkGeneric:
        resolvedRequires.add(newResolvedGenericArgumentType(typ.generic, generic.loc))

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataDef = ? resolveDataDef(app, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataDef)

  # NOTE: Infer requires list if not explicitly mentioned.
  if module.requires.isNone and resolvedData.isSome:
    resolvedRequires = resolvedData.get.requires

  # Constraint 3b (post-resolution): when requires is declared, the struct
  # block cannot have any generic fields — phantom types live in the
  # signature, not the data.
  if module.requires.isSome and resolvedData.isSome:
    let structRequires = resolvedData.get.struct.requires
    if structRequires.len > 0:
      let firstGeneric = structRequires[0]
      return err(fmt"{firstGeneric.loc} module `{module.name.asl}` declares requires but struct field is typed as a generic — phantom struct cannot have generic fields")

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module,
      function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(module, resolvedRequires, resolvedData,
    resolvedFunctions))

# ---- ResolvedGeneric: raw ctor + front-door ----

proc newResolvedGenericInternal(parsed: Generic,
    funcDefs: seq[ResolvedFunctionDef],
    funcDefIndex: Table[ResolvedFunctionDef, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]): ResolvedGeneric =
  ## Raw constructor used by the front-door `newResolvedGeneric`, which
  ## computes the two indices from the funcDef list.
  ResolvedGeneric(parsed: parsed, funcDefs: funcDefs,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex)

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDef]): ResolvedGeneric =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    assert(funcDef notin funcDefIndex, "UNREACHABLE: generic resolution broke due to duplicated function definition")
    funcDefIndex[funcDef] = id
  newResolvedGenericInternal(parsed, funcDefs, funcDefIndex,
    buildFuncNameArityIndex(funcDefs))

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

proc concreteImpls*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDef] =
  var concreteFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.funcDefs:
    concreteFuncDefs.add(def.concreteFunctionDef(concrete, generic.parsed))
  return concreteFuncDefs

proc findFunctionDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin generic.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(generic.funcDefs[generic.funcDefIndex[funcDef]])

proc findFunctionDefs*(generic: ResolvedGeneric, name: Identifier, arity: int): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup for generic funcDefs — every funcDef inside a
  ## generic is implicitly public (per grammar), so no public filter.
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it]))

proc resolveGeneric*(app: App, file: parser.File, fileScope: FileScope, generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDef]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope, generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDef)

  ok(newResolvedGeneric(generic, resolvedFunctionDefs))

# =====================================================================
# Type umbrella
# =====================================================================

proc newResolvedType*(id: int, module: ResolvedModule): ResolvedType =
  ResolvedType(id: id, kind: rdtkModule, module: module)

proc newResolvedType*(id: int, generic: ResolvedGeneric): ResolvedType =
  ResolvedType(id: id, kind: rdtkGeneric, generic: generic)

proc kind*(typ: ResolvedType): ResolvedTypeKind = typ.kind
proc module*(typ: ResolvedType): ResolvedModule =
  assert typ.kind == rdtkModule,
    fmt"ResolvedType.module accessed but kind is {typ.kind}"
  typ.module
proc generic*(typ: ResolvedType): ResolvedGeneric =
  assert typ.kind == rdtkGeneric,
    fmt"ResolvedType.generic accessed but kind is {typ.kind}"
  typ.generic

proc name*(typ: ResolvedType): Identifier =
  case typ.kind:
  of rdtkModule: typ.module.name
  of rdtkGeneric: typ.generic.name

proc loc*(typ: ResolvedType): Location =
  case typ.kind:
  of rdtkModule: typ.module.loc
  of rdtkGeneric: typ.generic.loc

proc resolveType*(app: App, file: parser.File, fileScope: FileScope, id: int, typ: Type): Result[ResolvedType, string] =
  case typ.kind:
  of tkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, fileScope, typ.generic)
    ok(newResolvedType(id, resolvedGeneric))
  of tkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, typ.module)
    ok(newResolvedType(id, resolvedModule))
