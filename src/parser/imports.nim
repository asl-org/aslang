import strformat, strutils, options, tables, results, os

import ./tokenizer
import ./combinators
import ./identifiers
import ./literals

# ============================================================
# ImportPath
# ============================================================
#
# The user-typed source of an import — either a relative path
# (`"./foo.asl"`) or a vendor reference (`"@std"`, `"@runtime"`).
# Used as the parsed form of `Import.source` once W3 lands; for now
# it lives standalone and `parseImportPath` is the entry point for
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

proc parseImportPath*(source: string, loc: Location): Result[ImportPath, ParserError] =
  ## Converts a raw quoted-string source (the body of an `import "..."`
  ## clause) into a typed ImportPath. Sources starting with `@` are
  ## vendor references; the remainder is validated as an ASL
  ## identifier (head: letter or underscore; tail: letter, digit, or
  ## underscore). Anything else is treated as a relative path —
  ## extension and parent-escape checks happen later in
  ## resolveImportPath.
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
  loc: Location

proc name*(n: ImportedType): Identifier = n.name
proc alias*(n: ImportedType): Option[Identifier] = n.alias
proc loc*(n: ImportedType): Location = n.loc
proc binding*(n: ImportedType): Identifier =
  if n.alias.isSome: n.alias.get else: n.name

proc newImportedType*(name: Identifier, alias: Option[Identifier],
    loc: Location): ImportedType =
  ImportedType(name: name, alias: alias, loc: loc)

proc asl*(importedType: ImportedType): string =
  if importedType.alias.isSome:
    fmt"{asl(importedType.name)} as {asl(importedType.alias.get)}"
  else:
    asl(importedType.name)

# import { Name, Name } from "path"
# identifier ("as" identifier)?
let importedTypeSpec* = Spec[ImportedType](
  name: "import_name",
  parseFn: proc(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(atLeastOne(spaceSpec))
  if maybeAs.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  discard ? parser.run(atLeastOne(spaceSpec))
  let alias = ? parser.run(identifierSpec)
  ok(newImportedType(name, some(alias), name.loc))
)

# ============================================================
# Import
# ============================================================

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
  var nameIndex: Table[Identifier, int]
  var bindingIndex: Table[Identifier, int]
  for index, importType in names:
    if importType.name in nameIndex:
      let prev = names[nameIndex[importType.name]]
      let msg = fmt"duplicate import encountered, see previous import at {prev.loc}"
      return err(newParserError(msg, importType.loc))
    else:
      nameIndex[importType.name] = index

    let binding = if importType.alias.isSome: importType.alias.get else: importType.name
    if binding in bindingIndex:
      let prev = names[bindingIndex[binding]]
      let msg = fmt"duplicate import binding encountered, see previous import at {prev.loc}"
      return err(newParserError(msg, binding.loc))
    else:
      bindingIndex[binding] = index

  ok(Import(kind: ikExplicit, names: names, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc newImport*(parsedPath: ImportPath, absPath: string, loc: Location): Result[Import, ParserError] =
  ## Shorthand form: `import "path"` — brings every public defined type
  ## from the target file into scope under its original name. No names
  ## list at parse time; the resolver expands via `publicTypes()` once
  ## the target file's parser AST is in hand. No uniqueness check here
  ## (there are no names yet); collisions are caught at resolver time.
  ok(Import(kind: ikShorthand, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc kind*(imp: Import): ImportKind = imp.kind
proc names*(imp: Import): seq[ImportedType] =
  assert imp.kind == ikExplicit,
    fmt"Import.names accessed but kind is {imp.kind}"
  imp.names
proc parsedPath*(imp: Import): ImportPath = imp.parsedPath
proc absPath*(imp: Import): string = imp.absPath
proc loc*(imp: Import): Location = imp.loc

proc asl*(imp: Import): string =
  case imp.kind:
  of ikExplicit:
    result = "import { "
    for i, name in imp.names:
      if i > 0: result.add(", ")
      result.add(asl(name))
    result.add(fmt" }} from ""{asl(imp.parsedPath)}""")
  of ikShorthand:
    result = fmt"import ""{asl(imp.parsedPath)}"""

proc resolveImportPath*(parsedPath: ImportPath, importingFile: string,
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
let explicitImportLineSpec* = Spec[Import](
  name: "explicit_import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importedTypeSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(atLeastOne(spaceSpec))
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  let parsedPath = ? parseImportPath(source.value, source.loc)
  let maybePath = resolveImportPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver in W5 via
# `publicTypes()` once the target file's parser AST is available.
let shorthandImportLineSpec* = Spec[Import](
  name: "shorthand_import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  let parsedPath = ? parseImportPath(source.value, source.loc)
  let maybePath = resolveImportPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

# Try explicit first — the `{` after `import ` disambiguates
# immediately; shorthand backtracks cleanly once explicit fails.
let importLineSpec* = oneOf("import_line", [
  explicitImportLineSpec,
  shorthandImportLineSpec,
])

let importBlockSpec* = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)
