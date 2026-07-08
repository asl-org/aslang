import strformat, strutils, tables, results, hashes, os

import ./tokenizer
import ./combinators
import ./identifiers
import ./funcs
import ./imports
import ./generics
import ./modules

# ============================================================
# Type
# ============================================================

type
  TypeKind* = enum
    tkModule, tkGeneric
  Type* = ref object
    case kind: TypeKind
    of tkModule: module: Module
    of tkGeneric: generic: Generic

proc newType*(module: Module): Type =
  Type(kind: tkModule, module: module)

proc newType*(generic: Generic): Type =
  Type(kind: tkGeneric, generic: generic)

proc kind*(dt: Type): TypeKind = dt.kind
proc public*(dt: Type): bool =
  case dt.kind:
  of tkModule: dt.module.public
  of tkGeneric: dt.generic.public

proc module*(dt: Type): Module =
  assert dt.kind == tkModule,
    fmt"Type.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: Type): Generic =
  assert dt.kind == tkGeneric,
    fmt"Type.generic accessed but kind is {dt.kind}"
  dt.generic

proc name*(definedType: Type): Identifier =
  case definedType.kind:
  of tkModule: definedType.module.name
  of tkGeneric: definedType.generic.name

proc loc*(definedType: Type): Location =
  case definedType.kind:
  of tkModule: definedType.module.loc
  of tkGeneric: definedType.generic.loc

proc asl(definedType: Type, indentWidth: uint32): seq[string] =
  case definedType.kind:
  of tkModule: definedType.module.asl(indentWidth)
  of tkGeneric: definedType.generic.asl(indentWidth)

proc findFunctionDefs*(definedType: Type, name: Identifier, arity: int): Result[seq[FunctionDef], string] =
  case definedType.kind:
  of tkModule: definedType.module.findFunctionDefs(name, arity)
  of tkGeneric: definedType.generic.findFunctionDefs(name, arity)

let typeSpec = oneOf("type_block", [
  moduleSpec.map("module_item",
    proc(v: Module): Type = newType(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): Type = newType(v)),
])

let definedTypeSpec = prefixed(blankLines, typeSpec)

# ============================================================
# File
# ============================================================

type
  FileKind* = enum
    fkAsl, fkAslr
  File* = ref object
    path: string
    types: seq[Type]
    typeIndex: Table[Identifier, int]
    case kind: FileKind
    of fkAsl:
      imports: seq[Import]
      importedNameIndex: Table[Identifier, ImportedType]
    of fkAslr: discard

proc newAslFile*(path: string, imports: seq[Import], types: seq[Type],
    vendorRoots: VendorRoots = initTable[string, string]()): Result[
    File, ParserError] =
  ## Builds an `fkAsl` File: source files written by users, may
  ## carry imports, may not host extern functions in their modules
  ## (those belong in .aslr files). When `vendorRoots` contains a
  ## `"std"` entry, a synthesized `import "@std"` (ikShorthand) is
  ## prepended to the imports seq before the typeIndex build, so
  ## every public defined type from the std vendor target is in
  ## scope without the user typing the line. Compiler-injected
  ## imports use a sentinel `newLocation()` — they have no source
  ## position, and downstream code can't otherwise distinguish them
  ## from a user-written line.

  # asl files cannot host extern functions. Walk every module's
  # function list; reject the first extern found with the extern's
  # own loc so the diagnostic points at the offending decoration.
  for definedType in types:
    case definedType.kind:
    of tkGeneric: discard
    of tkModule:
      for fn in definedType.module.functions:
        case fn.kind:
        of fkUser: discard
        of fkExtern:
          let msg = fmt"asl files cannot contain extern functions; extern functions belong in .aslr files (the runtime interface)"
          return err(newParserError(msg, fn.loc))

  var allImports = imports
  if "std" in vendorRoots:
    let stdImport = ? newImport(newVendorImportPath("std"),
        vendorRoots["std"], newLocation())
    allImports.insert(stdImport, 0)

  var importedNameIndex: Table[Identifier, ImportedType]
  var typeIndex: Table[Identifier, int]

  # Parser-time index build: only ikExplicit imports contribute
  # names to `importedNameIndex`. ikShorthand imports have no names
  # until the resolver expands them via `publicTypes()` (the target
  # file isn't parsed yet at this point). Shorthand-vs-local +
  # shorthand-vs-explicit collisions are caught by
  # validateNoDuplicateBindings in resolver/files.nim.
  for imp in allImports:
    if imp.absPath == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
    case imp.kind:
    of ikShorthand: discard
    of ikExplicit:
      for impType in imp.names:
        if impType.binding in importedNameIndex:
          let prev = importedNameIndex[impType.binding]
          let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
          return err(newParserError(msg, impType.loc))
        importedNameIndex[impType.binding] = impType

  for i, definedType in types:
    if definedType.name in importedNameIndex:
      let prev = importedNameIndex[definedType.name]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    typeIndex[definedType.name] = i
  ok(File(kind: fkAsl, path: path, imports: allImports, types: types,
    typeIndex: typeIndex, importedNameIndex: importedNameIndex))

proc newAslrFile*(path: string, types: seq[Type]): Result[
    File, ParserError] =
  ## Builds an `fkAslr` File: the runtime interface — no imports
  ## (structurally — the variant has no imports field), modules may
  ## host extern functions freely.
  var typeIndex: Table[Identifier, int]
  for i, definedType in types:
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    typeIndex[definedType.name] = i
  ok(File(kind: fkAslr, path: path, types: types,
    typeIndex: typeIndex))

proc newFile*(path: string, imports: seq[Import], types: seq[Type]): Result[
    File, ParserError] =
  ## Unified entry point — dispatches on the file's extension to the
  ## appropriate kind constructor. `.aslr` paths with non-empty
  ## imports are rejected here (the user wrote an import in a
  ## runtime-interface file). Once W7 splits the parser specs the
  ## fkAslr arm never receives imports in practice; this dispatcher
  ## remains the fallback for callers (test helpers, ad-hoc builders)
  ## that go through the unified entry.
  if path.endsWith(".aslr"):
    if imports.len > 0:
      let msg = fmt"{path}: .aslr files cannot contain import statements (they are the runtime interface, not an implementation)"
      return err(newParserError(msg, imports[0].loc))
    newAslrFile(path, types)
  else:
    newAslFile(path, imports, types)

proc kind*(file: File): FileKind = file.kind
proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] =
  assert file.kind == fkAsl,
    fmt"File.imports accessed but kind is {file.kind}"
  file.imports
proc types*(file: File): seq[Type] = file.types
proc hash*(file: File): Hash = file.path.hash
proc `==`*(a, b: File): bool = a.hash == b.hash

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  case file.kind:
  of fkAsl:
    for imp in file.imports:
      lines.add(asl(imp))
    if file.imports.len > 0 and file.types.len > 0:
      lines.add("")
  of fkAslr:
    discard
  for i, dt in file.types:
    if i > 0: lines.add("")
    lines.add(dt.asl(indentWidth))
  lines.join("\n") & "\n"

proc findType*(file: File, name: Identifier): Result[Type, string] =
  ## Locally-defined type lookup. Errors if the name refers to an
  ## imported binding (use `findImportedName` for that) or is unknown.
  if name in file.typeIndex:
    ok(file.types[file.typeIndex[name]])
  else:
    err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")

proc findImportedName*(file: File, name: Identifier): Result[ImportedType, string] =
  ## Imported-binding lookup — the parse-time placeholder pointing at
  ## a name in another file. `fkAslr` files have no imports and always
  ## return an error.
  case file.kind:
  of fkAsl:
    if name in file.importedNameIndex: ok(file.importedNameIndex[name])
    else: err(fmt"{name.loc} type `{name.asl}` is not imported in file `{file.path}`")
  of fkAslr:
    err(fmt"{name.loc} aslr files have no imports")

proc findExportedType*(file: File, name: Identifier): Result[Type, string] =
  let definedType = ? file.findType(name)
  if definedType.public: ok(definedType)
  else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

proc publicTypes*(file: File): seq[Type] =
  ## Returns every public defined type (module or generic) in this
  ## file, preserving declaration order. Used by the resolver to
  ## expand `ikShorthand` Imports — `import "file.asl"` brings the
  ## full public set into the importing file's scope under each
  ## type's original name.
  for definedType in file.types:
    if definedType.public:
      result.add(definedType)

# aslFile: import* (module | generic)*
#
# Parameterized by `vendorRoots` so the parseFn can pass it through
# to `newAslFile`. Each call to `aslFileSpec(roots)` returns a fresh
# Spec whose parseFn captures `roots` in its closure. The default
# closure shape (a `let` Spec) doesn't work here because the
# constructor needs runtime access to the vendor table.
proc aslFileSpec(vendorRoots: VendorRoots): Spec[File] =
  Spec[File](
    name: "asl_file",
    parseFn: proc(parser: Parser): Result[File, ParserError] =
      let imports = ? parser.run(any(importSpec))
      let items = ? parser.run(atLeastOne(definedTypeSpec))
      discard parser.run(blankLines)
      if not parser.done():
        # Force a parse attempt to get a specific error message
        discard ? parser.run(typeSpec)
      newAslFile(parser.filepath, imports, items, vendorRoots)
  )

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
let aslrFileSpec = Spec[File](
  name: "aslr_file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let items = ? parser.run(atLeastOne(definedTypeSpec))
  discard parser.run(blankLines)
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(typeSpec)
  newAslrFile(parser.filepath, items)
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token],
    vendorRoots: VendorRoots = initTable[string, string]()): Result[
    File, string] =
  ## Dispatches on the file's extension. `.asl` paths run through
  ## `aslFileSpec(vendorRoots)` (parses imports + items); `.aslr`
  ## paths run through `aslrFileSpec` (parses items only — no
  ## imports section). Anything else fails early — `resolveImportPath`
  ## rejects non-`.asl`/`.aslr` paths and the CLI rejects non-`.asl`
  ## entry points, so this defensive arm shouldn't fire in practice.
  let (_, _, ext) = filepath.splitFile()
  if ext != ".asl" and ext != ".aslr":
    return err(fmt"{filepath}: unrecognized file extension '{ext}' — expected '.asl' or '.aslr'")
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile =
    if ext == ".asl": parser.run(aslFileSpec(vendorRoots))
    else: parser.run(aslrFileSpec)
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
