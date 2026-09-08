import strformat, strutils, options, sequtils, tables, results, os

import ../tokenizer/main as tokenizer

import parser
import error

import identifiers
import literals

# ============================================================
# ImportPath
# ============================================================
#
# The user-typed source of an import — either a relative path
# (`"./foo.asl"`) or a vendor reference (`"@std"`, `"@runtime"`).
# Used as the parsed form of `Import.source` once W3 lands; for now
# it lives standalone and `toImportPath` is the entry point for
# converting a raw quoted-string source into the typed form.

type
  ImportPathKind* = enum
    ipkRelative, ipkVendor
  ImportPath* = ref object
    case kind: ImportPathKind
    of ipkRelative: relativeSource: string
    of ipkVendor: vendorName: string

proc newRelativeImportPath*(relativeSource: string): ImportPath =
  ImportPath(kind: ipkRelative, relativeSource: relativeSource)

proc newVendorImportPath*(vendorName: string): ImportPath =
  ImportPath(kind: ipkVendor, vendorName: vendorName)

proc kind*(p: ImportPath): ImportPathKind = p.kind

proc relativeSource*(p: ImportPath): string =
  assert p.kind == ipkRelative,
    fmt"ImportPath.relativeSource accessed but kind is {p.kind}"
  p.relativeSource

proc vendorName*(p: ImportPath): string =
  assert p.kind == ipkVendor,
    fmt"ImportPath.vendorName accessed but kind is {p.kind}"
  p.vendorName

proc asl*(p: ImportPath): string =
  ## Renders the user-visible form of the import source — what the
  ## user would have typed (or could have typed for compiler-injected
  ## imports).
  case p.kind:
  of ipkRelative: p.relativeSource
  of ipkVendor: fmt"@{p.vendorName}"

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
  discard ? parser.expect(newSpec("as"))
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

proc toImportPath*(source: string, loc: Location): Result[ImportPath, ParserError] =
  ## Converts a raw quoted-string source (the body of an `import "..."`
  ## clause) into a typed ImportPath. Sources starting with `@` are
  ## vendor references; the remainder is validated as an ASL
  ## identifier (head: letter or underscore; tail: letter, digit, or
  ## underscore). Anything else is treated as a relative path —
  ## extension and parent-escape checks happen later in
  ## toAbsPath.
  if not source.startsWith("@"):
    return ok(newRelativeImportPath(source))
  let name = source[1..^1]
  if name.len == 0:
    return err(newParserError("vendor import path '@' is missing a vendor name", loc))
  if not (name[0].isAlphaAscii or name[0] == '_'):
    return err(newParserError(fmt"vendor name '{name}' must start with a letter or underscore", loc))
  for c in name[1..^1]:
    if not (c.isAlphaNumeric or c == '_'):
      return err(newParserError(fmt"vendor name '{name}' contains invalid character '{c}' (allowed: letters, digits, underscore)", loc))
  ok(newVendorImportPath(name))

proc toAbsPath*(parsedPath: ImportPath, importingFile: string,
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

# Explicit form: `import { Name, Name as Alias } from "path"`.
proc explicitImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect(newSpec("import"))
  discard ? parser.expect(spaceSpec)
  let (names, _)  = ? parser.expect(importedTypeSpec.curlyBracketList(allowEmpty = false))
  discard ? parser.expect(spaceSpec)
  discard ? parser.expect(newSpec("from"))
  discard ? parser.expect(spaceSpec)
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let explicitImportLineSpec = newSpec[Import]("explicit import", explicitImportLineConsumer)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver once the
# target file's types are resolved.
proc shorthandImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect(newSpec("import"))
  discard ? parser.expect(spaceSpec.atLeastOne())
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

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