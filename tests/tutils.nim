## Shared test utilities. Named tutils to avoid colliding with src/utils.nim.

import os, results, strutils, tables

import tokenizer
import parser
import resolver
import analyzer

type FileSpec* = tuple[name: string, content: string]

proc emptyVendorRoots(): VendorRoots = initTable[string, string]()

var dirCounter {.threadvar.}: int

proc tokenizeStr*(source: string, filepath: string = "test.asl"):
    Result[seq[Token], string] =
  ## Tokenize a string with a synthetic filepath.
  tokenize(source, filepath, false)

proc parseStr*(source: string, filepath: string = "",
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): Result[decls.File, string] =
  ## Tokenize + parse a single in-memory source. Skips the BFS loader.
  ## Default filepath has a directory component so import-path
  ## resolution (which rejects parent-directory escapes) does not
  ## reject a synthetic relative import.
  let path = if filepath.len == 0: getTempDir() / "asl_parseStr.asl" else: filepath
  let tokens = ? tokenizeStr(source, path)
  decls.parse(path, indentWidth, tokens, vendorRoots)

proc parseStrAslb*(source: string, indentWidth: uint32 = 2): Result[decls.File, string] =
  ## Same as `parseStr` but uses a `.aslb` filepath, so the parser
  ## dispatches to `aslbFileSpec` / `newAslbFile`. Use for tests of
  ## grammar elements that are only legal in runtime-interface files
  ## (extern functions inside modules). `.aslb` files never receive
  ## vendor-driven auto-injection, so this helper does not take
  ## `vendorRoots`.
  parseStr(source, getTempDir() / "asl_parseStr.aslb", indentWidth)

proc writeFiles*(specs: openArray[FileSpec]): string =
  ## Write a set of files into a fresh temp dir. Returns the dir path.
  ## The first entry is treated as the entry point; its name is what
  ## the caller should pass as the rootPath to `parser.parse(...)`.
  inc dirCounter
  let dir = getTempDir() / "asl_test_" & $getCurrentProcessId() & "_" & $dirCounter
  removeDir(dir)
  createDir(dir)
  for spec in specs:
    let p = dir / spec.name
    createDir(parentDir(p))
    writeFile(p, spec.content)
  dir

proc cleanupDir*(dir: string) =
  ## Best-effort recursive delete; ignores missing-dir errors.
  try: removeDir(dir)
  except CatchableError: discard

proc parseFiles*(specs: openArray[FileSpec],
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[app: Result[App, string], dir: string] =
  ## Parse a set of files from a temp dir. The first spec is the entry
  ## point. Caller is responsible for cleaning up `dir` via cleanupDir.
  let dir = writeFiles(specs)
  let root = dir / specs[0].name
  (parser.parse(root, indentWidth, false, vendorRoots), dir)

proc voidErr(msg: string): Result[void, string] = err(msg)
proc voidOk(): Result[void, string] = ok()

proc resolveFiles*(specs: openArray[FileSpec],
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[res: Result[void, string], dir: string] =
  ## Parse + resolve. Returns the Result[void, string] form (caller
  ## just wants to know whether the program is well-formed).
  let (maybeApp, dir) = parseFiles(specs, indentWidth, vendorRoots)
  if maybeApp.isErr:
    return (voidErr(maybeApp.error), dir)
  let r = resolve(maybeApp.get)
  if r.isErr:
    return (voidErr(r.error), dir)
  (voidOk(), dir)

proc parseSingle*(source: string,
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[app: Result[App, string], dir: string] =
  ## Convenience for a single-file program.
  parseFiles([("entry.asl", source)], indentWidth, vendorRoots)

proc resolveSingle*(source: string,
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[res: Result[void, string], dir: string] =
  ## Convenience for a single-file program (no imports).
  resolveFiles([("entry.asl", source)], indentWidth, vendorRoots)

proc resolveSingleAslb*(source: string,
    indentWidth: uint32 = 2): tuple[res: Result[void, string], dir: string] =
  ## Same as `resolveSingle` but writes the source as `entry.aslb` so
  ## the parser dispatches to `aslbFileSpec` / `newAslbFile`. Use when
  ## the source contains modules with extern functions (asl files
  ## cannot host externs). `.aslb` entry points do not receive
  ## vendor-driven auto-injection, so this helper does not take
  ## `vendorRoots`.
  resolveFiles([("entry.aslb", source)], indentWidth)

proc analyzeFiles*(specs: openArray[FileSpec],
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[res: Result[void, string], dir: string] =
  ## Parse + resolve + analyze. Returns the Result[void, string] form
  ## (caller just wants to know whether the program is well-formed end
  ## to end).
  let (maybeApp, dir) = parseFiles(specs, indentWidth, vendorRoots)
  if maybeApp.isErr:
    return (voidErr(maybeApp.error), dir)
  let resolved = resolve(maybeApp.get)
  if resolved.isErr:
    return (voidErr(resolved.error), dir)
  let analyzed = analyze(resolved.get)
  if analyzed.isErr:
    return (voidErr(analyzed.error), dir)
  (voidOk(), dir)

proc analyzeSingle*(source: string,
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[res: Result[void, string], dir: string] =
  ## Convenience for a single-file program (no imports).
  analyzeFiles([("entry.asl", source)], indentWidth, vendorRoots)

proc errorContains*(err: string, needle: string): bool =
  ## Case-sensitive substring check, useful for asserting on error
  ## messages without locking in exact wording.
  needle in err
