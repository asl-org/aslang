import strformat, strutils, unicode, results, options, sets, os

# parser.nim (Parser + Spec[T] + oneOf / any / optional / ...) holds the
# combinator scaffolding. It is re-exported so the parser tests can drive
# the machinery (newParser, newSpec, expect, …) through the `parser/main`
# barrel; downstream layers consume the parser through the AST types +
# `parse*` entry point below and simply ignore it.
import parser
export parser

import identifiers
export identifiers

import scalars
export scalars

import literals
export literals

import getter
export getter

import importpath
export importpath

import imports
export imports

import argtype
export argtype

import refs
export refs

import datadef
export datadef

import pattern
export pattern

import statement
export statement

import function
export function

import generic
export generic

import module
export module

import types
export types

import app
export app

type File = app.File

# aslFile: import* (module | generic)*  — user-authored source files.
proc parseAslFile(parser: Parser, vendorRoots: VendorRoots): Result[File, ParserError] =
  discard ? parser.expect(emptyLineSpec.any())
  let imports = ? parser.expect(importSpec.any())
  discard ? parser.expect(emptyLineSpec.any())
  let items = ? parser.expect(typeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  discard ? parser.expect(emptyLineSpec.any())
  let types = ? parser.expect(typeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslrFile(parser.filepath, types)

proc toStringErr(r: Result[File, ParserError]): Result[File, string] =
  if r.isOk: ok(r.get) else: err(fmt"{r.error}")

proc parseFile*(parser: Parser, vendorRoots: VendorRoots): Result[File, string] =
  ## Runs the grammar against `parser` and returns the parsed `File`.
  ## Dispatches on the filepath extension: `.asl` files parse imports
  ## plus modules/generics; `.aslr` files parse modules/generics only
  ## (runtime interface — no imports allowed).
  let (_, _, ext) = parser.filepath.splitFile()
  case ext:
  of ".asl": parseAslFile(parser, vendorRoots).toStringErr
  of ".aslr": parseAslrFile(parser).toStringErr
  else: err(fmt"{parser.filepath}: unrecognized file extension '{ext}' — expected '.asl' or '.aslr'")

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  if not fileExists(filepath):
    return err(fmt"{filepath}: file not found")
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"{filepath} file exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      let source = readFile(filepath)
      let pos = validateUtf8(source)
      if pos == -1: ok(source)
      else: err(fmt"{filepath} invalid UTF-8 byte at position {pos}.")
  except CatchableError:
    err(fmt"{filepath} failed to read file.")

proc dump(filepath: string, tokens: seq[Token]): string =
  var content: seq[string]
  content.add(fmt"--- // START {filepath} tokens ({tokens.len}) ---")
  for token in tokens:
    content.add($(token))
  content.add(fmt"--- // END {filepath} ---")
  return content.join("\n")

proc loadFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool, vendorRoots: VendorRoots): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath)
  if dumpTokens: echo filepath.dump(tokens)
  let parser = newParser(filepath, indentWidth, tokens)
  parser.parseFile(vendorRoots)

proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool, vendorRoots: VendorRoots): Result[App, string] =
  ## Loads the root file and everything it transitively imports in a
  ## single depth-first walk, returning an App whose files are in
  ## dependency order — each file's imports precede it (leaves first,
  ## root last), which is the order the resolver consumes.
  ##
  ## The walk doubles as cycle detection. `visiting` is the current
  ## recursion stack: re-entering a path already on it is a cyclic
  ## import, reported as the offending chain. `visited` records files
  ## already emitted, so a file imported by several others is loaded
  ## and parsed exactly once, and the DFS terminates on a diamond.
  ##
  ## `imp.absPath` was resolved when the importing file was parsed
  ## (toAbsPath ran inside the import-line spec), so `importPaths`
  ## reuses it directly rather than re-resolving. `vendorRoots` threads
  ## through every `loadFile` so the per-file `aslFileSpec` can hand it
  ## to `newAslFile` (which auto-injects `import "@std"` in W10).
  var visiting: seq[string]      # DFS recursion stack: membership + cycle-path report
  var visited: HashSet[string]   # files already walked and emitted
  var ordered: seq[File]         # dependency order: leaves first, root last

  proc walk(path: string): Result[void, string] =
    if path in visited: return ok()
    if path in visiting:
      let chain = (visiting[visiting.find(path) .. ^1] & path).join(" -> ")
      return err(fmt"cyclic dependency detected: {chain}")

    visiting.add(path)
    let file = ? loadFile(path, indentWidth, dumpTokens, vendorRoots)
    for importPath in file.importPaths:
      ? walk(importPath)
    discard visiting.pop()

    visited.incl(path)
    ordered.add(file)
    ok()

  ? walk(rootPath)
  ok(newApp(ordered))
