## Parser local-type cluster — a file's declared types: Generic and
## Module (each with its header/body helpers), unified by the LocalType
## tagged union over them.

import strformat, strutils, sequtils, options, tables, results, hashes

import ../tokenizer/index as tokenizer
import error

import identifiers
import decorator
import function
import datadef

# ============================================================
# Generic
# ============================================================

proc buildNameArityIndex(defs: seq[FunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  var nameArityIndex: Table[Identifier, Table[int, seq[int]]]
  for index, def in defs:
    if def.name notin nameArityIndex:
      nameArityIndex[def.name] = initTable[int, seq[int]]()
    if def.arity notin nameArityIndex[def.name]:
      nameArityIndex[def.name][def.arity] = newSeq[int]()
    nameArityIndex[def.name][def.arity].add(index)
  return nameArityIndex

type Generic* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  defs: seq[FunctionDef]
  funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc newGeneric*(decorators: seq[Decorator], public: bool, name: Identifier, defs: seq[FunctionDef], loc: Location): Generic =
  let funcDefArityIndex = buildNameArityIndex(defs)
  Generic(decorators: decorators, public: public, name: name, defs: defs, funcDefArityIndex: funcDefArityIndex, loc: loc)

proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc public*(g: Generic): bool = g.public
proc name*(g: Generic): Identifier = g.name
proc defs*(g: Generic): seq[FunctionDef] = g.defs
proc loc*(g: Generic): Location = g.loc
proc hash*(g: Generic): Hash = g.loc.hash
proc `==`*(a, b: Generic): bool = a.hash == b.hash

proc asl*(gen: Generic, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines = gen.decorators.mapIt(fmt"{indent}{it.asl}")
  let prefix = if gen.public: "public generic" else: "generic"
  lines.add(fmt"{indent}{prefix} {asl(gen.name)}:")
  let defs = gen.defs.mapIt(fmt"{inner}{it.asl}")
  lines.add(defs)
  return lines

proc findFunctionDefs*(generic: Generic, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  if name notin generic.funcDefArityIndex:
    err(fmt"{name.loc} function `{name.asl}` does not exist in generic")
  elif arity notin generic.funcDefArityIndex[name]:
    err(fmt"{name.loc} function `{name.asl}` with arity `{arity}` does not exist in generic")
  else:
    let defIds = generic.funcDefArityIndex[name][arity]
    ok(defIds.mapIt(generic.defs[it]))

type GenericHeader* = ref object
  public: bool
  name: Identifier
  loc: Location

proc newGenericHeader*(public: bool, name: Identifier, loc: Location): GenericHeader =
  GenericHeader(public: public, name: name, loc: loc)

proc public*(header: GenericHeader): bool = header.public
proc name*(header: GenericHeader): Identifier = header.name
proc loc*(header: GenericHeader): Location = header.loc

# ============================================================
# Module
# ============================================================

proc buildNameArityIndex(funcList: FunctionList): Table[Identifier, Table[int, seq[int]]] =
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  for i, fn in funcList.functions:
    if fn.name notin functionIndex:
      functionIndex[fn.name] = initTable[int, seq[int]]()
    if fn.arity notin functionIndex[fn.name]:
      functionIndex[fn.name][fn.arity] = newSeq[int]()
    functionIndex[fn.name][fn.arity].add(i)
  return functionIndex

type Module* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  data: Option[DataDef]
  funcList: FunctionList
  functionIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc newModule*(decorators: seq[Decorator], public: bool, name: Identifier, data: Option[DataDef], funcList: FunctionList, loc: Location): Result[Module, ParserError] =
  if data.isNone and funcList.len == 0:
    let msg = "module must have at least 1 struct/union/function block"
    return err(newParserError(msg, loc))

  # NOTE: Inject `public func byte_size(): u64` in every data module
  var augumentedFuncList = funcList
  if data.isSome: augumentedFuncList = ? funcList.add(byteSizeBuiltinFunction(data.get.loc))
  let functionIndex = buildNameArityIndex(augumentedFuncList)

  ok(Module(decorators: decorators, public: public, name: name, data: data, funcList: augumentedFuncList, functionIndex: functionIndex, loc: loc))

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc data*(m: Module): Option[DataDef] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc
proc hash*(m: Module): Hash = m.loc.hash
proc `==`*(a, b: Module): bool = a.hash == b.hash

proc asl*(module: Module, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines = module.decorators.mapIt(fmt"{indent}{it.asl}")
  let prefix = if module.public: "public module" else: "module"
  lines.add(fmt"{indent}{prefix} {module.name.asl}:")
  if module.data.isSome:
    let data = module.data.get.asl(level + 1, indentWidth)
    lines.add(data)
    lines.add("")
  for i, fn in module.funcList.functions:
    if i > 0: lines.add("")
    let function = fn.asl(level + 1, indentWidth)
    lines.add(function)
  return lines

proc findFunctionDefs*(module: Module, name: Identifier, arity: int, access: FunctionAccess): Result[seq[FunctionDef], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    let defs = module.functionIndex[name][arity].mapIt(module.functions[it].def).filter(access)
    if defs.len > 0: ok(defs)
    else: err(fmt"{name.loc} function `{name.asl}` of module `{module.name.asl}` is not public")

type ModuleHeader* = ref object
  public: bool
  name: Identifier
  loc: Location

proc newModuleHeader*(public: bool, name: Identifier, loc: Location): ModuleHeader =
  ModuleHeader(public: public, name: name, loc: loc)

proc public*(header: ModuleHeader): bool = header.public
proc name*(header: ModuleHeader): Identifier = header.name
proc loc*(header: ModuleHeader): Location = header.loc

# Module body: optional data block + function list
type ModuleBody* = ref object
  data: Option[DataDef]
  funcList: FunctionList

proc newModuleBody*(data: Option[DataDef], funcList: FunctionList): ModuleBody =
  ModuleBody(data: data, funcList: funcList)

proc data*(body: ModuleBody): Option[DataDef] = body.data
proc funcList*(body: ModuleBody): FunctionList = body.funcList

# ============================================================
# LocalType (module | generic)
# ============================================================

type
  LocalTypeKind* = enum
    ltkModule, ltkGeneric
  LocalType* = ref object
    case kind: LocalTypeKind
    of ltkModule: module: Module
    of ltkGeneric: generic: Generic

proc newLocalType*(module: Module): LocalType =
  LocalType(kind: ltkModule, module: module)

proc newLocalType*(generic: Generic): LocalType =
  LocalType(kind: ltkGeneric, generic: generic)

proc kind*(localType: LocalType): LocalTypeKind = localType.kind
proc public*(localType: LocalType): bool =
  case localType.kind:
  of ltkModule: localType.module.public
  of ltkGeneric: localType.generic.public

proc module*(localType: LocalType): Module =
  assert localType.kind == ltkModule,
    fmt"LocalType.module accessed but kind is {localType.kind}"
  localType.module

proc generic*(localType: LocalType): Generic =
  assert localType.kind == ltkGeneric,
    fmt"LocalType.generic accessed but kind is {localType.kind}"
  localType.generic

proc access*(localType: LocalType, context: LocalType): FunctionAccess =
  ## Which functions of `module` a reference inside `context`'s enclosing
  ## definition may see: a module sees its own private functions
  ## (faAll), everything else sees only public.
  case localType.kind:
  of ltkModule:
    case context.kind:
    of ltkModule: (if context.module == localType.module: faAll else: faPublic)
    of ltkGeneric: faPublic
  of ltkGeneric: faAll

proc name*(typ: LocalType): Identifier =
  case typ.kind:
  of ltkModule: typ.module.name
  of ltkGeneric: typ.generic.name

proc loc*(typ: LocalType): Location =
  case typ.kind:
  of ltkModule: typ.module.loc
  of ltkGeneric: typ.generic.loc

proc hash*(typ: LocalType): Hash =
  ## Identity via the underlying parser.Module or parser.Generic hash
  ## (each of which is loc-based). Enables `Table[parser.LocalType, T]`
  ## for identity-based scope lookups downstream of name resolution.
  case typ.kind:
  of ltkModule: typ.module.hash
  of ltkGeneric: typ.generic.hash

proc `==`*(a, b: LocalType): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of ltkModule: a.module == b.module
    of ltkGeneric: a.generic == b.generic

proc decorators*(typ: LocalType): seq[Decorator] =
  case typ.kind:
  of ltkModule: typ.module.decorators
  of ltkGeneric: typ.generic.decorators

proc asl*(typ: LocalType, level: int, indentWidth: uint32): seq[string] =
  case typ.kind:
  of ltkModule: typ.module.asl(level, indentWidth)
  of ltkGeneric: typ.generic.asl(level, indentWidth)

proc findFunctionDefs*(typ: LocalType, name: Identifier, arity: int, context: LocalType): Result[seq[FunctionDef], string] =
  case typ.kind:
  of ltkModule: typ.module.findFunctionDefs(name, arity, typ.access(context))
  # Generic funcDefs are implicitly public per the grammar — no
  # access filter to apply.
  of ltkGeneric: typ.generic.findFunctionDefs(name, arity)
