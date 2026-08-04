## Phase-A `AnalyzedLocalType` — tagged union over the two defined-
## type kinds (module / generic). Phase-B module/generic lookups go
## through `AnalyzedFileContext.findType(ResolvedLocalType)`
## (per-file, identity-keyed, spans imports + locals) or the
## local-only `AnalyzedDefFile.findType`; this file just owns the
## variant itself + the per-defined-type function-overload accessor.

import results, strformat

import ./resolver
import ./funcdef
import ./moduledef
import ./generic

type
  AnalyzedLocalTypeKind* = enum
    altkModule, altkGeneric
  AnalyzedLocalType* = ref object
    case kind: AnalyzedLocalTypeKind
    of altkModule: module: AnalyzedDefModule
    of altkGeneric: generic: AnalyzedGeneric

proc newAnalyzedLocalType*(module: AnalyzedDefModule): AnalyzedLocalType =
  AnalyzedLocalType(kind: altkModule, module: module)

proc newAnalyzedLocalType*(generic: AnalyzedGeneric): AnalyzedLocalType =
  AnalyzedLocalType(kind: altkGeneric, generic: generic)

proc kind*(d: AnalyzedLocalType): AnalyzedLocalTypeKind = d.kind
proc module*(d: AnalyzedLocalType): AnalyzedDefModule =
  assert d.kind == altkModule,
    fmt"AnalyzedLocalType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedLocalType): AnalyzedGeneric =
  assert d.kind == altkGeneric,
    fmt"AnalyzedLocalType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedLocalType): Identifier =
  case d.kind:
  of altkModule: d.module.name
  of altkGeneric: d.generic.name
proc loc*(d: AnalyzedLocalType): Location =
  case d.kind:
  of altkModule: d.module.loc
  of altkGeneric: d.generic.loc

proc resolved*(definedType: AnalyzedLocalType): ResolvedLocalType =
  case definedType.kind:
  of altkModule: newResolvedLocalType(definedType.module.resolved)
  of altkGeneric: newResolvedLocalType(definedType.generic.resolved)

proc findFunctionDefs*(definedType: AnalyzedLocalType, name: Identifier, arity: int, access: FunctionAccess): Result[seq[AnalyzedFunctionDefinition], string] =
  ## Uniform overload lookup regardless of definedType.kind. `access`
  ## is honored by modules and ignored by generics (their funcDefs
  ## are implicitly public — a generic block is an interface
  ## declaration).
  case definedType.kind:
  of altkModule: definedType.module.findFunctionDefs(name, arity, access)
  of altkGeneric: definedType.generic.findFunctionDefs(name, arity)
