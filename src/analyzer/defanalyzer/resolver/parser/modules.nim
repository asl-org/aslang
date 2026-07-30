import strformat, strutils, sequtils, options, tables, results, hashes

import ./tokenizer
import ./error

import ./identifiers
import ./decorator

import ./structdef
import ./uniondef
import ./datadef
import ./funcdef
import ./externfunc
import ./function

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
  let functionIndex = buildNameArityIndex(funcList)
  ok(Module(decorators: decorators, public: public, name: name, data: data, funcList: funcList, functionIndex: functionIndex, loc: loc))

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc data*(m: Module): Option[DataDef] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc
proc hash*(m: Module): Hash = m.loc.hash
proc `==`*(a, b: Module): bool = a.hash == b.hash

proc struct*(m: Module, loc: Location): Result[StructDef, string] =
  if m.data.isSome: m.data.get.struct(m.name)
  else: err(fmt"{loc} module `{m.name.asl}` is not a struct")

proc externFunctions*(m: Module): seq[ExternFunction] =
  var externFuncs: seq[ExternFunction]
  for fn in m.functions:
    case fn.kind:
    of fkExtern: externFuncs.add(fn.extern)
    of fkUser: discard
  return externFuncs

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

proc findFunctionDefs*(module: Module, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    ok(module.functionIndex[name][arity].mapIt(module.functions[it].def))

type ModuleHeader* = tuple[public: bool, name: Identifier, loc: Location]

# Module body: optional requires + optional data block + function list
type ModuleBody* = tuple[data: Option[DataDef], funcList: FunctionList]