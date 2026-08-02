## Phase-A `AnalyzedType` — tagged union over the two defined-
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
  AnalyzedTypeKind* = enum
    atkModule, atkGeneric
  AnalyzedType* = ref object
    case kind: AnalyzedTypeKind
    of atkModule: module: AnalyzedDefModule
    of atkGeneric: generic: AnalyzedGeneric

proc newAnalyzedType*(module: AnalyzedDefModule): AnalyzedType =
  AnalyzedType(kind: atkModule, module: module)

proc newAnalyzedType*(generic: AnalyzedGeneric): AnalyzedType =
  AnalyzedType(kind: atkGeneric, generic: generic)

proc kind*(d: AnalyzedType): AnalyzedTypeKind = d.kind
proc module*(d: AnalyzedType): AnalyzedDefModule =
  assert d.kind == atkModule,
    fmt"AnalyzedType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedType): AnalyzedGeneric =
  assert d.kind == atkGeneric,
    fmt"AnalyzedType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedType): Identifier =
  case d.kind:
  of atkModule: d.module.name
  of atkGeneric: d.generic.name
proc loc*(d: AnalyzedType): Location =
  case d.kind:
  of atkModule: d.module.loc
  of atkGeneric: d.generic.loc

proc resolved*(definedType: AnalyzedType): ResolvedType =
  case definedType.kind:
  of atkModule: newResolvedType(definedType.module.resolved)
  of atkGeneric: newResolvedType(definedType.generic.resolved)

proc findFunctionDefs*(definedType: AnalyzedType, name: Identifier, arity: int, access: FunctionAccess): Result[seq[AnalyzedFunctionDefinition], string] =
  ## Uniform overload lookup regardless of definedType.kind. `access`
  ## is honored by modules and ignored by generics (their funcDefs
  ## are implicitly public — a generic block is an interface
  ## declaration).
  case definedType.kind:
  of atkModule: definedType.module.findFunctionDefs(name, arity, access)
  of atkGeneric: definedType.generic.findFunctionDefs(name, arity)
