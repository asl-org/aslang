## Import source paths: the typed `ImportPath` (relative vs vendor), the
## `VendorRoots` lookup table, and the resolution logic (`toImportPath`
## parses a raw source; `toAbsPath` resolves it to an absolute file
## path). Consumed by the Import line parser in imports.nim.

import strformat, strutils, results

import ../tokenizer/main as tokenizer
import parser
import error

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
    loc: Location
    case kind: ImportPathKind
    of ipkRelative: relativeSource: string
    of ipkVendor: vendorName: string

proc newRelativeImportPath*(relativeSource: string, loc: Location): ImportPath =
  ImportPath(kind: ipkRelative, relativeSource: relativeSource, loc: loc)

proc newVendorImportPath*(vendorName: string, loc: Location): ImportPath =
  ImportPath(kind: ipkVendor, vendorName: vendorName, loc: loc)

proc newImportPath*(literal: StringLiteral): Result[ImportPath, ParserError] =
  ## Converts a raw quoted-string source (the body of an `import "..."`
  ## clause) into a typed ImportPath. Sources starting with `@` are
  ## vendor references; the remainder is validated as an ASL
  ## identifier (head: letter or underscore; tail: letter, digit, or
  ## underscore). Anything else is treated as a relative path —
  ## extension and parent-escape checks happen later in
  ## toAbsPath.
  let source = literal.content
  let loc = literal.loc
  if not source.startsWith("@"):
    ok(newRelativeImportPath(source, loc))
  else:
    let name = source[1..^1]
    if name.len == 0:
      err(newParserError("vendor import path '@' is missing a vendor name", loc))
    elif not (name[0].isAlphaAscii or name[0] == '_'):
      err(newParserError(fmt"vendor name '{name}' must start with a letter or underscore", loc))
    else:
      for c in name[1..^1]:
        if not (c.isAlphaNumeric or c == '_'):
          return err(newParserError(fmt"vendor name '{name}' contains invalid character '{c}' (allowed: letters, digits, underscore)", loc))
      ok(newVendorImportPath(name, loc))

proc kind*(p: ImportPath): ImportPathKind = p.kind
proc loc*(p: ImportPath): Location = p.loc

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

let importPathSpec* = stringLiteralSpec.map(newImportPath)