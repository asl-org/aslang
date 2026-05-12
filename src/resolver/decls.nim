## DefinedType / File / App + the public resolve* entry point.

import results, strformat, tables

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
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType*(module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkModule, module: module)

proc newResolvedDefinedType*(generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkGeneric, generic: generic)

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

proc resolveDefinedType(app: App, file: parser.File, fileScope: FileScope,
    definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, definedType.generic)
    ok(newResolvedDefinedType(resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope,
      definedType.module)
    ok(newResolvedDefinedType(resolvedModule))

# ResolvedFile
type ResolvedFile* = ref object
  path: string
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedDefinedType]
  definedTypeIndex: Table[Identifier, ResolvedDefinedType]

proc newResolvedFile*(path: string, imports: seq[ResolvedImport],
    definedTypes: seq[ResolvedDefinedType]): ResolvedFile =
  var definedTypeIndex: Table[Identifier, ResolvedDefinedType]
  for definedType in definedTypes:
    definedTypeIndex[definedType.name] = definedType

  ResolvedFile(path: path, imports: imports, definedTypes: definedTypes, definedTypeIndex: definedTypeIndex)

proc path*(file: ResolvedFile): string = file.path
proc imports*(file: ResolvedFile): seq[ResolvedImport] = file.imports
proc definedTypes*(file: ResolvedFile): seq[ResolvedDefinedType] = file.definedTypes

proc findModule*(file: ResolvedFile, name: Identifier): Result[ResolvedDefinedType, string] =
  if name notin file.definedTypeIndex:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the file scope")
  else:
    ok(file.definedTypeIndex[name])

proc resolveFile(app: App, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var resolvedDefinedTypes: seq[ResolvedDefinedType]
  for definedType in file.definedTypes:
    let resolvedDefinedType = ? resolveDefinedType(app, file, fileScope,
      definedType)
    resolvedDefinedTypes.add(resolvedDefinedType)

  ok(newResolvedFile(file.path, resolvedImports, resolvedDefinedTypes))

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
