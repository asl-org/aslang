import strformat, strutils, tables, results, hashes, sequtils

import ./tokenizer
import ./error

import ./identifiers
import ./function
import ./imports
import ./modules
import ./types

# ============================================================
# File
# ============================================================

proc validateNoExternFunctions(types: seq[LocalType]): Result[void, ParserError] =
  ## Walks every module's function list; rejects the first extern
  ## found with the extern's own loc so the diagnostic points at
  ## the offending decoration. Asl files cannot host extern
  ## functions — those belong in .aslr files.
  for typ in types:
    case typ.kind:
    of ltkGeneric: discard
    of ltkModule:
      let externFuncs = typ.module.externFunctions
      if externFuncs.len > 0:
        let msg = fmt"asl files cannot contain extern functions; extern functions belong in .aslr files (the runtime interface)"
        return err(newParserError(msg, externFuncs[0].loc))
  ok()

proc insertStdImport(imports: seq[Import], vendors: VendorRoots): Result[seq[Import], ParserError] =
  ## When `vendors` contains a `"std"` entry, prepends a synthesized
  ## `import "@std"` (ikShorthand) so every public defined type from
  ## the std vendor target is in scope without the user typing the
  ## line. Compiler-injected imports use a sentinel `newLocation()` —
  ## they have no source position, and downstream code can't otherwise
  ## distinguish them from a user-written line.
  var augmentedImports: seq[Import]
  if "std" in vendors:
    let stdPath = newVendorImportPath("std")
    let stdImport = ? newImport(stdPath, vendors["std"], newLocation())
    augmentedImports.add(stdImport)
  augmentedImports.add(imports)
  ok(augmentedImports)

proc validateNoSelfImport(imports: seq[Import], path: string): Result[void, ParserError] =
  for imp in imports:
    if imp.absPath == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
  ok()

proc buildImportedTypeNameIndex(imports: seq[Import]): Result[Table[Identifier, ImportedType], ParserError] =
  ## Parser-time index build: only ikExplicit imports contribute
  ## names. ikShorthand imports have no names until the resolver
  ## expands them via `publicTypes()` (the target file isn't parsed
  ## yet at this point). Shorthand-vs-local + shorthand-vs-explicit
  ## collisions are caught by validateNoDuplicateBindings in
  ## resolver/files.nim.
  var index: Table[Identifier, ImportedType]
  for imp in imports:
    case imp.kind:
    of ikShorthand: discard
    of ikExplicit:
      for impType in imp.names:
        if impType.binding in index:
          let prev = index[impType.binding]
          let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
          return err(newParserError(msg, impType.loc))
        index[impType.binding] = impType
  ok(index)

proc buildTypeNameIndex(types: seq[LocalType]): Result[Table[Identifier, int], ParserError] =
  var index: Table[Identifier, int]
  for i, typ in types:
    if typ.name in index:
      let prev = types[index[typ.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, typ.loc))
    index[typ.name] = i
  ok(index)

proc validateTypeNameConflict(importIndex: Table[Identifier, ImportedType], typeIndex: Table[Identifier, int]): Result[void, ParserError] =
  for name in typeIndex.keys:
    if name in importIndex:
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {importIndex[name].loc}"
      return err(newParserError(msg, name.loc))
  ok()

proc validateNoImports(imports: seq[Import]): Result[void, ParserError] =
  if imports.len > 0:
    let msg = fmt"*.aslr files cannot contain import statements (they are the runtime interface, not an implementation)"
    err(newParserError(msg, imports[0].loc))
  else:
    ok()

type
  FileKind* = enum
    fkAsl, fkAslr
  File* = ref object
    path: string
    types: seq[LocalType]
    typeIndex: Table[Identifier, int]
    case kind: FileKind
    of fkAslr: discard
    of fkAsl:
      imports: seq[Import]
      importedNameIndex: Table[Identifier, ImportedType]

proc newAslFile*(path: string, imports: seq[Import], types: seq[LocalType],
    vendorRoots: VendorRoots = initTable[string, string]()): Result[
    File, ParserError] =
  ## Builds an `fkAsl` File: source files written by users, may carry
  ## imports, can not host extern functions in their modules (those
  ## belong in .aslr files). Delegates the extern check, `@std`
  ## auto-injection, self-import rejection, and name-index build to
  ## the validators and builders above.
  ? validateNoExternFunctions(types)
  let allImports = ? insertStdImport(imports, vendorRoots)
  # Validated AFTER @std injection — a vendor registered to point at
  # this very file would otherwise smuggle a self-import past the
  # check.
  ? validateNoSelfImport(allImports, path)
  let importedNameIndex = ? buildImportedTypeNameIndex(imports)
  let typeNameIndex = ? buildTypeNameIndex(types)
  ? validateTypeNameConflict(importedNameIndex, typeNameIndex)
  ok(File(kind: fkAsl, path: path, imports: allImports, types: types, typeIndex: typeNameIndex, importedNameIndex: importedNameIndex))

proc newAslrFile*(path: string, types: seq[LocalType], imports: seq[Import]): Result[File, ParserError] =
  ## Builds an `fkAslr` File: the runtime interface — no imports
  ## (structurally — the variant has no imports field), modules may
  ## host extern functions freely.
  ? validateNoImports(imports)
  var typeIndex = ? buildTypeNameIndex(types)
  ok(File(kind: fkAslr, path: path, types: types, typeIndex: typeIndex))

proc path*(file: File): string = file.path
proc types*(file: File): seq[LocalType] = file.types
proc imports*(file: File): seq[Import] =
  case file.kind:
  of fkAsl: file.imports
  of fkAslr: newSeq[Import]()
proc importPaths*(file: File): seq[string] =
  case file.kind:
  of fkAsl: file.imports.mapIt(it.absPath)
  of fkAslr: newSeq[string]()

proc hash*(file: File): Hash = file.path.hash
proc `==`*(a, b: File): bool = a.hash == b.hash

proc asl*(file: File, indentWidth: uint32): string =
  # Top-level entry point: walks the file at level=0, joins every
  # produced line into a single string. Every child asl call takes
  # (level, indentWidth) and returns seq[string] already properly
  # indented — see Task 18 in tasks.md and the block-asl convention
  # in individual parser files.
  var lines: seq[string]
  let importLines = file.imports.mapIt(it.asl).join("\n")
  if importLines != "": lines.add(importLines)

  let typeLines = file.types.mapIt(it.asl(0, indentWidth).join("\n")).join("\n")
  if typeLines != "": lines.add(typeLines)

  lines.add("") # add an extra new line at the end of file
  lines.join("\n")

proc findType*(file: File, name: Identifier): Result[LocalType, string] =
  ## Locally-defined type lookup. Errors if the name refers to an
  ## imported binding (use `findImportedType` for that) or is unknown.
  if name in file.typeIndex: ok(file.types[file.typeIndex[name]])
  else: err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")

proc findImportedType*(file: File, name: Identifier): Result[ImportedType, string] =
  ## Imported-binding lookup — the parse-time placeholder pointing at
  ## a name in another file. `fkAslr` files have no imports and always
  ## return an error.
  case file.kind:
  of fkAsl:
    if name in file.importedNameIndex: ok(file.importedNameIndex[name])
    else: err(fmt"{name.loc} type `{name.asl}` is not imported in file `{file.path}`")
  of fkAslr:
    err(fmt"{name.loc} aslr files have no imports")

proc findExportedType*(file: File, name: Identifier): Result[LocalType, string] =
  let typ = ? file.findType(name)
  if typ.public: ok(typ)
  else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

proc publicTypes*(file: File): seq[LocalType] =
  file.types.filterIt(it.public)
