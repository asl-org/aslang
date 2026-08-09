## TypeContext — the definition context a type reference appears in:
## the enclosing module or the enclosing generic block. Carried through
## resolution so visibility can be decided at the site that needs it:
## a non-public function is accessible only from inside the module
## that defines it (`faAll`); every other context — a different
## module, or any generic block (generics are not modules and their
## own funcDefs are implicitly public per the grammar) — sees public
## functions only (`faPublic`).

import results, strformat

import parser
import argtype

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

proc satisfies*(typeCtx: TypeContext, base: Generic, argType: ResolvedGenericArgumentType): Result[void, string] =
  for def in base.defs:
    # NOTE: Generic functions are always public so we don't need access parameter
    let maybeFuncDefs = argType.generic.findFunctionDefs(def.name, def.arity)
    if maybeFuncDefs.isErr: return err(fmt"{argType.loc} generic `{argType.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc satisfies*(typeCtx: TypeContext, base: Generic, impl: ResolvedModuleArgumentType): Result[void, string] =
  ## A private function only counts as implementing `base` when the
  ## lookup context is the impl module itself (`faAll`) — everywhere
  ## else the constraint demands a public function.
  let access = typeCtx.access(impl.module)
  for def in base.defs:
    let maybeFuncDefs = impl.module.findFunctionDefs(def.name, def.arity, access)
    if maybeFuncDefs.isErr: return err(fmt"{impl.loc} module `{impl.name.asl}` does not implement function `{def.name.asl}` to support `{base.name.asl}`")
  ok()

proc satisfies*(typeCtx: TypeContext, base: Generic, impl: ResolvedArgumentType): Result[void, string] =
  case impl.kind:
  of ratkModule: typeCtx.satisfies(base, impl.module)
  of ratkGeneric: typeCtx.satisfies(base, impl.generic)
