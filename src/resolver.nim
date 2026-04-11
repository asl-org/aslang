import options, results, strformat, tables

import parser, tokenizer, validator
export parser, tokenizer, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Resolved types
# ============================================================

type
  ResolvedImportName* = ref object
    id: int                               # index in imp.names
    name: Identifier
    alias: Option[Identifier]
    loc: Location

  ResolvedImport* = ref object
    id: int                               # index in file.imports
    source: string
    targetFileId: int                     # index in app.files
    names: seq[ResolvedImportName]
    loc: Location

  ResolvedFile* = ref object
    id: int                               # index in app.files
    path: string
    imports: seq[ResolvedImport]

  ResolvedApp* = ref object
    files: seq[ResolvedFile]
    fileIndex: Table[string, int]         # absolute path → index in files

# ============================================================
# Resolution
# ============================================================

proc resolveImportName(n: ImportName, id: int): ResolvedImportName =
  ResolvedImportName(
    id: id,
    name: n.name,
    alias: n.alias,
    loc: n.loc,
  )

proc resolveImport(imp: Import, id: int, importingPath: string,
    fileIndex: Table[string, int]): Result[ResolvedImport, string] =
  let absPath = ? resolveImportPath(imp.source, importingPath)
  if absPath notin fileIndex:
    return err(fmt"{importingPath}: import target '{imp.source}' not found in file index")
  let ri = ResolvedImport(
    id: id,
    source: imp.source,
    targetFileId: fileIndex[absPath],
    loc: imp.loc,
  )
  for nIdx, n in imp.names:
    ri.names.add(resolveImportName(n, nIdx))
  ok(ri)

proc resolveFile(f: IndexedFile, id: int,
    fileIndex: Table[string, int]): Result[ResolvedFile, string] =
  let rf = ResolvedFile(id: id, path: f.file.path)
  for impIdx, imp in f.file.imports:
    rf.imports.add(? resolveImport(imp, impIdx, f.file.path, fileIndex))
  ok(rf)

proc resolve*(app: App): Result[ResolvedApp, string] =
  let resolved = ResolvedApp()
  # First pass: build fileIndex so imports can look up their targets.
  for i, f in app.files:
    resolved.fileIndex[f.file.path] = i
  # Second pass: resolve each file.
  for i, f in app.files:
    resolved.files.add(? resolveFile(f, i, resolved.fileIndex))
  ok(resolved)
