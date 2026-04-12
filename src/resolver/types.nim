import options, strformat, tables

import tokenizer, parser, validator
export validator

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
    argType*: ArgumentType             # raw AST -- source of root, loc
    impls*: seq[ResolvedArgumentType]  # recursively resolved type params
    case kind*: ResolvedArgumentTypeKind
    of ratPrimitive: primitiveId*: int  # index in primitives table
    of ratModule:    moduleId*: int     # index in current file's modules
    of ratGeneric:   genericId*: int    # index in current file's generics
    of ratImported:
      importId*: int     # index in current file's imports
      importTypeId*: int # index in import.types

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

# ============================================================
# ResolvedField (struct field or variant field)
# ============================================================

type ResolvedField* = ref object
  id: int # index in parent fields list
  name: Identifier
  argType: ResolvedArgumentType
  loc: Location

proc newResolvedField*(id: int, name: Identifier,
    argType: ResolvedArgumentType, loc: Location): ResolvedField =
  ResolvedField(id: id, name: name, argType: argType, loc: loc)

proc id*(f: ResolvedField): int = f.id
proc name*(f: ResolvedField): Identifier = f.name
proc argType*(f: ResolvedField): ResolvedArgumentType = f.argType
proc loc*(f: ResolvedField): Location = f.loc

# ============================================================
# ResolvedStruct
# ============================================================

type ResolvedStruct* = ref object
  fields: seq[ResolvedField]
  loc: Location

proc newResolvedStruct*(fields: seq[ResolvedField],
    loc: Location): ResolvedStruct =
  ResolvedStruct(fields: fields, loc: loc)

proc fields*(s: ResolvedStruct): seq[ResolvedField] = s.fields
proc loc*(s: ResolvedStruct): Location = s.loc

# ============================================================
# ResolvedVariant
# ============================================================

type ResolvedVariant* = ref object
  id: int # index in union.variants
  name: Identifier
  fields: seq[ResolvedField]
  loc: Location

proc newResolvedVariant*(id: int, name: Identifier,
    fields: seq[ResolvedField], loc: Location): ResolvedVariant =
  ResolvedVariant(id: id, name: name, fields: fields, loc: loc)

proc id*(v: ResolvedVariant): int = v.id
proc name*(v: ResolvedVariant): Identifier = v.name
proc fields*(v: ResolvedVariant): seq[ResolvedField] = v.fields
proc loc*(v: ResolvedVariant): Location = v.loc

# ============================================================
# ResolvedUnion
# ============================================================

type ResolvedUnion* = ref object
  variants: seq[ResolvedVariant]
  loc: Location

proc newResolvedUnion*(variants: seq[ResolvedVariant],
    loc: Location): ResolvedUnion =
  ResolvedUnion(variants: variants, loc: loc)

proc variants*(u: ResolvedUnion): seq[ResolvedVariant] = u.variants
proc loc*(u: ResolvedUnion): Location = u.loc

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

proc newResolvedData*(s: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: s)

proc newResolvedData*(u: ResolvedUnion): ResolvedData =
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

# ============================================================
# ResolvedArgument (function or funcDef parameter)
# ============================================================

type ResolvedArgument* = ref object
  id: int # index in parent params list
  name: Identifier
  argType: ResolvedArgumentType
  loc: Location

proc newResolvedArgument*(id: int, name: Identifier,
    argType: ResolvedArgumentType, loc: Location): ResolvedArgument =
  ResolvedArgument(id: id, name: name, argType: argType, loc: loc)

proc id*(a: ResolvedArgument): int = a.id
proc name*(a: ResolvedArgument): Identifier = a.name
proc argType*(a: ResolvedArgument): ResolvedArgumentType = a.argType
proc loc*(a: ResolvedArgument): Location = a.loc

# ============================================================
# ResolvedFunction
# ============================================================

type ResolvedFunction* = ref object
  id: int                    # index in module.functions
  decorators: seq[Decorator] # raw
  name: Identifier
  params: seq[ResolvedArgument]
  returns: ResolvedArgumentType
  body: StatementList        # raw -- Phase 3 resolves
  loc: Location

proc newResolvedFunction*(id: int, decorators: seq[Decorator],
    name: Identifier, params: seq[ResolvedArgument],
    returns: ResolvedArgumentType, body: StatementList,
    loc: Location): ResolvedFunction =
  ResolvedFunction(id: id, decorators: decorators, name: name,
    params: params, returns: returns, body: body, loc: loc)

proc id*(fn: ResolvedFunction): int = fn.id
proc decorators*(fn: ResolvedFunction): seq[Decorator] = fn.decorators
proc name*(fn: ResolvedFunction): Identifier = fn.name
proc params*(fn: ResolvedFunction): seq[ResolvedArgument] = fn.params
proc returns*(fn: ResolvedFunction): ResolvedArgumentType = fn.returns
proc body*(fn: ResolvedFunction): StatementList = fn.body
proc loc*(fn: ResolvedFunction): Location = fn.loc

# ============================================================
# ResolvedFuncDef
# ============================================================

type ResolvedFuncDef* = ref object
  id: int # index in generic.funcDefs
  name: Identifier
  params: seq[ResolvedArgument]
  returns: ResolvedArgumentType
  loc: Location

proc newResolvedFuncDef*(id: int, name: Identifier,
    params: seq[ResolvedArgument], returns: ResolvedArgumentType,
    loc: Location): ResolvedFuncDef =
  ResolvedFuncDef(id: id, name: name, params: params,
    returns: returns, loc: loc)

proc id*(fd: ResolvedFuncDef): int = fd.id
proc name*(fd: ResolvedFuncDef): Identifier = fd.name
proc params*(fd: ResolvedFuncDef): seq[ResolvedArgument] = fd.params
proc returns*(fd: ResolvedFuncDef): ResolvedArgumentType = fd.returns
proc loc*(fd: ResolvedFuncDef): Location = fd.loc

# ============================================================
# ResolvedType
# ============================================================

type
  ResolvedTypeKind* = enum
    rtkModule, rtkGeneric

  ResolvedType* = ref object
    id: int                 # index in imp.names
    importName: ImportName  # raw AST -- source of name, alias, loc
    case kind: ResolvedTypeKind
    of rtkModule:  moduleId: int  # index in target file's modules
    of rtkGeneric: genericId: int # index in target file's generics

proc newResolvedType*(id: int, importName: ImportName,
    moduleId: int): ResolvedType =
  ResolvedType(id: id, importName: importName,
    kind: rtkModule, moduleId: moduleId)

proc newResolvedType*(id: int, importName: ImportName,
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

# ============================================================
# ResolvedImport
# ============================================================

type ResolvedImport* = ref object
  id: int              # index in file.imports
  imp: Import          # raw AST -- source of source, loc, raw names
  targetFileId: int    # index in app.files
  types: seq[ResolvedType]

proc newResolvedImport*(id: int, imp: Import, targetFileId: int,
    types: seq[ResolvedType]): ResolvedImport =
  ResolvedImport(id: id, imp: imp, targetFileId: targetFileId, types: types)

proc id*(r: ResolvedImport): int = r.id
proc imp*(r: ResolvedImport): Import = r.imp
proc source*(r: ResolvedImport): string = r.imp.source
proc targetFileId*(r: ResolvedImport): int = r.targetFileId
proc types*(r: ResolvedImport): seq[ResolvedType] = r.types
proc loc*(r: ResolvedImport): Location = r.imp.loc

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

proc newResolvedModule*(id: int, decorators: seq[Decorator],
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

# ============================================================
# ResolvedGeneric
# ============================================================

type ResolvedGeneric* = ref object
  id: int                    # index in file.generics
  decorators: seq[Decorator] # raw
  name: Identifier
  funcDefs: seq[ResolvedFuncDef]
  loc: Location

proc newResolvedGeneric*(id: int, decorators: seq[Decorator],
    name: Identifier, funcDefs: seq[ResolvedFuncDef],
    loc: Location): ResolvedGeneric =
  ResolvedGeneric(id: id, decorators: decorators, name: name,
    funcDefs: funcDefs, loc: loc)

proc id*(g: ResolvedGeneric): int = g.id
proc decorators*(g: ResolvedGeneric): seq[Decorator] = g.decorators
proc name*(g: ResolvedGeneric): Identifier = g.name
proc funcDefs*(g: ResolvedGeneric): seq[ResolvedFuncDef] = g.funcDefs
proc loc*(g: ResolvedGeneric): Location = g.loc

# ============================================================
# ResolvedFile
# ============================================================

type ResolvedFile* = ref object
  id: int # index in app.files
  path: string
  imports: seq[ResolvedImport]
  modules: seq[ResolvedModule]
  generics: seq[ResolvedGeneric]

proc newResolvedFile*(id: int, path: string,
    imports: seq[ResolvedImport], modules: seq[ResolvedModule],
    generics: seq[ResolvedGeneric]): ResolvedFile =
  ResolvedFile(id: id, path: path, imports: imports,
    modules: modules, generics: generics)

proc id*(f: ResolvedFile): int = f.id
proc path*(f: ResolvedFile): string = f.path
proc imports*(f: ResolvedFile): seq[ResolvedImport] = f.imports
proc modules*(f: ResolvedFile): seq[ResolvedModule] = f.modules
proc generics*(f: ResolvedFile): seq[ResolvedGeneric] = f.generics

# ============================================================
# ResolvedApp
# ============================================================

type ResolvedApp* = ref object
  files: seq[ResolvedFile]
  fileIndex: Table[string, int] # absolute path -> index in files

proc newResolvedApp*(files: seq[ResolvedFile],
    fileIndex: Table[string, int]): ResolvedApp =
  ResolvedApp(files: files, fileIndex: fileIndex)

proc files*(app: ResolvedApp): seq[ResolvedFile] = app.files
proc findFile*(app: ResolvedApp, path: string): int =
  app.fileIndex.getOrDefault(path, -1)
