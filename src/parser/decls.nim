import strformat, strutils, tables, results

import tokenizer
import combinators
import helpers
import identifiers
import imports
import generics
import modules

# ============================================================
# DefinedType
# ============================================================

type
  DefinedTypeKind* = enum
    dtkModule, dtkGeneric
  DefinedType* = ref object
    case kind: DefinedTypeKind
    of dtkModule: module: Module
    of dtkGeneric: generic: Generic

proc newDefinedType*(module: Module): DefinedType =
  DefinedType(kind: dtkModule, module: module)

proc newDefinedType*(generic: Generic): DefinedType =
  DefinedType(kind: dtkGeneric, generic: generic)

proc kind*(dt: DefinedType): DefinedTypeKind = dt.kind
proc public*(dt: DefinedType): bool =
  case dt.kind:
  of dtkModule: dt.module.public
  of dtkGeneric: dt.generic.public

proc module*(dt: DefinedType): Module =
  assert dt.kind == dtkModule,
    fmt"DefinedType.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: DefinedType): Generic =
  assert dt.kind == dtkGeneric,
    fmt"DefinedType.generic accessed but kind is {dt.kind}"
  dt.generic

proc name*(definedType: DefinedType): Identifier =
  case definedType.kind:
  of dtkModule: definedType.module.name
  of dtkGeneric: definedType.generic.name

proc loc*(definedType: DefinedType): Location =
  case definedType.kind:
  of dtkModule: definedType.module.loc
  of dtkGeneric: definedType.generic.loc

let typeSpec = oneOf("type_block", [
  moduleSpec.map("module_item",
    proc(v: Module): DefinedType = newDefinedType(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): DefinedType = newDefinedType(v)),
])

let definedTypeBlockSpec = Spec[DefinedType](
  name: "type_block_block",
  parseFn: proc(parser: Parser): Result[DefinedType, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let item = ? parser.run(typeSpec)
  ok(item)
)

# ============================================================
# Type (umbrella over imported and defined types)
# ============================================================

type
  TypeKind* = enum
    tkImported, tkDefined
  Type* = ref object
    case kind: TypeKind
    of tkImported: imported: ImportedType
    of tkDefined: definedType: DefinedType

proc newType(imported: ImportedType): Type =
  Type(kind: tkImported, imported: imported)

proc newType(definedType: DefinedType): Type =
  Type(kind: tkDefined, definedType: definedType)

proc kind*(typ: Type): TypeKind = typ.kind

proc imported*(typ: Type): ImportedType =
  assert typ.kind == tkImported,
    fmt"Type.imported accessed but kind is {typ.kind}"
  typ.imported

proc definedType*(typ: Type): DefinedType =
  assert typ.kind == tkDefined,
    fmt"Type.definedType accessed but kind is {typ.kind}"
  typ.definedType

proc loc*(typ: Type): Location =
  case typ.kind:
  of tkImported: typ.imported.loc
  of tkDefined: typ.definedType.loc

# ============================================================
# File
# ============================================================

type File* = ref object
  path: string
  imports: seq[Import]
  definedTypes: seq[DefinedType]
  types: seq[Type]
  typeIndex: Table[Identifier, int]

proc newFile*(path: string, imports: seq[Import], definedTypes: seq[DefinedType]): Result[
    File, ParserError] =
  # TODO: Ensure that same file is not used in multiple import statements
  # var importedFileSet: Hashset[string]
  # for imp in imports:
  #   if imp.path in importedFileSet:
  #     return err(newParserError("", imp.loc))
  #   importedFileSet.incl(imp.path)

  var typeIndex: Table[Identifier, int]
  var types: seq[Type]

  for imp in imports:
    if imp.path == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
    for impType in imp.names:
      if impType.binding in typeIndex:
        let prev = types[typeIndex[impType.binding]]
        let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
        return err(newParserError(msg, impType.loc))
      typeIndex[impType.binding] = types.len
      types.add(newType(impType))

  for definedType in definedTypes:
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    else:
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(path: path, imports: imports, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc definedTypes*(file: File): seq[DefinedType] = file.definedTypes
proc types*(file: File): seq[Type] = file.types

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and file.definedTypes.len > 0:
    lines.add("")
  for i, dt in file.definedTypes:
    if i > 0: lines.add("")
    case dt.kind:
    of dtkModule:
      for line in asl(dt.module, indentWidth):
        lines.add(line)
    of dtkGeneric:
      for line in asl(dt.generic, indentWidth):
        lines.add(line)
  lines.join("\n") & "\n"

proc findTypeId*(file: File, name: Identifier): Result[int, string] =
  if name in file.typeIndex: ok(file.typeIndex[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findType*(file: File, name: Identifier): Result[Type, string] =
  let id = ? file.findTypeId(name)
  ok(file.types[id])

proc findExportedTypeId*(file: File, name: Identifier): Result[int, string] =
  let id = ? file.findTypeId(name)
  let aslType = file.types[id]
  case aslType.kind:
  of tkImported: err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")
  of tkDefined:
    let definedType = aslType.definedType
    if definedType.public: ok(id)
    else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

proc findExportedType*(file: File, name: Identifier): Result[DefinedType, string] =
  let id = ? file.findTypeId(name)
  let aslType = file.types[id]
  case aslType.kind:
  of tkImported: err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")
  of tkDefined:
    let definedType = aslType.definedType
    if definedType.public: ok(definedType)
    else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

# file: import* (module | generic)*
let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let imports = ? parser.run(any(importBlockSpec))
  let items = ? parser.run(atLeastOne(definedTypeBlockSpec))
  discard parser.run(any(ignorableLineSpec))
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(typeSpec)
  newFile(parser.filepath, imports, items)
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)

# ============================================================
# App
# ============================================================

type App* = ref object
  files: seq[File]
  fileIndex: Table[string, int] # absolute path -> index in files

proc newApp*(files: seq[File]): App =
  var fileIndex: Table[string, int]
  for i, f in files:
    fileIndex[f.path] = i
  App(files: files, fileIndex: fileIndex)

proc files*(app: App): seq[File] = app.files

proc findFileId*(app: App, path: string): Result[int, string] =
  if path in app.fileIndex: ok(app.fileIndex[path])
  else: err(fmt"file '{path}' does not exists")

proc findFile*(app: App, path: string): Result[File, string] =
  let id = ? app.findFileId(path)
  ok(app.files[id])
