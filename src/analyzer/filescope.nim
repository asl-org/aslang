## ResolvedFileScope — per-file name-keyed lookup (Identifier ->
## ResolvedType). The initial entry point for name resolution —
## used by callers that hold an Identifier from the parse tree
## (`defaultLiteralArgType` looking up "i32", or the initial type
## reference at the top of an argType).
##
## Identity-based lookups (given a `parser.Type` from a resolved
## argType, find the ResolvedType) go through `app.findType` —
## the app-level index on ResolvedApp — not through this scope.
## An earlier iteration of plan_identity_based_lookups.md added a
## per-file `ResolvedTypeScope` here; the app-level index proved
## simpler and covers every case without threading.

import results, strformat, tables

import ./resolver
import ./importdef
import ./importedtype

type ResolvedFileScope* = Table[Identifier, ResolvedType]

proc update(fileScope: var ResolvedFileScope, name: Identifier, typ: ResolvedType): Result[ResolvedFileScope, string] =
  if name in fileScope:
    let loc = fileScope[name].loc
    return err(fmt"{name.loc} encountered duplicated type declaration, see previous declaration at {loc}")
  else:
    fileScope[name] = typ
    ok(fileScope)

proc newResolvedFileScope*(imports: seq[AnalyzedImportDefinition], types: seq[ResolvedType]): Result[ResolvedFileScope, string] =
  var fileScope: ResolvedFileScope
  for imp in imports:
    for impType in imp.importedTypes:
      fileScope = ? fileScope.update(impType.binding, impType.typ)

  for typ in types:
    fileScope = ? fileScope.update(typ.name, typ)

  ok(fileScope)