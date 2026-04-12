import options, results, strformat, tables

import parser, validator, types

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# resolveArgumentType
# ============================================================

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
# resolveField
# ============================================================

proc resolveField(f: ArgumentDefinition, id: int,
    file: IndexedFile): Result[ResolvedField, string] =
  let argType = ? resolveArgumentType(f.argType, file)
  ok(newResolvedField(id, f.name, argType, f.loc))

# ============================================================
# resolveStruct
# ============================================================

proc resolveStruct(s: Struct,
    file: IndexedFile): Result[ResolvedStruct, string] =
  var fields: seq[ResolvedField]
  for i, f in s.fields:
    fields.add(? resolveField(f, i, file))
  ok(newResolvedStruct(fields, s.loc))

# ============================================================
# resolveVariant
# ============================================================

proc resolveVariant(v: VariantDefinition, id: int,
    file: IndexedFile): Result[ResolvedVariant, string] =
  var fields: seq[ResolvedField]
  for i, f in v.fields:
    fields.add(? resolveField(f, i, file))
  ok(newResolvedVariant(id, v.name, fields, v.loc))

# ============================================================
# resolveUnion
# ============================================================

proc resolveUnion(u: Union,
    file: IndexedFile): Result[ResolvedUnion, string] =
  var variants: seq[ResolvedVariant]
  for i, v in u.variants:
    variants.add(? resolveVariant(v, i, file))
  ok(newResolvedUnion(variants, u.loc))

# ============================================================
# resolveData
# ============================================================

proc resolveData(db: DataBlock,
    file: IndexedFile): Result[ResolvedData, string] =
  case db.kind:
  of dbkStruct: ok(newResolvedData(? resolveStruct(db.struct, file)))
  of dbkUnion:  ok(newResolvedData(? resolveUnion(db.union, file)))

# ============================================================
# resolveArgument
# ============================================================

proc resolveArgument(a: ArgumentDefinition, id: int,
    file: IndexedFile): Result[ResolvedArgument, string] =
  let argType = ? resolveArgumentType(a.argType, file)
  ok(newResolvedArgument(id, a.name, argType, a.loc))

# ============================================================
# resolveFunction
# ============================================================

proc resolveFunction(fn: Function, id: int,
    file: IndexedFile): Result[ResolvedFunction, string] =
  var params: seq[ResolvedArgument]
  for i, p in fn.def.params:
    params.add(? resolveArgument(p, i, file))
  let returns = ? resolveArgumentType(fn.def.returns, file)
  ok(newResolvedFunction(
    id, fn.decorators, fn.def.name, params,
    returns, fn.statementList, fn.def.loc,
  ))

# ============================================================
# resolveFuncDef
# ============================================================

proc resolveFuncDef(fd: FunctionDefinition, id: int,
    file: IndexedFile): Result[ResolvedFuncDef, string] =
  var params: seq[ResolvedArgument]
  for i, p in fd.params:
    params.add(? resolveArgument(p, i, file))
  let returns = ? resolveArgumentType(fd.returns, file)
  ok(newResolvedFuncDef(id, fd.name, params, returns, fd.loc))

# ============================================================
# resolveType
# ============================================================

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
# resolveImport
# ============================================================

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
# resolveModule
# ============================================================

proc resolveModule(m: Module, id: int,
    file: IndexedFile): Result[ResolvedModule, string] =
  let data =
    if m.data.isSome: some(? resolveData(m.data.get, file))
    else: none(ResolvedData)
  var functions: seq[ResolvedFunction]
  for i, fn in m.functions:
    functions.add(? resolveFunction(fn, i, file))
  ok(newResolvedModule(id, m.decorators, m.name, data, functions, m.loc))

# ============================================================
# resolveGeneric
# ============================================================

proc resolveGeneric(g: Generic, id: int,
    file: IndexedFile): Result[ResolvedGeneric, string] =
  var funcDefs: seq[ResolvedFuncDef]
  for i, fd in g.funcDefs:
    funcDefs.add(? resolveFuncDef(fd, i, file))
  ok(newResolvedGeneric(id, g.decorators, g.name, funcDefs, g.loc))

# ============================================================
# resolveFile
# ============================================================

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
    generics.add(? resolveGeneric(g, gIdx, f))
  ok(newResolvedFile(id, f.file.path, imports, modules, generics))

# ============================================================
# resolve (public entry point)
# ============================================================

proc resolve*(app: App): Result[ResolvedApp, string] =
  # app already has fileIndex populated by the validator.
  # Build a matching index for ResolvedApp in the same order.
  var fileIndex: Table[string, int]
  var files: seq[ResolvedFile]
  for i, f in app.files:
    fileIndex[f.file.path] = i
    files.add(? resolveFile(f, i, app))
  ok(newResolvedApp(files, fileIndex))
