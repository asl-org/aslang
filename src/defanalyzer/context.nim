## Phase-A resolution contexts — `ResolvedFileContext` (per-file
## identity-keyed name→scope-entry lookup) and `ResolvedTypeContext`
## (the enclosing definition context — resolved module | resolved
## generic — carried for the one visibility decision a constraint check
## needs). Both threaded through the phase-A walk.

import results, strformat, hashes, tables

import ../parser/index as parser
import ../resolver/index as resolver
import importdef

# ============================================================
# ResolvedFileContext
# ============================================================
# Per-file identity-keyed lookup (parser.LocalType -> ResolvedLocalType),
# spanning imports + local defined types. Keys hash by source location,
# so the same type imported under two bindings lands on one key and
# aliased imports can never miss.

type
  ResolvedTypeKind* = enum
    rtkLocal, rtkImported
  ResolvedType* = ref object
    ## Scope entry — the Local | Imported union one rung up the
    ## ladder: a type analyzed in this file or the LINKED import
    ## binding, which carries the source file's ResolvedLocalType.
    ## Hashes and compares by the underlying so aliased imports land
    ## on one identity key; provenance is payload, not identity.
    case kind: ResolvedTypeKind
    of rtkLocal: local: ResolvedLocalType
    of rtkImported: imported: AnalyzedDefImportedType

proc newResolvedType*(local: ResolvedLocalType): ResolvedType =
  ResolvedType(kind: rtkLocal, local: local)

proc newResolvedType*(imported: AnalyzedDefImportedType): ResolvedType =
  ResolvedType(kind: rtkImported, imported: imported)

proc kind*(t: ResolvedType): ResolvedTypeKind = t.kind

proc local*(t: ResolvedType): ResolvedLocalType =
  assert t.kind == rtkLocal, "ResolvedType.local accessed but kind is rtkImported"
  t.local

proc imported*(t: ResolvedType): AnalyzedDefImportedType =
  assert t.kind == rtkImported, "ResolvedType.imported accessed but kind is rtkLocal"
  t.imported

proc localType*(t: ResolvedType): ResolvedLocalType =
  ## The underlying analyzed-of-resolved type, regardless of
  ## provenance.
  case t.kind:
  of rtkLocal: t.local
  of rtkImported: t.imported.typ

proc hash*(t: ResolvedType): Hash = t.localType.hash
proc `==`*(a, b: ResolvedType): bool = a.localType == b.localType

type ResolvedFileContext* = Table[parser.LocalType, ResolvedType]

proc update(fileCtx: var ResolvedFileContext, parsed: parser.LocalType, resolved: ResolvedType) =
  ## Same-identity re-insert (the same type imported under a second
  ## binding) is idempotent — keys hash by source location, and
  ## entries compare by their underlying, so both bindings land here
  ## equal. A genuinely different entry under an existing key is a
  ## compiler bug — the resolver's name-keyed ResolvedFile already
  ## rejected duplicate declarations.
  assert(parsed notin fileCtx or fileCtx[parsed] == resolved, fmt"[BUG] - {parsed.loc} conflicting entries for type `{parsed.name.asl}` in the file context")
  fileCtx[parsed] = resolved

proc newResolvedFileContext*(imports: seq[AnalyzedDefImport], types: seq[ResolvedLocalType]): ResolvedFileContext =
  var fileCtx: ResolvedFileContext
  for imp in imports:
    for impType in imp.importedTypes:
      fileCtx.update(impType.typ.parsed, newResolvedType(impType))
  for typ in types:
    fileCtx.update(typ.parsed, newResolvedType(typ))
  return fileCtx

# Identity lookups — the resolver bound every key it hands us in this
# same file's scope, so a miss (or a kind mismatch) is a compiler
# bug, never a user error. The asserts own that invariant here so
# call sites don't have to.
proc findType*(fileCtx: ResolvedFileContext, parsed: parser.LocalType): ResolvedType =
  assert(parsed in fileCtx, fmt"[BUG] - {parsed.loc} type `{parsed.name.asl}` missing from the file context")
  fileCtx[parsed]

proc findModule*(fileCtx: ResolvedFileContext, module: Module): ResolvedModule =
  let typ = fileCtx.findType(newLocalType(module)).localType
  assert(typ.kind == rltkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was bound as a module by the resolver")
  typ.module

proc findGeneric*(fileCtx: ResolvedFileContext, generic: Generic): ResolvedGeneric =
  let typ = fileCtx.findType(newLocalType(generic)).localType
  assert(typ.kind == rltkGeneric, fmt"[BUG] - {generic.loc} `{generic.name.asl}` was bound as a generic by the resolver")
  typ.generic

# ============================================================
# ResolvedTypeContext
# ============================================================
# The enclosing definition context (resolved module | resolved generic)
# a type reference is analyzed in — carried for exactly one decision:
# which functions of an impl module a constraint check may see.

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

proc findImplDef*(typeCtx: ResolvedTypeContext, module: ResolvedModule, def: ResolvedFunctionDef): Result[ResolvedFunctionDef, string] =
  let access = typeCtx.access(module)
  module.findImplDef(def, access)

proc findImplDef*(typeCtx: ResolvedTypeContext, generic: ResolvedGeneric, def: ResolvedFunctionDef): Result[ResolvedFunctionDef, string] =
  generic.findImplDef(def, faAll)
