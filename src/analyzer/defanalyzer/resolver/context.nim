## Resolution context — `TypeContext` (the enclosing definition context
## — module | generic — carried so visibility and constraint
## satisfaction can be decided at the site that needs them). The per-file
## scope (`ResolvedFile`) lives in app.nim.

import parser

# ============================================================
# TypeContext
# ============================================================
# The definition context a type reference appears in: the enclosing
# module or generic block. Carried through resolution so visibility can
# be decided at the site that needs it (a non-public function is
# accessible only from inside its own module; generics see public only)
# and so constraint satisfaction can consult it.

type
  TypeContextKind* = enum
    tckModule, tckGeneric

  TypeContext* = ref object
    case kind: TypeContextKind
    of tckModule: module: Module
    of tckGeneric: generic: Generic

proc newTypeContext*(module: Module): TypeContext =
  TypeContext(kind: tckModule, module: module)

proc newTypeContext*(generic: Generic): TypeContext =
  TypeContext(kind: tckGeneric, generic: generic)

proc kind*(typeCtx: TypeContext): TypeContextKind = typeCtx.kind

proc module*(typeCtx: TypeContext): Module =
  assert typeCtx.kind == tckModule,
    "TypeContext.module accessed but kind is tckGeneric"
  typeCtx.module

proc generic*(typeCtx: TypeContext): Generic =
  assert typeCtx.kind == tckGeneric,
    "TypeContext.generic accessed but kind is tckModule"
  typeCtx.generic

proc access*(typeCtx: TypeContext, module: Module): FunctionAccess =
  ## Which functions of `module` this context may see.
  case typeCtx.kind:
  of tckGeneric:
    faPublic
  of tckModule:
    if typeCtx.module == module: faAll else: faPublic
