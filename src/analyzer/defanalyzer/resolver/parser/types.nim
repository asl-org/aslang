import hashes, strformat, results

import ./tokenizer

import ./identifiers
import ./decorator
import ./funcdef
import ./generics
import ./modules

# ============================================================
# LocalType
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

proc kind*(dt: LocalType): LocalTypeKind = dt.kind
proc public*(dt: LocalType): bool =
  case dt.kind:
  of ltkModule: dt.module.public
  of ltkGeneric: dt.generic.public

proc module*(dt: LocalType): Module =
  assert dt.kind == ltkModule,
    fmt"LocalType.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: LocalType): Generic =
  assert dt.kind == ltkGeneric,
    fmt"LocalType.generic accessed but kind is {dt.kind}"
  dt.generic

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

proc findFunctionDefs*(typ: LocalType, name: Identifier, arity: int, access: FunctionAccess): Result[seq[FunctionDef], string] =
  case typ.kind:
  of ltkModule: typ.module.findFunctionDefs(name, arity, access)
  # Generic funcDefs are implicitly public per the grammar — no
  # access filter to apply.
  of ltkGeneric: typ.generic.findFunctionDefs(name, arity)
