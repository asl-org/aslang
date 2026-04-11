import options, results, strformat, tables

import parser, tokenizer, validator
export parser, tokenizer, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# ResolvedField (struct field or variant field)
# ============================================================

type ResolvedField* = ref object
  id: int               # index in parent fields list
  name: Identifier
  argType: ArgumentType # raw until Phase 2
  loc: Location

proc newResolvedField(id: int, name: Identifier, argType: ArgumentType,
    loc: Location): ResolvedField =
  ResolvedField(id: id, name: name, argType: argType, loc: loc)

proc id*(f: ResolvedField): int = f.id
proc name*(f: ResolvedField): Identifier = f.name
proc argType*(f: ResolvedField): ArgumentType = f.argType
proc loc*(f: ResolvedField): Location = f.loc

proc resolveField(f: ArgumentDefinition, id: int): ResolvedField =
  newResolvedField(id, f.name, f.argType, f.loc)

# ============================================================
# ResolvedStruct
# ============================================================

type ResolvedStruct* = ref object
  fields: seq[ResolvedField]
  loc: Location

proc newResolvedStruct(fields: seq[ResolvedField],
    loc: Location): ResolvedStruct =
  ResolvedStruct(fields: fields, loc: loc)

proc fields*(s: ResolvedStruct): seq[ResolvedField] = s.fields
proc loc*(s: ResolvedStruct): Location = s.loc

proc resolveStruct(s: Struct): ResolvedStruct =
  var fields: seq[ResolvedField]
  for i, f in s.fields:
    fields.add(resolveField(f, i))
  newResolvedStruct(fields, s.loc)

# ============================================================
# ResolvedVariant
# ============================================================

type ResolvedVariant* = ref object
  id: int # index in union.variants
  name: Identifier
  fields: seq[ResolvedField]
  loc: Location

proc newResolvedVariant(id: int, name: Identifier,
    fields: seq[ResolvedField], loc: Location): ResolvedVariant =
  ResolvedVariant(id: id, name: name, fields: fields, loc: loc)

proc id*(v: ResolvedVariant): int = v.id
proc name*(v: ResolvedVariant): Identifier = v.name
proc fields*(v: ResolvedVariant): seq[ResolvedField] = v.fields
proc loc*(v: ResolvedVariant): Location = v.loc

proc resolveVariant(v: VariantDefinition, id: int): ResolvedVariant =
  var fields: seq[ResolvedField]
  for i, f in v.fields:
    fields.add(resolveField(f, i))
  newResolvedVariant(id, v.name, fields, v.loc)

# ============================================================
# ResolvedUnion
# ============================================================

type ResolvedUnion* = ref object
  variants: seq[ResolvedVariant]
  loc: Location

proc newResolvedUnion(variants: seq[ResolvedVariant],
    loc: Location): ResolvedUnion =
  ResolvedUnion(variants: variants, loc: loc)

proc variants*(u: ResolvedUnion): seq[ResolvedVariant] = u.variants
proc loc*(u: ResolvedUnion): Location = u.loc

proc resolveUnion(u: Union): ResolvedUnion =
  var variants: seq[ResolvedVariant]
  for i, v in u.variants:
    variants.add(resolveVariant(v, i))
  newResolvedUnion(variants, u.loc)

# ============================================================
# ResolvedData (struct | union)
# ============================================================

type
  ResolvedDataKind* = enum
    rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

proc newResolvedData(s: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: s)

proc newResolvedData(u: ResolvedUnion): ResolvedData =
  ResolvedData(kind: rdkUnion, union: u)

proc kind*(d: ResolvedData): ResolvedDataKind = d.kind
proc struct*(d: ResolvedData): ResolvedStruct =
  assert d.kind == rdkStruct,
    fmt"ResolvedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: ResolvedData): ResolvedUnion =
  assert d.kind == rdkUnion,
    fmt"ResolvedData.union accessed but kind is {d.kind}"
  d.union

proc resolveData(db: DataBlock): ResolvedData =
  case db.kind:
  of dbkStruct: newResolvedData(resolveStruct(db.struct))
  of dbkUnion:  newResolvedData(resolveUnion(db.union))

# ============================================================
# ResolvedArgument (function or funcDef parameter)
# ============================================================

type ResolvedArgument* = ref object
  id: int               # index in parent params list
  name: Identifier
  argType: ArgumentType # raw until Phase 2
  loc: Location

proc newResolvedArgument(id: int, name: Identifier, argType: ArgumentType,
    loc: Location): ResolvedArgument =
  ResolvedArgument(id: id, name: name, argType: argType, loc: loc)

proc id*(a: ResolvedArgument): int = a.id
proc name*(a: ResolvedArgument): Identifier = a.name
proc argType*(a: ResolvedArgument): ArgumentType = a.argType
proc loc*(a: ResolvedArgument): Location = a.loc

proc resolveArgument(a: ArgumentDefinition, id: int): ResolvedArgument =
  newResolvedArgument(id, a.name, a.argType, a.loc)

# ============================================================
# ResolvedFunction
# ============================================================

type ResolvedFunction* = ref object
  id: int                    # index in module.functions
  decorators: seq[Decorator] # raw
  name: Identifier
  params: seq[ResolvedArgument]
  returns: ArgumentType      # raw
  body: StatementList        # raw — Phase 3 resolves
  loc: Location

proc newResolvedFunction(id: int, decorators: seq[Decorator],
    name: Identifier, params: seq[ResolvedArgument],
    returns: ArgumentType, body: StatementList,
    loc: Location): ResolvedFunction =
  ResolvedFunction(id: id, decorators: decorators, name: name,
    params: params, returns: returns, body: body, loc: loc)

proc id*(fn: ResolvedFunction): int = fn.id
proc decorators*(fn: ResolvedFunction): seq[Decorator] = fn.decorators
proc name*(fn: ResolvedFunction): Identifier = fn.name
proc params*(fn: ResolvedFunction): seq[ResolvedArgument] = fn.params
proc returns*(fn: ResolvedFunction): ArgumentType = fn.returns
proc body*(fn: ResolvedFunction): StatementList = fn.body
proc loc*(fn: ResolvedFunction): Location = fn.loc

proc resolveFunction(fn: Function, id: int): ResolvedFunction =
  var params: seq[ResolvedArgument]
  for i, p in fn.def.params:
    params.add(resolveArgument(p, i))
  newResolvedFunction(
    id, fn.decorators, fn.def.name, params,
    fn.def.returns, fn.statementList, fn.def.loc,
  )

# ============================================================
# ResolvedFuncDef
# ============================================================

type ResolvedFuncDef* = ref object
  id: int # index in generic.funcDefs
  name: Identifier
  params: seq[ResolvedArgument]
  returns: ArgumentType # raw
  loc: Location

proc newResolvedFuncDef(id: int, name: Identifier,
    params: seq[ResolvedArgument], returns: ArgumentType,
    loc: Location): ResolvedFuncDef =
  ResolvedFuncDef(id: id, name: name, params: params,
    returns: returns, loc: loc)

proc id*(fd: ResolvedFuncDef): int = fd.id
proc name*(fd: ResolvedFuncDef): Identifier = fd.name
proc params*(fd: ResolvedFuncDef): seq[ResolvedArgument] = fd.params
proc returns*(fd: ResolvedFuncDef): ArgumentType = fd.returns
proc loc*(fd: ResolvedFuncDef): Location = fd.loc

proc resolveFuncDef(fd: FunctionDefinition, id: int): ResolvedFuncDef =
  var params: seq[ResolvedArgument]
  for i, p in fd.params:
    params.add(resolveArgument(p, i))
  newResolvedFuncDef(id, fd.name, params, fd.returns, fd.loc)

# ============================================================
# ResolvedImportName
# ============================================================

type ResolvedImportName* = ref object
  id: int # index in imp.names
  name: Identifier
  alias: Option[Identifier]
  loc: Location

proc newResolvedImportName(id: int, name: Identifier,
    alias: Option[Identifier], loc: Location): ResolvedImportName =
  ResolvedImportName(id: id, name: name, alias: alias, loc: loc)

proc id*(n: ResolvedImportName): int = n.id
proc name*(n: ResolvedImportName): Identifier = n.name
proc alias*(n: ResolvedImportName): Option[Identifier] = n.alias
proc loc*(n: ResolvedImportName): Location = n.loc

proc resolveImportName(n: ImportName, id: int): ResolvedImportName =
  newResolvedImportName(id, n.name, n.alias, n.loc)

# ============================================================
# ResolvedImport
# ============================================================

type ResolvedImport* = ref object
  id: int           # index in file.imports
  source: string
  targetFileId: int # index in app.files
  names: seq[ResolvedImportName]
  loc: Location

proc newResolvedImport(id: int, source: string, targetFileId: int,
    names: seq[ResolvedImportName], loc: Location): ResolvedImport =
  ResolvedImport(id: id, source: source, targetFileId: targetFileId,
    names: names, loc: loc)

proc id*(imp: ResolvedImport): int = imp.id
proc source*(imp: ResolvedImport): string = imp.source
proc targetFileId*(imp: ResolvedImport): int = imp.targetFileId
proc names*(imp: ResolvedImport): seq[ResolvedImportName] = imp.names
proc loc*(imp: ResolvedImport): Location = imp.loc

proc resolveImport(imp: Import, id: int,
    fileIndex: Table[string, int]): Result[ResolvedImport, string] =
  if imp.path notin fileIndex:
    return err(fmt"import target '{imp.source}' not found in file index")
  var names: seq[ResolvedImportName]
  for nIdx, n in imp.names:
    names.add(resolveImportName(n, nIdx))
  ok(newResolvedImport(id, imp.source, fileIndex[imp.path], names, imp.loc))

# ============================================================
# ResolvedModule
# ============================================================

type ResolvedModule* = ref object
  id: int                    # index in file.modules
  decorators: seq[Decorator] # raw
  name: Identifier
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]
  loc: Location

proc newResolvedModule(id: int, decorators: seq[Decorator],
    name: Identifier, data: Option[ResolvedData],
    functions: seq[ResolvedFunction], loc: Location): ResolvedModule =
  ResolvedModule(id: id, decorators: decorators, name: name,
    data: data, functions: functions, loc: loc)

proc id*(m: ResolvedModule): int = m.id
proc decorators*(m: ResolvedModule): seq[Decorator] = m.decorators
proc name*(m: ResolvedModule): Identifier = m.name
proc data*(m: ResolvedModule): Option[ResolvedData] = m.data
proc functions*(m: ResolvedModule): seq[ResolvedFunction] = m.functions
proc loc*(m: ResolvedModule): Location = m.loc

proc resolveModule(m: Module, id: int): ResolvedModule =
  let data =
    if m.data.isSome: some(resolveData(m.data.get))
    else: none(ResolvedData)
  var functions: seq[ResolvedFunction]
  for i, fn in m.functions:
    functions.add(resolveFunction(fn, i))
  newResolvedModule(id, m.decorators, m.name, data, functions, m.loc)

# ============================================================
# ResolvedGeneric
# ============================================================

type ResolvedGeneric* = ref object
  id: int                    # index in file.generics
  decorators: seq[Decorator] # raw
  name: Identifier
  funcDefs: seq[ResolvedFuncDef]
  loc: Location

proc newResolvedGeneric(id: int, decorators: seq[Decorator],
    name: Identifier, funcDefs: seq[ResolvedFuncDef],
    loc: Location): ResolvedGeneric =
  ResolvedGeneric(id: id, decorators: decorators, name: name,
    funcDefs: funcDefs, loc: loc)

proc id*(g: ResolvedGeneric): int = g.id
proc decorators*(g: ResolvedGeneric): seq[Decorator] = g.decorators
proc name*(g: ResolvedGeneric): Identifier = g.name
proc funcDefs*(g: ResolvedGeneric): seq[ResolvedFuncDef] = g.funcDefs
proc loc*(g: ResolvedGeneric): Location = g.loc

proc resolveGeneric(g: Generic, id: int): ResolvedGeneric =
  var funcDefs: seq[ResolvedFuncDef]
  for i, fd in g.funcDefs:
    funcDefs.add(resolveFuncDef(fd, i))
  newResolvedGeneric(id, g.decorators, g.name, funcDefs, g.loc)

# ============================================================
# ResolvedFile
# ============================================================

type ResolvedFile* = ref object
  id: int # index in app.files
  path: string
  imports: seq[ResolvedImport]
  modules: seq[ResolvedModule]
  generics: seq[ResolvedGeneric]

proc newResolvedFile(id: int, path: string,
    imports: seq[ResolvedImport], modules: seq[ResolvedModule],
    generics: seq[ResolvedGeneric]): ResolvedFile =
  ResolvedFile(id: id, path: path, imports: imports,
    modules: modules, generics: generics)

proc id*(f: ResolvedFile): int = f.id
proc path*(f: ResolvedFile): string = f.path
proc imports*(f: ResolvedFile): seq[ResolvedImport] = f.imports
proc modules*(f: ResolvedFile): seq[ResolvedModule] = f.modules
proc generics*(f: ResolvedFile): seq[ResolvedGeneric] = f.generics

proc resolveFile(f: IndexedFile, id: int,
    fileIndex: Table[string, int]): Result[ResolvedFile, string] =
  var imports: seq[ResolvedImport]
  for impIdx, imp in f.file.imports:
    imports.add(? resolveImport(imp, impIdx, fileIndex))
  var modules: seq[ResolvedModule]
  for mIdx, m in f.file.modules:
    modules.add(resolveModule(m, mIdx))
  var generics: seq[ResolvedGeneric]
  for gIdx, g in f.file.generics:
    generics.add(resolveGeneric(g, gIdx))
  ok(newResolvedFile(id, f.file.path, imports, modules, generics))

# ============================================================
# ResolvedApp
# ============================================================

type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[string, int] # absolute path → index in files

proc newResolvedApp(files: seq[ResolvedFile],
    fileIndex: Table[string, int]): ResolvedApp =
  ResolvedApp(files: files, fileIndex: fileIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, path: string): int =
  app.fileIndex.getOrDefault(path, -1)

proc resolve*(app: App): Result[ResolvedApp, string] =
  # First pass: build fileIndex so imports can look up their targets.
  var fileIndex: Table[string, int]
  for i, f in app.files:
    fileIndex[f.file.path] = i
  # Second pass: resolve each file.
  var files: seq[ResolvedFile]
  for i, f in app.files:
    files.add(? resolveFile(f, i, fileIndex))
  ok(newResolvedApp(files, fileIndex))
