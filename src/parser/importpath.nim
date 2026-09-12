## Import source paths: the typed `ImportPath` (relative vs vendor), the
## `VendorRoots` lookup table, and the resolution logic (`toImportPath`
## parses a raw source; `toAbsPath` resolves it to an absolute file
## path). Consumed by the Import line parser in imports.nim.

import strformat, strutils, tables, results, os

import ../tokenizer/main as tokenizer
import error

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
