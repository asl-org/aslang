import hashes, strformat, results

import ./tokenizer

import ./identifiers
import ./decorator
import ./funcdef
import ./generics
import ./modules

# ============================================================
# Type
# ============================================================

type
  TypeKind* = enum
    tkModule, tkGeneric
  Type* = ref object
    case kind: TypeKind
    of tkModule: module: Module
    of tkGeneric: generic: Generic

proc newType*(module: Module): Type =
  Type(kind: tkModule, module: module)

proc newType*(generic: Generic): Type =
  Type(kind: tkGeneric, generic: generic)

proc kind*(dt: Type): TypeKind = dt.kind
proc public*(dt: Type): bool =
  case dt.kind:
  of tkModule: dt.module.public
  of tkGeneric: dt.generic.public

proc module*(dt: Type): Module =
  assert dt.kind == tkModule,
    fmt"Type.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: Type): Generic =
  assert dt.kind == tkGeneric,
    fmt"Type.generic accessed but kind is {dt.kind}"
  dt.generic

proc name*(typ: Type): Identifier =
  case typ.kind:
  of tkModule: typ.module.name
  of tkGeneric: typ.generic.name

proc loc*(typ: Type): Location =
  case typ.kind:
  of tkModule: typ.module.loc
  of tkGeneric: typ.generic.loc

proc hash*(typ: Type): Hash =
  ## Identity via the underlying parser.Module or parser.Generic hash
  ## (each of which is loc-based). Enables `Table[parser.Type, T]`
  ## for identity-based scope lookups downstream of name resolution.
  case typ.kind:
  of tkModule: typ.module.hash
  of tkGeneric: typ.generic.hash

proc `==`*(a, b: Type): bool =
  if a.kind != b.kind: false
  else:
    case a.kind:
    of tkModule: a.module == b.module
    of tkGeneric: a.generic == b.generic

proc decorators*(typ: Type): seq[Decorator] =
  case typ.kind:
  of tkModule: typ.module.decorators
  of tkGeneric: typ.generic.decorators

proc asl*(typ: Type, level: int, indentWidth: uint32): seq[string] =
  case typ.kind:
  of tkModule: typ.module.asl(level, indentWidth)
  of tkGeneric: typ.generic.asl(level, indentWidth)

proc findFunctionDefs*(typ: Type, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  case typ.kind:
  of tkModule: typ.module.findFunctionDefs(name, arity)
  of tkGeneric: typ.generic.findFunctionDefs(name, arity)
