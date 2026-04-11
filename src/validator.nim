import options, results, strformat, tables

import parser
export parser

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Indexed wrapper types
# ============================================================

type
  IndexedStruct* = ref object
    struct: Struct
    fieldIndex: Table[string, int]

  IndexedVariant* = ref object
    variant: VariantDefinition
    fieldIndex: Table[string, int]

  IndexedUnion* = ref object
    union: Union
    variants: seq[IndexedVariant]
    variantIndex: Table[string, int]

  IndexedDataKind* = enum
    idkStruct, idkUnion
  IndexedData* = ref object
    case kind: IndexedDataKind
    of idkStruct: struct: IndexedStruct
    of idkUnion: union: IndexedUnion

  IndexedModule* = ref object
    module: Module
    data: Option[IndexedData]
    functionIndex: Table[string, seq[int]]

  IndexedGeneric* = ref object
    generic: Generic
    funcDefIndex: Table[string, seq[int]]

  IndexedFile* = ref object
    file: File
    modules: seq[IndexedModule]
    generics: seq[IndexedGeneric]
    moduleIndex: Table[string, int]
    genericIndex: Table[string, int]
    importIndex: Table[string, (int, int)]
      # visible name → (import stmt idx, name idx)

  App* = ref object
    files: seq[IndexedFile]
    fileIndex: Table[string, int] # absolute path → index in files

# ============================================================
# Readonly accessors
# ============================================================

proc file*(f: IndexedFile): File = f.file
proc modules*(f: IndexedFile): seq[IndexedModule] = f.modules
proc generics*(f: IndexedFile): seq[IndexedGeneric] = f.generics

proc module*(m: IndexedModule): Module = m.module
proc data*(m: IndexedModule): Option[IndexedData] = m.data

proc generic*(g: IndexedGeneric): Generic = g.generic

proc kind*(d: IndexedData): IndexedDataKind = d.kind
proc struct*(d: IndexedData): IndexedStruct =
  assert d.kind == idkStruct,
    fmt"IndexedData.struct accessed but kind is {d.kind}"
  d.struct
proc union*(d: IndexedData): IndexedUnion =
  assert d.kind == idkUnion,
    fmt"IndexedData.union accessed but kind is {d.kind}"
  d.union

proc struct*(s: IndexedStruct): Struct = s.struct
proc union*(u: IndexedUnion): Union = u.union
proc variants*(u: IndexedUnion): seq[IndexedVariant] = u.variants
proc variant*(v: IndexedVariant): VariantDefinition = v.variant

proc files*(app: App): seq[IndexedFile] = app.files

# ============================================================
# Lookups
# ============================================================

proc findFile*(app: App, path: string): int =
  app.fileIndex.getOrDefault(path, -1)

proc findModule*(file: IndexedFile, name: string): int =
  file.moduleIndex.getOrDefault(name, -1)

proc findGeneric*(file: IndexedFile, name: string): int =
  file.genericIndex.getOrDefault(name, -1)

proc findImport*(file: IndexedFile, visibleName: string): (int, int) =
  file.importIndex.getOrDefault(visibleName, (-1, -1))

proc findFunction*(module: IndexedModule, name: string): seq[int] =
  module.functionIndex.getOrDefault(name, @[])

proc findFuncDef*(generic: IndexedGeneric, name: string): seq[int] =
  generic.funcDefIndex.getOrDefault(name, @[])

proc findField*(s: IndexedStruct, name: string): int =
  s.fieldIndex.getOrDefault(name, -1)

proc findField*(v: IndexedVariant, name: string): int =
  v.fieldIndex.getOrDefault(name, -1)

proc findVariant*(u: IndexedUnion, name: string): int =
  u.variantIndex.getOrDefault(name, -1)

# ============================================================
# Indexing
# ============================================================

proc indexStruct(s: Struct, path: string): Result[IndexedStruct, string] =
  let indexed = IndexedStruct(struct: s)
  for i, f in s.fields:
    if indexed.fieldIndex.hasKey(f.name.name):
      return err(fmt"{path}:{f.name.loc}: struct: duplicate field '{f.name.name}'")
    indexed.fieldIndex[f.name.name] = i
  ok(indexed)

proc indexVariant(v: VariantDefinition,
    path: string): Result[IndexedVariant, string] =
  let indexed = IndexedVariant(variant: v)
  for i, f in v.fields:
    if indexed.fieldIndex.hasKey(f.name.name):
      return err(fmt"{path}:{f.name.loc}: variant '{v.name.name}': duplicate field '{f.name.name}'")
    indexed.fieldIndex[f.name.name] = i
  ok(indexed)

proc indexUnion(u: Union, path: string): Result[IndexedUnion, string] =
  let indexed = IndexedUnion(union: u)
  for i, v in u.variants:
    if indexed.variantIndex.hasKey(v.name.name):
      return err(fmt"{path}:{v.name.loc}: union: duplicate variant '{v.name.name}'")
    indexed.variantIndex[v.name.name] = i
    indexed.variants.add(? indexVariant(v, path))
  ok(indexed)

proc indexData(db: DataBlock, path: string): Result[IndexedData, string] =
  case db.kind:
  of dbkStruct:
    let s = ? indexStruct(db.struct, path)
    ok(IndexedData(kind: idkStruct, struct: s))
  of dbkUnion:
    let u = ? indexUnion(db.union, path)
    ok(IndexedData(kind: idkUnion, union: u))

proc indexModule(m: Module, path: string): Result[IndexedModule, string] =
  # Rule 4: module must have data or at least one function
  if m.data.isNone and m.functions.len == 0:
    return err(fmt"{path}:{m.name.loc}: module '{m.name.name}': must have a data block or at least one function")

  let indexed = IndexedModule(module: m)
  for i, fn in m.functions:
    indexed.functionIndex.mgetOrPut(fn.name.name, @[]).add(i)

  if m.data.isSome:
    indexed.data = some(? indexData(m.data.get, path))
  else:
    indexed.data = none(IndexedData)
  ok(indexed)

proc indexGeneric(g: Generic,
    path: string): Result[IndexedGeneric, string] =
  let indexed = IndexedGeneric(generic: g)
  for i, fd in g.funcDefs:
    indexed.funcDefIndex.mgetOrPut(fd.name.name, @[]).add(i)
  ok(indexed)

proc indexFile(file: File): Result[IndexedFile, string] =
  # Rule 2: file must have at least one module or generic
  if file.modules.len == 0 and file.generics.len == 0:
    return err(fmt"{file.path}: file must have at least one module or generic")

  let indexed = IndexedFile(file: file)

  # Modules, generics, and import visible names share one namespace.
  for i, m in file.modules:
    if indexed.moduleIndex.hasKey(m.name.name) or
        indexed.genericIndex.hasKey(m.name.name) or
        indexed.importIndex.hasKey(m.name.name):
      return err(fmt"{file.path}:{m.name.loc}: duplicate name '{m.name.name}'")
    indexed.moduleIndex[m.name.name] = i
    indexed.modules.add(? indexModule(m, file.path))

  for i, g in file.generics:
    if indexed.moduleIndex.hasKey(g.name.name) or
        indexed.genericIndex.hasKey(g.name.name) or
        indexed.importIndex.hasKey(g.name.name):
      return err(fmt"{file.path}:{g.name.loc}: duplicate name '{g.name.name}'")
    indexed.genericIndex[g.name.name] = i
    indexed.generics.add(? indexGeneric(g, file.path))

  for impIdx, imp in file.imports:
    for nameIdx, n in imp.names:
      let visibleIdent = if n.alias.isSome: n.alias.get else: n.name
      let visible = visibleIdent.name
      if indexed.moduleIndex.hasKey(visible) or
          indexed.genericIndex.hasKey(visible) or
          indexed.importIndex.hasKey(visible):
        return err(fmt"{file.path}:{visibleIdent.loc}: duplicate name '{visible}'")
      indexed.importIndex[visible] = (impIdx, nameIdx)

  ok(indexed)

proc index*(files: seq[File]): Result[App, string] =
  let app = App()
  for i, f in files:
    if app.fileIndex.hasKey(f.path):
      return err(fmt"duplicate file path '{f.path}'")
    app.fileIndex[f.path] = i
    app.files.add(? indexFile(f))
  ok(app)
