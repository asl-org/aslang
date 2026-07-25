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
  typeIndex: Table[parser.Type, int]

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedType]): ResolvedFile =
  var typeIndex: Table[parser.Type, int]
  for id, typ in types:
    assert typ.parsed notin typeIndex, "duplicate local type detected in the resolved file"
    typeIndex[typ.parsed] = id
  ResolvedFile(parsed: parsed, imports: imports, types: types, typeIndex: typeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedType] = file.types

proc findType*(file: ResolvedFile, typ: parser.Type, loc: Location): Result[ResolvedType, string] =
  if typ notin file.typeIndex:
    err(fmt"{loc} type `{typ.name.asl}` does not exist in the file scope")
  else:
    ok(file.types[file.typeIndex[typ]])

proc findModule*(file: ResolvedFile, typ: Module, loc: Location): Result[ResolvedModule, string] =
  let resolvedType = ? file.findType(newType(typ), loc)
  case resolvedType.kind:
  of rdtkModule: ok(resolvedType.module)
  of rdtkGeneric: err(fmt"{loc} expected type `{typ.name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, typ: Generic, loc: Location): Result[ResolvedGeneric, string] =
  let resolvedType = ? file.findType(newType(typ), loc)
  case resolvedType.kind:
  of rdtkGeneric: ok(resolvedType.generic)
  of rdtkModule: err(fmt"{loc} expected type `{typ.name.asl}` to be a generic but found module")
