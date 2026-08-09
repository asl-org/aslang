## LocalType / File / App + the public resolve* entry point.

import sequtils, strformat, tables

import parser
import module
import generic
import types
import imports

# ResolvedFile
type ResolvedFile* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  types: seq[ResolvedLocalType]
  typeIndex: Table[parser.LocalType, int]

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedLocalType]): ResolvedFile =
  var typeIndex: Table[parser.LocalType, int]
  for id, typ in types:
    assert(typ.parsed notin typeIndex, fmt"[BUG] - {typ.loc} duplicate local type `{typ.name.asl}` in the resolved file")
    typeIndex[typ.parsed] = id
  ResolvedFile(parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedLocalType] = file.types
proc modules*(file: ResolvedFile): seq[ResolvedModule] =
  file.types.filterIt(it.kind == rltkModule).mapIt(it.module)

# Identity lookups — every key handed to these was bound by the
# resolver against this same file, so a miss (or a kind mismatch) is
# a compiler bug, never a user error.
proc findType*(file: ResolvedFile, typ: parser.LocalType): ResolvedLocalType =
  assert(typ in file.typeIndex, fmt"[BUG] - {typ.loc} type `{typ.name.asl}` missing from the resolved file")
  file.types[file.typeIndex[typ]]

proc findModule*(file: ResolvedFile, typ: Module): ResolvedModule =
  let resolvedType = file.findType(newLocalType(typ))
  assert(resolvedType.kind == rltkModule, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a module by the resolver")
  resolvedType.module

proc findGeneric*(file: ResolvedFile, typ: Generic): ResolvedGeneric =
  let resolvedType = file.findType(newLocalType(typ))
  assert(resolvedType.kind == rltkGeneric, fmt"[BUG] - {typ.loc} `{typ.name.asl}` was bound as a generic by the resolver")
  resolvedType.generic

proc importedBindings(file: ResolvedFile): seq[ResolvedImportedType] =
  var bindings: seq[ResolvedImportedType]
  for imp in file.imports:
    bindings.add(imp.importedTypes)
  bindings

proc findGenericInScope*(file: ResolvedFile, typ: Generic): ResolvedGeneric =
  ## Identity lookup spanning the file's OWN types AND its import
  ## bindings — everything this file's scope can see. Identity keys
  ## (hash-by-loc) make it alias-immune: the file may import the
  ## generic under a different binding name. Serves the constraint
  ## hop: a module's requirement generic is always in its defining
  ## file's scope (the file referenced it to define the module), so
  ## a miss is a compiler bug.
  let parsed = newLocalType(typ)
  if parsed in file.typeIndex:
    return file.findGeneric(typ)
  for impType in file.importedBindings:
    if impType.typ == parsed:
      return impType.resolvedType.generic
  assert(false, fmt"[BUG] - {typ.loc} generic `{typ.name.asl}` is not in the scope of file `{file.path}`")
