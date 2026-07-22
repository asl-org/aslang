## Type / File / App + the public resolve* entry point.

import results, strformat, tables

import ./parser
import module
import generic
import types
import imports

# ResolvedFile
type ResolvedFile* = ref object
  parsed: parser.File
  imports: seq[ResolvedImport]
  types: seq[ResolvedType]
  typeIndex: Table[Identifier, int]

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedType]): ResolvedFile =
  var typeIndex: Table[Identifier, int]
  for id, typ in types:
    assert typ.name notin typeIndex, "duplicate local type detected in the resolved file"
    typeIndex[typ.name] = id
  ResolvedFile(parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedType] = file.types

proc findType*(file: ResolvedFile, name: Identifier): Result[ResolvedType, string] =
  if name notin file.typeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.types[file.typeIndex[name]])

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedModule, string] =
  let typ = ? file.findType(name)
  case typ.kind:
  of rdtkModule: ok(typ.module)
  of rdtkGeneric: err(fmt"{name.loc} expected type `{name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[ResolvedGeneric, string] =
  let typ = ? file.findType(name)
  case typ.kind:
  of rdtkGeneric: ok(typ.generic)
  of rdtkModule: err(fmt"{name.loc} expected type `{name.asl}` to be a generic but found module")
