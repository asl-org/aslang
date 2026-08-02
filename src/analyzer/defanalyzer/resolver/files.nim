## Type / File / App + the public resolve* entry point.

import results, sequtils, strformat, tables

import ./parser
import filecontext
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
  scope: FileContext

proc newResolvedFile*(parsed: parser.File, imports: seq[ResolvedImport], types: seq[ResolvedType], scope: FileContext): ResolvedFile =
  var typeIndex: Table[parser.Type, int]
  for id, typ in types:
    assert typ.parsed notin typeIndex, "duplicate local type detected in the resolved file"
    typeIndex[typ.parsed] = id
  ResolvedFile(parsed: parsed, imports: imports, types: types, typeIndex: typeIndex, scope: scope)

proc path*(file: ResolvedFile): string = file.parsed.path
proc parsed*(file: ResolvedFile): parser.File = file.parsed
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc types*(file: ResolvedFile): seq[ResolvedType] = file.types
proc scope*(file: ResolvedFile): FileContext = file.scope
proc modules*(file: ResolvedFile): seq[ResolvedModule] =
  file.types.filterIt(it.kind == rtkModule).mapIt(it.module)

proc findType*(file: ResolvedFile, typ: parser.Type, loc: Location): Result[ResolvedType, string] =
  if typ notin file.typeIndex:
    err(fmt"{loc} type `{typ.name.asl}` does not exist in the file scope")
  else:
    ok(file.types[file.typeIndex[typ]])

proc findModule*(file: ResolvedFile, typ: Module, loc: Location): Result[ResolvedModule, string] =
  let resolvedType = ? file.findType(newType(typ), loc)
  case resolvedType.kind:
  of rtkModule: ok(resolvedType.module)
  of rtkGeneric: err(fmt"{loc} expected type `{typ.name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, typ: Generic, loc: Location): Result[ResolvedGeneric, string] =
  let resolvedType = ? file.findType(newType(typ), loc)
  case resolvedType.kind:
  of rtkGeneric: ok(resolvedType.generic)
  of rtkModule: err(fmt"{loc} expected type `{typ.name.asl}` to be a generic but found module")
