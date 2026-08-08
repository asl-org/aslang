import strformat, strutils, sequtils, tables, results, hashes

import ./tokenizer

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