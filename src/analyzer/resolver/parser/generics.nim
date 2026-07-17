import strformat, strutils, sequtils, tables, results, hashes

import ./tokenizer
import ./error

import ./identifiers
import ./decorator
import ./funcdef

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
  funcDefs: seq[FunctionDef]
  funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc newGeneric*(decorators: seq[Decorator], public: bool, name: Identifier,
    funcDefs: seq[FunctionDef], loc: Location): Result[Generic, ParserError] =
  let funcDefArityIndex = buildNameArityIndex(funcDefs)
  ok(Generic(decorators: decorators, public: public, name: name, funcDefs: funcDefs, funcDefArityIndex: funcDefArityIndex, loc: loc))

proc public*(g: Generic): bool = g.public
proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDef] = g.funcDefs
proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc loc*(g: Generic): Location = g.loc
proc hash*(g: Generic): Hash = g.loc.hash
proc `==`*(a, b: Generic): bool = a.hash == b.hash

proc asl*(gen: Generic, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines = gen.decorators.mapIt(fmt"{indent}{it.asl}")
  let prefix = if gen.public: "public generic" else: "generic"
  lines.add(fmt"{indent}{prefix} {asl(gen.name)}:")
  let funcDefs = gen.funcDefs.mapIt(fmt"{inner}{it.asl}")
  lines.add(funcDefs)
  return lines

proc findFunctionDefs*(generic: Generic, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  if name notin generic.funcDefArityIndex:
    err(fmt"{name.loc} function `{name.asl}` does not exist in generic")
  elif arity notin generic.funcDefArityIndex[name]:
    err(fmt"{name.loc} function `{name.asl}` with arity `{arity}` does not exist in generic")
  else:
    let defIds = generic.funcDefArityIndex[name][arity]
    ok(defIds.mapIt(generic.funcDefs[it]))

type GenericHeader* = tuple[public: bool, name: Identifier, loc: Location]