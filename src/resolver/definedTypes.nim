## DefinedType / File / App + the public resolve* entry point.

import results, strformat

import tokenizer
import parser
import argtypes
import modules

# ResolvedDefinedType
type
  ResolvedDefinedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType* = ref object
    id: int
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType*(id: int, module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkModule, module: module)

proc newResolvedDefinedType*(id: int, generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkGeneric, generic: generic)

proc kind*(definedType: ResolvedDefinedType): ResolvedDefinedTypeKind = definedType.kind
proc module*(definedType: ResolvedDefinedType): ResolvedModule =
  assert definedType.kind == rdtkModule,
    fmt"ResolvedDefinedType.module accessed but kind is {definedType.kind}"
  definedType.module
proc generic*(definedType: ResolvedDefinedType): ResolvedGeneric =
  assert definedType.kind == rdtkGeneric,
    fmt"ResolvedDefinedType.generic accessed but kind is {definedType.kind}"
  definedType.generic

proc name*(definedType: ResolvedDefinedType): Identifier =
  case definedType.kind:
  of rdtkModule: definedType.module.name
  of rdtkGeneric: definedType.generic.name

proc loc*(definedType: ResolvedDefinedType): Location =
  case definedType.kind:
  of rdtkModule: definedType.module.loc
  of rdtkGeneric: definedType.generic.loc

proc resolveDefinedType*(app: App, file: parser.File, fileScope: FileScope, id: int, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, fileScope, definedType.generic)
    ok(newResolvedDefinedType(id, resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, definedType.module)
    ok(newResolvedDefinedType(id, resolvedModule))
