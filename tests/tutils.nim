## Shared test utilities. Named tutils to avoid colliding with src/utils.nim.

import os, results, strutils, tables

import analyzer/defanalyzer/tokenizer/index
import analyzer

type FileSpec* = tuple[name: string, content: string]

proc emptyVendorRoots(): VendorRoots = initTable[string, string]()

var dirCounter {.threadvar.}: int

proc tokenizeStr*(source: string, filepath: string = "test.asl"):
    Result[seq[Token], string] =
  ## Tokenize a string with a synthetic filepath.
  tokenize(source, filepath)

proc parseStr*(source: string, filepath: string = "",
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): Result[parser.File, string] =
  ## Tokenize + parse a single in-memory source. Skips the BFS loader.
  ## Default filepath has a directory component so import-path
  ## resolution (which rejects parent-directory escapes) does not
  ## reject a synthetic relative import.
  let path = if filepath.len == 0: getTempDir() / "asl_parseStr.asl" else: filepath
  let tokens = ? tokenizeStr(source, path)
  newParser(path, indentWidth, tokens).parseFile(vendorRoots)

proc parseStrAslr*(source: string, indentWidth: uint32 = 2): Result[parser.File, string] =
  ## Same as `parseStr` but uses a `.aslr` filepath, so the parser
  ## dispatches to `aslrFileSpec` / `newAslrFile`. Use for tests of
  ## `.aslr`-specific behavior — files that carry no imports. `.aslr`
  ## files never receive vendor-driven auto-injection, so this helper
  ## does not take `vendorRoots`.
  parseStr(source, getTempDir() / "asl_parseStr.aslr", indentWidth)

proc writeFiles*(specs: openArray[FileSpec]): string =
  ## Write a set of files into a fresh temp dir. Returns the dir path.
  ## The first entry is treated as the entry point; its name is what
  ## the caller should pass as the rootPath to `parser.parse(...)`.
  inc dirCounter
  let dir = getTempDir() / "aslest_" & $getCurrentProcessId() & "_" & $dirCounter
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

const StdVendorBase* = """
public module u8:
  literal: "uint8"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public module String:
  literal: "string"

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { error: u8 }
"""

proc writeStdVendor*(): tuple[vendorRoots: VendorRoots, dir: string] =
  ## Writes a minimal std vendor `base.aslr` into a fresh temp dir
  ## and returns a `VendorRoots` mapping `std` → that file, plus the
  ## dir path for cleanup. Compose with any of the existing parse /
  ## resolve / analyze helpers by passing `vendorRoots` through
  ## their optional last parameter — auto-injection in `newAslFile`
  ## then synthesizes the `import "@std"` line for the user's file.
  let dir = writeFiles([("base.aslr", StdVendorBase)])
  var roots = initTable[string, string]()
  roots["std"] = dir / "base.aslr"
  (roots, dir)

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

proc resolveSingleAslr*(source: string,
    indentWidth: uint32 = 2): tuple[res: Result[void, string], dir: string] =
  ## Same as `resolveSingle` but writes the source as `entry.aslr` so
  ## the parser dispatches to `aslrFileSpec` / `newAslrFile`. Use for
  ## `.aslr`-specific behavior — entry files that carry no imports.
  ## `.aslr` entry points do not receive vendor-driven auto-injection,
  ## so this helper does not take `vendorRoots`.
  resolveFiles([("entry.aslr", source)], indentWidth)

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

proc analyzeAppSingle*(source: string,
    indentWidth: uint32 = 2,
    vendorRoots: VendorRoots = emptyVendorRoots()): tuple[res: Result[AnalyzedApp, string], dir: string] =
  ## Parse + resolve + analyze, returning the AnalyzedApp itself so callers
  ## can inspect it (e.g. entry).
  let (maybeApp, dir) = parseFiles([("entry.asl", source)], indentWidth, vendorRoots)
  proc go(app: Result[App, string]): Result[AnalyzedApp, string] =
    let parsed = ? app
    let resolved = ? resolve(parsed)
    analyze(resolved)
  (go(maybeApp), dir)

proc errorContains*(err: string, needle: string): bool =
  ## Case-sensitive substring check, useful for asserting on error
  ## messages without locking in exact wording.
  needle in err
