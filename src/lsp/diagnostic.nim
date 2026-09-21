## Compiler error string → LSP diagnostic.
##
## Every layer reports `Result[_, string]`; the strings come in three
## shapes (see plans/plan_lsp.md), tried in order as data:
##
##   <abs path>:<line>:<col> <message>          located
##   cyclic dependency detected: <path> -> ...   first file of the cycle
##   <abs path>: <message>                       file-level
##
## Anything else lands at the top of the compile root. Compiler
## positions are 1-based and rune-counted; LSP's are 0-based UTF-16
## units, which agree with runes across the BMP.
##
## TODO(structured-errors): replace this string parsing once the
## compiler reports structured errors — a `(Location, message,
## related: seq[Location])` value instead of `Result[_, string]` in
## every layer. Then `see previous declaration at <loc>` becomes a
## clickable `relatedInformation` entry, a file can carry more than one
## diagnostic, and nothing here depends on message wording. Deferred
## until the resolver settles (plans/plan_lsp.md W8).

import std/[json, options, strscans, strutils, unicode]

type Diagnostic* = object
  path: string
  line: int       # 0-based
  startCol: int   # 0-based, inclusive
  endCol: int     # 0-based, exclusive
  message: string

proc newDiagnostic(path: string, line: int, startCol: int, endCol: int,
    message: string): Diagnostic =
  Diagnostic(path: path, line: line, startCol: startCol, endCol: endCol,
      message: message)

proc newDiagnostic(path: string, message: string): Diagnostic =
  newDiagnostic(path, 0, 0, 1, message)

proc path*(diagnostic: Diagnostic): string = diagnostic.path
proc line*(diagnostic: Diagnostic): int = diagnostic.line
proc startCol*(diagnostic: Diagnostic): int = diagnostic.startCol
proc endCol*(diagnostic: Diagnostic): int = diagnostic.endCol
proc message*(diagnostic: Diagnostic): string = diagnostic.message

proc located(error: string): Option[Diagnostic] =
  var path, message: string
  var line, col: int
  if scanf(error, "$*:$i:$i $*$.", path, line, col, message):
    some(newDiagnostic(path, line - 1, col - 1, col, message))
  else: none(Diagnostic)

proc cyclic(error: string): Option[Diagnostic] =
  var first, rest: string
  if scanf(error, "cyclic dependency detected: $* -> $*$.", first, rest):
    some(newDiagnostic(first, error))
  else: none(Diagnostic)

proc fileLevel(error: string): Option[Diagnostic] =
  var path, message: string
  if scanf(error, "/$*: $*$.", path, message):
    some(newDiagnostic("/" & path, message))
  else: none(Diagnostic)

# TODO(lsp-error-shapes): add a `<abs path> <message>` shape (no colon
# after the path). The 1 MB limit, invalid UTF-8 and "failed to read
# file" errors use it, so today they fall through to the top of the
# compile root with the path inside the message, instead of landing
# on the file they name.
const ErrorShapes = [located, cyclic, fileLevel]

proc toDiagnostic*(error: string, rootPath: string): Diagnostic =
  var matched = none(Diagnostic)
  for shape in ErrorShapes:
    if matched.isNone: matched = shape(error)
  matched.get(newDiagnostic(rootPath, error))

proc isIdentifierRune(rune: Rune): bool =
  rune.int < 128 and char(rune.int) in IdentChars

proc identifierEnd(lineRunes: seq[Rune], start: int): int =
  var stop = start
  while stop < lineRunes.len and isIdentifierRune(lineRunes[stop]): inc stop
  max(stop, start + 1)

proc widen*(diagnostic: Diagnostic, source: string): Diagnostic =
  ## Extends a one-character range to the identifier under it, so the
  ## squiggle covers `Foo` rather than `F`.
  let lines = source.splitLines
  let lineRunes = if diagnostic.line < lines.len: lines[diagnostic.line].toRunes else: @[]
  newDiagnostic(diagnostic.path, diagnostic.line, diagnostic.startCol,
      identifierEnd(lineRunes, diagnostic.startCol), diagnostic.message)

proc position(line: int, character: int): JsonNode =
  %*{"line": line, "character": character}

proc toJson*(diagnostic: Diagnostic): JsonNode =
  %*{
    "range": {
      "start": position(diagnostic.line, diagnostic.startCol),
      "end": position(diagnostic.line, diagnostic.endCol),
    },
    "severity": 1,
    "source": "asl",
    "message": diagnostic.message,
  }
