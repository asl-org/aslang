## Resolution of module and generic top-level blocks.
##
## The `Resolved*` types, their raw constructors, and direct-field
## accessors live in `types.nim`. This file owns the front-door
## `newResolvedModule` / `newResolvedGeneric` factories (which
## compute the funcDefIndex / funcNameArityIndex tables from the
## function list), the computed helpers, and the resolve procs.

import results, options, strformat, tables, options, hashes, sets, sequtils

import tokenizer
import parser
import types
import argtypes
import funcdefs
import data
import funcs

proc buildFuncNameArityIndex(funcDefs: seq[ResolvedFunctionDefinition]): Table[Identifier, Table[int, seq[int]]] =
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
  var funcDefIndex: Table[ResolvedFunctionDefinition, int]
  var funcDefs: seq[ResolvedFunctionDefinition]
  for id, function in functions:
    assert(function.def notin funcDefIndex, fmt"NOTE: should be unreachable {function.def.asl}")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)
  newResolvedModuleInternal(parsed, requires, data, funcDefIndex,
    buildFuncNameArityIndex(funcDefs), functions)

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

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Option[ResolvedFunctionDefinition] =
  if funcDef notin module.funcDefIndex:
    none(ResolvedFunctionDefinition)
  else:
    some(module.functions[module.funcDefIndex[funcDef]].def)

proc findFunctionDefs*(module: ResolvedModule, name: Identifier, arity: int, public: bool): Result[seq[ResolvedFunctionDefinition], string] =
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
  of dbkStruct: ok()
  of dbkLiteral, dbkUnion:
    err(fmt"{module.data.get.loc} module `{module.name.asl}` declares requires but data block is not a struct")

proc resolveModule*(app: App, file: parser.File, fileScope: FileScope,
    module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  ? validateRequiresConstraints(module)

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let definedType = ? file.findDefinedType(fileScope, generic)
      case definedType.kind:
      of dtkModule:
        return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
      of dtkGeneric:
        resolvedRequires.add(newResolvedGenericArgumentType(definedType.generic, generic.loc))

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataBlock = ? resolveDataBlock(app, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataBlock)

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

  ok(newResolvedModule(module, resolvedRequires, resolvedData, resolvedFunctions))

# ---- ResolvedGeneric front-door constructor + helpers ----

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDefinition]): ResolvedGeneric =
  var funcDefIndex: Table[ResolvedFunctionDefinition, int]
  for id, funcDef in funcDefs:
    assert(funcDef notin funcDefIndex, "UNREACHABLE: generic resolution broke due to duplicated function definition")
    funcDefIndex[funcDef] = id
  newResolvedGenericInternal(parsed, funcDefs, funcDefIndex,
    buildFuncNameArityIndex(funcDefs))

proc self*(generic: ResolvedGeneric): Generic = generic.parsed
proc public*(generic: ResolvedGeneric): bool = generic.parsed.public
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed.name
proc loc*(generic: ResolvedGeneric): Location = generic.parsed.loc
proc hash*(a: ResolvedGeneric): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedGeneric): bool = a.hash == b.hash

proc concreteImpls*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDefinition] =
  var concreteFuncDefs: seq[ResolvedFunctionDefinition]
  for def in generic.funcDefs:
    concreteFuncDefs.add(def.concreteFunctionDefinition(concrete, generic.parsed))
  return concreteFuncDefs

proc findFunctionDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDefinition): Option[ResolvedFunctionDefinition] =
  if funcDef notin generic.funcDefIndex:
    none(ResolvedFunctionDefinition)
  else:
    some(generic.funcDefs[generic.funcDefIndex[funcDef]])

proc findFunctionDefs*(generic: ResolvedGeneric, name: Identifier, arity: int): Result[seq[ResolvedFunctionDefinition], string] =
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

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file, fileScope, generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic, resolvedFunctionDefs))
