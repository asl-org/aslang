import options, results, strformat, tables

import parser, tokenizer, validator
export parser, tokenizer, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Built-in primitive types
# ============================================================

const primitives* = [
  # Fixed-width integers
  "i8", "i16", "i32", "i64",
  "u8", "u16", "u32", "u64",
  # Fixed-width floats
  "f32", "f64",
  # Raw pointer
  "ptr",
  # Built-in containers and types
  "String", "List", "Map", "Array", "Status",
  # System interface
  "System",
]

proc primitiveId*(name: string): int =
  ## Returns the index of `name` in the primitives table, or -1.
  for i, p in primitives:
    if p == name: return i
  -1

# ============================================================
# ResolvedArgumentType
# ============================================================

type
  ResolvedArgumentTypeKind* = enum
    ratPrimitive
    ratModule
    ratGeneric
    ratImported

  ResolvedArgumentType* = ref object
    argType: ArgumentType             # raw AST — source of root, loc
    impls: seq[ResolvedArgumentType]  # recursively resolved type params
    case kind: ResolvedArgumentTypeKind
    of ratPrimitive: primitiveId: int  # index in primitives table
    of ratModule:    moduleId: int     # index in current file's modules
    of ratGeneric:   genericId: int    # index in current file's generics
    of ratImported:
      importId: int     # index in current file's imports
      importTypeId: int # index in import.types

proc argType*(t: ResolvedArgumentType): ArgumentType = t.argType
proc impls*(t: ResolvedArgumentType): seq[ResolvedArgumentType] = t.impls
proc loc*(t: ResolvedArgumentType): Location = t.argType.loc
proc kind*(t: ResolvedArgumentType): ResolvedArgumentTypeKind = t.kind
proc primitiveId*(t: ResolvedArgumentType): int =
  assert t.kind == ratPrimitive,
    fmt"ResolvedArgumentType.primitiveId accessed but kind is {t.kind}"
  t.primitiveId
proc moduleId*(t: ResolvedArgumentType): int =
  assert t.kind == ratModule,
    fmt"ResolvedArgumentType.moduleId accessed but kind is {t.kind}"
  t.moduleId
proc genericId*(t: ResolvedArgumentType): int =
  assert t.kind == ratGeneric,
    fmt"ResolvedArgumentType.genericId accessed but kind is {t.kind}"
  t.genericId
proc importId*(t: ResolvedArgumentType): int =
  assert t.kind == ratImported,
    fmt"ResolvedArgumentType.importId accessed but kind is {t.kind}"
  t.importId
proc importTypeId*(t: ResolvedArgumentType): int =
  assert t.kind == ratImported,
    fmt"ResolvedArgumentType.importTypeId accessed but kind is {t.kind}"
  t.importTypeId

proc resolveArgumentType(a: ArgumentType,
    file: IndexedFile): Result[ResolvedArgumentType, string] =
  var impls: seq[ResolvedArgumentType]
  for impl in a.impls:
    impls.add(? resolveArgumentType(impl, file))

  let root = a.root.value

  # 1. Primitive built-in?
  let primId = primitiveId(root)
  if primId >= 0:
    return ok(ResolvedArgumentType(argType: a, impls: impls,
      kind: ratPrimitive, primitiveId: primId))

  # 2. Module in current file?
  let modId = file.findModule(root)
  if modId >= 0:
    return ok(ResolvedArgumentType(argType: a, impls: impls,
      kind: ratModule, moduleId: modId))

  # 3. Generic in current file?
  let genId = file.findGeneric(root)
  if genId >= 0:
    return ok(ResolvedArgumentType(argType: a, impls: impls,
      kind: ratGeneric, genericId: genId))

  # 4. Imported name?
  let (impId, impNameId) = file.findImport(root)
  if impId >= 0:
    return ok(ResolvedArgumentType(argType: a, impls: impls,
      kind: ratImported, importId: impId, importTypeId: impNameId))

  err(fmt"{file.file.path}:{a.loc}: unknown type '{root}'")

# ============================================================
# ResolvedField (struct field or variant field)
# ============================================================

type ResolvedField* = ref object
  id: int # index in parent fields list
  name: Identifier
  argType: ResolvedArgumentType
  loc: Location

proc newResolvedField(id: int, name: Identifier,
    argType: ResolvedArgumentType, loc: Location): ResolvedField =
  ResolvedField(id: id, name: name, argType: argType, loc: loc)

proc id*(f: ResolvedField): int = f.id
proc name*(f: ResolvedField): Identifier = f.name
proc argType*(f: ResolvedField): ResolvedArgumentType = f.argType
proc loc*(f: ResolvedField): Location = f.loc

proc resolveField(f: ArgumentDefinition, id: int,
    file: IndexedFile): Result[ResolvedField, string] =
  let argType = ? resolveArgumentType(f.argType, file)
  ok(newResolvedField(id, f.name, argType, f.loc))

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

proc resolveStruct(s: Struct,
    file: IndexedFile): Result[ResolvedStruct, string] =
  var fields: seq[ResolvedField]
  for i, f in s.fields:
    fields.add(? resolveField(f, i, file))
  ok(newResolvedStruct(fields, s.loc))

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

proc resolveVariant(v: VariantDefinition, id: int,
    file: IndexedFile): Result[ResolvedVariant, string] =
  var fields: seq[ResolvedField]
  for i, f in v.fields:
    fields.add(? resolveField(f, i, file))
  ok(newResolvedVariant(id, v.name, fields, v.loc))

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

proc resolveUnion(u: Union,
    file: IndexedFile): Result[ResolvedUnion, string] =
  var variants: seq[ResolvedVariant]
  for i, v in u.variants:
    variants.add(? resolveVariant(v, i, file))
  ok(newResolvedUnion(variants, u.loc))

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

proc resolveData(db: DataBlock,
    file: IndexedFile): Result[ResolvedData, string] =
  case db.kind:
  of dbkStruct: ok(newResolvedData(? resolveStruct(db.struct, file)))
  of dbkUnion:  ok(newResolvedData(? resolveUnion(db.union, file)))

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
# ResolvedType
# ============================================================

type
  ResolvedTypeKind* = enum
    rtkModule, rtkGeneric

  ResolvedType* = ref object
    id: int                 # index in imp.names
    importName: ImportName  # raw AST — source of name, alias, loc
    case kind: ResolvedTypeKind
    of rtkModule:  moduleId: int  # index in target file's modules
    of rtkGeneric: genericId: int # index in target file's generics

proc newResolvedType(id: int, importName: ImportName,
    moduleId: int): ResolvedType =
  ResolvedType(id: id, importName: importName,
    kind: rtkModule, moduleId: moduleId)

proc newResolvedType(id: int, importName: ImportName,
    genericId: int, isGeneric: bool): ResolvedType =
  # isGeneric exists only to disambiguate the overload from the
  # module variant above; both carry a single int payload.
  discard isGeneric
  ResolvedType(id: id, importName: importName,
    kind: rtkGeneric, genericId: genericId)

proc id*(t: ResolvedType): int = t.id
proc importName*(t: ResolvedType): ImportName = t.importName
proc name*(t: ResolvedType): Identifier = t.importName.name
proc alias*(t: ResolvedType): Option[Identifier] = t.importName.alias
proc loc*(t: ResolvedType): Location = t.importName.loc
proc kind*(t: ResolvedType): ResolvedTypeKind = t.kind
proc moduleId*(t: ResolvedType): int =
  assert t.kind == rtkModule,
    fmt"ResolvedType.moduleId accessed but kind is {t.kind}"
  t.moduleId
proc genericId*(t: ResolvedType): int =
  assert t.kind == rtkGeneric,
    fmt"ResolvedType.genericId accessed but kind is {t.kind}"
  t.genericId

proc resolveType(n: ImportName, id: int,
    target: IndexedFile,
    importingPath: string): Result[ResolvedType, string] =
  let key = n.name.value
  let mId = target.findModule(key)
  if mId >= 0:
    return ok(newResolvedType(id, n, mId))
  let gId = target.findGeneric(key)
  if gId >= 0:
    return ok(newResolvedType(id, n, gId, isGeneric = true))
  err(fmt"{importingPath}:{n.loc}: import name '{key}' not found in '{target.file.path}'")

# ============================================================
# ResolvedImport
# ============================================================

type ResolvedImport* = ref object
  id: int              # index in file.imports
  imp: Import          # raw AST — source of source, loc, raw names
  targetFileId: int    # index in app.files
  types: seq[ResolvedType]

proc newResolvedImport(id: int, imp: Import, targetFileId: int,
    types: seq[ResolvedType]): ResolvedImport =
  ResolvedImport(id: id, imp: imp, targetFileId: targetFileId, types: types)

proc id*(r: ResolvedImport): int = r.id
proc imp*(r: ResolvedImport): Import = r.imp
proc source*(r: ResolvedImport): string = r.imp.source
proc targetFileId*(r: ResolvedImport): int = r.targetFileId
proc types*(r: ResolvedImport): seq[ResolvedType] = r.types
proc loc*(r: ResolvedImport): Location = r.imp.loc

proc resolveImport(imp: Import, id: int, app: App,
    importingPath: string): Result[ResolvedImport, string] =
  let targetFileId = app.findFile(imp.path)
  if targetFileId < 0:
    return err(fmt"{importingPath}:{imp.loc}: import target '{imp.source}' not found in file index")
  let target = app.files[targetFileId]
  var types: seq[ResolvedType]
  for nIdx, n in imp.names:
    types.add(? resolveType(n, nIdx, target, importingPath))
  ok(newResolvedImport(id, imp, targetFileId, types))

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

proc resolveModule(m: Module, id: int,
    file: IndexedFile): Result[ResolvedModule, string] =
  let data =
    if m.data.isSome: some(? resolveData(m.data.get, file))
    else: none(ResolvedData)
  var functions: seq[ResolvedFunction]
  for i, fn in m.functions:
    functions.add(resolveFunction(fn, i))
  ok(newResolvedModule(id, m.decorators, m.name, data, functions, m.loc))

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
    app: App): Result[ResolvedFile, string] =
  var imports: seq[ResolvedImport]
  for impIdx, imp in f.file.imports:
    imports.add(? resolveImport(imp, impIdx, app, f.file.path))
  var modules: seq[ResolvedModule]
  for mIdx, m in f.file.modules:
    modules.add(? resolveModule(m, mIdx, f))
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
  # app already has fileIndex populated by the validator.
  # Build a matching index for ResolvedApp in the same order.
  var fileIndex: Table[string, int]
  var files: seq[ResolvedFile]
  for i, f in app.files:
    fileIndex[f.file.path] = i
    files.add(? resolveFile(f, i, app))
  ok(newResolvedApp(files, fileIndex))
