import strformat, strutils, options, tables, results, hashes

import ./tokenizer
import ./combinators
import ./identifiers
import ./data
import ./funcs
import ./funcs
import ./generics

# ============================================================
# Module
# ============================================================

type Module* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  requires: Option[Requires]
  data: Option[DataBlock]
  funcList: FunctionList
  functionIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc requires*(m: Module): Option[Requires] = m.requires
proc data*(m: Module): Option[DataBlock] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc
proc hash*(m: Module): Hash = m.loc.hash
proc `==`*(a, b: Module): bool = a.hash == b.hash

proc struct*(m: Module, loc: Location): Result[StructDef, string] =
  if m.data.isSome: m.data.get.struct(m.name)
  else: err(fmt"{loc} module `{m.name.asl}` is not a struct")

proc union*(m: Module, loc: Location): Result[UnionDef, string] =
  if m.data.isSome: m.data.get.union(m.name)
  else: err(fmt"{loc} module `{m.name.asl}` is not a union")

proc newModule*(decorators: seq[Decorator], public: bool, name: Identifier,
    requires: Option[Requires], data: Option[DataBlock],
    funcList: FunctionList, loc: Location): Result[Module, ParserError] =
  if data.isNone and funcList.len == 0:
    let msg = "module must have at least 1 struct/union/function block"
    return err(newParserError(msg, loc))
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  for i, fn in funcList.functions:
    if fn.name notin functionIndex:
      functionIndex[fn.name] = initTable[int, seq[int]]()
    if fn.arity notin functionIndex[fn.name]:
      functionIndex[fn.name][fn.arity] = newSeq[int]()
    functionIndex[fn.name][fn.arity].add(i)

  ok(Module(decorators: decorators, public: public, name: name,
      requires: requires, data: data, funcList: funcList,
      functionIndex: functionIndex, loc: loc))

proc asl*(module: Module, indentWidth: uint32): seq[string] =
  for d in module.decorators:
    result.add(asl(d))
  let prefix = if module.public: "public module" else: "module"
  result.add(fmt"{prefix} {asl(module.name)}:")
  let indent = " ".repeat(indentWidth)
  if module.requires.isSome:
    result.add(fmt"{indent}{asl(module.requires.get)}")
    result.add("")
  if module.data.isSome:
    for line in asl(module.data.get, indentWidth):
      result.add(fmt"{indent}{line}")
    result.add("")
  for i, fn in module.funcList.functions:
    if i > 0: result.add("")
    for line in asl(fn, indentWidth):
      result.add(fmt"{indent}{line}")

proc findFunctionDefIds(module: Module, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    ok(module.functionIndex[name][arity])

proc findFunctionDefs*(module: Module, name: Identifier, arity: int): Result[seq[FunctionDefinition], string] =
  let funcDefIds = ? module.findFunctionDefIds(name, arity)
  var funcDefs: seq[FunctionDefinition]
  for id in funcDefIds:
    funcDefs.add(module.functions[id].def)
  ok(funcDefs)

type ModuleHeader = tuple[public: bool, name: Identifier, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let maybePublic = parser.run(keywordSpec("public"))
  if maybePublic.isOk: discard ? parser.run(atLeastOne(spaceSpec))
  let public = maybePublic.isOk

  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

# Module body: optional requires + optional data block + function list
type ModuleBody = tuple[requires: Option[Requires], data: Option[DataBlock],
    funcList: FunctionList]

let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let requires = ? parser.run(optional(requiresSpec))
  discard parser.run(any(ignorableLineSpec))
  let data = ? parser.run(optional(dataBlockSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((requires, data, funcList))
)

let moduleSpec* = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Result[Module, ParserError] =
  newModule(d, h.public, h.name, b.requires, b.data, b.funcList, h.loc))
