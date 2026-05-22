## DefinedType / File / App + the public resolve* entry point.

import results, strformat, tables

import tokenizer
import parser
import imports
import argtypes
import modules

# ResolvedType
type
  ResolvedTypeKind* = enum
    rtkModule, rtkGeneric
  ResolvedType* = ref object
    case kind: ResolvedTypeKind
    of rtkModule: module: ResolvedModule
    of rtkGeneric: generic: ResolvedGeneric

proc newResolvedType*(module: ResolvedModule): ResolvedType =
  ResolvedType(kind: rtkModule, module: module)

proc newResolvedType*(generic: ResolvedGeneric): ResolvedType =
  ResolvedType(kind: rtkGeneric, generic: generic)

proc kind*(aslType: ResolvedType): ResolvedTypeKind = aslType.kind
proc module*(aslType: ResolvedType): ResolvedModule = aslType.module
proc generic*(aslType: ResolvedType): ResolvedGeneric = aslType.generic

proc name*(aslType: ResolvedType): Identifier =
  case aslType.kind:
  of rtkModule: aslType.module.name
  of rtkGeneric: aslType.generic.name

proc loc*(aslType: ResolvedType): Location =
  case aslType.kind:
  of rtkModule: aslType.module.loc
  of rtkGeneric: aslType.generic.loc

proc resolveType(app: App, file: parser.File, fileScope: FileScope,
    aslType: DefinedType): Result[ResolvedType, string] =
  case aslType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, aslType.generic)
    ok(newResolvedType(resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope,
      aslType.module)
    ok(newResolvedType(resolvedModule))

# ResolvedFile
type ResolvedFile* = ref object
  path: string
  imports: seq[ResolvedImport]
  aslTypes: seq[ResolvedType]
  aslTypeIndex: Table[Identifier, ResolvedType]

proc newResolvedFile*(path: string, imports: seq[ResolvedImport],
    aslTypes: seq[ResolvedType]): ResolvedFile =
  var aslTypeIndex: Table[Identifier, ResolvedType]
  for aslType in aslTypes:
    aslTypeIndex[aslType.name] = aslType

  ResolvedFile(path: path, imports: imports, aslTypes: aslTypes, aslTypeIndex: aslTypeIndex)

proc path*(file: ResolvedFile): string = file.path
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc aslTypes*(file: ResolvedFile): seq[ResolvedType] = file.aslTypes

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedType, string] =
  if name notin file.aslTypeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.aslTypeIndex[name])

proc resolveFile(app: App, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.aslType

  var resolvedAslTypes: seq[ResolvedType]
  for aslType in file.definedTypes:
    let resolvedAslType = ? resolveType(app, file, fileScope,
      aslType)
    resolvedAslTypes.add(resolvedAslType)

  ok(newResolvedFile(file.path, resolvedImports, resolvedAslTypes))

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  ResolvedApp(files: files)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let maybeResolvedFile = resolveFile(app, file)
    if maybeResolvedFile.isErr:
      return err(fmt"{file.path}:{maybeResolvedFile.error}")
    else:
      resolvedFiles.add(maybeResolvedFile.get)
  ok(newResolvedApp(resolvedFiles))
