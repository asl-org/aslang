## Resolved DefinedType umbrella + resolver.
##
## The `ResolvedDefinedType` type, its constructors, and direct-field
## accessors live in `types.nim`. This file owns the computed helpers
## (name / loc dispatched by kind) and the resolveDefinedType proc.

import results

import tokenizer
import parser
import types
import argtypes
import modules

# ---- ResolvedDefinedType computed helpers ----

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
