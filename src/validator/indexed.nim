import options, strformat, tables

import parser, tokenizer
export parser, tokenizer

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Indexed wrapper types
# ============================================================

type
  IndexedStruct* = ref object
    struct*: Struct
    fieldIndex*: Table[string, int]

  IndexedVariant* = ref object
    variant*: VariantDefinition
    fieldIndex*: Table[string, int]

  IndexedUnion* = ref object
    union*: Union
    variants*: seq[IndexedVariant]
    variantIndex*: Table[string, int]

  IndexedDataKind* = enum
    idkStruct, idkUnion
  IndexedData* = ref object
    case kind*: IndexedDataKind
    of idkStruct: struct*: IndexedStruct
    of idkUnion: union*: IndexedUnion

  IndexedModule* = ref object
    module*: Module
    data*: Option[IndexedData]
    functionIndex*: Table[string, seq[int]]

  IndexedGeneric* = ref object
    generic*: Generic
    funcDefIndex*: Table[string, seq[int]]

  IndexedFile* = ref object
    file*: File
    modules*: seq[IndexedModule]
    generics*: seq[IndexedGeneric]
    moduleIndex*: Table[string, int]
    genericIndex*: Table[string, int]
    importIndex*: Table[string, (int, int)]
      # visible name -> (import stmt idx, name idx)

  App* = ref object
    files*: seq[IndexedFile]
    fileIndex*: Table[string, int] # absolute path -> index in files

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
