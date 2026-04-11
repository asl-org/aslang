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

  ResolvedVariant* = ref object
    id: int                               # index in union.variants
    name: Identifier
    fields: seq[ResolvedField]
    loc: Location

  ResolvedUnion* = ref object
    variants: seq[ResolvedVariant]
    loc: Location

  ResolvedDataKind* = enum
    rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

  ResolvedArgument* = ref object         # function or funcDef parameter
    id: int                               # index in parent params list
    name: Identifier
    argType: ArgumentType                 # raw until Phase 2
    loc: Location

  ResolvedFunction* = ref object
    id: int                               # index in module.functions
    decorators: seq[Decorator]            # raw
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType                 # raw
    body: StatementList                   # raw — Phase 3 resolves
    loc: Location

  ResolvedFuncDef* = ref object
    id: int                               # index in generic.funcDefs
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType                 # raw
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
    data: Option[ResolvedData]
    functions: seq[ResolvedFunction]
    loc: Location

  ResolvedGeneric* = ref object
    id: int                               # index in file.generics
    decorators: seq[Decorator]            # raw
    name: Identifier
    funcDefs: seq[ResolvedFuncDef]
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

proc resolveVariant(v: VariantDefinition, id: int): ResolvedVariant =
  let rv = ResolvedVariant(
    id: id,
    name: v.name,
    loc: v.loc,
  )
  for i, f in v.fields:
    rv.fields.add(resolveField(f, i))
  rv

proc resolveUnion(u: Union): ResolvedUnion =
  let ru = ResolvedUnion(loc: u.loc)
  for i, v in u.variants:
    ru.variants.add(resolveVariant(v, i))
  ru

proc resolveData(db: DataBlock): ResolvedData =
  case db.kind:
  of dbkStruct:
    ResolvedData(kind: rdkStruct, struct: resolveStruct(db.struct))
  of dbkUnion:
    ResolvedData(kind: rdkUnion, union: resolveUnion(db.union))

proc resolveArgument(a: ArgumentDefinition, id: int): ResolvedArgument =
  ResolvedArgument(
    id: id,
    name: a.name,
    argType: a.argType,
    loc: a.loc,
  )

proc resolveFunction(fn: Function, id: int): ResolvedFunction =
  let rf = ResolvedFunction(
    id: id,
    decorators: fn.decorators,
    name: fn.def.name,
    returns: fn.def.returns,
    body: fn.statementList,
    loc: fn.def.loc,
  )
  for i, p in fn.def.params:
    rf.params.add(resolveArgument(p, i))
  rf

proc resolveFuncDef(fd: FunctionDefinition, id: int): ResolvedFuncDef =
  let rfd = ResolvedFuncDef(
    id: id,
    name: fd.name,
    returns: fd.returns,
    loc: fd.loc,
  )
  for i, p in fd.params:
    rfd.params.add(resolveArgument(p, i))
  rfd

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
  let resolvedData =
    if m.data.isSome: some(resolveData(m.data.get))
    else: none(ResolvedData)
  let rm = ResolvedModule(
    id: id,
    decorators: m.decorators,
    name: m.name,
    data: resolvedData,
    loc: m.loc,
  )
  for i, fn in m.functions:
    rm.functions.add(resolveFunction(fn, i))
  rm

proc resolveGeneric(g: Generic, id: int): ResolvedGeneric =
  let rg = ResolvedGeneric(
    id: id,
    decorators: g.decorators,
    name: g.name,
    loc: g.loc,
  )
  for i, fd in g.funcDefs:
    rg.funcDefs.add(resolveFuncDef(fd, i))
  rg

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
