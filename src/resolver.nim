import results, tables

import parser, validator
export parser, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Resolved types
# ============================================================

type
  ResolvedFile* = ref object
    id: int                               # index in app.files
    path: string

  ResolvedApp* = ref object
    files: seq[ResolvedFile]
    fileIndex: Table[string, int]         # absolute path → index in files

# ============================================================
# Resolution
# ============================================================

proc resolveFile(f: IndexedFile, id: int): ResolvedFile =
  ResolvedFile(id: id, path: f.file.path)

proc resolve*(app: App): Result[ResolvedApp, string] =
  let resolved = ResolvedApp()
  for i, f in app.files:
    let rf = resolveFile(f, i)
    resolved.files.add(rf)
    resolved.fileIndex[rf.path] = i
  ok(resolved)
