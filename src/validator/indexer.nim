import options, results, strformat, tables

import indexed, parser

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Indexing
# ============================================================

proc indexStruct(s: Struct): IndexedStruct =
  let indexed = IndexedStruct(struct: s)
  for i, f in s.fields:
    indexed.fieldIndex[f.name.value] = i
  indexed

proc indexVariant(v: VariantDefinition): IndexedVariant =
  let indexed = IndexedVariant(variant: v)
  for i, f in v.fields:
    indexed.fieldIndex[f.name.value] = i
  indexed

proc indexUnion(u: Union): IndexedUnion =
  let indexed = IndexedUnion(union: u)
  for i, v in u.variants:
    indexed.variantIndex[v.name.value] = i
    indexed.variants.add(indexVariant(v))
  indexed

proc indexData(db: DataBlock): IndexedData =
  case db.kind:
  of dbkStruct:
    IndexedData(kind: idkStruct, struct: indexStruct(db.struct))
  of dbkUnion:
    IndexedData(kind: idkUnion, union: indexUnion(db.union))

proc indexModule(m: Module): IndexedModule =
  let indexed = IndexedModule(module: m)
  for i, fn in m.functions:
    indexed.functionIndex.mgetOrPut(fn.name.value, @[]).add(i)

  if m.data.isSome:
    indexed.data = some(indexData(m.data.get))
  else:
    indexed.data = none(IndexedData)
  indexed

proc indexGeneric(g: Generic): IndexedGeneric =
  let indexed = IndexedGeneric(generic: g)
  for i, fd in g.funcDefs:
    indexed.funcDefIndex.mgetOrPut(fd.name.value, @[]).add(i)
  indexed

proc indexFile(file: File): Result[IndexedFile, string] =
  # Rule 2: file must have at least one module or generic
  if file.modules.len == 0 and file.generics.len == 0:
    return err(fmt"{file.path}: file must have at least one module or generic")

  let indexed = IndexedFile(file: file)

  # Build module and generic indices.
  # Duplicate module/generic names and module-generic conflicts are
  # already caught by the parser (newFile's typeSet). Only the
  # import-namespace conflict checks remain here.
  for i, m in file.modules:
    if indexed.importIndex.hasKey(m.name.value):
      return err(fmt"{file.path}:{m.name.loc}: module name '{m.name.value}' conflicts with an imported name")
    indexed.moduleIndex[m.name.value] = i
    indexed.modules.add(indexModule(m))

  for i, g in file.generics:
    if indexed.importIndex.hasKey(g.name.value):
      return err(fmt"{file.path}:{g.name.loc}: generic name '{g.name.value}' conflicts with an imported name")
    indexed.genericIndex[g.name.value] = i
    indexed.generics.add(indexGeneric(g))

  for impIdx, imp in file.imports:
    for nameIdx, n in imp.names:
      let visibleIdent = if n.alias.isSome: n.alias.get else: n.name
      let visible = visibleIdent.value
      if indexed.moduleIndex.hasKey(visible) or
          indexed.genericIndex.hasKey(visible) or
          indexed.importIndex.hasKey(visible):
        return err(fmt"{file.path}:{visibleIdent.loc}: import name '{visible}' conflicts with an existing name")
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
