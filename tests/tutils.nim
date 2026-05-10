## Shared test utilities. Named tutils to avoid colliding with src/utils.nim.

import os, results, strutils

import tokenizer
import parser
import resolver

type FileSpec* = tuple[name: string, content: string]

var dirCounter {.threadvar.}: int

proc tokenizeStr*(source: string, filepath: string = "test.asl"):
    Result[seq[Token], string] =
  ## Tokenize a string with a synthetic filepath.
  tokenize(source, filepath, false)

proc parseStr*(source: string, filepath: string = "",
    indentWidth: uint32 = 2): Result[decls.File, string] =
  ## Tokenize + parse a single in-memory source. Skips the BFS loader.
  ## Default filepath has a directory component so import-path
  ## resolution (which rejects parent-directory escapes) does not
  ## reject a synthetic relative import.
  let path = if filepath.len == 0: getTempDir() / "asl_parseStr.asl" else: filepath
  let tokens = ? tokenizeStr(source, path)
  decls.parse(path, indentWidth, tokens)

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
    indentWidth: uint32 = 2): tuple[app: Result[App, string], dir: string] =
  ## Parse a set of files from a temp dir. The first spec is the entry
  ## point. Caller is responsible for cleaning up `dir` via cleanupDir.
  let dir = writeFiles(specs)
  let root = dir / specs[0].name
  (parser.parse(root, indentWidth, false), dir)

proc voidErr(msg: string): Result[void, string] = err(msg)
proc voidOk(): Result[void, string] = ok()

proc resolveFiles*(specs: openArray[FileSpec],
    indentWidth: uint32 = 2): tuple[res: Result[void, string], dir: string] =
  ## Parse + resolve. Returns the Result[void, string] form (caller
  ## just wants to know whether the program is well-formed).
  let (maybeApp, dir) = parseFiles(specs, indentWidth)
  if maybeApp.isErr:
    return (voidErr(maybeApp.error), dir)
  let r = resolve(maybeApp.get)
  if r.isErr:
    return (voidErr(r.error), dir)
  (voidOk(), dir)

proc parseSingle*(source: string,
    indentWidth: uint32 = 2): tuple[app: Result[App, string], dir: string] =
  ## Convenience for a single-file program.
  parseFiles([("entry.asl", source)], indentWidth)

proc resolveSingle*(source: string,
    indentWidth: uint32 = 2): tuple[res: Result[void, string], dir: string] =
  ## Convenience for a single-file program (no imports).
  resolveFiles([("entry.asl", source)], indentWidth)

proc errorContains*(err: string, needle: string): bool =
  ## Case-sensitive substring check, useful for asserting on error
  ## messages without locking in exact wording.
  needle in err
