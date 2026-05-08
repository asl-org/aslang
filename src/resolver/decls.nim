## Declaration-level resolution: user / extern functions, struct /
## variant / union / data blocks, modules, generics, defined types,
## files, and the App entry point.

import results, options, sets, strformat, tables

import parser
import literals
import imports
import argtypes
import funcdefs
import funcrefs
import body

# ResolvedUserFunction
type ResolvedUserFunction* = ref object
  funcDef: ResolvedFunctionDefinition
  statements: seq[ResolvedStatement]

proc newResolvedUserFunction*(funcDef: ResolvedFunctionDefinition,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(funcDef: funcDef, statements: statements)

proc resolveUserFunction(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file,
    fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDefinition.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(resolvedFunctionDefinition, resolvedStatements))

# ResolvedFunction
type
  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc resolveFunction(app: App, file: parser.File, fileScope: FileScope,
    module: Module, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

# ResolvedStruct
type ResolvedStruct* = ref object
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedStruct*(
    fields: seq[ResolvedArgumentDefinition]): ResolvedStruct =
  ResolvedStruct(fields: fields)

proc resolveStruct(app: App, file: parser.File, fileScope: FileScope,
    module: Module, struct: Struct): Result[ResolvedStruct, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module,
      field)
    resolvedFields.add(resolvedField)
  ok(newResolvedStruct(resolvedFields))

# ResolvedVariant
type ResolvedVariant* = ref object
  name: Identifier
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedVariant*(name: Identifier,
    fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  ResolvedVariant(name: name, fields: fields)

proc resolveVariant(app: App, file: parser.File, fileScope: FileScope,
    module: Module,
    variant: VariantDefinition): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module,
      field)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant.name, resolvedFields))

# ResolvedUnion
type ResolvedUnion* = ref object
  variants: seq[ResolvedVariant]

proc newResolvedUnion*(variants: seq[ResolvedVariant]): ResolvedUnion =
  ResolvedUnion(variants: variants)

proc resolveUnion(app: App, file: parser.File, fileScope: FileScope,
    module: Module, union: Union): Result[ResolvedUnion, string] =
  var resolvedVariants: seq[ResolvedVariant]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnion(resolvedVariants))

# ResolvedData
type
  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralType
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

proc newResolvedData*(literal: ResolvedLiteralType): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData*(struct: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc newResolvedData*(union: ResolvedUnion): ResolvedData =
  ResolvedData(kind: rdkUnion, union: union)

proc resolveDataBlock(app: App, file: parser.File, fileScope: FileScope,
    module: Module, data: DataBlock): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralType(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStruct(app, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion:
    let resolvedUnion = ? resolveUnion(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))

# ResolvedModule
type ResolvedModule* = ref object
  requires: seq[Generic]
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]

proc newResolvedModule*(requires: seq[Generic],
    data: Option[ResolvedData],
    functions: seq[ResolvedFunction]): ResolvedModule =
  ResolvedModule(requires: requires, data: data, functions: functions)

proc resolveModule(app: App, file: parser.File, fileScope: FileScope,
    module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  var resolvedRequires: seq[Generic]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let dataType = ? file.findType(generic)
      case dataType.kind:
      of tkImported:
        return err("todo: resolve imported type in requires block")
      of tkDefined:
        let definedType = dataType.definedType
        case definedType.kind:
        of dtkModule:
          return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
        of dtkGeneric:
          resolvedRequires.add(definedType.generic)

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataBlock = ? resolveDataBlock(app, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataBlock)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module,
      function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(resolvedRequires, resolvedData, resolvedFunctions))

# ResolvedGeneric
type ResolvedGeneric* = ref object
  public: bool
  name: Identifier
  funcDefs: seq[ResolvedFunctionDefinition]

proc newResolvedGeneric*(public: bool, name: Identifier,
    funcDefs: seq[ResolvedFunctionDefinition]): ResolvedGeneric =
  ResolvedGeneric(public: public, name: name, funcDefs: funcDefs)

proc resolveGeneric(app: App, file: parser.File,
    generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file,
      generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic.public, generic.name, resolvedFunctionDefs))

# ResolvedDefinedType
type
  ResolvedDefinedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType* = ref object
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType*(module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkModule, module: module)

proc newResolvedDefinedType*(generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkGeneric, generic: generic)

proc resolveDefinedType(app: App, file: parser.File, fileScope: FileScope,
    definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, definedType.generic)
    ok(newResolvedDefinedType(resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope,
      definedType.module)
    ok(newResolvedDefinedType(resolvedModule))

# ResolvedFile
type ResolvedFile* = ref object
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedDefinedType]

proc newResolvedFile*(imports: seq[ResolvedImport],
    definedTypes: seq[ResolvedDefinedType]): ResolvedFile =
  ResolvedFile(imports: imports, definedTypes: definedTypes)

proc resolveFile(app: App, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var resolvedDefinedTypes: seq[ResolvedDefinedType]
  for definedType in file.definedTypes:
    let resolvedDefinedType = ? resolveDefinedType(app, file, fileScope,
      definedType)
    resolvedDefinedTypes.add(resolvedDefinedType)

  ok(newResolvedFile(resolvedImports, resolvedDefinedTypes))

# ResolvedApp + entry
type ResolvedApp* = ref object
  files: seq[ResolvedFile]

proc newResolvedApp*(files: seq[ResolvedFile]): ResolvedApp =
  ResolvedApp(files: files)

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let maybeResolvedFile = resolveFile(app, file)
    if maybeResolvedFile.isErr:
      return err(fmt"{file.path}:{maybeResolvedFile.error}")
    else:
      resolvedFiles.add(maybeResolvedFile.get)
  ok(newResolvedApp(resolvedFiles))
