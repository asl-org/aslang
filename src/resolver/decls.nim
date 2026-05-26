## DefinedType / File / App + the public resolve* entry point.

import results, strformat, tables, options

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
    id: int
    case kind: ResolvedTypeKind
    of rtkModule: module: ResolvedModule
    of rtkGeneric: generic: ResolvedGeneric

proc newResolvedType*(id: int, module: ResolvedModule): ResolvedType =
  ResolvedType(id: id, kind: rtkModule, module: module)

proc newResolvedType*(id: int, generic: ResolvedGeneric): ResolvedType =
  ResolvedType(id: id, kind: rtkGeneric, generic: generic)

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

proc resolveType(app: App, file: parser.File, fileScope: FileScope, id: int, aslType: DefinedType): Result[ResolvedType, string] =
  case aslType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, aslType.generic)
    ok(newResolvedType(id, resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, aslType.module)
    ok(newResolvedType(id, resolvedModule))

# ResolvedFile
type ResolvedFile* = ref object
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedType]
  definedTypeIndex: Table[Identifier, int]

proc newResolvedFile*(id: int, parsed: parser.File, imports: seq[ResolvedImport], definedTypes: seq[ResolvedType]): ResolvedFile =
  var definedTypeIndex: Table[Identifier, int]
  for id, definedType in definedTypes:
    definedTypeIndex[definedType.name] = id
  ResolvedFile(id: id, parsed: parsed, imports: imports, definedTypes: definedTypes, definedTypeIndex: definedTypeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc definedTypes*(file: ResolvedFile): seq[ResolvedType] = file.definedTypes

proc findType(file: ResolvedFile, name: Identifier): Result[ResolvedType, string] =
  if name notin file.definedTypeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.definedTypes[file.definedTypeIndex[name]])

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedModule, string] =
  let resolvedType = ? file.findType(name)
  case resolvedType.kind:
  of rtkModule: ok(resolvedType.module)
  of rtkGeneric: err(fmt"{name.loc} expected type `{name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[ResolvedGeneric, string] =
  let resolvedType = ? file.findType(name)
  case resolvedType.kind:
  of rtkGeneric: ok(resolvedType.generic)
  of rtkModule: err(fmt"{name.loc} expected type `{name.asl}` to be a generic but found module")

proc resolveFile(app: App, id: int, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var resolvedAslTypes: seq[ResolvedType]
  for id, aslType in file.definedTypes:
    let resolvedAslType = ? resolveType(app, file, fileScope, id, aslType)
    resolvedAslTypes.add(resolvedAslType)

  ok(newResolvedFile(id, file, resolvedImports, resolvedAslTypes))

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[parser.File, int]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  var fileIndex: Table[parser.File, int]
  for id, file in files:
    fileIndex[file.parsed] = id
  ResolvedApp(files: files, fileIndex: fileIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, file: parser.File): Option[ResolvedFile] =
  if file notin app.fileIndex: none(ResolvedFile)
  else: some(app.files[app.fileIndex[file]])

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for id, file in app.files:
    let maybeResolvedFile = resolveFile(app, id, file)
    if maybeResolvedFile.isErr:
      return err(fmt"{file.path}:{maybeResolvedFile.error}")
    else:
      resolvedFiles.add(maybeResolvedFile.get)
  ok(newResolvedApp(resolvedFiles))
