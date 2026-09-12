import strformat, strutils, options, sequtils, tables, results, os

import parser

import identifiers

# ImportPath (relative vs vendor), VendorRoots, and the path-resolution
# logic (toImportPath / toAbsPath) were extracted to importpath.nim;
# re-exported so `import imports` and the parser/main barrel still
# surface them.
import importpath
export importpath

# ============================================================
# ImportedType
# ============================================================

type ImportedType* = ref object
  name: Identifier
  alias: Option[Identifier]

proc newImportedType*(name: Identifier, alias: Identifier): ImportedType =
  ImportedType(name: name, alias: some(alias))

proc newImportedType*(name: Identifier): ImportedType =
  ImportedType(name: name, alias: none(Identifier))

proc name*(n: ImportedType): Identifier = n.name
proc loc*(n: ImportedType): Location = n.name.loc
proc binding*(n: ImportedType): Identifier =
  if n.alias.isSome: n.alias.get else: n.name

proc asl*(importedType: ImportedType): string =
  if importedType.alias.isSome:
    fmt"{asl(importedType.name)} as {asl(importedType.alias.get)}"
  else:
    asl(importedType.name)

proc explicitImportedTypeConsumer(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec)
  discard ? parser.expect("as")
  discard ? parser.expect(spaceSpec)
  let alias = ? parser.expect(identifierSpec)
  ok(newImportedType(name, alias))

let explicitImportedTypeSpec = newSpec("explicit imported type", explicitImportedTypeConsumer)

let implicitImportedTypeSpec = map(identifierSpec,
  proc(name: Identifier): ImportedType = newImportedType(name))


let importedTypeSpec* = oneOf("imported type", @[
  explicitImportedTypeSpec,
  implicitImportedTypeSpec,
])

# ============================================================
# Import
# ============================================================


# ============================================================
# VendorRoots
# ============================================================
#
# A vendor name → absolute path table, built by the CLI from
# repeated `--vendor="<name>:<path>"` flags (plus the default
# `std → examples/base.aslr` when not user-supplied). Threaded
# through `parse*` → `aslFileSpec` → `newAslFile` so that auto-
# injected `import "@std"` and any user-written `import "@<name>"`
# resolve via the same lookup.

type VendorRoots* = Table[string, string]

proc toAbsPath(parsedPath: ImportPath, importingFile: string,
    vendorRoots: VendorRoots): Result[string, string] =
  ## Resolves an import path to an absolute file path.
  ##
  ## - `ipkRelative`: resolves the relative source against the
  ##   importing file's directory. Rejects paths that escape to a
  ##   parent directory (normalized so tricks like
  ##   `./sub/../../escape` are caught). The `.asl` / `.aslr`
  ##   suffix is *optional* on the source: if the source ends in
  ##   `.asl` or `.aslr` the resolved path is used as-is; otherwise
  ##   the compiler tries the resolved path as typed, then falls
  ##   back to `<source>.asl` and finally `<source>.aslr`. `.asl`
  ##   is tried before `.aslr` because user code overwhelmingly
  ##   imports other user code; the runtime-interface case is a
  ##   belt-and-braces last attempt (most runtime imports flow
  ##   through `@<vendor>` paths anyway). Only if none of the
  ##   candidates exist is an error raised.
  ## - `ipkVendor`: looks up the vendor name in `vendorRoots` (the
  ##   table populated from `--vendor="<name>:<path>"` CLI flags
  ##   plus the default `std`). The registered target path is
  ##   already absolute. Missing vendor → diagnostic listing the
  ##   known ones.
  case parsedPath.kind:
  of ipkRelative:
    let source = parsedPath.relativeSource
    let (_, _, ext) = source.splitFile()
    let dir = normalizedPath(importingFile.parentDir)
    let baseResolved = normalizedPath((dir / source).absolutePath)
    let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
    if not baseResolved.startsWith(dirPrefix):
      return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
    if ext == ".asl" or ext == ".aslr":
      # Explicit extension — defer file-existence to the loader
      # (matching prior behaviour for typed paths).
      return ok(baseResolved)
    # Extensionless (or unrecognized-extension) source: try the bare
    # path first, then `<source>.asl`, then `<source>.aslr`. Loader
    # emits the natural "file not found" if none exist.
    if fileExists(baseResolved):
      return ok(baseResolved)
    let withAsl = baseResolved & ".asl"
    if fileExists(withAsl):
      return ok(withAsl)
    let withAslr = baseResolved & ".aslr"
    if fileExists(withAslr):
      return ok(withAslr)
    err(fmt"{importingFile}: import path '{source}' not found (also tried '{source}.asl' and '{source}.aslr')")
  of ipkVendor:
    let name = parsedPath.vendorName
    if name in vendorRoots:
      return ok(vendorRoots[name])
    var knownNames: seq[string]
    for vendorName in vendorRoots.keys:
      knownNames.add(vendorName)
    let knownDesc = if knownNames.len == 0: "(no vendors registered)" else: knownNames.join(", ")
    err(fmt"{importingFile}: unknown vendor '@{name}' — known vendors: {knownDesc}")

proc validateTypeNameConflict(importedTypes: seq[ImportedType]): Result[void, ParserError] =
  var nameIndex: Table[Identifier, int]
  for index, importType in importedTypes:
    if importType.name in nameIndex:
      let loc = importedTypes[nameIndex[importType.name]].loc
      let msg = fmt"duplicate import encountered, see previous import at {loc}"
      return err(newParserError(msg, importType.loc))
    nameIndex[importType.name] = index
  ok()

proc validateBindingNameConflict(importedTypes: seq[ImportedType]): Result[void, ParserError] =
  var bindingIndex: Table[Identifier, int]
  for index, importType in importedTypes:
    let binding = if importType.alias.isSome: importType.alias.get else: importType.name
    if binding in bindingIndex:
      let loc = importedTypes[bindingIndex[binding]].loc
      let msg = fmt"duplicate import binding encountered, see previous import at {loc}"
      return err(newParserError(msg, binding.loc))
    else:
      bindingIndex[binding] = index
  ok()

proc validateAbsolutePath(importPath: ImportPath, importingFile: string, vendorRoots: VendorRoots): Result[string, ParserError] =
  let maybePath = toAbsPath(importPath, importingFile, vendorRoots) # initTable[string, string]()
  if maybePath.isOk: ok(maybePath.get)
  else: err(newParserError(maybePath.error, importPath.loc))

type
  ImportKind* = enum
    ikExplicit, ikShorthand
  Import* = ref object
    parsedPath: ImportPath # typed parsed source — either `ipkRelative` or `ipkVendor`
    absPath: string        # absolute path of the imported file; set during BFS in parse*
    loc: Location
    case kind: ImportKind
    of ikExplicit: names: seq[ImportedType]
    of ikShorthand: discard

proc newImport*(names: seq[ImportedType], parsedPath: ImportPath, absPath: string,
    loc: Location): Result[Import, ParserError] =
  ## Explicit form: `import { Name, Name as Alias, ... } from "path"`.
  ## Validates per-import uniqueness of both `name` and `binding`
  ## (binding = alias if present, else name).
  ? validateTypeNameConflict(names)
  ? validateBindingNameConflict(names)
  ok(Import(kind: ikExplicit, names: names, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc newImport*(parsedPath: ImportPath, absPath: string, loc: Location): Result[Import, ParserError] =
  ## Shorthand form: `import "path"` — brings every public defined type
  ## from the target file into scope under its original name. No names
  ## list at parse time; the resolver expands it once the target
  ## file's types are resolved. No uniqueness check here
  ## (there are no names yet); collisions are caught at resolver time.
  ok(Import(kind: ikShorthand, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc kind*(imp: Import): ImportKind = imp.kind
proc names*(imp: Import): seq[ImportedType] =
  assert imp.kind == ikExplicit,
    fmt"Import.names accessed but kind is {imp.kind}"
  imp.names
proc absPath*(imp: Import): string = imp.absPath
proc loc*(imp: Import): Location = imp.loc

proc asl*(imp: Import): string =
  var content: string
  case imp.kind:
  of ikExplicit:
    let inner = imp.names.mapIt(asl(it)).join(", ")
    content.add(fmt"import {{ {inner} }} from ""{asl(imp.parsedPath)}""")
  of ikShorthand:
    content.add(fmt"import ""{asl(imp.parsedPath)}""")
  content


# Explicit form: `import { Name, Name as Alias } from "path"`.
proc explicitImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect("import")
  discard ? parser.expect(spaceSpec)
  let (importedTypes, _)  = ? parser.expect(importedTypeSpec.curlyBracketList(allowEmpty = false))
  discard ? parser.expect(spaceSpec)
  discard ? parser.expect("from")
  discard ? parser.expect(spaceSpec)
  let importPath = ? parser.expect(importPathSpec)
  discard ? parser.expect(emptyLineSpec)
  let absPath = ? validateAbsolutePath(importPath, parser.filepath, initTable[string, string]())
  newImport(importedTypes, importPath, absPath, importKeyword.loc)

let explicitImportLineSpec = newSpec[Import]("explicit import", explicitImportLineConsumer)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver once the
# target file's types are resolved.
proc shorthandImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect("import")
  discard ? parser.expect(spaceSpec)
  let importPath = ? parser.expect(importPathSpec)
  discard ? parser.expect(emptyLineSpec)
  let absPath = ? validateAbsolutePath(importPath, parser.filepath, initTable[string, string]())
  newImport(importPath, absPath, importKeyword.loc)

let shorthandImportLineSpec = newSpec[Import]("implicit import", shorthandImportLineConsumer)

let importLineSpec =
  oneOf("import line", @[
    explicitImportLineSpec,
    shorthandImportLineSpec,
  ])

proc importConsumer(parser: Parser): Result[Import, ParserError] =
  ## Skips leading blank / comment lines, then parses one import line
  ## (either explicit `import { A, B } from "path"` or shorthand
  ## `import "path"`).
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(importLineSpec)

let importSpec* = newSpec[Import]("import", importConsumer)