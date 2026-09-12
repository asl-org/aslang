## Parser local-type cluster — a file's declared types: Generic and
## Module (each with its header/body helpers), unified by the LocalType
## tagged union over them.

import strformat, results, hashes

import parser

import identifiers
import decorator
import function

# Generic and Module (with their header/body helpers and parse specs)
# were extracted to generic.nim / module.nim; re-exported so
# `import types` and the parser/main barrel still surface them.
import generic
import module

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

proc typeConsumer(parser: Parser): Result[LocalType, ParserError] =
  ## Skips leading blank / comment lines, then parses a module or
  ## generic block. Used at file level between top-level type blocks so
  ## `typeSpec.atLeastOne()` collects every definition across the blank
  ## lines that separate them (not just the first block).
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(oneOf("type", @[
    moduleSpec.map(newLocalType),
    genericSpec.map(newLocalType),
  ]))

let typeSpec* = newSpec[LocalType]("type", typeConsumer)