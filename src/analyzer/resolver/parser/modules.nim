import strformat, strutils, options, tables, results, hashes

import ./tokenizer
import ./combinators
import ./identifiers
import ./data
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
  data: Option[DataDef]
  funcList: FunctionList
  functionIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc requires*(m: Module): Option[Requires] = m.requires
proc data*(m: Module): Option[DataDef] = m.data
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
    requires: Option[Requires], data: Option[DataDef],
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

proc asl*(module: Module, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  for d in module.decorators:
    lines.add(fmt"{indent}{asl(d)}")
  let prefix = if module.public: "public module" else: "module"
  lines.add(fmt"{indent}{prefix} {asl(module.name)}:")
  if module.requires.isSome:
    lines.add(fmt"{inner}{asl(module.requires.get)}")
    lines.add("")
  if module.data.isSome:
    for line in asl(module.data.get, level + 1, indentWidth):
      lines.add(line)
    lines.add("")
  for i, fn in module.funcList.functions:
    if i > 0: lines.add("")
    for line in asl(fn, level + 1, indentWidth):
      lines.add(line)
  lines

proc findFunctionDefIds(module: Module, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    ok(module.functionIndex[name][arity])

proc findFunctionDefs*(module: Module, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  let funcDefIds = ? module.findFunctionDefIds(name, arity)
  var funcDefs: seq[FunctionDef]
  for id in funcDefIds:
    funcDefs.add(module.functions[id].def)
  ok(funcDefs)

type ModuleHeader = tuple[public: bool, name: Identifier, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

# Module body: optional requires + optional data block + function list
type ModuleBody = tuple[requires: Option[Requires], data: Option[DataDef],
    funcList: FunctionList]

let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(blankLines)
  let requires = ? parser.run(optional(requiresSpec))
  discard parser.run(blankLines)
  let data = ? parser.run(optional(dataSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((requires, data, funcList))
)

let moduleSpec* = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Result[Module, ParserError] =
  newModule(d, h.public, h.name, b.requires, b.data, b.funcList, h.loc))
