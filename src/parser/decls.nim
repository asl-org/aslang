import strformat, strutils, tables, results, hashes

import tokenizer
import combinators
import helpers
import identifiers
import funcDefs
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

proc asl(definedType: DefinedType, indentWidth: uint32): seq[string] =
  case definedType.kind:
  of dtkModule: definedType.module.asl(indentWidth)
  of dtkGeneric: definedType.generic.asl(indentWidth)

proc findFunctionDefs*(definedType: DefinedType, name: Identifier, arity: int): Result[seq[FunctionDefinition], string] =
  case definedType.kind:
  of dtkModule: definedType.module.findFunctionDefs(name, arity)
  of dtkGeneric: definedType.generic.findFunctionDefs(name, arity)

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

# TODO(vendor): split File into a tagged union — `fkAsl { imports:
# seq[Import] }` and `fkAslb { discard }`. Aslb files are the runtime
# interface: they may contain modules with extern functions but
# structurally cannot have imports. Asl files may have imports but
# their modules cannot contain extern functions (validated at
# construction). The unified `newFile` splits into `newAslFile` /
# `newAslbFile`. See W6 in plans/how-is-claude-parsed-whistle.md.
type File* = ref object
  path: string
  imports: seq[Import]
  definedTypes: seq[DefinedType]
  types: seq[Type]
  typeIndex: Table[Identifier, int]

# TODO(vendor): once `File` is split (W6), this becomes `newAslFile`.
# Two additions:
#   - W8: walk every module in definedTypes; reject if any contains
#     an extern function (asl files cannot host extern functions —
#     those belong in .aslb).
#   - W10: take `vendorRoots: VendorRoots`; if "std" in vendorRoots,
#     prepend a synthesized ikShorthand `import "@std"` to imports
#     before the typeIndex build.
# A sibling `newAslbFile(path, definedTypes)` handles fkAslb files —
# no imports, no vendorRoots, modules may contain extern functions.
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

  # Parser-time typeIndex build: only ikExplicit imports contribute
  # names here. ikShorthand imports have no names until the resolver
  # expands them via `publicTypes()` (the target file isn't parsed
  # yet at this point). Shorthand-vs-local + shorthand-vs-explicit
  # collisions are caught by validateNoDuplicateBindings in
  # resolver/files.nim.
  for imp in imports:
    if imp.path == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
    case imp.kind:
    of ikShorthand: discard
    of ikExplicit:
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
      # echo path, " ", definedType.name.asl
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(path: path, imports: imports, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc definedTypes*(file: File): seq[DefinedType] = file.definedTypes
proc types*(file: File): seq[Type] = file.types
proc hash*(file: File): Hash = file.path.hash
proc `==`*(a, b: File): bool = a.hash == b.hash

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and file.definedTypes.len > 0:
    lines.add("")
  for i, dt in file.definedTypes:
    if i > 0: lines.add("")
    lines.add(dt.asl(indentWidth))
  lines.join("\n") & "\n"

proc findTypeId(file: File, name: Identifier): Result[int, string] =
  if name in file.typeIndex: ok(file.typeIndex[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findType*(file: File, name: Identifier): Result[Type, string] =
  let id = ? file.findTypeId(name)
  ok(file.types[id])

proc findExportedType*(file: File, name: Identifier): Result[DefinedType, string] =
  let aslType = ? file.findType(name)
  case aslType.kind:
  of tkImported:
    err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")
  of tkDefined:
    let definedType = aslType.definedType
    if definedType.public: ok(definedType)
    else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

proc publicTypes*(file: File): seq[DefinedType] =
  ## Returns every public defined type (module or generic) in this
  ## file, preserving declaration order. Used by the resolver to
  ## expand `ikShorthand` Imports — `import "file.asl"` brings the
  ## full public set into the importing file's scope under each
  ## type's original name.
  for definedType in file.definedTypes:
    if definedType.public:
      result.add(definedType)

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
    err(fmt"{maybeFile.error}")
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
  else: err(fmt"file '{path}' does not exist")

proc findFile*(app: App, path: string): Result[File, string] =
  let id = ? app.findFileId(path)
  ok(app.files[id])
