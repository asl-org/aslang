import options, results, strformat, tables

import indexed, parser

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Indexing
# ============================================================

proc indexStruct(s: Struct, path: string): Result[IndexedStruct, string] =
  let indexed = IndexedStruct(struct: s)
  for i, f in s.fields:
    if indexed.fieldIndex.hasKey(f.name.value):
      return err(fmt"{path}:{f.name.loc}: struct: duplicate field '{f.name.value}'")
    indexed.fieldIndex[f.name.value] = i
  ok(indexed)

proc indexVariant(v: VariantDefinition,
    path: string): Result[IndexedVariant, string] =
  let indexed = IndexedVariant(variant: v)
  for i, f in v.fields:
    if indexed.fieldIndex.hasKey(f.name.value):
      return err(fmt"{path}:{f.name.loc}: variant '{v.name.value}': duplicate field '{f.name.value}'")
    indexed.fieldIndex[f.name.value] = i
  ok(indexed)

proc indexUnion(u: Union, path: string): Result[IndexedUnion, string] =
  let indexed = IndexedUnion(union: u)
  for i, v in u.variants:
    if indexed.variantIndex.hasKey(v.name.value):
      return err(fmt"{path}:{v.name.loc}: union: duplicate variant '{v.name.value}'")
    indexed.variantIndex[v.name.value] = i
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
    return err(fmt"{path}:{m.name.loc}: module '{m.name.value}': must have a data block or at least one function")

  let indexed = IndexedModule(module: m)
  for i, fn in m.functions:
    indexed.functionIndex.mgetOrPut(fn.name.value, @[]).add(i)

  if m.data.isSome:
    indexed.data = some(? indexData(m.data.get, path))
  else:
    indexed.data = none(IndexedData)
  ok(indexed)

proc indexGeneric(g: Generic,
    path: string): Result[IndexedGeneric, string] =
  let indexed = IndexedGeneric(generic: g)
  for i, fd in g.funcDefs:
    indexed.funcDefIndex.mgetOrPut(fd.name.value, @[]).add(i)
  ok(indexed)

proc indexFile(file: File): Result[IndexedFile, string] =
  # Rule 2: file must have at least one module or generic
  if file.modules.len == 0 and file.generics.len == 0:
    return err(fmt"{file.path}: file must have at least one module or generic")

  let indexed = IndexedFile(file: file)

  # Modules, generics, and import visible names share one namespace.
  for i, m in file.modules:
    if indexed.moduleIndex.hasKey(m.name.value) or
        indexed.genericIndex.hasKey(m.name.value) or
        indexed.importIndex.hasKey(m.name.value):
      return err(fmt"{file.path}:{m.name.loc}: duplicate name '{m.name.value}'")
    indexed.moduleIndex[m.name.value] = i
    indexed.modules.add(? indexModule(m, file.path))

  for i, g in file.generics:
    if indexed.moduleIndex.hasKey(g.name.value) or
        indexed.genericIndex.hasKey(g.name.value) or
        indexed.importIndex.hasKey(g.name.value):
      return err(fmt"{file.path}:{g.name.loc}: duplicate name '{g.name.value}'")
    indexed.genericIndex[g.name.value] = i
    indexed.generics.add(? indexGeneric(g, file.path))

  for impIdx, imp in file.imports:
    for nameIdx, n in imp.names:
      let visibleIdent = if n.alias.isSome: n.alias.get else: n.name
      let visible = visibleIdent.value
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
