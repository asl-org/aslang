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
# Readonly accessors
# ============================================================

proc id*(f: ResolvedField): int = f.id
proc name*(f: ResolvedField): Identifier = f.name
proc argType*(f: ResolvedField): ArgumentType = f.argType
proc loc*(f: ResolvedField): Location = f.loc

proc fields*(s: ResolvedStruct): seq[ResolvedField] = s.fields
proc loc*(s: ResolvedStruct): Location = s.loc

proc id*(v: ResolvedVariant): int = v.id
proc name*(v: ResolvedVariant): Identifier = v.name
proc fields*(v: ResolvedVariant): seq[ResolvedField] = v.fields
proc loc*(v: ResolvedVariant): Location = v.loc

proc variants*(u: ResolvedUnion): seq[ResolvedVariant] = u.variants
proc loc*(u: ResolvedUnion): Location = u.loc

proc kind*(d: ResolvedData): ResolvedDataKind = d.kind
proc struct*(d: ResolvedData): ResolvedStruct =
  assert d.kind == rdkStruct,
    fmt"ResolvedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: ResolvedData): ResolvedUnion =
  assert d.kind == rdkUnion,
    fmt"ResolvedData.union accessed but kind is {d.kind}"
  d.union

proc id*(a: ResolvedArgument): int = a.id
proc name*(a: ResolvedArgument): Identifier = a.name
proc argType*(a: ResolvedArgument): ArgumentType = a.argType
proc loc*(a: ResolvedArgument): Location = a.loc

proc id*(fn: ResolvedFunction): int = fn.id
proc decorators*(fn: ResolvedFunction): seq[Decorator] = fn.decorators
proc name*(fn: ResolvedFunction): Identifier = fn.name
proc params*(fn: ResolvedFunction): seq[ResolvedArgument] = fn.params
proc returns*(fn: ResolvedFunction): ArgumentType = fn.returns
proc body*(fn: ResolvedFunction): StatementList = fn.body
proc loc*(fn: ResolvedFunction): Location = fn.loc

proc id*(fd: ResolvedFuncDef): int = fd.id
proc name*(fd: ResolvedFuncDef): Identifier = fd.name
proc params*(fd: ResolvedFuncDef): seq[ResolvedArgument] = fd.params
proc returns*(fd: ResolvedFuncDef): ArgumentType = fd.returns
proc loc*(fd: ResolvedFuncDef): Location = fd.loc

proc id*(n: ResolvedImportName): int = n.id
proc name*(n: ResolvedImportName): Identifier = n.name
proc alias*(n: ResolvedImportName): Option[Identifier] = n.alias
proc loc*(n: ResolvedImportName): Location = n.loc

proc id*(imp: ResolvedImport): int = imp.id
proc source*(imp: ResolvedImport): string = imp.source
proc targetFileId*(imp: ResolvedImport): int = imp.targetFileId
proc names*(imp: ResolvedImport): seq[ResolvedImportName] = imp.names
proc loc*(imp: ResolvedImport): Location = imp.loc

proc id*(m: ResolvedModule): int = m.id
proc decorators*(m: ResolvedModule): seq[Decorator] = m.decorators
proc name*(m: ResolvedModule): Identifier = m.name
proc data*(m: ResolvedModule): Option[ResolvedData] = m.data
proc functions*(m: ResolvedModule): seq[ResolvedFunction] = m.functions
proc loc*(m: ResolvedModule): Location = m.loc

proc id*(g: ResolvedGeneric): int = g.id
proc decorators*(g: ResolvedGeneric): seq[Decorator] = g.decorators
proc name*(g: ResolvedGeneric): Identifier = g.name
proc funcDefs*(g: ResolvedGeneric): seq[ResolvedFuncDef] = g.funcDefs
proc loc*(g: ResolvedGeneric): Location = g.loc

proc id*(f: ResolvedFile): int = f.id
proc path*(f: ResolvedFile): string = f.path
proc imports*(f: ResolvedFile): seq[ResolvedImport] = f.imports
proc modules*(f: ResolvedFile): seq[ResolvedModule] = f.modules
proc generics*(f: ResolvedFile): seq[ResolvedGeneric] = f.generics

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, path: string): int =
  app.fileIndex.getOrDefault(path, -1)

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
