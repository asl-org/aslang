import results, options, strformat

import parser

type File = parser.File

type ResolvedLiteralType = enum
  rltkU8, rltkU16, rltkU32, rltkU64
  rltkI8, rltkI16, rltkI32, rltkI64
  rltkF32, rltkF64, rltkString

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
  else: err(fmt"{file.path}:{literal.loc} unsupported literal type encountered `{literal.content}`")

proc resolveImport(app: App, file: File, imp: Import): Result[void, string] =
  err("todo: resolve import")

type
  ResolvedModuleType = ref object
    root: Module
    impls: seq[ResolvedModuleType]

proc newResolvedModuleType(root: Module, impls: seq[ResolvedModuleType]): ResolvedModuleType =
  ResolvedModuleType(root: root, impls: impls)

proc newResolvedModuleType(root: Module): ResolvedModuleType =
  newResolvedModuleType(root, @[])

proc resolveModuleType(app: App, file: File, module: Module, argType: ArgumentType, definedType: DefinedType, root: Module): Result[ResolvedModuleType, string] =
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleType(root))
      else:
        return err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkStruct: discard
    of dbkUnion: discard

    return err(fmt"{file.path}:{dataBlock.loc} todo: resolve data block in argument type")

  if argType.impls.len == 0:
    ok(newResolvedModuleType(root))
  else:
    err(fmt"{file.path}:{argType.loc} type `{root.name.asl}` does not require impl types")

type
  ResolvedDefinedTypeKind = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType = ref object
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModuleType
    of rdtkGeneric: discard

proc newResolvedDefinedType(module: ResolvedModuleType): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkModule, module: module)

proc resolveDefinedType(app: App, file: File, module: Module, argType: ArgumentType, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric: err("todo: resolve generic type")
  of dtkModule:
    let resolvedModuleType = ? resolveModuleType(app, file, module, argType, definedType, definedType.module)
    ok(newResolvedDefinedType(resolvedModuleType))

type
  ResolvedArgumentTypeKind = enum
    ratkImported, ratkDefined
  ResolvedArgumentType = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkImported: discard
    of ratkDefined: definedType: ResolvedDefinedType

proc newResolvedArgumentType(definedType: ResolvedDefinedType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkDefined, definedType: definedType)

proc resolveArgumentType(app: App, file: File, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let rootType = ? file.findType(argType.root)
  case rootType.kind:
  of tkImported: err("todo: resolve imported type")
  of tkDefined:
    let resolvedDefinedType = ? resolveDefinedType(app, file, module, argType, rootType.definedType)
    ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveArgumentDefinition(app: App, file: File, module: Module, arg: ArgumentDefinition): Result[void, string] =
  discard ? resolveArgumentType(app, file, module, arg.argType)
  ok()

proc resolveFunctionDefinition(app: App, file: File, module: Module, def: FunctionDefinition): Result[void, string] =
  for arg in def.args:
    ? resolveArgumentDefinition(app, file, module, arg)

  discard ? resolveArgumentType(app, file, module, def.returns)

  err("todo: resolve function definition")

proc resolveExternFunction(app: App, file: File, module: Module, function: ExternFunction): Result[void, string] =
  resolveFunctionDefinition(app, file, module, function.def)

proc resolveFunction(app: App, file: File, module: Module, function: Function): Result[void, string] =
  case function.kind:
  of fkExtern: resolveExternFunction(app, file, module, function.extern)
  of fkUser: err("todo: resolve user function")

proc resolveDataBlock(app: App, file: File, module: Module, data: DataBlock): Result[void, string] =
  case data.kind:
  of dbkLiteral:
    discard ? resolveLiteralType(file, data.literal)
    ok()
  of dbkStruct: err("todo: resolve struct block")
  of dbkUnion: err("todo: resolve union block")

proc resolveModule(app: App, file: File, module: Module): Result[void, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  if module.requires.isSome:
    return err("todo: resolve requires block")

  if module.data.isSome:
    ? resolveDataBlock(app, file, module, module.data.get)

  for function in module.functions:
    ? resolveFunction(app, file, module, function)

  err("todo: resolve module")

proc resolveDefinedType(app: App, file: File, definedType: DefinedType): Result[void, string] =
  case definedType.kind:
  of dtkGeneric: err("todo: resolve generic")
  of dtkModule: resolveModule(app, file, definedType.module)

proc resolveFile(app: App, file: File): Result[void, string] =
  for imp in file.imports:
    ? resolveImport(app, file, imp)

  for definedType in file.definedTypes:
    ? resolveDefinedType(app, file, definedType)

  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for file in app.files:
    ? resolveFile(app, file)

  err("todo: resolve app")
