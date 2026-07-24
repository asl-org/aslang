## Phase-A `AnalyzedDefinedType` — tagged union over the two defined-
## type kinds (module / generic). Plus `AnalyzedDefinedTypeScope`, a
## per-file index name → analyzed defined type. Used by phase B to
## look up call targets by name and by the fileDef scope walk to
## augment with imports.

import results, strformat, tables

import ./resolver
import ./argtype
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

proc findFunctionDefs*(definedType: AnalyzedDefinedType, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  ## Uniform overload lookup regardless of definedType.kind. `public`
  ## is honored by modules and ignored by generics (their funcDefs
  ## are implicitly public — a generic block is an interface
  ## declaration).
  case definedType.kind:
  of adtkModule: definedType.module.findFunctionDefs(name, arity, public)
  of adtkGeneric: definedType.generic.findFunctionDefs(name, arity)

# ---- AnalyzedDefinedTypeScope ----

type AnalyzedDefinedTypeScope* = Table[Identifier, AnalyzedDefinedType]

proc findType*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedDefinedType, string] =
  if name notin defScope:
    err(fmt"{loc} UNREACHABLE: type `{name.asl}` is not defined")
  else:
    ok(defScope[name])

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, name: Identifier, loc: Location): Result[AnalyzedModuleDefinition, string] =
  let entry = ? defScope.findType(name, loc)
  case entry.kind:
  of adtkModule: ok(entry.module)
  of adtkGeneric:
    err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

proc findModuleDef*(defScope: AnalyzedDefinedTypeScope, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  ## Look up the AnalyzedModuleDefinition backing a module-kind
  ## argType. Generic-kind argTypes are a caller error (phase-B
  ## overload resolution should never dispatch on a free generic).
  case argType.kind:
  of aatkGeneric:
    err(fmt"{loc} todo: analyze case blocks / method calls for generic subject type")
  of aatkModule:
    let moduleArgType = argType.module
    if moduleArgType.name notin defScope:
      err(fmt"{loc} UNREACHABLE: module `{moduleArgType.name.asl}` is not defined")
    else:
      let entry = defScope[moduleArgType.name]
      case entry.kind:
      of adtkModule: ok(entry.module)
      of adtkGeneric:
        err(fmt"{loc} UNREACHABLE: scope entry `{moduleArgType.name.asl}` is a generic but argType is a module")
