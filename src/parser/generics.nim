import strformat, strutils, tables, results, hashes

import ./tokenizer
import ./combinators
import ./identifiers
import ./funcs

# ============================================================
# Generic
# ============================================================

type Generic* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  funcDefs: seq[FunctionDef]
  funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[string, seq[int]]
  loc: Location

proc public*(g: Generic): bool = g.public
proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDef] = g.funcDefs
proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc loc*(g: Generic): Location = g.loc
proc hash*(g: Generic): Hash = g.loc.hash
proc `==`*(a, b: Generic): bool = a.hash == b.hash

proc newGeneric*(decorators: seq[Decorator], public: bool, name: Identifier,
    funcDefs: seq[FunctionDef], loc: Location): Result[Generic, ParserError] =
  var funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  var funcDefIndex: Table[string, seq[int]]
  for index, def in funcDefs:
    if def.name notin funcDefArityIndex:
      funcDefArityIndex[def.name] = initTable[int, seq[int]]()
    if def.arity notin funcDefArityIndex[def.name]:
      funcDefArityIndex[def.name][def.arity] = newSeq[int]()
    funcDefArityIndex[def.name][def.arity].add(index)
    funcDefIndex.mgetOrPut(def.name.value, @[]).add(index)
  ok(Generic(decorators: decorators, public: public, name: name, funcDefs: funcDefs,
      funcDefArityIndex: funcDefArityIndex, funcDefIndex: funcDefIndex, loc: loc))

proc asl*(gen: Generic, indentWidth: uint32): seq[string] =
  for d in gen.decorators:
    result.add(asl(d))
  let prefix = if gen.public: "public generic" else: "generic"
  result.add(fmt"{prefix} {asl(gen.name)}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

proc findFunctionDefIds(generic: Generic, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin generic.funcDefArityIndex:
    err(fmt"{name.loc} function `{name.asl}` does not exist in generic")
  elif arity notin generic.funcDefArityIndex[name]:
    err(fmt"{name.loc} function `{name.asl}` with arity `{arity}` does not exist in generic")
  else:
    ok(generic.funcDefArityIndex[name][arity])

proc findFunctionDefs*(generic: Generic, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  let funcIds = ? generic.findFunctionDefIds(name, arity)
  var funcs: seq[FunctionDef]
  for id in funcIds:
    funcs.add(generic.funcDefs[id])
  ok(funcs)

type GenericHeader = tuple[public: bool, name: Identifier, loc: Location]

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(ws1)
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

let genericSpec* = blockSpec("generic", genericHeaderSpec,
  functionDefListSpec,
  proc(h: GenericHeader, b: seq[FunctionDef]): Result[Generic, ParserError] =
  newGeneric(@[], h.public, h.name, b, h.loc))

# ============================================================
# Requires
# ============================================================

type Requires* = ref object
  generics: seq[Identifier]
  loc: Location

proc generics*(r: Requires): seq[Identifier] = r.generics
proc loc*(r: Requires): Location = r.loc

proc newRequires*(generics: seq[Identifier], loc: Location): Requires =
  Requires(generics: generics, loc: loc)

proc asl*(r: Requires): string =
  result = "requires("
  for i, g in r.generics:
    if i > 0: result.add(", ")
    result.add(asl(g))
  result.add(")")

# requires(Generic, Generic, ...)
let requiresSpec* = indentedLine(pair(keywordSpec("requires"),
    prefixed(ws0, contained("requires_generics", "(",
      separatedBy(identifierSpec, commaWithSpacesSpec), ")")))).map(
  "requires",
  proc(t: (Location, seq[Identifier])): Requires = newRequires(t[1], t[0]))
