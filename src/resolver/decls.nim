## DefinedType / File / App + the public resolve* entry point.

import results, strformat, tables, options

import tokenizer
import parser
import imports
import argtypes
import modules

# ResolvedDefinedType
type
  ResolvedDefinedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType* = ref object
    id: int
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType*(id: int, module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkModule, module: module)

proc newResolvedDefinedType*(id: int, generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkGeneric, generic: generic)

proc kind*(definedType: ResolvedDefinedType): ResolvedDefinedTypeKind = definedType.kind
proc module*(definedType: ResolvedDefinedType): ResolvedModule = definedType.module
proc generic*(definedType: ResolvedDefinedType): ResolvedGeneric = definedType.generic

proc name*(definedType: ResolvedDefinedType): Identifier =
  case definedType.kind:
  of rdtkModule: definedType.module.name
  of rdtkGeneric: definedType.generic.name

proc loc*(definedType: ResolvedDefinedType): Location =
  case definedType.kind:
  of rdtkModule: definedType.module.loc
  of rdtkGeneric: definedType.generic.loc

proc resolveDefinedType(app: App, file: parser.File, fileScope: FileScope, id: int, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, definedType.generic)
    ok(newResolvedDefinedType(id, resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, definedType.module)
    ok(newResolvedDefinedType(id, resolvedModule))

# ResolvedFile
type ResolvedFile* = ref object
  id: int
  parsed: parser.File
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedDefinedType]
  definedTypeIndex: Table[Identifier, int]

proc newResolvedFile*(id: int, parsed: parser.File, imports: seq[ResolvedImport], definedTypes: seq[ResolvedDefinedType]): ResolvedFile =
  var definedTypeIndex: Table[Identifier, int]
  for id, definedType in definedTypes:
    definedTypeIndex[definedType.name] = id
  ResolvedFile(id: id, parsed: parsed, imports: imports, definedTypes: definedTypes, definedTypeIndex: definedTypeIndex)

proc path*(file: ResolvedFile): string = file.parsed.path
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc definedTypes*(file: ResolvedFile): seq[ResolvedDefinedType] = file.definedTypes

proc findDefinedType(file: ResolvedFile, name: Identifier): Result[ResolvedDefinedType, string] =
  if name notin file.definedTypeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.definedTypes[file.definedTypeIndex[name]])

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedModule, string] =
  let definedType = ? file.findDefinedType(name)
  case definedType.kind:
  of rdtkModule: ok(definedType.module)
  of rdtkGeneric: err(fmt"{name.loc} expected type `{name.asl}` to be a module but found generic")

proc findGeneric*(file: ResolvedFile, name: Identifier): Result[ResolvedGeneric, string] =
  let definedType = ? file.findDefinedType(name)
  case definedType.kind:
  of rdtkGeneric: ok(definedType.generic)
  of rdtkModule: err(fmt"{name.loc} expected type `{name.asl}` to be a generic but found module")

proc resolveFile(app: App, id: int, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var resolvedDefinedTypes: seq[ResolvedDefinedType]
  for id, definedType in file.definedTypes:
    let resolvedDefinedType = ? resolveDefinedType(app, file, fileScope, id, definedType)
    resolvedDefinedTypes.add(resolvedDefinedType)

  ok(newResolvedFile(id, file, resolvedImports, resolvedDefinedTypes))

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
