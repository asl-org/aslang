import os, unicode, tables, deques, sets, results, strformat, strutils

import tokenizer, ast, grammar, utils

# Disambiguate against system File (syncio.File)
type File = ast.File

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

proc parseFile(filepath: string, indentWidth: uint32,
    dumpTokens: bool): Result[File, string] =
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath, dumpTokens)
  parse(filepath, indentWidth, tokens)

proc resolveImportPath(source: string, importingFile: string): Result[string, string] =
  ## Resolves an import path relative to the importing file.
  ## Rejects paths that escape to parent directories.
  ## Normalizes the resolved path so tricks like ./sub/../../escape
  ## are caught — not just paths starting with "..".
  let dir = normalizedPath(importingFile.parentDir)
  let resolved = normalizedPath((dir / source).absolutePath)
  let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
  if not resolved.startsWith(dirPrefix):
    return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
  ok(resolved)

proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool): Result[
    seq[File], string] =
  ## BFS through imports, tokenize + parse each file.
  ## Returns files in topological order: leaves first, root last.
  var parsed: Table[string, File]
  var queued: HashSet[string]
  var queue: Deque[string]

  queue.addLast(rootPath)
  queued.incl(rootPath)

  while queue.len > 0:
    let current = queue.popFirst()
    let file = ? parseFile(current, indentWidth, dumpTokens)
    parsed[current] = file

    for imp in file.imports:
      let depPath = ? resolveImportPath(imp.source, current)
      if depPath notin queued:
        queue.addLast(depPath)
        queued.incl(depPath)

  # Topological sort with cycle detection (leaves first, root last)
  let getNeighbors = proc(path: string): seq[string] =
    if parsed.hasKey(path):
      for imp in parsed[path].imports:
        result.add(imp.path)
  let sortedPaths = ? topoSort(rootPath, getNeighbors)

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(files)
