import strformat, strutils, options, tables, results

import tokenizer
import combinators
import helpers
import identifiers
import literals
import imports
import argtypes
import funcdefs
import body

# ============================================================
# Struct
# ============================================================

type Struct* = ref object
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc fields*(s: Struct): seq[ArgumentDefinition] = s.fields
proc loc*(s: Struct): Location = s.loc

proc newStruct*(fields: seq[ArgumentDefinition], loc: Location): Result[Struct, ParserError] =
  if fields.len == 0:
    return err(newParserError("struct must have at least one field", loc))
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(Struct(fields: fields, fieldIndex: fieldIndex, loc: loc))

proc asl(s: Struct, indentWidth: uint32): seq[string] =
  result.add("struct:")
  let indent = " ".repeat(indentWidth)
  for field in s.fields:
    result.add(fmt"{indent}{asl(field)}")

proc findFieldId*(struct: Struct, name: Identifier): Result[int, string] =
  if name notin struct.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` is not present in the struct")
  else:
    ok(struct.fieldIndex[name])

# struct: field+ (field is identifier ":" argumentType)
let structHeaderSpec = Spec[Location](
  name: "struct_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("struct"))
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

# Each field line: indentation + argumentDefinition + newline
let fieldLineSpec = Spec[ArgumentDefinition](
  name: "field_line",
  parseFn: proc(parser: Parser): Result[ArgumentDefinition, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  discard ? parser.run(indentationSpec)
  let argDef = ? parser.run(argumentDefinitionSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(argDef)
)

let structSpec* = blockSpec("struct", structHeaderSpec,
  atLeastOne(fieldLineSpec),
  proc(h: Location, b: seq[ArgumentDefinition]): Result[Struct, ParserError] =
  newStruct(b, h))

# ============================================================
# VariantDefinition
# ============================================================

type VariantDefinition* = ref object
  name: Identifier
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc newVariantDefinition*(name: Identifier, fields: seq[ArgumentDefinition],
    loc: Location): Result[VariantDefinition, ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(VariantDefinition(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc name*(v: VariantDefinition): Identifier = v.name
proc fields*(v: VariantDefinition): seq[ArgumentDefinition] = v.fields
proc loc*(v: VariantDefinition): Location = v.loc

proc asl(varDef: VariantDefinition): string =
  result = asl(varDef.name)
  if varDef.fields.len > 0:
    result.add(" { ")
    for i, field in varDef.fields:
      if i > 0: result.add(", ")
      result.add(asl(field))
    result.add(" }")

proc findFieldId*(variant: VariantDefinition, name: Identifier): Result[int, string] =
  if name notin variant.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` does not exist in union variant `{variant.name.asl}`")
  else:
    ok(variant.fieldIndex[name])

# union: variant+ (variant is identifier space* ("{" argDef, argDef "}")?)
let variantDefinitionLineSpec = Spec[VariantDefinition](
  name: "variant_definition_line",
  parseFn: proc(parser: Parser): Result[VariantDefinition, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  discard ? parser.run(indentationSpec)
  let name = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  let maybeFields = ? parser.run(optional(contained("variant_fields", "{",
    separatedBy(argumentDefinitionSpec, commaWithSpacesSpec), "}")))
  var fields: seq[ArgumentDefinition]
  if maybeFields.isSome: fields = maybeFields.get
  discard ? parser.run(ignorableLineSpec)
  newVariantDefinition(name, fields, name.loc)
)

# ============================================================
# Union
# ============================================================

type Union* = ref object
  variants: seq[VariantDefinition]
  variantIndex: Table[Identifier, int]
  loc: Location

proc newUnion*(variants: seq[VariantDefinition], loc: Location): Result[Union, ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(Union(variants: variants, variantIndex: variantIndex, loc: loc))

proc variants*(u: Union): seq[VariantDefinition] = u.variants
proc loc*(u: Union): Location = u.loc

proc asl(u: Union, indentWidth: uint32): seq[string] =
  result.add("union:")
  let indent = " ".repeat(indentWidth)
  for variant in u.variants:
    result.add(fmt"{indent}{asl(variant)}")

proc findVariantId(union: Union, variant: Identifier): Result[int, string] =
  if variant notin union.variantIndex:
    err(fmt"{variant.loc} variant `{variant.asl}` does not exist in union")
  else:
    ok(union.variantIndex[variant])

proc findVariant*(union: Union, variant: Identifier): Result[VariantDefinition, string] =
  let variantId = ? union.findVariantId(variant)
  ok(union.variants[variantId])

let unionHeaderSpec = Spec[Location](
  name: "union_header",
  parseFn: proc(parser: Parser): Result[Location, ParserError] =
  let loc = ? parser.run(keywordSpec("union"))
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok(loc)
)

let unionSpec* = blockSpec("union", unionHeaderSpec,
  atLeastOne(variantDefinitionLineSpec),
  proc(h: Location, b: seq[VariantDefinition]): Result[Union, ParserError] =
  newUnion(b, h))

# ============================================================
# DataBlock
# ============================================================

type
  DataBlockKind* = enum
    dbkLiteral, dbkStruct, dbkUnion
  DataBlock* = ref object
    case kind: DataBlockKind
    of dbkLiteral: literal: LiteralType
    of dbkStruct: struct: Struct
    of dbkUnion: union: Union

proc newDataBlock*(l: LiteralType): DataBlock =
  DataBlock(kind: dbkLiteral, literal: l)

proc newDataBlock*(s: Struct): DataBlock =
  DataBlock(kind: dbkStruct, struct: s)

proc newDataBlock*(u: Union): DataBlock =
  DataBlock(kind: dbkUnion, union: u)

proc kind*(db: DataBlock): DataBlockKind = db.kind
proc literal*(db: DataBlock): LiteralType =
  assert db.kind == dbkLiteral,
    fmt"DataBlock.literal accessed but kind is {db.kind}"
  db.literal
proc struct*(db: DataBlock): Struct =
  assert db.kind == dbkStruct,
    fmt"DataBlock.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataBlock): Union =
  assert db.kind == dbkUnion,
    fmt"DataBlock.union accessed but kind is {db.kind}"
  db.union

proc loc*(db: DataBlock): Location =
  case db.kind:
  of dbkLiteral: db.literal.loc
  of dbkStruct: db.struct.loc
  of dbkUnion: db.union.loc

proc asl(db: DataBlock, indentWidth: uint32): seq[string] =
  case db.kind:
  of dbkLiteral: asl(db.literal)
  of dbkStruct: asl(db.struct, indentWidth)
  of dbkUnion: asl(db.union, indentWidth)

let dataBlockSpec* = oneOf("data_block", [
  literalTypeSpec.map("literal_data",
    proc(v: LiteralType): DataBlock = newDataBlock(v)),
  structSpec.map("struct_data",
    proc(v: Struct): DataBlock = newDataBlock(v)),
  unionSpec.map("union_data",
    proc(v: Union): DataBlock = newDataBlock(v)),
])

# ============================================================
# UserFunction
# ============================================================

type UserFunction* = ref object
  decorators: seq[Decorator]
  def: FunctionDefinition
  statementList: StatementList

proc newUserFunction*(decorators: seq[Decorator], def: FunctionDefinition,
    statementList: StatementList): UserFunction =
  UserFunction(decorators: decorators, def: def, statementList: statementList)

proc loc*(fn: UserFunction): Location = fn.def.loc
proc name*(fn: UserFunction): Identifier = fn.def.name
proc def*(fn: UserFunction): FunctionDefinition = fn.def
proc statements*(fn: UserFunction): seq[Statement] = fn.statementList.statements
proc decorators*(fn: UserFunction): seq[Decorator] = fn.decorators
proc arity*(fn: UserFunction): int = fn.def.arity

proc asl(fn: UserFunction, indentWidth: uint32): seq[string] =
  for d in fn.decorators:
    result.add(asl(d))
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    for line in aslBlock(stmt, indentWidth):
      result.add(fmt"{indent}{line}")

let userFunctionSpec = decoratedBlockSpec("user_function", functionDefinitionSpec,
  statementListSpec,
  proc(d: seq[Decorator], h: FunctionDefinition, b: StatementList): UserFunction =
  newUserFunction(d, h, b))

# ============================================================
# ExternFunction
# ============================================================

type ExternFunction* = ref object
  ffi: string
  def: FunctionDefinition
  loc: Location

proc ffi*(fn: ExternFunction): string = fn.ffi
proc name*(fn: ExternFunction): Identifier = fn.def.name
proc def*(fn: ExternFunction): FunctionDefinition = fn.def
proc arity*(fn: ExternFunction): int = fn.def.arity
proc loc*(fn: ExternFunction): Location = fn.loc

proc newExternFunction*(ffi: string, def: FunctionDefinition,
    loc: Location): ExternFunction =
  ExternFunction(ffi: ffi, def: def, loc: loc)

proc asl(fn: ExternFunction, indentWidth: uint32): seq[string] =
  result.add(fmt"@extern(""{fn.ffi}"")")
  result.add(asl(fn.def))

# @extern("symbol")
# public func name(args): ReturnType
let externFunctionSpec = Spec[ExternFunction](
  name: "extern_function",
  parseFn: proc(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  discard ? parser.run(keywordSpec("extern"))
  discard parser.run(any(spaceSpec))
  let loc = parser.loc
  let symbol = ? parser.run(contained("extern_symbol", "(", stringLiteralSpec, ")"))
  discard ? parser.run(ignorableLineSpec)
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(functionDefinitionSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(newExternFunction(symbol.value, def, loc))
)

# ============================================================
# Function (user | extern)
# ============================================================

type
  FunctionKind* = enum
    fkUser, fkExtern
  Function* = ref object
    case kind: FunctionKind
    of fkUser: user: UserFunction
    of fkExtern: extern: ExternFunction

proc newFunction*(user: UserFunction): Function =
  Function(kind: fkUser, user: user)

proc newFunction*(extern: ExternFunction): Function =
  Function(kind: fkExtern, extern: extern)

proc kind*(fn: Function): FunctionKind = fn.kind

proc user*(fn: Function): UserFunction =
  assert fn.kind == fkUser,
    fmt"Function.user accessed but kind is {fn.kind}"
  fn.user

proc extern*(fn: Function): ExternFunction =
  assert fn.kind == fkExtern,
    fmt"Function.extern accessed but kind is {fn.kind}"
  fn.extern

proc loc*(fn: Function): Location =
  case fn.kind:
  of fkUser: fn.user.loc
  of fkExtern: fn.extern.loc

proc name*(fn: Function): Identifier =
  case fn.kind:
  of fkUser: fn.user.name
  of fkExtern: fn.extern.name

proc def*(fn: Function): FunctionDefinition =
  case fn.kind:
  of fkUser: fn.user.def
  of fkExtern: fn.extern.def

proc arity*(fn: Function): int =
  case fn.kind:
  of fkUser: fn.user.arity
  of fkExtern: fn.extern.arity

proc asl(fn: Function, indentWidth: uint32): seq[string] =
  case fn.kind:
  of fkUser: asl(fn.user, indentWidth)
  of fkExtern: asl(fn.extern, indentWidth)

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let funcBlockSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let f = parser.run(externFunctionSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.run(userFunctionSpec)
  ok(newFunction(u))
)

# ============================================================
# FunctionList
# ============================================================

type FunctionList* = ref object
  functions: seq[Function]
  functionIndex: Table[Identifier, Table[int, seq[int]]]

proc newFunctionList*(functions: seq[Function]): Result[FunctionList, ParserError] =
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  # TODO: ensure that there no duplicate function signatures
  for index, function in functions:
    if function.name notin functionIndex:
      functionIndex[function.name] = initTable[int, seq[int]]()
    if function.arity notin functionIndex[function.name]:
      functionIndex[function.name][function.arity] = newSeq[int]()
    functionIndex[function.name][function.arity].add(index)
  ok(FunctionList(functions: functions, functionIndex: functionIndex))

proc functions*(fnlist: FunctionList): seq[Function] = fnlist.functions
proc len*(fnlist: FunctionList): int = fnlist.functions.len

let functionListSpec = any(funcBlockSpec).map("function_list",
  proc(fns: seq[Function]): Result[FunctionList, ParserError] = newFunctionList(fns))

# ============================================================
# Generic
# ============================================================

type Generic* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  funcDefs: seq[FunctionDefinition]
  funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[string, seq[int]]
  loc: Location

proc public*(g: Generic): bool = g.public
proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDefinition] = g.funcDefs
proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc loc*(g: Generic): Location = g.loc
proc `==`*(a, b: Generic): bool = a.loc == b.loc

proc newGeneric*(decorators: seq[Decorator], public: bool, name: Identifier,
    funcDefs: seq[FunctionDefinition], loc: Location): Result[Generic, ParserError] =
  var funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  var funcDefIndex: Table[string, seq[int]]
  for index, def in funcDefs:
    if def.name notin funcDefArityIndex:
      funcDefArityIndex[def.name] = initTable[int, seq[int]]()
    if def.arity notin funcDefArityIndex[def.name]:
      funcDefArityIndex[def.name][def.arity] = newSeq[int]()
    funcDefArityIndex[def.name][def.arity].add(index)
    funcDefIndex.mgetOrPut(def.name.value, @[]).add(index)
  ok(Generic(decorators: decorators, public: public, name: name, funcDefs: funcDefs,
      funcDefArityIndex: funcDefArityIndex, funcDefIndex: funcDefIndex, loc: loc))

proc asl(gen: Generic, indentWidth: uint32): seq[string] =
  for d in gen.decorators:
    result.add(asl(d))
  let prefix = if gen.public: "public generic" else: "generic"
  result.add(fmt"{prefix} {asl(gen.name)}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

proc findFunctionDefIds(generic: Generic, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin generic.funcDefArityIndex:
    err(fmt"{name.loc} function `{name.asl}` does not exist in generic")
  elif arity notin generic.funcDefArityIndex[name]:
    err(fmt"{name.loc} function `{name.asl}` with arity `{arity}` does not exist in generic")
  else:
    ok(generic.funcDefArityIndex[name][arity])

proc findFunctionDefs*(generic: Generic, name: Identifier, arity: int): Result[seq[FunctionDefinition], string] =
  let funcIds = ? generic.findFunctionDefIds(name, arity)
  var funcs: seq[FunctionDefinition]
  for id in funcIds:
    funcs.add(generic.funcDefs[id])
  ok(funcs)

type GenericHeader = tuple[public: bool, name: Identifier, loc: Location]

let genericHeaderSpec = Spec[GenericHeader](
  name: "generic_header",
  parseFn: proc(parser: Parser): Result[GenericHeader, ParserError] =
  let maybePublic = parser.run(keywordSpec("public"))
  if maybePublic.isOk: discard ? parser.run(atLeastOne(spaceSpec))
  let public = maybePublic.isOk
  let loc = ? parser.run(keywordSpec("generic"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

let genericSpec = blockSpec("generic", genericHeaderSpec,
  functionDefinitionListSpec,
  proc(h: GenericHeader, b: seq[FunctionDefinition]): Result[Generic, ParserError] =
  newGeneric(@[], h.public, h.name, b, h.loc))

# ============================================================
# Requires
# ============================================================

type Requires* = ref object
  generics: seq[Identifier]
  loc: Location

proc generics*(r: Requires): seq[Identifier] = r.generics
proc loc*(r: Requires): Location = r.loc

proc newRequires*(generics: seq[Identifier], loc: Location): Requires =
  Requires(generics: generics, loc: loc)

proc asl(r: Requires): string =
  result = "requires("
  for i, g in r.generics:
    if i > 0: result.add(", ")
    result.add(asl(g))
  result.add(")")

# requires(Generic, Generic, ...)
let requiresSpec = Spec[Requires](
  name: "requires",
  parseFn: proc(parser: Parser): Result[Requires, ParserError] =
  discard ? parser.run(indentationSpec)
  let loc = ? parser.run(keywordSpec("requires"))
  discard parser.run(any(spaceSpec))
  let generics = ? parser.run(contained("requires_generics", "(",
    separatedBy(identifierSpec, commaWithSpacesSpec), ")"))
  discard ? parser.run(ignorableLineSpec)
  ok(newRequires(generics, loc))
)

# ============================================================
# Module
# ============================================================

type Module* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  requires: Option[Requires]
  data: Option[DataBlock]
  funcList: FunctionList
  functionIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc requires*(m: Module): Option[Requires] = m.requires
proc data*(m: Module): Option[DataBlock] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc

proc newModule*(decorators: seq[Decorator], public: bool, name: Identifier,
    requires: Option[Requires], data: Option[DataBlock],
    funcList: FunctionList, loc: Location): Result[Module, ParserError] =
  if data.isNone and funcList.len == 0:
    let msg = "module must have at least 1 struct/union/function block"
    return err(newParserError(msg, loc))
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  for i, fn in funcList.functions:
    if fn.name notin functionIndex:
      functionIndex[fn.name] = initTable[int, seq[int]]()
    if fn.arity notin functionIndex[fn.name]:
      functionIndex[fn.name][fn.arity] = newSeq[int]()
    functionIndex[fn.name][fn.arity].add(i)

  ok(Module(decorators: decorators, public: public, name: name,
      requires: requires, data: data, funcList: funcList,
      functionIndex: functionIndex, loc: loc))

proc asl(module: Module, indentWidth: uint32): seq[string] =
  for d in module.decorators:
    result.add(asl(d))
  let prefix = if module.public: "public module" else: "module"
  result.add(fmt"{prefix} {asl(module.name)}:")
  let indent = " ".repeat(indentWidth)
  if module.requires.isSome:
    result.add(fmt"{indent}{asl(module.requires.get)}")
    result.add("")
  if module.data.isSome:
    for line in asl(module.data.get, indentWidth):
      result.add(fmt"{indent}{line}")
    result.add("")
  for i, fn in module.funcList.functions:
    if i > 0: result.add("")
    for line in asl(fn, indentWidth):
      result.add(fmt"{indent}{line}")

proc findFunctionIds(module: Module, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    ok(module.functionIndex[name][arity])

proc findFunctions*(module: Module, name: Identifier, arity: int): Result[seq[Function], string] =
  let funcDefIds = ? module.findFunctionIds(name, arity)
  var funcDefs: seq[Function]
  for id in funcDefIds:
    funcDefs.add(module.functions[id])
  ok(funcDefs)

type ModuleHeader = tuple[public: bool, name: Identifier, loc: Location]

let moduleHeaderSpec = Spec[ModuleHeader](
  name: "module_header",
  parseFn: proc(parser: Parser): Result[ModuleHeader, ParserError] =
  let maybePublic = parser.run(keywordSpec("public"))
  if maybePublic.isOk: discard ? parser.run(atLeastOne(spaceSpec))
  let public = maybePublic.isOk

  let loc = ? parser.run(keywordSpec("module"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let nameIdent = ? parser.run(identifierSpec)
  discard parser.run(any(spaceSpec))
  discard ? parser.run(punctuationSpec(":"))
  ok((public, nameIdent, loc))
)

# Module body: optional requires + optional data block + function list
type ModuleBody = tuple[requires: Option[Requires], data: Option[DataBlock],
    funcList: FunctionList]

let moduleBodySpec = Spec[ModuleBody](
  name: "module_body",
  parseFn: proc(parser: Parser): Result[ModuleBody, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let requires = ? parser.run(optional(requiresSpec))
  discard parser.run(any(ignorableLineSpec))
  let data = ? parser.run(optional(dataBlockSpec))
  let funcList = ? parser.run(functionListSpec)
  ok((requires, data, funcList))
)

let moduleSpec = decoratedBlockSpec("module", moduleHeaderSpec, moduleBodySpec,
  proc(d: seq[Decorator], h: ModuleHeader, b: ModuleBody): Result[Module, ParserError] =
  newModule(d, h.public, h.name, b.requires, b.data, b.funcList, h.loc))

# ============================================================
# DefinedType
# ============================================================

type
  DefinedTypeKind* = enum
    dtkModule, dtkGeneric
  DefinedType* = ref object
    case kind: DefinedTypeKind
    of dtkModule: module: Module
    of dtkGeneric: generic: Generic

proc newDefinedType*(module: Module): DefinedType =
  DefinedType(kind: dtkModule, module: module)

proc newDefinedType*(generic: Generic): DefinedType =
  DefinedType(kind: dtkGeneric, generic: generic)

proc kind*(dt: DefinedType): DefinedTypeKind = dt.kind
proc public*(dt: DefinedType): bool =
  case dt.kind:
  of dtkModule: dt.module.public
  of dtkGeneric: dt.generic.public

proc module*(dt: DefinedType): Module =
  assert dt.kind == dtkModule,
    fmt"DefinedType.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: DefinedType): Generic =
  assert dt.kind == dtkGeneric,
    fmt"DefinedType.generic accessed but kind is {dt.kind}"
  dt.generic

proc name*(definedType: DefinedType): Identifier =
  case definedType.kind:
  of dtkModule: definedType.module.name
  of dtkGeneric: definedType.generic.name

proc loc*(definedType: DefinedType): Location =
  case definedType.kind:
  of dtkModule: definedType.module.loc
  of dtkGeneric: definedType.generic.loc

let typeSpec = oneOf("type_block", [
  moduleSpec.map("module_item",
    proc(v: Module): DefinedType = newDefinedType(v)),
  genericSpec.map("generic_item",
    proc(v: Generic): DefinedType = newDefinedType(v)),
])

let definedTypeBlockSpec = Spec[DefinedType](
  name: "type_block_block",
  parseFn: proc(parser: Parser): Result[DefinedType, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let item = ? parser.run(typeSpec)
  ok(item)
)

# ============================================================
# Type (umbrella over imported and defined types)
# ============================================================

type
  TypeKind* = enum
    tkImported, tkDefined
  Type* = ref object
    case kind: TypeKind
    of tkImported: imported: ImportedType
    of tkDefined: definedType: DefinedType

proc newType(imported: ImportedType): Type =
  Type(kind: tkImported, imported: imported)

proc newType(definedType: DefinedType): Type =
  Type(kind: tkDefined, definedType: definedType)

proc kind*(typ: Type): TypeKind = typ.kind

proc imported*(typ: Type): ImportedType =
  assert typ.kind == tkImported,
    fmt"Type.imported accessed but kind is {typ.kind}"
  typ.imported

proc definedType*(typ: Type): DefinedType =
  assert typ.kind == tkDefined,
    fmt"Type.definedType accessed but kind is {typ.kind}"
  typ.definedType

proc loc*(typ: Type): Location =
  case typ.kind:
  of tkImported: typ.imported.loc
  of tkDefined: typ.definedType.loc

# ============================================================
# File
# ============================================================

type File* = ref object
  path: string
  imports: seq[Import]
  definedTypes: seq[DefinedType]
  types: seq[Type]
  typeIndex: Table[Identifier, int]

proc newFile*(path: string, imports: seq[Import], definedTypes: seq[DefinedType]): Result[
    File, ParserError] =
  # TODO: Ensure that same file is not used in multiple import statements
  # var importedFileSet: Hashset[string]
  # for imp in imports:
  #   if imp.path in importedFileSet:
  #     return err(newParserError("", imp.loc))
  #   importedFileSet.incl(imp.path)

  var typeIndex: Table[Identifier, int]
  var types: seq[Type]

  for imp in imports:
    if imp.path == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
    for impType in imp.names:
      if impType.binding in typeIndex:
        let prev = types[typeIndex[impType.binding]]
        let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
        return err(newParserError(msg, impType.loc))
      typeIndex[impType.binding] = types.len
      types.add(newType(impType))

  for definedType in definedTypes:
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    else:
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(path: path, imports: imports, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc definedTypes*(file: File): seq[DefinedType] = file.definedTypes
proc types*(file: File): seq[Type] = file.types

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and file.definedTypes.len > 0:
    lines.add("")
  for i, dt in file.definedTypes:
    if i > 0: lines.add("")
    case dt.kind:
    of dtkModule:
      for line in asl(dt.module, indentWidth):
        lines.add(line)
    of dtkGeneric:
      for line in asl(dt.generic, indentWidth):
        lines.add(line)
  lines.join("\n") & "\n"

proc findType*(file: File, name: Identifier): Result[Type, string] =
  if name in file.typeIndex: ok(file.types[file.typeIndex[name]])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findExportedType*(file: File, name: Identifier): Result[DefinedType, string] =
  let aslType = ? file.findType(name)
  case aslType.kind:
  of tkImported: err(fmt"{name.loc} type `{name.asl}` is not defined in file `{file.path}`")
  of tkDefined:
    let definedType = aslType.definedType
    if definedType.public: ok(definedType)
    else: err(fmt"{name.loc} type `{name.asl}` is defined but is non-public")

# file: import* (module | generic)*
let fileSpec = Spec[File](
  name: "file",
  parseFn: proc(parser: Parser): Result[File, ParserError] =
  let imports = ? parser.run(any(importBlockSpec))
  let items = ? parser.run(atLeastOne(definedTypeBlockSpec))
  discard parser.run(any(ignorableLineSpec))
  if not parser.done():
    # Force a parse attempt to get a specific error message
    discard ? parser.run(typeSpec)
  newFile(parser.filepath, imports, items)
)

proc parse*(filepath: string, indentWidth: uint32, tokens: seq[Token]): Result[
    File, string] =
  let parser = newParser(filepath, indentWidth, tokens)
  let maybeFile = parser.run(fileSpec)
  if maybeFile.isErr:
    err(fmt"{filepath}:{maybeFile.error}")
  else:
    ok(maybeFile.get)

# ============================================================
# App
# ============================================================

type App* = ref object
  files: seq[File]
  fileIndex: Table[string, int] # absolute path -> index in files

proc newApp*(files: seq[File]): App =
  var fileIndex: Table[string, int]
  for i, f in files:
    fileIndex[f.path] = i
  App(files: files, fileIndex: fileIndex)

proc files*(app: App): seq[File] = app.files

proc findFileId*(app: App, path: string): Result[int, string] =
  if path in app.fileIndex: ok(app.fileIndex[path])
  else: err(fmt"file '{path}' does not exists")

proc findFile*(app: App, path: string): Result[File, string] =
  let id = ? app.findFileId(path)
  ok(app.files[id])
