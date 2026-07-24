## Per-file scope tables. Two parallel indices — one for name lookups
## (the initial "user typed this name" query), one for identity
## lookups (post-resolution "given this parser.Type, find its
## resolved counterpart"). See plans/plan_identity_based_lookups.md
## for the rationale.
##
## `ResolvedFileScope` (name-keyed) is the entry point for name
## resolution — used by callers that hold an `Identifier` from the
## parse tree (like `defaultLiteralArgType` looking up "i32", or the
## initial type reference at the top of an argType). Aliased imports
## surface via their binding, not the underlying module name.
##
## `ResolvedTypeScope` (identity-keyed) is for callers that already
## hold a `parser.Type` (from a `ResolvedModuleArgumentType.module`
## etc.) and want the corresponding `ResolvedType`. Immune to the
## aliased-import name mismatch that motivated
## plan_identity_based_lookups.md.
##
## Both scopes are populated from the same source: imports +
## file.types. `newResolvedFileScope` returns a tuple.

import results, strformat, tables

import ./resolver
import ./importdef
import ./importedtype

type
  ResolvedFileScope* = Table[Identifier, ResolvedType]
  ResolvedTypeScope* = Table[parser.Type, ResolvedType]

proc update(fileScope: var ResolvedFileScope, name: Identifier, typ: ResolvedType): Result[ResolvedFileScope, string] =
  if name in fileScope:
    let loc = fileScope[name].loc
    return err(fmt"{name.loc} encountered duplicated type declaration, see previous declaration at {loc}")
  else:
    fileScope[name] = typ
    ok(fileScope)

proc newResolvedFileScope*(imports: seq[AnalyzedImportDefinition], types: seq[ResolvedType]): Result[(ResolvedFileScope, ResolvedTypeScope), string] =
  ## Builds both the name-keyed and identity-keyed scopes in one
  ## pass. Duplicate-name errors surface via the name-scope's
  ## `update`; the identity scope tolerates duplicates silently
  ## because the same parser.Type appearing twice is impossible
  ## (each is loc-unique) — but if it did happen, the last write
  ## wins.
  var nameScope: ResolvedFileScope
  var typeScope: ResolvedTypeScope
  for imp in imports:
    for impType in imp.importedTypes:
      nameScope = ? nameScope.update(impType.binding, impType.typ)
      typeScope[impType.typ.parsed] = impType.typ

  for typ in types:
    nameScope = ? nameScope.update(typ.name, typ)
    typeScope[typ.parsed] = typ

  ok((nameScope, typeScope))