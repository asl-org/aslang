import strformat, strutils, tables, results, hashes, os

import ./tokenizer
import ./combinators
import ./identifiers
import ./funcs
import ./imports
import ./generics
import ./modules

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

let definedTypeBlockSpec = prefixed(blankLines, typeSpec)

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

type
  FileKind* = enum
    fkAsl, fkAslr
  File* = ref object
    path: string
    definedTypes: seq[DefinedType]
    types: seq[Type]
    typeIndex: Table[Identifier, int]
    case kind: FileKind
    of fkAsl: imports: seq[Import]
    of fkAslr: discard

proc newAslFile*(path: string, imports: seq[Import], definedTypes: seq[DefinedType],
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
  for definedType in definedTypes:
    case definedType.kind:
    of dtkGeneric: discard
    of dtkModule:
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

  var typeIndex: Table[Identifier, int]
  var types: seq[Type]

  # Parser-time typeIndex build: only ikExplicit imports contribute
  # names here. ikShorthand imports have no names until the resolver
  # expands them via `publicTypes()` (the target file isn't parsed
  # yet at this point). Shorthand-vs-local + shorthand-vs-explicit
  # collisions are caught by validateNoDuplicateBindings in
  # resolver/files.nim.
  for imp in allImports:
    if imp.absPath == path:
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
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(kind: fkAsl, path: path, imports: allImports, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc newAslrFile*(path: string, definedTypes: seq[DefinedType]): Result[
    File, ParserError] =
  ## Builds an `fkAslr` File: the runtime interface — no imports
  ## (structurally — the variant has no imports field), modules may
  ## host extern functions freely.
  var typeIndex: Table[Identifier, int]
  var types: seq[Type]
  for definedType in definedTypes:
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    else:
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(kind: fkAslr, path: path, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc newFile*(path: string, imports: seq[Import], definedTypes: seq[DefinedType]): Result[
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
    newAslrFile(path, definedTypes)
  else:
    newAslFile(path, imports, definedTypes)

proc kind*(file: File): FileKind = file.kind
proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] =
  assert file.kind == fkAsl,
    fmt"File.imports accessed but kind is {file.kind}"
  file.imports
proc definedTypes*(file: File): seq[DefinedType] = file.definedTypes
proc types*(file: File): seq[Type] = file.types
proc hash*(file: File): Hash = file.path.hash
proc `==`*(a, b: File): bool = a.hash == b.hash

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  case file.kind:
  of fkAsl:
    for imp in file.imports:
      lines.add(asl(imp))
    if file.imports.len > 0 and file.definedTypes.len > 0:
      lines.add("")
  of fkAslr:
    discard
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
      let imports = ? parser.run(any(importBlockSpec))
      let items = ? parser.run(atLeastOne(definedTypeBlockSpec))
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
  let items = ? parser.run(atLeastOne(definedTypeBlockSpec))
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
