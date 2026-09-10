import strformat, sequtils, strutils, unicode, results, options, tables, os

# The parser consumes Location (every AST node carries one) from the
# tokenizer, a sibling package. It is NOT re-exported: downstream
# layers that need Location import `tokenizer/main` directly.
import ../tokenizer/main as tokenizer

# parser.nim (Parser + Spec[T] + oneOf / any / optional / ...) holds the
# combinator scaffolding. It is re-exported so the parser tests can drive
# the machinery (newParser, newSpec, expect, …) through the `parser/main`
# barrel; downstream layers consume the parser through the AST types +
# `parse*` entry point below and simply ignore it.
import parser
export parser

import identifiers
export identifiers

import literals
export literals

import imports
export imports

import argtype
export argtype

import refs
export refs

import datadef
export datadef

import statement
export statement

import function
export function

# Parser-level ANF expansion (expand*). Reference code, not yet wired
# into the pipeline — imported here so it stays in the compile graph.
import expansion
export expansion

import types
export types

import app
export app

# import ./combinators
# export combinators
import error
import decorator
import utils

type File = app.File

# The body-cluster specs (expressions, statements, matches, functions, data
# defs) live with their types in statement.nim / function.nim / datadef.nim /
# refs.nim. What remains here is the top-level file structure: generics,
# modules, and the file/vendor entry points.

proc genericHeaderConsumer(parser: Parser): Result[GenericHeader, ParserError] =
  let public = parser.expect("public").isOk
  if public: discard ? parser.expect(spaceSpec)
  let genericKeyword = ? parser.expect("generic")
  discard ? parser.expect(spaceSpec)
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(newGenericHeader(public, nameIdent, genericKeyword.loc))

let genericHeaderSpec = newSpec[GenericHeader]("generic header", genericHeaderConsumer)

proc genericConsumer(parser: Parser): Result[Generic, ParserError] =
  ## Parses a `[public] generic Name:` block followed by its function
  ## definitions. Body failures are marked fatal — once past the
  ## header, the block cannot be backtracked out of.
  let (h, body) = ? parser.indentedBlock(genericHeaderSpec, functionDefSpec.indentedLine().atLeastOne())
  ok(newGeneric(@[], h.public, h.name, body, h.loc))

let genericSpec = newSpec[Generic]("generic", genericConsumer)

proc moduleHeaderConsumer(parser: Parser): Result[ModuleHeader, ParserError] =
  let public = parser.expect("public").isOk
  if public: discard ? parser.expect(spaceSpec)

  let moduleKeyword = ? parser.expect("module")
  discard ? parser.expect(spaceSpec)
  let nameIdent = ? parser.expect(identifierSpec)
  discard parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  ok(newModuleHeader(public, nameIdent, moduleKeyword.loc))

let moduleHeaderSpec = newSpec[ModuleHeader]("module header", moduleHeaderConsumer)

proc moduleBodyConsumer(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.expect(any(emptyLineSpec))
  let data = ? parser.expect(dataDefSpec.optional())
  let funcList = ? parser.expect(functionListSpec)
  ok(newModuleBody(data, funcList))

let moduleBodySpec = newSpec[ModuleBody]("module body", moduleBodyConsumer)

proc moduleConsumer(parser: Parser): Result[Module, ParserError] =
  ## Parses a `[public] module Name:` block with optional decorator
  ## lines. Body failures are marked fatal — once past the header,
  ## the block cannot be backtracked out of.
  let decorators = ? parser.expect(any(decoratorSpec))
  let (h, b) = ? parser.indentedBlock(moduleHeaderSpec, moduleBodySpec)
  newModule(decorators, h.public, h.name, b.data, b.funcList, h.loc)

let moduleSpec = newSpec[Module]("module", moduleConsumer)

let typeSpec = oneOf("type", @[
  moduleSpec.map(newLocalType),
  genericSpec.map(newLocalType),
])

proc parseDefinedType(parser: Parser): Result[LocalType, ParserError] =
  ## Skips leading blank / comment lines, then parses a module or
  ## generic block. Used at file level between top-level type blocks.
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(typeSpec)

let localTypeSpec = newSpec[LocalType]("local type", parseDefinedType)

proc parseDefinedTypes(parser: Parser): Result[seq[LocalType], ParserError] =
  ## Parses one-or-more top-level `LocalType` blocks (module / generic),
  ## skipping blank lines between them. Fails if the first attempt
  ## does not yield a type.
  var items: seq[LocalType]
  let first = ? parser.expect(localTypeSpec)
  items.add(first)
  while true:
    let maybeNext = parser.expect(localTypeSpec)
    if maybeNext.isErr:
      if maybeNext.error.fatal: return err(maybeNext.error)
      break
    items.add(maybeNext.get)
  ok(items)

let definedTypesSpec = newSpec[seq[LocalType]]("defined types", parseDefinedTypes)

# aslFile: import* (module | generic)*  — user-authored source files.
proc parseAslFile(parser: Parser, vendorRoots: VendorRoots): Result[File, ParserError] =
  discard ? parser.expect(emptyLineSpec.any())
  let imports = ? parser.expect(importSpec.any())
  discard ? parser.expect(emptyLineSpec.any())
  let items = ? parser.expect(localTypeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslFile(parser.filepath, imports, items, vendorRoots)

# aslrFile: (module | generic)*  — no imports section. Aslr files
# are the runtime interface; they cannot reference other files.
proc parseAslrFile(parser: Parser): Result[File, ParserError] =
  discard ? parser.expect(emptyLineSpec.any())
  let items = ? parser.expect(localTypeSpec.atLeastOne())
  discard ? parser.expect(emptyLineSpec.any())
  # Force a parse attempt to get a specific error message
  if not parser.done(): discard ? parser.expect(typeSpec)
  newAslrFile(parser.filepath, items, @[])

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
  ## BFS through imports, tokenize + parse each file.
  ## Returns App with files in topological order: leaves first, root last.
  ## `vendorRoots` threads through every `parseFile` call so the
  ## per-file `aslFileSpec` can hand it to `newAslFile` (which uses
  ## it to auto-inject `import "@std"` in W10).
  ##
  ## `imp.absPath` was already resolved when the importing file was
  ## parsed (toAbsPath ran inside the import-line spec).
  ## Both the BFS walk and the topoSort reuse it directly through
  ## `importPaths` — re-resolving would produce the same value and
  ## slow down parsing unnecessarily.
  let parsed = ? bfs(
    rootPath,
    proc(path: string): Result[File, string] =
      loadFile(path, indentWidth, dumpTokens, vendorRoots),
    importPaths)

  # Topological sort with cycle detection (leaves first, root last)
  let sortedPaths = ? topoSort(rootPath, proc(path: string): seq[string] =
    if parsed.hasKey(path): importPaths(parsed[path])
    else: @[])

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(newApp(files))
