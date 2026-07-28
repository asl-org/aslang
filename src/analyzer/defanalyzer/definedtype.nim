## Phase-A `AnalyzedDefinedType` — tagged union over the two defined-
## type kinds (module / generic). Phase-B module/generic lookups go
## through `AnalyzedDefApp.findDefinedType(ResolvedType)`
## (app-level, identity-keyed); this file just owns the variant
## itself + the per-defined-type function-overload accessor.

import results, strformat

import ./resolver
import ./funcdef
import ./moduledef
import ./generic

type
  AnalyzedDefinedTypeKind* = enum
    adtkModule, adtkGeneric
  AnalyzedDefinedType* = ref object
    case kind: AnalyzedDefinedTypeKind
    of adtkModule: module: AnalyzedModuleDefinition
    of adtkGeneric: generic: AnalyzedGeneric

proc newAnalyzedDefinedType*(module: AnalyzedModuleDefinition): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkModule, module: module)

proc newAnalyzedDefinedType*(generic: AnalyzedGeneric): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedType): AnalyzedDefinedTypeKind = d.kind
proc module*(d: AnalyzedDefinedType): AnalyzedModuleDefinition =
  assert d.kind == adtkModule,
    fmt"AnalyzedDefinedType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedDefinedType): AnalyzedGeneric =
  assert d.kind == adtkGeneric,
    fmt"AnalyzedDefinedType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedDefinedType): Identifier =
  case d.kind:
  of adtkModule: d.module.name
  of adtkGeneric: d.generic.name
proc loc*(d: AnalyzedDefinedType): Location =
  case d.kind:
  of adtkModule: d.module.loc
  of adtkGeneric: d.generic.loc

proc resolved*(definedType: AnalyzedDefinedType): ResolvedType =
  case definedType.kind:
  of adtkModule: newResolvedType(definedType.module.resolved)
  of adtkGeneric: newResolvedType(definedType.generic.resolved)

proc findFunctionDefs*(definedType: AnalyzedDefinedType, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  ## Uniform overload lookup regardless of definedType.kind. `public`
  ## is honored by modules and ignored by generics (their funcDefs
  ## are implicitly public — a generic block is an interface
  ## declaration).
  case definedType.kind:
  of adtkModule: definedType.module.findFunctionDefs(name, arity, public)
  of adtkGeneric: definedType.generic.findFunctionDefs(name, arity)
