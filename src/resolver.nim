import options, results, strformat, tables

import parser, tokenizer, validator
export parser, tokenizer, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Resolved types
# ============================================================

type
  ResolvedField* = ref object            # struct field or variant field
    id: int                               # index in parent fields list
    name: Identifier
    argType: ArgumentType                 # raw until Phase 2
    loc: Location

  ResolvedStruct* = ref object
    fields: seq[ResolvedField]
    loc: Location

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

  ResolvedModule* = ref object
    id: int                               # index in file.modules
    decorators: seq[Decorator]            # raw
    name: Identifier
    data: Option[DataBlock]               # raw, wired later
    functions: seq[Function]              # raw, wired later
    loc: Location

  ResolvedGeneric* = ref object
    id: int                               # index in file.generics
    decorators: seq[Decorator]            # raw
    name: Identifier
    funcDefs: seq[FunctionDefinition]     # raw, wired later
    loc: Location

  ResolvedFile* = ref object
    id: int                               # index in app.files
    path: string
    imports: seq[ResolvedImport]
    modules: seq[ResolvedModule]
    generics: seq[ResolvedGeneric]

  ResolvedApp* = ref object
    files: seq[ResolvedFile]
    fileIndex: Table[string, int]         # absolute path → index in files

# ============================================================
# Resolution
# ============================================================

proc resolveField(f: ArgumentDefinition, id: int): ResolvedField =
  ResolvedField(
    id: id,
    name: f.name,
    argType: f.argType,
    loc: f.loc,
  )

proc resolveStruct(s: Struct): ResolvedStruct =
  let rs = ResolvedStruct(loc: s.loc)
  for i, f in s.fields:
    rs.fields.add(resolveField(f, i))
  rs

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

proc resolveModule(m: Module, id: int): ResolvedModule =
  ResolvedModule(
    id: id,
    decorators: m.decorators,
    name: m.name,
    data: m.data,
    functions: m.functions,
    loc: m.loc,
  )

proc resolveGeneric(g: Generic, id: int): ResolvedGeneric =
  ResolvedGeneric(
    id: id,
    decorators: g.decorators,
    name: g.name,
    funcDefs: g.funcDefs,
    loc: g.loc,
  )

proc resolveFile(f: IndexedFile, id: int,
    fileIndex: Table[string, int]): Result[ResolvedFile, string] =
  let rf = ResolvedFile(id: id, path: f.file.path)
  for impIdx, imp in f.file.imports:
    rf.imports.add(? resolveImport(imp, impIdx, f.file.path, fileIndex))
  for mIdx, m in f.file.modules:
    rf.modules.add(resolveModule(m, mIdx))
  for gIdx, g in f.file.generics:
    rf.generics.add(resolveGeneric(g, gIdx))
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
