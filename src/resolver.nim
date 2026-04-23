import results, options, strformat

import parser

type File = parser.File

type ResolvedLiteralType = enum
  rltkU8, rltkU16, rltkU32, rltkU64
  rltkI8, rltkI16, rltkI32, rltkI64
  rltkF32, rltkF64, rltkString, rltkPointer

proc resolveLiteralType(file: File, literal: LiteralType): Result[ResolvedLiteralType, string] =
  case literal.content:
  of "u8": ok(rltkU8)
  of "u16": ok(rltkU16)
  of "u32": ok(rltkU32)
  of "u64": ok(rltkU64)
  of "i8": ok(rltkI8)
  of "i16": ok(rltkI16)
  of "i32": ok(rltkI32)
  of "i64": ok(rltkI64)
  of "f32": ok(rltkF32)
  of "f64": ok(rltkF64)
  of "string": ok(rltkString)
  of "pointer": ok(rltkPointer)
  else: err(fmt"{file.path}:{literal.loc} unsupported literal type encountered `{literal.content}`")

proc resolveImport(app: App, file: File, imp: Import): Result[void, string] =
  err("todo: resolve import")

type
  ResolvedModuleArgumentType = ref object
    root: Module
    impls: seq[ResolvedArgumentType]
  ResolvedDefinedArgumentTypeKind = enum
    rdatkModule, rdatkGeneric
  ResolvedDefinedArgumentType = ref object
    case kind: ResolvedDefinedArgumentTypeKind
    of rdatkModule: module: ResolvedModuleArgumentType
    of rdatkGeneric: generic: Generic
  ResolvedArgumentTypeKind = enum
    ratkImported, ratkDefined
  ResolvedArgumentType = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkImported: discard
    of ratkDefined: definedType: ResolvedDefinedArgumentType

proc newResolvedModuleArgumentType(root: Module, impls: seq[ResolvedArgumentType]): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(root: root, impls: impls)

proc newResolvedModuleArgumentType(root: Module): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(root, @[])

proc newResolvedDefinedArgumentType(module: ResolvedModuleArgumentType): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkModule, module: module)

proc newResolvedDefinedArgumentType(generic: Generic): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkGeneric, generic: generic)

proc newResolvedArgumentType(definedType: ResolvedDefinedArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkDefined, definedType: definedType)

proc resolveArgumentType(app: App, file: File, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveModuleType(app: App, file: File, module: Module, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkStruct:
      return err(fmt"{file.path}:{dataBlock.loc} todo: resolve struct block in argument type")
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root))
      else:
        return err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkUnion:
      var requires: seq[Generic]
      let union = dataBlock.union
      for variant in union.variants:
        for field in variant.fields:
          let fieldType = ? file.findType(field.argType.root)
          case fieldType.kind:
          of tkImported: return err("todo: resolve imported type field in union variant")
          of tkDefined:
            let definedFieldType = fieldType.definedType
            case definedFieldType.kind:
            of dtkModule: discard
            of dtkGeneric: requires.add(definedFieldType.generic)

      if argType.impls.len != requires.len:
        return err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, module, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root))
  else:
    err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveModuleType(app: App, file: File, generic: Generic, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkStruct:
      return err(fmt"{file.path}:{dataBlock.loc} todo: resolve struct block in argument type")
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root))
      else:
        return err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkUnion:
      var requires: seq[Generic]
      let union = dataBlock.union
      for variant in union.variants:
        for field in variant.fields:
          let fieldType = ? file.findType(field.argType.root)
          case fieldType.kind:
          of tkImported: return err("todo: resolve imported type field in union variant")
          of tkDefined:
            let definedFieldType = fieldType.definedType
            case definedFieldType.kind:
            of dtkModule: discard
            of dtkGeneric: requires.add(definedFieldType.generic)

      if argType.impls.len != requires.len:
        return err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, generic, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root))
  else:
    err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveDefinedArgumentType(app: App, file: File, module: Module, argType: ArgumentType, definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric: err("todo: resolve generic type")
  of dtkModule:
    let resolvedModuleType = ? resolveModuleType(app, file, module, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

proc resolveDefinedArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType, definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric:
    if definedType.generic == generic:
      ok(newResolvedDefinedArgumentType(definedType.generic))
    else:
      err(fmt"{file.path}:{definedType.loc} type `{definedType.name.asl}` is a generic and can not be used within the generic block")
  of dtkModule:
    let resolvedModuleType = ? resolveModuleType(app, file, generic, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

proc resolveArgumentType(app: App, file: File, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let rootType = ? file.findType(argType.root)
  case rootType.kind:
  of tkImported: err("todo: resolve imported type")
  of tkDefined:
    let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, module, argType, rootType.definedType)
    ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let rootType = ? file.findType(argType.root)
  case rootType.kind:
  of tkImported: err("todo: resolve imported type")
  of tkDefined:
    let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, generic, argType, rootType.definedType)
    ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveDataType(app: App, file: File, module: Module, arg: ArgumentType, resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkImported: err("todo: resolve imported type argument definition")
  of ratkDefined:
    let resolvedDefinedType = resolvedArgumentType.definedType
    case resolvedDefinedType.kind:
    of rdatkGeneric:
      err(fmt"{file.path}:{arg.loc} todo: resolve defined generic type argument definition")
    of rdatkModule:
      let resolvedDefinedModuleType = resolvedDefinedType.module
      if resolvedDefinedModuleType.root.data.isSome:
        ok()
      else:
        err(fmt"{file.path}:{arg.loc} module `{resolvedDefinedModuleType.root.name.asl}` is not a literal/struct/union")

proc resolveDataType(app: App, file: File, generic: Generic, arg: ArgumentType, resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkImported: err("todo: resolve imported type argument definition")
  of ratkDefined:
    let resolvedDefinedType = resolvedArgumentType.definedType
    case resolvedDefinedType.kind:
    of rdatkGeneric:
      ok()
    of rdatkModule:
      let resolvedDefinedModuleType = resolvedDefinedType.module
      if resolvedDefinedModuleType.root.data.isSome:
        ok()
      else:
        err(fmt"{file.path}:{arg.loc} module `{resolvedDefinedModuleType.root.name.asl}` is not a literal/struct/union")

type ResolvedArgumentDefinition = ref object
  argType: ResolvedArgumentType
  name: Identifier

proc newResolvedArgumentDefinition(argType: ResolvedArgumentType, name: Identifier): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, argType: argType)

proc resolveArgumentDefinition(app: App, file: File, module: Module, arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, module, arg.argType)
  ? resolveDataType(app, file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

proc resolveArgumentDefinition(app: App, file: File, generic: Generic, arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, generic, arg.argType)
  ? resolveDataType(app, file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

type ResolvedFunctionDefinition = ref object
  public: bool
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition(public: bool, name: Identifier, args: seq[ResolvedArgumentDefinition], returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(public: public, name: name, args: args, returns: returns)

proc resolveFunctionDefinition(app: App, file: File, module: Module, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, module, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, module, def.returns)
  ? resolveDataType(app, file, module,  def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs, resolvedReturnArgType))

proc resolveFunctionDefinition(app: App, file: File, generic: Generic, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, generic, def.returns)
  ? resolveDataType(app, file, generic,  def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs, resolvedReturnArgType))

type ResolvedExternFunction = ref object
  ffi: string
  def: ResolvedFunctionDefinition

proc newResolvedExternFunction(ffi: string, def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(ffi: ffi, def: def)

proc resolveExternFunction(app: App, file: File, module: Module, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDefinition(app, file, module, function.def)
  ok(newResolvedExternFunction(function.ffi, resolvedFunctionDef))

type
  ResolvedFunctionKind = enum
    rfkExtern, rfkUser
  ResolvedFunction = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: discard

proc newResolvedFunction(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc resolveFunction(app: App, file: File, module: Module, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser: err("todo: resolve user function")
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

type ResolvedStruct = ref object

proc resolveStruct(app: App, file: File, module: Module, struct: Struct): Result[ResolvedStruct, string] =
  err("todo: resolve struct block")

type
  ResolvedDataKind = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralType
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: discard

proc newResolvedData(literal: ResolvedLiteralType): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData(struct: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc resolveDataBlock(app: App, file: File, module: Module, data: DataBlock): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralType(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStruct(app, file, module, data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion: err("todo: resolve union block")

type ResolvedModule = ref object
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]

proc newResolvedModule(data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ResolvedModule(data: data, functions: functions)

proc resolveModule(app: App, file: File, module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  if module.requires.isSome:
    return err("todo: resolve requires block")

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataBlock = ? resolveDataBlock(app, file, module, module.data.get)
    resolvedData = some(resolvedDataBlock)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, module, function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(resolvedData, resolvedFunctions))

type ResolvedGeneric = ref object
  public: bool
  name: Identifier
  funcDefs: seq[ResolvedFunctionDefinition]

proc newResolvedGeneric(public: bool, name: Identifier, funcDefs: seq[ResolvedFunctionDefinition]): ResolvedGeneric =
  ResolvedGeneric(public: public, name: name, funcDefs: funcDefs)

proc resolveGeneric(app: App, file: File, generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{file.path}:{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file, generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic.public, generic.name, resolvedFunctionDefs))

type
  ResolvedDefinedTypeKind = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType = ref object
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType(module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkModule, module: module)

proc newResolvedDefinedType(generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkGeneric, generic: generic)

proc resolveDefinedType(app: App, file: File, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, definedType.generic)
    ok(newResolvedDefinedType(resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, definedType.module)
    ok(newResolvedDefinedType(resolvedModule))

proc resolveFile(app: App, file: File): Result[void, string] =
  for imp in file.imports:
    ? resolveImport(app, file, imp)

  for definedType in file.definedTypes:
    discard ? resolveDefinedType(app, file, definedType)

  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for file in app.files:
    ? resolveFile(app, file)

  err("todo: resolve app")
