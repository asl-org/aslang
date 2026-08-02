## ResolvedTypeContext — TypeContext one rung up the identity ladder:
## the enclosing definition context (resolved module | resolved
## generic) a type reference is analyzed in. Phase A carries it for
## exactly one decision: which functions of an impl module a
## constraint check may see (`access`). Same rule as the resolver's
## TypeContext — a non-public function is visible only from inside
## its own module; generic blocks are not modules and see public
## functions only.

import ./resolver

type
  ResolvedTypeContextKind* = enum
    rtckModule, rtckGeneric

  ResolvedTypeContext* = ref object
    case kind: ResolvedTypeContextKind
    of rtckModule: module: ResolvedModule
    of rtckGeneric: generic: ResolvedGeneric

proc newResolvedTypeContext*(module: ResolvedModule): ResolvedTypeContext =
  ResolvedTypeContext(kind: rtckModule, module: module)

proc newResolvedTypeContext*(generic: ResolvedGeneric): ResolvedTypeContext =
  ResolvedTypeContext(kind: rtckGeneric, generic: generic)

proc kind*(typeCtx: ResolvedTypeContext): ResolvedTypeContextKind = typeCtx.kind

proc module*(typeCtx: ResolvedTypeContext): ResolvedModule =
  assert typeCtx.kind == rtckModule,
    "ResolvedTypeContext.module accessed but kind is rtckGeneric"
  typeCtx.module

proc generic*(typeCtx: ResolvedTypeContext): ResolvedGeneric =
  assert typeCtx.kind == rtckGeneric,
    "ResolvedTypeContext.generic accessed but kind is rtckModule"
  typeCtx.generic

proc access*(typeCtx: ResolvedTypeContext, module: ResolvedModule): FunctionAccess =
  ## Which functions of `module` this context may see.
  case typeCtx.kind:
  of rtckModule:
    if typeCtx.module == module: faAll
    else: faPublic
  of rtckGeneric: faPublic
