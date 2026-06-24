import os, unicode, tables, deques, sets, results, strformat

import tokenizer, imports, decls, utils

# Disambiguate against system File (syncio.File)
type File = decls.File

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

# TODO(vendor): accept `vendorRoots: VendorRoots = initTable[string, string]()`
# as an additional parameter and thread it through `parseFile` →
# `decls.parse(filepath, indentWidth, tokens, vendorRoots)` → the
# parameterized `aslFileSpec(vendorRoots)` → `newAslFile`. The BFS
# `for imp in file.imports` becomes `if file.kind == fkAsl: for imp
# in file.imports` once W6 splits File. Also: resolveImportPath now
# also takes vendorRoots so `@vendor` paths surface as dependencies
# during BFS. See W9 in plans/how-is-claude-parsed-whistle.md.
proc parse*(rootPath: string, indentWidth: uint32, dumpTokens: bool): Result[App, string] =
  ## BFS through imports, tokenize + parse each file.
  ## Returns App with files in topological order: leaves first, root last.
  var parsed: Table[string, File]
  var queued: HashSet[string]
  var queue: Deque[string]

  queue.addLast(rootPath)
  queued.incl(rootPath)

  while queue.len > 0:
    let current = queue.popFirst()
    let file = ? parseFile(current, indentWidth, dumpTokens)
    parsed[current] = file

    if file.kind == fkAsl:
      for imp in file.imports:
        # `imp.absPath` was already resolved when the importing file
        # was parsed (resolveImportPath ran inside the import-line
        # spec). Use it directly — re-running resolveImportPath would
        # produce the same value and slow down BFS unnecessarily.
        if imp.absPath notin queued:
          queue.addLast(imp.absPath)
          queued.incl(imp.absPath)

  # Topological sort with cycle detection (leaves first, root last)
  let getNeighbors = proc(path: string): seq[string] =
    if parsed.hasKey(path):
      let p = parsed[path]
      if p.kind == fkAsl:
        for imp in p.imports:
          result.add(imp.absPath)
  let sortedPaths = ? topoSort(rootPath, getNeighbors)

  var files: seq[File]
  for path in sortedPaths:
    files.add(parsed[path])
  ok(newApp(files))
